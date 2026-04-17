import { LengthMetrics } from '@kit.ArkUI';
import { ScrollSpinBox } from '../../components/ScrollSpinBox';
import { ButtonColor, StyleIconButton } from '../../components/UIComponents';
import { PDFMetronomeController } from './PDFMetronomeController';

const MetronomeBeatSpacing: LengthMetrics = LengthMetrics.vp(10);
const MetronomeWindowWidth: number = 400;

@ComponentV2
export struct PDFMetronomePanel {
  @Param controller: PDFMetronomeController | undefined = undefined;
  metronomeGridLayout: GridLayoutOptions = {
    regularSize: [1, 1],
    irregularIndexes: [6, 7, 8],
    onGetIrregularSizeByIndex: (): [number, number] => [1, 2]
  };

  private getBeatIndices(): number[] {
    const beats: number[] = [];
    for (let i = 0; i < (this.controller?.numerator ?? 0); i++) {
      beats.push(i);
    }
    return beats;
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

          Grid(undefined, this.metronomeGridLayout) {
            // Row 0: Labels
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

            // Row 1: Tempo Spin Controls
            GridItem() {
              ScrollSpinBox({
                value: this.controller?.bpm ?? 120,
                min: 1,
                max: 600,
                step: 1,
                valueFontSize: 30,
                onValueChange: (value: number) => this.controller?.setBpm(value),
                itemHeight: 30,
                gradientHeight: 35
              })
              .width('100%')
              .height(120)
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .borderRadius(16)
              .backgroundColor('rgba(255, 255, 255, 0.2)')
            }

            // Row 1: Time Signature Controls
            GridItem() {
              Row({ space: 6 }) {
                ScrollSpinBox({
                  value: this.controller?.numerator ?? 4,
                  min: 1,
                  max: 16,
                  step: 1,
                  valueFontSize: 28,
                  onValueChange: (value: number) => this.controller?.setNumerator(value),
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
                  valueFontSize: 28,
                  onValueChange: (value: number) => this.controller?.setDenominator(value),
                  itemHeight: 28,
                  gradientHeight: 35
                })
                .layoutWeight(1)
              }
              .width('100%')
              .height(120)
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .borderRadius(16)
              .backgroundColor('rgba(255, 255, 255, 0.2)')
            }

            // Row 2: Preset Buttons
            GridItem() {
              Row({ space: 6 }) {
                Button('-10')
                  .type(ButtonType.Capsule)
                  .flexGrow(1)
                  .height(34)
                  .fontSize(13)
                  .fontColor(Color.White)
                  .backgroundColor('rgba(255, 255, 255, 0.1)')
                  .onClick(() => this.controller?.adjustBpm(-10))

                Button('预设')
                  .type(ButtonType.Capsule)
                  .flexGrow(1)
                  .height(34)
                  .fontSize(13)
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

            // Row 3: 拍点 Label (spans 2 columns)
            GridItem() {
              Text('拍点')
                .fontSize(12)
                .fontColor('rgba(255, 255, 255, 0.62)')
                .width('100%')
                .textAlign(TextAlign.Start)
            }

            // Row 4: Beat Controls (spans 2 columns)
            GridItem() {
              Flex({ wrap: FlexWrap.Wrap, space: { main: MetronomeBeatSpacing, cross: MetronomeBeatSpacing } }) {
                ForEach(this.getBeatIndices(), (beat: number) => {
                  Stack() {
                    Text(`${beat + 1}`)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Color.White)
                  }
                  .flexGrow(1)
                  .height(44)
                  .borderRadius(14)
                  .backgroundColor(this.getBeatColor(beat))
                  .border({
                    width: beat === 0 ? 2 : 1,
                    color: beat === 0 ? 'rgba(255, 159, 67, 0.45)' : 'rgba(255, 255, 255, 0.06)'
                  })
                }, (beat: number) => `${beat}`)
              }
              .width('100%')
              .padding(12)
              .borderRadius(16)
              .backgroundColor('rgba(255, 255, 255, 0.035)')
            }

            // Row 5: Play/Stop Button (spans 2 columns)
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
        .width(MetronomeWindowWidth)
        .padding(16)
        .backgroundColor('rgba(8, 10, 14, 0.78)')
        .borderRadius(18)
        .border({ width: 1, color: 'rgba(255, 255, 255, 0.07)' })
        .shadow({ radius: 16, color: 'rgba(0, 0, 0, 0.24)', offsetY: 4 })
        .align(Alignment.TopStart)
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -14 })))
      }

      if (!(this.controller?.showWindow ?? false) && (this.controller?.isPlaying ?? false)) {
        StyleIconButton({
          icon: $r('sys.symbol.clock'),
          alternateColor: !(this.controller?.isPlaying ?? false) || (this.controller?.currentBeat ?? -1) < 0 ? 'rgba(35, 42, 53, 0.62)' : (this.controller?.floatingButtonColor ?? 'rgba(35, 42, 53, 0.62)'),
          onClickCallback: () => this.controller?.openWindow()
        })
          .scale({
            x: this.getFloatingButtonScale(),
            y: this.getFloatingButtonScale(),
            centerX: 22,
            centerY: 22
          })
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.92, y: 0.92 })))
      }
    }
    .alignContent(Alignment.TopStart)
  }
}
