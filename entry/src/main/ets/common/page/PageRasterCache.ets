import { pdfService } from '@kit.PDFKit';
import { image } from '@kit.ImageKit';
import { mul, Vec2, Vector2 } from '../ui/Numbers';
/** 光栅化「预览档」缩放，用于快速首帧；须小于 MIN_RENDER_SCALE */
export const PREVIEW_RENDER_SCALE: number = 1;
/** 与 PDF 页面坐标一致的布局倍率（页面框在 vp 中的尺度），与光栅 renderScale 无关 */
export const DISPLAY_LAYOUT_SCALE: number = 2;
/** 阅读器默认可用光栅档位下限（与 PDFViewerViewModel.ViewerMinRenderScale 对齐） */
export const MIN_RENDER_SCALE: number = 6;
/**
 * 单页光栅像素上限约 7e7（~280MB RGBA）。
 * 阅读档提高后密谱细线可保留；A1 等大页仍会被钳制，避免整页过高倍率 OOM。
 * layoutPixelMap 在 TaskPool 预生成，供适口/手势使用，避免主线程同步缩小与 HQ 纹理跟手变换。
 */

export interface PageCache {
  pixelMap: PixelMap;
  /**
   * 缩到 displaySize 的显示代理（TaskPool 内生成）。
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

/** 在 TaskPool 工作线程中探测区间内含折线批注的页（避免主线程对每页调用 getPage）。 */
@Concurrent
export function probePdfPolylineAnnotationPages(
  documentPath: string,
  startPageIndex: number,
  endPageIndex: number,
  openPassword: string
): number[] {
  const document = new pdfService.PdfDocument();
  const loadResult = document.loadDocument(documentPath, openPassword);
  if (loadResult !== pdfService.ParseResult.PARSE_SUCCESS) {
    throw new Error(`加载文档失败: ${loadResult}`);
  }

  const affectedPageIndices: number[] = [];
  try {
    for (let pageIndex = startPageIndex; pageIndex < endPageIndex; pageIndex++) {
      const page = document.getPage(pageIndex);
      const annotations = page.getAnnotations();
      for (let i = 0; i < annotations.length; i++) {
        if (annotations[i].type === pdfService.AnnotationType.POLYLINE) {
          affectedPageIndices.push(pageIndex);
          break;
        }
      }
    }
  } finally {
    document.releaseDocument();
  }
  return affectedPageIndices;
}

@Concurrent
export function cachePage(documentPath: string, documentIndex: number, renderScale: number, openPassword: string): PageCache {

  const document = new pdfService.PdfDocument();
  const result = document.loadDocument(documentPath, openPassword);
  if (result != pdfService.ParseResult.PARSE_SUCCESS) {
    throw new Error(`加载文档失败: ${result}`);
  }

  try {
    const page = document.getPage(documentIndex);

    const baseSize = Vec2(page.getWidth(), page.getHeight());
    const pageArea: number = baseSize.x * baseSize.y;
    // @Concurrent 内不可引用模块级常量；与模块注释中的 7e7 预算对齐
    const maxBitmapPixels: number = 70000000;
    // 与 DISPLAY_LAYOUT_SCALE 对齐
    const layoutScale: number = 2;
    let effectiveScale: number = renderScale;
    if (pageArea > 0) {
      const maxScale: number = Math.sqrt(maxBitmapPixels / pageArea);
      if (effectiveScale > maxScale) {
        effectiveScale = Math.max(1, maxScale);
      }
    }
    const renderSize = mul(baseSize, effectiveScale);
    const matrix = new pdfService.PdfMatrix();
    matrix.x = 0;
    matrix.y = 0;
    matrix.width = renderSize.x;
    matrix.height = renderSize.y;
    matrix.rotate = 0;
    const pixelMap = page.getCustomPagePixelMap(matrix, false, true);

    // 布局倍率固定为 2，与模块常量 DISPLAY_LAYOUT_SCALE 一致（@Concurrent 内不可用模块级常量）
    const displaySize = mul(baseSize, layoutScale);

    // 阅读/高清档：在工作线程预生成 layout 代理
    let layoutPixelMap: PixelMap | undefined = undefined;
    if (effectiveScale > layoutScale + 0.001) {
      const factor: number = layoutScale / effectiveScale;
      try {
        layoutPixelMap = pixelMap.createScaledPixelMapSync(
          factor,
          factor,
          image.AntiAliasingLevel.MEDIUM
        );
      } catch (_scaleErr) {
        layoutPixelMap = undefined;
      }
    }

    return {
      pixelMap: pixelMap,
      layoutPixelMap: layoutPixelMap,
      renderScale: effectiveScale,
      baseSize: baseSize,
      displaySize: displaySize
    };
  } finally {
    // 释放文档以避免内存泄漏 - 每次 cachePage 调用都会创建新的 PdfDocument
    document.releaseDocument();
  }
}
