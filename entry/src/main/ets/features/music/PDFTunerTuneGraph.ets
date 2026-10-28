import { hilog } from '@kit.PerformanceAnalysisKit';
import { PDFTunerController, TunerTuneGraphCapacity } from './PDFTunerController';

const TunerTuneGraphZeroLineColor: string = 'rgba(255, 255, 255, 0.18)';
const TunerTuneGraphInTuneColor: string = '#42D392';
const TunerTuneGraphNearColor: string = '#FFB347';
const TunerTuneGraphFarColor: string = '#FF7A7A';
const TunerTuneGraphLineWidth: number = 2;
const TunerTuneGraphCentsMin: number = -50;
const TunerTuneGraphCentsMax: number = 50;

@ComponentV2
export struct PDFTunerTuneGraph {
  @Param controller: PDFTunerController | undefined = undefined;
  private readonly canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);
  private readonly scratchCents: number[] = [];
  private canvasReady: boolean = false;
  private epochListener: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.canvasReady = false;
    this.canvasContext = new CanvasRenderingContext2D(this.canvasSettings);
    this.ensureScratchCents();
    this.attachEpochListener();
  }

  aboutToDisappear(): void {
    this.detachEpochListener();
    this.canvasReady = false;
  }

  private ensureScratchCents(): void {
    if (this.scratchCents.length === TunerTuneGraphCapacity) {
      return;
    }
    this.scratchCents.length = 0;
    for (let index = 0; index < TunerTuneGraphCapacity; index++) {
      this.scratchCents.push(Number.NaN);
    }
  }

  private attachEpochListener(): void {
    const host: PDFTunerController | undefined = this.controller;
    if (host === undefined || this.epochListener !== undefined) {
      return;
    }
    this.epochListener = (): void => {
      this.redraw();
    };
    host.addTuneGraphRedrawListener(this.epochListener);
  }

  private detachEpochListener(): void {
    const host: PDFTunerController | undefined = this.controller;
    const listener: (() => void) | undefined = this.epochListener;
    if (host === undefined || listener === undefined) {
      this.epochListener = undefined;
      return;
    }
    host.removeTuneGraphRedrawListener(listener);
    this.epochListener = undefined;
  }

  private getLineColor(latestCents: number): string {
    const absCents: number = Math.abs(latestCents);
    if (absCents <= 4) {
      return TunerTuneGraphInTuneColor;
    }
    if (absCents <= 12) {
      return TunerTuneGraphNearColor;
    }
    return TunerTuneGraphFarColor;
  }

  private mapCentsToY(cents: number, height: number): number {
    const clamped: number = Math.max(TunerTuneGraphCentsMin, Math.min(TunerTuneGraphCentsMax, cents));
    const t: number = (TunerTuneGraphCentsMax - clamped) / (TunerTuneGraphCentsMax - TunerTuneGraphCentsMin);
    return t * height;
  }

  private applyHorizontalAlphaMask(width: number, height: number): void {
    const mask: CanvasGradient = this.canvasContext.createLinearGradient(0, 0, width, 0);
    mask.addColorStop(0, 'rgba(255, 255, 255, 1)');
    mask.addColorStop(0.25, 'rgba(255, 255, 255, 0.4)');
    mask.addColorStop(0.5, 'rgba(255, 255, 255, 0.2)');
    mask.addColorStop(0.75, 'rgba(255, 255, 255, 0.4)');
    mask.addColorStop(1, 'rgba(255, 255, 255, 1)');
    this.canvasContext.globalCompositeOperation = 'destination-in';
    this.canvasContext.fillStyle = mask;
    this.canvasContext.fillRect(0, 0, width, height);
    this.canvasContext.globalCompositeOperation = 'source-over';
  }

  private redraw(): void {
    if (!this.canvasReady) {
      return;
    }
    const width: number = this.canvasContext.width;
    const height: number = this.canvasContext.height;
    if (width <= 0 || height <= 0) {
      return;
    }

    this.ensureScratchCents();
    const host: PDFTunerController | undefined = this.controller;
    const count: number = host === undefined ? 0 : host.copyTuneGraphCents(this.scratchCents);
    try {
      this.canvasContext.clearRect(0, 0, width, height);

      const zeroY: number = this.mapCentsToY(0, height);
      this.canvasContext.beginPath();
      this.canvasContext.strokeStyle = TunerTuneGraphZeroLineColor;
      this.canvasContext.lineWidth = 1;
      this.canvasContext.setLineDash([4, 6]);
      this.canvasContext.moveTo(0, zeroY);
      this.canvasContext.lineTo(width, zeroY);
      this.canvasContext.stroke();
      this.canvasContext.setLineDash([]);

      if (count > 0 && host !== undefined) {
        let latestCents: number = 0;
        let hasLatest: boolean = false;
        for (let index = count - 1; index >= 0; index--) {
          const sample: number = this.scratchCents[index];
          if (!Number.isNaN(sample)) {
            latestCents = sample;
            hasLatest = true;
            break;
          }
        }
        if (hasLatest) {
          this.canvasContext.beginPath();
          this.canvasContext.strokeStyle = this.getLineColor(latestCents);
          this.canvasContext.lineWidth = TunerTuneGraphLineWidth;
          this.canvasContext.lineJoin = 'round';
          this.canvasContext.lineCap = 'round';
          let drawing: boolean = false;
          const lastIndex: number = Math.max(1, count - 1);
          for (let index = 0; index < count; index++) {
            const sample: number = this.scratchCents[index];
            if (Number.isNaN(sample)) {
              if (drawing) {
                this.canvasContext.stroke();
                this.canvasContext.beginPath();
                drawing = false;
              }
              continue;
            }
            const x: number = (index / lastIndex) * width;
            const y: number = this.mapCentsToY(sample, height);
            if (drawing) {
              this.canvasContext.lineTo(x, y);
            } else {
              this.canvasContext.moveTo(x, y);
              drawing = true;
            }
          }
          if (drawing) {
            this.canvasContext.stroke();
          }
        }
      }
      this.applyHorizontalAlphaMask(width, height);
    } catch (error) {
      this.canvasContext.globalCompositeOperation = 'source-over';
      hilog.error(0, 'PDFTuner', `tuneGraph redraw failed: ${String(error)}`);
    }
  }

  build() {
    Canvas(this.canvasContext)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
      .onReady(() => {
        this.canvasReady = true;
        this.attachEpochListener();
        this.redraw();
      });
  }
}
