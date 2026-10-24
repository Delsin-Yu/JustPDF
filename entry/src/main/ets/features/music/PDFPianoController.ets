import { preferences } from '@kit.ArkData';
import { audio } from '@kit.AudioKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { showAlertDialog } from '../../common/ui/UIComponents';
import {
  nativePianoAllNotesOff,
  nativePianoNoteOff,
  nativePianoNoteOn,
  nativePianoRetune,
  nativePianoSetProgram,
  prepareNativePiano,
  releaseNativePiano,
  startNativePiano,
  stopNativePiano
} from './PDFPianoNative';

const PianoReferenceHzPreferenceKey: string = 'pianoReferenceHz';
const PianoAutoHoldPreferenceKey: string = 'pianoAutoHold';
const PianoLowestMidiPreferenceKey: string = 'pianoLowestMidi';
const PianoWhiteKeyCountPreferenceKey: string = 'pianoWhiteKeyCount';
const PianoSoundProgramPreferenceKey: string = 'pianoSoundProgram';

export const PianoSoundProgramPiano: number = 0;
export const PianoSoundProgramOrgan: number = 1;
export const PianoSoundProgramSquare: number = 2;
export const PianoSoundProgramValues: number[] = [
  PianoSoundProgramPiano,
  PianoSoundProgramOrgan,
  PianoSoundProgramSquare
];
export const PianoSoundProgramLabels: string[] = ['钢琴', '风琴', '合成器'];

export const PianoReferenceHzMin: number = 200;
export const PianoReferenceHzMax: number = 600;
export const PianoReferenceHzPresets: number[] = [200, 220, 262, 415, 430, 432, 440, 442, 445, 523, 600];

export const PianoMinMidi: number = 36;
export const PianoMaxMidi: number = 108;
export const PianoDefaultLowestMidi: number = 48;
export const PianoDefaultWhiteKeyCount: number = 15;
export const PianoMinWhiteKeyCount: number = 7;
/** C2–C8 全部白键，左右拉伸可铺满当前音域。 */
export const PianoMaxWhiteKeyCount: number = 43;

export const PianoWhiteKeyWidthVp: number = 28;
export const PianoResizeHandleWidthVp: number = 22;
export const PianoResizeGapVp: number = 10;
export const PianoPanelPaddingVp: number = 10;
export const PianoKeyboardHeightVp: number = 152;
export const PianoBlackKeyHeightVp: number = 96;
/** 黑键上沿上移，避开与白键上沿浮点取整打架。 */
export const PianoBlackKeyTopOffsetVp: number = -2;
export const PianoBlackKeyWidthFraction: number = 0.62;
export const PianoEstimatedContentHeightVp: number = 270;

const PianoAudioSampleRateHz: number = 48000;
const PianoAudioMaxAmplitude: number = 32767;
const PianoVoiceGain: number = 0.34;
const PianoOutputScale: number = 0.96;
const PianoMaxVoices: number = 8;
const PianoAttackSeconds: number = 0.008;
const PianoFeltAttackSeconds: number = 0.008;
const PianoReleaseSeconds: number = 0.02;
const PianoAttackFrames: number = Math.max(1, Math.round(PianoAudioSampleRateHz * PianoAttackSeconds));
const PianoFeltAttackFrames: number = Math.max(1, Math.round(PianoAudioSampleRateHz * PianoFeltAttackSeconds));
const PianoReleaseFrames: number = Math.max(1, Math.round(PianoAudioSampleRateHz * PianoReleaseSeconds));
const PianoCompThreshold: number = 0.64;
const PianoCompRatio: number = 2.1;
const PianoNormLoudness: number = 0.30;
const PianoTwoPi: number = Math.PI * 2;
const PianoSineTableSize: number = 2048;
const PianoSineTableMask: number = 2047;
const PianoNoteNames: string[] = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
const PianoWhitePitchClasses: number[] = [0, 2, 4, 5, 7, 9, 11];
const PianoSineTable: Float32Array = createPianoSineTable();

function createPianoSineTable(): Float32Array {
  const table: Float32Array = new Float32Array(PianoSineTableSize);
  for (let index = 0; index < PianoSineTableSize; index++) {
    table[index] = Math.sin(PianoTwoPi * index / PianoSineTableSize);
  }
  return table;
}

export type PianoResizeSide = 'left' | 'right';
type PianoVoiceState = 'attack' | 'sustain' | 'release';

export interface PianoWhiteKeyItem {
  midi: number;
  label: string;
}

export interface PianoBlackKeyItem {
  midi: number;
  whiteIndexLeft: number;
}

interface PDFPianoControllerDependencies {
  getUIContext: () => UIContext;
  onVisualStateChanged?: () => void;
}

class PianoVoice {
  midi: number = 60;
  frequencyHz: number = 261.63;
  loudness: number = 1;
  envLevel: number = 0;
  releaseStartEnv: number = 1;
  state: PianoVoiceState = 'attack';
  framesInState: number = 0;
  framesSinceOn: number = 0;
  inUse: boolean = false;
  partialPhase: number[] = [0, 0, 0, 0, 0, 0];
  partialIncrement: number[] = [0, 0, 0, 0, 0, 0];
  partialAmp: number[] = [0, 0, 0, 0, 0, 0];
  partialLevel: number[] = [0, 0, 0, 0, 0, 0];
  partialDecay: number[] = [1, 1, 1, 1, 1, 1];
  partialCount: number = 2;
}

