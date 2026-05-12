// 长按唤起批注浮窗：触点处为径向扇形进度（深色圆底）；笔标置于右上偏移，
// 单独小圆底 + 浅色描边，解决旧版「白底上无衬底图标」看不清的问题。
// 大圆不再套高亮白边（在深色底上几乎无意义）；轨用略亮灰弧画在深色底上。

const PanelSize: number = 108;
const IconHubRadius: number = 24;
const OuterInset: number = 4;

const IconFont: number = 22;
// 笔标气泡：略大于字框，与主圆外沿留出间隙。
const IconBubbleSize: number = 40;
const IconBubbleGapFromRadial: number = 8;

const BackdropFill: string = 'rgba(26, 28, 32, 0.94)';
// 画在深色底上的进度槽（勿用高亮白描主圆，对比度差且语义重复）。
const TrackRingOnDark: string = 'rgba(88, 96, 110, 0.85)';
const PieFillColor: string = 'rgba(82, 168, 255, 0.95)';
const HubStrokeOnDark: string = 'rgba(60, 66, 76, 0.95)';
// 主圆在白纸上的外缘剪影（深描边），不靠浅色大环。
const PanelEdgeOnPaper: string = 'rgba(0, 0, 0, 0.32)';
// 笔标气泡：衬底 + 在浅色页面上可见的细亮边。
const IconBubbleFill: string = 'rgba(32, 34, 38, 0.96)';
const IconBubbleRim: string = 'rgba(255, 255, 255, 0.42)';

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
        .width(PanelSize)
        .height(PanelSize)
        .onReady(() => this.drawProgress())

      this.buildTopRightIconBubble()
    }
    .width(PanelSize)
    .height(PanelSize)
    .borderRadius(PanelSize / 2)
    .border({ width: 1, color: PanelEdgeOnPaper })
    .shadow({
      radius: 16,
      color: 'rgba(0, 0, 0, 0.45)',
      offsetX: 0,
      offsetY: 4
    })
    .position({
      x: this.posX - PanelSize / 2,
      y: this.posY - PanelSize / 2
    })
    .visibility(this.visible ? Visibility.Visible : Visibility.None)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildTopRightIconBubble() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.pencil_waveform'))
        .fontSize(IconFont)
        .fontColor(['#FFFFFF'])
    }
    .width(IconBubbleSize)
    .height(IconBubbleSize)
    .borderRadius(IconBubbleSize / 2)
    .backgroundColor(IconBubbleFill)
    .border({ width: 1.2, color: IconBubbleRim })
    .shadow({ radius: 6, color: 'rgba(0, 0, 0, 0.35)', offsetY: 2 })
    .position({
      x: this.computeIconBubbleLeft(),
      y: this.computeIconBubbleTop()
    })
  }

  private computeIconBubbleLeft(): number {
    const center: number = PanelSize / 2;
    const outerR: number = center - OuterInset;
    const dist: number = outerR + IconBubbleSize / 2 + IconBubbleGapFromRadial;
    const angle: number = -Math.PI / 4;
    return center + dist * Math.cos(angle) - IconBubbleSize / 2;
  }

  private computeIconBubbleTop(): number {
    const center: number = PanelSize / 2;
    const outerR: number = center - OuterInset;
    const dist: number = outerR + IconBubbleSize / 2 + IconBubbleGapFromRadial;
    const angle: number = -Math.PI / 4;
    return center + dist * Math.sin(angle) - IconBubbleSize / 2;
  }

  @Monitor('progress')
  onProgressChanged(): void {
    this.drawProgress();
  }

  private drawProgress(): void {
    if (!this.ctx) {
      return;
    }
    const center: number = PanelSize / 2;
    const outerR: number = center - OuterInset;

    this.ctx.clearRect(0, 0, PanelSize, PanelSize);

    this.ctx.beginPath();
    this.ctx.arc(center, center, outerR, 0, Math.PI * 2);
    this.ctx.fillStyle = BackdropFill;
    this.ctx.fill();

    this.ctx.beginPath();
    this.ctx.arc(center, center, outerR - 1, 0, Math.PI * 2);
    this.ctx.strokeStyle = TrackRingOnDark;
    this.ctx.lineWidth = 2;
    this.ctx.stroke();

    const p: number = Math.min(1, Math.max(0, this.progress));
    if (p > 0) {
      const startAngle: number = -Math.PI / 2;
      const endAngle: number = startAngle + Math.PI * 2 * p;
      this.ctx.beginPath();
      this.ctx.moveTo(center, center);
      this.ctx.arc(center, center, outerR - 0.5, startAngle, endAngle);
      this.ctx.closePath();
      this.ctx.fillStyle = PieFillColor;
      this.ctx.fill();
    }

    this.ctx.beginPath();
    this.ctx.arc(center, center, IconHubRadius, 0, Math.PI * 2);
    this.ctx.fillStyle = BackdropFill;
    this.ctx.fill();
    this.ctx.beginPath();
    this.ctx.arc(center, center, IconHubRadius, 0, Math.PI * 2);
    this.ctx.strokeStyle = HubStrokeOnDark;
    this.ctx.lineWidth = 1;
    this.ctx.stroke();
  }
}
