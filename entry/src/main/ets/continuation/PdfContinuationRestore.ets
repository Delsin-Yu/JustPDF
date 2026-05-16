import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import {
  logContinuationError,
  logContinuationLine,
  logContinuationWarn,
  PdfContinuationPayload,
  ROUTER_INITIAL_PAGE_INDEX
} from './PdfContinuation';
import { pdfContinuationDistributed } from './PdfContinuationDistributed';

/** 路由参数：由 PDFView 在页面内完成分布式文件落地 */
export const ROUTER_CONTINUATION_PENDING: string = 'continuationPending';

const POLL_INTERVAL_MS: number = 100;
const POLL_MAX_ATTEMPTS: number = 150;

export const ROUTER_EXTRA_LOCAL_PATHS: string = 'continuationExtraPaths';

export function createPendingContinuationRouterArgs(
  payload: PdfContinuationPayload,
  extraLocalPaths: string[] = []
): Record<string, string> {
  const args: Record<string, string> = {};
  args['systemPath'] = payload.fileRef;
  args['sandboxPath'] = '';
  args['saveTempPath'] = '';
  args['fileName'] = payload.fileName;
  args[ROUTER_INITIAL_PAGE_INDEX] = String(payload.pageIndex);
  args[ROUTER_CONTINUATION_PENDING] = 'true';
  if (extraLocalPaths.length > 0) {
    args[ROUTER_EXTRA_LOCAL_PATHS] = extraLocalPaths.join('|');
  }
  return args;
}

export function parseExtraLocalPathsFromRouter(args: Record<string, string>): string[] {
  const raw = args[ROUTER_EXTRA_LOCAL_PATHS];
  if (raw === undefined || raw.length === 0) {
    return [];
  }
  return raw.split('|').filter((segment: string) => segment.length > 0);
}

export function isContinuationPendingRouterArgs(args: Record<string, string>): boolean {
  return args[ROUTER_CONTINUATION_PENDING] === 'true';
}

function isPlausibleLocalPath(path: string): boolean {
  return path.length > 1 && path.startsWith('/') && path !== 'false';
}

function buildCandidateLocalPaths(
  context: common.UIAbilityContext,
  payload: PdfContinuationPayload,
  extraLocalPaths: string[]
): string[] {
  const paths: string[] = [];
  for (let i = 0; i < extraLocalPaths.length; i++) {
    const extra = extraLocalPaths[i];
    if (isPlausibleLocalPath(extra) && !paths.includes(extra)) {
      paths.push(extra);
    }
  }
  if (payload.fileName.length > 0) {
    paths.push(`${context.distributedFilesDir}/${payload.fileName}`);
  }
  try {
    const uriPath = new fileUri.FileUri(payload.fileRef).path;
    if (uriPath.length > 0) {
      paths.push(uriPath);
    }
  } catch (error) {
    logContinuationWarn(`FileUri 解析失败: ${error}`);
  }
  const tail = payload.fileRef.split('/').pop() ?? '';
  if (tail.length > 0) {
    const decoded = decodeURIComponent(tail);
    const decodedPath = `${context.distributedFilesDir}/${decoded}`;
    if (!paths.includes(decodedPath)) {
      paths.push(decodedPath);
    }
  }
  return paths;
}

function waitForReadableFile(path: string, maxAttempts: number): Promise<boolean> {
  return new Promise((resolve) => {
    pollReadableFile(path, 0, maxAttempts, resolve);
  });
}