function createPianoVoicePool(): PianoVoice[] {
  const pool: PianoVoice[] = [];
  for (let index = 0; index < PianoMaxVoices; index++) {
    pool.push(new PianoVoice());
  }
  return pool;
}

export function isPianoWhiteKey(midi: number): boolean {
  const pitchClass: number = ((midi % 12) + 12) % 12;
  return PianoWhitePitchClasses.includes(pitchClass);
}

export function walkPianoWhiteKeys(startMidi: number, whiteKeyCount: number, direction: number): number {
  const step: number = direction >= 0 ? 1 : -1;
  let midi: number = startMidi;
  let seen: number = 1;
  while (seen < whiteKeyCount) {
    midi += step;
    if (isPianoWhiteKey(midi)) {
      seen += 1;
    }
  }
  return midi;
}

export function getPianoHighestMidi(lowestMidi: number, whiteKeyCount: number): number {
  return walkPianoWhiteKeys(lowestMidi, whiteKeyCount, 1);
}

export function getPianoContentWidthVp(whiteKeyCount: number): number {
  return PianoPanelPaddingVp * 2 + PianoResizeHandleWidthVp * 2 + PianoResizeGapVp * 2 +
    whiteKeyCount * PianoWhiteKeyWidthVp;
}

export function getPianoNoteLabel(midi: number): string {
  const pitchClass: number = ((midi % 12) + 12) % 12;
  const octave: number = Math.floor(midi / 12) - 1;
  const noteName: string = PianoNoteNames[pitchClass] ?? 'C';
  if (pitchClass === 0) {
    return `${noteName}${octave}`;
  }
  return noteName;
}

function snapMidiToWhiteKey(midi: number, direction: number): number {
  let snapped: number = Math.round(midi);
  if (isPianoWhiteKey(snapped)) {
    return snapped;
  }
  const step: number = direction >= 0 ? 1 : -1;
  for (let offset = 1; offset <= 12; offset++) {
    const candidate: number = snapped + step * offset;
    if (isPianoWhiteKey(candidate)) {
      return candidate;
    }
  }
  return PianoDefaultLowestMidi;
}

function clampNumber(value: number, minValue: number, maxValue: number): number {
  return Math.max(minValue, Math.min(maxValue, value));
}

function peakLimitSample(sample: number): number {
  const magnitude: number = Math.abs(sample);
  if (magnitude <= 0.88) {
    return sample;
  }
  const limited: number = 0.88 + (magnitude - 0.88) / (1 + (magnitude - 0.88) * 12);
  return sample < 0 ? -limited : limited;
}

@ObservedV2
export class PDFPianoController {
  private readonly dependencies: PDFPianoControllerDependencies;
  private preferenceStore?: preferences.Preferences;
  private audioRenderer: audio.AudioRenderer | undefined = undefined;
  private audioRendererLoading: boolean = false;
  private pendingRendererStop: Promise<void> | undefined = undefined;
  private audioRequestToken: number = 0;
  private audioPlaybackSessionToken: number = 0;
  private playbackStartRequested: boolean = false;
  private readonly voices: PianoVoice[] = createPianoVoicePool();
  private latchedMidis: number[] = [];
  private audioFailureAlertShown: boolean = false;
  private useNativeEngine: boolean = false;
  private dynPeak: number = 0;
  private dynRms2: number = 0;
  private dynNorm: number = 1;

  @Trace public showWindow: boolean = false;
  @Trace public referenceHz: number = 440;
  @Trace public soundProgram: number = PianoSoundProgramPiano;
  @Trace public autoHoldEnabled: boolean = false;
  @Trace public lowestMidi: number = PianoDefaultLowestMidi;
  @Trace public whiteKeyCount: number = PianoDefaultWhiteKeyCount;
  @Trace public soundingMidiNotes: number[] = [];
  @Trace public audioReady: boolean = false;

  private readonly handleAudioWriteData: audio.AudioRendererWriteDataCallback =
    (buffer: ArrayBuffer): audio.AudioDataCallbackResult => {
      const output: Int16Array = new Int16Array(buffer);
      this.mixVoicesIntoBuffer(output);
      return audio.AudioDataCallbackResult.VALID;
    };

  constructor(dependencies: PDFPianoControllerDependencies) {
    this.dependencies = dependencies;
  }

  initialize(preferenceStore: preferences.Preferences): void {
    this.preferenceStore = preferenceStore;
    this.loadPreferences(preferenceStore);
    this.initializeAudio();
  }

  cleanup(): void {
    this.allNotesOff(true);
    this.releaseAudio();
  }

  openWindow(): void {
    this.showWindow = true;
    this.playbackStartRequested = true;
    this.startAudioRendererPlayback(++this.audioPlaybackSessionToken);
  }

  closeWindow(): void {
    this.showWindow = false;
    this.allNotesOff(true);
    this.playbackStartRequested = false;
    this.audioPlaybackSessionToken += 1;
    this.stopAudioRendererPlayback('closeWindow');
  }

  toggleWindow(): void {
    if (this.showWindow) {
      this.closeWindow();
      return;
    }
    this.openWindow();
  }

