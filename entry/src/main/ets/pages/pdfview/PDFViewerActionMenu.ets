import { deviceInfo } from '@kit.BasicServicesKit';
import { ButtonColor, ButtonColorSemiTransparent, ContainerSpacing, StyleIconButton } from '../../components/UIComponents';

@ComponentV2
export struct PDFViewerActionMenu {
  @Param menuExpanded: boolean = false;
  @Param isExclusiveFullScreen: boolean = false;
  @Param pageDisplayModeText: string = '';
  @Param pageFlipModeText: string = '';
  @Param annotateModeText: string = '';
  @Param shareButtonId: string = '';
  @Param displayModeMenu: MenuElement[] = [];
  @Param flipModeMenu: MenuElement[] = [];
  @Param jumpMenu: MenuElement[] = [];
  @Param annotateModeMenu: MenuElement[] = [];
  @Param onTutorial: () => void = () => {};
  @Param onSettings: () => void = () => {};
  @Param onToggleFullscreen: () => void = () => {};
  @Param onShare: () => void = () => {};
  @Param onToggleMetronome: () => void = () => {};
  @Param onToggleMenu: () => void = () => {};

  build() {
    Column({ space: ContainerSpacing }) {
      if (this.menuExpanded) {
        Row({ space: ContainerSpacing }) {
          // 左列：通用操作
          Column({ space: ContainerSpacing }) {
            StyleIconButton({
              icon: $r('sys.symbol.questionmark_circle'),
              label: '教程',
              onClickCallback: () => this.onTutorial()
            }).transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 })))

            StyleIconButton({
              icon: $r('sys.symbol.gearshape'),
              label: '设置',
              onClickCallback: () => this.onSettings()
            }).transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 })))

            if (deviceInfo.deviceType != 'phone') {
              StyleIconButton({
                icon: this.isExclusiveFullScreen ? $r('sys.symbol.arrow_down_right_and_arrow_up_left') : $r('sys.symbol.arrow_up_left_and_arrow_down_right'),
                label: this.isExclusiveFullScreen ? '窗口' : '全屏',
                onClickCallback: () => this.onToggleFullscreen()
              }).transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 })))
            }

            StyleIconButton({
              icon: $r('sys.symbol.share'),
              label: '分享',
              onClickCallback: () => this.onShare()
            }).transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 })))

            StyleIconButton({
              icon: $r('sys.symbol.clock'),
              label: '节拍器',
              onClickCallback: () => this.onToggleMetronome()
            }).transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 })))
          }
          .alignItems(HorizontalAlign.Start)

          // 右列：视图与交互模式（包含较长标签）
          Column({ space: ContainerSpacing }) {
            StyleIconButton({
              icon: $r('sys.symbol.square_grid_2x2'),
              label: `显示:${this.pageDisplayModeText}`,
              menuElement: this.displayModeMenu,
              menuPlacement: Placement.RightBottom
            }).transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 })))

            StyleIconButton({
              icon: $r('sys.symbol.rectangle_rotate'),
              label: `翻页:${this.pageFlipModeText}`,
              menuElement: this.flipModeMenu,
              menuPlacement: Placement.RightBottom
            }).transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 })))

            StyleIconButton({
              icon: $r('sys.symbol.arrow_right'),
              label: '跳转',
              menuElement: this.jumpMenu,
              menuPlacement: Placement.RightBottom
            }).transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 })))

            StyleIconButton({
              icon: $r('sys.symbol.pencil_waveform'),
              label: this.annotateModeText,
              menuElement: this.annotateModeMenu,
              menuPlacement: Placement.RightBottom
            }).transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 })))
          }
          .alignItems(HorizontalAlign.Start)
        }
      }

      StyleIconButton({
        icon: this.menuExpanded ? $r('sys.symbol.xmark') : $r('sys.symbol.more'),
        alternateColor: this.menuExpanded ? ButtonColor : ButtonColorSemiTransparent,
        onClickCallback: () => this.onToggleMenu()
      }).id(this.shareButtonId)
    }
    .alignItems(HorizontalAlign.Start)
  }
}
