import { LengthMetrics } from '@kit.ArkUI';
import { uiEffect } from '@kit.ArkGraphics2D';
import { ScrollSpinBox } from '../../components/ScrollSpinBox';
import { ButtonColor, ContainerPadding, StyleIconButton, toVisibility } from '../../components/UIComponents';
import { PDFMetronomeController } from './PDFMetronomeController';
import { SharedPanelBackgroundBlurRadius, SharedPanelBackgroundColor } from './PDFPanelVisualConstants';

const MetronomeBeatSpacing: Length = `10vp`;
const MetronomeSpinBoxSettleMs: number = 160;
const MetronomeWindowMargin: number = 16;
const MetronomeWindowWidth: number = 400;
export const MetronomeTotalWidth: number = MetronomeWindowWidth + MetronomeWindowMargin * 2;
export const FloatingMetronomeDefaultScale: number = 1;
const FloatingMetronomeMinScale: number = 0.35;
const FloatingMetronomeMaxScale: number = 1.5;
const FloatingMetronomeDragDistanceVp: number = 1;
const MetronomeHeaderGap: number = 10;
const MetronomeHeaderCloseButtonWidth: number = 60;
const MetronomeHeaderDragMaxWidth: Length = `calc(100% - ${MetronomeHeaderCloseButtonWidth + MetronomeHeaderGap}vp)`;
const MetronomeTempoDialogWidth: number = 260;
const MetronomeBeatButtonHeight: number = 44;

interface FloatingMetronomeOffset {
  x: number;
  y: number;
}

function clampFloatingMetronomeScale(scale: number): number {
  return Math.max(FloatingMetronomeMinScale, Math.min(FloatingMetronomeMaxScale, scale));
}

export function getFloatingMetronomeTotalWidth(scale: number): number {
  return MetronomeTotalWidth * clampFloatingMetronomeScale(scale);
}

@CustomDialog
struct TempoInputDialogBuilder {
  private controller: CustomDialogController;
  initialValue: string = '';
  onCancel: () => void = () => {
  };
  onConfirm: (value: number) => void = () => {
  };
  @State private tempoInputValue: string = '';

  aboutToAppear(): void {
    this.tempoInputValue = this.sanitizeTempoInput(this.initialValue);
  }

  private sanitizeTempoInput(value: string): string {
    return value.replace(/[^0-9]/g, '').slice(0, 3);
  }

  private trySubmitTempoInput(): void {
    const sanitizedValue = this.sanitizeTempoInput(this.tempoInputValue);
    const parsedValue = sanitizedValue === '' ? 0 : Number.parseInt(sanitizedValue, 10);
    const normalizedValue = Number.isNaN(parsedValue) ? 0 : parsedValue;
    const clampedValue = Math.max(0, Math.min(600, normalizedValue));

    if (normalizedValue !== clampedValue) {
      this.tempoInputValue = `${clampedValue}`;
      return;
    }

    this.controller.close();
    this.onConfirm(clampedValue);
  }

  private closeWithCancel(): void {
    this.controller.close();
    this.onCancel();
  }

  private closeWithConfirm(): void {
    this.trySubmitTempoInput();
  }

  build() {
    Column({ space: 14 }) {

      Text('设置速度')
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .width('100%')
        .textAlign(TextAlign.Start)

      TextInput({ text: this.tempoInputValue, placeholder: '144' })
        .type(InputType.Number)
        .enterKeyType(EnterKeyType.Done)
        .defaultFocus(true)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .placeholderColor('rgba(255, 255, 255, 0.38)')
        .backgroundColor('rgba(255, 255, 255, 0.08)')
        .borderRadius(14)
        .padding({
          left: 14,
          right: 14,
          top: 12,
          bottom: 12
        })
        .caretColor('#4DA6FF')
        .width('100%')
        .onChange((value: string) => {
          this.tempoInputValue = this.sanitizeTempoInput(value);
        })
        .onSubmit((_enterKey: EnterKeyType, _event: SubmitEvent) => {
          this.trySubmitTempoInput();
        })

      Row({ space: 8 }) {
        Button('取消')
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor('rgba(255, 255, 255, 0.12)')
          .onClick(() => this.closeWithCancel())

        Button('确定')
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .backgroundColor('rgba(77, 166, 255, 0.88)')
          .onClick(() => this.closeWithConfirm())
      }
      .width('100%')
    }
    .width(MetronomeTempoDialogWidth)
    .padding(16)
    .backgroundColor('rgba(12, 15, 21, 0.96)')
    .borderRadius(18)
    .border({ width: 1, color: 'rgba(255, 255, 255, 0.08)' })
    .shadow({ radius: 18, color: 'rgba(0, 0, 0, 0.28)', offsetY: 6 })
  }
}

