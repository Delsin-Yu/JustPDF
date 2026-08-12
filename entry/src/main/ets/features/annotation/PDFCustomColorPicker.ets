import { SharedPanelBackgroundColor } from '../viewer/PDFPanelVisualConstants';
import {
  AnnotationColor,
  hsvToRgb,
  makeCustomAnnotationColor,
  parseHexColor,
  pdfColorToRgb,
  rgbToHex,
  rgbToHsv,
  RgbTuple
} from './PDFAnnotationColors';

// 颜色轮盘的物理尺寸（vp）。
const WheelSize: number = 184;
const WheelCenter: number = WheelSize / 2;
const WheelOuterR: number = 88;
const WheelInnerR: number = 70;
const WheelRingCenterR: number = (WheelOuterR + WheelInnerR) / 2;
// SV 方块边长——略小于环内切正方形，确保不压住环。
const SquareSide: number = 92;
const SquareOrigin: number = (WheelSize - SquareSide) / 2;

const HueMarkerR: number = 7;
const SquareMarkerR: number = 7;

const PickerPad: number = 14;
const SectionGap: number = 10;
const PreviewHeight: number = 26;
const InputHeight: number = 32;
const LabelWidth: number = 18;
const FloatInputWidth: number = 56;

const RecentCols: number = 5;
const RecentRows: number = 2;
const RecentSwatchSize: number = 30;
const RecentSwatchGap: number = 6;

// 弹出层与按钮的统一字体色。
const FgPrimary: string = 'rgba(255, 255, 255, 0.92)';
const FgSecondary: string = 'rgba(255, 255, 255, 0.6)';
const FgMuted: string = 'rgba(255, 255, 255, 0.42)';
const InputBg: string = 'rgba(255, 255, 255, 0.08)';
const InputBorder: string = 'rgba(255, 255, 255, 0.14)';

// 色相环触摸命中外沿容差（与旧逻辑一致，略大于绘制外径）。
const WheelRingHitOuterSlack: number = 4;

// 单次手势内锁定的控件：方块与环互不抢占，手指移出区域时按规则钳制到边界直至抬起。
type WheelDragKind = 'none' | 'hueRing' | 'svSquare';

@ComponentV2
export struct PDFCustomColorPicker {
  @Param initialPdfColor: number = 0x808080;
  @Param recentColors: AnnotationColor[] = [];
  @Event onColorChanged: (color: AnnotationColor) => void = () => {};

  // 工作色相/饱和度/明度（均在 [0, 1] 区间）。
  @Local h: number = 0;
  @Local s: number = 0;
  @Local v: number = 0.5;
  // 文本输入分别用一组独立字符串，避免数值更新打断用户输入。
  @Local hueText: string = '0.00';
  @Local satText: string = '0.00';
  @Local valText: string = '0.50';
  @Local hexText: string = '808080';

  private readonly settings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private contextReady: boolean = false;

  private wheelDragKind: WheelDragKind = 'none';

  aboutToAppear(): void {
    const rgb: RgbTuple = pdfColorToRgb(this.initialPdfColor);
    const hsv = rgbToHsv(rgb.r, rgb.g, rgb.b);
    this.h = hsv.s > 0 ? hsv.h : 0;
    this.s = hsv.s;
    this.v = hsv.v;
    this.refreshHueText();
    this.refreshSatText();
    this.refreshValText();
    this.refreshHexText();
  }

  // ------------------ 计算辅助 ------------------

  private currentRgb(): RgbTuple {
    return hsvToRgb(this.h, this.s, this.v);
  }

  private currentCanvasColor(): string {
    const rgb: RgbTuple = this.currentRgb();
    return `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, 1.00)`;
  }

  private formatFloat(n: number): string {
    return n.toFixed(2);
  }

  private refreshHueText(): void {
    this.hueText = this.formatFloat(this.h);
  }

  private refreshSatText(): void {
    this.satText = this.formatFloat(this.s);
  }

  private refreshValText(): void {
    this.valText = this.formatFloat(this.v);
  }

