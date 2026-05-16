import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Router, window } from '@kit.ArkUI';
import { preferences, uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { addRecentFile } from '../components/RecentFilesHelper';

const SYSTEM_SHARE_LAUNCH_REASON: string = 'ReasonMessage_SystemShare';

export default class EntryAbility extends UIAbility {
  private currentRouter: Router | undefined;
  private preferences: preferences.Preferences | undefined;
  private window: window.Window | undefined;
  /** 与 window.on('avoidAreaChange') 传入 off 的引用需一致 */
  private avoidAreaChangeHandler: ((data: window.AvoidAreaOptions) => void) | undefined = undefined;
  /** 冷启动时系统分享传入的 Want，在 loadInitialContent 中解析 */
  private pendingSystemShareWant: Want | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (error) {
    }

    if (this.isSystemShareLaunch(launchParam)) {
      this.pendingSystemShareWant = want;
      return;
    }

    let uri = want.uri;
    if (uri == null || uri == undefined) {
      return;
    }
    AppStorage.setOrCreate('launchUri', uri);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (this.isSystemShareLaunch(launchParam)) {
      this.handleSystemShareWant(want);
      return;
    }

    let uri = want.uri;
    if (uri == null || uri == undefined) {
      return;
    }
    if (!this.currentRouter) {
      return;
    }
    AppStorage.setOrCreate('launchUri', uri);
    this.tryDirectLaunch();
  }

  onDestroy(): void {
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main applicationWindow is created, set main page for this ability
    try {
      this.preferences = preferences.getPreferencesSync(this.context, { name: 'stagePersistence' });
      this.window = windowStage.getMainWindowSync();
    } catch (error) {
      return;
    }
    AppStorage.setOrCreate('window', this.window);
    AppStorage.setOrCreate('preferences', this.preferences);
    AppStorage.setOrCreate('avoidAreaTopPx', 0);
    AppStorage.setOrCreate('avoidAreaBottomPx', 0);
    this.loadInitialContent(windowStage);
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
      hilog.error(0, 'EntryAbility', `解析系统分享数据失败: ${error}`);
    }
    return null;
  }

  private handleSystemShareWant(want: Want): void {
    this.extractPdfUriFromShareWant(want).then((uri: string | null) => {
      if (!uri) {
        hilog.warn(0, 'EntryAbility', '系统分享未包含可打开的 PDF');
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

  private async loadInitialContent(windowStage: window.WindowStage): Promise<void> {
    let pageUrl: string = 'pages/Index';
    let launchUri: string | undefined = AppStorage.get<string>('launchUri');
    if (this.pendingSystemShareWant) {
      const shareWant = this.pendingSystemShareWant;
      this.pendingSystemShareWant = undefined;
      const shareUri = await this.extractPdfUriFromShareWant(shareWant);
      if (shareUri) {
        launchUri = shareUri;
      }
    }
    if (launchUri) {
      try {
        const params = await this.buildLaunchParams(launchUri);
        // 保存到最近打开文件列表
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
        hilog.error(0, 'PDFView', `Cold launch preparation failed: ${error}`);
      }
    }
    windowStage.loadContent(pageUrl, null, (err) => {
      if (err.code) {
        hilog.error(0, 'PDFView', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }

      if (!this.window) {
        hilog.error(0, 'PDFView', 'Window is undefined.');
        return;
      }

      try {
        this.currentRouter = this.window.getUIContext().getRouter();
      } catch (error) {
        hilog.error(0, 'PDFView', 'Failed to get router. Cause: %{public}s', error);
      }
      try {
        this.window.on('windowRectChange', options => this.windowStateChanged(options));
      } catch (error) {
      }
      this.restoreWindowState();
      this.enableLayoutFullScreenAndSyncAvoidAreas();
    });
  }

  /**
   * 窗口全屏布局：内容延伸至状态栏与导航指示区，避让高度通过 AppStorage 下发页面 padding。
   * 参见本地文档：guides/.../arkts-develop-apply-immersive-effects.md
   */
  private enableLayoutFullScreenAndSyncAvoidAreas(): void {
    const win = this.window;
    if (!win) {
      return;
    }
    win.setWindowLayoutFullScreen(true).then(() => {
      this.syncWindowAvoidAreasToAppStorage();
      this.registerAvoidAreaChangeListener();
    }).catch((err: BusinessError) => {
      hilog.warn(0, 'EntryAbility', `setWindowLayoutFullScreen 未生效: code=${err.code}, ${err.message}`);
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
      hilog.warn(0, 'EntryAbility', `getWindowAvoidArea 失败: ${error}`);
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
      hilog.error(0, 'EntryAbility', `注册 avoidAreaChange 失败: ${error}`);
      this.avoidAreaChangeHandler = undefined;
    }
  }

  private async buildLaunchParams(launchUri: string): Promise<Record<string, string>> {
    const dir = this.context.tempDir;
    const sourceFile = await fs.open(launchUri, fs.OpenMode.READ_ONLY);
    const fileName = sourceFile.name;
    const file = dir + '/' + fileName;
    const tempFile = dir + '/saveTemp_' + fileName;
    try {
      await fs.copyFile(sourceFile.fd, file);
    } finally {
      await fs.close(sourceFile);
    }
    return {
      'systemPath': launchUri,
      'sandboxPath': file,
      'saveTempPath': tempFile,
      'fileName': fileName
    };
  }

  private async tryDirectLaunch(): Promise<void> {
    const launchUri = AppStorage.get<string>('launchUri');
    if (!launchUri || !this.currentRouter) {
      return;
    }
    // Clear launchUri so Index won't also try to load it
    AppStorage.setOrCreate('launchUri', '');
    try {
      const args = await this.buildLaunchParams(launchUri);
      // 保存到最近打开文件列表
      if (this.preferences != null) {
        addRecentFile(this.preferences, {
          fileName: args['fileName'],
          systemPath: args['systemPath'],
          openedAt: new Date().getTime()
        });
      }
      this.currentRouter.replaceUrl({ url: 'pages/PDFView', params: args });
    } catch (error) {
      hilog.error(0, 'PDFView', `Direct launch failed: ${error}`);
      AppStorage.setOrCreate('launchUri', launchUri);
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
      hilog.error(0, 'PDFView', 'Failed to restore window state. Cause: %{public}s', error);
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
      hilog.error(0, 'PDFView', 'Failed to save window state. Cause: %{public}s', error);
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
    // Ability has brought to foreground
  }

  onBackground(): void {
    // Ability has back to background
  }
}