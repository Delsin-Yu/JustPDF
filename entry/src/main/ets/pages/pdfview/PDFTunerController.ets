import { preferences } from '@kit.ArkData';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { audio } from '@kit.AudioKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

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
const TunerMicSampleRateHz: number = 48000;
const TunerMicPermission: Permissions = 'ohos.permission.MICROPHONE';
const TunerMicSpectrumFreqMinHz: number = 90;
const TunerMicSpectrumFreqMaxHz: number = 6000;
/** 每次 readData 回调后，未刷新到新峰值时柱值线性回落的步长（0～∞量纲，与 instant 一致）。 */
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
const TunerPitchMinHz: number = 55;
const TunerPitchMaxHz: number = 2000;
/** 基频检测 RMS 静音门限（归一化振幅）。 */
const TunerPitchRmsGateThreshold: number = 0.008;
/** MPM 局部峰值阈值：过低会吸收噪声周期，过高会漏检弱音。 */
const TunerMpmPeakThreshold: number = 0.42;
/** MPM 最低清晰度阈值：用于过滤过于模糊的候选。 */
const TunerMpmMinClarity: number = 0.28;
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
/** 帧间允许的音高变化标准差（半音），越大越宽容。 */
const TunerPitchTransitionWidth: number = 5;
/** 转换代价占候选评分的权重；剩余部分为纯候选概率。 */
const TunerPitchTransitionWeight: number = 0.38;

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
  private audioCapturer: audio.AudioCapturer | undefined = undefined;
  private micCapturerLoading: boolean = false;
  private micCaptureSession: number = 0;
  private readonly smoothedMicSpectrum: number[] = [];
  private micPeakEnvelope: number = 0.0001;
  private micHighPassPrevInput: number = 0;
  private micHighPassPrevOutput: number = 0;
  private micLowPassPrevOutput: number = 0;
  private spectrumAutoGainTarget: number = 1;
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
  private smoothedPitchHz: number = 0;
  private pitchSilenceFrameCount: number = 0;
  private displayCentsSmoothed: number = 0;
  private pendingNoteName: string = '--';
  private pendingNoteHoldCount: number = 0;

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

  initialize(preferenceStore: preferences.Preferences): void {
    this.preferenceStore = preferenceStore;
    this.loadPreferences(preferenceStore);
    this.initializeSmoothedMicSpectrum();
    this.updateFilterCurveLevels();
    this.initializeAudio();
    this.syncReferenceTonePlaybackState();
  }

  cleanup(): void {
    this.stopMicrophoneMonitoring();
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
    if (this.audioCapturer || this.micCapturerLoading) {
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
      if (!this.panelVisible) {
        return;
      }
      await this.createAndStartMicCapturer();
    } catch (error) {
      hilog.error(0, 'PDFTunerController', `启动麦克风采集失败: ${JSON.stringify(error)}`);
      this.resetSpectrumLevels();
    } finally {
      this.micCapturerLoading = false;
    }
  }

  stopMicrophoneMonitoring(): void {
    this.micCaptureSession += 1;
    const capturer: audio.AudioCapturer | undefined = this.audioCapturer;
    this.audioCapturer = undefined;
    this.resetSpectrumLevels();
    if (!capturer) {
      return;
    }
    void this.releaseDetachedAudioCapturer(capturer);
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
    this.resetPreprocessorState();
    this.savePreferences();
  }

  setAutoGainEnabled(value: boolean): void {
    if (this.autoGainEnabled === value) {
      return;
    }
    this.autoGainEnabled = value;
    if (value) {
      this.spectrumAutoGainTarget = this.spectrumGain;
    }
    this.savePreferences();
  }

  setSpectrumGain(value: number): void {
    const nextValue: number = this.clampSpectrumGain(value);
    this.spectrumAutoGainTarget = nextValue;
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

  setReferenceNoteMidi(value: number): void {
    const nextValue = this.clampReferenceNoteMidi(value);
    if (this.referenceNoteMidi === nextValue) {
      return;
    }
    this.referenceNoteMidi = nextValue;
    this.updateReferenceToneSynthesisTargets();
    this.savePreferences();
  }

  private getTriangleWaveSample(phase: number): number {
    const normalizedPhase: number = phase / (2 * Math.PI);
    return 1 - 4 * Math.abs(normalizedPhase - 0.5);
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

  private readonly handleCapturerReadData = (buffer: ArrayBuffer): void => {
    if (!this.audioCapturer) {
      return;
    }
    this.processMicPcmBuffer(buffer);
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
      const sample: number = this.getTriangleWaveSample(this.oscillatorPhase) * this.oscillatorAmplitude * loudnessComp;
      output[sampleIndex] = this.clampPcmSample(Math.round(sample * TunerReferenceToneMaxAmplitude));
    }

    return audio.AudioDataCallbackResult.VALID;
  };

  private startReferenceTonePlayback(): void {
    this.playbackStartRequested = true;
    this.updateReferenceToneSynthesisTargets();
    this.startAudioRendererPlayback(++this.audioPlaybackSessionToken);
  }

  private stopReferenceTonePlayback(): void {
    this.playbackStartRequested = false;
    this.audioPlaybackSessionToken += 1;
    this.updateReferenceToneSynthesisTargets();
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
      this.spectrumAutoGainTarget = this.spectrumGain;
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
    if (this.audioRendererLoading || this.audioRenderer) {
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

  private resetPreprocessorState(): void {
    this.micHighPassPrevInput = 0;
    this.micHighPassPrevOutput = 0;
    this.micLowPassPrevOutput = 0;
  }

  private getHighPassAlpha(cutoffHz: number): number {
    if (cutoffHz <= 0) {
      return 0;
    }
    const dt: number = 1 / TunerMicSampleRateHz;
    const rc: number = 1 / (2 * Math.PI * cutoffHz);
    return rc / (rc + dt);
  }

  private getLowPassAlpha(cutoffHz: number): number {
    if (cutoffHz <= 0) {
      return 1;
    }
    const dt: number = 1 / TunerMicSampleRateHz;
    const rc: number = 1 / (2 * Math.PI * cutoffHz);
    return dt / (rc + dt);
  }

  private preprocessMicSamples(sourceSamples: Int16Array): Float32Array {
    const preset = this.getCurrentFilterPresetDefinition();
    const highPassAlpha: number = this.getHighPassAlpha(preset.highPassHz);
    const lowPassAlpha: number = this.getLowPassAlpha(preset.lowPassHz);
    const filteredSamples: Float32Array = new Float32Array(sourceSamples.length);
    for (let i = 0; i < sourceSamples.length; i++) {
      let sample: number = sourceSamples[i] / 32768;
      if (preset.highPassHz > 0) {
        const nextHighPass: number = highPassAlpha * (this.micHighPassPrevOutput + sample - this.micHighPassPrevInput);
        this.micHighPassPrevInput = sample;
        this.micHighPassPrevOutput = nextHighPass;
        sample = nextHighPass;
      }
      if (preset.lowPassHz > 0) {
        this.micLowPassPrevOutput += lowPassAlpha * (sample - this.micLowPassPrevOutput);
        sample = this.micLowPassPrevOutput;
      }
      filteredSamples[i] = sample;
    }
    return filteredSamples;
  }

  private updateSpectrumGain(envelopeFloor: number, rawInputEnvelope: number): void {
    if (!this.autoGainEnabled) {
      return;
    }
    if (rawInputEnvelope < TunerSpectrumAutoGainMinInputEnvelope) {
      this.spectrumAutoGainTarget = this.spectrumGain;
      return;
    }
    const desiredGain: number = this.clampSpectrumGain(
      TunerSpectrumAutoGainTargetEnvelope / Math.max(TunerMicEnvelopeFloorMin, envelopeFloor),
    );
    const smoothing: number = desiredGain < this.spectrumGain
      ? TunerSpectrumAutoGainAttack
      : TunerSpectrumAutoGainRelease;
    const nextGain: number = this.spectrumGain + (desiredGain - this.spectrumGain) * smoothing;
    this.spectrumAutoGainTarget = desiredGain;
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

  private async createAndStartMicCapturer(): Promise<void> {
    const sessionId: number = this.micCaptureSession;
    try {
      const capturerOptions: audio.AudioCapturerOptions = {
        streamInfo: {
          samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_48000,
          channels: audio.AudioChannel.CHANNEL_1,
          sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
          encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW,
        },
        capturerInfo: {
          source: audio.SourceType.SOURCE_TYPE_MIC,
          capturerFlags: 0,
        },
      };
      const capturer: audio.AudioCapturer = await audio.createAudioCapturer(capturerOptions);
      if (sessionId !== this.micCaptureSession) {
        await this.releaseDetachedAudioCapturer(capturer);
        return;
      }

      this.audioCapturer = capturer;
      capturer.on('readData', this.handleCapturerReadData);
      await capturer.start();
      if (sessionId !== this.micCaptureSession) {
        this.audioCapturer = undefined;
        await this.releaseDetachedAudioCapturer(capturer);
        return;
      }
    } catch (error) {
      if (sessionId === this.micCaptureSession) {
        this.audioCapturer = undefined;
        hilog.error(0, 'PDFTunerController', `创建或启动麦克风AudioCapturer失败: ${JSON.stringify(error)}`);
      }
      this.resetSpectrumLevels();
    }
  }

  private processMicPcmBuffer(buffer: ArrayBuffer): void {
    const samples: Float32Array = this.preprocessMicSamples(new Int16Array(buffer));
    if (samples.length === 0) {
      return;
    }

    const n: number = samples.length;
    const invN: number = 1 / Math.max(1, n - 1);
    const rawMagnitudes: number[] = [];
    let bandPeak: number = 0;
    for (let band = 0; band < TunerMicSpectrumBandCount; band++) {
      const freqHz: number = this.getMicSpectrumTargetFreqHz(band);
      const omegaPerSample: number = (2 * Math.PI * freqHz) / TunerMicSampleRateHz;
      let re: number = 0;
      let im: number = 0;
      for (let i = 0; i < n; i++) {
        const hann: number = 0.5 * (1 - Math.cos((2 * Math.PI * i) * invN));
        const x: number = samples[i] * hann;
        const angle: number = omegaPerSample * i;
        re += x * Math.cos(angle);
        im -= x * Math.sin(angle);
      }
      const mag: number = Math.sqrt(re * re + im * im) / n;
      rawMagnitudes.push(mag);
      bandPeak = Math.max(bandPeak, mag);
    }

    this.micPeakEnvelope = this.micPeakEnvelope * 0.992 + bandPeak * 0.008;
    const envelopeFloor: number = Math.max(TunerMicEnvelopeFloorMin, this.micPeakEnvelope);
    this.updateSpectrumGain(envelopeFloor, bandPeak);
    const effectiveSpectrumGain: number = this.spectrumGain;
    const nextLevels: number[] = [];
    for (let band = 0; band < TunerMicSpectrumBandCount; band++) {
      const curveLevel: number = this.filterCurveLevels[band] ?? 0;
      const weightedInput: number = rawMagnitudes[band] * curveLevel * effectiveSpectrumGain / envelopeFloor;
      const instant: number = this.compressSpectrumLevel(weightedInput);
      const held: number = this.smoothedMicSpectrum[band];
      const nextHeld: number = instant > held
        ? instant
        : Math.max(0, held - TunerMicSpectrumPeakFallPerUpdate);
      this.smoothedMicSpectrum[band] = nextHeld;
      nextLevels.push(nextHeld);
    }
    this.spectrumBarLevels = nextLevels.slice();
    this.updateDetectedPitch(this.detectPitchHz(samples));
  }

  private getMicSpectrumTargetFreqHz(bandIndex: number): number {
    const t: number = bandIndex / (TunerMicSpectrumBandCount - 1);
    return TunerMicSpectrumFreqMinHz * Math.pow(TunerMicSpectrumFreqMaxHz / TunerMicSpectrumFreqMinHz, t);
  }

  /**
   * MPM（McLeod Pitch Method）基频检测：
   * 1. 计算 NSDF（Normalized Square Difference Function）
   * 2. 在当前预设音域内寻找局部峰值
   * 3. 对最佳峰值做抛物线插值，并结合前一帧音高抑制跳变
   */
  private detectPitchHz(samples: Float32Array): number {
    const n: number = samples.length;
    const preset = this.getCurrentFilterPresetDefinition();
    const minLag: number = Math.floor(TunerMicSampleRateHz / preset.pitchMaxHz);
    const maxLag: number = Math.min(
      Math.floor(TunerMicSampleRateHz / preset.pitchMinHz),
      Math.floor(n / 2),
    );
    if (maxLag <= minLag) {
      return 0;
    }

    let sumSq: number = 0;
    for (let i: number = 0; i < n; i++) {
      const s: number = samples[i];
      sumSq += s * s;
    }
    if (Math.sqrt(sumSq / n) < preset.rmsGateThreshold) {
      return 0;
    }

    const nsdf: number[] = new Array<number>(maxLag + 1);
    nsdf[0] = 1;
    for (let tau: number = 1; tau <= maxLag; tau++) {
      let acf: number = 0;
      let divisor: number = 0;
      for (let i: number = 0; i < n - tau; i++) {
        const x: number = samples[i];
        const y: number = samples[i + tau];
        acf += x * y;
        divisor += x * x + y * y;
      }
      nsdf[tau] = divisor > 0 ? (2 * acf) / divisor : 0;
    }

    let bestScore: number = -1;
    let bestRefinedTau: number = 0;

    for (let tau: number = minLag + 1; tau < maxLag; tau++) {
      const peakValue: number = nsdf[tau];
      if (
        peakValue < TunerMpmPeakThreshold ||
        peakValue < nsdf[tau - 1] ||
        peakValue <= nsdf[tau + 1]
      ) {
        continue;
      }

      const s0: number = nsdf[tau - 1];
      const s1: number = peakValue;
      const s2: number = nsdf[tau + 1];
      const denom: number = s0 - 2 * s1 + s2;
      let refinedTau: number = tau;
      if (Math.abs(denom) > 1e-6) {
        refinedTau = tau + (s0 - s2) / (2 * denom);
      }

      let score: number = peakValue;
      if (this.smoothedPitchHz > 0) {
        const freqHz: number = TunerMicSampleRateHz / refinedTau;
        const semitones: number = Math.abs(12 * Math.log2(freqHz / this.smoothedPitchHz));
        const twiceSigmaSq: number = 2 * TunerPitchTransitionWidth * TunerPitchTransitionWidth;
        const transition: number = Math.exp(-semitones * semitones / twiceSigmaSq);
        score *= TunerPitchTransitionWeight * transition + (1 - TunerPitchTransitionWeight);
      }

      if (score > bestScore) {
        bestScore = score;
        bestRefinedTau = refinedTau;
      }
    }

    if (bestRefinedTau <= 0 || bestScore < TunerMpmMinClarity) {
      return 0;
    }
    return TunerMicSampleRateHz / bestRefinedTau;
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
  }

  private resetSpectrumLevels(): void {
    for (let i = 0; i < TunerMicSpectrumBandCount; i++) {
      this.smoothedMicSpectrum[i] = 0;
    }
    this.resetPreprocessorState();
    this.micPeakEnvelope = 0.0001;
    this.spectrumAutoGainTarget = this.spectrumGain;
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
  }

  private async releaseDetachedAudioCapturer(capturer: audio.AudioCapturer): Promise<void> {
    try {
      capturer.off('readData', this.handleCapturerReadData);
    } catch (error) {
      hilog.error(0, 'PDFTunerController', `解绑麦克风readData监听失败: ${JSON.stringify(error)}`);
    }

    try {
      if (capturer.state === audio.AudioState.STATE_RUNNING || capturer.state === audio.AudioState.STATE_PAUSED) {
        await capturer.stop();
      }
    } catch (error) {
      hilog.error(0, 'PDFTunerController', `停止麦克风采集失败: ${JSON.stringify(error)}`);
    }

    try {
      if (capturer.state !== audio.AudioState.STATE_RELEASED) {
        await capturer.release();
      }
    } catch (error) {
      hilog.error(0, 'PDFTunerController', `释放麦克风AudioCapturer失败: ${JSON.stringify(error)}`);
    }
  }
}