@ComponentV2
export struct PDFMetronomePanelContent {
  @Param controller: PDFMetronomeController | undefined = undefined;
  @Param useDocked: boolean = false;
  @Param dockedTopOffsetVp: number = 0;
  @Param hostScale: number = FloatingMetronomeDefaultScale;
  @Param hostOffset: FloatingMetronomeOffset = { x: 0, y: 0 };
  @Param showDragHandle: boolean = true;
  @Event onInteraction: () => void = () => {
  };
  @Event onTouchStateChanged: (active: boolean) => void = (_active: boolean) => {
  };
  @Event onWindowAreaHeightChanged: (heightVp: number) => void = (_heightVp: number) => {
  };
  @Event onHostDragStart: () => void = () => {
  };
  @Event onHostDragUpdate: (event: GestureEvent) => void = (_event: GestureEvent) => {
  };
  @Event onHostDragEnd: () => void = () => {
  };
  @Event onHostPinchStart: () => void = () => {
  };
  @Event onHostPinchUpdate: (event: GestureEvent) => void = (_event: GestureEvent) => {
  };
  @Event onHostPinchEnd: () => void = () => {
  };
  @Event onClose: () => void = () => {
  };
  private tempoDialogOpen: boolean = false;
  tempoInputDialogController: CustomDialogController = new CustomDialogController({
    builder: TempoInputDialogBuilder()
  });
  private resumeMetronomeAfterInteraction: boolean = false;
  private activeSpinInteractionCount: number = 0;
  private readonly panelBackgroundBlurFilter: uiEffect.Filter =
    uiEffect.createFilter().blur(SharedPanelBackgroundBlurRadius);
  metronomeGridLayout: GridLayoutOptions = {
    regularSize: [1, 1],
    irregularIndexes: [6, 7, 8],
    onGetIrregularSizeByIndex: (): [number, number] => [1, 2]
  };

  private getBeatColor(beat: number): string {
    if (beat === (this.controller?.currentBeat ?? -1)) {
      return beat === 0 ? '#FF9F43' : '#4DA6FF';
    }
    return 'rgba(255, 255, 255, 0.12)';
  }

  private getBeatRowSizes(): number[] {
    switch (this.controller?.numerator ?? 0) {
      case 0:
        return [];
      case 8:
        return [4, 4];
      case 9:
        return [3, 3, 3];
      case 10:
        return [5, 5];
      case 11:
        return [6, 5];
      case 12:
        return [6, 6];
      case 13:
        return [7, 6];
      case 14:
        return [7, 7];
      case 15:
        return [5, 5, 5];
      case 16:
        return [4, 4, 4, 4];
      default:
        return [Math.max(1, this.controller?.numerator ?? 1)];
    }
  }

  private getBeatRows(): number[][] {
    const rows: number[][] = [];
    const rowSizes: number[] = this.getBeatRowSizes();
    let beatIndex: number = 0;

    for (let i = 0; i < rowSizes.length; i++) {
      const row: number[] = [];
      for (let j = 0; j < rowSizes[i]; j++) {
        row.push(beatIndex);
        beatIndex += 1;
      }
      rows.push(row);
    }

    return rows;
  }

  private getBeatLayoutVersion(): string {
    const numerator: number = this.controller?.numerator ?? 0;
    return `${numerator}-${this.getBeatRowSizes().join('-')}`;
  }

  private handleSpinInteractionStart(): void {
    this.activeSpinInteractionCount += 1;
    if (this.activeSpinInteractionCount > 1) {
      return;
    }

    this.resumeMetronomeAfterInteraction = this.controller?.isPlaying ?? false;
    if (this.resumeMetronomeAfterInteraction) {
      this.controller?.pauseForInteraction();
    }
  }

