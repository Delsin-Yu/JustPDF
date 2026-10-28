import { preferences } from '@kit.ArkData';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { audio } from '@kit.AudioKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { nativePianoSetTunerTone, prepareNativePiano } from './PDFPianoNative';
import {
  nativeTunerClearResultCallback,
  nativeTunerSetConfig,
  nativeTunerSetResultCallback,
  nativeTunerStartMic,
  nativeTunerStopMic,
  TunerNativeAnalysisResult,
} from './PDFTunerNative';

const TunerReferenceHzPreferenceKey: string = 'tunerReferenceHz';
/** 参考音「A4」频率可调范围（Hz），与界面 ScrollSpinBox 一致。 */
export const TunerReferenceHzMin: number = 200;
export const TunerReferenceHzMax: number = 600;
const TunerTransposeIndexPreferenceKey: string = 'tunerTransposeIndex';
const TunerNoteDisplayModePreferenceKey: string = 'tunerNoteDisplayMode';
const TunerNoteNamingModePreferenceKey: string = 'tunerNoteNamingMode';
const TunerFilterPresetPreferenceKey: string = 'tunerFilterPreset';
const TunerAutoGainEnabledPreferenceKey: string = 'tunerAutoGainEnabled';
const TunerSpectrumGainPreferenceKey: string = 'tunerSpectrumGain';
const TunerReferenceToneEnabledPreferenceKey: string = 'tunerReferenceToneEnabled';
const TunerReferenceNoteMidiPreferenceKey: string = 'tunerReferenceNoteMidi';
const TunerReferenceToneSampleRateHz: number = 48000;
const TunerReferenceToneMaxAmplitude: number = 32767;
const TunerReferenceToneAmplitudeRatio: number = 0.16;
const TunerReferenceToneMinHz: number = 20;
const TunerReferenceToneMaxHz: number = 10000;
const TunerReferenceToneFadeFactor: number = 0.0024;
/** 等响感知锚点：低于该频率时略提升幅度，减轻低音「发虚」感。 */
const TunerReferenceToneLoudnessAnchorHz: number = 440;
/** 低音补偿强度：(锚点/频率)^指数，约 0.25～0.35 接近温和等响曲线。 */
const TunerReferenceToneLoudnessCompExponent: number = 0.32;
/** 相对锚点的最大提升倍数，避免极低频与换能器共振时削波过多。 */
const TunerReferenceToneLoudnessCompMaxRatio: number = 2.85;
/** 高于锚点时的略衰：(锚点/频率)^指数，减轻高音毛刺、刺耳感。 */
const TunerReferenceToneHighAttenExponent: number = 0.17;
/** 高音端增益下限，避免极高频时过细听不清。 */
const TunerReferenceToneHighGainMin: number = 0.78;
const TunerMicSpectrumBandCount: number = 20;
const TunerMicPermission: Permissions = 'ohos.permission.MICROPHONE';
const TunerMicSpectrumFreqMinHz: number = 90;
const TunerMicSpectrumFreqMaxHz: number = 6000;
/** 每次分析结果后，未刷新到新峰值时柱值线性回落的步长（0～∞量纲，与 instant 一致）。 */
const TunerMicSpectrumPeakFallPerUpdate: number = 0.032;
/** 频谱电平压缩参数：使用 log(1 + gamma*x) 压缩动态范围，避免低频过快顶满。 */
const TunerMicSpectrumCompressionGamma: number = 12;
/** 包络地板：限制极低噪声时的归一化放大倍率。 */
const TunerMicEnvelopeFloorMin: number = 0.0012;
const TunerSpectrumGainMin: number = 0.25;
const TunerSpectrumGainMax: number = 4;
const TunerSpectrumAutoGainTargetEnvelope: number = 0.045;
const TunerSpectrumAutoGainMinInputEnvelope: number = 0.003;
const TunerSpectrumAutoGainAttack: number = 0.26;
const TunerSpectrumAutoGainRelease: number = 0.08;
const TunerPitchRmsGateThreshold: number = 0.008;
/** 平滑后基频对原始值的追踪速度。 */
const TunerPitchSmoothingFactor: number = 0.32;
/** 连续多少帧无有效检测后清空显示。 */
const TunerPitchSilenceDecayFrames: number = 12;
/** 显示用 cents 对原始值的 lerp 速度：越小越平稳（0-1）。 */
const TunerDisplayCentsLerpFactor: number = 0.18;
/** 同一音名须连续保持多少帧才切换显示，防止半音边界抖动。 */
const TunerDisplayNoteHoldFrames: number = 3;
/** 紧凑音名，键与 Panel 侧 TunerNoteSemitoneMap 一致。 */
const TunerPitchNoteNames: string[] = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'G#', 'A', 'Bb', 'B'];
/** 频谱柱变化小于该值时不写 @Trace，减少无效刷新。 */
const TunerSpectrumBarPublishEpsilon: number = 0.02;
const TunerAnalysisWindowDefault: number = 4096;
const TunerAnalysisWindowLow: number = 8192;
/** 约 8 秒历史（分析 hop ≈ 21ms）。 */
export const TunerTuneGraphCapacity: number = 384;

