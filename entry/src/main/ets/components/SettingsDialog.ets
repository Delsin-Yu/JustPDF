import { LengthMetrics, display } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ContainerWideCfg, ContainerWidePadding } from './UIComponents';
import { WaterfallPreference } from '../common/WaterfallPreference';

const AccentColor: ResourceColor = '#4DA6FF';
const ChipSelected: ResourceColor = AccentColor;
const ChipUnselected: ResourceColor = 'rgba(255, 255, 255, 0.1)';
const LabelColor: ResourceColor = '#AAAAAA';
const chipSpacing: LengthMetrics = LengthMetrics.vp(8);

@CustomDialog
export struct SettingsDialogBuilder {
  private controller: CustomDialogController;
  @State pageDisplayMode: 'single' | 'dual' | 'dualContinuous' | 'tri' | 'triContinuous' = 'single';
  @State pageFlipMode: 'side' | 'button' | 'extern' = 'side';
  @State showSlider: boolean = true;
  @StorageLink('preferWaterfall') preferWaterfall: boolean = true;
  onPageDisplayModeChanged: (mode: 'single' | 'dual' | 'dualContinuous' | 'tri' | 'triContinuous') => void = () => {};
  onPageFlipModeChanged: (mode: 'side' | 'button' | 'extern') => void = () => {};
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

        // 显示模式
        Column({ space: 8 }) {
          Text('显示模式')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(LabelColor)
            .width('100%')

          Flex({ wrap: FlexWrap.Wrap, space: { main: chipSpacing, cross: chipSpacing } }) {
            Text('单页')
              .fontSize(14).fontColor(Color.White)
              .fontWeight(this.pageDisplayMode == 'single' ? FontWeight.Bold : FontWeight.Normal)
              .height(34).padding({ left: 16, right: 16 }).borderRadius(17)
              .backgroundColor(this.pageDisplayMode == 'single' ? ChipSelected : ChipUnselected)
              .onClick(() => { this.pageDisplayMode = 'single'; this.onPageDisplayModeChanged('single'); })
            Text('双页')
              .fontSize(14).fontColor(Color.White)
              .fontWeight(this.pageDisplayMode == 'dual' ? FontWeight.Bold : FontWeight.Normal)
              .height(34).padding({ left: 16, right: 16 }).borderRadius(17)
              .backgroundColor(this.pageDisplayMode == 'dual' ? ChipSelected : ChipUnselected)
              .onClick(() => { this.pageDisplayMode = 'dual'; this.onPageDisplayModeChanged('dual'); })
            Text('双页连续')
              .fontSize(14).fontColor(Color.White)
              .fontWeight(this.pageDisplayMode == 'dualContinuous' ? FontWeight.Bold : FontWeight.Normal)
              .height(34).padding({ left: 16, right: 16 }).borderRadius(17)
              .backgroundColor(this.pageDisplayMode == 'dualContinuous' ? ChipSelected : ChipUnselected)
              .onClick(() => { this.pageDisplayMode = 'dualContinuous'; this.onPageDisplayModeChanged('dualContinuous'); })
            Text('三页')
              .fontSize(14).fontColor(Color.White)
              .fontWeight(this.pageDisplayMode == 'tri' ? FontWeight.Bold : FontWeight.Normal)
              .height(34).padding({ left: 16, right: 16 }).borderRadius(17)
              .backgroundColor(this.pageDisplayMode == 'tri' ? ChipSelected : ChipUnselected)
              .onClick(() => { this.pageDisplayMode = 'tri'; this.onPageDisplayModeChanged('tri'); })
            Text('三页连续')
              .fontSize(14).fontColor(Color.White)
              .fontWeight(this.pageDisplayMode == 'triContinuous' ? FontWeight.Bold : FontWeight.Normal)
              .height(34).padding({ left: 16, right: 16 }).borderRadius(17)
              .backgroundColor(this.pageDisplayMode == 'triContinuous' ? ChipSelected : ChipUnselected)
              .onClick(() => { this.pageDisplayMode = 'triContinuous'; this.onPageDisplayModeChanged('triContinuous'); })
          }.width('100%')
        }
        .width('100%')

        // 翻页模式
        Column({ space: 8 }) {
          Text('翻页模式')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(LabelColor)
            .width('100%')

          Flex({ wrap: FlexWrap.Wrap, space: { main: chipSpacing, cross: chipSpacing } }) {
            Text('屏侧翻页')
              .fontSize(14).fontColor(Color.White)
              .fontWeight(this.pageFlipMode == 'side' ? FontWeight.Bold : FontWeight.Normal)
              .height(34).padding({ left: 16, right: 16 }).borderRadius(17)
              .backgroundColor(this.pageFlipMode == 'side' ? ChipSelected : ChipUnselected)
              .onClick(() => { this.pageFlipMode = 'side'; this.onPageFlipModeChanged('side'); })
            Text('按钮翻页')
              .fontSize(14).fontColor(Color.White)
              .fontWeight(this.pageFlipMode == 'button' ? FontWeight.Bold : FontWeight.Normal)
              .height(34).padding({ left: 16, right: 16 }).borderRadius(17)
              .backgroundColor(this.pageFlipMode == 'button' ? ChipSelected : ChipUnselected)
              .onClick(() => { this.pageFlipMode = 'button'; this.onPageFlipModeChanged('button'); })
            Text('外设翻页')
              .fontSize(14).fontColor(Color.White)
              .fontWeight(this.pageFlipMode == 'extern' ? FontWeight.Bold : FontWeight.Normal)
              .height(34).padding({ left: 16, right: 16 }).borderRadius(17)
              .backgroundColor(this.pageFlipMode == 'extern' ? ChipSelected : ChipUnselected)
              .onClick(() => { this.pageFlipMode = 'extern'; this.onPageFlipModeChanged('extern'); })
          }.width('100%')
        }
        .width('100%')

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
              Text('跨屏最大化')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(LabelColor)
                .width('100%')
              Text('折叠屏 2in1 设备悬停态下，最大化时横跨上下两半屏（瀑布流模式）')
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
