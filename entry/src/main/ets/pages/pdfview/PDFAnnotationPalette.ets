import { uiEffect } from '@kit.ArkGraphics2D';
import {
  SharedPanelBackgroundBlurRadius,
  SharedPanelBackgroundColor,
  SharedPanelControlHighlightColor
} from './PDFPanelVisualConstants';
import { PDFAnnotateMode } from './PDFViewerViewModel';

const BtnSize: number = 44;
const Gap: number = 6;
const Pad: number = 10;
const HandleW: number = 40;
const DragDistance: number = 1;

const GridW: number = 3 * BtnSize + 2 * Gap;
const GridH: number = 2 * BtnSize + Gap;
export const AnnotationPaletteContentWidth: number = HandleW + Gap + GridW + Pad * 2;
export const AnnotationPaletteContentHeight: number = GridH + Pad * 2;

interface FloatingPaletteOffset {
  x: number;
  y: number;
}

@ComponentV2
export struct PDFAnnotationPalette {
  @Param annotateMode: PDFAnnotateMode = 'draw';
  @Param undoCount: number = 0;
  @Param redoCount: number = 0;
  @Param hasUnsaved: boolean = false;
  @Param hostScale: number = 1.0;
  @Param hostOffset: FloatingPaletteOffset = { x: 0, y: 0 };
  @Param onSetMode: (mode: PDFAnnotateMode) => void = () => {};
  @Param onUndo: () => void = () => {};
  @Param onRedo: () => void = () => {};
  @Param onSave: () => void = () => {};
  @Param onClose: () => void = () => {};
  @Event onHostDragStart: () => void = () => {};
  @Event onHostDragUpdate: (event: GestureEvent) => void = () => {};
  @Event onHostDragEnd: () => void = () => {};
  @Event onHostPinchStart: () => void = () => {};
  @Event onHostPinchUpdate: (event: GestureEvent) => void = () => {};
  @Event onHostPinchEnd: () => void = () => {};
  @Event onTouchStateChanged: (active: boolean) => void = () => {};

  private readonly blurFilter: uiEffect.Filter =
    uiEffect.createFilter().blur(SharedPanelBackgroundBlurRadius);

  build() {
    Row() {
      Column({ space: 3 }) {
        Row({ space: 3 }) {
          Text('').width(4).height(4).borderRadius(2).backgroundColor('rgba(255, 255, 255, 0.26)')
          Text('').width(4).height(4).borderRadius(2).backgroundColor('rgba(255, 255, 255, 0.26)')
        }
        Row({ space: 3 }) {
          Text('').width(4).height(4).borderRadius(2).backgroundColor('rgba(255, 255, 255, 0.16)')
          Text('').width(4).height(4).borderRadius(2).backgroundColor('rgba(255, 255, 255, 0.16)')
        }
        Row({ space: 3 }) {
          Text('').width(4).height(4).borderRadius(2).backgroundColor('rgba(255, 255, 255, 0.26)')
          Text('').width(4).height(4).borderRadius(2).backgroundColor('rgba(255, 255, 255, 0.26)')
        }
        Row({ space: 3 }) {
          Text('').width(4).height(4).borderRadius(2).backgroundColor('rgba(255, 255, 255, 0.16)')
          Text('').width(4).height(4).borderRadius(2).backgroundColor('rgba(255, 255, 255, 0.16)')
        }
      }
      .width(HandleW)
      .height(GridH)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .borderRadius({ topLeft: 10, bottomLeft: 10 })
      .backgroundColor('rgba(255, 255, 255, 0.05)')
      .border({ width: 1, color: 'rgba(255, 255, 255, 0.06)' })
      .gesture(
        PanGesture({ fingers: 1, distance: DragDistance })
          .onActionStart(() => this.onHostDragStart())
          .onActionUpdate((event: GestureEvent) => this.onHostDragUpdate(event))
          .onActionEnd(() => this.onHostDragEnd())
          .onActionCancel(() => this.onHostDragEnd())
      )

      Blank().width(Gap)

      Column({ space: Gap }) {
        Row({ space: Gap }) {
          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.pencil_waveform')).fontSize(20).fontColor([Color.White])
          }
          .width(BtnSize).height(BtnSize).borderRadius(10)
          .backgroundColor(this.annotateMode === 'draw' ? SharedPanelControlHighlightColor : Color.Transparent)
          .onClick(() => this.onSetMode('draw'))

          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.eraser_line')).fontSize(20).fontColor([Color.White])
          }
          .width(BtnSize).height(BtnSize).borderRadius(10)
          .backgroundColor(this.annotateMode === 'erase' ? SharedPanelControlHighlightColor : Color.Transparent)
          .onClick(() => this.onSetMode('erase'))

          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([Color.White])
          }
          .width(BtnSize).height(BtnSize).borderRadius(10)
          .backgroundColor(Color.Transparent)
          .onClick(() => this.onClose())
        }