export type TunerNoteDisplayMode = 'standard' | 'sharp' | 'flat';
export type TunerNoteNamingMode = 'pitch' | 'solfege';
export type TunerFilterPresetId = 'chromatic' | 'contrabass' | 'bass' | 'tenor' | 'alto' | 'soprano';

const TunerValidDisplayModes: TunerNoteDisplayMode[] = ['standard', 'sharp', 'flat'];
const TunerValidNamingModes: TunerNoteNamingMode[] = ['pitch', 'solfege'];
const TunerValidFilterPresetIds: TunerFilterPresetId[] = [
  'chromatic',
  'contrabass',
  'bass',
  'tenor',
  'alto',
  'soprano',
];

export interface TunerFilterPresetOption {
  id: TunerFilterPresetId;
  label: string;
}

export const TunerFilterPresetOptions: TunerFilterPresetOption[] = [
  { id: 'chromatic', label: '全频' },
  { id: 'contrabass', label: '倍低音' },
  { id: 'bass', label: '低音' },
  { id: 'tenor', label: '次中音' },
  { id: 'alto', label: '中音' },
  { id: 'soprano', label: '高音' },
];

interface TunerFilterPresetDefinition {
  id: TunerFilterPresetId;
  label: string;
  pitchMinHz: number;
  pitchMaxHz: number;
  highPassHz: number;
  lowPassHz: number;
  rmsGateThreshold: number;
}

interface TunerFilterPresetDefinitionMap {
  chromatic: TunerFilterPresetDefinition;
  contrabass: TunerFilterPresetDefinition;
  bass: TunerFilterPresetDefinition;
  tenor: TunerFilterPresetDefinition;
  alto: TunerFilterPresetDefinition;
  soprano: TunerFilterPresetDefinition;
}

const TunerFilterPresetDefinitions: TunerFilterPresetDefinitionMap = {
  chromatic: {
    id: 'chromatic',
    label: '全频',
    pitchMinHz: 27.5,
    pitchMaxHz: 1760,
    highPassHz: 22,
    lowPassHz: 5200,
    rmsGateThreshold: TunerPitchRmsGateThreshold,
  },
  contrabass: {
    id: 'contrabass',
    label: '倍低音',
    pitchMinHz: 27.5,
    pitchMaxHz: 110,
    highPassHz: 18,
    lowPassHz: 170,
    rmsGateThreshold: 0.0045,
  },
  bass: {
    id: 'bass',
    label: '低音',
    pitchMinHz: 55,
    pitchMaxHz: 220,
    highPassHz: 40,
    lowPassHz: 320,
    rmsGateThreshold: 0.0055,
  },
  tenor: {
    id: 'tenor',
    label: '次中音',
    pitchMinHz: 95,
    pitchMaxHz: 520,
    highPassHz: 75,
    lowPassHz: 700,
    rmsGateThreshold: 0.006,
  },
  alto: {
    id: 'alto',
    label: '中音',
    pitchMinHz: 170,
    pitchMaxHz: 1000,
    highPassHz: 140,
    lowPassHz: 1300,
    rmsGateThreshold: 0.0065,
  },
  soprano: {
    id: 'soprano',
    label: '高音',
    pitchMinHz: 240,
    pitchMaxHz: 1760,
    highPassHz: 220,
    lowPassHz: 2400,
    rmsGateThreshold: 0.007,
  },
};

@ObservedV2
export class PDFTunerController {
  private preferenceStore?: preferences.Preferences;
  private audioRenderer: audio.AudioRenderer | undefined = undefined;
  private audioRendererLoading: boolean = false;
  private micCapturerLoading: boolean = false;
  private readonly smoothedMicSpectrum: number[] = [];
  private micPeakEnvelope: number = 0.0001;
  private lastMicrophoneAbilityContext: common.UIAbilityContext | undefined = undefined;
  private pendingRendererStop: Promise<void> | undefined = undefined;
  private audioRequestToken: number = 0;
  private audioPlaybackSessionToken: number = 0;
  private playbackStartRequested: boolean = false;
  private panelVisible: boolean = false;
  private oscillatorPhase: number = 0;
  private oscillatorFrequencyHz: number = 440;
  private oscillatorTargetFrequencyHz: number = 440;
  private oscillatorAmplitude: number = 0;
  private oscillatorTargetAmplitude: number = 0;
  private useNativeTone: boolean = false;
  private nativeMicActive: boolean = false;
  private smoothedPitchHz: number = 0;
  private pitchSilenceFrameCount: number = 0;
  private displayCentsSmoothed: number = 0;
  private pendingNoteName: string = '--';
  private pendingNoteHoldCount: number = 0;
  private readonly tuneGraphCents: number[] = [];
  private tuneGraphCount: number = 0;
  private tuneGraphWrite: number = 0;
  private readonly tuneGraphRedrawListeners: Array<() => void> = [];