  silenceForBackground(): void {
    this.allNotesOff(true);
    this.playbackStartRequested = false;
    this.audioPlaybackSessionToken += 1;
    this.stopAudioRendererPlayback('background');
  }

  setSoundProgram(program: number): void {
    const clamped: number = clampNumber(Math.round(program), PianoSoundProgramPiano, PianoSoundProgramSquare);
    if (this.soundProgram === clamped) {
      return;
    }
    this.soundProgram = clamped;
    this.dynPeak = 0;
    this.dynRms2 = 0;
    this.dynNorm = 1;
    if (this.useNativeEngine) {
      nativePianoSetProgram(clamped);
    } else {
      for (let index = 0; index < this.voices.length; index++) {
        if (this.voices[index].inUse) {
          this.configureFallbackPartials(this.voices[index], false);
          if (clamped === PianoSoundProgramSquare && this.voices[index].state === 'attack') {
            this.voices[index].envLevel = 1;
            this.voices[index].state = 'sustain';
          }
        }
      }
    }
    this.savePreferences();
  }

  setReferenceHz(nextHz: number): void {
    const clamped: number = this.clampReferenceHz(nextHz);
    if (this.referenceHz === clamped) {
      return;
    }
    this.referenceHz = clamped;
    this.retuneActiveVoices();
    this.savePreferences();
  }

  setAutoHoldEnabled(enabled: boolean): void {
    if (this.autoHoldEnabled === enabled) {
      return;
    }
    this.autoHoldEnabled = enabled;
    if (!enabled) {
      this.releaseLatchedNotes();
    }
    this.savePreferences();
  }

  shiftOctave(direction: number): void {
    const step: number = direction >= 0 ? 1 : -1;
    const nextLowest: number = this.lowestMidi + step * 12;
    this.setVisibleRange(nextLowest, this.whiteKeyCount);
  }

  resizeFromLeftAnchor(anchorLowest: number, anchorCount: number, deltaWhiteKeys: number): void {
    if (deltaWhiteKeys > 0) {
      const nextLowest: number = walkPianoWhiteKeys(anchorLowest, deltaWhiteKeys + 1, -1);
      this.setVisibleRange(nextLowest, anchorCount + deltaWhiteKeys);
      return;
    }
    if (deltaWhiteKeys < 0) {
      const removeCount: number = Math.min(-deltaWhiteKeys, anchorCount - PianoMinWhiteKeyCount);
      const nextLowest: number = walkPianoWhiteKeys(anchorLowest, removeCount + 1, 1);
      this.setVisibleRange(nextLowest, anchorCount - removeCount);
    }
  }

  resizeFromRightAnchor(anchorLowest: number, anchorCount: number, deltaWhiteKeys: number): void {
    this.setVisibleRange(anchorLowest, anchorCount + deltaWhiteKeys);
  }

  fitToAvailableWidth(availablePanelWidthVp: number): void {
    const innerWidth: number = availablePanelWidthVp - PianoPanelPaddingVp * 2;
    const maxCount: number = Math.floor(innerWidth / PianoWhiteKeyWidthVp);
    this.clampWhiteKeyCount(maxCount, 'right');
  }

  clampWhiteKeyCount(maxCount: number, side: PianoResizeSide): void {
    const limited: number = clampNumber(Math.floor(maxCount), PianoMinWhiteKeyCount, PianoMaxWhiteKeyCount);
    if (this.whiteKeyCount <= limited) {
      return;
    }
    if (side === 'left') {
      const removeCount: number = this.whiteKeyCount - limited;
      const nextLowest: number = walkPianoWhiteKeys(this.lowestMidi, removeCount + 1, 1);
      this.setVisibleRange(nextLowest, limited);
      return;
    }
    this.setVisibleRange(this.lowestMidi, limited);
  }

  canShiftOctave(direction: number): boolean {
    const step: number = direction >= 0 ? 1 : -1;
    const preview: number[] = this.computeClampedRange(this.lowestMidi + step * 12, this.whiteKeyCount);
    return preview[0] !== this.lowestMidi || preview[1] !== this.whiteKeyCount;
  }

  getHighestMidi(): number {
    return getPianoHighestMidi(this.lowestMidi, this.whiteKeyCount);
  }

  getVisibleWhiteKeys(): PianoWhiteKeyItem[] {
    const keys: PianoWhiteKeyItem[] = [];
    let midi: number = this.lowestMidi;
    for (let index = 0; index < this.whiteKeyCount; index++) {
      const item: PianoWhiteKeyItem = {
        midi: midi,
        label: getPianoNoteLabel(midi)
      };
      keys.push(item);
      if (index < this.whiteKeyCount - 1) {
        midi = walkPianoWhiteKeys(midi, 2, 1);
      }
    }
    return keys;
  }

  getVisibleBlackKeys(): PianoBlackKeyItem[] {
    const keys: PianoBlackKeyItem[] = [];
    let midi: number = this.lowestMidi;
    for (let whiteIndex = 0; whiteIndex < this.whiteKeyCount - 1; whiteIndex++) {
      const nextWhite: number = walkPianoWhiteKeys(midi, 2, 1);
      if (nextWhite - midi === 2) {
        const item: PianoBlackKeyItem = {
          midi: midi + 1,
          whiteIndexLeft: whiteIndex
        };
        keys.push(item);
      }
      midi = nextWhite;
    }
    return keys;
  }

