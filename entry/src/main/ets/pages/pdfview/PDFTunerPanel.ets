import { ScrollSpinBox } from '../../components/ScrollSpinBox';
import { ContainerPadding, toVisibility } from '../../components/UIComponents';

const TunerWindowMargin: number = 16;
const TunerWindowWidth: number = 360;
export const TunerTotalWidth: number = TunerWindowWidth + TunerWindowMargin * 2;
export const FloatingTunerDefaultScale: number = 1;
const FloatingTunerMinScale: number = 0.4;
const FloatingTunerMaxScale: number = 1.6;
const FloatingTunerDragDistanceVp: number = 1;
const TunerHeaderGap: number = 10;
const TunerHeaderCloseButtonWidth: number = 60;
const TunerHeaderDragMaxWidth: Length = `calc(100% - ${TunerHeaderCloseButtonWidth + TunerHeaderGap}vp)`;
const TunerDefaultOffsetX: number = 24;
const TunerDefaultOffsetY: number = 112;
const TunerMeterSegments: number = 11;

interface FloatingTunerOffset {
  x: number;
  y: number;
}

function clampFloatingTunerScale(scale: number): number {
  return Math.max(FloatingTunerMinScale, Math.min(FloatingTunerMaxScale, scale));
}

export function getFloatingTunerTotalWidth(scale: number): number {
  return TunerTotalWidth * clampFloatingTunerScale(scale);
}

@ComponentV2
export struct PDFTunerPanelContent {
  @Param useDocked: boolean = false;
  @Param dockedTopOffsetVp: number = 0;
  @Param hostScale: number = FloatingTunerDefaultScale;
  @Param hostOffset: FloatingTunerOffset = { x: TunerDefaultOffsetX, y: TunerDefaultOffsetY };
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
  @Local mockDetectedNote: string = 'A4';
  @Local mockDetuneCents: number = 3;
  @Local mockReferenceHz: number = 440;
  @Local mockModeIndex: number = 0;
  @Local mockSelectedStringIndex: number = 0;
  @Local mockSensitivity: number = 2;
  @Local mockMonitoringEnabled: boolean = true;
  @Local mockHoldEnabled: boolean = false;

  private getModeOptions(): string[] {
    return ['自动', '吉他', '尤克里里'];
  }

  private getStringOptions(): string[] {
    switch (this.mockModeIndex) {
      case 1:
        return ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'];
      case 2:
        return ['G4', 'C4', 'E4', 'A4'];
      default:
        return ['C3', 'D3', 'E3', 'F3', 'G3', 'A3'];
    }
  }

  private clampStringIndex(): void {
    const optionsLength: number = this.getStringOptions().length;
    if (optionsLength <= 0) {
      this.mockSelectedStringIndex = 0;
      return;
    }

    if (this.mockSelectedStringIndex >= optionsLength) {
      this.mockSelectedStringIndex = optionsLength - 1;
    }
  }

  private selectMode(index: number): void {
    if (this.mockModeIndex === index) {
      return;
    }

    this.mockModeIndex = index;
    this.clampStringIndex();
    this.mockDetectedNote = this.getStringOptions()[this.mockSelectedStringIndex] ?? 'A4';
  }

  private selectString(index: number): void {
    this.mockSelectedStringIndex = index;
    this.mockDetectedNote = this.getStringOptions()[index] ?? this.mockDetectedNote;
    const centsPattern: number[] = [-18, -9, -3, 0, 4, 11];
    this.mockDetuneCents = centsPattern[index % centsPattern.length];
  }

  private adjustMockDetune(delta: number): void {
    this.mockDetuneCents = Math.max(-50, Math.min(50, this.mockDetuneCents + delta));
  }

  private setMockDetune(value: number): void {
    this.mockDetuneCents = Math.max(-50, Math.min(50, value));
  }

  private getDetuneSummary(): string {
    if (Math.abs(this.mockDetuneCents) <= 1) {
      return '音高稳定';
    }
    return this.mockDetuneCents > 0 ? '略高' : '略低';
  }

  private getDetuneColor(): string {
    if (Math.abs(this.mockDetuneCents) <= 4) {
      return '#42D392';
    }
    if (Math.abs(this.mockDetuneCents) <= 12) {
      return '#FFB347';
    }
    return '#FF7A7A';
  }

