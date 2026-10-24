import { ScrollSpinBox } from '../../common/ui/ScrollSpinBox';
import {
  ContainerPadding,
  DropdownMenuBackgroundColor,
  DropdownMenuPrimaryBlurStyle,
  toVisibility
} from '../../common/ui/UIComponents';
import {
  getPianoContentWidthVp,
  getPianoNoteLabel,
  PDFPianoController,
  PianoBlackKeyHeightVp,
  PianoBlackKeyItem,
  PianoBlackKeyTopOffsetVp,
  PianoBlackKeyWidthFraction,
  PianoKeyboardHeightVp,
  PianoPanelPaddingVp,
  PianoReferenceHzMax,
  PianoReferenceHzMin,
  PianoReferenceHzPresets,
  PianoResizeGapVp,
  PianoResizeHandleWidthVp,
  PianoResizeSide,
  PianoSoundProgramLabels,
  PianoSoundProgramValues,
  PianoWhiteKeyItem,
  PianoWhiteKeyWidthVp
} from './PDFPianoController';
import { SharedPanelBackgroundColor, SharedPanelControlHighlightColor } from '../viewer/PDFPanelVisualConstants';
import { FloatingPanelOffset } from '../panels/FloatingPanelChrome';

export const FloatingPianoDefaultScale: number = 1;
export const FloatingPianoMinScale: number = 0.4;
export const FloatingPianoMaxScale: number = 1.6;
const FloatingPianoDragDistanceVp: number = 1;
const PianoSectionGap: number = 8;
const PianoHeaderGap: number = 8;
const PianoHeaderCloseButtonWidth: number = 48;
const PianoHeaderRowHeight: number = 44;
const PianoHeaderDragMaxWidth: Length = `calc(100% - ${PianoHeaderCloseButtonWidth + PianoHeaderGap}vp)`;
const PianoTuneBlockHeight: number = 36;
const PianoTuneWheelHeight: number = 32;
/** 完整按钮行（音色+音高+预设+八度-+保持）大约要这么宽，再窄「八度-」会裁字。 */
const PianoCompactControlsEnterWidthVp: number = 352;
const PianoCompactControlsExitWidthVp: number = 360;

interface PianoPopupStateEvent {
  isVisible: boolean;
}

interface PianoResizeHandleConfig {
  side: PianoResizeSide;
}

export function getFloatingPianoTotalWidth(whiteKeyCount: number, scale: number): number {
  const clampedScale: number = Math.max(FloatingPianoMinScale, Math.min(FloatingPianoMaxScale, scale));
  return getPianoContentWidthVp(whiteKeyCount) * clampedScale;
}

