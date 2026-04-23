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
const TunerMicrophoneGainPreferenceKey: string = 'tunerMicrophoneGain';
const TunerMicrophoneGainLowPreferenceKey: string = 'tunerMicrophoneGainLow';
const TunerMicrophoneGainMidPreferenceKey: string = 'tunerMicrophoneGainMid';
const TunerMicrophoneGainHighPreferenceKey: string = 'tunerMicrophoneGainHigh';
const TunerMicGainLowMaxHz: number = 300;
const TunerMicGainMidMaxHz: number = 4000;
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
/** 三段增益映射：将滑杆值映射到较温和的线性增益，避免最大档持续过载。 */
const TunerMicGainLinearBase: number = 0.12;
const TunerMicGainLinearRange: number = 0.70;
/** 包络地板：限制极低噪声时的归一化放大倍率。 */
const TunerMicEnvelopeFloorMin: number = 0.0012;
/** 低频附加衰减：在最低频段使用更小权重，逐步过渡到 1。 */
const TunerMicLowWeightMin: number = 0.52;
const TunerMicLowWeightTransitionMaxHz: number = TunerMicGainLowMaxHz;
const TunerMicLowWeightCurvePower: number = 1.7;
/** 诊断日志节流：避免 readData 回调中频繁打印。 */
const TunerMicSpectrumLogIntervalMs: number = 1500;
const TunerPitchMinHz: number = 55;
const TunerPitchMaxHz: number = 2000;
/** 基频检测 RMS 静音门限（归一化振幅）。 */
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
/**
 * pYIN 参数（Mauch & Dixon, ICASSP 2014）。
 * 使用 Beta(2, 18) 先验的生存函数对 CMNDF 局部极小值打分，
 * 再用帧间高斯转换代价做在线 pitch tracking，抑制八度跳变。
 */
/** Beta(2,18) 生存函数：S(v) = (1-v)^18 · (1 + 18v)，低于此概率的候选直接丢弃。 */
const TunerPyinMinCandidateProb: number = 0.01;
/** 帧间允许的音高变化标准差（半音），越大越宽容。 */
const TunerPyinTransitionWidth: number = 5;
/** 转换代价占候选评分的权重；剩余部分为纯候选概率。 */
const TunerPyinTransitionWeight: number = 0.48;

export type TunerNoteDisplayMode = 'standard' | 'sharp' | 'flat';
export type TunerNoteNamingMode = 'pitch' | 'solfege';
export type TunerMicrophoneBand = 'low' | 'mid' | 'high';