  isMidiSounding(midi: number): boolean {
    return this.soundingMidiNotes.includes(midi);
  }

  noteOn(midi: number): void {
    if (!this.showWindow) {
      return;
    }
    const clampedMidi: number = clampNumber(Math.round(midi), PianoMinMidi, PianoMaxMidi);
    this.ensureVoice(clampedMidi);
    this.publishSoundingNotes();
    this.ensurePlaybackRunning();
    if (this.useNativeEngine) {
      nativePianoNoteOn(clampedMidi, this.midiToHz(clampedMidi));
    }
  }

  noteOff(midi: number): void {
    if (this.latchedMidis.includes(midi)) {
      return;
    }
    this.releaseVoice(midi);
    this.publishSoundingNotes();
    if (this.useNativeEngine) {
      nativePianoNoteOff(midi);
    }
  }

  toggleLatch(midi: number): void {
    const clampedMidi: number = clampNumber(Math.round(midi), PianoMinMidi, PianoMaxMidi);
    const latchIndex: number = this.latchedMidis.indexOf(clampedMidi);
    if (latchIndex >= 0) {
      const nextLatched: number[] = [];
      for (let index = 0; index < this.latchedMidis.length; index++) {
        if (index !== latchIndex) {
          nextLatched.push(this.latchedMidis[index]);
        }
      }
      this.latchedMidis = nextLatched;
      this.releaseVoice(clampedMidi);
      this.publishSoundingNotes();
      if (this.useNativeEngine) {
        nativePianoNoteOff(clampedMidi);
      }
      return;
    }
    this.latchedMidis.push(clampedMidi);
    this.ensureVoice(clampedMidi);
    this.publishSoundingNotes();
    this.ensurePlaybackRunning();
    if (this.useNativeEngine) {
      nativePianoNoteOn(clampedMidi, this.midiToHz(clampedMidi));
    }
  }

  allNotesOff(immediate: boolean = false): void {
    this.latchedMidis = [];
    for (let index = 0; index < this.voices.length; index++) {
      if (!this.voices[index].inUse) {
        continue;
      }
      if (immediate) {
        this.voices[index].inUse = false;
      } else {
        this.beginRelease(this.voices[index]);
      }
    }
    this.publishSoundingNotes();
    if (this.useNativeEngine) {
      nativePianoAllNotesOff(immediate);
    }
  }

  private setVisibleRange(lowestMidi: number, whiteKeyCount: number): void {
    const clamped: number[] = this.computeClampedRange(lowestMidi, whiteKeyCount);
    if (this.lowestMidi === clamped[0] && this.whiteKeyCount === clamped[1]) {
      return;
    }
    this.lowestMidi = clamped[0];
    this.whiteKeyCount = clamped[1];
    this.savePreferences();
    this.notifyVisualStateChanged();
  }

  private computeClampedRange(lowestMidi: number, whiteKeyCount: number): number[] {
    let count: number = clampNumber(Math.round(whiteKeyCount), PianoMinWhiteKeyCount, PianoMaxWhiteKeyCount);
    let lowest: number = snapMidiToWhiteKey(lowestMidi, 1);
    lowest = clampNumber(lowest, PianoMinMidi, PianoMaxMidi);
    if (!isPianoWhiteKey(lowest)) {
      lowest = snapMidiToWhiteKey(lowest, 1);
    }
    let highest: number = getPianoHighestMidi(lowest, count);
    if (highest > PianoMaxMidi) {
      highest = snapMidiToWhiteKey(PianoMaxMidi, -1);
      lowest = walkPianoWhiteKeys(highest, count, -1);
    }
    if (lowest < PianoMinMidi) {
      lowest = snapMidiToWhiteKey(PianoMinMidi, 1);
      highest = getPianoHighestMidi(lowest, count);
      if (highest > PianoMaxMidi) {
        highest = snapMidiToWhiteKey(PianoMaxMidi, -1);
        count = this.countWhiteKeysInclusive(lowest, highest);
      }
    }
    count = clampNumber(count, PianoMinWhiteKeyCount, PianoMaxWhiteKeyCount);
    return [lowest, count];
  }

  private countWhiteKeysInclusive(lowestMidi: number, highestMidi: number): number {
    let count: number = 0;
    for (let midi = lowestMidi; midi <= highestMidi; midi++) {
      if (isPianoWhiteKey(midi)) {
        count += 1;
      }
    }
    return count;
  }

  private midiToHz(midi: number): number {
    return this.referenceHz * Math.pow(2, (midi - 69) / 12);
  }

  private retuneActiveVoices(): void {
    for (let index = 0; index < this.voices.length; index++) {
      const voice: PianoVoice = this.voices[index];
      if (!voice.inUse) {
        continue;
      }
      voice.frequencyHz = this.midiToHz(voice.midi);
      voice.loudness = this.getLoudnessCompensation(voice.frequencyHz);
      this.configureFallbackPartials(voice, false);
      if (this.useNativeEngine) {
        nativePianoRetune(voice.midi, voice.frequencyHz);
      }
    }
  }

  private ensureVoice(midi: number): void {
    const existingIndex: number = this.findActiveVoiceIndex(midi);
    if (existingIndex >= 0) {
      this.resetVoice(this.voices[existingIndex], midi);
      return;
    }
    const freeIndex: number = this.findFreeVoiceIndex();
    const voiceIndex: number = freeIndex >= 0 ? freeIndex : this.stealOldestVoice();
    this.resetVoice(this.voices[voiceIndex], midi);
  }

