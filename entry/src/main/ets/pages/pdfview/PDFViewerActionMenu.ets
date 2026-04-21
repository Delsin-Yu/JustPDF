import { SymbolGlyphModifier } from '@kit.ArkUI';
import { ButtonColor, ButtonColorSemiTransparent } from '../../components/UIComponents';

@ComponentV2
export struct PDFViewerActionMenu {
  @Param isExclusiveFullScreen: boolean = false;
  @Param showFullscreenButton: boolean = false;
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
  @Param onToggleTuner: () => void = () => {};

  private readonly tutorialIcon: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.questionmark_circle')).fontSize('20vp');
  private readonly settingsIcon: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.gearshape')).fontSize('20vp');
  private readonly shareIcon: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.share')).fontSize('20vp');
  private readonly metronomeIcon: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.clock')).fontSize('20vp');
  private readonly tunerIcon: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.mic')).fontSize('20vp');
  private readonly displayModeIcon: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.square_grid_2x2')).fontSize('20vp');
  private readonly flipModeIcon: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.rectangle_rotate')).fontSize('20vp');
  private readonly jumpIcon: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.arrow_right')).fontSize('20vp');
  private readonly annotateIcon: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.pencil_waveform')).fontSize('20vp');
  private readonly submenuArrowIcon: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.chevron_forward'))
    .fontSize('18vp')
    .padding('2vp');

  private getFullscreenIcon(): SymbolGlyphModifier {
    return new SymbolGlyphModifier(
      this.isExclusiveFullScreen ?
        $r('sys.symbol.arrow_down_right_and_arrow_up_left') :
        $r('sys.symbol.arrow_up_left_and_arrow_down_right')
    ).fontSize('20vp');
  }

  @Builder
  private buildLeafMenuItems(items: MenuElement[]) {
    ForEach(items, (item: MenuElement, index: number) => {
      MenuItem({
        content: item.value,
        startIcon: item.icon,
        symbolStartIcon: item.symbolIcon
      })
        .enabled(item.enabled ?? true)
        .onClick(() => item.action())
    }, (_item: MenuElement, index: number) => index.toString())
  }

  @Builder
  private buildSubMenu(items: MenuElement[]) {
    Menu() {
      this.buildLeafMenuItems(items)
    }
      .backgroundColor(ButtonColorSemiTransparent)
  }

  @Builder
  private buildActionMenu() {
    Menu() {
      MenuItemGroup() {
        MenuItem({
          content: '教程',
          symbolStartIcon: this.tutorialIcon
        })
          .onClick(() => this.onTutorial())

        MenuItem({
          content: '设置',
          symbolStartIcon: this.settingsIcon
        })
          .onClick(() => this.onSettings())

        if (this.showFullscreenButton) {
          MenuItem({
            content: this.isExclusiveFullScreen ? '窗口' : '全屏',
            symbolStartIcon: this.getFullscreenIcon()
          })
            .onClick(() => this.onToggleFullscreen())
        }

        MenuItem({
          content: '分享',
          symbolStartIcon: this.shareIcon
        })
          .onClick(() => this.onShare())

        MenuItem({
          content: '节拍器',
          symbolStartIcon: this.metronomeIcon
        })
          .onClick(() => this.onToggleMetronome())

        MenuItem({
          content: '调音器',
          symbolStartIcon: this.tunerIcon
        })
          .onClick(() => this.onToggleTuner())
      }

      MenuItemGroup() {
        MenuItem({
          content: `显示:${this.pageDisplayModeText}`,
          symbolStartIcon: this.displayModeIcon,
          symbolEndIcon: this.submenuArrowIcon,
          builder: (): void => this.buildSubMenu(this.displayModeMenu)
        })

        MenuItem({
          content: `翻页:${this.pageFlipModeText}`,
          symbolStartIcon: this.flipModeIcon,
          symbolEndIcon: this.submenuArrowIcon,
          builder: (): void => this.buildSubMenu(this.flipModeMenu)
        })

        MenuItem({
          content: '跳转',
          symbolStartIcon: this.jumpIcon,
          symbolEndIcon: this.submenuArrowIcon,
          builder: (): void => this.buildSubMenu(this.jumpMenu)
        })

        MenuItem({
          content: this.annotateModeText,
          symbolStartIcon: this.annotateIcon,
          symbolEndIcon: this.submenuArrowIcon,
          builder: (): void => this.buildSubMenu(this.annotateModeMenu)
        })
      }
    }
    .subMenuExpandingMode(SubMenuExpandingMode.SIDE_EXPAND)
  }

  build() {
    Column() {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.more'))
          .fontSize(20)
          .fontColor([Color.White])
          .fontWeight(FontWeight.Bold)
      }
        .id(this.shareButtonId)
        .width(44)
        .height(44)
        .hitTestBehavior(HitTestMode.Block)
        .monopolizeEvents(true)
        .backgroundColor(ButtonColorSemiTransparent)
        .bindMenu(this.buildActionMenu, {
          backgroundColor: ButtonColor,
          outlineColor: Color.Transparent,
          placement: Placement.Top
        })
    }
    .alignItems(HorizontalAlign.Start)
  }
}