function pollReadableFile(
  path: string,
  attempt: number,
  maxAttempts: number,
  resolve: (ok: boolean) => void
): void {
  try {
    fs.accessSync(path);
    const stat = fs.statSync(path);
    if (stat.size > 0) {
      logContinuationLine(`pollReadableFile 成功 attempt=${attempt} size=${stat.size} path=${path}`);
      resolve(true);
      return;
    }
    if (attempt === 0 || attempt % 20 === 0) {
      logContinuationWarn(`pollReadableFile attempt=${attempt} 大小为 0: ${path}`);
    }
  } catch (error) {
    if (attempt === 0 || attempt % 20 === 0) {
      logContinuationWarn(`pollReadableFile attempt=${attempt} 不可读: ${path} (${error})`);
    }
  }
  if (attempt >= maxAttempts) {
    resolve(false);
    return;
  }
  setTimeout(() => {
    pollReadableFile(path, attempt + 1, maxAttempts, resolve);
  }, POLL_INTERVAL_MS);
}

async function findPdfInDistributedDir(context: common.UIAbilityContext): Promise<string | null> {
  try {
    const names = fs.listFileSync(context.distributedFilesDir);
    logContinuationLine(`distributedFilesDir 共 ${names.length} 项: ${names.join(' | ')}`);
    for (let i = 0; i < names.length; i++) {
      const name = names[i];
      if (!name.toLowerCase().endsWith('.pdf')) {
        continue;
      }
      const path = `${context.distributedFilesDir}/${name}`;
      if (await waitForReadableFile(path, 5)) {
        logContinuationLine(`distributedFilesDir 选用 PDF: ${path}`);
        return path;
      }
    }
  } catch (error) {
    logContinuationWarn(`listFileSync distributedFilesDir 失败: ${error}`);
  }
  return null;
}

export async function buildLaunchParamsFromLocalPath(
  context: common.UIAbilityContext,
  localPath: string,
  systemPath: string,
  fileNameHint: string
): Promise<Record<string, string>> {
  const dir = context.tempDir;
  const sourceFile = await fs.open(localPath, fs.OpenMode.READ_ONLY);
  const fileName = fileNameHint.length > 0 ? fileNameHint : sourceFile.name;
  const sandboxPath = `${dir}/${fileName}`;
  const saveTempPath = `${dir}/saveTemp_${fileName}`;
  try {
    await fs.copyFile(sourceFile.fd, sandboxPath);
  } finally {
    await fs.close(sourceFile);
  }
  return {
    'systemPath': systemPath,
    'sandboxPath': sandboxPath,
    'saveTempPath': saveTempPath,
    'fileName': fileName
  };
}

/**
 * 目标端：等待分布式目录中的 PDF 就绪并复制到应用 temp，供 PDFView 打开。
 */
const DISTRIBUTED_RESTORE_TIMEOUT_MS: number = 120000;

export async function resolveContinuationPdfParams(
  context: common.UIAbilityContext,
  payload: PdfContinuationPayload,
  extraLocalPaths: string[] = []
): Promise<Record<string, string> | null> {
  logContinuationLine(`resolveContinuationPdfParams 开始 fileName=${payload.fileName}`);
  logContinuationLine(`distributedFilesDir=${context.distributedFilesDir}`);

  const fromObject = await pdfContinuationDistributed.waitForRestoredLaunchParams(
    DISTRIBUTED_RESTORE_TIMEOUT_MS
  );
  if (fromObject !== null) {
    logContinuationLine('resolveContinuationPdfParams 已由分布式对象 restored 提供路径');
    return fromObject;
  }

  const candidates = buildCandidateLocalPaths(context, payload, extraLocalPaths);
  for (let i = 0; i < candidates.length; i++) {
    const path = candidates[i];
    if (await waitForReadableFile(path, POLL_MAX_ATTEMPTS)) {
      return await buildLaunchParamsFromLocalPath(context, path, payload.fileRef, payload.fileName);
    }
  }

  const discovered = await findPdfInDistributedDir(context);
  if (discovered !== null) {
    return await buildLaunchParamsFromLocalPath(context, discovered, payload.fileRef, payload.fileName);
  }

  logContinuationError(
    `resolveContinuationPdfParams 失败，已尝试: ${candidates.join(' | ')}`
  );
  return null;
}
