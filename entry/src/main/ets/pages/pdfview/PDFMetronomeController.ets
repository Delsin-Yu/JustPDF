import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { audio } from '@kit.AudioKit';
import { media } from '@kit.MediaKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const MetronomeDenominatorOptions: number[] = [2, 4, 8, 16];
const MetronomeBpmPresets: number[] = [40, 60, 80, 100, 120, 140, 160, 180, 200];
const MetronomeBpmPreferenceKey: string = 'metronomeBpm';
const MetronomeNumeratorPreferenceKey: string = 'metronomeNumerator';
const MetronomeDenominatorPreferenceKey: string = 'metronomeDenominator';
const MetronomeAccentRawFile: string = 'metronome_accent.wav';
const MetronomeWeakRawFile: string = 'metronome_beat.wav';
const MetronomeFloatingButtonBaseColor: string = 'rgba(35, 42, 53, 0.62)';
const MetronomeTimeSignaturePresets: Array<[number, number]> = [
  [2, 4],
  [3, 4],
  [4, 4],
  [5, 4],
  [5, 8],
  [6, 8],
  [7, 8],
  [9, 8],
  [12, 8]
];

interface PDFMetronomeControllerDependencies {
  getUIContext: () => UIContext;
  getHostContext: () => common.UIAbilityContext;
}

@ObservedV2
export class PDFMetronomeController {
  private readonly dependencies: PDFMetronomeControllerDependencies;
  private preferenceStore?: preferences.Preferences;
  private soundPool: media.SoundPool | undefined = undefined;
  private accentSoundId: number = -1;
  private weakSoundId: number = -1;
  private soundPoolLoading: boolean = false;
  private loadedSoundIds: Set<number> = new Set<number>();
  private metronomeTimerId: number | undefined = undefined;
  private metronomeNextTickAt: number = 0;
  private pulseTimerId: number | undefined = undefined;
  private audioRequestToken: number = 0;

  @Trace public showWindow: boolean = false;
  @Trace public bpm: number = 120;
  @Trace public numerator: number = 4;
  @Trace public denominator: number = 4;
  @Trace public currentBeat: number = -1;
  @Trace public isPlaying: boolean = false;
  @Trace public floatingButtonPulseScale: number = 1;
  @Trace public floatingButtonColor: string = MetronomeFloatingButtonBaseColor;
  @Trace public soundPoolReady: boolean = false;

  private readonly handleSoundPoolLoadComplete = (soundId: number): void => {
    this.loadedSoundIds.add(soundId);
    this.soundPoolReady = this.loadedSoundIds.has(this.accentSoundId) && this.loadedSoundIds.has(this.weakSoundId);
  };

  private readonly handleSoundPoolError = (error: BusinessError): void => {
    hilog.error(0, 'PDFMetronomeController', `节拍器音频错误: ${error.code} ${error.message}`);
  };

  constructor(dependencies: PDFMetronomeControllerDependencies) {
    this.dependencies = dependencies;
  }

  initialize(preferenceStore: preferences.Preferences): void {
    this.preferenceStore = preferenceStore;
    this.loadPreferences(preferenceStore);
    this.initializeAudio();
  }

  cleanup(): void {
    this.stopPlayback();
    this.releaseAudio();
  }

  openWindow(): void {
    this.showWindow = true;
  }

  closeWindow(): void {
    this.showWindow = false;
  }

  toggleWindow(): void {
    this.showWindow = !this.showWindow;
  }

  getBpmMenu(): MenuElement[] {
    return MetronomeBpmPresets.map((preset: number): MenuElement => ({
      value: `${preset}`,
      action: () => this.setBpm(preset)
    }));
  }

  getTimeSignatureMenu(): MenuElement[] {
    return MetronomeTimeSignaturePresets.map((preset: [number, number]): MenuElement => ({
      value: `${preset[0]}/${preset[1]}`,
      action: () => this.setTimeSignature(preset[0], preset[1])
    }));
  }

  setBpm(value: number): void {
    const nextValue = this.clampBpm(value);
    if (this.bpm === nextValue) {
      return;
    }
    this.bpm = nextValue;
    this.savePreferences();
    this.restartIfPlaying();
  }

  adjustBpm(delta: number): void {
    this.setBpm(this.bpm + delta);
  }

  setNumerator(value: number): void {
    const nextValue = this.clampNumerator(value);
    if (this.numerator === nextValue) {
      return;
    }
    this.numerator = nextValue;
    if (this.currentBeat >= this.numerator) {
      this.currentBeat = 0;
    }
    this.savePreferences();
    this.restartIfPlaying();
  }