  private getMeterSegmentColor(index: number): string {
    const centeredIndex: number = Math.floor(TunerMeterSegments / 2);
    const activeIndex: number = Math.max(0,
      Math.min(TunerMeterSegments - 1, Math.round((this.mockDetuneCents + 50) / 100 * (TunerMeterSegments - 1))));
    if (index === centeredIndex) {
      return Math.abs(this.mockDetuneCents) <= 4 ? '#42D392' : 'rgba(255, 255, 255, 0.16)';
    }
    if ((this.mockDetuneCents < 0 && index >= activeIndex && index < centeredIndex)
      || (this.mockDetuneCents > 0 && index <= activeIndex && index > centeredIndex)) {
      return this.getDetuneColor();
    }
    return 'rgba(255, 255, 255, 0.12)';
  }

  @Builder
  private buildCapsuleButton(label: string, isActive: boolean, onClick: () => void, height: number = 34,
    fillWidth: boolean = false) {
    Button(label)
      .type(ButtonType.Capsule)
      .height(height)
      .width(fillWidth ? '100%' : 'auto')
      .fontSize(13)
      .fontWeight(isActive ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(Color.White)
      .backgroundColor(isActive ? 'rgba(77, 166, 255, 0.28)' : 'rgba(255, 255, 255, 0.1)')
      .border({ width: 1, color: isActive ? 'rgba(77, 166, 255, 0.45)' : 'rgba(255, 255, 255, 0.05)' })
      .onClick(onClick)
  }

  build() {
    Column({ space: 14 }) {
          Row({ space: TunerHeaderGap }) {
            Row({ space: this.useDocked ? 0 : 10 }) {
              Column({ space: 3 }) {
                Row({ space: 3 }) {
                  ForEach([0, 1, 2, 3], (index: number) => {
                    Text('')
                      .width(4)
                      .height(4)
                      .borderRadius(2)
                      .backgroundColor('rgba(255, 255, 255, 0.26)')
                  }, (index: number) => `tuner-drag-grip-top-${index}`)
                }

                Row({ space: 3 }) {
                  ForEach([0, 1, 2, 3], (index: number) => {
                    Text('')
                      .width(4)
                      .height(4)
                      .borderRadius(2)
                      .backgroundColor('rgba(255, 255, 255, 0.16)')
                  }, (index: number) => `tuner-drag-grip-bottom-${index}`)
                }
              }
              .visibility(toVisibility(this.showDragHandle && !this.useDocked))

              Text('调音器')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
            }
            .height('auto')
            .width('100%')
            .constraintSize({ maxWidth: TunerHeaderDragMaxWidth })
            .padding(ContainerPadding)
            .alignItems(VerticalAlign.Center)
            .borderRadius(10)
            .backgroundColor('rgba(255, 255, 255, 0.05)')
            .border({ width: 1, color: 'rgba(255, 255, 255, 0.06)' })
            .gesture(
              PanGesture({ fingers: 1, distance: FloatingTunerDragDistanceVp })
                .onActionStart((_event: GestureEvent) => {
                  if (this.useDocked) {
                    return;
                  }
                  this.onHostDragStart();
                })
                .onActionUpdate((event: GestureEvent) => {
                  if (this.useDocked) {
                    return;
                  }
                  this.onHostDragUpdate(event);
                })
                .onActionEnd((_event: GestureEvent) => {
                  if (this.useDocked) {
                    return;
                  }
                  this.onHostDragEnd();
                })
                .onActionCancel(() => {
                  if (this.useDocked) {
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
            .width(TunerHeaderCloseButtonWidth)
            .height(LayoutPolicy.matchParent)
            .borderRadius(10)
            .backgroundColor('rgba(255, 255, 255, 0.16)')
            .onClick(() => this.onClose())
          }
          .width('100%')
          .hitTestBehavior(HitTestMode.Default)

          Column({ space: 12 }) {
            Column({ space: 4 }) {
              Text(this.mockDetectedNote)
                .fontSize(40)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)

              Text(`${this.mockDetuneCents > 0 ? '+' : ''}${this.mockDetuneCents} cents`)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.getDetuneColor())

              Text(this.getDetuneSummary())
                .fontSize(12)
                .fontColor('rgba(255, 255, 255, 0.54)')
            }
            .width('100%')
            .padding({ top: 6, bottom: 6 })
            .alignItems(HorizontalAlign.Center)

            Column({ space: 8 }) {
              Row({ space: 6 }) {
                Text('-50')
                  .fontSize(11)
                  .fontColor('rgba(255, 255, 255, 0.4)')

                Blank().layoutWeight(1)

                Text('0')
                  .fontSize(11)
                  .fontColor('rgba(255, 255, 255, 0.52)')

                Blank().layoutWeight(1)

                Text('+50')
                  .fontSize(11)
                  .fontColor('rgba(255, 255, 255, 0.4)')
              }
              .width('100%')

              Row({ space: 6 }) {
                ForEach(Array.from({ length: TunerMeterSegments }, (_value: number, index: number) => index),
                  (index: number) => {
                    Column() {}
                      .layoutWeight(1)
                      .height(index === Math.floor(TunerMeterSegments / 2) ? 36 : 24)
                      .borderRadius(6)
                      .backgroundColor(this.getMeterSegmentColor(index))
                  }, (index: number) => `tuner-meter-${index}`)
              }
              .width('100%')

              Row({ space: 8 }) {
                this.buildCapsuleButton('-5c', false, () => this.adjustMockDetune(-5))
                this.buildCapsuleButton('居中', Math.abs(this.mockDetuneCents) <= 1, () => this.setMockDetune(0))
                this.buildCapsuleButton('+5c', false, () => this.adjustMockDetune(5))
              }
              .width('100%')
            }
            .padding(14)
            .borderRadius(18)
            .backgroundColor('rgba(255, 255, 255, 0.08)')
            .border({ width: 1, color: 'rgba(255, 255, 255, 0.05)' })

            Column({ space: 8 }) {
              Row() {
                Text('参考频率')
                  .fontSize(12)
                  .fontColor('rgba(255, 255, 255, 0.62)')

                Blank()

                Text(`${this.mockReferenceHz} Hz`)
                  .fontSize(12)
                  .fontColor('rgba(255, 255, 255, 0.46)')
              }
              .width('100%')

              ScrollSpinBox({
                value: this.mockReferenceHz,
                canLoop: false,
                min: 430,
                max: 450,
                step: 1,
                valueFontSize: 28,
                debounceMs: 100,
                onValueChange: (value: number) => {
                  this.mockReferenceHz = value;
                },
                itemHeight: 26,
                gradientHeight: 32
              })
                .width('100%')
                .height(96)
                .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                .borderRadius(16)
                .backgroundColor('rgba(255, 255, 255, 0.12)')
            }

            Column({ space: 8 }) {
              Text('模式')
                .fontSize(12)
                .fontColor('rgba(255, 255, 255, 0.62)')
                .width('100%')
                .textAlign(TextAlign.Start)

              Row({ space: 8 }) {
                ForEach(this.getModeOptions(), (label: string, index: number) => {
                  Column() {
                    this.buildCapsuleButton(label, this.mockModeIndex === index, () => this.selectMode(index), 34, true)
                  }
                    .layoutWeight(1)
                }, (label: string) => `tuner-mode-${label}`)
              }
              .width('100%')
            }

            Column({ space: 8 }) {
              Text('弦位预设')
                .fontSize(12)
                .fontColor('rgba(255, 255, 255, 0.62)')
                .width('100%')
                .textAlign(TextAlign.Start)

              Grid() {
                ForEach(this.getStringOptions(), (label: string, index: number) => {
                  GridItem() {
                    this.buildCapsuleButton(label, this.mockSelectedStringIndex === index, () => this.selectString(index), 34, true)
                  }
                }, (label: string) => `tuner-string-${label}`)
              }
              .columnsTemplate('1fr 1fr 1fr')
              .columnsGap(8)
              .rowsGap(8)
              .width('100%')
              .height(LayoutPolicy.wrapContent)
            }

            Column({ space: 8 }) {
              Text('灵敏度')
                .fontSize(12)
                .fontColor('rgba(255, 255, 255, 0.62)')
                .width('100%')
                .textAlign(TextAlign.Start)

              Row({ space: 8 }) {
                ForEach(['低', '中', '高'], (label: string, index: number) => {
                  Column() {
                    this.buildCapsuleButton(label, this.mockSensitivity === index, () => {
                      this.mockSensitivity = index;
                    }, 34, true)
                  }
                    .layoutWeight(1)
                }, (label: string) => `tuner-sensitivity-${label}`)
              }
              .width('100%')
            }

            Row({ space: 8 }) {
              Column() {
                this.buildCapsuleButton(this.mockMonitoringEnabled ? '监听中' : '开始监听', this.mockMonitoringEnabled, () => {
                  this.mockMonitoringEnabled = !this.mockMonitoringEnabled;
                }, 40, true)
              }
                .layoutWeight(1)

              Column() {
                this.buildCapsuleButton(this.mockHoldEnabled ? '已保持' : '保持读数', this.mockHoldEnabled, () => {
                  this.mockHoldEnabled = !this.mockHoldEnabled;
                }, 40, true)
              }
                .layoutWeight(1)
            }
            .width('100%')
          }
          .width('100%')
          .height(LayoutPolicy.wrapContent)
    }
    .width(this.useDocked ? '100%' : TunerWindowWidth)
    .height(LayoutPolicy.wrapContent)
    .padding(16)
    .backgroundColor('rgba(8, 10, 14, 0.82)')
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
        .onActionStart((_event: GestureEvent) => this.onHostPinchStart())
        .onActionUpdate((event: GestureEvent) => this.onHostPinchUpdate(event))
        .onActionEnd((_event: GestureEvent) => this.onHostPinchEnd())
        .onActionCancel(() => this.onHostPinchEnd())
    )
  }
}

@ComponentV2
export struct PDFTunerPanel {
  @Param showWindow: boolean = false;
  @Param useDocked: boolean = false;
  @Param dockedTopOffsetVp: number = 0;
  @Param floatingMinYVp: number = 0;
  @Param initialFloatingScale: number = FloatingTunerDefaultScale;
  @Param floatingViewportWidthVp: number = 0;
  @Param floatingViewportHeightVp: number = 0;
  @Event onFloatingScaleChanged: (scale: number) => void = (_scale: number) => {
  };
  @Event onInteraction: () => void = () => {
  };
  @Event onWindowAreaHeightChanged: (heightVp: number) => void = (_heightVp: number) => {
  };
  @Event onClose: () => void = () => {
  };
  @Local floatingScale: number = FloatingTunerDefaultScale;
  @Local floatingOffset: FloatingTunerOffset = { x: TunerDefaultOffsetX, y: TunerDefaultOffsetY };
  private floatingDragStartOffset: FloatingTunerOffset = { x: TunerDefaultOffsetX, y: TunerDefaultOffsetY };
  private pinchStartScale: number = FloatingTunerDefaultScale;
  private floatingPinchActive: boolean = false;
  private floatingWindowAreaWidthVp: number = TunerWindowWidth;
  private floatingWindowContentHeightVp: number = 0;

  aboutToAppear(): void {
    this.floatingScale = clampFloatingTunerScale(this.initialFloatingScale);
    this.pinchStartScale = this.floatingScale;
    this.floatingOffset = this.clampFloatingOffset({ x: TunerDefaultOffsetX, y: TunerDefaultOffsetY });
    this.floatingDragStartOffset = { x: this.floatingOffset.x, y: this.floatingOffset.y };
  }

  private updateFloatingScale(scale: number): void {
    const nextScale = clampFloatingTunerScale(scale);
    if (Math.abs(nextScale - this.floatingScale) < 0.001) {
      return;
    }

    this.floatingScale = nextScale;
    this.syncFloatingOffsetToBounds();
    this.onFloatingScaleChanged(nextScale);
  }

  private clampFloatingOffset(offset: FloatingTunerOffset): FloatingTunerOffset {
    if (this.useDocked) {
      return { x: 0, y: this.dockedTopOffsetVp };
    }

    const scaledWidthVp: number = this.floatingWindowAreaWidthVp * this.floatingScale;
    const scaledHeightVp: number = this.floatingWindowContentHeightVp * this.floatingScale;
    const minX: number = 0;
    const minY: number = this.floatingMinYVp;
    const maxX: number = this.floatingViewportWidthVp - scaledWidthVp - TunerWindowMargin;
    const maxY: number = this.floatingViewportHeightVp - scaledHeightVp - TunerWindowMargin;
    return {
      x: Math.max(minX, Math.min(offset.x, Math.max(minX, maxX))),
      y: Math.max(minY, Math.min(offset.y, Math.max(minY, maxY)))
    };
  }

  private getClampedFloatingOffset(): FloatingTunerOffset {
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

    this.floatingOffset = this.clampFloatingOffset({
      x: this.floatingDragStartOffset.x + event.offsetX * this.floatingScale,
      y: this.floatingDragStartOffset.y + event.offsetY * this.floatingScale
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
      PDFTunerPanelContent({
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
        onClose: this.onClose
      })
        .visibility(this.showWindow ? Visibility.Visible : Visibility.None)
    }
  }
}