  private resetVoice(voice: PianoVoice, midi: number): void {
    const frequencyHz: number = this.midiToHz(midi);
    voice.midi = midi;
    voice.frequencyHz = frequencyHz;
    voice.loudness = this.getLoudnessCompensation(frequencyHz);
    voice.envLevel = 0;
    voice.releaseStartEnv = 1;
    voice.state = 'attack';
    voice.framesInState = 0;
    voice.framesSinceOn = 0;
    voice.inUse = true;
    this.configureFallbackPartials(voice, true);
    if (this.soundProgram === PianoSoundProgramSquare) {
      voice.envLevel = 1;
      voice.state = 'sustain';
    }
  }

  private configureFallbackPartials(voice: PianoVoice, resetPhases: boolean): void {
    const frequencyHz: number = voice.frequencyHz;
    if (this.soundProgram === PianoSoundProgramSquare) {
      voice.partialCount = 5;
      for (let index = 0; index < voice.partialCount; index++) {
        const harmonic: number = index * 2 + 1;
        voice.partialIncrement[index] = PianoSineTableSize * frequencyHz * harmonic / PianoAudioSampleRateHz;
        voice.partialAmp[index] = 0.52 / harmonic;
        voice.partialDecay[index] = 1;
        voice.partialLevel[index] = 1;
        if (resetPhases) {
          voice.partialPhase[index] = 0;
        }
      }
      return;
    }
    if (this.soundProgram === PianoSoundProgramOrgan) {
      voice.partialCount = 2;
      voice.partialIncrement[0] = PianoSineTableSize * frequencyHz / PianoAudioSampleRateHz;
      voice.partialIncrement[1] = voice.partialIncrement[0] * 2.003;
      voice.partialAmp[0] = 0.70;
      voice.partialAmp[1] = 0.22;
      voice.partialDecay[0] = 1;
      voice.partialDecay[1] = 1;
      voice.partialLevel[0] = 1;
      voice.partialLevel[1] = 1;
      if (resetPhases) {
        voice.partialPhase[0] = 0;
        voice.partialPhase[1] = 0;
      }
      return;
    }
    const inharmonicity: number = Math.min(0.00055, Math.max(0.00004, 0.00016 * Math.pow(98 / frequencyHz, 0.42)));
    const baseTau: number = Math.min(6.5, Math.max(0.85, 3.1 * Math.pow(196 / frequencyHz, 0.42)));
    voice.partialCount = 6;
    for (let partial = 1; partial <= voice.partialCount; partial++) {
      const index: number = partial - 1;
      const stretch: number = Math.sqrt(1 + inharmonicity * partial * partial);
      voice.partialIncrement[index] = PianoSineTableSize * frequencyHz * partial * stretch / PianoAudioSampleRateHz;
      voice.partialAmp[index] = 1 / Math.pow(partial, partial <= 3 ? 1.05 : 1.62);
      const tauSeconds: number = baseTau / (1 + 0.22 * partial * partial);
      voice.partialDecay[index] = Math.exp(-1 / (tauSeconds * PianoAudioSampleRateHz));
      voice.partialLevel[index] = 1;
      if (resetPhases) {
        voice.partialPhase[index] = (partial * 137 + voice.midi * 17) % PianoSineTableSize;
      }
    }
  }

  private releaseVoice(midi: number): void {
    for (let index = 0; index < this.voices.length; index++) {
      if (this.voices[index].inUse && this.voices[index].midi === midi &&
        this.voices[index].state !== 'release') {
        this.beginRelease(this.voices[index]);
      }
    }
  }

  private beginRelease(voice: PianoVoice): void {
    if (voice.state === 'release') {
      return;
    }
    voice.releaseStartEnv = Math.max(voice.envLevel, 0.0001);
    voice.state = 'release';
    voice.framesInState = 0;
  }

  private findActiveVoiceIndex(midi: number): number {
    for (let index = 0; index < this.voices.length; index++) {
      if (this.voices[index].inUse && this.voices[index].midi === midi &&
        this.voices[index].state !== 'release') {
        return index;
      }
    }
    return -1;
  }

  private findFreeVoiceIndex(): number {
    for (let index = 0; index < this.voices.length; index++) {
      if (!this.voices[index].inUse) {
        return index;
      }
    }
    return -1;
  }

  private stealOldestVoice(): number {
    for (let index = 0; index < this.voices.length; index++) {
      if (this.voices[index].inUse && this.voices[index].state === 'release') {
        return index;
      }
    }
    return 0;
  }

  private releaseLatchedNotes(): void {
    const latched: number[] = this.latchedMidis;
    this.latchedMidis = [];
    for (let index = 0; index < latched.length; index++) {
      this.releaseVoice(latched[index]);
      if (this.useNativeEngine) {
        nativePianoNoteOff(latched[index]);
      }
    }
    this.publishSoundingNotes();
  }

  private publishSoundingNotes(): void {
    const next: number[] = [];
    for (let index = 0; index < this.voices.length; index++) {
      if (this.voices[index].inUse && this.voices[index].state !== 'release') {
        next.push(this.voices[index].midi);
      }
    }
    this.soundingMidiNotes = next;
  }

