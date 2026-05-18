import { ContainerWideCfg, ContainerWidePadding } from './UIComponents';

const LabelColor: ResourceColor = '#AAAAAA';
const HintColor: ResourceColor = '#888888';

@CustomDialog
export struct SettingsDialogBuilder {
  private controller: CustomDialogController;
  @State showSlider: boolean = true;
  @State slideSensitivityUi: number = 5;
  horizontalSlideSensitivity: number = 5;
  onSliderToggled: (show: boolean) => void = () => {};
  onHorizontalSlideSensitivityChange: (level: number) => void = () => {};

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

          Text('同时影响松手所需滑动距离与甩动翻页的容易程度；0 最钝，10 最敏，中间为默认手感。')
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
      })

    }
    .margin(ContainerWidePadding)

  }
}