  private handleSpinInteractionEnd(): void {
    if (this.activeSpinInteractionCount <= 0) {
      return;
    }

    this.activeSpinInteractionCount -= 1;
    if (this.activeSpinInteractionCount > 0) {
      return;
    }

    if (this.tempoDialogOpen) {
      return;
    }

    if (this.resumeMetronomeAfterInteraction) {
      this.resumeMetronomeAfterInteraction = false;
      this.controller?.resumeAfterInteraction();
    }
  }

  private openTempoInputDialog(): void {
    if (this.tempoDialogOpen) {
      return;
    }

    this.tempoInputDialogController = new CustomDialogController({
      builder: TempoInputDialogBuilder({
        initialValue: `${this.controller?.bpm ?? 0}`,
        onCancel: () => this.handleTempoDialogClosed(),
        onConfirm: (value: number) => this.applyTempoInputValue(value)
      }),
      alignment: DialogAlignment.Center,
      autoCancel: true,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.38)',
      keyboardAvoidDistance: LengthMetrics.vp(16),
      cancel: () => this.handleTempoDialogClosed()
    });

    this.tempoDialogOpen = true;
    this.handleSpinInteractionStart();
    this.tempoInputDialogController.open();
  }

  private handleTempoDialogClosed(): void {
    if (!this.tempoDialogOpen) {
      return;
    }

    this.tempoDialogOpen = false;
    this.handleSpinInteractionEnd();
  }

  private applyTempoInputValue(value: number): void {
    this.controller?.setBpm(value);
    this.handleTempoDialogClosed();
  }

  build() {
    Column({ space: 14 }) {
          Row({ space: MetronomeHeaderGap }) {
            Row({ space: this.useDocked ? 0 : 10 }) {
              Column({ space: 3 }) {
                Row({ space: 3 }) {
                  ForEach([0, 1, 2, 3], (index: number) => {
                    Text('')
                      .width(4)
                      .height(4)
                      .borderRadius(2)
                      .backgroundColor('rgba(255, 255, 255, 0.26)')
                  }, (index: number) => `metronome-drag-grip-top-${index}`)
                }

                Row({ space: 3 }) {
                  ForEach([0, 1, 2, 3], (index: number) => {
                    Text('')
                      .width(4)
                      .height(4)
                      .borderRadius(2)
                      .backgroundColor('rgba(255, 255, 255, 0.16)')
                  }, (index: number) => `metronome-drag-grip-bottom-${index}`)
                }
              }
              .visibility(toVisibility(this.showDragHandle && !this.useDocked))

              Text('节拍器')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
            }
            .height('auto')
            .width('100%')
            .constraintSize({ maxWidth: MetronomeHeaderDragMaxWidth })
            .padding(ContainerPadding)
            .alignItems(VerticalAlign.Center)
            .borderRadius(10)
            .backgroundColor('rgba(255, 255, 255, 0.05)')
            .border({ width: 1, color: 'rgba(255, 255, 255, 0.06)' })
            .gesture(
              PanGesture({ fingers: 1, distance: FloatingMetronomeDragDistanceVp })
                .onActionStart((_event: GestureEvent) => {
                  if (this.useDocked || this.tempoDialogOpen) {
                    return;
                  }
                  this.onHostDragStart();
                })
                .onActionUpdate((event: GestureEvent) => {
                  if (this.useDocked || this.tempoDialogOpen) {
                    return;
                  }
                  this.onHostDragUpdate(event);
                })
                .onActionEnd((_event: GestureEvent) => {
                  if (this.useDocked || this.tempoDialogOpen) {
                    return;
                  }
                  this.onHostDragEnd();
                })
                .onActionCancel(() => {
                  if (this.useDocked || this.tempoDialogOpen) {
                    return;
                  }
                  this.onHostDragEnd();
                })
            )

            Button({ type: ButtonType.Normal }) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor([Color.White])
            }
            .width(MetronomeHeaderCloseButtonWidth)
            .height(LayoutPolicy.matchParent)
            .borderRadius(10)
            .backgroundColor('rgba(255, 255, 255, 0.16)')
            .onClick(() => this.onClose())
          }
          .width('100%')
          .hitTestBehavior(HitTestMode.Default)

          Grid(undefined, this.metronomeGridLayout) {
            GridItem() {
              Text('速度')
                .fontSize(12)
                .fontColor('rgba(255, 255, 255, 0.62)')
                .width('100%')
                .textAlign(TextAlign.Start)
            }

            GridItem() {
              Text('拍号')
                .fontSize(12)
                .fontColor('rgba(255, 255, 255, 0.62)')
                .width('100%')
                .textAlign(TextAlign.Start)
            }

            GridItem() {
              ScrollSpinBox({
                value: this.controller?.bpm ?? 120,
                canLoop: false,
                min: 0,
                max: 600,
                step: 1,
                valueFontSize: 30,
                debounceMs: MetronomeSpinBoxSettleMs,
                onValueChange: (value: number) => this.controller?.setBpm(value),
                onInteractionStart: () => this.handleSpinInteractionStart(),
                onInteractionEnd: () => this.handleSpinInteractionEnd(),
                onLongPress: () => this.openTempoInputDialog(),
                itemHeight: 30,
                gradientHeight: 35
              })
                .width('100%')
                .height(120)
                .padding({
                  left: 10,
                  right: 10,
                  top: 8,
                  bottom: 8
                })
                .borderRadius(16)
                .backgroundColor('rgba(255, 255, 255, 0.2)')
            }

            GridItem() {
              Row({ space: 6 }) {
                ScrollSpinBox({
                  value: this.controller?.numerator ?? 4,
                  canLoop: false,
                  min: 1,
                  max: 16,
                  step: 1,
                  valueFontSize: 28,
                  debounceMs: MetronomeSpinBoxSettleMs,
                  onValueChange: (value: number) => this.controller?.setNumerator(value),
                  onInteractionStart: () => this.handleSpinInteractionStart(),
                  onInteractionEnd: () => this.handleSpinInteractionEnd(),
                  itemHeight: 28,
                  gradientHeight: 35
                })
                  .layoutWeight(1)

                Divider()
                  .strokeWidth(2)
                  .vertical(true)
                  .color('rgba(255, 255, 255, 0.16)')
                  .rotate({ angleZ: 20 })

                ScrollSpinBox({
                  value: this.controller?.denominator ?? 4,
                  values: [2, 4, 8, 16],
                  canLoop: false,
                  valueFontSize: 28,
                  debounceMs: MetronomeSpinBoxSettleMs,
                  onValueChange: (value: number) => this.controller?.setDenominator(value),
                  onInteractionStart: () => this.handleSpinInteractionStart(),
                  onInteractionEnd: () => this.handleSpinInteractionEnd(),
                  itemHeight: 28,
                  gradientHeight: 35
                })
                  .layoutWeight(1)
              }
              .width('100%')
              .height(120)
              .padding({
                left: 10,
                right: 10,
                top: 8,
                bottom: 8
              })
              .borderRadius(16)
              .backgroundColor('rgba(255, 255, 255, 0.2)')
            }

            GridItem() {
              Row({ space: 6 }) {
                Button('-10')
                  .type(ButtonType.Capsule)
                  .flexGrow(1)
                  .height(34)
                  .fontSize(13)
                  .fontColor(Color.White)
                  .backgroundColor('rgba(255, 255, 255, 0.1)')
                  .visibility(toVisibility(!this.useDocked))
                  .onClick(() => this.controller?.adjustBpm(-10))

                Button('预设')
                  .type(ButtonType.Capsule)
                  .flexGrow(1)
                  .height(34)
                  .fontSize(13)
                  .width(this.useDocked ? '100%' : 'auto')
                  .fontColor(Color.White)
                  .backgroundColor('rgba(255, 255, 255, 0.1)')
                  .bindMenu(this.controller?.getBpmMenu() ?? [], {
                    backgroundColor: ButtonColor,
                    outlineColor: Color.Transparent,
                    placement: Placement.BottomRight
                  })

                Button('+10')
                  .type(ButtonType.Capsule)
                  .flexGrow(1)
                  .height(34)
                  .fontSize(13)
                  .fontColor(Color.White)
                  .backgroundColor('rgba(255, 255, 255, 0.1)')
                  .visibility(toVisibility(!this.useDocked))
                  .onClick(() => this.controller?.adjustBpm(+10))
              }
            }

            GridItem() {
              Button('预设')
                .type(ButtonType.Capsule)
                .width('100%')
                .height(34)
                .fontSize(13)
                .fontColor(Color.White)
                .backgroundColor('rgba(255, 255, 255, 0.1)')
                .bindMenu(this.controller?.getTimeSignatureMenu() ?? [], {
                  backgroundColor: ButtonColor,
                  outlineColor: Color.Transparent,
                  placement: Placement.BottomRight
                })
            }

            GridItem() {
              Text('拍点')
                .fontSize(12)
                .fontColor('rgba(255, 255, 255, 0.62)')
                .width('100%')
                .textAlign(TextAlign.Start)

            }

            GridItem() {
              Column({ space: MetronomeBeatSpacing }) {
                ForEach(this.getBeatRows(), (row: number[], rowIndex: number) => {
                  Row({ space: MetronomeBeatSpacing }) {
                    ForEach(row, (beat: number) => {
                      Stack() {
                        Text(`${beat + 1}`)
                          .fontSize(16)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(Color.White)
                      }
                      .layoutWeight(1)
                      .height(MetronomeBeatButtonHeight)
                      .borderRadius(14)
                      .backgroundColor(this.getBeatColor(beat))
                      .animation({ duration: 0 })
                      .border({
                        width: beat === 0 ? 2 : 1,
                        color: beat === 0 ? 'rgba(255, 159, 67, 0.45)' : 'rgba(255, 255, 255, 0.06)'
                      })
                    }, (beat: number) => `${this.getBeatLayoutVersion()}-${rowIndex}-${beat}`)
                  }
                  .width('100%')
                }, (row: number[], rowIndex: number) => `${this.getBeatLayoutVersion()}-${rowIndex}-${row.length}`)
              }
              .width('100%')

            }

            GridItem() {
              Button(this.controller?.isPlaying ?? false ? '停止' : '播放')
                .type(ButtonType.Capsule)
                .width('100%')
                .height(42)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .backgroundColor(this.controller?.isPlaying ?? false ? 'rgba(211, 84, 0, 0.82)' : 'rgba(77, 166, 255, 0.88)')
                .onClick(() => this.controller?.togglePlayback())
            }
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(12)
          .rowsGap(10)
          .height(LayoutPolicy.wrapContent)
          .width('100%')
    }
    .width(this.useDocked ? "100%" : MetronomeWindowWidth)
    .padding(16)
    .backgroundColor(SharedPanelBackgroundColor)
    .backgroundFilter(this.panelBackgroundBlurFilter)
    .borderRadius({
      topLeft: this.useDocked ? 0 : 18,
      topRight: this.useDocked ? 0 : 18,
      bottomLeft: 18,
      bottomRight: 18
    })
    .margin(this.useDocked ? 0 : ContainerPadding)
    .border({ width: 1, color: 'rgba(255, 255, 255, 0.07)' })
    .shadow({ radius: 16, color: 'rgba(0, 0, 0, 0.24)', offsetY: 4 })
    .align(Alignment.TopStart)
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -14 })))
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.onInteraction();
        this.onTouchStateChanged(true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.onTouchStateChanged(false);
      }
    })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.onWindowAreaHeightChanged(newValue.height as number);
    })
    .scale(this.useDocked ? { x: 1, y: 1 } : { x: this.hostScale, y: this.hostScale, centerX: 0, centerY: 0 })
    .offset(this.useDocked ? { x: 0, y: this.dockedTopOffsetVp } : this.hostOffset)
    .gesture(
      PinchGesture({ fingers: 2 })
        .onActionStart((_event: GestureEvent) => {
          if (this.tempoDialogOpen) {
            return;
          }
          this.onHostPinchStart();
        })
        .onActionUpdate((event: GestureEvent) => {
          if (this.tempoDialogOpen) {
            return;
          }
          this.onHostPinchUpdate(event);
        })
        .onActionEnd((_event: GestureEvent) => {
          if (this.tempoDialogOpen) {
            return;
          }
          this.onHostPinchEnd();
        })
        .onActionCancel(() => {
          if (this.tempoDialogOpen) {
            return;
          }
          this.onHostPinchEnd();
        })
    )
  }
}

