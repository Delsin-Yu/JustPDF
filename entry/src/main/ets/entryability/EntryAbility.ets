import { AbilityConstant, ConfigurationConstant, UIAbility, Want, wantConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Router, window } from '@kit.ArkUI';
import { preferences, uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { addRecentFile } from '../components/RecentFilesHelper';
import {
  describeLaunchReason,
  extractContinuationPayload,
  getContinuationReadingStateForMigrate,
  logContinuationError,
  logContinuationLine,
  logContinuationWarn,
  logWantParameterKeys,
  extractContinuationExtraLocalPaths
} from '../continuation/PdfContinuation';
import {
  createPendingContinuationRouterArgs
} from '../continuation/PdfContinuationRestore';
import { ensureDistributedDataSyncPermission } from '../continuation/PdfContinuationPermission';
import { pdfContinuationDistributed } from '../continuation/PdfContinuationDistributed';
import {
  EVENT_APP_TERMINATE_REQUESTED,
  isPdfViewerActiveWithUnsaved,
  PDF_VIEWER_ACTIVE_KEY,
  requestReplacePdfDocument
} from '../navigation/PendingDocumentOpen';

const SYSTEM_SHARE_LAUNCH_REASON: string = 'ReasonMessage_SystemShare';
const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  private currentRouter: Router | undefined;
  private preferences: preferences.Preferences | undefined;
  private window: window.Window | undefined;
  /** 与 window.on('avoidAreaChange') 传入 off 的引用需一致 */
  private avoidAreaChangeHandler: ((data: window.AvoidAreaOptions) => void) | undefined = undefined;
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
      pdfContinuationDistributed.startRestore(this.context, want);
      this.pendingContinuationWant = want;
      logContinuationLine('onCreate 已暂存 pendingContinuationWant，等待 onWindowStageRestore');
      return;
    }

    if (this.isSystemShareLaunch(launchParam)) {
      this.pendingSystemShareWant = want;
      return;
    }

    let uri = want.uri;
    if (uri == null || uri == undefined) {
      logContinuationLine('onCreate 无 want.uri');
      return;
    }
    AppStorage.setOrCreate('launchUri', uri);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    logContinuationLine(
      `onNewWant ${describeLaunchReason(launchParam)}, hasRouter=${this.currentRouter !== undefined}`
    );
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      logWantParameterKeys(want, 'onNewWant.CONTINUATION');
      pdfContinuationDistributed.startRestore(this.context, want);
      this.pendingContinuationWant = want;
      // 勿在此处 replaceUrl：随后常会触发 onWindowStageRestore，由 loadInitialContent 加载 PDFView
      logContinuationLine('onNewWant 接续已暂存，等待 onWindowStageRestore 或延迟温启动');
      this.scheduleContinuationLaunchFallback();
      return;
    }

    if (this.isSystemShareLaunch(launchParam)) {
      this.handleSystemShareWant(want);
      return;
    }

    let uri = want.uri;
    if (uri == null || uri == undefined) {
      return;
    }
    AppStorage.setOrCreate('launchUri', uri);
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
    AppStorage.setOrCreate('window', this.window);
    AppStorage.setOrCreate('preferences', this.preferences);
    AppStorage.setOrCreate('avoidAreaTopPx', 0);
    AppStorage.setOrCreate('avoidAreaBottomPx', 0);
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

  private async extractPdfUriFromShareWant(want: Want): Promise<string | null> {
    try {
      const data: systemShare.SharedData = await systemShare.getSharedData(want);
      const records = data.getRecords();
      const pdfUtd: string = utd.UniformDataType.PDF;
      for (let i = 0; i < records.length; i++) {
        const record = records[i];
        if (!record.uri || record.uri.length === 0) {
          continue;
        }
        if (record.utd === pdfUtd || record.utd === 'com.adobe.pdf' ||
          (record.uri.toLowerCase().endsWith('.pdf'))) {
          return record.uri;
        }
      }
    } catch (error) {
      hilog.error(0, TAG, `解析系统分享数据失败: ${error}`);
    }
    return null;
  }

  private handleSystemShareWant(want: Want): void {
    this.extractPdfUriFromShareWant(want).then((uri: string | null) => {
      if (!uri) {
        hilog.warn(0, TAG, '系统分享未包含可打开的 PDF');
        return;
      }
      if (this.currentRouter) {
        AppStorage.setOrCreate('launchUri', uri);
        this.tryDirectLaunch();
        return;
      }
      AppStorage.setOrCreate('launchUri', uri);
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

    let pageUrl: string = 'pages/Index';
    let launchUri: string | undefined = AppStorage.get<string>('launchUri');
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
        const viewerActive = AppStorage.get<boolean>(PDF_VIEWER_ACTIVE_KEY) === true;
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
        AppStorage.setOrCreate('initialPdfViewArgs', continuationArgs);
        pageUrl = 'pages/PDFView';
        logContinuationLine('loadInitialContent 接续 -> pages/PDFView（PDFView 内等待分布式落地）');
      }
    } else if (this.pendingSystemShareWant) {
      const shareWant = this.pendingSystemShareWant;
      this.pendingSystemShareWant = undefined;
      const shareUri = await this.extractPdfUriFromShareWant(shareWant);
      if (shareUri) {
        launchUri = shareUri;
      }
    }

    if (pageUrl === 'pages/Index' && launchUri) {
      try {
        const params = await this.buildLaunchParams(launchUri);
        if (this.preferences != null) {
          addRecentFile(this.preferences, {
            fileName: params['fileName'],
            systemPath: params['systemPath'],
            openedAt: new Date().getTime()
          });
        }
        AppStorage.setOrCreate('initialPdfViewArgs', params);
        pageUrl = 'pages/PDFView';
        AppStorage.setOrCreate('launchUri', '');
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
      const systemArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      AppStorage.setOrCreate('avoidAreaTopPx', systemArea.topRect.height);
      const navArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      AppStorage.setOrCreate('avoidAreaBottomPx', navArea.bottomRect.height);
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
  }

  private async buildLaunchParamsFromLocalPath(
    localPath: string,
    systemPath: string,
    fileNameHint: string
  ): Promise<Record<string, string>> {
    const dir = this.context.tempDir;
    const sourceFile = await fs.open(localPath, fs.OpenMode.READ_ONLY);
    const fileName = fileNameHint.length > 0 ? fileNameHint : sourceFile.name;
    const file = `${dir}/${fileName}`;
    const tempFile = `${dir}/saveTemp_${fileName}`;
    try {
      await fs.copyFile(sourceFile.fd, file);
    } finally {
      await fs.close(sourceFile);
    }
    return {
      'systemPath': systemPath,
      'sandboxPath': file,
      'saveTempPath': tempFile,
      'fileName': fileName
    };
  }

  private async buildLaunchParams(launchUri: string): Promise<Record<string, string>> {
    let localPath = launchUri;
    try {
      const resolved = new fileUri.FileUri(launchUri).path;
      if (resolved.length > 0) {
        localPath = resolved;
      }
    } catch (_error) {
    }
    return this.buildLaunchParamsFromLocalPath(localPath, launchUri, '');
  }

  /**
   * 处理 onNewWant / 系统分享等写入的 launchUri。
   * @returns 是否已发起打开（含 defer 到 PDFView）；false 表示 Router 未就绪，launchUri 仍保留
   */
  private async tryDirectLaunch(): Promise<boolean> {
    const launchUri = AppStorage.get<string>('launchUri');
    const router = this.resolveActiveRouter();
    if (!launchUri || router === undefined) {
      return false;
    }
    AppStorage.setOrCreate('launchUri', '');
    try {
      const args = await this.buildLaunchParams(launchUri);
      if (this.preferences != null) {
        addRecentFile(this.preferences, {
          fileName: args['fileName'],
          systemPath: args['systemPath'],
          openedAt: new Date().getTime()
        });
      }
      requestReplacePdfDocument(this.context, router, args);
      return true;
    } catch (error) {
      hilog.error(0, TAG, `Direct launch failed: ${error}`);
      AppStorage.setOrCreate('launchUri', launchUri);
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
  }

  onForeground(): void {
  }

  onBackground(): void {
  }
}