  private refreshHexText(): void {
    const rgb: RgbTuple = this.currentRgb();
    this.hexText = rgbToHex(rgb.r, rgb.g, rgb.b);
  }

  private emitColor(): void {
    const rgb: RgbTuple = this.currentRgb();
    this.onColorChanged(makeCustomAnnotationColor(rgb.r, rgb.g, rgb.b));
  }

  // ------------------ 状态变更入口 ------------------

  private setHue(value: number): void {
    const clamped: number = Math.max(0, Math.min(1, value));
    this.h = clamped;
    this.refreshHueText();
    this.refreshHexText();
    this.renderSvSquare();
    this.emitColor();
  }

  private setSat(value: number): void {
    const clamped: number = Math.max(0, Math.min(1, value));
    this.s = clamped;
    this.refreshSatText();
    this.refreshHexText();
    this.emitColor();
  }

  private setVal(value: number): void {
    const clamped: number = Math.max(0, Math.min(1, value));
    this.v = clamped;
    this.refreshValText();
    this.refreshHexText();
    this.emitColor();
  }

  private setSatVal(sat: number, val: number): void {
    this.s = Math.max(0, Math.min(1, sat));
    this.v = Math.max(0, Math.min(1, val));
    this.refreshSatText();
    this.refreshValText();
    this.refreshHexText();
    this.emitColor();
  }

  // 通过外部 RGB 同步整体 HSV 状态——例如来自最近颜色或 hex 输入。
  private adoptRgb(rgb: RgbTuple, preserveHueWhenGray: boolean): void {
    const hsv = rgbToHsv(rgb.r, rgb.g, rgb.b);
    if (!(preserveHueWhenGray && hsv.s === 0)) {
      this.h = hsv.h;
    }
    this.s = hsv.s;
    this.v = hsv.v;
    this.refreshHueText();
    this.refreshSatText();
    this.refreshValText();
    this.refreshHexText();
    this.renderSvSquare();
    this.emitColor();
  }

  // ------------------ Canvas 绘制 ------------------

  private renderHueRing(): void {
    const segments: number = 360;
    for (let i = 0; i < segments; i++) {
      const a0: number = (i / segments) * Math.PI * 2 - Math.PI / 2;
      const a1: number = ((i + 1) / segments) * Math.PI * 2 - Math.PI / 2;
      this.ctx.beginPath();
      this.ctx.moveTo(WheelCenter, WheelCenter);
      this.ctx.arc(WheelCenter, WheelCenter, WheelOuterR, a0 - 0.005, a1 + 0.005);
      this.ctx.closePath();
      const rgb: RgbTuple = hsvToRgb(i / segments, 1, 1);
      this.ctx.fillStyle = `rgb(${rgb.r}, ${rgb.g}, ${rgb.b})`;
      this.ctx.fill();
    }
    this.ctx.save();
    this.ctx.globalCompositeOperation = 'destination-out';
    this.ctx.beginPath();
    this.ctx.arc(WheelCenter, WheelCenter, WheelInnerR, 0, Math.PI * 2);
    this.ctx.closePath();
    this.ctx.fillStyle = 'rgba(0, 0, 0, 1)';
    this.ctx.fill();
    this.ctx.restore();
  }

  private renderSvSquare(): void {
    if (!this.contextReady) {
      return;
    }
    // 清掉原方块区域。
    this.ctx.clearRect(SquareOrigin - 1, SquareOrigin - 1, SquareSide + 2, SquareSide + 2);

    const hueRgb: RgbTuple = hsvToRgb(this.h, 1, 1);
    this.ctx.fillStyle = `rgb(${hueRgb.r}, ${hueRgb.g}, ${hueRgb.b})`;
    this.ctx.fillRect(SquareOrigin, SquareOrigin, SquareSide, SquareSide);

    const satGrad = this.ctx.createLinearGradient(
      SquareOrigin, 0, SquareOrigin + SquareSide, 0
    );
    satGrad.addColorStop(0, 'rgba(255, 255, 255, 1)');
    satGrad.addColorStop(1, 'rgba(255, 255, 255, 0)');
    this.ctx.fillStyle = satGrad;
    this.ctx.fillRect(SquareOrigin, SquareOrigin, SquareSide, SquareSide);

    const valGrad = this.ctx.createLinearGradient(
      0, SquareOrigin, 0, SquareOrigin + SquareSide
    );
    valGrad.addColorStop(0, 'rgba(0, 0, 0, 0)');
    valGrad.addColorStop(1, 'rgba(0, 0, 0, 1)');
    this.ctx.fillStyle = valGrad;
    this.ctx.fillRect(SquareOrigin, SquareOrigin, SquareSide, SquareSide);
  }

