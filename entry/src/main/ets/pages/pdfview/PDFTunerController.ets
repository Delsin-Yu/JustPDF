import { preferences } from '@kit.ArkData';
import { audio } from '@kit.AudioKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TunerReferenceHzPreferenceKey: string = 'tunerReferenceHz';
const TunerTransposeIndexPreferenceKey: string = 'tunerTransposeIndex';
const TunerNoteDisplayModePreferenceKey: string = 'tunerNoteDisplayMode';
const TunerNoteNamingModePreferenceKey: string = 'tunerNoteNamingMode';
const TunerMicrophoneGainPreferenceKey: string = 'tunerMicrophoneGain';
const TunerReferenceToneEnabledPreferenceKey: string = 'tunerReferenceToneEnabled';
const TunerReferenceNoteMidiPreferenceKey: string = 'tunerReferenceNoteMidi';
const TunerReferenceToneSampleRateHz: number = 48000;
const TunerReferenceToneMaxAmplitude: number = 32767;
const TunerReferenceToneAmplitudeRatio: number = 0.16;
const TunerReferenceToneMinHz: number = 20;
const TunerReferenceToneMaxHz: number = 10000;
const TunerReferenceToneFadeFactor: number = 0.0024;

export type TunerNoteDisplayMode = 'standard' | 'sharp' | 'flat';
export type TunerNoteNamingMode = 'pitch' | 'solfege';

const TunerValidDisplayModes: TunerNoteDisplayMode[] = ['standard', 'sharp', 'flat'];
const TunerValidNamingModes: TunerNoteNamingMode[] = ['pitch', 'solfege'];

@ObservedV2
export class PDFTunerController {
  private preferenceStore?: preferences.Preferences;
  private audioRenderer: audio.AudioRenderer | undefined = undefined;
  private audioRendererLoading: boolean = false;
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
  @Trace public microphoneGain: number = 0.65;
  @Trace public referenceToneEnabled: boolean = false;
  @Trace public referenceNoteMidi: number = 69;

  initialize(preferenceStore: preferences.Preferences): void {
    this.preferenceStore = preferenceStore;
    this.loadPreferences(preferenceStore);
    this.initializeAudio();
    this.syncReferenceTonePlaybackState();
  }

  cleanup(): void {
    this.stopReferenceTonePlayback();
    this.releaseAudio();
    this.preferenceStore = undefined;
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
    this.syncReferenceTonePlaybackState();
    this.savePreferences();
  }

  setPanelVisible(value: boolean): void {
    if (this.panelVisible === value) {
      return;
    }
    this.panelVisible = value;
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
      const sample: number = Math.sin(this.oscillatorPhase) * this.oscillatorAmplitude;
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
      this.microphoneGain = this.clampMicrophoneGain(
        preferenceStore.getSync(TunerMicrophoneGainPreferenceKey, 0.65) as number,
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

  private clampPcmSample(value: number): number {
    return Math.max(-TunerReferenceToneMaxAmplitude - 1, Math.min(TunerReferenceToneMaxAmplitude, Math.round(value)));
  }
}