  private notifyVisualStateChanged(): void {
    this.dependencies.onVisualStateChanged?.();
  }

  private mixVoicesIntoBuffer(output: Int16Array): void {
    output.fill(0);
    if (this.countInUseVoices() <= 0) {
      return;
    }
    const outputAmplitude: number = PianoAudioMaxAmplitude * PianoOutputScale;
    const mixScale: number = 1 / Math.sqrt(Math.max(1, this.countInUseVoices()));
    for (let sampleIndex = 0; sampleIndex < output.length; sampleIndex++) {
      let mixed: number = 0;
      for (let voiceIndex = 0; voiceIndex < this.voices.length; voiceIndex++) {
        const voice: PianoVoice = this.voices[voiceIndex];
        if (!voice.inUse) {
          continue;
        }
        const envelope: number = this.advanceVoiceEnvelope(voice);
        if (envelope <= 0 && voice.state === 'release') {
          voice.inUse = false;
          continue;
        }
        mixed += this.renderVoiceSample(voice, envelope) * PianoVoiceGain * mixScale;
      }
      output[sampleIndex] = this.clampPcmSample(peakLimitSample(this.processDynamics(mixed)) * outputAmplitude);
    }
  }

  private processDynamics(sample: number): number {
    const absx: number = sample < 0 ? -sample : sample;
    const peakCoeff: number = absx > this.dynPeak ? 0.0069 : 0.00030;
    this.dynPeak += peakCoeff * (absx - this.dynPeak);
    let comp: number = 1;
    if (this.dynPeak > PianoCompThreshold) {
      const over: number = this.dynPeak / PianoCompThreshold;
      comp = Math.pow(over, (1 / PianoCompRatio) - 1);
    }
    this.dynRms2 += 0.0018 * (sample * sample - this.dynRms2);
    if (this.dynRms2 < 0) {
      this.dynRms2 = 0;
    }
    const rms: number = Math.sqrt(this.dynRms2);
    let normTarget: number = 1;
    if (rms > 0.003) {
      normTarget = Math.min(3.20, Math.max(0.70, PianoNormLoudness / rms));
    }
    this.dynNorm += (rms > 0.003 ? 0.0012 : 0.0028) * (normTarget - this.dynNorm);
    return sample * comp * this.dynNorm * 1.18;
  }

  private countInUseVoices(): number {
    let count: number = 0;
    for (let index = 0; index < this.voices.length; index++) {
      if (this.voices[index].inUse) {
        count += 1;
      }
    }
    return count;
  }

  private advanceVoiceEnvelope(voice: PianoVoice): number {
    if (voice.state === 'attack') {
      const attackFrames: number = this.soundProgram === PianoSoundProgramOrgan ? PianoAttackFrames : PianoFeltAttackFrames;
      const t: number = (voice.framesInState + 1) / attackFrames;
      if (this.soundProgram === PianoSoundProgramPiano) {
        const clamped: number = Math.min(1, Math.max(0, t));
        voice.envLevel = 0.5 * (1 - Math.cos(Math.PI * clamped));
      } else {
        voice.envLevel = Math.min(1, t);
      }
      voice.framesInState += 1;
      voice.framesSinceOn += 1;
      if (voice.framesInState >= attackFrames) {
        voice.state = 'sustain';
        voice.framesInState = 0;
        voice.envLevel = 1;
      }
      return voice.envLevel;
    }
    if (voice.state === 'sustain') {
      voice.envLevel = 1;
      voice.framesInState += 1;
      voice.framesSinceOn += 1;
      return 1;
    }
    voice.framesInState += 1;
    voice.framesSinceOn += 1;
    const releaseGain: number = 1 - voice.framesInState / PianoReleaseFrames;
    voice.envLevel = voice.releaseStartEnv * Math.max(0, releaseGain);
    return voice.envLevel;
  }

  private renderVoiceSample(voice: PianoVoice, envelope: number): number {
    let mixed: number = 0;
    let remainingEnergy: number = 0;
    const earlyDecay: boolean = this.soundProgram === PianoSoundProgramPiano && voice.framesSinceOn < 4320;
    for (let index = 0; index < voice.partialCount; index++) {
      mixed += PianoSineTable[(voice.partialPhase[index] | 0) & PianoSineTableMask] *
        voice.partialAmp[index] * voice.partialLevel[index];
      voice.partialPhase[index] += voice.partialIncrement[index];
      if (voice.partialPhase[index] >= PianoSineTableSize) {
        voice.partialPhase[index] -= PianoSineTableSize;
      }
      let decay: number = voice.partialDecay[index];
      if (earlyDecay && index >= 3 && decay < 1) {
        decay *= decay;
      }
      voice.partialLevel[index] *= decay;
      remainingEnergy += voice.partialLevel[index] * voice.partialAmp[index];
    }
    if (this.soundProgram === PianoSoundProgramPiano && remainingEnergy < 0.0008 && voice.state !== 'attack') {
      voice.inUse = false;
      return 0;
    }
    const programGain: number = this.soundProgram === PianoSoundProgramPiano ? 0.52 :
      (this.soundProgram === PianoSoundProgramSquare ? 0.58 : 0.55);
    return mixed * programGain * envelope * voice.loudness;
  }

