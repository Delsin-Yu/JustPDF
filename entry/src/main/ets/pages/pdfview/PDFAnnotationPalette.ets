import { uiEffect } from '@kit.ArkGraphics2D';
import {
  SharedPanelBackgroundBlurRadius,
  SharedPanelBackgroundColor,
  SharedPanelControlHighlightColor
} from './PDFPanelVisualConstants';
import { PDFAnnotateMode } from './PDFViewerViewModel';
import {
  AnnotationColor,
  AnnotationColorPalette,
  CustomAnnotationColorId,
  DefaultAnnotationColor,
  DefaultCustomAnnotationColor
} from './PDFAnnotationColors';
import { PDFCustomColorPicker } from './PDFCustomColorPicker';

const BtnSize: number = 44;
const Gap: number = 6;
const Pad: number = 10;
const HandleW: number = 40;
const DragDistance: number = 1;

const GridW: number = 3 * BtnSize + 2 * Gap;
const GridH: number = 2 * BtnSize + Gap;
export const AnnotationPaletteContentWidth: number = HandleW + Gap + GridW + Pad * 2;
export const AnnotationPaletteContentHeight: number = GridH + Pad * 2;

// 迷你色板（预设颜色弹出层）尺寸——加大圆点与间距。
const ColorSwatchSize: number = 34;
const ColorSwatchInnerInset: number = 8;
const ColorSwatchGap: number = 10;
const ColorPickerPad: number = 12;

