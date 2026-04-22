import { ScrollSpinBox } from "../../components/ScrollSpinBox";
import { ButtonColor, ContainerPadding, getCheckIcon, toVisibility } from "../../components/UIComponents";
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { uiEffect } from '@kit.ArkGraphics2D';
import {
  PDFTunerController,
  TunerNoteDisplayMode,
  TunerNoteNamingMode,
} from './PDFTunerController';
import {
  SharedPanelBackgroundBlurRadius,
  SharedPanelBackgroundColor,
  SharedPanelControlHighlightColor,
} from './PDFPanelVisualConstants';

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
const TunerSpectrumBars: number = 20;
const TunerReferenceNoteMinMidi: number = 24;
const TunerReferenceNoteMaxMidi: number = 84;
const TunerReferenceNoteDefaultMidi: number = 69;

interface FloatingTunerOffset {
  x: number;
  y: number;
}

interface TunerNoteDisplayModeOption {
  mode: TunerNoteDisplayMode;
  label: string;
  notes: string[];
}

interface TunerNoteNamingModeOption {
  mode: TunerNoteNamingMode;
  label: string;
}

interface TunerSolfegeDisplayModeSet {
  standard: string[];
  sharp: string[];
  flat: string[];
}

const TunerNoteDisplayModes: TunerNoteDisplayModeOption[] = [
  {
    mode: "standard",
    label: "标准",
    notes: ["C", "C #", "D", "E b", "E", "F", "G b", "G", "G #", "A", "B b", "B"],
  },
  {
    mode: "sharp",
    label: "升号",
    notes: ["C", "C #", "D", "D #", "E", "F", "F #", "G", "G #", "A", "A #", "B"],
  },
  {
    mode: "flat",
    label: "降号",
    notes: ["C", "D b", "D", "E b", "E", "F b", "G b", "A b", "A", "B b", "C b", "D b"],
  },
];

const TunerSolfegeDisplayModes: TunerSolfegeDisplayModeSet = {
  standard: ["Do", "Do #", "Re", "Mi b", "Mi", "Fa", "Sol b", "Sol", "Sol #", "La", "Si b", "Si"],
  sharp: ["Do", "Do #", "Re", "Re #", "Mi", "Fa", "Fa #", "Sol", "Sol #", "La", "La #", "Si"],
  flat: ["Do", "Re b", "Re", "Mi b", "Mi", "Fa b", "Sol b", "La b", "La", "Si b", "Do b", "Do"],
};

const TunerNoteNamingModes: TunerNoteNamingModeOption[] = [
  { mode: "pitch", label: "音高" },
  { mode: "solfege", label: "唱名" },
];