  private getLoudnessCompensation(frequencyHz: number): number {
    if (frequencyHz <= 0) {
      return 1;
    }
    if (frequencyHz < 440) {
      return Math.min(1.28, Math.pow(440 / frequencyHz, 0.18));
    }
    return Math.max(0.88, Math.pow(440 / frequencyHz, 0.10));
  }

  private clampPcmSample(value: number): number {
    if (value > PianoAudioMaxAmplitude) {
      return PianoAudioMaxAmplitude;
    }
    if (value < -PianoAudioMaxAmplitude) {
      return -PianoAudioMaxAmplitude;
    }
    return value | 0;
  }

  private clampReferenceHz(value: number): number {
    return clampNumber(Math.round(value), PianoReferenceHzMin, PianoReferenceHzMax);
  }

  private loadPreferences(preferenceStore: preferences.Preferences): void {
    try {
      this.referenceHz = this.clampReferenceHz(preferenceStore.getSync(PianoReferenceHzPreferenceKey, 440) as number);
      this.soundProgram = clampNumber(
        Math.round(preferenceStore.getSync(PianoSoundProgramPreferenceKey, PianoSoundProgramPiano) as number),
        PianoSoundProgramPiano,
        PianoSoundProgramSquare
      );
      this.autoHoldEnabled = (preferenceStore.getSync(PianoAutoHoldPreferenceKey, false) as boolean) === true;
      const savedLowest: number = preferenceStore.getSync(PianoLowestMidiPreferenceKey, PianoDefaultLowestMidi) as number;
      const savedCount: number =
        preferenceStore.getSync(PianoWhiteKeyCountPreferenceKey, PianoDefaultWhiteKeyCount) as number;
      const clamped: number[] = this.computeClampedRange(savedLowest, savedCount);
      this.lowestMidi = clamped[0];
      this.whiteKeyCount = clamped[1];
    } catch (error) {
      hilog.error(0, 'PDFPianoController', `加载钢琴偏好出错: ${error}.`);
    }
  }

  private savePreferences(): void {
    if (!this.preferenceStore) {
      return;
    }
    try {
      this.preferenceStore.putSync(PianoReferenceHzPreferenceKey, this.referenceHz);
      this.preferenceStore.putSync(PianoSoundProgramPreferenceKey, this.soundProgram);
      this.preferenceStore.putSync(PianoAutoHoldPreferenceKey, this.autoHoldEnabled);
      this.preferenceStore.putSync(PianoLowestMidiPreferenceKey, this.lowestMidi);
      this.preferenceStore.putSync(PianoWhiteKeyCountPreferenceKey, this.whiteKeyCount);
      this.preferenceStore.flushSync();
    } catch (error) {
      hilog.error(0, 'PDFPianoController', `保存钢琴偏好出错: ${error}.`);
    }
  }

  private ensurePlaybackRunning(): void {
    this.playbackStartRequested = true;
    this.startAudioRendererPlayback(this.audioPlaybackSessionToken === 0
      ? ++this.audioPlaybackSessionToken
      : this.audioPlaybackSessionToken);
  }

  private initializeAudio(): void {
    if (this.useNativeEngine || this.audioRendererLoading || this.audioRenderer) {
      return;
    }
    if (prepareNativePiano()) {
      this.useNativeEngine = true;
      this.audioReady = true;
      nativePianoSetProgram(this.soundProgram);
      hilog.info(0, 'PDFPianoController', '键盘使用 OHAudio C API 建模引擎');
      return;
    }
    this.audioRendererLoading = true;
    const requestToken: number = ++this.audioRequestToken;
    this.createAudioRenderer(requestToken).finally(() => {
      if (this.audioRequestToken === requestToken) {
        this.audioRendererLoading = false;
      }
    });
  }

  private async createAudioRenderer(requestToken: number): Promise<void> {
    this.audioReady = false;
    try {
      const audioRendererOptions: audio.AudioRendererOptions = {
        streamInfo: {
          samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_48000,
          channels: audio.AudioChannel.CHANNEL_1,
          sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
          encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
        },
        rendererInfo: {
          usage: audio.StreamUsage.STREAM_USAGE_GAME,
          rendererFlags: 0
        }
      };
      const audioRenderer: audio.AudioRenderer = await audio.createAudioRenderer(audioRendererOptions);
      try {
        await audioRenderer.setAudioEffectMode(audio.AudioEffectMode.EFFECT_NONE);
      } catch (effectError) {
        hilog.warn(0, 'PDFPianoController', `关闭钢琴音效失败: ${JSON.stringify(effectError)}`);
      }
      audioRenderer.on('writeData', this.handleAudioWriteData);
      if (requestToken !== this.audioRequestToken) {
        this.releaseDetachedAudioRenderer(audioRenderer);
        return;
      }
      this.audioRenderer = audioRenderer;
      this.audioReady = true;
      if (this.playbackStartRequested) {
        this.startAudioRendererPlayback(this.audioPlaybackSessionToken);
      }
    } catch (error) {
      hilog.error(0, 'PDFPianoController', `初始化钢琴AudioRenderer失败: ${JSON.stringify(error)}`);
      if (requestToken === this.audioRequestToken) {
        this.audioRenderer = undefined;
        this.audioReady = false;
        this.showAudioFailureAlert();
      }
    }
  }