type ColorPopupMode = 'preset' | 'custom';

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
  @Param drawColor: AnnotationColor = DefaultAnnotationColor;
  @Param customDrawColor: AnnotationColor = DefaultCustomAnnotationColor;
  @Param recentCustomColors: AnnotationColor[] = [];
  @Param onSetMode: (mode: PDFAnnotateMode) => void = () => {};
  @Param onSelectDrawColor: (color: AnnotationColor) => void = () => {};
  @Param onSetCustomDrawColor: (color: AnnotationColor) => void = () => {};
  @Param onCommitRecentCustomColor: (color: AnnotationColor) => void = () => {};
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

  @Local showColorPopup: boolean = false;
  @Local colorPopupMode: ColorPopupMode = 'preset';

  private readonly blurFilter: uiEffect.Filter =
    uiEffect.createFilter().blur(SharedPanelBackgroundBlurRadius);

  // ----------- 颜色弹出（预设）-----------

  @Builder
  private buildColorSwatch(color: AnnotationColor) {
    Stack() {
      Text('')
        .width(ColorSwatchSize - ColorSwatchInnerInset)
        .height(ColorSwatchSize - ColorSwatchInnerInset)
        .borderRadius((ColorSwatchSize - ColorSwatchInnerInset) / 2)
        .backgroundColor(color.canvasColor)
    }
    .width(ColorSwatchSize)
    .height(ColorSwatchSize)
    .borderRadius(ColorSwatchSize / 2)
    .backgroundColor(color.id === this.drawColor.id ? 'rgba(255, 255, 255, 0.18)' : Color.Transparent)
    .border(color.id === this.drawColor.id
      ? { width: 1, color: 'rgba(255, 255, 255, 0.85)' }
      : { width: 1, color: 'rgba(255, 255, 255, 0.12)' })
    .onClick(() => {
      this.onSelectDrawColor(color);
      this.showColorPopup = false;
    })
  }

  @Builder
  private buildCustomColorButton() {
    Stack() {
      SymbolGlyph($r('sys.symbol.paintpalette_fill'))
        .fontSize(20)
        .fontColor(this.drawColor.id === CustomAnnotationColorId
          ? [this.drawColor.canvasColor]
          : ['rgba(255, 255, 255, 0.82)'])
    }
    .width(ColorSwatchSize)
    .height(ColorSwatchSize)
    .borderRadius(ColorSwatchSize / 2)
    .backgroundColor(this.drawColor.id === CustomAnnotationColorId
      ? 'rgba(255, 255, 255, 0.18)' : Color.Transparent)
    .border(this.drawColor.id === CustomAnnotationColorId
      ? { width: 1, color: 'rgba(255, 255, 255, 0.85)' }
      : { width: 1, color: 'rgba(255, 255, 255, 0.20)', style: BorderStyle.Dashed })
    .onClick(() => {
      // 切换到自定义模式：当前选中颜色变为自定义颜色存储里的值。
      this.onSelectDrawColor(this.customDrawColor);
      this.colorPopupMode = 'custom';
    })
  }

  @Builder
  private buildPresetPicker() {
    Column({ space: ColorSwatchGap }) {
      Row({ space: ColorSwatchGap }) {
        this.buildColorSwatch(AnnotationColorPalette[0]);
        this.buildColorSwatch(AnnotationColorPalette[1]);
        this.buildColorSwatch(AnnotationColorPalette[2]);
        this.buildColorSwatch(AnnotationColorPalette[3]);
      }
      Row({ space: ColorSwatchGap }) {
        this.buildColorSwatch(AnnotationColorPalette[4]);
        this.buildColorSwatch(AnnotationColorPalette[5]);
        this.buildColorSwatch(AnnotationColorPalette[6]);
        this.buildCustomColorButton();
      }
    }
    .padding(ColorPickerPad)
    .backgroundColor(SharedPanelBackgroundColor)
    .backgroundFilter(this.blurFilter)
    .borderRadius(16)
    .border({ width: 1, color: 'rgba(255, 255, 255, 0.07)' })
    .shadow({ radius: 12, color: 'rgba(0, 0, 0, 0.24)', offsetY: 4 })
  }

  @Builder
  private buildCustomPicker() {
    PDFCustomColorPicker({
      initialPdfColor: this.customDrawColor.pdfColor,
      recentColors: this.recentCustomColors,
      onColorChanged: (color: AnnotationColor) => {
        this.onSetCustomDrawColor(color);
      }
    })
  }

  @Builder
  private buildColorPopup() {
    if (this.colorPopupMode === 'custom') {
      this.buildCustomPicker();
    } else {
      this.buildPresetPicker();
    }
  }

  private handleDrawButtonClick(): void {
    if (this.annotateMode === 'draw') {
      // 同模式下点击：切换弹层显示，并恢复到预设视图。
      const willShow: boolean = !this.showColorPopup;
      this.colorPopupMode = 'preset';
      this.showColorPopup = willShow;
    } else {
      this.onSetMode('draw');
      this.colorPopupMode = 'preset';
      this.showColorPopup = true;
    }
  }

  private handleColorPopupVisibility(visible: boolean): void {
    if (!visible) {
      // 退出时：若处于自定义模式，提交当前自定义颜色到最近列表。
      // 注意：不要在此重置 colorPopupMode。
      // 弹层在切换内容（preset ↔ custom）时尺寸差异会触发 ArkUI 短暂回报 visible=false
      // 紧接着 true，若此刻把模式翻回 preset，会让较小的预设色板瞬时铺到原本是色相环的位置，
      // 致使紧随其后的触摸抬手事件被分发给左上角的橙色色块——表现为绘制出意料之外的橙色笔迹。
      // 真正切回 preset 由 handleDrawButtonClick 在用户主动点击画笔按钮时控制。
      if (this.colorPopupMode === 'custom' && this.drawColor.id === CustomAnnotationColorId) {
        this.onCommitRecentCustomColor(this.drawColor);
      }
      this.showColorPopup = false;
    } else {
      this.showColorPopup = true;
    }
  }

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
      .borderRadius(10)
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
            Stack() {
              SymbolGlyph($r('sys.symbol.pencil_waveform')).fontSize(20).fontColor([Color.White])
              Text('')
                .width(8).height(8).borderRadius(4)
                .backgroundColor(this.drawColor.canvasColor)
                .border({ width: 1, color: 'rgba(255, 255, 255, 0.9)' })
                .position({ x: BtnSize - 18, y: BtnSize - 18 })
            }.width('100%').height('100%')
          }
          .width(BtnSize).height(BtnSize).borderRadius(10)
          .backgroundColor(this.annotateMode === 'draw' ? SharedPanelControlHighlightColor : Color.Transparent)
          .onClick(() => this.handleDrawButtonClick())
          .bindPopup(this.showColorPopup, {
            builder: this.buildColorPopup,
            placement: Placement.Top,
            popupColor: Color.Transparent,
            mask: false,
            autoCancel: true,
            enableArrow: false,
            showInSubWindow: false,
            followTransformOfTarget: true,
            onStateChange: (event) => {
              this.handleColorPopupVisibility(event.isVisible);
            }
          })

          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.eraser_line')).fontSize(20).fontColor([Color.White])
          }
          .width(BtnSize).height(BtnSize).borderRadius(10)
          .backgroundColor(this.annotateMode === 'erase' ? SharedPanelControlHighlightColor : Color.Transparent)
          .onClick(() => {
            this.showColorPopup = false;
            this.onSetMode('erase');
          })

          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([Color.White])
          }
          .width(BtnSize).height(BtnSize).borderRadius(10)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showColorPopup = false;
            this.onClose();
          })
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
