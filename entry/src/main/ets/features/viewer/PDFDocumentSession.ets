import { toResultCode } from '../../common/ui/UIComponents';
import { pdfLoadNeedsPassword, reloadPdfDocument } from '../../common/document/PdfDocumentLoader';
import { PageInfo } from '../../common/page/PageInfo';
import { PageStore } from '../../common/page/PageStore';
import {
  logAppStorageContinuationState,
  logContinuationError,
  logContinuationLine,
  logContinuationWarn,
  PdfContinuationPayload,
  updateContinuationReadingState
} from '../continuation/PdfContinuation';
import { ensureDistributedDataSyncPermission } from '../continuation/PdfContinuationPermission';
import { resolveContinuationPdfParams } from '../continuation/PdfContinuationRestore';
import { AbilityConstant, common } from '@kit.AbilityKit';
import { pdfService } from '@kit.PDFKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PDFViewerViewModel } from './PDFViewerViewModel';

export interface PDFDocumentSessionPaths {
  systemPath: string;
  sandBoxPath: string;
  saveTempPath: string;
  fileName: string;
}

export interface PDFDocumentSessionDependencies {
  document: pdfService.PdfDocument;
  pageDataSource: PageStore;
  viewerViewModel: PDFViewerViewModel;
  getUIContext: () => UIContext;
  getPaths: () => PDFDocumentSessionPaths;
  setPaths: (paths: PDFDocumentSessionPaths) => void;
  getDocumentLoadVersion: () => number;
  bumpDocumentLoadVersion: () => number;
  cancelAnnotatePrepareSession: () => void;
  createPlaceholderPixelMap: () => Promise<void>;
  clearLinkJumpHistory: () => void;
  gotoPage: (targetIndex: number, deferSlideVisualReset: boolean, recordJumpHistory: boolean) => Promise<void>;
  refreshBookmarks: () => void;
  triggerPageFlipShadeIntro: () => void;
  startTransparencyTimeout: () => void;
  requestLeaveViewer: () => void;
}

@ObservedV2
export class PDFDocumentSession {
  private readonly dependencies: PDFDocumentSessionDependencies;
  private passwordPromptResolver: ((password: string | null) => void) | undefined = undefined;
  private lastContinuationLoggedPageIndex: number = -1;

  /** 当前会话打开加密 PDF 的密码；不写 preferences，离开阅读页即丢弃。 */
  sessionPdfPassword: string = '';
  /** 跨设备接续恢复时的起始页（0-based） */
  continuationInitialPageIndex: number = 0;
  /** 目标端：沙箱 PDF 尚未落地，需在 initializeDocument 中轮询 distributedFilesDir */
  continuationPending: boolean = false;
  continuationExtraLocalPaths: string[] = [];
  documentInitStarted: boolean = false;

  @Trace isDocumentLoading: boolean = true;
  @Trace loadError: string = '';
  @Trace showPasswordGate: boolean = false;
  @Trace passwordGateInput: string = '';
  @Trace passwordGateErrorHint: string = '';

  constructor(dependencies: PDFDocumentSessionDependencies) {
    this.dependencies = dependencies;
  }

  configureFromRouterArgs(
    continuationInitialPageIndex: number,
    continuationPending: boolean,
    continuationExtraLocalPaths: string[]
  ): void {
    this.continuationInitialPageIndex = continuationInitialPageIndex;
    this.continuationPending = continuationPending;
    this.continuationExtraLocalPaths = continuationExtraLocalPaths;
  }

  enableContinuationForMigration(): void {
    logContinuationLine('PDFView.onPageShow -> setMissionContinueState(ACTIVE)');
    logAppStorageContinuationState('PDFView.onPageShow.进入');
    try {
      const abilityContext = this.dependencies.getUIContext().getHostContext() as common.UIAbilityContext;
      void ensureDistributedDataSyncPermission(abilityContext, true);
      abilityContext.setMissionContinueState(AbilityConstant.ContinueState.ACTIVE, (result) => {
        if (result.code !== 0) {
          logContinuationWarn(
            'setMissionContinueState(ACTIVE) 失败 code=' + result.code.toString() +
              ', msg=' + (result.message ?? '')
          );
        } else {
          logContinuationLine('setMissionContinueState(ACTIVE) 成功');
        }
      });
    } catch (error) {
      logContinuationError('setMissionContinueState(ACTIVE) 异常: ' + error);
    }
  }

