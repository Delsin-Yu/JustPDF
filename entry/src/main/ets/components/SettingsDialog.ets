import { ContainerWideCfg, ContainerWidePadding } from './UIComponents';

const LabelColor: ResourceColor = '#AAAAAA';

@CustomDialog
export struct SettingsDialogBuilder {
  private controller: CustomDialogController;
  @State showSlider: boolean = true;
  onSliderToggled: (show: boolean) => void = () => {};

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

      }
      .width('100%')
      .padding(20)

    }
    .margin(ContainerWidePadding)

  }
}