  private showAudioFailureAlert(): void {
    if (this.audioFailureAlertShown) {
      return;
    }
    this.audioFailureAlertShown = true;
    try {
      const uiContext: UIContext = this.dependencies.getUIContext();
      void showAlertDialog('键盘无法发声', '无法创建音频输出，请稍后重试。', uiContext);
    } catch (error) {
      hilog.error(0, 'PDFPianoController', `显示钢琴音频错误对话框失败: ${JSON.stringify(error)}`);
    }
  }

  private releaseAudio(): void {
    this.audioRequestToken += 1;
    this.audioRendererLoading = false;
    if (this.useNativeEngine) {
      releaseNativePiano();
      this.useNativeEngine = false;
      this.audioReady = false;
      return;
    }
    const audioRenderer: audio.AudioRenderer | undefined = this.audioRenderer;
    this.audioRenderer = undefined;
    this.audioReady = false;
    if (!audioRenderer) {
      return;
    }
    this.releaseDetachedAudioRenderer(audioRenderer);
  }

  private releaseDetachedAudioRenderer(audioRenderer: audio.AudioRenderer): void {
    try {
      audioRenderer.off('writeData', this.handleAudioWriteData);
    } catch (error) {
      hilog.error(0, 'PDFPianoController', `解绑钢琴AudioRenderer回调失败: ${JSON.stringify(error)}`);
    }
    const releaseRenderer = async (): Promise<void> => {
      try {
        if (audioRenderer.state === audio.AudioState.STATE_RUNNING ||
          audioRenderer.state === audio.AudioState.STATE_PAUSED) {
          await audioRenderer.stop();
        }
      } catch (error) {
        hilog.error(0, 'PDFPianoController', `停止钢琴AudioRenderer失败: ${JSON.stringify(error)}`);
      }
      try {
        if (audioRenderer.state === audio.AudioState.STATE_STOPPED) {
          await audioRenderer.flush();
        }
      } catch (error) {
        hilog.error(0, 'PDFPianoController', `清空钢琴音频缓冲失败: ${JSON.stringify(error)}`);
      }
      try {
        if (audioRenderer.state !== audio.AudioState.STATE_RELEASED) {
          await audioRenderer.release();
        }
      } catch (error) {
        hilog.error(0, 'PDFPianoController', `释放钢琴AudioRenderer失败: ${JSON.stringify(error)}`);
      }
    };
    void releaseRenderer();
  }

  private stopAudioRendererPlayback(_reason: string): void {
    if (this.useNativeEngine) {
      stopNativePiano();
      return;
    }
    if (!this.audioRenderer) {
      return;
    }
    const audioRenderer: audio.AudioRenderer = this.audioRenderer;
    const stopPromise: Promise<void> = (async (): Promise<void> => {
      try {
        if (audioRenderer.state === audio.AudioState.STATE_RUNNING ||
          audioRenderer.state === audio.AudioState.STATE_PAUSED) {
          await audioRenderer.stop();
        }
      } catch (error) {
        hilog.error(0, 'PDFPianoController', `停止钢琴播放失败: ${JSON.stringify(error)}`);
      }
      try {
        if (audioRenderer.state === audio.AudioState.STATE_STOPPED) {
          await audioRenderer.flush();
        }
      } catch (error) {
        hilog.error(0, 'PDFPianoController', `清空钢琴播放缓冲失败: ${JSON.stringify(error)}`);
      }
    })();
    this.pendingRendererStop = stopPromise;
    void stopPromise.finally(() => {
      if (this.pendingRendererStop === stopPromise) {
        this.pendingRendererStop = undefined;
      }
    });
  }

  private startAudioRendererPlayback(playbackToken: number): void {
    if (playbackToken !== this.audioPlaybackSessionToken || !this.playbackStartRequested) {
      return;
    }
    if (this.useNativeEngine) {
      if (!startNativePiano()) {
        hilog.warn(0, 'PDFPianoController', '原生键盘引擎启动失败，回退 ArkTS AudioRenderer');
        this.useNativeEngine = false;
        this.audioReady = false;
        releaseNativePiano();
        this.initializeAudio();
        return;
      }
      this.audioReady = true;
      return;
    }
    if (!this.audioRenderer) {
      this.initializeAudio();
      return;
    }
    const audioRenderer: audio.AudioRenderer = this.audioRenderer;
    const startRenderer = async (): Promise<void> => {
      try {
        const pendingStop: Promise<void> | undefined = this.pendingRendererStop;
        if (pendingStop) {
          await pendingStop;
        }
        if (playbackToken !== this.audioPlaybackSessionToken || !this.playbackStartRequested) {
          return;
        }
        if (audioRenderer.state === audio.AudioState.STATE_RUNNING) {
          return;
        }
        if (audioRenderer.state === audio.AudioState.STATE_STOPPED) {
          await audioRenderer.flush();
        }
        await audioRenderer.start();
        try {
          const bufferBytes: number = audioRenderer.getBufferSizeSync();
          hilog.info(0, 'PDFPianoController', `键盘低时延通路缓冲 ${bufferBytes} bytes`);
        } catch (_bufferError) {
        }
      } catch (error) {
        if (playbackToken === this.audioPlaybackSessionToken) {
          hilog.error(0, 'PDFPianoController', `启动钢琴播放失败: ${JSON.stringify(error)}`);
        }
      }
    };
    void startRenderer();
  }
}