  setDenominator(value: number): void {
    if (!MetronomeDenominatorOptions.includes(value) || this.denominator === value) {
      return;
    }
    this.denominator = value;
    this.savePreferences();
    this.restartIfPlaying();
  }

  setTimeSignature(numerator: number, denominator: number): void {
    this.numerator = this.clampNumerator(numerator);
    this.denominator = MetronomeDenominatorOptions.includes(denominator) ? denominator : 4;
    if (this.currentBeat >= this.numerator) {
      this.currentBeat = 0;
    }
    this.savePreferences();
    this.restartIfPlaying();
  }

  togglePlayback(): void {
    if (this.isPlaying) {
      this.stopPlayback();
      return;
    }
    this.startPlayback();
  }

  stopPlayback(resetBeat: boolean = true): void {
    this.isPlaying = false;
    this.metronomeNextTickAt = 0;
    if (this.metronomeTimerId !== undefined) {
      clearTimeout(this.metronomeTimerId);
      this.metronomeTimerId = undefined;
    }
    if (resetBeat) {
      this.currentBeat = -1;
    }
    this.stopFloatingButtonPulse();
  }

  private loadPreferences(preferenceStore: preferences.Preferences): void {
    try {
      this.bpm = this.clampBpm(preferenceStore.getSync(MetronomeBpmPreferenceKey, 120) as number);
      this.numerator = this.clampNumerator(preferenceStore.getSync(MetronomeNumeratorPreferenceKey, 4) as number);
      const savedDenominator = preferenceStore.getSync(MetronomeDenominatorPreferenceKey, 4) as number;
      this.denominator = MetronomeDenominatorOptions.includes(savedDenominator) ? savedDenominator : 4;
    } catch (error) {
      hilog.error(0, 'PDFMetronomeController', `加载节拍器偏好出错: ${error}.`);
    }
  }

  private savePreferences(): void {
    if (!this.preferenceStore) {
      return;
    }
    try {
      this.preferenceStore.putSync(MetronomeBpmPreferenceKey, this.bpm);
      this.preferenceStore.putSync(MetronomeNumeratorPreferenceKey, this.numerator);
      this.preferenceStore.putSync(MetronomeDenominatorPreferenceKey, this.denominator);
      this.preferenceStore.flushSync();
    } catch (error) {
      hilog.error(0, 'PDFMetronomeController', `保存节拍器偏好出错: ${error}.`);
    }
  }

  private initializeAudio(): void {
    if (this.soundPoolLoading || this.soundPool) {
      return;
    }
    this.soundPoolLoading = true;
    const requestToken = ++this.audioRequestToken;
    this.createSoundPool(requestToken).finally(() => {
      if (this.audioRequestToken === requestToken) {
        this.soundPoolLoading = false;
      }
    });
  }