const TunerValidDisplayModes: TunerNoteDisplayMode[] = ['standard', 'sharp', 'flat'];
const TunerValidNamingModes: TunerNoteNamingMode[] = ['pitch', 'solfege'];

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
  private micSpectrumLogLastTimestampMs: number = 0;
  private micSpectrumLogFrameCount: number = 0;
  private micSpectrumLogBandPeakMax: number = 0;
  private micSpectrumLogEnvelopeMax: number = 0;
  private micSpectrumLogRawLowMax: number = 0;
  private micSpectrumLogRawMidMax: number = 0;
  private micSpectrumLogRawHighMax: number = 0;
  private micSpectrumLogPreCurveLowMax: number = 0;
  private micSpectrumLogPreCurveMidMax: number = 0;
  private micSpectrumLogPreCurveHighMax: number = 0;
  private micSpectrumLogPostCurveLowMax: number = 0;
  private micSpectrumLogPostCurveMidMax: number = 0;
  private micSpectrumLogPostCurveHighMax: number = 0;
  private readonly micSpectrumLogOverloadCount: number[] = [];
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
  @Trace public microphoneGainLow: number = 0.5;
  @Trace public microphoneGainMid: number = 0.5;
  @Trace public microphoneGainHigh: number = 0.5;
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

  setMicrophoneBandGain(band: TunerMicrophoneBand, value: number): void {
    const nextValue: number = this.clampMicrophoneGain(value);
    if (band === 'low') {
      if (this.microphoneGainLow === nextValue) {
        return;
      }
      this.microphoneGainLow = nextValue;
    } else if (band === 'mid') {
      if (this.microphoneGainMid === nextValue) {
        return;
      }
      this.microphoneGainMid = nextValue;
    } else {
      if (this.microphoneGainHigh === nextValue) {
        return;
      }
      this.microphoneGainHigh = nextValue;
    }
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
      const legacyMicGain: number = this.clampMicrophoneGain(
        preferenceStore.getSync(TunerMicrophoneGainPreferenceKey, 0.5) as number,
      );
      this.microphoneGainLow = this.clampMicrophoneGain(
        preferenceStore.getSync(TunerMicrophoneGainLowPreferenceKey, legacyMicGain) as number,
      );
      this.microphoneGainMid = this.clampMicrophoneGain(
        preferenceStore.getSync(TunerMicrophoneGainMidPreferenceKey, legacyMicGain) as number,
      );
      this.microphoneGainHigh = this.clampMicrophoneGain(
        preferenceStore.getSync(TunerMicrophoneGainHighPreferenceKey, legacyMicGain) as number,
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
      this.preferenceStore.putSync(TunerMicrophoneGainLowPreferenceKey, this.microphoneGainLow);
      this.preferenceStore.putSync(TunerMicrophoneGainMidPreferenceKey, this.microphoneGainMid);
      this.preferenceStore.putSync(TunerMicrophoneGainHighPreferenceKey, this.microphoneGainHigh);
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

  private clampMicrophoneGain(value: number): number {
    return Math.max(0, Math.min(1, value));
  }

  private clampReferenceNoteMidi(value: number): number {
    return Math.max(24, Math.min(108, Math.round(value)));
  }

  private clampPcmSample(value: number): number {
    return Math.max(-TunerReferenceToneMaxAmplitude - 1, Math.min(TunerReferenceToneMaxAmplitude, Math.round(value)));
  }

  private clampUnit(value: number): number {
    return Math.max(0, Math.min(1, value));
  }

  private getLowFrequencyWeight(freqHz: number): number {
    if (freqHz >= TunerMicLowWeightTransitionMaxHz) {
      return 1;
    }
    if (freqHz <= TunerMicSpectrumFreqMinHz) {
      return TunerMicLowWeightMin;
    }
    const ratio: number = (freqHz - TunerMicSpectrumFreqMinHz)
      / (TunerMicLowWeightTransitionMaxHz - TunerMicSpectrumFreqMinHz);
    const curvedRatio: number = Math.pow(this.clampUnit(ratio), TunerMicLowWeightCurvePower);
    return TunerMicLowWeightMin + curvedRatio * (1 - TunerMicLowWeightMin);
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

  private mapSliderGainToLinear(bandMicGain: number): number {
    return TunerMicGainLinearBase + this.clampUnit(bandMicGain) * TunerMicGainLinearRange;
  }

  private initializeSmoothedMicSpectrum(): void {
    if (this.smoothedMicSpectrum.length === TunerMicSpectrumBandCount) {
      return;
    }
    this.smoothedMicSpectrum.length = 0;
    for (let i = 0; i < TunerMicSpectrumBandCount; i++) {
      this.smoothedMicSpectrum.push(0);
    }
    this.micSpectrumLogOverloadCount.length = 0;
    for (let i = 0; i < TunerMicSpectrumBandCount; i++) {
      this.micSpectrumLogOverloadCount.push(0);
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
    const samples: Int16Array = new Int16Array(buffer);
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
        const x: number = (samples[i] / 32768) * hann;
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
    const nextLevels: number[] = [];
    let rawLowMax: number = 0;
    let rawMidMax: number = 0;
    let rawHighMax: number = 0;
    let preCurveLowMax: number = 0;
    let preCurveMidMax: number = 0;
    let preCurveHighMax: number = 0;
    let postCurveLowMax: number = 0;
    let postCurveMidMax: number = 0;
    let postCurveHighMax: number = 0;
    for (let band = 0; band < TunerMicSpectrumBandCount; band++) {
      const freqHz: number = this.getMicSpectrumTargetFreqHz(band);
      const bandMicGain: number = this.getMicrophoneGainForSpectrumBand(band);
      const gainLinear: number = this.mapSliderGainToLinear(bandMicGain) / envelopeFloor;
      const weightedInput: number = rawMagnitudes[band] * gainLinear * this.getLowFrequencyWeight(freqHz);
      const instant: number = this.compressSpectrumLevel(weightedInput);
      const held: number = this.smoothedMicSpectrum[band];
      const nextHeld: number = instant > held
        ? instant
        : Math.max(0, held - TunerMicSpectrumPeakFallPerUpdate);
      if (freqHz < TunerMicGainLowMaxHz) {
        rawLowMax = Math.max(rawLowMax, rawMagnitudes[band]);
        preCurveLowMax = Math.max(preCurveLowMax, weightedInput);
        postCurveLowMax = Math.max(postCurveLowMax, instant);
      } else if (freqHz <= TunerMicGainMidMaxHz) {
        rawMidMax = Math.max(rawMidMax, rawMagnitudes[band]);
        preCurveMidMax = Math.max(preCurveMidMax, weightedInput);
        postCurveMidMax = Math.max(postCurveMidMax, instant);
      } else {
        rawHighMax = Math.max(rawHighMax, rawMagnitudes[band]);
        preCurveHighMax = Math.max(preCurveHighMax, weightedInput);
        postCurveHighMax = Math.max(postCurveHighMax, instant);
      }
      if (nextHeld > 1 && band < this.micSpectrumLogOverloadCount.length) {
        this.micSpectrumLogOverloadCount[band] += 1;
      }
      this.smoothedMicSpectrum[band] = nextHeld;
      nextLevels.push(nextHeld);
    }
    this.spectrumBarLevels = nextLevels.slice();
    this.updateDetectedPitch(this.detectPitchHz(samples));
    this.collectMicSpectrumDiagnostics(
      bandPeak,
      envelopeFloor,
      rawLowMax,
      rawMidMax,
      rawHighMax,
      preCurveLowMax,
      preCurveMidMax,
      preCurveHighMax,
      postCurveLowMax,
      postCurveMidMax,
      postCurveHighMax,
    );
  }

  private collectMicSpectrumDiagnostics(
    bandPeak: number,
    envelopeFloor: number,
    rawLowMax: number,
    rawMidMax: number,
    rawHighMax: number,
    preCurveLowMax: number,
    preCurveMidMax: number,
    preCurveHighMax: number,
    postCurveLowMax: number,
    postCurveMidMax: number,
    postCurveHighMax: number,
  ): void {
    this.micSpectrumLogFrameCount += 1;
    this.micSpectrumLogBandPeakMax = Math.max(this.micSpectrumLogBandPeakMax, bandPeak);
    this.micSpectrumLogEnvelopeMax = Math.max(this.micSpectrumLogEnvelopeMax, envelopeFloor);
    this.micSpectrumLogRawLowMax = Math.max(this.micSpectrumLogRawLowMax, rawLowMax);
    this.micSpectrumLogRawMidMax = Math.max(this.micSpectrumLogRawMidMax, rawMidMax);
    this.micSpectrumLogRawHighMax = Math.max(this.micSpectrumLogRawHighMax, rawHighMax);
    this.micSpectrumLogPreCurveLowMax = Math.max(this.micSpectrumLogPreCurveLowMax, preCurveLowMax);
    this.micSpectrumLogPreCurveMidMax = Math.max(this.micSpectrumLogPreCurveMidMax, preCurveMidMax);
    this.micSpectrumLogPreCurveHighMax = Math.max(this.micSpectrumLogPreCurveHighMax, preCurveHighMax);
    this.micSpectrumLogPostCurveLowMax = Math.max(this.micSpectrumLogPostCurveLowMax, postCurveLowMax);
    this.micSpectrumLogPostCurveMidMax = Math.max(this.micSpectrumLogPostCurveMidMax, postCurveMidMax);
    this.micSpectrumLogPostCurveHighMax = Math.max(this.micSpectrumLogPostCurveHighMax, postCurveHighMax);
    const nowMs: number = Date.now();
    if (this.micSpectrumLogLastTimestampMs > 0 && nowMs - this.micSpectrumLogLastTimestampMs < TunerMicSpectrumLogIntervalMs) {
      return;
    }
    const sortedBandIndices: number[] = Array.from(
      { length: this.micSpectrumLogOverloadCount.length },
      (_value: number, bandIndex: number) => bandIndex,
    )
      .sort((a: number, b: number) => this.micSpectrumLogOverloadCount[b] - this.micSpectrumLogOverloadCount[a]);
    const overloadBands: string[] = [];
    for (let i = 0; i < sortedBandIndices.length && overloadBands.length < 4; i++) {
      const bandIndex: number = sortedBandIndices[i];
      const count: number = this.micSpectrumLogOverloadCount[bandIndex];
      if (count <= 0) {
        continue;
      }
      overloadBands.push(`${bandIndex}:${count}`);
    }
    hilog.info(
      0,
      'PDFTunerController',
      `调音器频谱诊断 frame=${this.micSpectrumLogFrameCount} gain=[${this.microphoneGainLow.toFixed(2)},` +
      `${this.microphoneGainMid.toFixed(2)},${this.microphoneGainHigh.toFixed(2)}] bandPeak=${this.micSpectrumLogBandPeakMax.toFixed(5)} ` +
      `env=${this.micSpectrumLogEnvelopeMax.toFixed(5)} rawMax=[${this.micSpectrumLogRawLowMax.toFixed(5)},` +
      `${this.micSpectrumLogRawMidMax.toFixed(5)},${this.micSpectrumLogRawHighMax.toFixed(5)}] preCurveMax=[` +
      `${this.micSpectrumLogPreCurveLowMax.toFixed(3)},${this.micSpectrumLogPreCurveMidMax.toFixed(3)},` +
      `${this.micSpectrumLogPreCurveHighMax.toFixed(3)}] postCurveMax=[${this.micSpectrumLogPostCurveLowMax.toFixed(3)},` +
      `${this.micSpectrumLogPostCurveMidMax.toFixed(3)},${this.micSpectrumLogPostCurveHighMax.toFixed(3)}] ` +
      `overload=${overloadBands.length > 0 ? overloadBands.join('|') : 'none'}`,
    );
    this.micSpectrumLogLastTimestampMs = nowMs;
    this.micSpectrumLogFrameCount = 0;
    this.micSpectrumLogBandPeakMax = 0;
    this.micSpectrumLogEnvelopeMax = 0;
    this.micSpectrumLogRawLowMax = 0;
    this.micSpectrumLogRawMidMax = 0;
    this.micSpectrumLogRawHighMax = 0;
    this.micSpectrumLogPreCurveLowMax = 0;
    this.micSpectrumLogPreCurveMidMax = 0;
    this.micSpectrumLogPreCurveHighMax = 0;
    this.micSpectrumLogPostCurveLowMax = 0;
    this.micSpectrumLogPostCurveMidMax = 0;
    this.micSpectrumLogPostCurveHighMax = 0;
    for (let i = 0; i < this.micSpectrumLogOverloadCount.length; i++) {
      this.micSpectrumLogOverloadCount[i] = 0;
    }
  }

  private getMicSpectrumTargetFreqHz(bandIndex: number): number {
    const t: number = bandIndex / (TunerMicSpectrumBandCount - 1);
    return TunerMicSpectrumFreqMinHz * Math.pow(TunerMicSpectrumFreqMaxHz / TunerMicSpectrumFreqMinHz, t);
  }

  private getMicrophoneGainForSpectrumBand(bandIndex: number): number {
    const freqHz: number = this.getMicSpectrumTargetFreqHz(bandIndex);
    if (freqHz < TunerMicGainLowMaxHz) {
      return this.microphoneGainLow;
    }
    if (freqHz <= TunerMicGainMidMaxHz) {
      return this.microphoneGainMid;
    }
    return this.microphoneGainHigh;
  }

  /**
   * pYIN 基频检测：
   * 1. 计算 CMNDF（与 YIN 步骤 1-4 相同）
   * 2. 提取所有局部极小值，用 Beta(2,18) 生存函数为每个候选打分
   * 3. 结合前帧 pitch 的高斯转换代价做在线 tracking
   */
  private detectPitchHz(samples: Int16Array): number {
    const n: number = samples.length;
    const minLag: number = Math.floor(TunerMicSampleRateHz / TunerPitchMaxHz);
    const maxLag: number = Math.min(
      Math.floor(TunerMicSampleRateHz / TunerPitchMinHz),
      Math.floor(n / 2),
    );
    if (maxLag <= minLag) {
      return 0;
    }

    let sumSq: number = 0;
    for (let i: number = 0; i < n; i++) {
      const s: number = samples[i] / 32768;
      sumSq += s * s;
    }
    if (Math.sqrt(sumSq / n) < TunerPitchRmsGateThreshold) {
      return 0;
    }

    const windowLen: number = n - maxLag;
    const yinSize: number = maxLag + 1;
    const cmndf: number[] = new Array<number>(yinSize);
    cmndf[0] = 1;
    let runningSum: number = 0;
    for (let tau: number = 1; tau < yinSize; tau++) {
      let diff: number = 0;
      for (let i: number = 0; i < windowLen; i++) {
        const delta: number = (samples[i] - samples[i + tau]) / 32768;
        diff += delta * delta;
      }
      runningSum += diff;
      cmndf[tau] = runningSum > 0 ? diff * tau / runningSum : 1;
    }

    let bestScore: number = -1;
    let bestRefinedTau: number = 0;

    for (let tau: number = minLag + 1; tau < yinSize - 1; tau++) {
      if (cmndf[tau] >= cmndf[tau - 1] || cmndf[tau] > cmndf[tau + 1]) {
        continue;
      }

      const val: number = Math.max(0, Math.min(1, cmndf[tau]));
      const oneMinusVal: number = 1 - val;
      const prob: number = Math.pow(oneMinusVal, 18) * (1 + 18 * val);
      if (prob < TunerPyinMinCandidateProb) {
        continue;
      }

      const s0: number = cmndf[tau - 1];
      const s1: number = cmndf[tau];
      const s2: number = cmndf[tau + 1];
      const denom: number = 2 * s1 - s2 - s0;
      let refinedTau: number = tau;
      if (denom !== 0) {
        refinedTau = tau + (s0 - s2) / (2 * denom);
      }

      let score: number = prob;
      if (this.smoothedPitchHz > 0) {
        const freqHz: number = TunerMicSampleRateHz / refinedTau;
        const semitones: number = Math.abs(12 * Math.log2(freqHz / this.smoothedPitchHz));
        const twiceSigmaSq: number = 2 * TunerPyinTransitionWidth * TunerPyinTransitionWidth;
        const transition: number = Math.exp(-semitones * semitones / twiceSigmaSq);
        score *= TunerPyinTransitionWeight * transition + (1 - TunerPyinTransitionWeight);
      }

      if (score > bestScore) {
        bestScore = score;
        bestRefinedTau = refinedTau;
      }
    }

    if (bestRefinedTau <= 0) {
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
    this.micPeakEnvelope = 0.0001;
    this.micSpectrumLogFrameCount = 0;
    this.micSpectrumLogBandPeakMax = 0;
    this.micSpectrumLogEnvelopeMax = 0;
    this.micSpectrumLogRawLowMax = 0;
    this.micSpectrumLogRawMidMax = 0;
    this.micSpectrumLogRawHighMax = 0;
    this.micSpectrumLogPreCurveLowMax = 0;
    this.micSpectrumLogPreCurveMidMax = 0;
    this.micSpectrumLogPreCurveHighMax = 0;
    this.micSpectrumLogPostCurveLowMax = 0;
    this.micSpectrumLogPostCurveMidMax = 0;
    this.micSpectrumLogPostCurveHighMax = 0;
    this.micSpectrumLogLastTimestampMs = 0;
    for (let i = 0; i < this.micSpectrumLogOverloadCount.length; i++) {
      this.micSpectrumLogOverloadCount[i] = 0;
    }
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
