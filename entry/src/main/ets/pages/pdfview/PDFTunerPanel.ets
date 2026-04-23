import { ScrollSpinBox } from "../../components/ScrollSpinBox";
import { ButtonColor, ContainerPadding, getCheckIcon, toVisibility } from "../../components/UIComponents";
import { common } from '@kit.AbilityKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { uiEffect } from '@kit.ArkGraphics2D';
import {
  PDFTunerController,
  TunerNoteDisplayMode,
  TunerNoteNamingMode,
  TunerReferenceHzMax,
  TunerReferenceHzMin,
} from './PDFTunerController';
import {
  SharedPanelBackgroundBlurRadius,
  SharedPanelBackgroundColor,
  SharedPanelControlHighlightColor,
} from './PDFPanelVisualConstants';

const TunerWindowMargin: number = 16;
const TunerWindowWidth: number = 392;
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
const TunerSpectrumRedThreshold: number = 1.08;
const TunerReferenceNoteMinMidi: number = 48;
const TunerReferenceNoteMaxMidi: number = 108;
const TunerReferenceNoteDefaultMidi: number = 69;
const TunerPianoWhiteKeySemitones: number[] = [0, 2, 4, 5, 7, 9, 11];
const TunerPianoBlackKeys: number[][] = [
  [1, 0],
  [3, 1],
  [6, 3],
  [8, 4],
  [10, 5],
];
const TunerPianoWhiteKeyCount: number = 7;
const TunerPianoKeyboardHeight: number = 108;
const TunerPianoBlackKeyHeight: number = 68;
const TunerPianoBlackKeyWidthFraction: number = 0.1;
const TunerPianoWhiteKeyLabelBottom: number = 5;
const TunerPianoBlackKeyLabelBottom: number = 4;
const TunerPianoBlackKeyOffsets: number[] = [0.11, 0.245, 0.53, 0.665, 0.8];

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
  @Local showReferencePresetPopup: boolean = false;
  @Local showTransposePresetPopup: boolean = false;
  @Local showModePopup: boolean = false;
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

  /** 柱高为频谱行高度的 0～100%，与柱索引无关；顶满时各柱齐平（不再乘两侧压低包络）。level>1 时高度仍按 1 封顶，颜色另判。 */
  private getSpectrumBarHeightPercent(index: number): string {
    const level: number = this.controller?.spectrumBarLevels[index] ?? 0;
    const levelForBar: number = Math.min(Math.max(level, 0), 1);
    const pct: number = Math.min(Math.max(levelForBar * 100, 0), 100);
    return `${pct}%`;
  }

  private getSpectrumBarColor(index: number): string {
    const level: number = this.controller?.spectrumBarLevels[index] ?? 0;
    if (level > TunerSpectrumRedThreshold) {
      return "rgba(255, 82, 82, 0.88)";
    }
    return "rgba(77, 166, 255, 0.75)";
  }

  private getReferencePresetMenu(): MenuElement[] {
    const presets: number[] = [200, 220, 262, 415, 430, 432, 440, 442, 445, 523, 600];
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
  }

  private handleReferenceNoteChanged(value: number): void {
    const clampedValue: number = Math.max(TunerReferenceNoteMinMidi, Math.min(TunerReferenceNoteMaxMidi, value));
    this.controller?.setReferenceNoteMidi(clampedValue);
  }

  private adjustReferenceOctave(deltaOctave: number): void {
    this.handleReferenceNoteChanged(this.getReferenceNoteMidi() + deltaOctave * 12);
  }

  private getReferenceKeyboardBaseMidi(): number {
    return Math.floor(this.getReferenceNoteMidi() / 12) * 12;
  }

  private getKeyLabel(semitone: number): string {
    return this.getCurrentTransposeNotes()[semitone] ?? 'C';
  }

  private isKeySelected(semitone: number): boolean {
    return ((this.getReferenceNoteMidi() % 12) + 12) % 12 === semitone;
  }

  private getWhiteKeyColor(semitone: number): string {
    return this.isKeySelected(semitone) ? 'rgba(77, 166, 255, 0.92)' : 'rgba(215, 218, 224, 0.92)';
  }

  private getWhiteKeyFontColor(semitone: number): ResourceColor {
    return this.isKeySelected(semitone) ? Color.White : 'rgba(28, 32, 40, 0.88)';
  }

  private getBlackKeyColor(semitone: number): string {
    return this.isKeySelected(semitone) ? 'rgba(77, 166, 255, 0.96)' : 'rgba(18, 22, 30, 0.94)';
  }

  private pressKey(semitone: number): void {
    const targetMidi: number = this.getReferenceKeyboardBaseMidi() + semitone;
    this.handleReferenceNoteChanged(Math.max(TunerReferenceNoteMinMidi, Math.min(TunerReferenceNoteMaxMidi, targetMidi)));
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


  @Builder
  private buildLeafMenu(items: MenuElement[], onSelected?: () => void) {
    ForEach(items, (item: MenuElement, index: number) => {
      MenuItem({
        content: item.value,
        startIcon: item.icon,
        symbolStartIcon: item.symbolIcon,
      })
        .enabled(item.enabled ?? true)
        .onClick(() => {
          item.action();
          onSelected?.();
        });
    }, (_item: MenuElement, index: number) => index.toString());
  }

  @Builder
  private buildFlatModeMenu() {
    Menu() {
      MenuItemGroup({ header: "升降" }) {
        ForEach(TunerNoteDisplayModes, (option: TunerNoteDisplayModeOption) => {
          MenuItem({
            content: option.label,
            symbolStartIcon: getCheckIcon((this.controller?.noteDisplayMode ?? 'standard') === option.mode),
          })
            .onClick(() => {
              this.controller?.setNoteDisplayMode(option.mode);
              this.showModePopup = false;
            });
        }, (option: TunerNoteDisplayModeOption) => `mode-display-${option.mode}`);
      }
      MenuItemGroup({ header: "音名" }) {
        ForEach(TunerNoteNamingModes, (option: TunerNoteNamingModeOption) => {
          MenuItem({
            content: option.label,
            symbolStartIcon: getCheckIcon((this.controller?.noteNamingMode ?? 'pitch') === option.mode),
          })
            .onClick(() => {
              this.controller?.setNoteNamingMode(option.mode);
              this.showModePopup = false;
            });
        }, (option: TunerNoteNamingModeOption) => `mode-naming-${option.mode}`);
      }
    }
    .backgroundColor(ButtonColor)
  }

  @Builder
  private buildReferencePresetPopup() {
    Menu() {
      this.buildLeafMenu(this.getReferencePresetMenu(), () => this.hideReferencePresetPopup());
    }
    .backgroundColor(ButtonColor)
  }

  @Builder
  private buildTransposePresetPopup() {
    Menu() {
      this.buildLeafMenu(this.getTransposePresetMenu(), () => this.hideTransposePresetPopup());
    }
    .backgroundColor(ButtonColor)
  }

  private hideReferencePresetPopup(): void {
    this.showReferencePresetPopup = false;
  }

  private hideTransposePresetPopup(): void {
    this.showTransposePresetPopup = false;
  }

  aboutToAppear(): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void this.controller?.startMicrophoneMonitoring(context, false);
  }

  aboutToDisappear(): void {
    this.controller?.stopMicrophoneMonitoring();
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
                  Column({ space: 8 }) {
                    ScrollSpinBox({
                      value: this.getReferenceNoteMidi(),
                      values: this.getReferenceNoteValues(),
                      labels: this.getReferenceNoteLabels(),
                      canLoop: false,
                      valueFontSize: 40,
                      debounceMs: 20,
                      onValueChange: (value: number) => {
                        this.handleReferenceNoteChanged(value);
                      },
                      itemHeight: 40,
                      gradientHeight: 30,
                    })
                      .width(168)
                      .height(96)

                    Row({ space: 8 }) {
                      Button('低八度')
                        .type(ButtonType.Capsule)
                        .layoutWeight(1)
                        .height(30)
                        .fontSize(12)
                        .fontColor(Color.White)
                        .backgroundColor('rgba(255, 255, 255, 0.12)')
                        .onClick(() => this.adjustReferenceOctave(-1))
                      Button('高八度')
                        .type(ButtonType.Capsule)
                        .layoutWeight(1)
                        .height(30)
                        .fontSize(12)
                        .fontColor(Color.White)
                        .backgroundColor('rgba(255, 255, 255, 0.12)')
                        .onClick(() => this.adjustReferenceOctave(1))
                    }
                    .width('100%')

                    Stack() {
                      Row({ space: 2 }) {
                        ForEach(
                          TunerPianoWhiteKeySemitones,
                          (semitone: number) => {
                            Button() {
                              Column() {
                                Blank()
                                  .layoutWeight(1)
                                Text(this.getKeyLabel(semitone))
                                  .fontSize(10)
                                  .fontWeight(this.isKeySelected(semitone) ? FontWeight.Bold : FontWeight.Normal)
                                  .fontColor(this.getWhiteKeyFontColor(semitone))
                                  .margin({ bottom: TunerPianoWhiteKeyLabelBottom })
                              }
                              .width('100%')
                              .height('100%')
                              .justifyContent(FlexAlign.End)
                              .alignItems(HorizontalAlign.Center)
                            }
                              .type(ButtonType.Normal)
                              .layoutWeight(1)
                              .height(TunerPianoKeyboardHeight)
                              .backgroundColor(this.getWhiteKeyColor(semitone))
                              .borderRadius(4)
                              .onClick(() => this.pressKey(semitone))
                          },
                          (semitone: number) => `tuner-wk-${semitone}`,
                        )
                      }
                      .width('100%')
                      .height(TunerPianoKeyboardHeight)

                      ForEach(
                        TunerPianoBlackKeyOffsets,
                        (offset: number, index: number) => {
                          Button() {
                            Column() {
                              Blank()
                                .layoutWeight(1)
                              Text(this.getKeyLabel(TunerPianoBlackKeys[index][0]))
                                .fontSize(8)
                                .fontWeight(this.isKeySelected(TunerPianoBlackKeys[index][0]) ? FontWeight.Bold : FontWeight.Normal)
                                .fontColor(Color.White)
                                .margin({ bottom: TunerPianoBlackKeyLabelBottom })
                            }
                            .width('100%')
                            .height('100%')
                            .justifyContent(FlexAlign.End)
                            .alignItems(HorizontalAlign.Center)
                          }
                            .type(ButtonType.Normal)
                            .width(`${TunerPianoBlackKeyWidthFraction * 100}%`)
                            .height(TunerPianoBlackKeyHeight)
                            .backgroundColor(this.getBlackKeyColor(TunerPianoBlackKeys[index][0]))
                            .borderRadius({ bottomLeft: 3, bottomRight: 3 })
                            .position({ x: `${offset * 100}%`, y: 0 })
                            .onClick(() => this.pressKey(TunerPianoBlackKeys[index][0]))
                        },
                        (_offset: number, index: number) => `tuner-bk-${index}`,
                      )
                    }
                    .width('100%')
                    .height(TunerPianoKeyboardHeight)
                    .clip(true)
                  }
                  .width('100%')
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
        }.visibility(this.isReferenceToneEnabled() ? Visibility.None : Visibility.Visible)
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
            min: TunerReferenceHzMin,
            max: TunerReferenceHzMax,
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
            .onClick(() => {
              this.showReferencePresetPopup = true;
            })
            .bindPopup(this.showReferencePresetPopup, {
              builder: this.buildReferencePresetPopup,
              placement: Placement.BottomRight,
              autoCancel: true,
              showInSubWindow: false,
              followTransformOfTarget: true,
              onStateChange: (event) => {
                this.showReferencePresetPopup = event.isVisible;
              },
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
              .onClick(() => {
                this.showTransposePresetPopup = true;
              })
              .bindPopup(this.showTransposePresetPopup, {
                builder: this.buildTransposePresetPopup,
                placement: Placement.BottomRight,
                autoCancel: true,
                showInSubWindow: false,
                followTransformOfTarget: true,
                onStateChange: (event) => {
                  this.showTransposePresetPopup = event.isVisible;
                },
              })
            Button("模式")
              .type(ButtonType.Capsule)
              .flexGrow(1)
              .height(34)
              .fontSize(13)
              .fontColor(Color.White)
              .backgroundColor("rgba(255, 255, 255, 0.1)")
              .onClick(() => {
                this.showModePopup = true;
              })
              .bindPopup(this.showModePopup, {
                builder: this.buildFlatModeMenu,
                placement: Placement.BottomRight,
                autoCancel: true,
                showInSubWindow: false,
                followTransformOfTarget: true,
                onStateChange: (event) => {
                  this.showModePopup = event.isVisible;
                },
              })
          }.width("100%")
        }
        GridItem() {
          if (this.controller?.microphonePermissionDenied ?? false) {
            Button("重新请求麦克风权限")
              .type(ButtonType.Capsule)
              .width("100%")
              .height(44)
              .fontSize(14)
              .fontColor(Color.White)
              .backgroundColor("rgba(77, 166, 255, 0.55)")
              .onClick(() => {
                const context: common.UIAbilityContext =
                  this.getUIContext().getHostContext() as common.UIAbilityContext;
                void this.controller?.startMicrophoneMonitoring(context, true);
              })
          } else {
            Column({ space: 8 }) {
              Text("麦克风频段增益")
                .fontSize(12)
                .fontColor("rgba(255, 255, 255, 0.62)")
                .width("100%")
                .textAlign(TextAlign.Start)
              Row({ space: 4 }) {
                ForEach(
                  Array.from({ length: TunerSpectrumBars }, (_value: number, index: number) => index),
                  (index: number) => {
                    Column() {
                      Column()
                        .width("100%")
                        .height(this.getSpectrumBarHeightPercent(index))
                        .borderRadius(3)
                        .backgroundColor(this.getSpectrumBarColor(index));
                    }
                    .layoutWeight(1)
                    .width("100%")
                    .height("100%")
                    .justifyContent(FlexAlign.End);
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
              Row() {
                Column() {
                  Text("低频")
                    .fontSize(11)
                    .fontColor("rgba(255, 255, 255, 0.58)")
                    .width("100%")
                    .textAlign(TextAlign.Start)
                    .margin({ bottom: -10 })
                  Slider({
                    value: this.controller?.microphoneGainLow ?? 0.5,
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
                      this.controller?.setMicrophoneBandGain('low', value);
                    })
                }
                .layoutWeight(1)
                Column() {
                  Text("中频")
                    .fontSize(11)
                    .fontColor("rgba(255, 255, 255, 0.58)")
                    .width("100%")
                    .textAlign(TextAlign.Start)
                    .margin({ bottom: -10 })
                  Slider({
                    value: this.controller?.microphoneGainMid ?? 0.5,
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
                      this.controller?.setMicrophoneBandGain('mid', value);
                    })
                }
                .layoutWeight(1)
                Column() {
                  Text("高频")
                    .fontSize(11)
                    .fontColor("rgba(255, 255, 255, 0.58)")
                    .width("100%")
                    .textAlign(TextAlign.Start)
                    .margin({ bottom: -10 })
                  Slider({
                    value: this.controller?.microphoneGainHigh ?? 0.5,
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
                      this.controller?.setMicrophoneBandGain('high', value);
                    })
                }
                .layoutWeight(1)
              }
              .width("100%")
            }.width("100%")
          }
        }.visibility(this.isReferenceToneEnabled() ? Visibility.None : Visibility.Visible)
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
