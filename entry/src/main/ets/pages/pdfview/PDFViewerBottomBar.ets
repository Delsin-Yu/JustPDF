import {
  ButtonColorSemiTransparent,
  ContainerCfg,
  StyleIconButton,
  toVisibility
} from '../../components/UIComponents';

@ComponentV2
export struct PDFViewerBottomBar {
  @Param showControls: boolean = true;
  @Param pageFlipMode: 'side' | 'button' | 'extern' = 'side';
  @Param annotateMode: 'drag' | 'draw' | 'erase' = 'drag';
  @Param currentPageIndex: number = 0;
  @Param totalPageCount: number = 0;
  @Param onPrevPage: () => void = () => {};
  @Param onNextPage: () => void = () => {};

  // 当前页左侧补零，位数与总页数一致（如 12 页时显示 03/12）。
  private formatPageFraction(): string {
    const total: number = this.totalPageCount;
    const cur: number = this.currentPageIndex + 1;
    if (total <= 0) {
      return `${cur}/0`;
    }
    const width: number = total.toString().length;
    let curStr: string = cur.toString();
    while (curStr.length < width) {
      curStr = '0' + curStr;
    }
    return `${curStr}/${total}`;
  }

  build() {
    Row(ContainerCfg) {
      StyleIconButton({
        icon: $r('sys.symbol.chevron_backward'),
        iconSize: 22,
        alternateColor: ButtonColorSemiTransparent,
        onClickCallback: () => this.onPrevPage()
      })
        .visibility(toVisibility(this.pageFlipMode == 'button' || (this.pageFlipMode == 'side' && this.annotateMode != 'drag')))
      Text(this.formatPageFraction())
        .height(44)
        .padding({ left: 16, right: 16 })
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .constraintSize({ minWidth: 72 })
        .backgroundColor(ButtonColorSemiTransparent)
        .borderRadius(22)
        .alignSelf(ItemAlign.End)
        .visibility(toVisibility(this.totalPageCount > 0))
      StyleIconButton({
        icon: $r('sys.symbol.chevron_forward'),
        iconSize: 22,
        alternateColor: ButtonColorSemiTransparent,
        onClickCallback: () => this.onNextPage()
      })
        .visibility(toVisibility(this.pageFlipMode == 'button' || (this.pageFlipMode == 'side' && this.annotateMode != 'drag')))
    }
  }
}
