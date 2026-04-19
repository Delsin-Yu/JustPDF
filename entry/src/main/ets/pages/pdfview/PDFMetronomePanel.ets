import { LengthMetrics } from '@kit.ArkUI';
import { ScrollSpinBox } from '../../components/ScrollSpinBox';
import { ButtonColor, ContainerPadding, StyleIconButton } from '../../components/UIComponents';
import { PDFMetronomeController } from './PDFMetronomeController';

const MetronomeBeatSpacing: Length = `10vp`;
const MetronomeSpinBoxSettleMs: number = 160;
const MetronomeWindowMargin: number = 16;
const MetronomeWindowWidth: number = 400;
export const MetronomeTotalWidth: number = MetronomeWindowWidth + MetronomeWindowMargin * 2;
export const FloatingMetronomeDefaultScale: number = 0.5;
const FloatingMetronomeMinScale: number = 0.35;
const FloatingMetronomeMaxScale: number = 1.5;
const MetronomeTempoDialogWidth: number = 260;
const MetronomeBeatButtonHeight: number = 44;

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
export struct PDFMetronomePanel {
  @Param controller: PDFMetronomeController | undefined = undefined;
  @Param useDocked: boolean = false;
  @Param initialFloatingScale: number = FloatingMetronomeDefaultScale;
  @Event onFloatingScaleChanged: (scale: number) => void = (_scale: number) => {
  };
  @Local floatingScale: number = FloatingMetronomeDefaultScale;
  private tempoDialogOpen: boolean = false;
  tempoInputDialogController: CustomDialogController = new CustomDialogController({
    builder: TempoInputDialogBuilder()
  });
  private resumeMetronomeAfterInteraction: boolean = false;
  private activeSpinInteractionCount: number = 0;
  private pinchStartScale: number = FloatingMetronomeDefaultScale;
  metronomeGridLayout: GridLayoutOptions = {
    regularSize: [1, 1],
    irregularIndexes: [6, 7, 8],
    onGetIrregularSizeByIndex: (): [number, number] => [1, 2]
  };

  aboutToAppear(): void {
    this.floatingScale = clampFloatingMetronomeScale(this.initialFloatingScale);
    this.pinchStartScale = this.floatingScale;
  }

  private getBeatColor(beat: number): string {
    if (beat === (this.controller?.currentBeat ?? -1)) {
      return beat === 0 ? '#FF9F43' : '#4DA6FF';
    }
    return 'rgba(255, 255, 255, 0.12)';
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

  private updateFloatingScale(scale: number): void {
    const nextScale = clampFloatingMetronomeScale(scale);
    if (Math.abs(nextScale - this.floatingScale) < 0.001) {
      return;
    }
    this.floatingScale = nextScale;
    this.onFloatingScaleChanged(nextScale);
  }

  private handleFloatingPinchStart(): void {
    this.pinchStartScale = this.floatingScale;
  }

  private handleFloatingPinchUpdate(event: GestureEvent): void {
    this.updateFloatingScale(this.pinchStartScale * event.scale);
  }

  private handleFloatingPinchEnd(): void {
    this.pinchStartScale = this.floatingScale;
  }

  build() {
    Stack() {
      if (this.controller?.showWindow ?? false) {
        Column({ space: 14 }) {
          Row() {
            Text('节拍器')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            Blank()
            Button({ type: ButtonType.Capsule }) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor([Color.White])
            }
            .width(60)
            .height(28)
            .backgroundColor('rgba(255, 255, 255, 0.16)')
            .onClick(() => this.controller?.closeWindow())
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
                if (!this.useDocked) {
                  Button('-10')
                    .type(ButtonType.Capsule)
                    .flexGrow(1)
                    .height(34)
                    .fontSize(13)
                    .fontColor(Color.White)
                    .backgroundColor('rgba(255, 255, 255, 0.1)')
                    .onClick(() => this.controller?.adjustBpm(-10))
                }

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

                if (!this.useDocked) {
                  Button('+10')
                    .type(ButtonType.Capsule)
                    .flexGrow(1)
                    .height(34)
                    .fontSize(13)
                    .fontColor(Color.White)
                    .backgroundColor('rgba(255, 255, 255, 0.1)')
                    .onClick(() => this.controller?.adjustBpm(+10))
                }
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
        .backgroundColor('rgba(8, 10, 14, 0.78)')
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
        .scale(this.useDocked ? { x: 1, y: 1 } : { x: this.floatingScale, y: this.floatingScale, centerX: 0, centerY: 0 })
        .gesture(
          PinchGesture({ fingers: 2 })
            .onActionStart((_event: GestureEvent) => this.handleFloatingPinchStart())
            .onActionUpdate((event: GestureEvent) => this.handleFloatingPinchUpdate(event))
            .onActionEnd((_event: GestureEvent) => this.handleFloatingPinchEnd())
            .onActionCancel(() => this.handleFloatingPinchEnd())
        )
      }

      if (!(this.controller?.showWindow ?? false) && (this.controller?.isPlaying ?? false)) {
        StyleIconButton({
          icon: $r('sys.symbol.clock'),
          alternateColor: this.getFloatingButtonColor(),
          backgroundAnimationDurationMs: this.getFloatingButtonTransitionDurationMs(),
          onClickCallback: () => this.controller?.openWindow()
        })
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
    .alignContent(Alignment.TopStart)
  }
}
