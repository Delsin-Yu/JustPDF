import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Router, window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { WaterfallPreference } from '../common/WaterfallPreference';

export default class EntryAbility extends UIAbility {
  private currentRouter: Router | undefined;
  private preferences: preferences.Preferences | undefined;
  private window: window.Window | undefined;
  // Tracks whether the user has opted into waterfall (瀑布流) mode for hover-state
  // 2in1 devices. Persisted via preferences and editable from the Settings dialog.
  private preferWaterfall: boolean = true;

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
    this.tryDirectLaunch();
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
    try {
      this.preferWaterfall = this.preferences.getSync('preferWaterfall', true) as boolean;
    } catch (error) {
      this.preferWaterfall = true;
    }
    AppStorage.setOrCreate('preferWaterfall', this.preferWaterfall);
    WaterfallPreference.setter = (enable: boolean) => this.setPreferWaterfall(enable);
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

      // If a launch URI is already set, skip Index and go directly to PDFView
      this.tryDirectLaunch();

      hilog.info(0, 'PDFView', 'Succeeded in loading the content.');
    });
  }

  private async tryDirectLaunch(): Promise<void> {
    const launchUri = AppStorage.get<string>('launchUri');
    if (!launchUri || !this.currentRouter) {
      return;
    }
    // Clear launchUri so Index won't also try to load it
    AppStorage.setOrCreate('launchUri', '');
    try {
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
      const args: Record<string, string> = {
        'systemPath': launchUri,
        'sandboxPath': file,
        'saveTempPath': tempFile,
        'fileName': fileName
      };
      this.currentRouter.replaceUrl({ url: 'pages/PDFView', params: args });
    } catch (error) {
      hilog.error(0, 'PDFView', `Direct launch failed: ${error}`);
    }
  }

  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    hilog.fatal(0, 'PDFView', 'Ability onMemoryLevel, level: %{public}d', level);
  }

  // Re-entry guard so that the MAXIMIZE rect-change event triggered by our own
  // restoreWindowState() call doesn't end up double-applying waterfall.
  // (windowStateChanged's prevMode check already prevents loops for normal
  // interactive flows; this is a belt-and-suspenders for startup.)
  private suppressNextMaximizeReapply: boolean = false;
  // Some foldable 2in1 devices may convert "exit maximize+waterfall" into a
  // plain MAXIMIZE transition (drop waterfall first, keep maximized). Track an
  // in-flight recover() we trigger to avoid duplicate recover calls.
  private recoveringFromWaterfallExit: boolean = false;

  /**
   * Maximize the window. On foldable 2in1 devices in hover state, pass the
   * user's waterfall (瀑布流) preference via the API 22 `acrossDisplay`
   * parameter so the app spans both halves instead of being confined to one.
   * The call falls back to the API 12 signature on older devices.
   */
  private maximizeRespectingPreference(presentation: window.MaximizePresentation): void {
    if (!this.window) {
      return;
    }
    // acrossDisplay=true/false is only honored on foldable 2in1 devices; on
    // other devices it's a no-op per the API docs. If preferWaterfall is false
    // we pass `false` explicitly so that the device leaves any previously set
    // waterfall mode.
    this.window.maximize(presentation, this.preferWaterfall).catch(() => {
      this.window?.maximize(presentation).catch();
    });
  }

  /**
   * Updates the waterfall preference and, if the window is currently
   * maximized, applies it right away so the user sees the effect. Invoked from
   * the Settings dialog via the AppStorage-exposed callback.
   */
  setPreferWaterfall(enable: boolean): void {
    this.preferWaterfall = enable;
    AppStorage.setOrCreate('preferWaterfall', enable);
    try {
      this.preferences?.putSync('preferWaterfall', enable);
      this.preferences?.flushSync();
    } catch (error) {
      hilog.error(0, 'PDFView', 'Failed to save preferWaterfall. Cause: %{public}s', error);
    }
    if (!this.window) {
      return;
    }
    // Apply to the currently-maximized window so the toggle takes effect
    // immediately. If we're not maximized, the preference will be applied the
    // next time the window enters maximize via restoreWindowState or a fresh
    // MAXIMIZE rect-change event.
    try {
      const mode = (this.preferences?.getSync('maximizeMode', 'windowed') as string) ?? 'windowed';
      if (mode == 'windowed') {
        return;
      }
      const presentation = mode == 'full_screen'
        ? window.MaximizePresentation.ENTER_IMMERSIVE
        : window.MaximizePresentation.EXIT_IMMERSIVE;
      this.suppressNextMaximizeReapply = true;
      this.window.maximize(presentation, enable).catch(() => {
        // Ignore: API 22 fallback is unnecessary since this is user-initiated.
      });
    } catch (error) {
      hilog.error(0, 'PDFView', 'Failed to apply preferWaterfall. Cause: %{public}s', error);
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
          this.suppressNextMaximizeReapply = true;
          this.maximizeRespectingPreference(window.MaximizePresentation.ENTER_IMMERSIVE);
          break;
        case 'full_screen_window':
          this.suppressNextMaximizeReapply = true;
          this.maximizeRespectingPreference(window.MaximizePresentation.EXIT_IMMERSIVE);
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
        // Read the previous mode BEFORE we overwrite it so we can detect a
        // fresh windowed->maximized transition. The system also emits MAXIMIZE
        // when the user toggles waterfall from an already-maximized state
        // (e.g. via the system titlebar); in that case we must NOT reapply or
        // we'd fight the user and ping-pong between modes.
        const prevMode = (this.preferences.getSync('maximizeMode', 'windowed') as string) ?? 'windowed';
        const immersive = this.window.getImmersiveModeEnabledState();
        const newMode = immersive ? 'full_screen' : 'full_screen_window';
        this.preferences.putSync('maximizeMode', newMode);

        const wasWindowed = prevMode == 'windowed';
        if (this.suppressNextMaximizeReapply) {
          this.suppressNextMaximizeReapply = false;
        } else if (wasWindowed && this.preferWaterfall) {
          // Fresh maximize entry and the user prefers waterfall: apply it.
          // On non-2in1 / non-hover devices this is a harmless no-op.
          this.suppressNextMaximizeReapply = true;
          this.window.maximize(
            immersive ? window.MaximizePresentation.ENTER_IMMERSIVE : window.MaximizePresentation.EXIT_IMMERSIVE,
            true
          ).catch();
        } else if (!wasWindowed && this.preferWaterfall && prevMode == newMode && !this.recoveringFromWaterfallExit) {
          // UX fix: on some foldable 2in1 devices, pressing the titlebar
          // restore button while in maximize+waterfall first exits waterfall
          // and emits MAXIMIZE (still maximized). Convert that intermediate
          // state to real windowed mode so one click is enough.
          this.recoveringFromWaterfallExit = true;
          this.window.recover().catch(() => {
            this.recoveringFromWaterfallExit = false;
          });
        }
      } else if (options.reason == window.RectChangeReason.RECOVER) {
        this.preferences.putSync('maximizeMode', 'windowed');
        this.suppressNextMaximizeReapply = false;
        this.recoveringFromWaterfallExit = false;
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