  // ------------------ 触摸交互（手势锁定 + 越界钳制）------------------

  private pointInSquare(vpX: number, vpY: number): boolean {
    return vpX >= SquareOrigin && vpX <= SquareOrigin + SquareSide &&
      vpY >= SquareOrigin && vpY <= SquareOrigin + SquareSide;
  }

  private pointInRing(vpX: number, vpY: number): boolean {
    const dx: number = vpX - WheelCenter;
    const dy: number = vpY - WheelCenter;
    const dist: number = Math.sqrt(dx * dx + dy * dy);
    return dist >= WheelInnerR && dist <= WheelOuterR + WheelRingHitOuterSlack;
  }

  private distSq(ax: number, ay: number, bx: number, by: number): number {
    const dx: number = ax - bx;
    const dy: number = ay - by;
    return dx * dx + dy * dy;
  }

  /**
   * 按下瞬间判定本次手势作用于 SV 方块还是色相环。
   * 方块与环在几何上不重叠；落在空白区时，比较到环（径向钳制）与到方块（轴对齐钳制）的最近点距离。
   */
  private classifyInitialTouch(vpX: number, vpY: number): WheelDragKind {
    if (this.pointInSquare(vpX, vpY)) {
      return 'svSquare';
    }
    if (this.pointInRing(vpX, vpY)) {
      return 'hueRing';
    }

    const cx: number = Math.max(SquareOrigin, Math.min(SquareOrigin + SquareSide, vpX));
    const cy: number = Math.max(SquareOrigin, Math.min(SquareOrigin + SquareSide, vpY));
    const dSquare: number = this.distSq(vpX, vpY, cx, cy);

    const rdx: number = vpX - WheelCenter;
    const rdy: number = vpY - WheelCenter;
    const rdist: number = Math.sqrt(rdx * rdx + rdy * rdy);
    if (rdist < 1e-6) {
      return 'svSquare';
    }
    const rClamped: number = Math.max(WheelInnerR, Math.min(WheelOuterR, rdist));
    const ringPx: number = WheelCenter + (rdx / rdist) * rClamped;
    const ringPy: number = WheelCenter + (rdy / rdist) * rClamped;
    const dRing: number = this.distSq(vpX, vpY, ringPx, ringPy);

    return dSquare <= dRing ? 'svSquare' : 'hueRing';
  }

  /** 色相仅由从圆心指向触点（或其在环上的径向投影）的方位角决定；手指在环内外滑动时角度连续。 */
  private applyHueFromPoint(vpX: number, vpY: number): void {
    const dx: number = vpX - WheelCenter;
    const dy: number = vpY - WheelCenter;
    const dist: number = Math.sqrt(dx * dx + dy * dy);
    if (dist < 1e-6) {
      return;
    }
    let angle: number = Math.atan2(dy, dx) + Math.PI / 2;
    while (angle < 0) {
      angle += Math.PI * 2;
    }
    while (angle >= Math.PI * 2) {
      angle -= Math.PI * 2;
    }
    this.setHue(angle / (Math.PI * 2));
  }

  /** 将触点钳制在 SV 矩形内再换算 S/V。 */
  private applySvFromPoint(vpX: number, vpY: number): void {
    const px: number = Math.max(SquareOrigin, Math.min(SquareOrigin + SquareSide, vpX));
    const py: number = Math.max(SquareOrigin, Math.min(SquareOrigin + SquareSide, vpY));
    const sat: number = (px - SquareOrigin) / SquareSide;
    const val: number = 1 - (py - SquareOrigin) / SquareSide;
    this.setSatVal(sat, val);
  }

