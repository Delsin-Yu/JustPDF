const RingDiameter: number = 80;
const BarWidth: number = 6;
const IconSize: number = 22;
const IconOffsetFromCenter: number = RingDiameter / 2 + 8;
const ProgressColor: string = 'rgba(66, 133, 244, 1.0)';
const TrackColor: string = 'rgba(255, 255, 255, 0.25)';
const FillColor: string = 'rgba(0, 0, 0, 0.15)';
const TotalSize: number = RingDiameter + IconSize + 16;

@ComponentV2
export struct AnnotateLongPressIndicator {
  @Param progress: number = 0;
  @Param posX: number = 0;
  @Param posY: number = 0;
  @Param visible: boolean = false;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  build() {
    Stack() {
      Canvas(this.ctx)
        .width(TotalSize)
        .height(TotalSize)
        .onReady(() => this.drawProgress())

      SymbolGlyph($r('sys.symbol.pencil_waveform'))
        .fontSize(IconSize)
        .fontColor([Color.White])
        .position({
          x: TotalSize / 2 + IconOffsetFromCenter * Math.cos(-Math.PI / 4) - IconSize / 2,
          y: TotalSize / 2 + IconOffsetFromCenter * Math.sin(-Math.PI / 4) - IconSize / 2
        })
    }
    .width(TotalSize)
    .height(TotalSize)
    .position({
      x: this.posX - TotalSize / 2,
      y: this.posY - TotalSize / 2
    })
    .visibility(this.visible ? Visibility.Visible : Visibility.None)
    .hitTestBehavior(HitTestMode.None)
  }

  @Monitor('progress')
  onProgressChanged(): void {
    this.drawProgress();
  }

  private drawProgress(): void {
    if (!this.ctx) {
      return;
    }
    const center = TotalSize / 2;
    const radius = RingDiameter / 2 - BarWidth / 2;

    this.ctx.clearRect(0, 0, TotalSize, TotalSize);

    this.ctx.beginPath();
    this.ctx.arc(center, center, RingDiameter / 2 - BarWidth, 0, Math.PI * 2);
    this.ctx.fillStyle = FillColor;
    this.ctx.fill();

    this.ctx.beginPath();
    this.ctx.arc(center, center, radius, 0, Math.PI * 2);
    this.ctx.strokeStyle = TrackColor;
    this.ctx.lineWidth = BarWidth;
    this.ctx.stroke();

    if (this.progress > 0) {
      const startAngle = -Math.PI / 2;
      const endAngle = startAngle + Math.PI * 2 * Math.min(1, this.progress);
      this.ctx.beginPath();
      this.ctx.arc(center, center, radius, startAngle, endAngle);
      this.ctx.strokeStyle = ProgressColor;
      this.ctx.lineWidth = BarWidth;
      this.ctx.lineCap = 'round';
      this.ctx.stroke();
    }
  }
}
