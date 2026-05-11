import {
  ContainerCfg,
  StyleButton,
  StyleText,
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

  build() {
    Row(ContainerCfg) {
      StyleButton({ text: '<', onClickCallback: () => this.onPrevPage() })
        .visibility(toVisibility(this.pageFlipMode == 'button' || (this.pageFlipMode == 'side' && this.annotateMode != 'drag')))
      StyleButton({ text: '>', onClickCallback: () => this.onNextPage() })
        .visibility(toVisibility(this.pageFlipMode == 'button' || (this.pageFlipMode == 'side' && this.annotateMode != 'drag')))
      StyleText({ text: `${this.currentPageIndex + 1}/${this.totalPageCount}` }).visibility(toVisibility(this.pageFlipMode != 'button'))
    }
  }
}
