import {
  StyleButton,
  StyleIconBadgeButton,
  StyleIconButton,
  StyleText,
  toVisibility
} from '../../components/UIComponents';

@ComponentV2
export struct PDFViewerBottomBar {
  @Param showControls: boolean = true;
  @Param undoHistoryCount: number = 0;
  @Param redoHistoryCount: number = 0;
  @Param hasUnsavedStrokes: boolean = false;
  @Param pageFlipMode: 'side' | 'button' | 'extern' = 'side';
  @Param currentPageIndex: number = 0;
  @Param totalPageCount: number = 0;
  @Param onUndo: () => void = () => {};
  @Param onRedo: () => void = () => {};
  @Param onSave: () => void = () => {};
  @Param onPrevPage: () => void = () => {};
  @Param onNextPage: () => void = () => {};

  build() {
    Row() {
      StyleIconBadgeButton({
        icon: $r('sys.symbol.undo'),
        count: this.undoHistoryCount,
        onClickCallback: () => this.onUndo()
      }).visibility(toVisibility(this.showControls && (this.undoHistoryCount > 0 || this.redoHistoryCount > 0 || this.hasUnsavedStrokes)))
        .enabled(this.undoHistoryCount > 0)
        .opacity(this.undoHistoryCount > 0 ? 1.0 : 0.4)
      StyleIconBadgeButton({
        icon: $r('sys.symbol.redo'),
        count: this.redoHistoryCount,
        onClickCallback: () => this.onRedo()
      }).visibility(toVisibility(this.showControls && (this.undoHistoryCount > 0 || this.redoHistoryCount > 0 || this.hasUnsavedStrokes)))
        .enabled(this.redoHistoryCount > 0)
        .opacity(this.redoHistoryCount > 0 ? 1.0 : 0.4)
      StyleIconButton({
        icon: $r('sys.symbol.save'),
        onClickCallback: () => this.onSave()
      }).visibility(toVisibility(this.showControls && (this.undoHistoryCount > 0 || this.redoHistoryCount > 0 || this.hasUnsavedStrokes)))
        .enabled(this.hasUnsavedStrokes)
        .opacity(this.hasUnsavedStrokes ? 1.0 : 0.4)
      StyleButton({ text: '<', onClickCallback: () => this.onPrevPage() })
        .visibility(toVisibility(this.pageFlipMode == 'button'))
      StyleButton({ text: '>', onClickCallback: () => this.onNextPage() })
        .visibility(toVisibility(this.pageFlipMode == 'button'))
      StyleText({ text: `${this.currentPageIndex + 1}/${this.totalPageCount}` }).visibility(toVisibility(this.pageFlipMode != 'button'))
    }
  }
}
