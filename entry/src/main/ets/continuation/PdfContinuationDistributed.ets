import { common, Want } from '@kit.AbilityKit';
import { commonType, distributedDataObject } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import {
  CONTINUE_WANT_FILE_NAME,
  CONTINUE_WANT_FILE_REF,
  CONTINUE_WANT_PAGE_INDEX,
  logContinuationError,
  logContinuationLine,
  logContinuationWarn,
  ROUTER_INITIAL_PAGE_INDEX
} from './PdfContinuation';
import { buildLaunchParamsFromLocalPath } from './PdfContinuationRestore';

/**
 * 分布式数据对象组网 id（勿用系统保留键 sessionId，见 bpta-continue-data.md）。
 */
export const CONTINUE_WANT_DATA_SESSION_ID: string = 'justpdf_dataSessionId';

/** 源端/对端分布式对象根属性（文件资产 + 页码） */
class PdfContinuationMigrateSource {
  pageIndex: number | undefined = undefined;
  fileName: string | undefined = undefined;
  pdfAttachment: commonType.Asset | undefined = undefined;

  constructor(
    pageIndex: number | undefined,
    fileName: string | undefined,
    pdfAttachment: commonType.Asset | undefined
  ) {
    this.pageIndex = pageIndex;
    this.fileName = fileName;
    this.pdfAttachment = pdfAttachment;
  }
}

function buildAssetFromDistributedPath(filePath: string, fileName: string): commonType.Asset {
  try {
    const stat = fs.statSync(filePath);
    const uri = fileUri.getUriFromPath(filePath);
    return {
      name: fileName,
      uri: uri,
      path: filePath,
      createTime: stat.ctime.toString(),
      modifyTime: stat.mtime.toString(),
      size: stat.size.toString()
    };
  } catch (error) {
    throw new Error(`buildAssetFromDistributedPath 失败: ${error}`);
  }
}

/**
 * 按 HarmonyOS 文件资产迁移：distributedDataObject + Asset + save(targetDevice)。
 * 见 bpta-continue-data.md「文件资产迁移」、bpta-content-creation.md「应用接续的实现」。
 */
export class PdfContinuationDistributedRestore {
  /** 对端须为成员变量，避免 on() 异步回调时对象被回收 */
  private dataObject?: distributedDataObject.DataObject;
  private restoreFinished: boolean = false;
  private restoredParams: Record<string, string> | null = null;
  private restoreWaiters: Array<(result: Record<string, string> | null) => void> = [];

  resetRestoreState(): void {
    this.restoreFinished = false;
    this.restoredParams = null;
    this.restoreWaiters = [];
  }

  async savePdfForContinuation(
    context: common.UIAbilityContext,
    wantParam: Record<string, Object>,
    sandboxPath: string,
    fileName: string,
    pageIndex: number
  ): Promise<boolean> {
    const safeName = fileName.length > 0 ? fileName : 'continued.pdf';
    const distPath = `${context.distributedFilesDir}/${safeName}`;
    logContinuationLine(`savePdfForContinuation 复制到分布式目录: ${distPath}`);
    try {
      fs.accessSync(sandboxPath);
      fs.copyFileSync(sandboxPath, distPath);
      const stat = fs.statSync(distPath);
      logContinuationLine(`savePdfForContinuation 分布式文件 size=${stat.size}`);
    } catch (error) {
      logContinuationError(`savePdfForContinuation 复制失败: ${error}`);
      return false;
    }

    let attachment: commonType.Asset;
    try {
      attachment = buildAssetFromDistributedPath(distPath, safeName);
    } catch (error) {
      logContinuationError(`savePdfForContinuation 创建 Asset 失败: ${error}`);
      return false;
    }

    const source = new PdfContinuationMigrateSource(pageIndex, safeName, attachment);
    this.dataObject = distributedDataObject.create(context, source);
    const dataSessionId: string = distributedDataObject.genSessionId();
    try {
      await this.dataObject.setSessionId(dataSessionId);
    } catch (error) {
      logContinuationError(`savePdfForContinuation setSessionId 失败: ${error}`);
      return false;
    }

    const targetDevice = wantParam['targetDevice'];
    if (targetDevice === undefined || targetDevice === null || String(targetDevice).length === 0) {
      logContinuationError('savePdfForContinuation 缺少 wantParam.targetDevice');
      return false;
    }

    try {
      await this.dataObject.save(String(targetDevice));
      logContinuationLine(`savePdfForContinuation save() 成功 dataSessionId=${dataSessionId}`);
    } catch (error) {
      const err = error as BusinessError;
      logContinuationError(`savePdfForContinuation save() 失败: code=${err.code}, ${err.message}`);
      return false;
    }

    wantParam[CONTINUE_WANT_DATA_SESSION_ID] = dataSessionId;
    wantParam[CONTINUE_WANT_FILE_REF] = fileUri.getUriFromPath(distPath);
    wantParam[CONTINUE_WANT_PAGE_INDEX] = pageIndex;
    wantParam[CONTINUE_WANT_FILE_NAME] = safeName;
    return true;
  }

