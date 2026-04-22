import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TunerReferenceHzPreferenceKey: string = 'tunerReferenceHz';
const TunerTransposeIndexPreferenceKey: string = 'tunerTransposeIndex';
const TunerNoteDisplayModePreferenceKey: string = 'tunerNoteDisplayMode';
const TunerNoteNamingModePreferenceKey: string = 'tunerNoteNamingMode';
const TunerMicrophoneGainPreferenceKey: string = 'tunerMicrophoneGain';
const TunerReferenceToneEnabledPreferenceKey: string = 'tunerReferenceToneEnabled';
const TunerReferenceNoteMidiPreferenceKey: string = 'tunerReferenceNoteMidi';

export type TunerNoteDisplayMode = 'standard' | 'sharp' | 'flat';
export type TunerNoteNamingMode = 'pitch' | 'solfege';

const TunerValidDisplayModes: TunerNoteDisplayMode[] = ['standard', 'sharp', 'flat'];
const TunerValidNamingModes: TunerNoteNamingMode[] = ['pitch', 'solfege'];

@ObservedV2
export class PDFTunerController {
  private preferenceStore?: preferences.Preferences;

  @Trace public referenceHz: number = 440;
  @Trace public transposeIndex: number = 0;
  @Trace public noteDisplayMode: TunerNoteDisplayMode = 'standard';
  @Trace public noteNamingMode: TunerNoteNamingMode = 'pitch';
  @Trace public microphoneGain: number = 0.65;
  @Trace public referenceToneEnabled: boolean = false;
  @Trace public referenceNoteMidi: number = 69;

  initialize(preferenceStore: preferences.Preferences): void {
    this.preferenceStore = preferenceStore;
    this.loadPreferences(preferenceStore);
  }

  cleanup(): void {
    this.preferenceStore = undefined;
  }

  setReferenceHz(value: number): void {
    const nextValue = this.clampReferenceHz(value);
    if (this.referenceHz === nextValue) {
      return;
    }
    this.referenceHz = nextValue;
    this.savePreferences();
  }

  setTransposeIndex(value: number): void {
    const nextValue = this.clampTransposeIndex(value);
    if (this.transposeIndex === nextValue) {
      return;
    }
    this.transposeIndex = nextValue;
    this.savePreferences();
  }

  setNoteDisplayMode(value: TunerNoteDisplayMode): void {
    if (this.noteDisplayMode === value) {
      return;
    }
    this.noteDisplayMode = value;
    this.savePreferences();
  }

  setNoteNamingMode(value: TunerNoteNamingMode): void {
    if (this.noteNamingMode === value) {
      return;
    }
    this.noteNamingMode = value;
    this.savePreferences();
  }

  setMicrophoneGain(value: number): void {
    const nextValue = this.clampMicrophoneGain(value);
    if (this.microphoneGain === nextValue) {
      return;
    }
    this.microphoneGain = nextValue;
    this.savePreferences();
  }

  setReferenceToneEnabled(value: boolean): void {
    if (this.referenceToneEnabled === value) {
      return;
    }
    this.referenceToneEnabled = value;
    this.savePreferences();
  }

  setReferenceNoteMidi(value: number): void {
    const nextValue = this.clampReferenceNoteMidi(value);
    if (this.referenceNoteMidi === nextValue) {
      return;
    }
    this.referenceNoteMidi = nextValue;
    this.savePreferences();
  }

  private loadPreferences(preferenceStore: preferences.Preferences): void {
    try {
      this.referenceHz = this.clampReferenceHz(preferenceStore.getSync(TunerReferenceHzPreferenceKey, 440) as number);
      this.transposeIndex = this.clampTransposeIndex(
        preferenceStore.getSync(TunerTransposeIndexPreferenceKey, 0) as number,
      );
      const savedDisplay = preferenceStore.getSync(TunerNoteDisplayModePreferenceKey, 'standard') as string;
      this.noteDisplayMode = TunerValidDisplayModes.includes(savedDisplay as TunerNoteDisplayMode)
        ? (savedDisplay as TunerNoteDisplayMode)
        : 'standard';
      const savedNaming = preferenceStore.getSync(TunerNoteNamingModePreferenceKey, 'pitch') as string;
      this.noteNamingMode = TunerValidNamingModes.includes(savedNaming as TunerNoteNamingMode)
        ? (savedNaming as TunerNoteNamingMode)
        : 'pitch';
      this.microphoneGain = this.clampMicrophoneGain(
        preferenceStore.getSync(TunerMicrophoneGainPreferenceKey, 0.65) as number,
      );
      this.referenceToneEnabled = !!preferenceStore.getSync(TunerReferenceToneEnabledPreferenceKey, false);
      this.referenceNoteMidi = this.clampReferenceNoteMidi(
        preferenceStore.getSync(TunerReferenceNoteMidiPreferenceKey, 69) as number,
      );
    } catch (error) {
      hilog.error(0, 'PDFTunerController', `加载调音器偏好出错: ${error}.`);
    }
  }

  private savePreferences(): void {
    if (!this.preferenceStore) {
      return;
    }
    try {
      this.preferenceStore.putSync(TunerReferenceHzPreferenceKey, this.referenceHz);
      this.preferenceStore.putSync(TunerTransposeIndexPreferenceKey, this.transposeIndex);
      this.preferenceStore.putSync(TunerNoteDisplayModePreferenceKey, this.noteDisplayMode);
      this.preferenceStore.putSync(TunerNoteNamingModePreferenceKey, this.noteNamingMode);
      this.preferenceStore.putSync(TunerMicrophoneGainPreferenceKey, this.microphoneGain);
      this.preferenceStore.putSync(TunerReferenceToneEnabledPreferenceKey, this.referenceToneEnabled);
      this.preferenceStore.putSync(TunerReferenceNoteMidiPreferenceKey, this.referenceNoteMidi);
      this.preferenceStore.flushSync();
    } catch (error) {
      hilog.error(0, 'PDFTunerController', `保存调音器偏好出错: ${error}.`);
    }
  }

  private clampReferenceHz(value: number): number {
    return Math.max(430, Math.min(450, Math.round(value)));
  }

  private clampTransposeIndex(value: number): number {
    return Math.max(0, Math.min(11, Math.round(value)));
  }

  private clampMicrophoneGain(value: number): number {
    return Math.max(0, Math.min(1, value));
  }

  private clampReferenceNoteMidi(value: number): number {
    return Math.max(24, Math.min(84, Math.round(value)));
  }
}