@ComponentV2
export struct PDFMetronomePanel {
  @Param controller: PDFMetronomeController | undefined = undefined;
  @Param useDocked: boolean = false;
  @Param dockedTopOffsetVp: number = 0;
  @Param floatingMinYVp: number = 0;
  @Param initialFloatingScale: number = FloatingMetronomeDefaultScale;
  @Param floatingViewportWidthVp: number = 0;
  @Param floatingViewportHeightVp: number = 0;
  @Event onFloatingScaleChanged: (scale: number) => void = (_scale: number) => {
  };
  @Event onInteraction: () => void = () => {
  };
  @Event onWindowAreaHeightChanged: (heightVp: number) => void = (_heightVp: number) => {
  };
  @Local floatingScale: number = FloatingMetronomeDefaultScale;
  @Local floatingOffset: FloatingMetronomeOffset = { x: 0, y: 0 };
  private floatingDragStartOffset: FloatingMetronomeOffset = { x: 0, y: 0 };
  private pinchStartScale: number = FloatingMetronomeDefaultScale;
  private floatingPinchActive: boolean = false;
  private floatingWindowAreaWidthVp: number = MetronomeWindowWidth;
  private floatingWindowContentHeightVp: number = 0;

  aboutToAppear(): void {
    this.floatingScale = clampFloatingMetronomeScale(this.initialFloatingScale);
    this.pinchStartScale = this.floatingScale;
  }