  @Trace public referenceHz: number = 440;
  @Trace public transposeIndex: number = 0;
  @Trace public noteDisplayMode: TunerNoteDisplayMode = 'standard';
  @Trace public noteNamingMode: TunerNoteNamingMode = 'pitch';
  @Trace public filterPresetId: TunerFilterPresetId = 'chromatic';
  @Trace public autoGainEnabled: boolean = true;
  @Trace public spectrumGain: number = 1;
  @Trace public filterCurveLevels: number[] = [
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  ];
  @Trace public spectrumBarLevels: number[] = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ];
  @Trace public referenceToneEnabled: boolean = false;
  @Trace public referenceNoteMidi: number = 69;
  /** 用户曾拒绝麦克风授权后，不再自动弹窗，直至用户点击「重新请求」或系统设置中已授予。 */
  @Trace public microphonePermissionDenied: boolean = false;
  @Trace public detectedNote: string = '--';
  @Trace public detuneCents: number = 0;
  @Trace public tuneGraphEpoch: number = 0;

  initialize(preferenceStore: preferences.Preferences): void {
    this.preferenceStore = preferenceStore;
    this.loadPreferences(preferenceStore);
    this.initializeSmoothedMicSpectrum();
    this.initializeTuneGraph();
    this.updateFilterCurveLevels();
    nativeTunerSetResultCallback(this.handleNativeAnalysisResult);
    this.pushNativeAnalysisConfig();
    this.initializeAudio();
    this.syncReferenceTonePlaybackState();
  }

  cleanup(): void {
    this.stopMicrophoneMonitoring();
    nativeTunerClearResultCallback();
    this.stopReferenceTonePlayback();
    this.releaseAudio();
    this.preferenceStore = undefined;
  }

  async startMicrophoneMonitoring(
    context: common.UIAbilityContext,
    permissionUserInitiated: boolean = false,
  ): Promise<void> {
    this.lastMicrophoneAbilityContext = context;
    if (!this.panelVisible || this.referenceToneEnabled) {
      return;
    }
    if (this.nativeMicActive || this.micCapturerLoading) {
      return;
    }

    const allowPermissionDialog: boolean = permissionUserInitiated || !this.microphonePermissionDenied;

    this.micCapturerLoading = true;
    try {
      const granted: boolean = await this.ensureMicrophonePermission(context, allowPermissionDialog);
      if (!granted) {
        if (allowPermissionDialog) {
          this.microphonePermissionDenied = true;
          this.resetSpectrumLevels();
        }
        return;
      }
      this.microphonePermissionDenied = false;
      if (!this.panelVisible || this.referenceToneEnabled) {
        return;
      }
      this.pushNativeAnalysisConfig();
      const started: boolean = nativeTunerStartMic();
      if (!started) {
        hilog.error(0, 'PDFTunerController', '启动原生调音器采集失败');
        this.resetSpectrumLevels();
        return;
      }
      this.nativeMicActive = true;
    } catch (error) {
      hilog.error(0, 'PDFTunerController', `启动麦克风采集失败: ${JSON.stringify(error)}`);
      this.resetSpectrumLevels();
    } finally {
      this.micCapturerLoading = false;
    }
  }

  stopMicrophoneMonitoring(): void {
    this.nativeMicActive = false;
    nativeTunerStopMic();
    this.resetSpectrumLevels();
  }

  setReferenceHz(value: number): void {
    const nextValue = this.clampReferenceHz(value);
    if (this.referenceHz === nextValue) {
      return;
    }
    this.referenceHz = nextValue;
    this.updateReferenceToneSynthesisTargets();
    this.savePreferences();
  }

  setTransposeIndex(value: number): void {
    const nextValue = this.clampTransposeIndex(value);
    if (this.transposeIndex === nextValue) {
      return;
    }
    this.transposeIndex = nextValue;
    this.updateReferenceToneSynthesisTargets();
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

  setFilterPresetId(value: TunerFilterPresetId): void {
    if (this.filterPresetId === value) {
      return;
    }
    this.filterPresetId = value;
    this.updateFilterCurveLevels();
    this.pushNativeAnalysisConfig();
    this.savePreferences();
  }

  setAutoGainEnabled(value: boolean): void {
    if (this.autoGainEnabled === value) {
      return;
    }
    this.autoGainEnabled = value;
    this.savePreferences();
  }

  setSpectrumGain(value: number): void {
    const nextValue: number = this.clampSpectrumGain(value);
    if (this.spectrumGain === nextValue) {
      return;
    }
    this.spectrumGain = nextValue;
    this.savePreferences();
  }

  setReferenceToneEnabled(value: boolean): void {
    if (this.referenceToneEnabled === value) {
      return;
    }
    this.referenceToneEnabled = value;
    if (value) {
      this.stopMicrophoneMonitoring();
    } else if (this.panelVisible && this.lastMicrophoneAbilityContext) {
      void this.startMicrophoneMonitoring(this.lastMicrophoneAbilityContext, false);
    }
    this.syncReferenceTonePlaybackState();
    this.savePreferences();
  }

  setPanelVisible(value: boolean): void {
    if (this.panelVisible === value) {
      return;
    }
    this.panelVisible = value;
    if (!value) {
      this.stopMicrophoneMonitoring();
    }
    this.syncReferenceTonePlaybackState();
  }

  addTuneGraphRedrawListener(listener: () => void): void {
    if (this.tuneGraphRedrawListeners.indexOf(listener) >= 0) {
      return;
    }
    this.tuneGraphRedrawListeners.push(listener);
  }

  removeTuneGraphRedrawListener(listener: () => void): void {
    const index: number = this.tuneGraphRedrawListeners.indexOf(listener);
    if (index < 0) {
      return;
    }
    this.tuneGraphRedrawListeners.splice(index, 1);
  }

  copyTuneGraphCents(out: number[]): number {
    this.initializeTuneGraph();
    while (out.length < TunerTuneGraphCapacity) {
      out.push(Number.NaN);
    }
    const count: number = this.tuneGraphCount;
    const startPad: number = TunerTuneGraphCapacity - count;
    for (let index = 0; index < startPad; index++) {
      out[index] = Number.NaN;
    }
    const oldest: number = (this.tuneGraphWrite - count + TunerTuneGraphCapacity) % TunerTuneGraphCapacity;
    for (let index = 0; index < count; index++) {
      out[startPad + index] = this.tuneGraphCents[(oldest + index) % TunerTuneGraphCapacity];
    }
    return TunerTuneGraphCapacity;
  }

  setReferenceNoteMidi(value: number): void {
    const nextValue = this.clampReferenceNoteMidi(value);
    if (this.referenceNoteMidi === nextValue) {
      return;
    }
    this.referenceNoteMidi = nextValue;
    this.updateReferenceToneSynthesisTargets();
    this.savePreferences();
  }

  private getSquareWaveSample(phase: number): number {
    return phase < Math.PI ? 1 : -1;
  }

  /**
   * 等响与听感折中：低于锚点略提、高于锚点略压，均用当前平滑后的频率，避免改调时突变。
   */
  private getReferenceTonePitchLoudnessCompensation(frequencyHz: number): number {
    const anchor: number = TunerReferenceToneLoudnessAnchorHz;
    if (frequencyHz < anchor) {
      const safeHz: number = Math.max(TunerReferenceToneMinHz, frequencyHz);
      const ratio: number = anchor / safeHz;
      const boosted: number = Math.pow(ratio, TunerReferenceToneLoudnessCompExponent);
      return Math.min(TunerReferenceToneLoudnessCompMaxRatio, boosted);
    }
    if (frequencyHz <= anchor) {
      return 1;
    }
    const atten: number = Math.pow(anchor / frequencyHz, TunerReferenceToneHighAttenExponent);
    return Math.max(TunerReferenceToneHighGainMin, atten);
  }

  private readonly handleNativeAnalysisResult = (result: TunerNativeAnalysisResult): void => {
    if (!this.nativeMicActive) {
      return;
    }
    this.applyNativeSpectrum(result);
    this.updateDetectedPitch(result.pitchHz);
  };

  private readonly handleAudioWriteData: audio.AudioRendererWriteDataCallback = (buffer: ArrayBuffer):
    audio.AudioDataCallbackResult => {
    const output: Int16Array = new Int16Array(buffer);
    const shouldPlayTone: boolean = this.referenceToneEnabled && this.playbackStartRequested;

    this.oscillatorTargetAmplitude = shouldPlayTone ? TunerReferenceToneAmplitudeRatio : 0;
    this.oscillatorTargetFrequencyHz = this.getReferenceToneFrequencyHz();

    for (let sampleIndex = 0; sampleIndex < output.length; sampleIndex++) {
      this.oscillatorAmplitude += (this.oscillatorTargetAmplitude - this.oscillatorAmplitude) * TunerReferenceToneFadeFactor;
      this.oscillatorFrequencyHz += (this.oscillatorTargetFrequencyHz - this.oscillatorFrequencyHz)
        * TunerReferenceToneFadeFactor;
      this.oscillatorFrequencyHz = Math.max(
        TunerReferenceToneMinHz,
        Math.min(TunerReferenceToneMaxHz, this.oscillatorFrequencyHz),
      );
      this.oscillatorPhase += 2 * Math.PI * this.oscillatorFrequencyHz / TunerReferenceToneSampleRateHz;
      if (this.oscillatorPhase >= 2 * Math.PI) {
        this.oscillatorPhase -= 2 * Math.PI;
      }
      const loudnessComp: number = this.getReferenceTonePitchLoudnessCompensation(this.oscillatorFrequencyHz);
      const sample: number = this.getSquareWaveSample(this.oscillatorPhase) * this.oscillatorAmplitude * loudnessComp;
      output[sampleIndex] = this.clampPcmSample(Math.round(sample * TunerReferenceToneMaxAmplitude));
    }

    return audio.AudioDataCallbackResult.VALID;
  };

  private startReferenceTonePlayback(): void {
    this.playbackStartRequested = true;
    if (this.useNativeTone) {
      this.updateReferenceToneSynthesisTargets();
      return;
    }
    this.updateReferenceToneSynthesisTargets();
    this.startAudioRendererPlayback(++this.audioPlaybackSessionToken);
  }

  private stopReferenceTonePlayback(): void {
    this.playbackStartRequested = false;
    this.audioPlaybackSessionToken += 1;
    this.updateReferenceToneSynthesisTargets();
    if (this.useNativeTone) {
      return;
    }
    const stopPromise: Promise<void> = this.stopAudioRendererPlayback();
    this.pendingRendererStop = stopPromise;
    void stopPromise.finally(() => {
      if (this.pendingRendererStop === stopPromise) {
        this.pendingRendererStop = undefined;
      }
      this.oscillatorAmplitude = 0;
    });
  }

  private updateReferenceToneSynthesisTargets(): void {
    this.oscillatorTargetFrequencyHz = this.getReferenceToneFrequencyHz();
    this.oscillatorTargetAmplitude = (this.referenceToneEnabled && this.playbackStartRequested)
      ? TunerReferenceToneAmplitudeRatio
      : 0;
    if (this.useNativeTone) {
      nativePianoSetTunerTone(this.oscillatorTargetFrequencyHz, this.oscillatorTargetAmplitude);
    }
  }

  private getReferenceToneFrequencyHz(): number {
    const transposedMidi: number = this.referenceNoteMidi + this.transposeIndex;
    const semitoneOffsetFromA4: number = transposedMidi - 69;
    const computedFrequencyHz: number = this.referenceHz * Math.pow(2, semitoneOffsetFromA4 / 12);
    return Math.max(TunerReferenceToneMinHz, Math.min(TunerReferenceToneMaxHz, computedFrequencyHz));
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
      const savedFilterPresetId = preferenceStore.getSync(TunerFilterPresetPreferenceKey, 'chromatic') as string;
      this.filterPresetId = TunerValidFilterPresetIds.includes(savedFilterPresetId as TunerFilterPresetId)
        ? (savedFilterPresetId as TunerFilterPresetId)
        : 'chromatic';
      this.autoGainEnabled = !!preferenceStore.getSync(TunerAutoGainEnabledPreferenceKey, true);
      this.spectrumGain = this.clampSpectrumGain(
        preferenceStore.getSync(TunerSpectrumGainPreferenceKey, 1) as number,
      );
      this.referenceToneEnabled = !!preferenceStore.getSync(TunerReferenceToneEnabledPreferenceKey, false);
      this.referenceNoteMidi = this.clampReferenceNoteMidi(
        preferenceStore.getSync(TunerReferenceNoteMidiPreferenceKey, 69) as number,
      );
      this.updateReferenceToneSynthesisTargets();
    } catch (error) {
      hilog.error(0, 'PDFTunerController', `加载调音器偏好出错: ${error}.`);
    }
  }

  private initializeAudio(): void {
    if (this.useNativeTone || this.audioRendererLoading || this.audioRenderer) {
      return;
    }
    if (prepareNativePiano()) {
      this.useNativeTone = true;
      hilog.info(0, 'PDFTunerController', '调音器参考音使用共享方波引擎');
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
    try {
      const audioRendererOptions: audio.AudioRendererOptions = {
        streamInfo: {
          samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_48000,
          channels: audio.AudioChannel.CHANNEL_1,
          sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
          encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW,
        },
        rendererInfo: {
          usage: audio.StreamUsage.STREAM_USAGE_AUDIOBOOK,
          rendererFlags: 0,
        },
      };
      const audioRenderer: audio.AudioRenderer = await audio.createAudioRenderer(audioRendererOptions);
      audioRenderer.on('writeData', this.handleAudioWriteData);

      if (requestToken !== this.audioRequestToken) {
        this.releaseDetachedAudioRenderer(audioRenderer);
        return;
      }

      this.audioRenderer = audioRenderer;
      if (this.playbackStartRequested && this.referenceToneEnabled) {
        this.startAudioRendererPlayback(this.audioPlaybackSessionToken);
      }
    } catch (error) {
      hilog.error(0, 'PDFTunerController', `初始化参考音AudioRenderer失败: ${JSON.stringify(error)}`);
      if (requestToken === this.audioRequestToken) {
        this.audioRenderer = undefined;
      }
    }
  }

  private releaseAudio(): void {
    this.audioRequestToken += 1;
    this.audioRendererLoading = false;
    if (this.useNativeTone) {
      nativePianoSetTunerTone(this.getReferenceToneFrequencyHz(), 0);
      this.useNativeTone = false;
      return;
    }
    const audioRenderer: audio.AudioRenderer | undefined = this.audioRenderer;
    this.audioRenderer = undefined;
    this.oscillatorAmplitude = 0;
    this.oscillatorTargetAmplitude = 0;
    this.oscillatorPhase = 0;
    this.oscillatorFrequencyHz = this.getReferenceToneFrequencyHz();
    this.oscillatorTargetFrequencyHz = this.oscillatorFrequencyHz;
    if (!audioRenderer) {
      return;
    }
    this.releaseDetachedAudioRenderer(audioRenderer);
  }

  private releaseDetachedAudioRenderer(audioRenderer: audio.AudioRenderer): void {
    try {
      audioRenderer.off('writeData', this.handleAudioWriteData);
    } catch (error) {
      hilog.error(0, 'PDFTunerController', `解绑参考音AudioRenderer回调失败: ${JSON.stringify(error)}`);
    }

    const releaseRenderer = async (): Promise<void> => {
      try {
        if (audioRenderer.state === audio.AudioState.STATE_RUNNING || audioRenderer.state === audio.AudioState.STATE_PAUSED) {
          await audioRenderer.stop();
        }
      } catch (error) {
        hilog.error(0, 'PDFTunerController', `停止参考音AudioRenderer失败: ${JSON.stringify(error)}`);
      }

      try {
        if (audioRenderer.state === audio.AudioState.STATE_STOPPED) {
          await audioRenderer.flush();
        }
      } catch (error) {
        hilog.error(0, 'PDFTunerController', `清空参考音AudioRenderer缓冲失败: ${JSON.stringify(error)}`);
      }

      try {
        if (audioRenderer.state !== audio.AudioState.STATE_RELEASED) {
          await audioRenderer.release();
        }
      } catch (error) {
        hilog.error(0, 'PDFTunerController', `释放参考音AudioRenderer失败: ${JSON.stringify(error)}`);
      }
    };

    void releaseRenderer();
  }

  private stopAudioRendererPlayback(): Promise<void> {
    if (!this.audioRenderer) {
      return Promise.resolve();
    }

    const audioRenderer: audio.AudioRenderer = this.audioRenderer;
    return (async (): Promise<void> => {
      try {
        if (audioRenderer.state === audio.AudioState.STATE_RUNNING || audioRenderer.state === audio.AudioState.STATE_PAUSED) {
          await audioRenderer.stop();
        }
      } catch (error) {
        hilog.error(0, 'PDFTunerController', `停止参考音播放失败: ${JSON.stringify(error)}`);
      }

      try {
        if (audioRenderer.state === audio.AudioState.STATE_STOPPED) {
          await audioRenderer.flush();
        }
      } catch (error) {
        hilog.error(0, 'PDFTunerController', `清空参考音播放缓冲失败: ${JSON.stringify(error)}`);
      }
    })();
  }

  private startAudioRendererPlayback(playbackToken: number): void {
    if (playbackToken !== this.audioPlaybackSessionToken || !this.playbackStartRequested || !this.referenceToneEnabled) {
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

        if (playbackToken !== this.audioPlaybackSessionToken || !this.playbackStartRequested || !this.referenceToneEnabled) {
          return;
        }

        if (audioRenderer.state === audio.AudioState.STATE_RUNNING) {
          return;
        }

        if (audioRenderer.state === audio.AudioState.STATE_STOPPED) {
          await audioRenderer.flush();
        }

        await audioRenderer.start();
      } catch (error) {
        if (playbackToken === this.audioPlaybackSessionToken && this.referenceToneEnabled) {
          hilog.error(0, 'PDFTunerController', `启动参考音播放失败: ${JSON.stringify(error)}`);
          this.stopReferenceTonePlayback();
        }
      }
    };

    void startRenderer();
  }

  private syncReferenceTonePlaybackState(): void {
    if (this.referenceToneEnabled && this.panelVisible) {
      if (!this.playbackStartRequested) {
        this.startReferenceTonePlayback();
      } else {
        this.updateReferenceToneSynthesisTargets();
      }
      return;
    }

    if (this.playbackStartRequested) {
      this.stopReferenceTonePlayback();
    } else {
      this.updateReferenceToneSynthesisTargets();
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
      this.preferenceStore.putSync(TunerFilterPresetPreferenceKey, this.filterPresetId);
      this.preferenceStore.putSync(TunerAutoGainEnabledPreferenceKey, this.autoGainEnabled);
      this.preferenceStore.putSync(TunerSpectrumGainPreferenceKey, this.spectrumGain);
      this.preferenceStore.putSync(TunerReferenceToneEnabledPreferenceKey, this.referenceToneEnabled);
      this.preferenceStore.putSync(TunerReferenceNoteMidiPreferenceKey, this.referenceNoteMidi);
      this.preferenceStore.flushSync();
    } catch (error) {
      hilog.error(0, 'PDFTunerController', `保存调音器偏好出错: ${error}.`);
    }
  }

  private clampReferenceHz(value: number): number {
    return Math.max(TunerReferenceHzMin, Math.min(TunerReferenceHzMax, Math.round(value)));
  }

  private clampTransposeIndex(value: number): number {
    return Math.max(0, Math.min(11, Math.round(value)));
  }

  private clampSpectrumGain(value: number): number {
    return Math.max(TunerSpectrumGainMin, Math.min(TunerSpectrumGainMax, value));
  }

  private clampReferenceNoteMidi(value: number): number {
    return Math.max(24, Math.min(108, Math.round(value)));
  }

  private clampPcmSample(value: number): number {
    return Math.max(-TunerReferenceToneMaxAmplitude - 1, Math.min(TunerReferenceToneMaxAmplitude, Math.round(value)));
  }

  private compressSpectrumLevel(linearValue: number): number {
    if (linearValue <= 0) {
      return 0;
    }
    const numerator: number = Math.log(1 + TunerMicSpectrumCompressionGamma * linearValue);
    const denominator: number = Math.log(1 + TunerMicSpectrumCompressionGamma);
    if (denominator <= 0) {
      return linearValue;
    }
    return numerator / denominator;
  }

  private initializeSmoothedMicSpectrum(): void {
    if (this.smoothedMicSpectrum.length === TunerMicSpectrumBandCount) {
      return;
    }
    this.smoothedMicSpectrum.length = 0;
    for (let i = 0; i < TunerMicSpectrumBandCount; i++) {
      this.smoothedMicSpectrum.push(0);
    }
  }

  private initializeTuneGraph(): void {
    if (this.tuneGraphCents.length === TunerTuneGraphCapacity) {
      return;
    }
    this.tuneGraphCents.length = 0;
    for (let index = 0; index < TunerTuneGraphCapacity; index++) {
      this.tuneGraphCents.push(Number.NaN);
    }
    this.tuneGraphCount = 0;
    this.tuneGraphWrite = 0;
  }

  private pushTuneGraphSample(cents: number): void {
    this.initializeTuneGraph();
    this.tuneGraphCents[this.tuneGraphWrite] = cents;
    this.tuneGraphWrite = (this.tuneGraphWrite + 1) % TunerTuneGraphCapacity;
    if (this.tuneGraphCount < TunerTuneGraphCapacity) {
      this.tuneGraphCount++;
    }
    this.notifyTuneGraphRedraw();
  }

  private clearTuneGraph(): void {
    this.initializeTuneGraph();
    for (let index = 0; index < TunerTuneGraphCapacity; index++) {
      this.tuneGraphCents[index] = Number.NaN;
    }
    this.tuneGraphCount = 0;
    this.tuneGraphWrite = 0;
    this.notifyTuneGraphRedraw();
  }

  private notifyTuneGraphRedraw(): void {
    this.tuneGraphEpoch++;
    const listeners: Array<() => void> = this.tuneGraphRedrawListeners.slice();
    for (let index = 0; index < listeners.length; index++) {
      try {
        listeners[index]();
      } catch (error) {
        hilog.error(0, 'PDFTunerController', `tuneGraph redraw listener failed: ${String(error)}`);
      }
    }
  }

  private getCurrentFilterPresetDefinition(): TunerFilterPresetDefinition {
    switch (this.filterPresetId) {
      case 'contrabass':
        return TunerFilterPresetDefinitions.contrabass;
      case 'bass':
        return TunerFilterPresetDefinitions.bass;
      case 'tenor':
        return TunerFilterPresetDefinitions.tenor;
      case 'alto':
        return TunerFilterPresetDefinitions.alto;
      case 'soprano':
        return TunerFilterPresetDefinitions.soprano;
      case 'chromatic':
      default:
        return TunerFilterPresetDefinitions.chromatic;
    }
  }

  private getAnalysisWindowSize(): number {
    if (this.filterPresetId === 'contrabass' || this.filterPresetId === 'bass') {
      return TunerAnalysisWindowLow;
    }
    return TunerAnalysisWindowDefault;
  }

  private pushNativeAnalysisConfig(): void {
    const preset = this.getCurrentFilterPresetDefinition();
    nativeTunerSetConfig(
      preset.pitchMinHz,
      preset.pitchMaxHz,
      preset.highPassHz,
      preset.lowPassHz,
      preset.rmsGateThreshold,
      this.getAnalysisWindowSize(),
    );
  }

  private getFirstOrderHighPassResponse(freqHz: number, cutoffHz: number): number {
    if (cutoffHz <= 0 || freqHz <= 0) {
      return 1;
    }
    return freqHz / Math.sqrt(freqHz * freqHz + cutoffHz * cutoffHz);
  }

  private getFirstOrderLowPassResponse(freqHz: number, cutoffHz: number): number {
    if (cutoffHz <= 0 || freqHz <= 0) {
      return 1;
    }
    return cutoffHz / Math.sqrt(freqHz * freqHz + cutoffHz * cutoffHz);
  }

  private updateFilterCurveLevels(): void {
    const preset = this.getCurrentFilterPresetDefinition();
    const nextLevels: number[] = [];
    for (let band = 0; band < TunerMicSpectrumBandCount; band++) {
      const freqHz: number = this.getMicSpectrumTargetFreqHz(band);
      const response: number = this.getFirstOrderHighPassResponse(freqHz, preset.highPassHz)
        * this.getFirstOrderLowPassResponse(freqHz, preset.lowPassHz);
      nextLevels.push(Math.max(0, Math.min(1, response)));
    }
    this.filterCurveLevels = nextLevels;
  }

  private updateSpectrumGain(envelopeFloor: number, rawInputEnvelope: number): void {
    if (!this.autoGainEnabled) {
      return;
    }
    if (rawInputEnvelope < TunerSpectrumAutoGainMinInputEnvelope) {
      return;
    }
    const desiredGain: number = this.clampSpectrumGain(
      TunerSpectrumAutoGainTargetEnvelope / Math.max(TunerMicEnvelopeFloorMin, envelopeFloor),
    );
    const smoothing: number = desiredGain < this.spectrumGain
      ? TunerSpectrumAutoGainAttack
      : TunerSpectrumAutoGainRelease;
    const nextGain: number = this.spectrumGain + (desiredGain - this.spectrumGain) * smoothing;
    const clampedGain: number = this.clampSpectrumGain(nextGain);
    if (Math.abs(clampedGain - this.spectrumGain) >= 0.001) {
      this.spectrumGain = clampedGain;
    }
  }

  private async ensureMicrophonePermission(
    context: common.UIAbilityContext,
    allowDialog: boolean,
  ): Promise<boolean> {
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const tokenId: number = context.applicationInfo.accessTokenId;
      const initialStatus: abilityAccessCtrl.GrantStatus =
        await atManager.checkAccessToken(tokenId, TunerMicPermission);
      if (initialStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return true;
      }
      if (!allowDialog) {
        return false;
      }
      const requestResult = await atManager.requestPermissionsFromUser(context, [TunerMicPermission]);
      const auth: number = requestResult.authResults[0];
      return auth === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (error) {
      hilog.error(0, 'PDFTunerController', `请求麦克风权限失败: ${JSON.stringify(error)}`);
      return false;
    }
  }

  private applyNativeSpectrum(result: TunerNativeAnalysisResult): void {
    const magnitudes: number[] = result.spectrumMagnitudes;
    let bandPeak: number = result.rawEnvelope;
    const bandCount: number = Math.min(TunerMicSpectrumBandCount, magnitudes.length);
    for (let band = 0; band < bandCount; band++) {
      bandPeak = Math.max(bandPeak, magnitudes[band]);
    }

    this.micPeakEnvelope = this.micPeakEnvelope * 0.992 + bandPeak * 0.008;
    const envelopeFloor: number = Math.max(TunerMicEnvelopeFloorMin, this.micPeakEnvelope);
    this.updateSpectrumGain(envelopeFloor, bandPeak);
    const effectiveSpectrumGain: number = this.spectrumGain;
    const nextLevels: number[] = [];
    for (let band = 0; band < TunerMicSpectrumBandCount; band++) {
      const curveLevel: number = this.filterCurveLevels[band] ?? 0;
      const rawMagnitude: number = magnitudes[band] ?? 0;
      const weightedInput: number = rawMagnitude * curveLevel * effectiveSpectrumGain / envelopeFloor;
      const instant: number = this.compressSpectrumLevel(weightedInput);
      const held: number = this.smoothedMicSpectrum[band];
      const nextHeld: number = instant > held
        ? instant
        : Math.max(0, held - TunerMicSpectrumPeakFallPerUpdate);
      this.smoothedMicSpectrum[band] = nextHeld;
      nextLevels.push(nextHeld);
    }
    if (this.shouldPublishSpectrumLevels(nextLevels)) {
      this.spectrumBarLevels = nextLevels.slice();
    }
  }

  private shouldPublishSpectrumLevels(nextLevels: number[]): boolean {
    if (this.spectrumBarLevels.length !== nextLevels.length) {
      return true;
    }
    for (let band = 0; band < nextLevels.length; band++) {
      if (Math.abs(this.spectrumBarLevels[band] - nextLevels[band]) >= TunerSpectrumBarPublishEpsilon) {
        return true;
      }
    }
    return false;
  }

  private getMicSpectrumTargetFreqHz(bandIndex: number): number {
    const t: number = bandIndex / (TunerMicSpectrumBandCount - 1);
    return TunerMicSpectrumFreqMinHz * Math.pow(TunerMicSpectrumFreqMaxHz / TunerMicSpectrumFreqMinHz, t);
  }

  private updateDetectedPitch(pitchHz: number): void {
    if (pitchHz <= 0) {
      this.pitchSilenceFrameCount++;
      if (this.pitchSilenceFrameCount > TunerPitchSilenceDecayFrames) {
        this.detectedNote = '--';
        this.detuneCents = 0;
        this.smoothedPitchHz = 0;
        this.displayCentsSmoothed = 0;
        this.pendingNoteHoldCount = 0;
      }
      this.pushTuneGraphSample(Number.NaN);
      return;
    }

    this.pitchSilenceFrameCount = 0;
    if (this.smoothedPitchHz <= 0) {
      this.smoothedPitchHz = pitchHz;
    } else {
      this.smoothedPitchHz += (pitchHz - this.smoothedPitchHz) * TunerPitchSmoothingFactor;
    }

    const midiFloat: number = 69 + 12 * Math.log2(this.smoothedPitchHz / this.referenceHz);
    const nearestMidi: number = Math.round(midiFloat);
    const rawCents: number = (midiFloat - nearestMidi) * 100;
    const semitone: number = ((nearestMidi % 12) + 12) % 12;
    const octave: number = Math.floor(nearestMidi / 12) - 1;
    const candidateNote: string = `${TunerPitchNoteNames[semitone]}${octave}`;

    this.displayCentsSmoothed += (rawCents - this.displayCentsSmoothed) * TunerDisplayCentsLerpFactor;
    const nextCents: number = Math.max(-50, Math.min(50, Math.round(this.displayCentsSmoothed)));
    if (nextCents !== this.detuneCents) {
      this.detuneCents = nextCents;
    }

    if (candidateNote === this.pendingNoteName) {
      this.pendingNoteHoldCount++;
    } else {
      this.pendingNoteName = candidateNote;
      this.pendingNoteHoldCount = 1;
    }
    if (this.pendingNoteHoldCount >= TunerDisplayNoteHoldFrames && this.detectedNote !== candidateNote) {
      this.detectedNote = candidateNote;
    }
    this.pushTuneGraphSample(nextCents);
  }

  private resetSpectrumLevels(): void {
    for (let i = 0; i < TunerMicSpectrumBandCount; i++) {
      this.smoothedMicSpectrum[i] = 0;
    }
    this.micPeakEnvelope = 0.0001;
    this.spectrumBarLevels = [
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    ];
    this.detectedNote = '--';
    this.detuneCents = 0;
    this.smoothedPitchHz = 0;
    this.pitchSilenceFrameCount = 0;
    this.displayCentsSmoothed = 0;
    this.pendingNoteName = '--';
    this.pendingNoteHoldCount = 0;
    this.clearTuneGraph();
  }
}