  disableContinuationForMigration(): void {
    logContinuationLine('PDFView.aboutToDisappear -> setMissionContinueState(INACTIVE)');
    try {
      const abilityContext = this.dependencies.getUIContext().getHostContext() as common.UIAbilityContext;
      abilityContext.setMissionContinueState(AbilityConstant.ContinueState.INACTIVE, (result) => {
        if (result.code !== 0) {
          logContinuationWarn('setMissionContinueState(INACTIVE) 失败 code=' + result.code.toString());
        } else {
          logContinuationLine('setMissionContinueState(INACTIVE) 成功');
        }
      });
    } catch (error) {
      logContinuationError('setMissionContinueState(INACTIVE) 异常: ' + error);
    }
  }

  syncContinuationReadingState(): void {
    if (this.isDocumentLoading) {
      logContinuationWarn('syncContinuationReadingState 跳过：文档仍在加载');
      return;
    }
    const paths = this.dependencies.getPaths();
    if (paths.sandBoxPath.length === 0) {
      logContinuationWarn('syncContinuationReadingState 跳过：sandBoxPath 为空');
      return;
    }
    const pageIndex = this.dependencies.viewerViewModel.currentPageIndex;
    updateContinuationReadingState(
      paths.sandBoxPath,
      paths.systemPath,
      paths.fileName,
      pageIndex
    );
    if (pageIndex !== this.lastContinuationLoggedPageIndex) {
      this.lastContinuationLoggedPageIndex = pageIndex;
      logContinuationLine(
        'syncContinuationReadingState pageIndex=' + pageIndex.toString() +
          ', fileName=' + paths.fileName
      );
      logAppStorageContinuationState('PDFView.sync后');
    }
  }

  async initializeDocument(): Promise<void> {
    this.loadError = '';
    this.sessionPdfPassword = '';
    this.dependencies.cancelAnnotatePrepareSession();
    const loadVersion = this.dependencies.bumpDocumentLoadVersion();

    if (this.continuationPending) {
      this.continuationPending = false;
      const abilityContext = this.dependencies.getUIContext().getHostContext() as common.UIAbilityContext;
      const syncGranted = await ensureDistributedDataSyncPermission(abilityContext, true);
      if (!syncGranted) {
        if (this.dependencies.getDocumentLoadVersion() === loadVersion) {
          this.loadError = '需要「分布式数据同步」权限才能完成跨设备接续';
          this.isDocumentLoading = false;
        }
        return;
      }
      const paths = this.dependencies.getPaths();
      const payload: PdfContinuationPayload = {
        fileRef: paths.systemPath,
        pageIndex: this.continuationInitialPageIndex,
        fileName: paths.fileName
      };
      logContinuationLine('initializeDocument 接续目标端，等待分布式 PDF 落地');
      const resolved = await resolveContinuationPdfParams(
        abilityContext,
        payload,
        this.continuationExtraLocalPaths
      );
      if (this.dependencies.getDocumentLoadVersion() !== loadVersion) {
        return;
      }
      if (resolved === null) {
        this.loadError =
          '接续文件尚未到达本机。请确认双端同一华为账号、已开启 Wi‑Fi/蓝牙与系统「接续」，并已授予分布式同步权限。';
        this.isDocumentLoading = false;
        return;
      }
      const nextPaths: PDFDocumentSessionPaths = {
        systemPath: resolved['systemPath'],
        sandBoxPath: resolved['sandboxPath'],
        saveTempPath: resolved['saveTempPath'],
        fileName: resolved['fileName']
      };
      this.dependencies.setPaths(nextPaths);
      logContinuationLine('initializeDocument 接续文件已落地 sandbox=' + nextPaths.sandBoxPath);
    }

    const loaded = await this.loadDocumentWithPasswordPrompt(loadVersion);
    if (!loaded) {
      return;
    }
    if (this.dependencies.getDocumentLoadVersion() != loadVersion) {
      return;
    }
    const pathsAfterLoad = this.dependencies.getPaths();
    this.dependencies.viewerViewModel.setTotalPageCount(this.dependencies.document.getPageCount());
    for (let i = 0; i < this.dependencies.viewerViewModel.totalPageCount; i++) {
      this.dependencies.pageDataSource.push(
        new PageInfo(i, this.dependencies.document, pathsAfterLoad.sandBoxPath, this.sessionPdfPassword)
      );
    }

    await this.dependencies.createPlaceholderPixelMap();
    let startPage = this.continuationInitialPageIndex;
    if (startPage >= this.dependencies.viewerViewModel.totalPageCount) {
      const clamped = this.dependencies.viewerViewModel.getLastNavigableIndex();
      logContinuationWarn(
        'initializeDocument 起始页 ' + startPage.toString() +
          ' 超出总页数 ' + this.dependencies.viewerViewModel.totalPageCount.toString() +
          '，改为 ' + clamped.toString()
      );
      startPage = clamped;
    }
    this.dependencies.clearLinkJumpHistory();
    logContinuationLine(
      'initializeDocument gotoPage startPage=' + startPage.toString() +
        ', totalPages=' + this.dependencies.viewerViewModel.totalPageCount.toString()
    );
    await this.dependencies.gotoPage(startPage, false, false);
    this.syncContinuationReadingState();
    this.dependencies.refreshBookmarks();
    this.isDocumentLoading = false;
    this.dependencies.triggerPageFlipShadeIntro();
    this.dependencies.startTransparencyTimeout();
  }

