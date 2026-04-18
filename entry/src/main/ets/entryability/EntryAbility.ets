import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Router, window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';

export default class EntryAbility extends UIAbility {
  private currentRouter: Router | undefined;
  private preferences: preferences.Preferences | undefined;
  private window: window.Window | undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (error) {
    }

    let uri = want.uri;
    if (uri == null || uri == undefined) {
      return;
    }
    AppStorage.setOrCreate('launchUri', uri);
  }

  onNewWant(want: Want): void {
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
    this.loadInitialContent(windowStage);
  }

  private async loadInitialContent(windowStage: window.WindowStage): Promise<void> {
    let pageUrl: string = 'pages/Index';
    const launchUri = AppStorage.get<string>('launchUri');
    if (launchUri) {
      try {
        const params = await this.buildLaunchParams(launchUri);
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
    });
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
      this.currentRouter.replaceUrl({ url: 'pages/PDFView', params: args });
    } catch (error) {
      hilog.error(0, 'PDFView', `Direct launch failed: ${error}`);
      AppStorage.setOrCreate('launchUri', launchUri);
    }
  }

  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    hilog.warn(0, 'PDFView', 'Ability onMemoryLevel, level: %{public}d', level);
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
    // Main applicationWindow is destroyed, release UI related resources
  }

  onForeground(): void {
    // Ability has brought to foreground
  }

  onBackground(): void {
    // Ability has back to background
  }
}