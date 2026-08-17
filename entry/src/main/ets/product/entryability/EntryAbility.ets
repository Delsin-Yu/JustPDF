import { AbilityConstant, ConfigurationConstant, UIAbility, Want, wantConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Router, window } from '@kit.ArkUI';
import { preferences, uniformTypeDescriptor as utd } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';
import {
  describeLaunchReason,
  extractContinuationPayload,
  getContinuationReadingStateForMigrate,
  logContinuationError,
  logContinuationLine,
  logContinuationWarn,
  logWantParameterKeys,
  extractContinuationExtraLocalPaths
} from '../../features/continuation/PdfContinuation';
import {
  createPendingContinuationRouterArgs
} from '../../features/continuation/PdfContinuationRestore';
import { ensureDistributedDataSyncPermission } from '../../features/continuation/PdfContinuationPermission';
import { pdfContinuationDistributed } from '../../features/continuation/PdfContinuationDistributed';
import {
  EVENT_APP_TERMINATE_REQUESTED,
  isPdfViewerActiveWithUnsaved,
  requestReplacePdfDocument,
  setExitViewerOnBack
} from '../../navigation/PendingDocumentOpen';
import {
  clearLaunchUri,
  initAvoidAreaPx,
  isPdfViewerActive,
  peekLaunchUri,
  setAvoidAreaPx,
  setInitialPdfViewArgs,
  setLaunchUri,
  setSessionPreferences,
  setSessionWindow,
  takeLaunchUri
} from '../../common/session/AppSession';
import {
  DocumentOpenParams,
  documentOpenParamsToRecord,
  prepareFromLocalPath,
  prepareFromUri,
  rememberOpenedDocument
} from '../../common/document/DocumentOpenService';
import { readWindowSafeInsetsPx } from '../../common/ui/WindowSafeInsets';
const SYSTEM_SHARE_LAUNCH_REASON: string = 'ReasonMessage_SystemShare';
const TAG = 'EntryAbility';
const WANT_ACTION_HOME: string = 'ohos.want.action.home';
const WANT_ACTION_VIEW_DATA: string = 'ohos.want.action.viewData';
const WANT_ACTION_SEND_DATA: string = 'ohos.want.action.sendData';
const WANT_ACTION_SEND_MULTIPLE_DATA: string = 'ohos.want.action.sendMultipleData';