@ComponentV2
export struct PDFPianoPanelContent {
  @Param controller: PDFPianoController | undefined = undefined;
  @Param useDocked: boolean = false;
  @Param dockedTopOffsetVp: number = 0;
  @Param hostScale: number = FloatingPianoDefaultScale;
  @Param hostOffset: FloatingPanelOffset = { x: 0, y: 0 };
  @Param showDragHandle: boolean = true;
  @Event onInteraction: () => void = () => {
  };
  @Event onTouchStateChanged: (active: boolean) => void = (_active: boolean) => {
  };
  @Event onWindowAreaHeightChanged: (heightVp: number) => void = (_heightVp: number) => {
  };
  @Event onContentWidthChanged: (side: PianoResizeSide) => void = (_side: PianoResizeSide) => {
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
  @Local showReferencePresetPopup: boolean = false;
  @Local showCompactMorePopup: boolean = false;
  @Local compactControlsActive: boolean = false;
  @Local controlRowWidthVp: number = 0;
  @Local highlightTick: number = 0;
  private pointerIds: number[] = [];
  private pointerMidis: number[] = [];
  private leftResizeAnchorLowest: number = 48;
  private leftResizeAnchorCount: number = 15;
  private rightResizeAnchorLowest: number = 48;
  private rightResizeAnchorCount: number = 15;
  private isPanelPinching: boolean = false;

  private getPanelContentWidthVp(): number {
    return getPianoContentWidthVp(this.controller?.whiteKeyCount ?? 15);
  }

  private getWhiteKeys(): PianoWhiteKeyItem[] {
    if (!this.controller) {
      return [];
    }
    return this.controller.getVisibleWhiteKeys();
  }

  private getBlackKeys(): PianoBlackKeyItem[] {
    if (!this.controller) {
      return [];
    }
    return this.controller.getVisibleBlackKeys();
  }

  private getKeyboardInnerWidthVp(): number {
    return (this.controller?.whiteKeyCount ?? 15) * PianoWhiteKeyWidthVp;
  }

  private getBlackKeyOffsetX(item: PianoBlackKeyItem): number {
    const blackWidth: number = PianoWhiteKeyWidthVp * PianoBlackKeyWidthFraction;
    return (item.whiteIndexLeft + 1) * PianoWhiteKeyWidthVp - blackWidth / 2;
  }

  private bumpHighlight(): void {
    this.highlightTick += 1;
  }

  private getWhiteKeyColor(midi: number): string {
    if ((this.highlightTick >= 0) && (this.controller?.isMidiSounding(midi) ?? false)) {
      return 'rgba(196, 220, 255, 0.96)';
    }
    return '#F4F1EA';
  }

  private getWhiteKeyFontColor(midi: number): string {
    if ((this.highlightTick >= 0) && (this.controller?.isMidiSounding(midi) ?? false)) {
      return '#1A3358';
    }
    return 'rgba(32, 36, 44, 0.78)';
  }

  private getBlackKeyColor(midi: number): string {
    if ((this.highlightTick >= 0) && (this.controller?.isMidiSounding(midi) ?? false)) {
      return '#4DA6FF';
    }
    return '#1B1E24';
  }

  private handlePinchStart(): void {
    if (this.useDocked) {
      return;
    }
    this.isPanelPinching = true;
    this.onHostPinchStart();
  }

  private handlePinchUpdate(event: GestureEvent): void {
    if (this.useDocked) {
      return;
    }
    this.onHostPinchUpdate(event);
  }

  private handlePinchEnd(): void {
    if (this.useDocked) {
      return;
    }
    this.isPanelPinching = false;
    this.onHostPinchEnd();
  }

  private shouldShowResizeHandles(): boolean {
    return !this.useDocked;
  }

  private canShiftOctave(direction: number): boolean {
    return this.controller?.canShiftOctave(direction) ?? false;
  }

  aboutToAppear(): void {
    this.updateCompactControlsFromWidth(this.getPanelContentWidthVp() - PianoPanelPaddingVp * 2);
  }

  private updateCompactControlsFromWidth(widthVp: number): void {
    if (widthVp <= 0) {
      return;
    }
    if (Math.abs(widthVp - this.controlRowWidthVp) > 0.5) {
      this.controlRowWidthVp = widthVp;
    }
    if (this.compactControlsActive) {
      if (widthVp >= PianoCompactControlsExitWidthVp) {
        this.compactControlsActive = false;
        this.showCompactMorePopup = false;
      }
      return;
    }
    if (widthVp < PianoCompactControlsEnterWidthVp) {
      this.compactControlsActive = true;
      this.showReferencePresetPopup = false;
    }
  }

  private hitTestKey(localX: number, localY: number): number {
    const whiteKeys: PianoWhiteKeyItem[] = this.getWhiteKeys();
    if (whiteKeys.length === 0) {
      return -1;
    }
    const keyboardWidth: number = this.getKeyboardInnerWidthVp();
    if (localX < 0 || localX > keyboardWidth || localY < 0 || localY > PianoKeyboardHeightVp) {
      return -1;
    }
    if (localY <= PianoBlackKeyHeightVp + PianoBlackKeyTopOffsetVp) {
      const blackKeys: PianoBlackKeyItem[] = this.getBlackKeys();
      const blackWidth: number = PianoWhiteKeyWidthVp * PianoBlackKeyWidthFraction;
      for (let index = 0; index < blackKeys.length; index++) {
        const left: number = this.getBlackKeyOffsetX(blackKeys[index]);
        if (localX >= left && localX <= left + blackWidth) {
          return blackKeys[index].midi;
        }
      }
    }
    const whiteIndex: number = Math.min(whiteKeys.length - 1, Math.max(0, Math.floor(localX / PianoWhiteKeyWidthVp)));
    return whiteKeys[whiteIndex].midi;
  }

  private findPointerIndex(fingerId: number): number {
    for (let index = 0; index < this.pointerIds.length; index++) {
      if (this.pointerIds[index] === fingerId) {
        return index;
      }
    }
    return -1;
  }

  private otherPointerHolds(midi: number, exceptFingerId: number): boolean {
    for (let index = 0; index < this.pointerIds.length; index++) {
      if (this.pointerIds[index] !== exceptFingerId && this.pointerMidis[index] === midi) {
        return true;
      }
    }
    return false;
  }

  private bindPointer(fingerId: number, midi: number): void {
    const existing: number = this.findPointerIndex(fingerId);
    if (existing >= 0) {
      this.pointerMidis[existing] = midi;
      return;
    }
    this.pointerIds.push(fingerId);
    this.pointerMidis.push(midi);
  }

  private unbindPointer(fingerId: number): number {
    const existing: number = this.findPointerIndex(fingerId);
    if (existing < 0) {
      return -1;
    }
    const midi: number = this.pointerMidis[existing];
    const nextIds: number[] = [];
    const nextMidis: number[] = [];
    for (let index = 0; index < this.pointerIds.length; index++) {
      if (index !== existing) {
        nextIds.push(this.pointerIds[index]);
        nextMidis.push(this.pointerMidis[index]);
      }
    }
    this.pointerIds = nextIds;
    this.pointerMidis = nextMidis;
    return midi;
  }

  private pressMidi(midi: number): void {
    if (!this.controller || midi < 0) {
      return;
    }
    if (this.controller.autoHoldEnabled) {
      this.controller.toggleLatch(midi);
      this.bumpHighlight();
      return;
    }
    this.controller.noteOn(midi);
    this.bumpHighlight();
  }

  private releaseMidi(midi: number, fingerId: number): void {
    if (!this.controller || midi < 0 || this.controller.autoHoldEnabled) {
      return;
    }
    if (this.otherPointerHolds(midi, fingerId)) {
      return;
    }
    this.controller.noteOff(midi);
    this.bumpHighlight();
  }

  private handleKeyboardTouch(event: TouchEvent): void {
    for (let index = 0; index < event.changedTouches.length; index++) {
      const touch: TouchObject = event.changedTouches[index];
      if (event.type === TouchType.Down) {
        const midi: number = this.hitTestKey(touch.x, touch.y);
        if (midi >= 0) {
          this.bindPointer(touch.id, midi);
          this.pressMidi(midi);
        }
      } else if (event.type === TouchType.Move) {
        if (this.isPanelPinching) {
          continue;
        }
        const pointerIndex: number = this.findPointerIndex(touch.id);
        if (pointerIndex < 0 || (this.controller?.autoHoldEnabled ?? false)) {
          continue;
        }
        const nextMidi: number = this.hitTestKey(touch.x, touch.y);
        const previousMidi: number = this.pointerMidis[pointerIndex];
        if (nextMidi < 0 || nextMidi === previousMidi) {
          continue;
        }
        this.releaseMidi(previousMidi, touch.id);
        this.bindPointer(touch.id, nextMidi);
        this.pressMidi(nextMidi);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        const previousMidi: number = this.unbindPointer(touch.id);
        this.releaseMidi(previousMidi, touch.id);
      }
    }
  }

  private beginLeftResize(): void {
    this.leftResizeAnchorLowest = this.controller?.lowestMidi ?? 48;
    this.leftResizeAnchorCount = this.controller?.whiteKeyCount ?? 15;
  }

  private updateLeftResize(event: GestureEvent): void {
    const deltaKeys: number = Math.round(-event.offsetX / (this.hostScale * PianoWhiteKeyWidthVp));
    this.controller?.resizeFromLeftAnchor(this.leftResizeAnchorLowest, this.leftResizeAnchorCount, deltaKeys);
    this.onContentWidthChanged('left');
  }

  private beginRightResize(): void {
    this.rightResizeAnchorLowest = this.controller?.lowestMidi ?? 48;
    this.rightResizeAnchorCount = this.controller?.whiteKeyCount ?? 15;
  }

  private updateRightResize(event: GestureEvent): void {
    const deltaKeys: number = Math.round(event.offsetX / (this.hostScale * PianoWhiteKeyWidthVp));
    this.controller?.resizeFromRightAnchor(this.rightResizeAnchorLowest, this.rightResizeAnchorCount, deltaKeys);
    this.onContentWidthChanged('right');
  }

  @Builder
  private buildResizeHandle($$: PianoResizeHandleConfig) {
    Column() {
      Row({ space: 3 }) {
        Column({ space: 3 }) {
          ForEach([0, 1, 2, 3], (dotIndex: number) => {
            Text('')
              .width(4)
              .height(4)
              .borderRadius(2)
              .backgroundColor('rgba(255, 255, 255, 0.26)')
          }, (dotIndex: number) => `piano-resize-${$$.side}-l-${dotIndex}`)
        }
        Column({ space: 3 }) {
          ForEach([0, 1, 2, 3], (otherDot: number) => {
            Text('')
              .width(4)
              .height(4)
              .borderRadius(2)
              .backgroundColor('rgba(255, 255, 255, 0.16)')
          }, (otherDot: number) => `piano-resize-${$$.side}-r-${otherDot}`)
        }
      }
    }
    .width(PianoResizeHandleWidthVp)
    .height(PianoKeyboardHeightVp)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(10)
    .backgroundColor('rgba(255, 255, 255, 0.05)')
    .border({ width: 1, color: 'rgba(255, 255, 255, 0.06)' })
    .margin({
      right: $$.side === 'left' ? PianoResizeGapVp : 0,
      left: $$.side === 'right' ? PianoResizeGapVp : 0
    })
    .gesture(
      PanGesture({ fingers: 1, distance: 1 })
        .onActionStart((_event: GestureEvent) => {
          if ($$.side === 'left') {
            this.beginLeftResize();
          } else {
            this.beginRightResize();
          }
          this.onTouchStateChanged(true);
        })
        .onActionUpdate((event: GestureEvent) => {
          if ($$.side === 'left') {
            this.updateLeftResize(event);
          } else {
            this.updateRightResize(event);
          }
        })
        .onActionEnd((_event: GestureEvent) => {
          this.onTouchStateChanged(false);
        })
        .onActionCancel(() => {
          this.onTouchStateChanged(false);
        })
    )
  }

  @Builder
  private buildReferencePresetPopup() {
    Column({ space: 6 }) {
      ForEach(PianoReferenceHzPresets, (presetHz: number) => {
        Button(`${presetHz} Hz`)
          .type(ButtonType.Capsule)
          .width('100%')
          .height(34)
          .fontSize(13)
          .fontColor(Color.White)
          .backgroundColor(
            (this.controller?.referenceHz ?? 440) === presetHz
              ? 'rgba(77, 166, 255, 0.88)'
              : 'rgba(255, 255, 255, 0.10)'
          )
          .onClick(() => {
            this.controller?.setReferenceHz(presetHz);
            this.showReferencePresetPopup = false;
          })
      }, (presetHz: number) => `piano-a4-preset-${presetHz}`)
    }
    .width(128)
    .padding(8)
    .backgroundColor(DropdownMenuBackgroundColor)
    .borderRadius(12)
  }

  @Builder
  private buildCompactMorePopup() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        ScrollSpinBox({
          value: this.controller?.soundProgram ?? 0,
          values: PianoSoundProgramValues,
          labels: PianoSoundProgramLabels,
          canLoop: false,
          valueFontSize: 13,
          debounceMs: 40,
          onValueChange: (nextProgram: number) => {
            this.controller?.setSoundProgram(nextProgram);
          },
          itemHeight: 16,
          gradientHeight: 12
        })
          .width(68)
          .height(PianoTuneWheelHeight)
          .borderRadius(10)
          .backgroundColor(SharedPanelControlHighlightColor)

        ScrollSpinBox({
          value: this.controller?.referenceHz ?? 440,
          canLoop: false,
          min: PianoReferenceHzMin,
          max: PianoReferenceHzMax,
          step: 1,
          valueFontSize: 14,
          debounceMs: 80,
          onValueChange: (nextHz: number) => {
            this.controller?.setReferenceHz(nextHz);
          },
          itemHeight: 16,
          gradientHeight: 12
        })
          .width(64)
          .height(PianoTuneWheelHeight)
          .borderRadius(10)
          .backgroundColor(SharedPanelControlHighlightColor)
      }
      .width('100%')
      .height(PianoTuneWheelHeight)