const TunerNoteSemitoneMap: Record<string, number> = {
  "C": 0,
  "B#": 0,
  "C#": 1,
  "Db": 1,
  "D": 2,
  "D#": 3,
  "Eb": 3,
  "E": 4,
  "Fb": 4,
  "E#": 5,
  "F": 5,
  "F#": 6,
  "Gb": 6,
  "G": 7,
  "G#": 8,
  "Ab": 8,
  "A": 9,
  "A#": 10,
  "Bb": 10,
  "B": 11,
  "Cb": 11,
};

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
  @Event onInteraction: () => void = () => {};
  @Event onTouchStateChanged: (active: boolean) => void = (_active: boolean) => {};
  @Event onWindowAreaHeightChanged: (heightVp: number) => void = (_heightVp: number) => {};
  @Event onHostDragStart: () => void = () => {};
  @Event onHostDragUpdate: (event: GestureEvent) => void = (_event: GestureEvent) => {};
  @Event onHostDragEnd: () => void = () => {};
  @Event onHostPinchStart: () => void = () => {};
  @Event onHostPinchUpdate: (event: GestureEvent) => void = (_event: GestureEvent) => {};
  @Event onHostPinchEnd: () => void = () => {};
  @Event onClose: () => void = () => {};
  @Param controller: PDFTunerController | undefined = undefined;
  @Local detectedNote: string = "A4";
  @Local detuneCents: number = 3;
  private readonly submenuArrowIcon: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.chevron_forward'))
    .fontSize('18vp')
    .padding('2vp');
  private readonly panelBackgroundBlurFilter: uiEffect.Filter =
    uiEffect.createFilter().blur(SharedPanelBackgroundBlurRadius);
  private readonly tunerGridLayout: GridLayoutOptions = {
    regularSize: [1, 1],
    irregularIndexes: [0, 1, 2, 9],
    onGetIrregularSizeByIndex: (): [number, number] => [1, 2],
  };

  private getDetuneSummary(): string {
    if (Math.abs(this.detuneCents) <= 1) {
      return "音高稳定";
    }
    return this.detuneCents > 0 ? "略高" : "略低";
  }

  private getDetuneColor(): string {
    if (Math.abs(this.detuneCents) <= 4) {
      return "#42D392";
    }
    if (Math.abs(this.detuneCents) <= 12) {
      return "#FFB347";
    }
    return "#FF7A7A";
  }

  private getMeterSegmentColor(index: number): string {
    const centeredIndex: number = Math.floor(TunerMeterSegments / 2);
    const activeIndex: number = Math.max(
      0,
      Math.min(
        TunerMeterSegments - 1,
        Math.round(((this.detuneCents + 50) / 100) * (TunerMeterSegments - 1)),
      ),
    );
    if (index === centeredIndex) {
      return Math.abs(this.detuneCents) <= 4 ? "#42D392" : "rgba(255, 255, 255, 0.16)";
    }
    if (
      (this.detuneCents < 0 && index >= activeIndex && index < centeredIndex) ||
      (this.detuneCents > 0 && index <= activeIndex && index > centeredIndex)
    ) {
      return this.getDetuneColor();
    }
    return "rgba(255, 255, 255, 0.12)";
  }

  private getSpectrumBarHeight(index: number): number {
    const center: number = (TunerSpectrumBars - 1) / 2;
    const distanceRatio: number = Math.abs(index - center) / center;
    const envelope: number = Math.max(0.2, 1 - distanceRatio * 0.75);
    const wave: number = 0.58 + 0.42 * Math.sin(index * 0.7 + this.detuneCents * 0.08);
    const sensitivityGain: number = 0.45 + (this.controller?.microphoneGain ?? 0.65) * 0.55;
    return 10 + envelope * wave * sensitivityGain * 48;
  }

  private getReferencePresetMenu(): MenuElement[] {
    const presets: number[] = [415, 430, 432, 440, 442, 445];
    return presets.map(
      (preset: number): MenuElement => ({
        value: `${preset} Hz`,
        action: () => {
          this.controller?.setReferenceHz(preset);
        },
      }),
    );
  }

  private getCurrentNoteDisplayMode(): TunerNoteDisplayModeOption {
    const mode: TunerNoteDisplayMode = this.controller?.noteDisplayMode ?? 'standard';
    return TunerNoteDisplayModes.find(
      (option: TunerNoteDisplayModeOption) => option.mode === mode,
    ) ?? TunerNoteDisplayModes[0];
  }

  private getCurrentTransposeNotes(): string[] {
    if ((this.controller?.noteNamingMode ?? 'pitch') === "pitch") {
      return this.getCurrentNoteDisplayMode().notes;
    }
    if ((this.controller?.noteDisplayMode ?? 'standard') === "standard") {
      return TunerSolfegeDisplayModes.standard;
    }
    if ((this.controller?.noteDisplayMode ?? 'standard') === "sharp") {
      return TunerSolfegeDisplayModes.sharp;
    }
    return TunerSolfegeDisplayModes.flat;
  }

  private getFormattedDetectedNote(): string {
    const match: RegExpMatchArray | null = this.detectedNote.match(/^([A-G](?:#|b)?)(.*)$/);
    if (match === null) {
      return this.detectedNote;
    }
    const sourceNote: string = match[1];
    const suffix: string = match[2];
    const semitone: number | undefined = TunerNoteSemitoneMap[sourceNote];
    if (semitone === undefined) {
      return this.detectedNote;
    }
    const displayNote: string = this.getCurrentTransposeNotes()[semitone] ?? sourceNote;
    return `${displayNote}${suffix}`;
  }

  private isReferenceToneEnabled(): boolean {
    return this.controller?.referenceToneEnabled ?? false;
  }

  private getReferenceNoteValues(): number[] {
    return Array.from(
      { length: TunerReferenceNoteMaxMidi - TunerReferenceNoteMinMidi + 1 },
      (_value: number, index: number) => TunerReferenceNoteMinMidi + index,
    );
  }

  private getReferenceNoteLabel(midi: number): string {
    const semitone: number = ((midi % 12) + 12) % 12;
    const octave: number = Math.floor(midi / 12) - 1;
    const noteLabel: string = this.getCurrentTransposeNotes()[semitone] ?? 'C';
    return `${noteLabel}${octave}`;
  }

  private getReferenceNoteLabels(): string[] {
    return this.getReferenceNoteValues().map((midi: number) => this.getReferenceNoteLabel(midi));
  }

  private getReferenceNoteMidi(): number {
    return this.controller?.referenceNoteMidi ?? TunerReferenceNoteDefaultMidi;
  }

  private toggleReferenceToneEnabled(): void {
    const nextValue: boolean = !this.isReferenceToneEnabled();
    this.controller?.setReferenceToneEnabled(nextValue);
    // TODO: 在这里接入参考音播放/停止逻辑。
  }

  private handleReferenceNoteChanged(value: number): void {
    this.controller?.setReferenceNoteMidi(value);
    // TODO: 在这里接入参考音切换后的发声音高更新逻辑。
  }

  private getTransposePresetMenu(): MenuElement[] {
    return this.getCurrentTransposeNotes().map(
      (note: string, index: number): MenuElement => ({
        value: note,
        action: () => {
          this.controller?.setTransposeIndex(index);
        },
      }),
    );
  }

  private getNoteDisplayModeMenu(): MenuElement[] {
    return TunerNoteDisplayModes.map(
      (option: TunerNoteDisplayModeOption): MenuElement => ({
        value: option.label,
        action: () => {
          this.controller?.setNoteDisplayMode(option.mode);
        },
        symbolIcon: getCheckIcon((this.controller?.noteDisplayMode ?? 'standard') === option.mode),
      }),
    );
  }

  private getNoteNamingModeMenu(): MenuElement[] {
    return TunerNoteNamingModes.map(
      (option: TunerNoteNamingModeOption): MenuElement => ({
        value: option.label,
        action: () => {
          this.controller?.setNoteNamingMode(option.mode);
        },
        symbolIcon: getCheckIcon((this.controller?.noteNamingMode ?? 'pitch') === option.mode),
      }),
    );
  }

  @Builder
  private buildLeafMenu(items: MenuElement[]) {
    ForEach(items, (item: MenuElement, index: number) => {
      MenuItem({
        content: item.value,
        startIcon: item.icon,
        symbolStartIcon: item.symbolIcon,
      })
        .enabled(item.enabled ?? true)
        .onClick(() => item.action());
    }, (_item: MenuElement, index: number) => index.toString());
  }

  @Builder
  private buildSubMenu(items: MenuElement[]) {
    Menu() {
      this.buildLeafMenu(items);
    }
    .backgroundColor(ButtonColor)
  }

  @Builder
  private buildNestedModeMenu() {
    Menu() {
      MenuItem({
        content: "升降",
        symbolEndIcon: this.submenuArrowIcon,
        builder: (): void => this.buildSubMenu(this.getNoteDisplayModeMenu()),
      });
      MenuItem({
        content: "音名",
        symbolEndIcon: this.submenuArrowIcon,
        builder: (): void => this.buildSubMenu(this.getNoteNamingModeMenu()),
      });
    }
    .subMenuExpandingMode(SubMenuExpandingMode.SIDE_EXPAND);
  }

  build() {
    Column() {
      Grid(undefined, this.tunerGridLayout) {
        GridItem() {
          Row({ space: TunerHeaderGap }) {
            Row({ space: this.useDocked ? 0 : 10 }) {
              Column({ space: 3 }) {
                Row({ space: 3 }) {
                  ForEach(
                    [0, 1, 2, 3],
                    (index: number) => {
                      Text("")
                        .width(4)
                        .height(4)
                        .borderRadius(2)
                        .backgroundColor("rgba(255, 255, 255, 0.26)");
                    },
                    (index: number) => `tuner-drag-grip-top-${index}`,
                  )
                }
                Row({ space: 3 }) {
                  ForEach(
                    [0, 1, 2, 3],
                    (index: number) => {
                      Text("")
                        .width(4)
                        .height(4)
                        .borderRadius(2)
                        .backgroundColor("rgba(255, 255, 255, 0.16)");
                    },
                    (index: number) => `tuner-drag-grip-bottom-${index}`,
                  )
                }
              }.visibility(toVisibility(this.showDragHandle && !this.useDocked))
              Text("调音器")
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
            }
            .height("auto")
            .width("100%")
            .constraintSize({ maxWidth: TunerHeaderDragMaxWidth })
            .padding(ContainerPadding)
            .alignItems(VerticalAlign.Center)
            .borderRadius(10)
            .backgroundColor("rgba(255, 255, 255, 0.05)")
            .border({ width: 1, color: "rgba(255, 255, 255, 0.06)" })
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
                }),
            )
            Button({ type: ButtonType.Normal }) {
              SymbolGlyph($r("sys.symbol.xmark"))
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor([Color.White])
            }
            .width(TunerHeaderCloseButtonWidth)
            .height(LayoutPolicy.matchParent)
            .borderRadius(10)
            .backgroundColor("rgba(255, 255, 255, 0.16)")
            .onClick(() => this.onClose())
          }
          .width("100%")
          .hitTestBehavior(HitTestMode.Default)
        }
        GridItem() {
          Column() {
            Stack({ alignContent: Alignment.TopEnd }) {
              Column({ space: this.isReferenceToneEnabled() ? 0 : 4 }) {
                if (this.isReferenceToneEnabled()) {
                  ScrollSpinBox({
                    value: this.getReferenceNoteMidi(),
                    values: this.getReferenceNoteValues(),
                    labels: this.getReferenceNoteLabels(),
                    canLoop: true,
                    valueFontSize: 32,
                    debounceMs: 100,
                    onValueChange: (value: number) => {
                      this.handleReferenceNoteChanged(value);
                    },
                    itemHeight: 34,
                    gradientHeight: 30,
                  })
                    .width(168)
                    .height(92)
                } else {
                  Text(this.getFormattedDetectedNote())
                    .fontSize(40)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Color.White)
                  Text(`${this.detuneCents > 0 ? "+" : ""}${this.detuneCents} cents`)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.getDetuneColor())
                  Text(this.getDetuneSummary())
                    .fontSize(12)
                    .fontColor("rgba(255, 255, 255, 0.54)")
                }
              }
              .width("100%")
              .padding({ top: 12, bottom: 12, left: 8, right: 8 })
              .alignItems(HorizontalAlign.Center)
              .hitTestBehavior(HitTestMode.Transparent)
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.speaker_wave_2_fill'))
                  .fontSize(18)
                  .fontColor([Color.White])
              }
              .width(36)
              .height(36)
              .margin({ top: 10, right: 10 })
              .backgroundColor(
                this.isReferenceToneEnabled() ? "rgba(77, 166, 255, 0.92)" : "rgba(255, 255, 255, 0.12)",
              )
              .border({
                width: 1,
                color: this.isReferenceToneEnabled() ? "rgba(255, 255, 255, 0.24)" : "rgba(255, 255, 255, 0.08)",
              })
              .onClick(() => this.toggleReferenceToneEnabled())
            }
            .width("100%")
          }
          .width("100%")
          .borderRadius(18)
          .backgroundColor("rgba(255, 255, 255, 0.05)")
          .border({ width: 1, color: "rgba(255, 255, 255, 0.05)" })
        }
        GridItem() {
          Column({ space: 8 }) {
            Row({ space: 6 }) {
              Text("-50")
                .fontSize(11)
                .fontColor("rgba(255, 255, 255, 0.4)")
              Blank().layoutWeight(1)
              Text("0")
                .fontSize(11)
                .fontColor("rgba(255, 255, 255, 0.52)")
              Blank().layoutWeight(1)
              Text("+50")
                .fontSize(11)
                .fontColor("rgba(255, 255, 255, 0.4)")
            }.width("100%")
            Row({ space: 6 }) {
              ForEach(
                Array.from(
                  { length: TunerMeterSegments },
                  (_value: number, index: number) => index,
                ),
                (index: number) => {
                  Column()
                    .layoutWeight(1)
                    .height(index === Math.floor(TunerMeterSegments / 2) ? 36 : 24)
                    .borderRadius(6)
                    .backgroundColor(this.getMeterSegmentColor(index));
                },
                (index: number) => `tuner-meter-${index}`,
              )
            }.width("100%")
          }
          .padding(14)
          .borderRadius(18)
          .backgroundColor("rgba(255, 255, 255, 0.08)")
          .border({ width: 1, color: "rgba(255, 255, 255, 0.05)" })
        }
        GridItem() {
          Text("参考频率")
            .fontSize(12)
            .fontColor("rgba(255, 255, 255, 0.62)")
            .width("100%")
            .textAlign(TextAlign.Start)
        }
        GridItem() {
          Text("移调")
            .fontSize(12)
            .fontColor("rgba(255, 255, 255, 0.62)")
            .width("100%")
            .textAlign(TextAlign.Start)
        }
        GridItem() {
          ScrollSpinBox({
            value: this.controller?.referenceHz ?? 440,
            canLoop: false,
            min: 430,
            max: 450,
            step: 1,
            valueFontSize: 28,
            debounceMs: 100,
            onValueChange: (value: number) => {
              this.controller?.setReferenceHz(value);
            },
            itemHeight: 26,
            gradientHeight: 32,
          })
            .width("100%")
            .height(96)
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .borderRadius(16)
            .backgroundColor(SharedPanelControlHighlightColor)
        }
        GridItem() {
          ScrollSpinBox({
            value: this.controller?.transposeIndex ?? 0,
            values: Array.from(
              { length: this.getCurrentTransposeNotes().length },
              (_value: number, index: number) => index,
            ),
            labels: this.getCurrentTransposeNotes(),
            canLoop: true,
            valueFontSize: 28,
            debounceMs: 100,
            onValueChange: (value: number) => {
              this.controller?.setTransposeIndex(value);
            },
            itemHeight: 26,
            gradientHeight: 32,
          })
            .width("100%")
            .height(96)
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .borderRadius(16)
            .backgroundColor(SharedPanelControlHighlightColor)
        }
        GridItem() {
          Button("预设")
            .type(ButtonType.Capsule)
            .width("100%")
            .height(34)
            .fontSize(13)
            .fontColor(Color.White)
            .backgroundColor("rgba(255, 255, 255, 0.1)")
            .bindMenu(this.getReferencePresetMenu(), {
              backgroundColor: ButtonColor,
              outlineColor: Color.Transparent,
              placement: Placement.BottomRight,
            })
        }
        GridItem() {
          Row({ space: 6 }) {
            Button("预设")
              .type(ButtonType.Capsule)
              .flexGrow(1)
              .height(34)
              .fontSize(13)
              .fontColor(Color.White)
              .backgroundColor("rgba(255, 255, 255, 0.1)")
              .bindMenu(this.getTransposePresetMenu(), {
                backgroundColor: ButtonColor,
                outlineColor: Color.Transparent,
                placement: Placement.BottomRight,
              })
            Button("模式")
              .type(ButtonType.Capsule)
              .flexGrow(1)
              .height(34)
              .fontSize(13)
              .fontColor(Color.White)
              .backgroundColor("rgba(255, 255, 255, 0.1)")
              .bindMenu(this.buildNestedModeMenu, {
                backgroundColor: ButtonColor,
                outlineColor: Color.Transparent,
                placement: Placement.BottomRight,
              })
          }.width("100%")
        }
        GridItem() {
          Column() {
            Text("麦克风灵敏度")
              .fontSize(12)
              .fontColor("rgba(255, 255, 255, 0.62)")
              .width("100%")
              .textAlign(TextAlign.Start)
              .margin({ bottom: 8 })
            Row({ space: 4 }) {
              ForEach(
                Array.from({ length: TunerSpectrumBars }, (_value: number, index: number) => index),
                (index: number) => {
                  Column()
                    .layoutWeight(1)
                    .height(this.getSpectrumBarHeight(index))
                    .borderRadius(3)
                    .backgroundColor("rgba(77, 166, 255, 0.75)");
                },
                (index: number) => `tuner-spectrum-${index}`,
              )
            }
            .width("100%")
            .height(64)
            .alignItems(VerticalAlign.Bottom)
            .padding({ left: 6, right: 6, top: 6, bottom: 0 })
            .borderRadius(12)
            .backgroundColor("rgba(255, 255, 255, 0.08)")
            Slider({
              value: this.controller?.microphoneGain ?? 0.65,
              min: 0,
              max: 1,
              step: 0.01,
              style: SliderStyle.OutSet,
            })
              .width("100%")
              .selectedColor("rgba(77, 166, 255, 0.9)")
              .trackColor("rgba(255, 255, 255, 0.2)")
              .showTips(false)
              .onChange((value: number, _mode: SliderChangeMode) => {
                this.controller?.setMicrophoneGain(value);
              })
          }.width("100%")
        }
      }
      .columnsTemplate("1fr 1fr")
      .columnsGap(10)
      .rowsGap(10)
      .width("100%")
      .height(LayoutPolicy.wrapContent)
    }
    .width(this.useDocked ? "100%" : TunerWindowWidth)
    .height(LayoutPolicy.wrapContent)
    .padding(16)
    .backgroundColor(SharedPanelBackgroundColor)
    .backgroundFilter(this.panelBackgroundBlurFilter)
    .borderRadius({
      topLeft: this.useDocked ? 0 : 18,
      topRight: this.useDocked ? 0 : 18,
      bottomLeft: 18,
      bottomRight: 18,
    })
    .margin(this.useDocked ? 0 : ContainerPadding)
    .border({ width: 1, color: "rgba(255, 255, 255, 0.07)" })
    .shadow({ radius: 16, color: "rgba(0, 0, 0, 0.24)", offsetY: 4 })
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
    .scale(
      this.useDocked
        ? { x: 1, y: 1 }
        : { x: this.hostScale, y: this.hostScale, centerX: 0, centerY: 0 },
    )
    .offset(this.useDocked ? { x: 0, y: this.dockedTopOffsetVp } : this.hostOffset)
    .gesture(
      PinchGesture({ fingers: 2 })
        .onActionStart((_event: GestureEvent) => this.onHostPinchStart())
        .onActionUpdate((event: GestureEvent) => this.onHostPinchUpdate(event))
        .onActionEnd((_event: GestureEvent) => this.onHostPinchEnd())
        .onActionCancel(() => this.onHostPinchEnd()),
    );
  }
}
@ComponentV2
export struct PDFTunerPanel {
  @Param controller: PDFTunerController | undefined = undefined;
  @Param showWindow: boolean = false;
  @Param useDocked: boolean = false;
  @Param dockedTopOffsetVp: number = 0;
  @Param floatingMinYVp: number = 0;
  @Param initialFloatingScale: number = FloatingTunerDefaultScale;
  @Param floatingViewportWidthVp: number = 0;
  @Param floatingViewportHeightVp: number = 0;
  @Event onFloatingScaleChanged: (scale: number) => void = (_scale: number) => {};
  @Event onInteraction: () => void = () => {};
  @Event onWindowAreaHeightChanged: (heightVp: number) => void = (_heightVp: number) => {};
  @Event onClose: () => void = () => {};
  @Local floatingScale: number = FloatingTunerDefaultScale;
  @Local floatingOffset: FloatingTunerOffset = { x: TunerDefaultOffsetX, y: TunerDefaultOffsetY };
  private floatingDragStartOffset: FloatingTunerOffset = {
    x: TunerDefaultOffsetX,
    y: TunerDefaultOffsetY,
  };
  private pinchStartScale: number = FloatingTunerDefaultScale;
  private floatingPinchActive: boolean = false;
  private floatingWindowAreaWidthVp: number = TunerWindowWidth;
  private floatingWindowContentHeightVp: number = 0;