  /**
   * 对端：在 onCreate/onNewWant(CONTINUATION) 尽早调用；在 setSessionId 之前注册 on('status')。
   */
  startRestore(context: common.UIAbilityContext, want: Want): void {
    this.resetRestoreState();
    const emptySource = new PdfContinuationMigrateSource(undefined, undefined, undefined);
    this.dataObject = distributedDataObject.create(context, emptySource);

    try {
      this.dataObject.on(
        'status',
        (sessionId: string, networkId: string, status: 'online' | 'offline' | 'restored') => {
          logContinuationLine(`分布式对象 status=${status} sessionId=${sessionId} networkId=${networkId}`);
          if (status === 'restored') {
            void this.handleRestored(context);
          }
        }
      );
    } catch (error) {
      logContinuationError(`startRestore 注册 status 监听失败: ${error}`);
      this.completeRestore(null);
      return;
    }

    let dataSessionId = '';
    const params = want.parameters;
    if (params !== undefined) {
      const raw = params[CONTINUE_WANT_DATA_SESSION_ID];
      if (raw !== undefined && raw !== null) {
        dataSessionId = String(raw);
      }
    }
    if (dataSessionId.length === 0) {
      logContinuationWarn('startRestore 无 justpdf_dataSessionId，将仅尝试目录轮询');
      this.completeRestore(null);
      return;
    }

    logContinuationLine(`startRestore 加入组网 dataSessionId=${dataSessionId}`);
    this.dataObject.setSessionId(dataSessionId).catch((error: BusinessError) => {
      logContinuationError(`startRestore setSessionId 失败: code=${error.code}, ${error.message}`);
      this.completeRestore(null);
    });
  }

  private async handleRestored(context: common.UIAbilityContext): Promise<void> {
    if (this.restoreFinished || this.dataObject === undefined) {
      return;
    }
    const restoredFields = this.dataObject as object as PdfContinuationMigrateSource;
    const attachment: commonType.Asset | undefined = restoredFields.pdfAttachment;
    if (attachment === undefined || attachment.name === undefined || attachment.name.length === 0) {
      logContinuationError('handleRestored 缺少 pdfAttachment');
      this.completeRestore(null);
      return;
    }

    const fileName = attachment.name;
    const localPath = `${context.distributedFilesDir}/${fileName}`;
    logContinuationLine(`handleRestored 从分布式目录读取: ${localPath}`);
    try {
      fs.accessSync(localPath);
      const stat = fs.statSync(localPath);
      if (stat.size <= 0) {
        logContinuationError('handleRestored 文件大小为 0');
        this.completeRestore(null);
        return;
      }
    } catch (error) {
      logContinuationError(`handleRestored 分布式 PDF 不可读: ${error}`);
      this.completeRestore(null);
      return;
    }

    const restoredSource = this.dataObject as object as PdfContinuationMigrateSource;
    let pageIndex = 0;
    if (restoredSource.pageIndex !== undefined) {
      pageIndex = Math.max(0, Math.floor(restoredSource.pageIndex));
    }

    const fileRef = attachment.uri.length > 0 ? attachment.uri : fileUri.getUriFromPath(localPath);
    try {
      const params = await buildLaunchParamsFromLocalPath(context, localPath, fileRef, fileName);
      params[ROUTER_INITIAL_PAGE_INDEX] = String(pageIndex);
      logContinuationLine(
        `handleRestored 成功 sandbox=${params['sandboxPath']}, pageIndex=${pageIndex}`
      );
      this.completeRestore(params);
    } catch (error) {
      logContinuationError(`handleRestored 复制到沙箱失败: ${error}`);
      this.completeRestore(null);
    }
  }

  waitForRestoredLaunchParams(timeoutMs: number): Promise<Record<string, string> | null> {
    if (this.restoreFinished) {
      return Promise.resolve(this.restoredParams);
    }
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        logContinuationWarn(`waitForRestoredLaunchParams 超时 ${timeoutMs}ms`);
        this.completeRestore(null);
        resolve(this.restoredParams);
      }, timeoutMs);
      this.restoreWaiters.push((result: Record<string, string> | null) => {
        clearTimeout(timer);
        resolve(result);
      });
    });
  }

  private completeRestore(params: Record<string, string> | null): void {
    if (this.restoreFinished) {
      return;
    }
    this.restoreFinished = true;
    this.restoredParams = params;
    const waiters = this.restoreWaiters.splice(0);
    for (let i = 0; i < waiters.length; i++) {
      waiters[i](params);
    }
  }
}

export const pdfContinuationDistributed: PdfContinuationDistributedRestore =
  new PdfContinuationDistributedRestore();
