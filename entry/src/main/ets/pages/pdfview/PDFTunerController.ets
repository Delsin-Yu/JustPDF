import { preferences } from '@kit.ArkData';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { audio } from '@kit.AudioKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TunerReferenceHzPreferenceKey: string = 'tunerReferenceHz';
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
const TunerMicSpectrumBandCount: number = 20;
const TunerMicSampleRateHz: number = 48000;
const TunerMicPermission: Permissions = 'ohos.permission.MICROPHONE';
const TunerMicSpectrumFreqMinHz: number = 90;
const TunerMicSpectrumFreqMaxHz: number = 6000;
/** 每次 readData 回调后，未刷新到新峰值时柱值线性回落的步长（0～∞量纲，与 instant 一致）。 */
const TunerMicSpectrumPeakFallPerUpdate: number = 0.032;

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

  @Trace public referenceHz: number = 440;
  @Trace public transposeIndex: number = 0;
  @Trace public noteDisplayMode: TunerNoteDisplayMode = 'standard';
  @Trace public noteNamingMode: TunerNoteNamingMode = 'pitch';
  @Trace public microphoneGainLow: number = 0.65;
  @Trace public microphoneGainMid: number = 0.65;
  @Trace public microphoneGainHigh: number = 0.65;
  @Trace public spectrumBarLevels: number[] = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ];
  @Trace public referenceToneEnabled: boolean = false;
  @Trace public referenceNoteMidi: number = 69;
  /** 用户曾拒绝麦克风授权后，不再自动弹窗，直至用户点击「重新请求」或系统设置中已授予。 */
  @Trace public microphonePermissionDenied: boolean = false;

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
      const sample: number = this.getTriangleWaveSample(this.oscillatorPhase) * this.oscillatorAmplitude;
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
        preferenceStore.getSync(TunerMicrophoneGainPreferenceKey, 0.65) as number,
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

  private clampPcmSample(value: number): number {
    return Math.max(-TunerReferenceToneMaxAmplitude - 1, Math.min(TunerReferenceToneMaxAmplitude, Math.round(value)));
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
    const envelopeFloor: number = Math.max(0.00008, this.micPeakEnvelope);
    const nextLevels: number[] = [];
    for (let band = 0; band < TunerMicSpectrumBandCount; band++) {
      const bandMicGain: number = this.getMicrophoneGainForSpectrumBand(band);
      const gainLinear: number = (0.2 + bandMicGain * 3.2) / envelopeFloor;
      const instant: number = Math.pow(rawMagnitudes[band] * gainLinear, 0.58);
      const held: number = this.smoothedMicSpectrum[band];
      const nextHeld: number = instant > held
        ? instant
        : Math.max(0, held - TunerMicSpectrumPeakFallPerUpdate);
      this.smoothedMicSpectrum[band] = nextHeld;
      nextLevels.push(nextHeld);
    }
    this.spectrumBarLevels = nextLevels.slice();
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

  private resetSpectrumLevels(): void {
    for (let i = 0; i < TunerMicSpectrumBandCount; i++) {
      this.smoothedMicSpectrum[i] = 0;
    }
    this.micPeakEnvelope = 0.0001;
    this.spectrumBarLevels = [
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    ];
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