  private applyLockedDrag(vpX: number, vpY: number): void {
    if (this.wheelDragKind === 'svSquare') {
      this.applySvFromPoint(vpX, vpY);
    } else if (this.wheelDragKind === 'hueRing') {
      this.applyHueFromPoint(vpX, vpY);
    }
  }

  // TouchObject.x/y 已经是 vp（相对事件响应组件的坐标系），无需再做 px→vp 转换。
  private dispatchWheelTouchEvent(event: TouchEvent): void {
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.wheelDragKind = 'none';
      return;
    }

    if (event.touches.length === 0) {
      return;
    }
    const touch = event.touches[0];
    const vpX: number = touch.x;
    const vpY: number = touch.y;

    if (event.type === TouchType.Down) {
      this.wheelDragKind = this.classifyInitialTouch(vpX, vpY);
      this.applyLockedDrag(vpX, vpY);
      return;
    }

    if (event.type === TouchType.Move && this.wheelDragKind !== 'none') {
      this.applyLockedDrag(vpX, vpY);
    }
  }

  // ------------------ 标记位置 ------------------

  private hueMarkerX(): number {
    const angle: number = this.h * Math.PI * 2 - Math.PI / 2;
    return WheelCenter + WheelRingCenterR * Math.cos(angle) - HueMarkerR;
  }

  private hueMarkerY(): number {
    const angle: number = this.h * Math.PI * 2 - Math.PI / 2;
    return WheelCenter + WheelRingCenterR * Math.sin(angle) - HueMarkerR;
  }

  private svMarkerX(): number {
    return SquareOrigin + this.s * SquareSide - SquareMarkerR;
  }

  private svMarkerY(): number {
    return SquareOrigin + (1 - this.v) * SquareSide - SquareMarkerR;
  }

  // ------------------ 文本输入处理 ------------------

  // 解析 0~1 之间的浮点字符串；若有效则即时更新分量但不立即重置文本，
  // 这样用户可以连续输入（例如先 “0.” 再 “0.5”）。
  private tryApplyHueText(text: string): void {
    const parsed: number = parseFloat(text);
    if (!isNaN(parsed) && parsed >= 0 && parsed <= 1) {
      this.h = parsed;
      this.refreshHexText();
      this.renderSvSquare();
      this.emitColor();
    }
  }

  private tryApplySatText(text: string): void {
    const parsed: number = parseFloat(text);
    if (!isNaN(parsed) && parsed >= 0 && parsed <= 1) {
      this.s = parsed;
      this.refreshHexText();
      this.emitColor();
    }
  }

  private tryApplyValText(text: string): void {
    const parsed: number = parseFloat(text);
    if (!isNaN(parsed) && parsed >= 0 && parsed <= 1) {
      this.v = parsed;
      this.refreshHexText();
      this.emitColor();
    }
  }

  private commitHueText(): void {
    const parsed: number = parseFloat(this.hueText);
    if (isNaN(parsed) || parsed < 0 || parsed > 1) {
      this.refreshHueText();
    } else {
      this.setHue(parsed);
    }
  }

  private commitSatText(): void {
    const parsed: number = parseFloat(this.satText);
    if (isNaN(parsed) || parsed < 0 || parsed > 1) {
      this.refreshSatText();
    } else {
      this.setSat(parsed);
    }
  }

  private commitValText(): void {
    const parsed: number = parseFloat(this.valText);
    if (isNaN(parsed) || parsed < 0 || parsed > 1) {
      this.refreshValText();
    } else {
      this.setVal(parsed);
    }
  }

  private commitHexText(): void {
    const rgb: RgbTuple | undefined = parseHexColor(this.hexText);
    if (!rgb) {
      this.refreshHexText();
      return;
    }
    this.adoptRgb(rgb, true);
  }

  // ------------------ Builders ------------------

  @Builder
  private buildWheel() {
    Stack() {
      Canvas(this.ctx)
        .width(WheelSize)
        .height(WheelSize)
        .onReady(() => {
          this.contextReady = true;
          this.renderHueRing();
          this.renderSvSquare();
        })

      // SV 标记。
      Stack()
        .width(SquareMarkerR * 2)
        .height(SquareMarkerR * 2)
        .borderRadius(SquareMarkerR)
        .backgroundColor(Color.Transparent)
        .border({ width: 2, color: 'rgba(255, 255, 255, 0.95)' })
        .shadow({ radius: 4, color: 'rgba(0, 0, 0, 0.6)' })
        .position({ x: this.svMarkerX(), y: this.svMarkerY() })
        .hitTestBehavior(HitTestMode.None)

      // 色相标记。
      Stack()
        .width(HueMarkerR * 2)
        .height(HueMarkerR * 2)
        .borderRadius(HueMarkerR)
        .backgroundColor(Color.Transparent)
        .border({ width: 2, color: 'rgba(255, 255, 255, 0.98)' })
        .shadow({ radius: 4, color: 'rgba(0, 0, 0, 0.55)' })
        .position({ x: this.hueMarkerX(), y: this.hueMarkerY() })
        .hitTestBehavior(HitTestMode.None)
    }
    .width(WheelSize)
    .height(WheelSize)
    .alignContent(Alignment.TopStart)
    .hitTestBehavior(HitTestMode.Default)
    .onTouch((event: TouchEvent) => this.dispatchWheelTouchEvent(event))
  }

  @Builder
  private buildHueRow() {
    Row({ space: 8 }) {
      Text('H')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(FgPrimary)
        .width(LabelWidth)
        .textAlign(TextAlign.Center)

      Slider({
        value: this.h,
        min: 0,
        max: 1,
        step: 0.01,
        style: SliderStyle.OutSet
      })
        .layoutWeight(1)
        .showTips(false)
        .onChange((v: number, _mode: SliderChangeMode) => this.setHue(v))

      TextInput({ text: this.hueText!! })
        .width(FloatInputWidth)
        .height(InputHeight)
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor(FgPrimary)
        .placeholderColor(FgMuted)
        .backgroundColor(InputBg)
        .borderRadius(8)
        .padding({ left: 8, right: 8 })
        .textAlign(TextAlign.Center)
        .type(InputType.NUMBER_DECIMAL)
        .onChange((value: string) => this.tryApplyHueText(value))
        .onSubmit(() => this.commitHueText())
        .onBlur(() => this.commitHueText())
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildSatRow() {
    Row({ space: 8 }) {
      Text('S')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(FgPrimary)
        .width(LabelWidth)
        .textAlign(TextAlign.Center)

      Slider({
        value: this.s,
        min: 0,
        max: 1,
        step: 0.01,
        style: SliderStyle.OutSet
      })
        .layoutWeight(1)
        .showTips(false)
        .onChange((v: number, _mode: SliderChangeMode) => this.setSat(v))

      TextInput({ text: this.satText!! })
        .width(FloatInputWidth)
        .height(InputHeight)
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor(FgPrimary)
        .placeholderColor(FgMuted)
        .backgroundColor(InputBg)
        .borderRadius(8)
        .padding({ left: 8, right: 8 })
        .textAlign(TextAlign.Center)
        .type(InputType.NUMBER_DECIMAL)
        .onChange((value: string) => this.tryApplySatText(value))
        .onSubmit(() => this.commitSatText())
        .onBlur(() => this.commitSatText())
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildValRow() {
    Row({ space: 8 }) {
      Text('V')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(FgPrimary)
        .width(LabelWidth)
        .textAlign(TextAlign.Center)

      Slider({
        value: this.v,
        min: 0,
        max: 1,
        step: 0.01,
        style: SliderStyle.OutSet
      })
        .layoutWeight(1)
        .showTips(false)
        .onChange((v: number, _mode: SliderChangeMode) => this.setVal(v))

      TextInput({ text: this.valText!! })
        .width(FloatInputWidth)
        .height(InputHeight)
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor(FgPrimary)
        .placeholderColor(FgMuted)
        .backgroundColor(InputBg)
        .borderRadius(8)
        .padding({ left: 8, right: 8 })
        .textAlign(TextAlign.Center)
        .type(InputType.NUMBER_DECIMAL)
        .onChange((value: string) => this.tryApplyValText(value))
        .onSubmit(() => this.commitValText())
        .onBlur(() => this.commitValText())
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildHexRow() {
    Row({ space: 8 }) {
      Text('Hex')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(FgSecondary)
        .width(LabelWidth + 12)

      Text('#')
        .fontSize(14)
        .fontFamily('monospace')
        .fontColor(FgMuted)
        .width(14)
        .textAlign(TextAlign.Center)

      TextInput({ text: this.hexText })
        .layoutWeight(1)
        .height(InputHeight)
        .fontSize(13)
        .fontFamily('monospace')
        .fontColor(FgPrimary)
        .placeholderColor(FgMuted)
        .backgroundColor(InputBg)
        .borderRadius(8)
        .padding({ left: 10, right: 10 })
        .maxLength(6)
        .onChange((value: string) => {
          this.hexText = value.toUpperCase();
        })
        .onSubmit(() => this.commitHexText())
        .onBlur(() => this.commitHexText())
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildPreview() {
    Stack()
      .width('100%')
      .height(PreviewHeight)
      .borderRadius(8)
      .backgroundColor(this.currentCanvasColor())
      .border({ width: 1, color: 'rgba(255, 255, 255, 0.16)' })
  }

  @Builder
  private buildRecentSwatch(index: number) {
    if (index < this.recentColors.length) {
      Stack() {
        Text('')
          .width(RecentSwatchSize - 6)
          .height(RecentSwatchSize - 6)
          .borderRadius((RecentSwatchSize - 6) / 2)
          .backgroundColor(this.recentColors[index].canvasColor)
      }
      .width(RecentSwatchSize)
      .height(RecentSwatchSize)
      .borderRadius(RecentSwatchSize / 2)
      .border({ width: 1, color: 'rgba(255, 255, 255, 0.18)' })
      .onClick(() => {
        const target: AnnotationColor = this.recentColors[index];
        const rgb: RgbTuple = pdfColorToRgb(target.pdfColor);
        this.adoptRgb(rgb, true);
      })
    } else {
      Stack()
        .width(RecentSwatchSize)
        .height(RecentSwatchSize)
        .borderRadius(RecentSwatchSize / 2)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: 'rgba(255, 255, 255, 0.10)', style: BorderStyle.Dashed })
    }
  }

  @Builder
  private buildRecentRow(startIdx: number) {
    Row({ space: RecentSwatchGap }) {
      ForEach([0, 1, 2, 3, 4], (col: number) => {
        this.buildRecentSwatch(startIdx + col);
      }, (col: number) => `${startIdx}-${col}`);
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder
  private buildRecents() {
    Column({ space: RecentSwatchGap }) {
      Text('最近颜色')
        .fontSize(11)
        .fontColor(FgSecondary)
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ bottom: 2 })

      this.buildRecentRow(0);
      this.buildRecentRow(RecentCols);
    }
    .width('100%')
  }

  build() {
    Column({ space: SectionGap }) {

      // 1. 色相环 + 饱和度/明度方块
      this.buildWheel()

      // 2. 当前颜色预览矩形
      this.buildPreview()

      // 3. H / S / V 滑块 + 浮点输入
      Column({ space: 8 }) {
        this.buildHueRow()
        this.buildSatRow()
        this.buildValRow()
      }
      .width('100%')

      // 4. Hex 输入
      this.buildHexRow()

      // 5. 最近颜色
      this.buildRecents()

    }
    .width(WheelSize + PickerPad * 2)
    .padding(PickerPad)
    .backgroundColor(SharedPanelBackgroundColor)
    .borderRadius(16)
    .border({ width: 1, color: 'rgba(255, 255, 255, 0.07)' })
    .shadow({ radius: 14, color: 'rgba(0, 0, 0, 0.28)', offsetY: 5 })
  }
}