  private getFloatingButtonScale(): number {
    if (!(this.controller?.isPlaying ?? false) || (this.controller?.currentBeat ?? -1) < 0) {
      return 1;
    }
    return this.controller?.floatingButtonPulseScale ?? 1;
  }

  private getFloatingButtonColor(isActive: boolean = true): string {
    if (!isActive || !(this.controller?.isPlaying ?? false) || (this.controller?.currentBeat ?? -1) < 0) {
      return 'rgba(35, 42, 53, 0.62)';
    }
    return this.controller?.floatingButtonColor ?? 'rgba(35, 42, 53, 0.62)';
  }

  private getFloatingButtonTransitionDurationMs(): number {
    return this.controller?.floatingButtonTransitionDurationMs ?? 0;
  }

  private updateFloatingScale(scale: number): void {
    const nextScale = clampFloatingMetronomeScale(scale);
    if (Math.abs(nextScale - this.floatingScale) < 0.001) {
      return;
    }
    this.floatingScale = nextScale;
    this.syncFloatingOffsetToBounds();
    this.onFloatingScaleChanged(nextScale);
  }

  private clampFloatingOffset(offset: FloatingMetronomeOffset): FloatingMetronomeOffset {
    if (this.useDocked) {
      return { x: 0, y: this.dockedTopOffsetVp };
    }

    const scaledWidthVp: number = this.floatingWindowAreaWidthVp * this.floatingScale;
    const scaledHeightVp: number = this.floatingWindowContentHeightVp * this.floatingScale;
    const minX: number = 0;
    const minY: number = this.floatingMinYVp;
    const maxX: number = this.floatingViewportWidthVp - scaledWidthVp - MetronomeWindowMargin;
    const maxY: number = this.floatingViewportHeightVp - scaledHeightVp - MetronomeWindowMargin;
    return {
      x: Math.max(minX, Math.min(offset.x, Math.max(minX, maxX))),
      y: Math.max(minY, Math.min(offset.y, Math.max(minY, maxY)))
    };
  }

