import { Vec2, Vector2 } from '../../common/ui/Numbers';
import { PageCache } from '../../common/page/PageRasterCache';
import { LengthMetricsUnit } from '@kit.ArkUI';

/** 主条 / 过渡条共用的单槽显示与画布状态（三列模式最多 3 槽） */
export const PAGE_VIEW_SLOT_COUNT: number = 3;

/**
 * 单页槽位状态。pixelMap / loading / viewSize 使用 @Trace，
 * 以便作为 @Local 数组元素时在 ComponentV2 中触发 UI 刷新（与 PDFViewerViewModel 一致）。
 */
@ObservedV2
export class PageViewSlot {
  @Trace pixelMap: PixelMap | undefined = undefined;
  @Trace loading: boolean = false;
  @Trace viewSize: Vector2 = Vec2(0, 0);
  readonly annotateCtx: CanvasRenderingContext2D;
  readonly drawCtx: CanvasRenderingContext2D;
  /** true 时 pixelMap 由本槽 createScaled 持有，替换前须 release */
  private ownsDisplayPixelMap: boolean = false;

  constructor(settings: RenderingContextSettings) {
    this.annotateCtx = new CanvasRenderingContext2D(settings, LengthMetricsUnit.PX);
    this.drawCtx = new CanvasRenderingContext2D(settings, LengthMetricsUnit.PX);
  }

  private releaseOwnedDisplayPixelMap(): void {
    if (this.ownsDisplayPixelMap && this.pixelMap !== undefined) {
      try {
        this.pixelMap.release();
      } catch (_e) {
      }
    }
    this.ownsDisplayPixelMap = false;
  }

  /** 写入 PixelMap、尺寸与加载标记 */
  applyDisplay(pixelMap: PixelMap | undefined, viewSize: Vector2, loading: boolean): void {
    this.releaseOwnedDisplayPixelMap();
    this.pixelMap = pixelMap;
    this.viewSize = viewSize;
    this.loading = loading;
  }

  /** 用缓存结果更新显示并结束 loading（不接管缓存内 PixelMap 生命周期） */
  applyCache(cache: PageCache): void {
    this.releaseOwnedDisplayPixelMap();
    this.pixelMap = cache.pixelMap;
    this.viewSize = cache.displaySize;
    this.loading = false;
  }

  /** 仅替换 PixelMap（高分就绪等路径） */
  applyPixelMap(pixelMap: PixelMap | undefined): void {
    this.releaseOwnedDisplayPixelMap();
    this.pixelMap = pixelMap;
  }

  /**
   * 显示用缩小副本（如高分位图适口过采样时 createScaled）。
   * 槽位拥有该 PixelMap，后续替换会 release。
   */
  applyOwnedDisplay(pixelMap: PixelMap, viewSize: Vector2): void {
    this.releaseOwnedDisplayPixelMap();
    this.pixelMap = pixelMap;
    this.viewSize = viewSize;
    this.loading = false;
    this.ownsDisplayPixelMap = true;
  }

  /** 从另一槽拷贝显示状态（过渡条 → 主条）；不转移 owned 所有权 */
  copyDisplayFrom(other: PageViewSlot): void {
    this.releaseOwnedDisplayPixelMap();
    this.pixelMap = other.pixelMap;
    this.viewSize = other.viewSize;
    this.loading = other.loading;
  }

  clearPixelMap(): void {
    this.releaseOwnedDisplayPixelMap();
    this.pixelMap = undefined;
  }

  clearLoading(): void {
    this.loading = false;
  }

  resetDrawCanvas(): void {
    this.drawCtx.reset();
  }

  resetCanvases(): void {
    this.annotateCtx.reset();
    this.drawCtx.reset();
  }
}

/** 创建固定长度的槽位数组 */
export function createPageViewSlots(settings: RenderingContextSettings, count: number = PAGE_VIEW_SLOT_COUNT): PageViewSlot[] {
  const slots: PageViewSlot[] = [];
  for (let i = 0; i < count; i++) {
    slots.push(new PageViewSlot(settings));
  }
  return slots;
}