  private async createSoundPool(requestToken: number): Promise<void> {
    this.loadedSoundIds.clear();
    this.soundPoolReady = false;
    this.accentSoundId = -1;
    this.weakSoundId = -1;

    try {
      const audioRendererInfo: audio.AudioRendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_AUDIOBOOK,
        rendererFlags: 1
      };
      const soundPool = await media.createSoundPool(4, audioRendererInfo);
      soundPool.on('loadComplete', this.handleSoundPoolLoadComplete);
      soundPool.on('error', this.handleSoundPoolError);

      if (requestToken !== this.audioRequestToken) {
        this.releaseDetachedSoundPool(soundPool);
        return;
      }

      const context = this.dependencies.getHostContext();
      const accentDescriptor = await context.resourceManager.getRawFd(MetronomeAccentRawFile);
      const weakDescriptor = await context.resourceManager.getRawFd(MetronomeWeakRawFile);

      if (requestToken !== this.audioRequestToken) {
        this.releaseDetachedSoundPool(soundPool);
        return;
      }

      this.soundPool = soundPool;
      this.accentSoundId = await soundPool.load(accentDescriptor.fd, accentDescriptor.offset, accentDescriptor.length);
      if (requestToken !== this.audioRequestToken || this.soundPool !== soundPool) {
        this.releaseDetachedSoundPool(soundPool);
        return;
      }
      this.weakSoundId = await soundPool.load(weakDescriptor.fd, weakDescriptor.offset, weakDescriptor.length);
      if (requestToken !== this.audioRequestToken || this.soundPool !== soundPool) {
        this.releaseDetachedSoundPool(soundPool);
        return;
      }
      hilog.info(0, 'PDFMetronomeController', '节拍器音频资源已开始加载');
    } catch (error) {
      hilog.error(0, 'PDFMetronomeController', `初始化节拍器音频失败: ${JSON.stringify(error)}`);
      if (requestToken === this.audioRequestToken) {
        this.resetAudioState();
      }
    }
  }

  private releaseAudio(): void {
    this.audioRequestToken += 1;
    this.soundPoolLoading = false;
    const soundPool = this.soundPool;
    this.resetAudioState();
    if (!soundPool) {
      return;
    }
    this.releaseDetachedSoundPool(soundPool);
  }

  private resetAudioState(): void {
    this.soundPool = undefined;
    this.soundPoolReady = false;
    this.loadedSoundIds.clear();
    this.accentSoundId = -1;
    this.weakSoundId = -1;
  }

  private releaseDetachedSoundPool(soundPool: media.SoundPool): void {
    soundPool.off('loadComplete');
    soundPool.off('error');
    soundPool.release().catch((error: BusinessError) => {
      hilog.error(0, 'PDFMetronomeController', `释放节拍器音频失败: ${error.code} ${error.message}`);
    });
  }

  private playBeatSound(beat: number): void {
    if (!this.soundPool || !this.soundPoolReady) {
      return;
    }
    const soundId = beat === 0 ? this.accentSoundId : this.weakSoundId;
    if (soundId < 0) {
      return;
    }
    const playParameters: media.PlayParameters = {
      loop: 0,
      rate: audio.AudioRendererRate.RENDER_RATE_NORMAL,
      leftVolume: 1,
      rightVolume: 1,
      priority: 1
    };
    this.soundPool.play(soundId, playParameters).catch((error: BusinessError) => {
      hilog.error(0, 'PDFMetronomeController', `播放节拍器音频失败: ${error.code} ${error.message}`);
    });
  }

  private clampBpm(value: number): number {
    return Math.max(1, Math.min(600, Math.round(value)));
  }

  private clampNumerator(value: number): number {
    return Math.max(1, Math.min(16, Math.round(value)));
  }

  private getIntervalMs(): number {
    return Math.round((60000 / this.bpm) * (4 / this.denominator));
  }

  private startPlayback(): void {
    this.stopPlayback(false);
    this.isPlaying = true;
    this.currentBeat = -1;
    this.advanceBeat();
    const intervalMs = this.getIntervalMs();
    this.metronomeNextTickAt = Date.now() + intervalMs;
    this.scheduleTick(intervalMs);
    this.startFloatingButtonPulse();
  }

  private advanceBeat(): void {
    if (this.currentBeat < 0 || this.currentBeat >= this.numerator - 1) {
      this.currentBeat = 0;
    } else {
      this.currentBeat += 1;
    }
    this.playBeatSound(this.currentBeat);
  }

  private scheduleTick(delayMs: number): void {
    if (this.metronomeTimerId !== undefined) {
      clearTimeout(this.metronomeTimerId);
      this.metronomeTimerId = undefined;
    }
    this.metronomeTimerId = setTimeout(() => {
      if (!this.isPlaying) {
        return;
      }
      this.advanceBeat();
      const intervalMs = this.getIntervalMs();
      const now = Date.now();
      this.metronomeNextTickAt += intervalMs;
      const nextDelay = Math.max(12, this.metronomeNextTickAt - now);
      this.scheduleTick(nextDelay);
    }, Math.max(12, delayMs));
  }

  private restartIfPlaying(): void {
    if (!this.isPlaying) {
      return;
    }
    this.startPlayback();
  }

  private startFloatingButtonPulse(): void {
    let uiContext: UIContext;
    try {
      uiContext = this.dependencies.getUIContext();
    } catch (_error) {
      return;
    }

    const pulse = () => {
      if (!this.isPlaying) {
        return;
      }
      this.floatingButtonPulseScale = 1.12;
      this.floatingButtonColor = this.currentBeat === 0 ? 'rgba(255, 159, 67, 0.78)' : 'rgba(77, 166, 255, 0.76)';

      uiContext.keyframeAnimateTo({ iterations: 1 }, [
        {
          duration: 500,
          curve: Curve.EaseOut,
          event: () => {
            this.floatingButtonPulseScale = 1;
            this.floatingButtonColor = MetronomeFloatingButtonBaseColor;
          }
        }
      ]);
    };

    pulse();
    this.pulseTimerId = setInterval(() => {
      if (!this.isPlaying) {
        if (this.pulseTimerId !== undefined) {
          clearInterval(this.pulseTimerId);
          this.pulseTimerId = undefined;
        }
        return;
      }
      pulse();
    }, this.getIntervalMs());
  }

  private stopFloatingButtonPulse(): void {
    if (this.pulseTimerId !== undefined) {
      clearInterval(this.pulseTimerId);
      this.pulseTimerId = undefined;
    }
    this.floatingButtonPulseScale = 1;
    this.floatingButtonColor = MetronomeFloatingButtonBaseColor;
  }
}