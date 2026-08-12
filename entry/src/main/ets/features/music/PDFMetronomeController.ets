import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { audio } from '@kit.AudioKit';
import { displaySync } from '@kit.ArkGraphics2D';
import { hilog } from '@kit.PerformanceAnalysisKit';

const MetronomeDenominatorOptions: number[] = [2, 4, 8, 16];
const MetronomeBpmPresets: number[] = [40, 60, 80, 100, 120, 140, 160, 180, 200, 300, 400, 500, 600];
const MetronomeBpmPreferenceKey: string = 'metronomeBpm';
const MetronomeNumeratorPreferenceKey: string = 'metronomeNumerator';
const MetronomeDenominatorPreferenceKey: string = 'metronomeDenominator';
const MetronomeFloatingButtonBaseColor: string = 'rgba(35, 42, 53, 0.62)';
const MetronomeNsPerSecond: number = 1000000000;
const MetronomeNsPerMs: number = 1000000;
const MetronomeDisplaySyncFrameRate: number = 120;
const MetronomeAudioTimestampRefreshNs: number = 200 * MetronomeNsPerMs;
const MetronomeAudioSampleRateHz: number = 48000;
const MetronomeAudioBytesPerFrame: number = 2;
const MetronomeAudioMaxAmplitude: number = 32767;
const MetronomeAudioNoiseFloorAmplitude: number = 2;
const MetronomeAudioNoiseFloorSeed: number = 0x6d2b79f5;
const MetronomeBeatPhaseEpsilonFrames: number = 0.5;
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
  onVisualStateChanged?: () => void;
}

interface MetronomeClickInstance {
  startFrame: number;
  waveform: Int16Array;
}

@Observed
export class PDFMetronomeControllerState {
  public controller: PDFMetronomeController;

  constructor(controller: PDFMetronomeController) {
    this.controller = controller;
  }
}

@ObservedV2
export class PDFMetronomeController {
  private readonly dependencies: PDFMetronomeControllerDependencies;
  private readonly accentWaveform: Int16Array;
  private readonly weakWaveform: Int16Array;
  private preferenceStore?: preferences.Preferences;
  private audioRenderer: audio.AudioRenderer | undefined = undefined;
  private audioRendererLoading: boolean = false;
  private metronomeDisplaySync: displaySync.DisplaySync | undefined = undefined;
  private metronomeDisplaySyncStarted: boolean = false;
  private pendingRendererStop: Promise<void> | undefined = undefined;
  private audioRequestToken: number = 0;
  private audioPlaybackSessionToken: number = 0;
  private playbackStartRequested: boolean = false;
  private beatIntervalFrames: number = 0;
  private rendererBufferFrames: number = 0;
  private streamCursorFrame: number = 0;
  private nextBeatFrame: number = 0;
  private nextBeatIndex: number = 0;
  private activeClicks: MetronomeClickInstance[] = [];
  private audioTimestampAnchor: audio.AudioTimestampInfo | undefined = undefined;
  private audioTimestampAnchorUpdatedAtNs: number = 0;
  private audioRenderedFrameAtAnchor: number = 0;
  private lastVisualizedBeatOrdinal: number = -1;
  private noiseFloorState: number = MetronomeAudioNoiseFloorSeed;
  private floatingButtonPulseToken: number = 0;
  private floatingButtonPulseResetTimeoutId: number | undefined = undefined;

  private notifyVisualStateChanged(): void {
    this.dependencies.onVisualStateChanged?.();
  }

  @Trace public showWindow: boolean = false;
  @Trace public bpm: number = 120;
  @Trace public numerator: number = 4;
  @Trace public denominator: number = 4;
  @Trace public currentBeat: number = -1;
  @Trace public isPlaying: boolean = false;
  @Trace public floatingButtonPulseScale: number = 1;
  @Trace public floatingButtonColor: string = MetronomeFloatingButtonBaseColor;
  @Trace public floatingButtonTransitionDurationMs: number = 0;
  @Trace public audioReady: boolean = false;