  private getClampedFloatingOffset(): FloatingMetronomeOffset {
    return this.clampFloatingOffset(this.floatingOffset);
  }

  private syncFloatingOffsetToBounds(): void {
    const nextOffset = this.getClampedFloatingOffset();
    if (Math.abs(nextOffset.x - this.floatingOffset.x) < 0.001
      && Math.abs(nextOffset.y - this.floatingOffset.y) < 0.001) {
      return;
    }

    this.floatingOffset = nextOffset;
    this.floatingDragStartOffset = { x: nextOffset.x, y: nextOffset.y };
  }

  private handleFloatingWindowAreaChange(heightVp: number): void {
    if (Math.abs(heightVp - this.floatingWindowContentHeightVp) < 0.001) {
      return;
    }

    this.floatingWindowContentHeightVp = heightVp;
    this.onWindowAreaHeightChanged(heightVp);
    this.syncFloatingOffsetToBounds();
  }

  private handleFloatingDragStart(): void {
    if (this.useDocked) {
      return;
    }

    const clampedOffset = this.getClampedFloatingOffset();
    this.floatingOffset = clampedOffset;
    this.floatingDragStartOffset = { x: clampedOffset.x, y: clampedOffset.y };
  }

  private handleFloatingDragUpdate(event: GestureEvent): void {
    if (this.useDocked || this.floatingPinchActive) {
      return;
    }

    const visualDragScale: number = this.floatingScale;
    this.floatingOffset = this.clampFloatingOffset({
      x: this.floatingDragStartOffset.x + event.offsetX * visualDragScale,
      y: this.floatingDragStartOffset.y + event.offsetY * visualDragScale
    });
  }