export default class EntryAbility extends UIAbility {
  private currentRouter: Router | undefined;
  private preferences: preferences.Preferences | undefined;
  private window: window.Window | undefined;
  /** 与 window.on('avoidAreaChange') 传入 off 的引用需一致 */
  private avoidAreaChangeHandler: ((data: window.AvoidAreaOptions) => void) | undefined = undefined;
  /** 与 window.on('windowTitleButtonRectChange') 传入 off 的引用需一致 */
  private titleButtonRectChangeHandler: ((rect: window.TitleButtonRect) => void) | undefined = undefined;
  /** 冷启动时系统分享传入的 Want，在 loadInitialContent 中解析 */
  private pendingSystemShareWant: Want | undefined = undefined;
  /** 冷启动接续：在 onCreate 暂存，于 loadInitialContent 处理 */
  private pendingContinuationWant: Want | undefined = undefined;
  /** onNewWant(CONTINUATION) 后若未走 onWindowStageRestore，延迟温启动接续 */
  private continuationLaunchFallbackTimer: number | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    logContinuationLine(`onCreate ${describeLaunchReason(launchParam)}, reasonMessage=${launchParam.launchReasonMessage ?? ''}`);
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (error) {
    }

    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      logWantParameterKeys(want, 'onCreate.CONTINUATION');
      setExitViewerOnBack(false);
      pdfContinuationDistributed.startRestore(this.context, want);
      this.pendingContinuationWant = want;
      logContinuationLine('onCreate 已暂存 pendingContinuationWant，等待 onWindowStageRestore');
      return;
    }

    if (this.isInboundShareWant(want, launchParam)) {
      setExitViewerOnBack(true);
      this.pendingSystemShareWant = want;
      const fallbackUri = this.getWantUriOrStream(want);
      if (fallbackUri !== undefined) {
        setLaunchUri(fallbackUri);
      }
      hilog.info(0, TAG, 'onCreate 系统分享/sendData：武装 Want 返回');
      return;
    }

    const createUri = this.getDocumentOpenUri(want, launchParam);
    if (createUri === undefined) {
      setExitViewerOnBack(false);
      logContinuationLine('onCreate 非文档打开 Want，解除 Want 返回武装 action=' +
        (want.action ?? '') + ', uriLen=' + this.wantUriLength(want));
      return;
    }

    setExitViewerOnBack(true);
    setLaunchUri(createUri);
    hilog.info(0, TAG, 'onCreate 文档打开：武装 Want 返回 action=' + (want.action ?? '') +
      ', uriLen=' + createUri.length);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    logContinuationLine(
      'onNewWant ' + describeLaunchReason(launchParam) +
        ', hasRouter=' + (this.currentRouter !== undefined) +
        ', action=' + (want.action ?? '') +
        ', uriLen=' + this.wantUriLength(want)
    );
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      logWantParameterKeys(want, 'onNewWant.CONTINUATION');
      setExitViewerOnBack(false);
      pdfContinuationDistributed.startRestore(this.context, want);
      this.pendingContinuationWant = want;
      // 勿在此处 replaceUrl：随后常会触发 onWindowStageRestore，由 loadInitialContent 加载 PDFView
      logContinuationLine('onNewWant 接续已暂存，等待 onWindowStageRestore 或延迟温启动');
      this.scheduleContinuationLaunchFallback();
      return;
    }

    if (this.isInboundShareWant(want, launchParam)) {
      setExitViewerOnBack(true);
      hilog.info(0, TAG, 'onNewWant 系统分享/sendData：武装 Want 返回');
      this.handleSystemShareWant(want);
      return;
    }

    // 桌面图标温启动也会走 onNewWant，且可能携带上次文档的粘性 uri。
    // 仅在真正的 viewData/sendData 文档打开时武装「返回调用方」；否则显式解除。
    const openUri = this.getDocumentOpenUri(want, launchParam);
    if (openUri === undefined) {
      setExitViewerOnBack(false);
      hilog.info(0, TAG, 'onNewWant 非文档打开（如桌面图标）：解除 Want 返回武装');
      return;
    }

    setExitViewerOnBack(true);
    setLaunchUri(openUri);
    hilog.info(0, TAG, 'onNewWant 文档打开：武装 Want 返回');
    if (this.resolveActiveRouter() === undefined) {
      logContinuationLine('onNewWant 已写入 launchUri，等待 Router 就绪后打开');
    }
    void this.tryDirectLaunch();
  }

  async onContinue(wantParam: Record<string, Object>): Promise<AbilityConstant.OnContinueResult> {
    logContinuationLine('onContinue 被系统调用（源端）');
    const targetVersion = wantParam['version'];
    const targetDevice = wantParam['targetDevice'];
    if (targetVersion !== undefined) {
      logContinuationLine(`onContinue 对端 version=${String(targetVersion)}`);
    }
    if (targetDevice !== undefined) {
      logContinuationLine(`onContinue 对端 targetDevice=${String(targetDevice)}`);
    }

    wantParam[wantConstant.Params.SUPPORT_CONTINUE_PAGE_STACK_KEY] = false;
    logContinuationLine('onContinue SUPPORT_CONTINUE_PAGE_STACK_KEY=false');

    const readingState = getContinuationReadingStateForMigrate();
    if (readingState === null) {
      logContinuationWarn('onContinue 返回 REJECT：无阅读快照（未打开 PDF 或已返回首页）');
      return AbilityConstant.OnContinueResult.REJECT;
    }

    const sandboxPath = readingState.sandboxPath;
    const fileName = readingState.fileName.length > 0 ? readingState.fileName : 'document.pdf';
    const pageIndex = readingState.pageIndex;

    const syncGranted = await ensureDistributedDataSyncPermission(this.context, true);
    if (!syncGranted) {
      logContinuationError('onContinue 返回 REJECT：未授予 DISTRIBUTED_DATASYNC');
      return AbilityConstant.OnContinueResult.REJECT;
    }

    const saved = await pdfContinuationDistributed.savePdfForContinuation(
      this.context,
      wantParam,
      sandboxPath,
      fileName,
      pageIndex
    );
    if (!saved) {
      logContinuationError('onContinue 返回 REJECT：分布式对象/文件资产 save 失败');
      return AbilityConstant.OnContinueResult.REJECT;
    }

    logContinuationLine(
      `onContinue 返回 AGREE: pageIndex=${pageIndex}, fileName=${fileName}, ` +
      `dataSessionId=${String(wantParam['justpdf_dataSessionId'] ?? '')}`
    );
    return AbilityConstant.OnContinueResult.AGREE;
  }

  onDestroy(): void {
  }

  /**
   * 2in1/平板窗口关闭前询问是否保存；返回 true 取消本次关闭。
   * 手机从多任务划掉通常不会触发此回调。
   */
  async onPrepareToTerminateAsync(): Promise<boolean> {
    if (!isPdfViewerActiveWithUnsaved()) {
      return false;
    }
    try {
      this.context.eventHub.emit(EVENT_APP_TERMINATE_REQUESTED);
    } catch (error) {
      hilog.error(0, TAG, `onPrepareToTerminateAsync emit 失败: ${error}`);
    }
    return true;
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    logContinuationLine('onWindowStageCreate（普通启动）');
    this.bootstrapWindowStage(windowStage, 'create');
  }

  onWindowStageRestore(windowStage: window.WindowStage): void {
    logContinuationLine('onWindowStageRestore（接续/迁移启动）');
    this.bootstrapWindowStage(windowStage, 'restore');
  }

  private bootstrapWindowStage(windowStage: window.WindowStage, stageKind: string): void {
    logContinuationLine(
      `bootstrapWindowStage kind=${stageKind}, pendingContinuation=${this.pendingContinuationWant !== undefined}`
    );
    try {
      this.preferences = preferences.getPreferencesSync(this.context, { name: 'stagePersistence' });
      this.window = windowStage.getMainWindowSync();
    } catch (error) {
      logContinuationError(`bootstrapWindowStage 失败: ${error}`);
      return;
    }
    setSessionWindow(this.window);
    setSessionPreferences(this.preferences);
    initAvoidAreaPx();
    void this.loadInitialContent(windowStage, stageKind);
  }

  private clearContinuationLaunchFallback(): void {
    if (this.continuationLaunchFallbackTimer !== undefined) {
      clearTimeout(this.continuationLaunchFallbackTimer);
      this.continuationLaunchFallbackTimer = undefined;
    }
  }

  /** 仅当未发生 onWindowStageRestore 时，在应用已前台的情况下温启动接续 */
  private scheduleContinuationLaunchFallback(): void {
    this.clearContinuationLaunchFallback();
    this.continuationLaunchFallbackTimer = setTimeout(() => {
      this.continuationLaunchFallbackTimer = undefined;
      if (this.pendingContinuationWant === undefined) {
        return;
      }
      logContinuationLine('接续延迟温启动（未收到 onWindowStageRestore）');
      if (this.attemptPendingContinuationLaunch()) {
        logContinuationLine('接续延迟温启动完成');
      }
    }, 250);
  }

  private isSystemShareLaunch(launchParam: AbilityConstant.LaunchParam): boolean {
    return launchParam.launchReasonMessage === SYSTEM_SHARE_LAUNCH_REASON;
  }

  /** 系统分享面板，或其它应用以 sendData 直接拉起（微信等可能不带 ReasonMessage_SystemShare）。 */
  private isInboundShareWant(want: Want, launchParam: AbilityConstant.LaunchParam): boolean {
    if (this.isSystemShareLaunch(launchParam)) {
      return true;
    }
    const action = want.action ?? '';
    return action === WANT_ACTION_SEND_DATA || action === WANT_ACTION_SEND_MULTIPLE_DATA;
  }

  private wantUriLength(want: Want): number {
    const uri = want.uri;
    if (uri === undefined || uri === null) {
      return 0;
    }
    return uri.length;
  }

  /**
   * 从「文件管理器/分享打开 PDF」的 Want 取出 uri；桌面图标（home）或粘性 uri 返回 undefined。
   * 桌面图标温启动常复用上次文档 uri，但 action 为 home，不得武装 Want 返回。
   * 微信 PDF 预览「用其他应用打开」常省略 action，只带 file URI + application/pdf + READ 授权。
   */
  private getDocumentOpenUri(want: Want, launchParam: AbilityConstant.LaunchParam): string | undefined {
    if (this.isSystemShareLaunch(launchParam)) {
      return undefined;
    }
    const action = want.action ?? '';
    if (action === WANT_ACTION_HOME) {
      return undefined;
    }
    const hasFileOpenAction = action === WANT_ACTION_VIEW_DATA
      || action === WANT_ACTION_SEND_DATA
      || action === WANT_ACTION_SEND_MULTIPLE_DATA;
    if (!hasFileOpenAction && !this.isImplicitPdfFileOpenWant(want)) {
      return undefined;
    }
    const uri = want.uri;
    if (uri !== undefined && uri !== null && uri.length > 0) {
      return uri;
    }
    return this.extractStreamUri(want);
  }

  /** 无 action 的隐式打开：须同时具备 PDF 标识与 URI 读授权，避免把桌面空启动当成打开文档。 */
  private isImplicitPdfFileOpenWant(want: Want): boolean {
    const action = want.action ?? '';
    if (action.length > 0) {
      return false;
    }
    const rawUri = want.uri;
    if (rawUri === undefined || rawUri === null || rawUri.length === 0) {
      return false;
    }
    const flags = want.flags;
    const flagValue = flags === undefined ? 0 : flags;
    if ((flagValue & wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION) === 0) {
      return false;
    }
    const wantType = want.type ?? '';
    if (wantType === 'application/pdf' || wantType === 'com.adobe.pdf' || wantType === 'general.pdf') {
      return true;
    }
    return rawUri.toLowerCase().indexOf('.pdf') >= 0;
  }

  private getWantUriOrStream(want: Want): string | undefined {
    const uri = want.uri;
    if (uri !== undefined && uri !== null && uri.length > 0) {
      return uri;
    }
    return this.extractStreamUri(want);
  }

  private extractStreamUri(want: Want): string | undefined {
    const params = want.parameters;
    if (params === undefined) {
      return undefined;
    }
    const streamRaw = params[wantConstant.Params.PARAMS_STREAM];
    if (streamRaw === undefined || streamRaw === null) {
      return undefined;
    }
    if (typeof streamRaw === 'string' && streamRaw.length > 0) {
      return streamRaw;
    }
    const joined = String(streamRaw);
    if (joined.length === 0 || joined === '[object Object]') {
      return undefined;
    }
    const comma = joined.indexOf(',');
    if (comma < 0) {
      return joined;
    }
    return joined.substring(0, comma);
  }

  private shareRecordLooksLikePdf(record: systemShare.SharedRecord): boolean {
    const recordUtd = record.utd;
    if (recordUtd === utd.UniformDataType.PDF || recordUtd === 'com.adobe.pdf' ||
      recordUtd === 'application/pdf') {
      return true;
    }
    if (recordUtd !== undefined && recordUtd.length > 0) {
      try {
        const typeDesc = utd.getTypeDescriptor(recordUtd);
        if (typeDesc !== null && typeDesc.belongsTo(utd.UniformDataType.PDF)) {
          return true;
        }
      } catch (_error) {
      }
    }
    const recordUri = record.uri;
    if (recordUri !== undefined && recordUri.toLowerCase().indexOf('.pdf') >= 0) {
      return true;
    }
    const title = record.title;
    if (title !== undefined && title.toLowerCase().endsWith('.pdf')) {
      return true;
    }
    return false;
  }

  private async extractPdfUriFromShareWant(want: Want): Promise<string | null> {
    try {
      const data: systemShare.SharedData = await systemShare.getSharedData(want);
      const records = data.getRecords();
      let firstFileUri: string | null = null;
      for (let i = 0; i < records.length; i++) {
        const record = records[i];
        const recordUri = record.uri;
        if (recordUri === undefined || recordUri.length === 0) {
          continue;
        }
        hilog.info(0, TAG, '分享记录[' + i.toString() + '] utd=' + (record.utd ?? '') +
          ', uriLen=' + recordUri.length.toString());
        if (this.shareRecordLooksLikePdf(record)) {
          return recordUri;
        }
        if (firstFileUri === null) {
          firstFileUri = recordUri;
        }
      }
      if (firstFileUri !== null) {
        hilog.info(0, TAG, '分享未标 PDF，使用首条文件 URI');
        return firstFileUri;
      }
    } catch (error) {
      hilog.error(0, TAG, '解析系统分享数据失败: ' + String(error));
    }
    const fallback = this.getWantUriOrStream(want);
    if (fallback !== undefined) {
      hilog.info(0, TAG, '分享回退 want.uri/stream，uriLen=' + fallback.length.toString());
      return fallback;
    }
    return null;
  }

  private handleSystemShareWant(want: Want): void {
    this.extractPdfUriFromShareWant(want).then((uri: string | null) => {
      if (uri === null) {
        hilog.warn(0, TAG, '系统分享未包含可打开的 PDF');
        return;
      }
      setLaunchUri(uri);
      void this.tryDirectLaunch();
    });
  }

  private resolveActiveRouter(): Router | undefined {
    if (this.currentRouter !== undefined) {
      return this.currentRouter;
    }
    if (!this.window) {
      return undefined;
    }
    try {
      return this.window.getUIContext().getRouter();
    } catch (error) {
      hilog.warn(0, TAG, `resolveActiveRouter 失败: ${error}`);
      return undefined;
    }
  }

  private buildContinuationRouterArgs(want: Want): Record<string, string> | undefined {
    const payload = extractContinuationPayload(want);
    if (payload === null) {
      return undefined;
    }
    const extraPaths = extractContinuationExtraLocalPaths(want);
    return createPendingContinuationRouterArgs(payload, extraPaths);
  }

  /**
   * 跨设备接续：Router 就绪时通过 guarded replaceUrl 打开；否则保留 pendingContinuationWant。
   */
  private attemptPendingContinuationLaunch(): boolean {
    if (this.pendingContinuationWant === undefined) {
      return false;
    }
    const args = this.buildContinuationRouterArgs(this.pendingContinuationWant);
    if (args === undefined) {
      logContinuationError('attemptPendingContinuationLaunch 接续载荷无效');
      this.pendingContinuationWant = undefined;
      return false;
    }
    const router = this.resolveActiveRouter();
    if (router === undefined) {
      return false;
    }
    this.pendingContinuationWant = undefined;
    const handled = requestReplacePdfDocument(this.context, router, args);
    if (handled) {
      logContinuationLine('attemptPendingContinuationLaunch 已请求打开接续 PDF');
    }
    return handled;
  }

  private async loadInitialContent(windowStage: window.WindowStage, stageKind: string): Promise<void> {
    this.clearContinuationLaunchFallback();

    let pageUrl: string = 'product/pages/Index';
    let launchUri: string | undefined = peekLaunchUri();
    if (launchUri !== undefined && launchUri.length === 0) {
      launchUri = undefined;
    }
    logContinuationLine(
      `loadInitialContent 开始 kind=${stageKind}, pendingContinuation=${this.pendingContinuationWant !== undefined}`
    );

    if (this.pendingContinuationWant !== undefined) {
      const continuationWant = this.pendingContinuationWant;
      const continuationArgs = this.buildContinuationRouterArgs(continuationWant);
      if (continuationArgs === undefined) {
        this.pendingContinuationWant = undefined;
        logContinuationError('loadInitialContent 接续载荷无效，留在 Index');
      } else {
        const router = this.resolveActiveRouter();
        const viewerActive = isPdfViewerActive();
        this.pendingContinuationWant = undefined;

        // 迁移恢复 + 阅读页未保存：不 loadContent(Index)，保留当前页并弹窗
        if (stageKind === 'restore' && viewerActive && router !== undefined && isPdfViewerActiveWithUnsaved()) {
          requestReplacePdfDocument(this.context, router, continuationArgs);
          logContinuationLine('loadInitialContent 接续 restore+未保存：defer，跳过 loadContent');
          try {
            this.currentRouter = router;
          } catch (_error) {
          }
          return;
        }

        // 温接续（非 restore）：阅读页已在前台，guarded replaceUrl，勿再 loadContent 盖掉
        if (stageKind !== 'restore' && viewerActive && router !== undefined) {
          requestReplacePdfDocument(this.context, router, continuationArgs);
          logContinuationLine(
            `loadInitialContent 温接续已派发（未保存=${isPdfViewerActiveWithUnsaved()}），跳过 loadContent`
          );
          try {
            this.currentRouter = router;
          } catch (_error) {
          }
          return;
        }

        // 冷启动 / onWindowStageRestore：必须由 loadContent 进入 PDFView
        setInitialPdfViewArgs(continuationArgs);
        pageUrl = 'features/viewer/PDFView';
        logContinuationLine('loadInitialContent 接续 -> features/viewer/PDFView（PDFView 内等待分布式落地）');
      }
    } else if (this.pendingSystemShareWant) {
      const shareWant = this.pendingSystemShareWant;
      this.pendingSystemShareWant = undefined;
      const shareUri = await this.extractPdfUriFromShareWant(shareWant);
      if (shareUri) {
        launchUri = shareUri;
      } else {
        hilog.warn(0, TAG, 'loadInitialContent 系统分享未解析到 URI，回退 launchUri');
      }
    }

    if (pageUrl === 'product/pages/Index' && launchUri) {
      try {
        const params = await this.buildLaunchParams(launchUri);
        await rememberOpenedDocument(this.preferences, params);
        setInitialPdfViewArgs(documentOpenParamsToRecord(params));
        pageUrl = 'features/viewer/PDFView';
        clearLaunchUri();
      } catch (error) {
        hilog.error(0, TAG, `Cold launch preparation failed: ${error}`);
      }
    }

    logContinuationLine(`loadInitialContent loadContent url=${pageUrl}`);
    windowStage.loadContent(pageUrl, null, (err) => {
      if (err.code) {
        logContinuationError(`loadContent 失败: ${JSON.stringify(err)}`);
        return;
      }
      logContinuationLine(`loadContent 成功 url=${pageUrl}`);

      if (!this.window) {
        hilog.error(0, TAG, 'Window is undefined.');
        return;
      }

      try {
        this.currentRouter = this.window.getUIContext().getRouter();
      } catch (error) {
        hilog.error(0, TAG, 'Failed to get router. Cause: %{public}s', error);
      }
      try {
        this.window.on('windowRectChange', options => this.windowStateChanged(options));
      } catch (error) {
      }
      this.restoreWindowState();
      this.enableLayoutFullScreenAndSyncAvoidAreas();
      void this.tryDirectLaunch();
    });
  }

  private enableLayoutFullScreenAndSyncAvoidAreas(): void {
    const win = this.window;
    if (!win) {
      return;
    }
    win.setWindowLayoutFullScreen(true).then(() => {
      this.syncWindowAvoidAreasToAppStorage();
      this.registerAvoidAreaChangeListener();
    }).catch((err: BusinessError) => {
      hilog.warn(0, TAG, `setWindowLayoutFullScreen 未生效: code=${err.code}, ${err.message}`);
      this.syncWindowAvoidAreasToAppStorage();
      this.registerAvoidAreaChangeListener();
    });
  }

  private syncWindowAvoidAreasToAppStorage(): void {
    const win = this.window;
    if (!win) {
      return;
    }
    try {
      setAvoidAreaPx(readWindowSafeInsetsPx(win));
    } catch (error) {
      hilog.warn(0, TAG, `getWindowAvoidArea 失败: ${error}`);
    }
  }

  private registerAvoidAreaChangeListener(): void {
    const win = this.window;
    if (!win || this.avoidAreaChangeHandler !== undefined) {
      return;
    }
    this.avoidAreaChangeHandler = (_data: window.AvoidAreaOptions) => {
      this.syncWindowAvoidAreasToAppStorage();
    };
    try {
      win.on('avoidAreaChange', this.avoidAreaChangeHandler);
    } catch (error) {
      hilog.error(0, TAG, `注册 avoidAreaChange 失败: ${error}`);
      this.avoidAreaChangeHandler = undefined;
    }
    if (this.titleButtonRectChangeHandler === undefined) {
      this.titleButtonRectChangeHandler = (_rect: window.TitleButtonRect) => {
        this.syncWindowAvoidAreasToAppStorage();
      };
      try {
        win.on('windowTitleButtonRectChange', this.titleButtonRectChangeHandler);
      } catch (error) {
        hilog.warn(0, TAG, `注册 windowTitleButtonRectChange 失败: ${error}`);
        this.titleButtonRectChangeHandler = undefined;
      }
    }
  }

  private async buildLaunchParamsFromLocalPath(
    localPath: string,
    systemPath: string,
    fileNameHint: string
  ): Promise<DocumentOpenParams> {
    return prepareFromLocalPath(this.context, localPath, systemPath, fileNameHint);
  }

  private async buildLaunchParams(launchUri: string): Promise<DocumentOpenParams> {
    return prepareFromUri(this.context, launchUri);
  }

  /**
   * 处理 onNewWant / 系统分享等写入的 launchUri。
   * @returns 是否已发起打开（含 defer 到 PDFView）；false 表示 Router 未就绪，launchUri 仍保留
   */
  private async tryDirectLaunch(): Promise<boolean> {
    const router = this.resolveActiveRouter();
    if (router === undefined) {
      return false;
    }
    const launchUri = takeLaunchUri();
    if (launchUri === undefined) {
      return false;
    }
    try {
      const params = await this.buildLaunchParams(launchUri);
      await rememberOpenedDocument(this.preferences, params);
      requestReplacePdfDocument(this.context, router, documentOpenParamsToRecord(params));
      return true;
    } catch (error) {
      hilog.error(0, TAG, `Direct launch failed: ${error}`);
      setLaunchUri(launchUri);
      return false;
    }
  }

  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    try {
      this.context.eventHub.emit('memoryPressure', level);
    } catch (_e) {
    }
  }

  restoreWindowState(): void {
    if (!this.preferences || !this.window) {
      return;
    }
    try {
      if (this.preferences.hasSync('windowRect')) {
        let rect = this.preferences.getSync('windowRect', {
          left: 0,
          top: 0,
          width: 0,
          height: 0
        }) as window.Rect;
        this.window.resize(rect.width, rect.height).catch();
        this.window.moveWindowToGlobalDisplay(rect.left, rect.top).catch();
      }
      switch ((this.preferences.getSync('maximizeMode', 'windowed') as string))
      {
        case 'full_screen':
          this.window.maximize(window.MaximizePresentation.ENTER_IMMERSIVE).catch();
          break;
        case 'full_screen_window':
          this.window.maximize(window.MaximizePresentation.EXIT_IMMERSIVE).catch();
          break;
        case 'windowed':
          break;
      }

    } catch (error) {
      hilog.error(0, TAG, 'Failed to restore window state. Cause: %{public}s', error);
    }
  }

  windowStateChanged(options: window.RectChangeOptions): void {
    if (!this.preferences || !this.window) {
      return;
    }
    try {
      if (options.reason == window.RectChangeReason.DRAG_START) {
        return;
      }
      this.preferences.putSync('windowRect', this.window.getGlobalRect());
      if (options.reason == window.RectChangeReason.MAXIMIZE) {
        const immersive = this.window.getImmersiveModeEnabledState();
        this.preferences.putSync('maximizeMode', immersive ? 'full_screen' : 'full_screen_window');
      } else if (options.reason == window.RectChangeReason.RECOVER) {
        this.preferences.putSync('maximizeMode', 'windowed');
      }
      this.preferences.flushSync();
      this.syncWindowAvoidAreasToAppStorage();
    } catch (error) {
      hilog.error(0, TAG, 'Failed to save window state. Cause: %{public}s', error);
    }
  }

  onWindowStageDestroy(): void {
    if (this.window !== undefined && this.avoidAreaChangeHandler !== undefined) {
      try {
        this.window.off('avoidAreaChange', this.avoidAreaChangeHandler);
      } catch (_e) {
      }
      this.avoidAreaChangeHandler = undefined;
    }
    if (this.window !== undefined && this.titleButtonRectChangeHandler !== undefined) {
      try {
        this.window.off('windowTitleButtonRectChange', this.titleButtonRectChangeHandler);
      } catch (_e) {
      }
      this.titleButtonRectChangeHandler = undefined;
    }
  }

  onForeground(): void {
  }

  onBackground(): void {
    // Want「返回调用方」仅武装一次；任意进后台后解除，避免桌面再入后系统返回仍进后台。
    setExitViewerOnBack(false);
  }
}