  private readonly handleAudioWriteData: audio.AudioRendererWriteDataCallback = (buffer: ArrayBuffer): audio.AudioDataCallbackResult => {
    const output = new Int16Array(buffer);
    if (this.isPlaying && this.beatIntervalFrames > 0) {
      this.fillOutputWithNoiseFloor(output);
    } else {
      output.fill(0);
    }

    if (!this.isPlaying || this.beatIntervalFrames <= 0) {
      this.streamCursorFrame += output.length;
      return audio.AudioDataCallbackResult.VALID;
    }

    const chunkStartFrame = this.streamCursorFrame;
    const chunkFrameCount = output.length;
    const chunkEndFrame = chunkStartFrame + chunkFrameCount;

    this.pruneFinishedClicks(chunkStartFrame);
    this.enqueueClicksWithinRange(chunkEndFrame);
    this.mixActiveClicksIntoChunk(output, chunkStartFrame, chunkFrameCount);

    this.streamCursorFrame = chunkEndFrame;
    return audio.AudioDataCallbackResult.VALID;
  };

  private readonly handleMetronomeFrame = (frameInfo: displaySync.IntervalInfo): void => {
    if (!this.isPlaying) {
      return;
    }

    const presentationTimestamp = Math.max(frameInfo.timestamp, frameInfo.targetTimestamp);
    const renderedFrame = this.getEstimatedRenderedFrame(presentationTimestamp);
    if (renderedFrame === undefined || this.beatIntervalFrames <= 0) {
      return;
    }

    const beatOrdinal = Math.floor((renderedFrame + MetronomeBeatPhaseEpsilonFrames) / this.beatIntervalFrames);
    if (beatOrdinal < 0 || beatOrdinal === this.lastVisualizedBeatOrdinal) {
      return;
    }

    this.lastVisualizedBeatOrdinal = beatOrdinal;
    this.currentBeat = beatOrdinal % this.numerator;
    this.startFloatingButtonPulse();
  };

  constructor(dependencies: PDFMetronomeControllerDependencies) {
    this.dependencies = dependencies;
    this.accentWaveform = this.createClickWaveform(1760, 16, 0.95, 7.2);
    this.weakWaveform = this.createClickWaveform(1320, 11, 0.62, 8.8);
  }

  initialize(preferenceStore: preferences.Preferences): void {
    this.preferenceStore = preferenceStore;
    this.loadPreferences(preferenceStore);
    this.initializeAudio();
  }

  cleanup(): void {
    this.stopPlayback();
    this.releaseAudio();
    this.releaseMetronomeLoop();
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

  pauseForInteraction(): void {
    if (!this.isPlaying) {
      return;
    }
    this.playbackStartRequested = false;
    this.isPlaying = false;
    this.audioPlaybackSessionToken += 1;
    this.clearAudioClockState();
    this.stopMetronomeLoop();
    this.currentBeat = -1;
    this.stopFloatingButtonPulse();

    const stopPromise = this.stopAudioRendererPlayback('pauseForInteraction');
    this.pendingRendererStop = stopPromise;
    void stopPromise.finally(() => {
      if (this.pendingRendererStop === stopPromise) {
        this.pendingRendererStop = undefined;
      }
    });
  }

  resumeAfterInteraction(): void {
    if (this.isPlaying) {
      return;
    }
    if (this.bpm <= 0) {
      this.playbackStartRequested = false;
      this.isPlaying = false;
      this.currentBeat = -1;
      return;
    }
    this.playbackStartRequested = true;
    this.isPlaying = true;
    this.currentBeat = -1;
    this.prepareAudioSchedule();
    this.startMetronomeLoop();
    this.startAudioRendererPlayback(++this.audioPlaybackSessionToken);
  }

  stopPlayback(resetBeat: boolean = true): void {
    this.playbackStartRequested = false;
    this.isPlaying = false;
    this.audioPlaybackSessionToken += 1;
    this.clearAudioClockState();
    this.stopMetronomeLoop();
    const stopPromise = this.stopAudioRendererPlayback('stopPlayback');
    this.pendingRendererStop = stopPromise;
    void stopPromise.finally(() => {
      if (this.pendingRendererStop === stopPromise) {
        this.pendingRendererStop = undefined;
      }
    });
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
    if (this.audioRendererLoading || this.audioRenderer) {
      return;
    }

    this.audioRendererLoading = true;
    const requestToken = ++this.audioRequestToken;
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
          usage: audio.StreamUsage.STREAM_USAGE_AUDIOBOOK,
          rendererFlags: 0
        }
      };