  private handleFloatingDragEnd(): void {
    if (this.useDocked) {
      return;
    }

    const clampedOffset = this.getClampedFloatingOffset();
    this.floatingOffset = clampedOffset;
    this.floatingDragStartOffset = { x: clampedOffset.x, y: clampedOffset.y };
  }

  private handleFloatingPinchStart(): void {
    this.floatingPinchActive = true;
    this.pinchStartScale = this.floatingScale;
  }

  private handleFloatingPinchUpdate(event: GestureEvent): void {
    this.updateFloatingScale(this.pinchStartScale * event.scale);
  }

  private handleFloatingPinchEnd(): void {
    this.floatingPinchActive = false;
    this.pinchStartScale = this.floatingScale;
    this.syncFloatingOffsetToBounds();
  }

  build() {
    Column() {
      PDFMetronomePanelContent({
        controller: this.controller,
        useDocked: this.useDocked,
        dockedTopOffsetVp: this.dockedTopOffsetVp,
        hostScale: this.floatingScale,
        hostOffset: this.getClampedFloatingOffset(),
        showDragHandle: !this.useDocked,
        onInteraction: this.onInteraction,
        onWindowAreaHeightChanged: (heightVp: number) => this.handleFloatingWindowAreaChange(heightVp),
        onHostDragStart: () => this.handleFloatingDragStart(),
        onHostDragUpdate: (event: GestureEvent) => this.handleFloatingDragUpdate(event),
        onHostDragEnd: () => this.handleFloatingDragEnd(),
        onHostPinchStart: () => this.handleFloatingPinchStart(),
        onHostPinchUpdate: (event: GestureEvent) => this.handleFloatingPinchUpdate(event),
        onHostPinchEnd: () => this.handleFloatingPinchEnd(),
        onClose: () => this.controller?.closeWindow()
      })
        .visibility((this.controller?.showWindow ?? false) ? Visibility.Visible : Visibility.None)

      StyleIconButton({
        icon: $r('sys.symbol.clock'),
        alternateColor: this.getFloatingButtonColor(),
        backgroundAnimationDurationMs: this.getFloatingButtonTransitionDurationMs(),
        onClickCallback: () => {
          this.onInteraction();
          this.controller?.openWindow();
        }
      })
        .visibility((!(this.controller?.showWindow ?? false) && (this.controller?.isPlaying ?? false))
          ? Visibility.Visible
          : Visibility.None)
        .scale({
          x: this.getFloatingButtonScale(),
          y: this.getFloatingButtonScale(),
          centerX: 22,
          centerY: 22
        })
        .animation({ duration: this.getFloatingButtonTransitionDurationMs(), curve: Curve.EaseOut })
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.92, y: 0.92 })))
        .margin(ContainerPadding)
    }
  }
}
