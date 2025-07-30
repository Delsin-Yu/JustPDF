import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router, window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');

    let uri = want.uri;
    if (uri == null || uri == undefined) {
      return;
    }
    AppStorage.setOrCreate('launchUri', uri);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    let uri = want.uri;
    if (uri == null || uri == undefined) {
      return;
    }
    AppStorage.setOrCreate('launchUri', uri);
    router.clear();
    router.replaceUrl({ url: 'pages/Index' });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main applicationWindow is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    let dataPreferences = preferences.getPreferencesSync(this.context, { name: 'stagePersistence' });
    AppStorage.setOrCreate('windowStage', windowStage);
    AppStorage.setOrCreate('preferences', dataPreferences);
    windowStage.loadContent('pages/Index', null, (err) => {
      let applicationWindow = windowStage.getMainWindowSync();
      applicationWindow.setWindowDecorVisible(false);
      applicationWindow.on('windowRectChange', rectChangeOptions => {
        if (rectChangeOptions.reason == window.RectChangeReason.DRAG_START) {
          return;
        }
        dataPreferences.putSync('windowRect', rectChangeOptions.rect);
        if (rectChangeOptions.reason == window.RectChangeReason.MAXIMIZE) {
          dataPreferences.putSync('isMaximized', true);
        } else if (rectChangeOptions.reason == window.RectChangeReason.RECOVER) {
          dataPreferences.putSync('isMaximized', false);
        }
        dataPreferences.flushSync();
      });
      if (dataPreferences.hasSync('windowRect')) {
        let rect = dataPreferences.getSync('windowRect', {
          left: 0,
          top: 0,
          width: 0,
          height: 0
        }) as window.Rect;
        applicationWindow.resize(rect.width, rect.height);
        applicationWindow.moveWindowToGlobal(rect.left, rect.top);
      }
      if ((dataPreferences.getSync('isMaximized', false) as boolean)) {
        applicationWindow.maximize(window.MaximizePresentation.EXIT_IMMERSIVE)
      }
      AppStorage.setOrCreate('decorBarHeight', applicationWindow.getWindowDecorHeight());
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main applicationWindow is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}