      ForEach(PianoReferenceHzPresets, (presetHz: number) => {
        Button(`${presetHz} Hz`)
          .type(ButtonType.Capsule)
          .width('100%')
          .height(34)
          .fontSize(13)
          .fontColor(Color.White)
          .backgroundColor(
            (this.controller?.referenceHz ?? 440) === presetHz
              ? 'rgba(77, 166, 255, 0.88)'
              : 'rgba(255, 255, 255, 0.10)'
          )
          .onClick(() => {
            this.controller?.setReferenceHz(presetHz);
          })
      }, (presetHz: number) => `piano-compact-a4-preset-${presetHz}`)
    }
    .width(154)
    .padding(8)
    .backgroundColor(DropdownMenuBackgroundColor)
    .borderRadius(12)
  }

  @Builder
  private buildFullControlRow() {
    Row({ space: 6 }) {
      ScrollSpinBox({
        value: this.controller?.soundProgram ?? 0,
        values: PianoSoundProgramValues,
        labels: PianoSoundProgramLabels,
        canLoop: false,
        valueFontSize: 13,
        debounceMs: 40,
        onValueChange: (nextProgram: number) => {
          this.controller?.setSoundProgram(nextProgram);
        },
        itemHeight: 16,
        gradientHeight: 12
      })
        .width(68)
        .height(PianoTuneWheelHeight)
        .borderRadius(10)
        .backgroundColor(SharedPanelControlHighlightColor)

      ScrollSpinBox({
        value: this.controller?.referenceHz ?? 440,
        canLoop: false,
        min: PianoReferenceHzMin,
        max: PianoReferenceHzMax,
        step: 1,
        valueFontSize: 14,
        debounceMs: 80,
        onValueChange: (nextHz: number) => {
          this.controller?.setReferenceHz(nextHz);
        },
        itemHeight: 16,
        gradientHeight: 12
      })
        .width(64)
        .height(PianoTuneWheelHeight)
        .borderRadius(10)
        .backgroundColor(SharedPanelControlHighlightColor)

      Button({ type: ButtonType.Normal }) {
        Text('预设')
          .fontSize(12)
          .fontColor(Color.White)
          .maxLines(1)
          .textAlign(TextAlign.Center)
      }
      .layoutWeight(1)
      .height(PianoTuneBlockHeight)
      .padding({ left: 4, right: 4 })
      .borderRadius(10)
      .backgroundColor('rgba(255, 255, 255, 0.10)')
      .onClick(() => {
        this.showReferencePresetPopup = true;
      })
      .bindPopup(this.showReferencePresetPopup, {
        builder: this.buildReferencePresetPopup,
        placement: Placement.Bottom,
        backgroundBlurStyle: DropdownMenuPrimaryBlurStyle,
        popupColor: Color.Transparent,
        autoCancel: true,
        showInSubWindow: false,
        followTransformOfTarget: true,
        onStateChange: (event: PianoPopupStateEvent) => {
          this.showReferencePresetPopup = event.isVisible;
        }
      })

      Button({ type: ButtonType.Normal }) {
        Text('八度-')
          .fontSize(12)
          .fontColor(Color.White)
          .maxLines(1)
          .textAlign(TextAlign.Center)
      }
      .layoutWeight(1)
      .height(PianoTuneBlockHeight)
      .padding({ left: 4, right: 4 })
      .borderRadius(10)
      .enabled(this.canShiftOctave(-1))
      .backgroundColor('rgba(255, 255, 255, 0.12)')
      .onClick(() => this.controller?.shiftOctave(-1))

      Button({ type: ButtonType.Normal }) {
        Text('八度+')
          .fontSize(12)
          .fontColor(Color.White)
          .maxLines(1)
          .textAlign(TextAlign.Center)
      }
      .layoutWeight(1)
      .height(PianoTuneBlockHeight)
      .padding({ left: 4, right: 4 })
      .borderRadius(10)
      .enabled(this.canShiftOctave(1))
      .backgroundColor('rgba(255, 255, 255, 0.12)')
      .onClick(() => this.controller?.shiftOctave(1))

      Button({ type: ButtonType.Normal }) {
        Text('保持')
          .fontSize(12)
          .fontColor(Color.White)
          .maxLines(1)
          .textAlign(TextAlign.Center)
      }
      .layoutWeight(1)
      .height(PianoTuneBlockHeight)
      .padding({ left: 4, right: 4 })
      .borderRadius(10)
      .backgroundColor((this.controller?.autoHoldEnabled ?? false)
        ? 'rgba(77, 166, 255, 0.88)'
        : 'rgba(255, 255, 255, 0.10)')
      .onClick(() => {
        this.controller?.setAutoHoldEnabled(!(this.controller?.autoHoldEnabled ?? false));
      })
    }
    .width('100%')
    .height(PianoTuneBlockHeight)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildCompactControlRow() {
    Row({ space: 6 }) {
      Button({ type: ButtonType.Normal }) {
        Text('...')
          .fontSize(16)
          .fontColor(Color.White)
          .maxLines(1)
          .textAlign(TextAlign.Center)
      }
      .layoutWeight(1)
      .height(PianoTuneBlockHeight)
      .borderRadius(10)
      .backgroundColor(this.showCompactMorePopup
        ? 'rgba(77, 166, 255, 0.88)'
        : 'rgba(255, 255, 255, 0.10)')
      .onClick(() => {
        this.showCompactMorePopup = true;
      })
      .bindPopup(this.showCompactMorePopup, {
        builder: this.buildCompactMorePopup,
        placement: Placement.Bottom,
        backgroundBlurStyle: DropdownMenuPrimaryBlurStyle,
        popupColor: Color.Transparent,
        autoCancel: true,
        showInSubWindow: false,
        followTransformOfTarget: true,
        onStateChange: (event: PianoPopupStateEvent) => {
          this.showCompactMorePopup = event.isVisible;
        }
      })

      Button({ type: ButtonType.Normal }) {
        Text('-')
          .fontSize(18)
          .fontColor(Color.White)
          .maxLines(1)
          .textAlign(TextAlign.Center)
      }
      .layoutWeight(1)
      .height(PianoTuneBlockHeight)
      .borderRadius(10)
      .enabled(this.canShiftOctave(-1))
      .backgroundColor('rgba(255, 255, 255, 0.12)')
      .onClick(() => this.controller?.shiftOctave(-1))

      Button({ type: ButtonType.Normal }) {
        Text('+')
          .fontSize(18)
          .fontColor(Color.White)
          .maxLines(1)
          .textAlign(TextAlign.Center)
      }
      .layoutWeight(1)
      .height(PianoTuneBlockHeight)
      .borderRadius(10)
      .enabled(this.canShiftOctave(1))
      .backgroundColor('rgba(255, 255, 255, 0.12)')
      .onClick(() => this.controller?.shiftOctave(1))

      Button({ type: ButtonType.Normal }) {
        Text('H')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .maxLines(1)
          .textAlign(TextAlign.Center)
      }
      .layoutWeight(1)
      .height(PianoTuneBlockHeight)
      .borderRadius(10)
      .backgroundColor((this.controller?.autoHoldEnabled ?? false)
        ? 'rgba(77, 166, 255, 0.88)'
        : 'rgba(255, 255, 255, 0.10)')
      .onClick(() => {
        this.controller?.setAutoHoldEnabled(!(this.controller?.autoHoldEnabled ?? false));
      })
    }
    .width('100%')
    .height(PianoTuneBlockHeight)
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column({ space: PianoSectionGap }) {
      Row({ space: PianoHeaderGap }) {
        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Row({ space: 3 }) {
              ForEach([0, 1, 2, 3], (index: number) => {
                Text('')
                  .width(4)
                  .height(4)
                  .borderRadius(2)
                  .backgroundColor('rgba(255, 255, 255, 0.26)')
              }, (index: number) => `piano-drag-grip-top-${index}`)
            }
            Row({ space: 3 }) {
              ForEach([0, 1, 2, 3], (index: number) => {
                Text('')
                  .width(4)
                  .height(4)
                  .borderRadius(2)
                  .backgroundColor('rgba(255, 255, 255, 0.16)')
              }, (index: number) => `piano-drag-grip-bottom-${index}`)
            }
          }
          .visibility(toVisibility(this.showDragHandle))
          Text('键盘')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
        }
        .height(PianoHeaderRowHeight)
        .width('100%')
        .constraintSize({ maxWidth: PianoHeaderDragMaxWidth })
        .padding(ContainerPadding)
        .alignItems(VerticalAlign.Center)
        .borderRadius(10)
        .backgroundColor('rgba(255, 255, 255, 0.05)')
        .border({ width: 1, color: 'rgba(255, 255, 255, 0.06)' })
        .gesture(
          PanGesture({ fingers: 1, distance: FloatingPianoDragDistanceVp })
            .onActionStart((_event: GestureEvent) => {
              this.onHostDragStart();
            })
            .onActionUpdate((event: GestureEvent) => {
              this.onHostDragUpdate(event);
            })
            .onActionEnd((_event: GestureEvent) => {
              this.onHostDragEnd();
            })
            .onActionCancel(() => {
              this.onHostDragEnd();
            })
        )
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor([Color.White])
        }
        .width(PianoHeaderCloseButtonWidth)
        .height(PianoHeaderRowHeight)
        .borderRadius(10)
        .backgroundColor('rgba(255, 255, 255, 0.16)')
        .onClick(() => this.onClose())
      }
      .width('100%')
      .height(PianoHeaderRowHeight)

      Column() {
        if (this.compactControlsActive) {
          this.buildCompactControlRow()
        } else {
          this.buildFullControlRow()
        }
      }
      .width('100%')
      .height(PianoTuneBlockHeight)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.updateCompactControlsFromWidth(newValue.width as number);
      })

      Row() {
        if (this.shouldShowResizeHandles()) {
          this.buildResizeHandle({ side: 'left' })
        }

        Stack({ alignContent: Alignment.TopStart }) {
          Row() {
            ForEach(this.getWhiteKeys(), (keyItem: PianoWhiteKeyItem) => {
              Column() {
                Blank()
                  .layoutWeight(1)
                Text(keyItem.label)
                  .fontSize(10)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.getWhiteKeyFontColor(keyItem.midi))
                  .margin({ bottom: 6 })
              }
              .width(PianoWhiteKeyWidthVp)
              .height(PianoKeyboardHeightVp)
              .justifyContent(FlexAlign.End)
              .alignItems(HorizontalAlign.Center)
              .backgroundColor(this.getWhiteKeyColor(keyItem.midi))
              .border({ width: 0.5, color: 'rgba(20, 24, 32, 0.18)' })
              .hitTestBehavior(HitTestMode.Transparent)
            }, (keyItem: PianoWhiteKeyItem) => `piano-wk-${keyItem.midi}`)
          }
          .width(this.getKeyboardInnerWidthVp())
          .height(PianoKeyboardHeightVp)

          ForEach(this.getBlackKeys(), (keyItem: PianoBlackKeyItem) => {
            Column() {
              Blank()
                .layoutWeight(1)
              Text(getPianoNoteLabel(keyItem.midi))
                .fontSize(8)
                .fontColor(Color.White)
                .margin({ bottom: 4 })
            }
            .width(PianoWhiteKeyWidthVp * PianoBlackKeyWidthFraction)
            .height(PianoBlackKeyHeightVp)
            .justifyContent(FlexAlign.End)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor(this.getBlackKeyColor(keyItem.midi))
            .borderRadius({ bottomLeft: 3, bottomRight: 3 })
            .position({ x: this.getBlackKeyOffsetX(keyItem), y: PianoBlackKeyTopOffsetVp })
            .hitTestBehavior(HitTestMode.Transparent)
          }, (keyItem: PianoBlackKeyItem) => `piano-bk-${keyItem.whiteIndexLeft}-${keyItem.midi}`)
        }
        .width(this.getKeyboardInnerWidthVp())
        .height(PianoKeyboardHeightVp)
        .clip(false)
        .monopolizeEvents(true)
        .onTouch((event: TouchEvent) => {
          this.handleKeyboardTouch(event);
        })
        .gesture(
          PinchGesture({ fingers: 2 })
            .onActionStart((_event: GestureEvent) => {
              this.handlePinchStart();
            })
            .onActionUpdate((event: GestureEvent) => {
              this.handlePinchUpdate(event);
            })
            .onActionEnd((_event: GestureEvent) => {
              this.handlePinchEnd();
            })
            .onActionCancel(() => {
              this.handlePinchEnd();
            })
        )

        if (this.shouldShowResizeHandles()) {
          this.buildResizeHandle({ side: 'right' })
        }
      }
      .width('100%')
      .height(PianoKeyboardHeightVp)
      .clip(false)
    }
    .width(this.useDocked ? '100%' : this.getPanelContentWidthVp())
    .padding(PianoPanelPaddingVp)
    .backgroundColor(SharedPanelBackgroundColor)
    .borderRadius({
      topLeft: this.useDocked ? 0 : 18,
      topRight: this.useDocked ? 0 : 18,
      bottomLeft: 18,
      bottomRight: 18
    })
    .margin(0)
    .border({ width: 1, color: 'rgba(255, 255, 255, 0.07)' })
    .shadow({ radius: 16, color: 'rgba(0, 0, 0, 0.24)', offsetY: 4 })
    .align(Alignment.TopStart)
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: this.useDocked ? -14 : 14 })))
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
          this.handlePinchStart();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.handlePinchUpdate(event);
        })
        .onActionEnd((_event: GestureEvent) => {
          this.handlePinchEnd();
        })
        .onActionCancel(() => {
          this.handlePinchEnd();
        })
    )
  }
}
