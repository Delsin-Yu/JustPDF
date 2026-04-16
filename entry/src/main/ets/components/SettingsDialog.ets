import { display } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ContainerWideCfg, ContainerWidePadding } from './UIComponents';
import { WaterfallPreference } from '../common/WaterfallPreference';

const LabelColor: ResourceColor = '#AAAAAA';

@CustomDialog
export struct SettingsDialogBuilder {
  private controller: CustomDialogController;
  @State showSlider: boolean = true;
  @StorageLink('preferWaterfall') preferWaterfall: boolean = true;
  onSliderToggled: (show: boolean) => void = () => {};

  private shouldShowWaterfallSetting(): boolean {
    if (deviceInfo.deviceType != '2in1') {
      return false;
    }
    try {
      return display.isFoldable();
    } catch (_) {
      return false;
    }
  }

  build() {
    Column(ContainerWideCfg) {

      Text('设置')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .height(60)

      Column({ space: 20 }) {

        // 进度滑块
        Row() {
          Text('进度滑块')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(LabelColor)
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.showSlider })
            .onChange((isOn: boolean) => {
              this.showSlider = isOn;
              this.onSliderToggled(isOn);
            })
        }
        .width('100%')

        if (this.shouldShowWaterfallSetting()) {
          // 跨屏最大化 (瀑布流)：折叠屏 2in1 设备悬停态下让窗口最大化时横跨上下两半屏
          Row() {
            Column() {
              Text('瀑布模式')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(LabelColor)
                .width('100%')
              Text('在设备处于半折叠状态下，开启此选项后窗口全屏时能够横跨上下两半屏显示')
                .fontSize(12)
                .fontColor(LabelColor)
                .opacity(0.7)
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.preferWaterfall })
              .onChange((isOn: boolean) => {
                if (WaterfallPreference.setter) {
                  WaterfallPreference.setter(isOn);
                } else {
                  this.preferWaterfall = isOn;
                }
              })
          }
          .width('100%')
        }

      }
      .width('100%')
      .padding(20)

    }
    .margin(ContainerWidePadding)

  }
}