      const audioRenderer = await audio.createAudioRenderer(audioRendererOptions);
      audioRenderer.on('writeData', this.handleAudioWriteData);
      this.rendererBufferFrames = this.getRendererBufferFrames(audioRenderer);

      if (requestToken !== this.audioRequestToken) {
        this.releaseDetachedAudioRenderer(audioRenderer);
        return;
      }

      this.audioRenderer = audioRenderer;
      this.audioReady = true;

      if (this.playbackStartRequested && this.isPlaying) {
        this.startAudioRendererPlayback(this.audioPlaybackSessionToken);
      }
    } catch (error) {
      hilog.error(0, 'PDFMetronomeController', `初始化节拍器AudioRenderer失败: ${JSON.stringify(error)}`);
      if (requestToken === this.audioRequestToken) {
        this.resetAudioState();
      }
    }
  }

  private releaseAudio(): void {
    this.audioRequestToken += 1;
    this.audioRendererLoading = false;
    const audioRenderer = this.audioRenderer;
    this.resetAudioState();
    if (!audioRenderer) {
      return;
    }
    this.releaseDetachedAudioRenderer(audioRenderer);
  }

  private resetAudioState(): void {
    this.audioRenderer = undefined;
    this.audioReady = false;
    this.clearAudioClockState();
  }

  private releaseDetachedAudioRenderer(audioRenderer: audio.AudioRenderer): void {
    try {
      audioRenderer.off('writeData', this.handleAudioWriteData);
    } catch (error) {
      hilog.error(0, 'PDFMetronomeController', `解绑节拍器AudioRenderer回调失败: ${JSON.stringify(error)}`);
    }

    const releaseRenderer = async (): Promise<void> => {
      try {
        if (audioRenderer.state === audio.AudioState.STATE_RUNNING || audioRenderer.state === audio.AudioState.STATE_PAUSED) {
          await audioRenderer.stop();
        }
      } catch (error) {
        hilog.error(0, 'PDFMetronomeController', `停止节拍器AudioRenderer失败: ${JSON.stringify(error)}`);
      }

      try {
        if (audioRenderer.state === audio.AudioState.STATE_STOPPED) {
          await audioRenderer.flush();
        }
      } catch (error) {
        hilog.error(0, 'PDFMetronomeController', `清空节拍器音频缓冲失败: ${JSON.stringify(error)}`);
      }

      try {
        if (audioRenderer.state !== audio.AudioState.STATE_RELEASED) {
          await audioRenderer.release();
        }
      } catch (error) {
        hilog.error(0, 'PDFMetronomeController', `释放节拍器AudioRenderer失败: ${JSON.stringify(error)}`);
      }
    };

    void releaseRenderer();
  }

  private stopAudioRendererPlayback(reason: string): Promise<void> {
    if (!this.audioRenderer) {
      return Promise.resolve();
    }

    const audioRenderer = this.audioRenderer;
    return (async (): Promise<void> => {
      try {
        if (audioRenderer.state === audio.AudioState.STATE_RUNNING || audioRenderer.state === audio.AudioState.STATE_PAUSED) {
          await audioRenderer.stop();
        }
      } catch (error) {
        hilog.error(0, 'PDFMetronomeController', `停止节拍器播放失败: ${JSON.stringify(error)}`);
      }

      try {
        if (audioRenderer.state === audio.AudioState.STATE_STOPPED) {
          await audioRenderer.flush();
        }
      } catch (error) {
        hilog.error(0, 'PDFMetronomeController', `清空节拍器播放缓冲失败: ${JSON.stringify(error)}`);
      }
    })();
  }

  private clampBpm(value: number): number {
    return Math.max(0, Math.min(600, Math.round(value)));
  }

  private clampNumerator(value: number): number {
    return Math.max(1, Math.min(16, Math.round(value)));
  }

  private getIntervalFrames(): number {
    if (this.bpm <= 0) {
      return 0;
    }
    return (MetronomeAudioSampleRateHz * 60 / this.bpm) * (4 / this.denominator);
  }

  private startPlayback(): void {
    this.stopPlayback(false);

    if (this.bpm <= 0) {
      this.currentBeat = -1;
      return;
    }

    this.playbackStartRequested = true;
    this.isPlaying = true;
    this.currentBeat = -1;
    this.prepareAudioSchedule();
    this.startMetronomeLoop();
    this.startAudioRendererPlayback(++this.audioPlaybackSessionToken);
  }

  private prepareAudioSchedule(): void {
    this.clearAudioClockState();
    this.beatIntervalFrames = this.getIntervalFrames();
    this.streamCursorFrame = 0;
    this.nextBeatFrame = 0;
    this.nextBeatIndex = 0;
  }

  private clearAudioClockState(): void {
    this.beatIntervalFrames = 0;
    this.streamCursorFrame = 0;
    this.nextBeatFrame = 0;
    this.nextBeatIndex = 0;
    this.activeClicks = [];
    this.audioTimestampAnchor = undefined;
    this.audioTimestampAnchorUpdatedAtNs = 0;
    this.audioRenderedFrameAtAnchor = 0;
    this.lastVisualizedBeatOrdinal = -1;
  }

  private getRendererBufferFrames(audioRenderer: audio.AudioRenderer): number {
    try {
      return Math.max(1, Math.floor(audioRenderer.getBufferSizeSync() / MetronomeAudioBytesPerFrame));
    } catch (error) {
      hilog.error(0, 'PDFMetronomeController', `获取节拍器缓冲区大小失败: ${JSON.stringify(error)}`);
      return 0;
    }
  }

  private startAudioRendererPlayback(playbackToken: number): void {
    if (playbackToken !== this.audioPlaybackSessionToken || !this.playbackStartRequested || !this.isPlaying) {
      return;
    }

    if (!this.audioRenderer) {
      this.initializeAudio();
      return;
    }

    const audioRenderer = this.audioRenderer;
    const startRenderer = async (): Promise<void> => {
      try {
        const pendingStop = this.pendingRendererStop;
        if (pendingStop) {
          await pendingStop;
        }

        if (playbackToken !== this.audioPlaybackSessionToken || !this.playbackStartRequested || !this.isPlaying) {
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
        if (playbackToken === this.audioPlaybackSessionToken && this.isPlaying) {
          hilog.error(0, 'PDFMetronomeController', `启动节拍器播放失败: ${JSON.stringify(error)}`);
          this.stopPlayback();
        }
      }
    };

    void startRenderer();
  }

  private restartIfPlaying(): void {
    if (!this.isPlaying) {
      return;
    }
    this.startPlayback();
  }

  private createClickWaveform(frequencyHz: number, durationMs: number, amplitude: number,
    decayStrength: number): Int16Array {
    const frameCount = Math.max(1, Math.round(MetronomeAudioSampleRateHz * durationMs / 1000));
    const attackFrames = Math.max(1, Math.round(MetronomeAudioSampleRateHz * 0.0015));
    const waveform = new Int16Array(frameCount);

    for (let frameIndex = 0; frameIndex < frameCount; frameIndex++) {
      const phase = 2 * Math.PI * frequencyHz * frameIndex / MetronomeAudioSampleRateHz;
      const attackGain = frameIndex < attackFrames ? frameIndex / attackFrames : 1;
      const decayGain = Math.exp(-decayStrength * frameIndex / frameCount);
      const sample = Math.sin(phase) * amplitude * attackGain * decayGain;
      waveform[frameIndex] = Math.round(sample * MetronomeAudioMaxAmplitude);
    }

    return waveform;
  }

  private fillOutputWithNoiseFloor(output: Int16Array): void {
    for (let sampleIndex = 0; sampleIndex < output.length; sampleIndex++) {
      this.noiseFloorState = (Math.imul(this.noiseFloorState, 1664525) + 1013904223) >>> 0;
      output[sampleIndex] = (this.noiseFloorState & 1) === 0
        ? -MetronomeAudioNoiseFloorAmplitude
        : MetronomeAudioNoiseFloorAmplitude;
    }
  }

  private pruneFinishedClicks(chunkStartFrame: number): void {
    this.activeClicks = this.activeClicks.filter((click: MetronomeClickInstance): boolean => {
      return click.startFrame + click.waveform.length > chunkStartFrame;
    });
  }

  private enqueueClicksWithinRange(chunkEndFrame: number): void {
    const scheduleWindowEndFrame = chunkEndFrame + this.rendererBufferFrames;
    while (this.nextBeatFrame < scheduleWindowEndFrame) {
      this.activeClicks.push({
        startFrame: Math.max(0, Math.round(this.nextBeatFrame)),
        waveform: this.nextBeatIndex === 0 ? this.accentWaveform : this.weakWaveform
      });

      this.nextBeatFrame += this.beatIntervalFrames;
      if (this.nextBeatIndex >= this.numerator - 1) {
        this.nextBeatIndex = 0;
      } else {
        this.nextBeatIndex += 1;
      }
    }
  }

  private mixActiveClicksIntoChunk(output: Int16Array, chunkStartFrame: number, chunkFrameCount: number): void {
    for (const click of this.activeClicks) {
      const clickOffsetInChunk = click.startFrame - chunkStartFrame;
      const sourceStartIndex = Math.max(0, -clickOffsetInChunk);
      const targetStartIndex = Math.max(0, clickOffsetInChunk);
      const sampleCount = Math.min(click.waveform.length - sourceStartIndex, chunkFrameCount - targetStartIndex);

      if (sampleCount <= 0) {
        continue;
      }

      for (let sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
        const outputIndex = targetStartIndex + sampleIndex;
        const mixedSample = output[outputIndex] + click.waveform[sourceStartIndex + sampleIndex];
        output[outputIndex] = this.clampPcmSample(mixedSample);
      }
    }
  }

  private clampPcmSample(value: number): number {
    return Math.max(-MetronomeAudioMaxAmplitude - 1, Math.min(MetronomeAudioMaxAmplitude, Math.round(value)));
  }

  private getEstimatedRenderedFrame(nowNs: number): number | undefined {
    const audioRenderer = this.audioRenderer;
    if (!audioRenderer || audioRenderer.state !== audio.AudioState.STATE_RUNNING || this.beatIntervalFrames <= 0) {
      return undefined;
    }

    if (!this.audioTimestampAnchor || nowNs - this.audioTimestampAnchorUpdatedAtNs >= MetronomeAudioTimestampRefreshNs) {
      try {
        const timestampInfo = audioRenderer.getAudioTimestampInfoSync();
        if (timestampInfo.timestamp > 0 && timestampInfo.framePos > 0) {
          this.updateAudioTimestampAnchor(timestampInfo, nowNs);
        }
      } catch (error) {
        hilog.error(0, 'PDFMetronomeController', `获取节拍器音频时间戳失败: ${JSON.stringify(error)}`);
      }
    }

    if (!this.audioTimestampAnchor || this.audioTimestampAnchor.timestamp <= 0) {
      return undefined;
    }

    const elapsedFrames = Math.max(0,
      (nowNs - this.audioTimestampAnchor.timestamp) * MetronomeAudioSampleRateHz / MetronomeNsPerSecond);
    return Math.max(0, this.audioRenderedFrameAtAnchor + elapsedFrames);
  }

  private updateAudioTimestampAnchor(timestampInfo: audio.AudioTimestampInfo, nowNs: number): void {
    if (!this.audioTimestampAnchor) {
      this.audioTimestampAnchor = timestampInfo;
      this.audioTimestampAnchorUpdatedAtNs = nowNs;
      this.audioRenderedFrameAtAnchor = 0;
      return;
    }

    const frameDelta = timestampInfo.framePos - this.audioTimestampAnchor.framePos;
    if (frameDelta >= 0) {
      this.audioRenderedFrameAtAnchor += frameDelta;
    } else {
      const timestampDeltaFrames = Math.max(0,
        (timestampInfo.timestamp - this.audioTimestampAnchor.timestamp) * MetronomeAudioSampleRateHz / MetronomeNsPerSecond);
      this.audioRenderedFrameAtAnchor += timestampDeltaFrames;
    }

    this.audioTimestampAnchor = timestampInfo;
    this.audioTimestampAnchorUpdatedAtNs = nowNs;
  }

  private ensureMetronomeLoop(): displaySync.DisplaySync | undefined {
    if (this.metronomeDisplaySync) {
      return this.metronomeDisplaySync;
    }

    const nextDisplaySync = displaySync.create();
    nextDisplaySync.setExpectedFrameRateRange({
      expected: MetronomeDisplaySyncFrameRate,
      min: 0,
      max: MetronomeDisplaySyncFrameRate
    });
    nextDisplaySync.on('frame', this.handleMetronomeFrame);
    this.metronomeDisplaySync = nextDisplaySync;
    return nextDisplaySync;
  }

  private startMetronomeLoop(): void {
    const metronomeLoop = this.ensureMetronomeLoop();
    if (!metronomeLoop || this.metronomeDisplaySyncStarted) {
      return;
    }

    let uiContext: UIContext;
    try {
      uiContext = this.dependencies.getUIContext();
    } catch (error) {
      hilog.error(0, 'PDFMetronomeController', `节拍器帧循环启动失败: ${JSON.stringify(error)}`);
      return;
    }

    uiContext.runScopedTask(() => {
      metronomeLoop.start();
      this.metronomeDisplaySyncStarted = true;
    });
  }

  private stopMetronomeLoop(): void {
    if (!this.metronomeDisplaySync || !this.metronomeDisplaySyncStarted) {
      return;
    }
    this.metronomeDisplaySync.stop();
    this.metronomeDisplaySyncStarted = false;
  }

  private releaseMetronomeLoop(): void {
    if (!this.metronomeDisplaySync) {
      return;
    }
    this.stopMetronomeLoop();
    this.metronomeDisplaySync.off('frame', this.handleMetronomeFrame);
    this.metronomeDisplaySync = undefined;
  }

  private getFloatingButtonPulseDurationMs(): number {
    if (this.bpm <= 0) {
      return 180;
    }

    const beatDurationMs = 60000 / this.bpm * (4 / this.denominator);
    return Math.max(60, Math.round(beatDurationMs));
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
      const pulseToken = ++this.floatingButtonPulseToken;
      const pulseDurationMs = this.getFloatingButtonPulseDurationMs();
      if (this.floatingButtonPulseResetTimeoutId !== undefined) {
        clearTimeout(this.floatingButtonPulseResetTimeoutId);
        this.floatingButtonPulseResetTimeoutId = undefined;
      }
      this.floatingButtonTransitionDurationMs = 0;
      this.floatingButtonPulseScale = 1.12;
      this.floatingButtonColor = this.currentBeat === 0 ? 'rgba(255, 159, 67, 0.78)' : 'rgba(77, 166, 255, 0.76)';
      this.notifyVisualStateChanged();

      this.floatingButtonPulseResetTimeoutId = setTimeout(() => {
        this.floatingButtonPulseResetTimeoutId = undefined;
        if (pulseToken !== this.floatingButtonPulseToken) {
          return;
        }

        if (!this.isPlaying) {
          return;
        }

        this.floatingButtonTransitionDurationMs = pulseDurationMs;
        this.floatingButtonColor = MetronomeFloatingButtonBaseColor;
        this.floatingButtonPulseScale = 1;
        this.notifyVisualStateChanged();
      }, 16);
    };

    pulse();
  }

  private stopFloatingButtonPulse(): void {
    this.floatingButtonPulseToken += 1;
    if (this.floatingButtonPulseResetTimeoutId !== undefined) {
      clearTimeout(this.floatingButtonPulseResetTimeoutId);
      this.floatingButtonPulseResetTimeoutId = undefined;
    }
    this.floatingButtonTransitionDurationMs = 0;
    this.floatingButtonPulseScale = 1;
    this.floatingButtonColor = MetronomeFloatingButtonBaseColor;
    this.notifyVisualStateChanged();
  }
}