        Row({ space: Gap }) {
          Button({ type: ButtonType.Normal }) {
            Stack() {
              SymbolGlyph($r('sys.symbol.undo')).fontSize(20).fontColor([Color.White])
              if (this.undoCount > 0) {
                Text(`${this.undoCount}`)
                  .fontSize(9)
                  .fontColor(Color.White)
                  .fontWeight(FontWeight.Bold)
                  .textAlign(TextAlign.Center)
                  .width(16).height(16).borderRadius(8)
                  .backgroundColor('rgba(255, 132, 0, 0.9)')
                  .position({ x: BtnSize - 22, y: 2 })
              }
            }.width('100%').height('100%')
          }
          .width(BtnSize).height(BtnSize).borderRadius(10)
          .backgroundColor(Color.Transparent)
          .enabled(this.undoCount > 0).opacity(this.undoCount > 0 ? 1.0 : 0.35)
          .onClick(() => this.onUndo())

          Button({ type: ButtonType.Normal }) {
            Stack() {
              SymbolGlyph($r('sys.symbol.redo')).fontSize(20).fontColor([Color.White])
              if (this.redoCount > 0) {
                Text(`${this.redoCount}`)
                  .fontSize(9)
                  .fontColor(Color.White)
                  .fontWeight(FontWeight.Bold)
                  .textAlign(TextAlign.Center)
                  .width(16).height(16).borderRadius(8)
                  .backgroundColor('rgba(255, 132, 0, 0.9)')
                  .position({ x: BtnSize - 22, y: 2 })
              }
            }.width('100%').height('100%')
          }
          .width(BtnSize).height(BtnSize).borderRadius(10)
          .backgroundColor(Color.Transparent)
          .enabled(this.redoCount > 0).opacity(this.redoCount > 0 ? 1.0 : 0.35)
          .onClick(() => this.onRedo())

          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.save')).fontSize(20).fontColor([Color.White])
          }
          .width(BtnSize).height(BtnSize).borderRadius(10)
          .backgroundColor(Color.Transparent)
          .onClick(() => this.onSave())
        }
      }
    }
    .width(AnnotationPaletteContentWidth)
    .height(AnnotationPaletteContentHeight)
    .padding(Pad)
    .backgroundColor(SharedPanelBackgroundColor)
    .backgroundFilter(this.blurFilter)
    .borderRadius(16)
    .border({ width: 1, color: 'rgba(255, 255, 255, 0.07)' })
    .shadow({ radius: 12, color: 'rgba(0, 0, 0, 0.24)', offsetY: 4 })
    .margin(10)
    .align(Alignment.TopStart)
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.onTouchStateChanged(true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.onTouchStateChanged(false);
      }
    })
    .scale({ x: this.hostScale, y: this.hostScale, centerX: 0, centerY: 0 })
    .offset(this.hostOffset)
    .gesture(
      PinchGesture({ fingers: 2 })
        .onActionStart(() => this.onHostPinchStart())
        .onActionUpdate((event: GestureEvent) => this.onHostPinchUpdate(event))
        .onActionEnd(() => this.onHostPinchEnd())
        .onActionCancel(() => this.onHostPinchEnd())
    )
  }
}
