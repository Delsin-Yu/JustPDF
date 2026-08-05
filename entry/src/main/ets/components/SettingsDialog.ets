import { ContainerWideCfg, ContainerWidePadding } from './UIComponents';
import { PDFLinkVisualMode } from '../pages/pdfview/PDFViewerViewModel';

const LabelColor: ResourceColor = '#AAAAAA';
const HintColor: ResourceColor = '#888888';
const SegmentedButtonActiveColor: ResourceColor = 'rgba(77, 166, 255, 0.34)';
const SegmentedButtonInactiveColor: ResourceColor = 'rgba(255, 255, 255, 0.08)';

@CustomDialog
export struct SettingsDialogBuilder {
  private controller: CustomDialogController;
  @State showSlider: boolean = true;
  @State slideSensitivityUi: number = 5;
  @State linkVisualModeUi: PDFLinkVisualMode = 'fadeOnPageEnter';
  horizontalSlideSensitivity: number = 5;
  linkVisualMode: PDFLinkVisualMode = 'fadeOnPageEnter';
  onSliderToggled: (show: boolean) => void = () => {};
  onHorizontalSlideSensitivityChange: (level: number) => void = () => {};
  onLinkVisualModeChange: (mode: PDFLinkVisualMode) => void = () => {};

  private setLinkVisualMode(mode: PDFLinkVisualMode): void {
    this.linkVisualModeUi = mode;
    this.onLinkVisualModeChange(mode);
  }

  @Builder
  private LinkVisualModeButton(label: string, mode: PDFLinkVisualMode) {
    Button(label)
      .type(ButtonType.Capsule)
      .layoutWeight(1)
      .height(34)
      .fontSize(13)
      .fontWeight(this.linkVisualModeUi === mode ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(Color.White)
      .backgroundColor(this.linkVisualModeUi === mode ? SegmentedButtonActiveColor : SegmentedButtonInactiveColor)
      .border({
        width: 1,
        color: this.linkVisualModeUi === mode ? 'rgba(77, 166, 255, 0.58)' : 'rgba(255, 255, 255, 0.08)'
      })
      .onClick(() => this.setLinkVisualMode(mode))
  }

  build() {
    Column(ContainerWideCfg) {

      Text('设置')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .height(60)

      Column({ space: 20 }) {

        // 进度滑块
        Column({ space: 8 }) {
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

          Text('在页面右侧显示跳页滑块，便于在长文档中快速定位。')
            .fontSize(12)
            .fontColor(HintColor)
            .width('100%')
        }
        .width('100%')

        Column({ space: 8 }) {
          Text('PDF 跳转链接显示')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(LabelColor)
            .width('100%')

          Text('设置页面内跳转链接的显示方式，不影响链接的点击跳转。')
            .fontSize(12)
            .fontColor(HintColor)
            .width('100%')

          Row({ space: 8 }) {
            this.LinkVisualModeButton('隐藏', 'hidden')
            this.LinkVisualModeButton('进入后淡出', 'fadeOnPageEnter')
            this.LinkVisualModeButton('始终显示', 'always')
          }
          .width('100%')
        }
        .width('100%')

        Column({ space: 8 }) {
          Row() {
            Text('水平滑动灵敏度')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(LabelColor)
              .layoutWeight(1)
            Text(`${this.slideSensitivityUi}`)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(LabelColor)
          }
          .width('100%')

          Text('调整水平滑动与甩动翻页的灵敏度。数值越高越灵敏，越低越不易误触，中间为默认手感。')
            .fontSize(12)
            .fontColor(HintColor)
            .width('100%')

          Row() {
            Text('钝')
              .fontSize(12)
              .fontColor(HintColor)
            Slider({
              value: this.slideSensitivityUi,
              min: 0,
              max: 10,
              step: 1,
              style: SliderStyle.OutSet
            })
              .layoutWeight(1)
              .showSteps(true)
              .showTips(true)
              .onChange((value: number, _mode: SliderChangeMode) => {
                this.slideSensitivityUi = value;
                this.onHorizontalSlideSensitivityChange(value);
              })
            Text('敏')
              .fontSize(12)
              .fontColor(HintColor)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')

      }
      .width('100%')
      .padding(20)
      .onAppear(() => {
        this.slideSensitivityUi = this.horizontalSlideSensitivity;
        this.linkVisualModeUi = this.linkVisualMode;
      })

    }
    .margin(ContainerWidePadding)

  }
}
