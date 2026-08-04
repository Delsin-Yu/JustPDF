import { AnimatorResult } from '@kit.ArkUI';

/**
 * 深海渐变配色（起始方案），与 endScheme 之间随相位插值。
 * 三个停靠点：近黑 -> 深藏青 -> 明亮深海蓝，拉开明度层级。
 */
const SCHEME_START: string[] = ['#01030A', '#03284D', '#006E9C'];
/** 深海渐变配色（结束方案），偏青一些，营造洋流涌动感。 */
const SCHEME_END: string[] = ['#000208', '#003A60', '#0089B3'];

/**
 * 解析 '#RRGGBB' 颜色到 [r, g, b] 数组。
 */
function parseHexColor(hex: string): number[] {
  const r = parseInt(hex.substring(1, 3), 16);
  const g = parseInt(hex.substring(3, 5), 16);
  const b = parseInt(hex.substring(5, 7), 16);
  return [r, g, b];
}

function channelToHex(value: number): string {
  let clamped = Math.round(value);
  if (clamped < 0) {
    clamped = 0;
  }
  if (clamped > 255) {
    clamped = 255;
  }
  let text = clamped.toString(16);
  if (text.length < 2) {
    text = '0' + text;
  }
  return text;
}

/**
 * 按比例 t（0..1）混合两个 '#RRGGBB' 颜色，返回 '#RRGGBB'。
 * 供背景组件与页面文字取同源色调使用。
 */
export function mixHexColors(colorA: string, colorB: string, t: number): string {
  const a = parseHexColor(colorA);
  const b = parseHexColor(colorB);
  const r = channelToHex(a[0] + (b[0] - a[0]) * t);
  const g = channelToHex(a[1] + (b[1] - a[1]) * t);
  const bch = channelToHex(a[2] + (b[2] - a[2]) * t);
  return '#' + r + g + bch;
}

/**
 * 全屏海洋渐变背景：
 * - 基础层为随相位缓慢变色、变角度的清晰三色线性渐变；
 * - 上层若干半透明径向渐变光晕，随相位漂移形成波浪涌动感。
 * 相位由单个 Animator 驱动（往复 0..1），并通过 onPhaseChange 回调
 * 通知宿主页面同步文字色调。
 */
@Component
export struct OceanBackground {
  /** 页面可见性开关：false 时暂停动画以省电 */
  @Prop @Watch('onActiveChanged') active: boolean = true;
  /** 相位回调，宿主可据此联动标题颜色 */
  onPhaseChange: (phase: number) => void = (_phase: number) => {
  };
  @State phase: number = 0;
  private animator: AnimatorResult | undefined = undefined;

  aboutToAppear(): void {
    try {
      this.animator = this.getUIContext().createAnimator({
        duration: 24000,
        easing: 'linear',
        delay: 0,
        fill: 'forwards',
        direction: 'normal',
        iterations: -1,
        begin: 0,
        end: 1
      });
      // 背景变化缓慢，限帧以降低功耗
      this.animator.setExpectedFrameRateRange({ min: 10, expected: 20, max: 30 });
      this.animator.onFrame = (progress: number) => {
        this.phase = progress;
        this.onPhaseChange(this.tidePhase());
      };
      if (this.active) {
        this.animator.play();
      }
    } catch (_error) {
    }
  }

  aboutToDisappear(): void {
    if (this.animator !== undefined) {
      // 先清空 onFrame 再取消，避免终点跳变帧；并释放引用防止内存泄漏
      this.animator.onFrame = (_progress: number) => {
      };
      try {
        this.animator.cancel();
      } catch (_error) {
      }
      this.animator = undefined;
    }
  }

  onActiveChanged(): void {
    if (this.animator === undefined) {
      return;
    }
    try {
      if (this.active) {
        this.animator.play();
      } else {
        this.animator.pause();
      }
    } catch (_error) {
    }
  }

  /** 周期正弦波，确保动画从末帧回到首帧时连续。 */
  private wave(offset: number, frequency: number): number {
    return Math.sin((this.phase * frequency + offset) * Math.PI * 2);
  }

  /** 将潮汐波映射到 0..1，供配色和标题联动使用。 */
  private tidePhase(): number {
    return (this.wave(0.08, 1) + 1) * 0.5;
  }

  /** 仅保留三个关键色标，由渲染器直接完成连续插值。 */
  private baseGradientColors(): [ResourceColor, number][] {
    const tide = this.tidePhase();
    const c0 = mixHexColors(SCHEME_START[0], SCHEME_END[0], tide);
    const c1 = mixHexColors(SCHEME_START[1], SCHEME_END[1], tide);
    const c2 = mixHexColors(SCHEME_START[2], SCHEME_END[2], tide);
    const stops: [ResourceColor, number][] = [
      [c0, 0],
      [c1, 0.55],
      [c2, 1]
    ];
    return stops;
  }

  /** 百分比坐标字符串，供径向渐变中心随相位漂移 */
  private percent(value: number): string {
    return value.toFixed(2) + '%';
  }

  /** 使用少量透明度色标形成干净的径向光晕。 */
  private glowStops(rgb: string, peakAlpha: number): [ResourceColor, number][] {
    const middleAlpha = Math.round(peakAlpha * 0.22);
    const stops: [ResourceColor, number][] = [
      ['#' + channelToHex(peakAlpha) + rgb, 0],
      ['#' + channelToHex(middleAlpha) + rgb, 0.58],
      ['#00' + rgb, 1]
    ];
    return stops;
  }

  build() {
    Stack() {
      // 基础深海渐变：三个原生色标直接插值，保持画面清晰
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 172 + 12 * this.wave(0.12, 1),
          colors: this.baseGradientColors()
        })

      // 左上方深藏青缓慢绕流，横纵方向采用不同频率
      Column()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: [
            this.percent(10 + 8 * this.wave(0, 1)),
            this.percent(8 + 6 * this.wave(0.25, 2))
          ],
          radius: this.percent(82 + 5 * this.wave(0.18, 1)),
          colors: this.glowStops('004C86', 0x3D)
        })

      // 底部青蓝光晕以错相潮汐方式左右涌动
      Column()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: [
            this.percent(38 + 13 * this.wave(0.38, 1)),
            this.percent(98 + 5 * this.wave(0.12, 2))
          ],
          radius: this.percent(92 + 7 * this.wave(0.55, 1)),
          colors: this.glowStops('00779E', 0x4A)
        })

      // 中部淡青微光反向漂流，形成交错洋流
      Column()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: [
            this.percent(78 + 15 * this.wave(0.68, 1)),
            this.percent(28 + 8 * this.wave(0.42, 2))
          ],
          radius: this.percent(68 + 6 * this.wave(0.82, 1)),
          colors: this.glowStops('00A0BF', 0x2A)
        })

      // 薄模糊柔化渐变过渡，不叠加噪声纹理
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#01FFFFFF')
        .backdropBlur(5)
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }
}
