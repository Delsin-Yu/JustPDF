import { display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'IndexFoldSplit';
/** 横/竖折痕轴比阈值，避免单次宽高比较误判 */
const AXIS_RATIO_THRESHOLD: number = 1.35;
/** 折痕厚度超过内容高度该比例时钳位 */
const CREASE_THICKNESS_MAX_RATIO: number = 0.35;
/** 折痕厚度异常时的回退（vp） */
const CREASE_THICKNESS_FALLBACK_VP: number = 8;
/** 上区底边距折痕上边界：尽量贴折痕，给最近打开更多高度 */
const UPPER_SAFE_GAP_VP: number = 4;
/** 下区顶边距折痕下边界 */
const LOWER_SAFE_GAP_VP: number = 4;
/** 横折痕锚定时主视觉过矮则回退 50% */
const MIN_HERO_HEIGHT_VP: number = 96;

/** 首页竖向可折叠分屏的几何快照 */
export class IndexFoldSplitSnapshot {
  deviceFoldable: boolean = false;
  /** 半折/笔记本姿态，最近打开才收到下半屏 */
  laptopMode: boolean = false;
  horizontalCrease: boolean = false;
  heroHeightVp: number = 0;
  creaseBandVp: number = 0;
}

export interface IndexFoldSplitMeasureOptions {
  uiContext: UIContext;
  contentHeightVp: number;
  contentTopInsetVp: number;
}

export function createEmptyIndexFoldSplit(): IndexFoldSplitSnapshot {
  return new IndexFoldSplitSnapshot();
}

/**
 * 仅笔记本/悬停半折时把最近打开收到下半屏。
 * 有横折痕则锚到折痕上方；否则回退 50%。展开竖持不收窄。
 */
export function measureIndexFoldSplit(options: IndexFoldSplitMeasureOptions): IndexFoldSplitSnapshot {
  const snap: IndexFoldSplitSnapshot = createEmptyIndexFoldSplit();
  const contentHeightVp: number = options.contentHeightVp;
  const fallbackHeroVp: number = contentHeightVp > 0 ? contentHeightVp * 0.5 : 0;

  try {
    if (!display.isFoldable()) {
      return snap;
    }
    snap.deviceFoldable = true;
    snap.laptopMode = isIndexLaptopFoldStatus(display.getFoldStatus());
  } catch (error) {
    const bizErr = error as BusinessError;
    hilog.warn(0x0000, TAG, `读取折叠状态失败: code=${bizErr.code}`);
    return snap;
  }

  if (!snap.laptopMode) {
    return snap;
  }
  snap.heroHeightVp = fallbackHeroVp;

  try {
    const region: display.FoldCreaseRegion = display.getCurrentFoldCreaseRegion();
    if (region === undefined || region.creaseRects.length === 0) {
      return snap;
    }
    const rect: display.Rect = region.creaseRects[0];
    // 笔记本态优先按横折痕用；轴比不够 1.35 时只要更扁也当横折痕
    if (!isHorizontalCreaseRect(rect) && !isFlatCreaseRect(rect)) {
      return snap;
    }

    const mapped: IndexFoldCreaseBandVp = mapHorizontalCreaseBand(options, region, rect);
    const heroHeightVp: number = mapped.topVp - UPPER_SAFE_GAP_VP;
    if (heroHeightVp < MIN_HERO_HEIGHT_VP) {
      return snap;
    }

    snap.horizontalCrease = true;
    snap.heroHeightVp = heroHeightVp;
    snap.creaseBandVp = mapped.heightVp + UPPER_SAFE_GAP_VP + LOWER_SAFE_GAP_VP;
    return snap;
  } catch (error) {
    const bizErr = error as BusinessError;
    hilog.warn(0x0000, TAG, `读取折痕失败: code=${bizErr.code}`);
    return snap;
  }
}

/** 半折姿态：2-in-1 笔记本态、双折悬停，以及三折带半折的组合 */
export function isIndexLaptopFoldStatus(status: display.FoldStatus): boolean {
  return status === display.FoldStatus.FOLD_STATUS_HALF_FOLDED
    || status === display.FoldStatus.FOLD_STATUS_HALF_FOLDED_WITH_SECOND_EXPANDED
    || status === display.FoldStatus.FOLD_STATUS_HALF_FOLDED_WITH_SECOND_HALF_FOLDED
    || status === display.FoldStatus.FOLD_STATUS_EXPANDED_WITH_SECOND_HALF_FOLDED;
}

export function bindIndexFoldStatusChange(callback: Callback<display.FoldStatus>): void {
  try {
    display.on('foldStatusChange', callback);
  } catch (error) {
    const bizErr = error as BusinessError;
    hilog.warn(0x0000, TAG, `监听 foldStatusChange 失败: code=${bizErr.code}`);
  }
}

export function unbindIndexFoldStatusChange(callback: Callback<display.FoldStatus>): void {
  try {
    display.off('foldStatusChange', callback);
  } catch (error) {
    const bizErr = error as BusinessError;
    hilog.warn(0x0000, TAG, `取消 foldStatusChange 失败: code=${bizErr.code}`);
  }
}

class IndexFoldCreaseBandVp {
  topVp: number = 0;
  heightVp: number = 0;
}

function isHorizontalCreaseRect(rect: display.Rect): boolean {
  const widthPx: number = Math.abs(rect.width);
  const heightPx: number = Math.abs(rect.height);
  return widthPx >= heightPx * AXIS_RATIO_THRESHOLD;
}

function isFlatCreaseRect(rect: display.Rect): boolean {
  return Math.abs(rect.width) >= Math.abs(rect.height);
}

function mapHorizontalCreaseBand(
  options: IndexFoldSplitMeasureOptions,
  region: display.FoldCreaseRegion,
  rect: display.Rect
): IndexFoldCreaseBandVp {
  const band: IndexFoldCreaseBandVp = new IndexFoldCreaseBandVp();
  let topPx: number = rect.top;
  let bottomPx: number = rect.top + rect.height;
  try {
    const topPos: display.Position = { x: rect.left, y: rect.top };
    const bottomPos: display.Position = {
      x: rect.left + rect.width,
      y: rect.top + rect.height
    };
    const relTop: display.RelativePosition =
      display.convertGlobalToRelativeCoordinate(topPos, region.displayId);
    const relBottom: display.RelativePosition =
      display.convertGlobalToRelativeCoordinate(bottomPos, region.displayId);
    topPx = Math.min(relTop.position.y, relBottom.position.y);
    bottomPx = Math.max(relTop.position.y, relBottom.position.y);
  } catch (error) {
    const bizErr = error as BusinessError;
    hilog.warn(0x0000, TAG, `折痕坐标转换失败: code=${bizErr.code}`);
  }

  let topVp: number = options.uiContext.px2vp(topPx) - options.contentTopInsetVp;
  let heightVp: number = options.uiContext.px2vp(bottomPx - topPx);
  const maxThickness: number = options.contentHeightVp * CREASE_THICKNESS_MAX_RATIO;
  if (heightVp > maxThickness) {
    heightVp = CREASE_THICKNESS_FALLBACK_VP;
  }
  if (topVp < 0) {
    topVp = 0;
  }
  band.topVp = topVp;
  band.heightVp = heightVp;
  return band;
}