  /**
   * 尝试加载 PDF；若加密则循环弹出密码框直至成功或用户取消。
   * 密码仅保存在 sessionPdfPassword，不写入 preferences。
   */
  private async loadDocumentWithPasswordPrompt(loadVersion: number): Promise<boolean> {
    let password = '';
    let passwordErrorHint = '';

    while (true) {
      const paths = this.dependencies.getPaths();
      const result = password.length === 0
        ? this.dependencies.document.loadDocument(paths.sandBoxPath, '')
        : reloadPdfDocument(this.dependencies.document, paths.sandBoxPath, password);

      if (result === pdfService.ParseResult.PARSE_SUCCESS) {
        this.sessionPdfPassword = password;
        return true;
      }

      if (!pdfLoadNeedsPassword(result, paths.sandBoxPath)) {
        const resultText = toResultCode(result);
        hilog.error(0, 'PDFView', '加载 PDF 文件出错: ' + resultText);
        if (this.dependencies.getDocumentLoadVersion() === loadVersion) {
          this.loadError = '无法加载 PDF 文件: ' + resultText;
          this.isDocumentLoading = false;
        }
        return false;
      }

      if (result === pdfService.ParseResult.PARSE_ERROR_PASSWORD) {
        try {
          this.dependencies.document.releaseDocument();
        } catch (_e) {
          /* ignore */
        }
      }

      if (this.dependencies.getDocumentLoadVersion() !== loadVersion) {
        return false;
      }

      const entered = await this.waitForPasswordGateInput(passwordErrorHint);

      if (entered === null) {
        if (this.dependencies.getDocumentLoadVersion() === loadVersion) {
          this.isDocumentLoading = false;
          this.dependencies.requestLeaveViewer();
        }
        return false;
      }

      password = entered;
      passwordErrorHint = '密码错误，请重试';
    }
  }

  /** 在阅读页内嵌密码门（不用 CustomDialog，避免页面未完成构建时 open 崩溃）。 */
  private waitForPasswordGateInput(errorHint: string): Promise<string | null> {
    return new Promise<string | null>((resolve) => {
      this.passwordGateInput = '';
      this.passwordGateErrorHint = errorHint;
      this.showPasswordGate = true;
      this.passwordPromptResolver = resolve;
    });
  }

  resolvePasswordGate(password: string | null): void {
    this.showPasswordGate = false;
    const resolver = this.passwordPromptResolver;
    this.passwordPromptResolver = undefined;
    resolver?.(password);
  }

  confirmPasswordGate(): void {
    this.resolvePasswordGate(this.passwordGateInput);
  }

  cancelPasswordGate(): void {
    this.resolvePasswordGate(null);
  }

  resetSessionOnLeave(): void {
    this.sessionPdfPassword = '';
    this.resolvePasswordGate(null);
    this.documentInitStarted = false;
  }
}