  aboutToAppear(): void {
    this.floatingScale = clampFloatingTunerScale(this.initialFloatingScale);
    this.pinchStartScale = this.floatingScale;
    this.floatingOffset = this.clampFloatingOffset({
      x: TunerDefaultOffsetX,
      y: TunerDefaultOffsetY,
    });
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
      y: Math.max(minY, Math.min(offset.y, Math.max(minY, maxY))),
    };
  }

  private getClampedFloatingOffset(): FloatingTunerOffset {
    return this.clampFloatingOffset(this.floatingOffset);
  }

  private syncFloatingOffsetToBounds(): void {
    const nextOffset = this.getClampedFloatingOffset();
    if (
      Math.abs(nextOffset.x - this.floatingOffset.x) < 0.001 &&
      Math.abs(nextOffset.y - this.floatingOffset.y) < 0.001
    ) {
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
      y: this.floatingDragStartOffset.y + event.offsetY * this.floatingScale,
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
        controller: this.controller,
        useDocked: this.useDocked,
        dockedTopOffsetVp: this.dockedTopOffsetVp,
        hostScale: this.floatingScale,
        hostOffset: this.getClampedFloatingOffset(),
        showDragHandle: !this.useDocked,
        onInteraction: this.onInteraction,
        onWindowAreaHeightChanged: (heightVp: number) =>
          this.handleFloatingWindowAreaChange(heightVp),
        onHostDragStart: () => this.handleFloatingDragStart(),
        onHostDragUpdate: (event: GestureEvent) => this.handleFloatingDragUpdate(event),
        onHostDragEnd: () => this.handleFloatingDragEnd(),
        onHostPinchStart: () => this.handleFloatingPinchStart(),
        onHostPinchUpdate: (event: GestureEvent) => this.handleFloatingPinchUpdate(event),
        onHostPinchEnd: () => this.handleFloatingPinchEnd(),
        onClose: this.onClose,
      }).visibility(this.showWindow ? Visibility.Visible : Visibility.None)
    };
  }
}
