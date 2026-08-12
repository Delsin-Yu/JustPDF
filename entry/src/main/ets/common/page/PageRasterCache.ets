import { Vector2 } from '../ui/Numbers';
/** 光栅化「预览档」缩放，用于快速首帧；须小于 MIN_RENDER_SCALE */
export const PREVIEW_RENDER_SCALE: number = 1;
/** 与 PDF 页面坐标一致的布局倍率（页面框在 vp 中的尺度），与光栅 renderScale 无关 */
export const DISPLAY_LAYOUT_SCALE: number = 2;
/** 阅读器默认可用光栅档位下限（与 PDFViewerViewModel.ViewerMinRenderScale 对齐） */
export const MIN_RENDER_SCALE: number = 6;
/**
 * 单页光栅像素上限约 7e7（~280MB RGBA）。
 * 阅读档提高后密谱细线可保留；A1 等大页仍会被钳制，避免整页过高倍率 OOM。
 * layoutPixelMap 在光栅 Worker 预生成，供适口/手势使用，避免主线程同步缩小与 HQ 纹理跟手变换。
 */

export interface PageCache {
  pixelMap: PixelMap;
  /**
   * 缩到 displaySize 的显示代理（Worker 内生成）。
   * 适口/小缩放与拖拽滑动时 UI 优先用它，避免全幅 HQ 上屏或每帧变换。
   */
  layoutPixelMap: PixelMap | undefined;
  renderScale: number;
  baseSize: Vector2; // 原始页面大小（无缩放）
  /** 布局用页面框尺寸（与 DISPLAY_LAYOUT_SCALE 一致），与光栅 renderScale 无关 */
  displaySize: Vector2;
}

/** 释放 PageCache 持有的全部 PixelMap */
export function releasePageCachePixelMaps(cache: PageCache): void {
  try {
    cache.pixelMap.release();
  } catch (_e) {
  }
  if (cache.layoutPixelMap !== undefined) {
    try {
      cache.layoutPixelMap.release();
    } catch (_e) {
    }
  }
}

/**
 * 交互拖拽/滑动时优先用 layout 代理，避免 GPU 每帧变换整页 HQ。
 */
export function selectDisplayPixelMap(cache: PageCache, preferLayout: boolean): PixelMap {
  if (preferLayout && cache.layoutPixelMap !== undefined) {
    return cache.layoutPixelMap;
  }
  return cache.pixelMap;
}
