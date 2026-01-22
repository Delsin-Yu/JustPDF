import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Router, window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';

export default class EntryAbility extends UIAbility {
  private currentRouter: Router | undefined;
  private preferences: preferences.Preferences | undefined;
  private window: window.Window | undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (error) {
    }
    hilog.info(0, 'PDFView', '%{public}s', 'Ability onCreate');
    hilog.info(0, 'PDFView', `Exit Reason: ${launchParam.lastExitReason}`);

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
    this.currentRouter.replaceUrl({ url: 'pages/Index' }).catch(() => {
      hilog.error(0, 'PDFView', 'Failed to navigate to Index page on new want.');
    });
  }

  onDestroy(): void {
    hilog.info(0, 'PDFView', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main applicationWindow is created, set main page for this ability
    hilog.info(0, 'PDFView', '%{public}s', 'Ability onWindowStageCreate');
    try {
      this.preferences = preferences.getPreferencesSync(this.context, { name: 'stagePersistence' });
      this.window = windowStage.getMainWindowSync();
    } catch (error) {
      return;
    }
    AppStorage.setOrCreate('window', this.window);
    AppStorage.setOrCreate('preferences', this.preferences);
    windowStage.loadContent('pages/Index', null, (err) => {
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

      hilog.info(0, 'PDFView', 'Succeeded in loading the content.');
    });
  }

  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    hilog.fatal(0, 'PDFView', 'Ability onMemoryLevel, level: %{public}d', level);
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
          this.window.maximize(window.MaximizePresentation.ENTER_IMMERSIVE).catch()
          break;
        case 'full_screen_window':
          this.window.maximize(window.MaximizePresentation.EXIT_IMMERSIVE).catch()
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
        this.preferences.putSync('maximizeMode', this.window.getImmersiveModeEnabledState() ? 'full_screen' : 'full_screen_window');
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
    hilog.info(0, 'PDFView', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(0, 'PDFView', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(0, 'PDFView', '%{public}s', 'Ability onBackground');
  }
}