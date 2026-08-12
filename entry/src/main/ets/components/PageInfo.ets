import { pdfService } from '@kit.PDFKit';
import { AbilityConstant } from '@kit.AbilityKit';
import { mul, pxToVp, Vec2, Vector2 } from '../components/Numbers';
import { taskpool, util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { DefaultAnnotationColor, pdfColorToCanvasColor } from '../pages/pdfview/PDFAnnotationColors';

export interface ImportedPdfPolylineStrokeSource {
  kind: 'importedPdfPolyline';
  uniqueId: string;
  annotationInfo: pdfService.PolylineAnnotationInfo;
}

export type StrokeSource = ImportedPdfPolylineStrokeSource;

export interface PdfLinkRectangle {
  left: number;
  right: number;
  bottom: number;
  top: number;
}

export interface PdfLinkDestination {
  pageIndex: number;
  fitMode: pdfService.FitMode;
  left?: number;
  top?: number;
  right?: number;
  bottom?: number;
  zoom?: number;
}

export interface PdfGotoPageLinkTarget {
  kind: 'gotoPage';
  pageIndex: number;
  destination?: PdfLinkDestination;
}

export interface PdfUriLinkTarget {
  kind: 'uri';
  uri: string;
}

export interface PdfUnknownLinkTarget {
  kind: 'unknown';
  actionType?: pdfService.PdfActionType;
}

export type PdfLinkTarget = PdfGotoPageLinkTarget | PdfUriLinkTarget | PdfUnknownLinkTarget;

export interface PdfLinkAnnotation {
  rect: PdfLinkRectangle;
  target: PdfLinkTarget;
  uniqueId?: string;
  highlightMode?: pdfService.HighlightMode;
  color?: number;
}

export interface ReadonlyStroke {
  readonly points: readonly Vector2[];
  readonly pdfLineColor: number;
  readonly canvasColor: string;
  readonly source: StrokeSource | undefined;
  stroke(renderingContext: CanvasRenderingContext2D): void;
}

export function NewStroke(pdfLineColor: number = DefaultAnnotationColor.pdfColor): Stroke {
  return new Stroke(new Path2D(), [], pdfLineColor);
}

export class Stroke implements ReadonlyStroke {
  path: Path2D;
  points: Vector2[];
  pdfLineColor: number;
  canvasColor: string;
  source: StrokeSource | undefined;

  constructor(
    path: Path2D,
    points: Vector2[],
    pdfLineColor: number = DefaultAnnotationColor.pdfColor,
    source: StrokeSource | undefined = undefined
  ) {
    this.path = path;
    this.points = points;
    this.pdfLineColor = pdfLineColor;
    this.canvasColor = pdfColorToCanvasColor(pdfLineColor);
    this.source = source;
  }

  public stroke(renderingContext: CanvasRenderingContext2D): void {
    renderingContext.strokeStyle = this.canvasColor;
    renderingContext.stroke(this.path);
  }
}

export interface History {
  path: ReadonlyStroke;
  mode: 'add' | 'erase';
  pageIndex: number;
}

/** 光栅化「预览档」缩放，用于快速首帧；须小于 MIN_RENDER_SCALE */
export const PREVIEW_RENDER_SCALE: number = 2;
/** 与 PDF 页面坐标一致的布局倍率（页面框在 vp 中的尺度），与光栅 renderScale 无关 */
export const DISPLAY_LAYOUT_SCALE: number = 2;
/** 阅读器默认可用光栅档位下限（与 PDFViewerViewModel.ViewerMinRenderScale 对齐） */
export const MIN_RENDER_SCALE: number = 6;

export interface PageCache {
  pixelMap: PixelMap;
  renderScale: number;
  baseSize: Vector2; // 原始页面大小（无缩放）
  /** 布局用页面框尺寸（与 DISPLAY_LAYOUT_SCALE 一致），与光栅 renderScale 无关 */
  displaySize: Vector2;
}

/** 在 TaskPool 工作线程中探测区间内含折线批注的页（避免主线程对每页调用 getPage）。 */
@Concurrent
function probePdfPolylineAnnotationPages(
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
function cachePage(documentPath: string, documentIndex: number, renderScale: number, openPassword: string): PageCache {

  const document = new pdfService.PdfDocument();
  const result = document.loadDocument(documentPath, openPassword);
  if (result != pdfService.ParseResult.PARSE_SUCCESS) {
    throw new Error(`加载文档失败: ${result}`);
  }

  try {
    const page = document.getPage(documentIndex);

    const baseSize = Vec2(page.getWidth(), page.getHeight());
    const renderSize = mul(baseSize, renderScale);
    const matrix = new pdfService.PdfMatrix();
    matrix.x = 0;
    matrix.y = 0;
    matrix.width = renderSize.x;
    matrix.height = renderSize.y;
    matrix.rotate = 0;
    const pixelMap = page.getCustomPagePixelMap(matrix, false, true);

    // 布局倍率固定为 2，与模块常量 DISPLAY_LAYOUT_SCALE 一致（@Concurrent 内不可用模块级常量）
    const displaySize = mul(baseSize, 2);

    return {
      pixelMap: pixelMap,
      renderScale: renderScale,
      baseSize: baseSize,
      displaySize: displaySize
    };
  } finally {
    // 释放文档以避免内存泄漏 - 每次 cachePage 调用都会创建新的 PdfDocument
    document.releaseDocument();
  }
}

export interface ReadonlyPageInfo {
  readonly globalPageIndex: number | undefined;
  readonly localPageIndex: number;
  readonly strokes: readonly ReadonlyStroke[];
  readonly pageThumbnail: image.PixelMap | undefined;
  retainThumbnail(preferredSize: Vector2): void;
}

interface PendingCacheTask {
  task: taskpool.Task;
  promise: Promise<PageCache>;
}

interface PendingThumbnailTask {
  task: taskpool.Task;
  promise: Promise<void>;
}

@Observed
export class PageInfo implements ReadonlyPageInfo {
  public readonly pageGuid: string = util.generateRandomUUID(true);
  public globalPageIndex: number | undefined;
  public localPageIndex: number;
  private _pdfPage: pdfService.PdfPage | undefined = undefined;
  private pdfDocument: pdfService.PdfDocument;
  public strokes: Stroke[] = [];
  private caches: Map<number, PageCache> = new Map();
  private pendingTasks: Map<number, PendingCacheTask> = new Map();
  private pagePath: string;
  private openPassword: string;
  private importedPdfPolylineSources: ImportedPdfPolylineStrokeSource[] = [];
  private pdfLinks: PdfLinkAnnotation[] | undefined = undefined;
  public pageThumbnail: image.PixelMap | undefined = undefined;
  private pageThumbnailTask: PendingThumbnailTask | undefined = undefined;
  private thumbnailRefCount: number = 0;
  public associatedSource: PageStore | undefined = undefined;

  public get pdfPage(): pdfService.PdfPage {
    if (!this._pdfPage) {
      this._pdfPage = this.pdfDocument.getPage(this.localPageIndex);
    }
    return this._pdfPage;
  }

  /** 文档从磁盘重载后清除缓存的 PdfPage 句柄。 */
  public resetPdfPageHandle(): void {
    this._pdfPage = undefined;
    this.pdfLinks = undefined;
  }

  constructor(
    localPageIndex: number,
    pdfDocument: pdfService.PdfDocument,
    pagePath: string,
    openPassword: string = ''
  ) {
    this.localPageIndex = localPageIndex;
    this.pdfDocument = pdfDocument;
    this.pagePath = pagePath;
    this.openPassword = openPassword;
  }

  public getPageLinks(): PdfLinkAnnotation[] {
    if (this.pdfLinks === undefined) {
      this.pdfLinks = this.extractPageLinks();
    }
    return this.pdfLinks;
  }

  public invalidatePdfLinks(): void {
    this.pdfLinks = undefined;
  }

  private extractPageLinks(): PdfLinkAnnotation[] {
    const links: PdfLinkAnnotation[] = [];
    const annotations = this.pdfPage.getAnnotations();
    let linkAnnotationCount = 0;

    for (const annotation of annotations) {
      if (annotation.type !== pdfService.AnnotationType.LINK) {
        continue;
      }
      linkAnnotationCount++;

      try {
        const annotationInfo = annotation.getAnnotationInfo() as pdfService.LinkAnnotationInfo;
        const rect = this.normalizeLinkRectangle(annotationInfo);
        if (rect === undefined) {
          hilog.warn(0, 'PDFView', `PDF 链接批注矩形无效: page=${this.localPageIndex}, uniqueId=${annotation.uniqueId}`);
          continue;
        }

        const target = this.normalizeLinkTarget(annotationInfo.action);
        const link: PdfLinkAnnotation = {
          rect: rect,
          target: target,
          uniqueId: annotationInfo.uniqueId && annotationInfo.uniqueId.length > 0 ? annotationInfo.uniqueId : annotation.uniqueId,
          highlightMode: annotationInfo.highlightMode,
          color: annotationInfo.color
        };
        links.push(link);
        hilog.info(0, 'PDFView', `PDF 链接批注: page=${this.localPageIndex}, uniqueId=${link.uniqueId ?? ''}, rect=(${rect.left},${rect.bottom},${rect.right},${rect.top}), target=${target.kind}`);
      } catch (error) {
        hilog.warn(0, 'PDFView', `读取页面 ${this.localPageIndex} 链接批注失败: ${error}`);
      }
    }

    hilog.info(0, 'PDFView', `PDF 链接扫描完成: page=${this.localPageIndex}, annotations=${annotations.length}, linkAnnotations=${linkAnnotationCount}, usableLinks=${links.length}`);
    return links;
  }

  private normalizeLinkRectangle(annotationInfo: pdfService.LinkAnnotationInfo): PdfLinkRectangle | undefined {
    if (!Number.isFinite(annotationInfo.left) || !Number.isFinite(annotationInfo.right) ||
      !Number.isFinite(annotationInfo.bottom) || !Number.isFinite(annotationInfo.top)) {
      return undefined;
    }

    return {
      left: Math.min(annotationInfo.left, annotationInfo.right),
      right: Math.max(annotationInfo.left, annotationInfo.right),
      bottom: Math.min(annotationInfo.bottom, annotationInfo.top),
      top: Math.max(annotationInfo.bottom, annotationInfo.top)
    };
  }

  private normalizeLinkTarget(action: pdfService.PdfAction | undefined): PdfLinkTarget {
    if (action === undefined) {
      return { kind: 'unknown' };
    }

    if (action.type === pdfService.PdfActionType.GOTO) {
      return this.normalizeGoToLinkTarget(action as pdfService.PdfActionGoTo);
    }

    if (action.type === pdfService.PdfActionType.HYPERLINK) {
      const hyperlinkAction = action as pdfService.PdfActionHyperlink;
      if (hyperlinkAction.hyperlink === undefined || hyperlinkAction.hyperlink.length === 0) {
        return { kind: 'unknown', actionType: action.type };
      }
      return {
        kind: 'uri',
        uri: hyperlinkAction.hyperlink
      };
    }

    return { kind: 'unknown', actionType: action.type };
  }

  private normalizeGoToLinkTarget(action: pdfService.PdfActionGoTo): PdfLinkTarget {
    const destInfo = action.destInfo;
    if (destInfo === undefined || !Number.isFinite(destInfo.pageIndex)) {
      return { kind: 'unknown', actionType: action.type };
    }

    return {
      kind: 'gotoPage',
      pageIndex: destInfo.pageIndex,
      destination: this.cloneDestInfo(destInfo)
    };
  }

  private cloneDestInfo(destInfo: pdfService.DestInfo): PdfLinkDestination {
    const destination: PdfLinkDestination = {
      pageIndex: destInfo.pageIndex,
      fitMode: destInfo.fitMode
    };

    if (destInfo.left !== undefined && Number.isFinite(destInfo.left)) {
      destination.left = destInfo.left;
    }
    if (destInfo.top !== undefined && Number.isFinite(destInfo.top)) {
      destination.top = destInfo.top;
    }
    if (destInfo.right !== undefined && Number.isFinite(destInfo.right)) {
      destination.right = destInfo.right;
    }
    if (destInfo.bottom !== undefined && Number.isFinite(destInfo.bottom)) {
      destination.bottom = destInfo.bottom;
    }
    if (destInfo.zoom !== undefined && Number.isFinite(destInfo.zoom)) {
      destination.zoom = destInfo.zoom;
    }

    return destination;
  }

  public retainThumbnail(preferredSize: Vector2): void {
    // Increment reference count for this thumbnail request
    this.thumbnailRefCount++;

    if (this.pageThumbnail) return;
    if (this.pageThumbnailTask) return;

    const pageSize = Vec2(this.pdfPage.getWidth(), this.pdfPage.getHeight());
    const scaleX = preferredSize.x / pageSize.x;
    const scaleY = preferredSize.y / pageSize.y;
    const scale = Math.min(scaleX, scaleY);
    const task = new taskpool.Task(cachePage, this.pagePath, this.localPageIndex, scale, this.openPassword);
    const promise = taskpool.execute(task, taskpool.Priority.LOW)
      .then(result => {
        const pageCache = result as PageCache;
        this.pageThumbnail = pageCache.pixelMap;
        this.pageThumbnailTask = undefined;
        if (!this.associatedSource || !this.globalPageIndex) return;
        this.associatedSource.markPageChanged(this.globalPageIndex);
      })
      .catch((error: Error) => {
        this.pageThumbnailTask = undefined;
        hilog.error(0, 'PDFView', `生成页面 ${this.localPageIndex} 缩略图失败: ${error.message}`);
        throw error;
      });
    this.pageThumbnailTask = { task, promise };
    return;
  }

  /**
   * Ensures the page is cached at the specified render scale.
   * If already cached or caching is in progress, this is a no-op.
   */
  public ensureCached(
    renderScale: number,
    priority: taskpool.Priority
  ): Promise<PageCache> | undefined {
    if (this.caches.has(renderScale) || this.pendingTasks.has(renderScale)) {
      return undefined;
    }
    return this.startNewCacheTask(renderScale, priority);
  }

  /**
   * 若已有缓存或正在加载则返回对应 Promise；否则启动任务并返回其 Promise。
   */
  private resolveOrStartCacheTask(renderScale: number, priority: taskpool.Priority): Promise<PageCache> {
    const cached = this.caches.get(renderScale);
    if (cached !== undefined) {
      return Promise.resolve(cached);
    }
    const pending = this.pendingTasks.get(renderScale);
    if (pending !== undefined) {
      return pending.promise;
    }
    return this.startNewCacheTask(renderScale, priority);
  }

  private startNewCacheTask(renderScale: number, priority: taskpool.Priority): Promise<PageCache> {
    const task = new taskpool.Task(cachePage, this.pagePath, this.localPageIndex, renderScale, this.openPassword);
    const promise = taskpool.execute(task, priority)
      .then(result => {
        const pageCache = result as PageCache;
        this.caches.set(renderScale, pageCache as PageCache);
        this.pendingTasks.delete(renderScale);
        if (renderScale === PREVIEW_RENDER_SCALE && this.associatedSource !== undefined &&
          this.globalPageIndex !== undefined) {
          this.associatedSource.notifyPreviewCacheFilled(this.globalPageIndex);
        }
        return pageCache as PageCache;
      })
      .catch((error: Error) => {
        this.pendingTasks.delete(renderScale);
        hilog.error(0, 'PDFView', `在缩放 ${renderScale} 下缓存页面 ${this.localPageIndex} 失败: ${error.message}`);
        throw error;
      });

    this.pendingTasks.set(renderScale, { task, promise });
    return promise as Promise<PageCache>;
  }

  /**
   * Cancels all pending cache tasks.
   */
  public cancelPendingTasks(): void {
    for (const pendingTask of this.pendingTasks.values()) {
      try {
        taskpool.cancel(pendingTask.task);
      } catch (_error) {
        // Task may have already completed or been cancelled.
      }
    }
    this.pendingTasks.clear();
  }

  private cancelPendingWhere(predicate: (scale: number) => boolean): void {
    const scales: number[] = [];
    for (const pair of this.pendingTasks.entries()) {
      if (predicate(pair[0])) {
        scales.push(pair[0]);
      }
    }
    for (const scale of scales) {
      const pendingTask = this.pendingTasks.get(scale);
      if (pendingTask !== undefined) {
        try {
          taskpool.cancel(pendingTask.task);
        } catch (_error) {
        }
        this.pendingTasks.delete(scale);
      }
    }
  }

  /**
   * 释放高于预览档的光栅缓存（保留 PREVIEW_RENDER_SCALE），并取消对应 pending。
   */
  public evictHighResolutionCaches(): void {
    const scalesToRemove: number[] = [];
    for (const pair of this.caches.entries()) {
      if (pair[0] > PREVIEW_RENDER_SCALE) {
        scalesToRemove.push(pair[0]);
      }
    }
    for (const scale of scalesToRemove) {
      const cache = this.caches.get(scale);
      if (cache !== undefined) {
        try {
          cache.pixelMap.release();
        } catch (error) {
          hilog.warn(0, 'PDFView', `释放 PixelMap 时出错: ${error}`);
        }
        this.caches.delete(scale);
      }
    }
    this.cancelPendingWhere((s: number) => s > PREVIEW_RENDER_SCALE);
  }

  /** 仅移除预览档光栅（用于全局预算或内存回收） */
  public evictPreviewRasterOnly(): void {
    const cache = this.caches.get(PREVIEW_RENDER_SCALE);
    if (cache !== undefined) {
      try {
        cache.pixelMap.release();
      } catch (error) {
        hilog.warn(0, 'PDFView', `释放预览 PixelMap 时出错: ${error}`);
      }
      this.caches.delete(PREVIEW_RENDER_SCALE);
    }
    this.cancelPendingWhere((s: number) => s === PREVIEW_RENDER_SCALE);
  }

  public hasPreviewRasterInCache(): boolean {
    return this.caches.has(PREVIEW_RENDER_SCALE);
  }

  /**
   * 释放全部阅读器光栅缓存与 pending（离开文档或内存危急）。
   */
  public evictAllViewerCaches(): void {
    if (this.associatedSource !== undefined && this.globalPageIndex !== undefined) {
      this.associatedSource.clearPreviewLruSlot(this.globalPageIndex);
    }
    for (const cache of this.caches.values()) {
      try {
        cache.pixelMap.release();
      } catch (error) {
        hilog.warn(0, 'PDFView', `释放 PixelMap 时出错: ${error}`);
      }
    }
    this.caches.clear();
    this.cancelPendingTasks();
  }

  /**
   * @deprecated 语义同 evictAllViewerCaches，保留名称以兼容既有调用。
   */
  public evictViewerCache(): void {
    this.evictAllViewerCaches();
  }

  /**
   * Releases a reference to the thumbnail. When the reference count reaches zero,
   * the PixelMap is released and any pending thumbnail task is cancelled.
   * Used to free memory when the thumbnail scrolls out of view.
   */
  public releaseThumbnail(): void {
    // Decrement reference count
    this.thumbnailRefCount--;

    // Only evict when no more references
    if (this.thumbnailRefCount > 0) {
      return;
    }

    // Ensure ref count doesn't go negative
    this.thumbnailRefCount = 0;

    // Cancel pending thumbnail task if any
    if (this.pageThumbnailTask) {
      try {
        taskpool.cancel(this.pageThumbnailTask.task);
      } catch (error) {
        // Task may have already completed or been cancelled.
      }
      this.pageThumbnailTask = undefined;
    }
    
    // Release the thumbnail PixelMap
    if (this.pageThumbnail) {
      try {
        this.pageThumbnail.release();
      } catch (error) {
        hilog.error(0, 'PDFView', `释放缩略图 PixelMap 时出错: ${error}`);
      }
      this.pageThumbnail = undefined;
    }
  }

  /**
   * 取低于 targetScale 的已缓存档位中**质量最高**的一档，用于加载更高档时的占位。
   * 避免同时存在预览与 4x 时误选最低档导致缩放瞬间画面变糊。
   */
  private getBestCachedScaleBelow(targetScale: number): PageCache | undefined {
    let bestScale: number | undefined = undefined;
    let bestCache: PageCache | undefined = undefined;
    for (const pair of this.caches.entries()) {
      const scale = pair[0];
      const cache = pair[1];
      if (scale >= targetScale) {
        continue;
      }
      if (bestScale === undefined || scale > bestScale) {
        bestScale = scale;
        bestCache = cache;
      }
    }
    return bestCache;
  }

  private getLowestRenderScaleCache(): PageCache | undefined {
    let lowestScale: number | undefined = undefined;
    let lowestCache: PageCache | undefined = undefined;
    for (const pair of this.caches.entries()) {
      const scale = pair[0];
      const cache = pair[1];
      if (lowestScale === undefined || scale < lowestScale) {
        lowestScale = scale;
        lowestCache = cache;
      }
    }
    return lowestCache;
  }

  /**
   * Returns an existing preview PixelMap (lowest-res cache or thumbnail) without triggering new work.
   * Used as a placeholder during page transitions to avoid white flashes.
   */
  public getExistingPreview(): PixelMap | undefined {
    const cache = this.getLowestRenderScaleCache();
    if (cache !== undefined) {
      return cache.pixelMap;
    }
    return this.pageThumbnail;
  }

  public invalidateCaches(): void {
    // Release all cached PixelMaps before clearing
    for (const cache of this.caches.values()) {
      try {
        cache.pixelMap.release();
      } catch (error) {
        hilog.warn(0, 'PDFView', `invalidateCaches 释放 PixelMap 时出错: ${error}`);
      }
    }
    this.caches.clear();

    // Cancel pending cache tasks
    this.cancelPendingTasks();

    if (this.associatedSource !== undefined && this.globalPageIndex !== undefined) {
      this.associatedSource.clearPreviewLruSlot(this.globalPageIndex);
    }
  }

  public setPagePath(pagePath: string): void {
    if (this.pagePath === pagePath) {
      return;
    }
    this.pagePath = pagePath;
    this.invalidatePdfLinks();
    this.invalidateCaches();
  }

  public importPdfPolylineAnnotations(uiContext: UIContext, canvasOverSampling: number): number {
    if (this.importedPdfPolylineSources.length > 0) {
      return 0;
    }

    const pageSize = Vec2(this.pdfPage.getWidth(), this.pdfPage.getHeight());
    const canvasSize = pxToVp(mul(pageSize, canvasOverSampling), uiContext);
    const annotations = this.pdfPage.getAnnotations();
    const annotationsToRemove: pdfService.PdfAnnotation[] = [];

    for (const annotation of annotations) {
      if (annotation.type !== pdfService.AnnotationType.POLYLINE) {
        continue;
      }

      const annotationInfo = annotation.getAnnotationInfo() as pdfService.PolylineAnnotationInfo;
      if (annotationInfo.vertexes === undefined || annotationInfo.vertexes.length < 2) {
        continue;
      }

      const source = this.makeImportedPdfPolylineSource(annotation, annotationInfo);
      const stroke = this.makeStrokeFromPdfPolyline(annotationInfo, source, pageSize, canvasSize);
      this.importedPdfPolylineSources.push(source);
      this.strokes.push(stroke);
      annotationsToRemove.push(annotation);
    }

    for (const annotation of annotationsToRemove) {
      this.pdfPage.removeAnnotation(annotation);
    }

    if (annotationsToRemove.length > 0) {
      this.invalidateCaches();
    }
    return annotationsToRemove.length;
  }

  public clearImportedPdfPolylineTracking(): void {
    this.importedPdfPolylineSources = [];
  }

  public restoreImportedPdfPolylineAnnotations(): number {
    if (this.importedPdfPolylineSources.length === 0) {
      return 0;
    }

    for (const source of this.importedPdfPolylineSources) {
      this.pdfPage.addAnnotation(source.annotationInfo);
    }

    const restoredCount = this.importedPdfPolylineSources.length;
    this.strokes = this.strokes.filter((stroke: Stroke) => stroke.source?.kind !== 'importedPdfPolyline');
    this.importedPdfPolylineSources = [];
    this.invalidateCaches();
    return restoredCount;
  }

  public get importedPdfPolylineCount(): number {
    return this.importedPdfPolylineSources.length;
  }

  private makeImportedPdfPolylineSource(
    annotation: pdfService.PdfAnnotation,
    annotationInfo: pdfService.PolylineAnnotationInfo
  ): ImportedPdfPolylineStrokeSource {
    const clonedInfo = this.clonePolylineAnnotationInfo(annotationInfo, annotation.uniqueId);
    return {
      kind: 'importedPdfPolyline',
      uniqueId: annotation.uniqueId,
      annotationInfo: clonedInfo
    };
  }

  private clonePolylineAnnotationInfo(
    annotationInfo: pdfService.PolylineAnnotationInfo,
    fallbackUniqueId: string
  ): pdfService.PolylineAnnotationInfo {
    const clonedInfo = new pdfService.PolylineAnnotationInfo();
    clonedInfo.uniqueId = annotationInfo.uniqueId && annotationInfo.uniqueId.length > 0 ? annotationInfo.uniqueId : fallbackUniqueId;
    clonedInfo.content = annotationInfo.content;
    clonedInfo.modifiedTime = annotationInfo.modifiedTime;
    clonedInfo.border = annotationInfo.border;
    clonedInfo.flag = annotationInfo.flag;
    clonedInfo.title = annotationInfo.title;
    clonedInfo.opacity = annotationInfo.opacity;
    clonedInfo.subject = annotationInfo.subject;
    clonedInfo.creationDate = annotationInfo.creationDate;
    clonedInfo.lineColor = annotationInfo.lineColor;
    clonedInfo.vertexes = annotationInfo.vertexes.map((point: Vector2) => Vec2(point.x, point.y));
    return clonedInfo;
  }

  private makeStrokeFromPdfPolyline(
    annotationInfo: pdfService.PolylineAnnotationInfo,
    source: ImportedPdfPolylineStrokeSource,
    pageSize: Vector2,
    canvasSize: Vector2
  ): Stroke {
    const path = new Path2D();
    const points: Vector2[] = [];

    for (let i = 0; i < annotationInfo.vertexes.length; i++) {
      const pdfPoint = annotationInfo.vertexes[i];
      const point = Vec2(
        (pdfPoint.x / pageSize.x) * canvasSize.x,
        (1 - pdfPoint.y / pageSize.y) * canvasSize.y
      );
      points.push(point);
      if (i === 0) {
        path.moveTo(point.x, point.y);
      } else {
        path.lineTo(point.x, point.y);
      }
    }

    const pdfLineColor = annotationInfo.lineColor ?? DefaultAnnotationColor.pdfColor;
    return new Stroke(path, points, pdfLineColor, source);
  }

  public stroke(renderingContext: CanvasRenderingContext2D): void {
    for (const stroke of this.strokes) {
      stroke.stroke(renderingContext);
    }
  }

  public async getPageCacheAsync(
    renderScale: number,
    onHighResReady?: (cache: PageCache) => void
  ): Promise<PageCache> {
    if (this.associatedSource !== undefined && this.globalPageIndex !== undefined) {
      this.associatedSource.notePageRasterAccess(this.globalPageIndex);
    }

    const cached = this.caches.get(renderScale);
    if (cached !== undefined) {
      return cached;
    }

    const fallback = this.getBestCachedScaleBelow(renderScale);
    if (fallback !== undefined) {
      const targetPriority = renderScale === MIN_RENDER_SCALE ? taskpool.Priority.HIGH : taskpool.Priority.MEDIUM;
      const targetPromise = this.resolveOrStartCacheTask(renderScale, targetPriority);
      if (onHighResReady !== undefined) {
        targetPromise.then((c: PageCache) => {
          onHighResReady(c);
        }).catch((_e: Error) => {
        });
      }
      return fallback;
    }

    if (renderScale > PREVIEW_RENDER_SCALE) {
      const targetPriority = renderScale === MIN_RENDER_SCALE ? taskpool.Priority.HIGH : taskpool.Priority.MEDIUM;
      const targetPromise = this.resolveOrStartCacheTask(renderScale, targetPriority);
      if (onHighResReady !== undefined) {
        targetPromise.then((c: PageCache) => {
          onHighResReady(c);
        }).catch((_e: Error) => {
        });
      }
      await this.resolveOrStartCacheTask(PREVIEW_RENDER_SCALE, taskpool.Priority.HIGH);
      const hiReady = this.caches.get(renderScale);
      if (hiReady !== undefined) {
        return hiReady;
      }
      const pvReady = this.caches.get(PREVIEW_RENDER_SCALE);
      if (pvReady !== undefined) {
        return pvReady;
      }
      return await targetPromise;
    }

    const soloPriority = renderScale === MIN_RENDER_SCALE ? taskpool.Priority.HIGH : taskpool.Priority.MEDIUM;
    return await this.resolveOrStartCacheTask(renderScale, soloPriority);
  }

  get strokesCount(): number {
    return this.strokes.length;
  }
}

export class PageStore implements IDataSource {
  private pages: PageInfo[] = [];
  private listeners: DataChangeListener[] = [];
  /** 最近一次预取中心，供预览池预算与内存回调使用 */
  private lastPrefetchCenterIndex: number = 0;
  private lastPrefetchDisplayed: number[] = [];
  private lastPrefetchWindowRadius: number = 5;
  /** 持有预览光栅的页索引，队尾为最近使用 */
  private previewLru: number[] = [];
  /** 与系统内存压力联动，临时收紧预览池 */
  private previewBudgetMultiplier: number = 1.0;

  private indexInDisplayed(arr: number[], v: number): boolean {
    return arr.indexOf(v) >= 0;
  }

  private maxPreviewSlotsForTotal(totalPages: number): number {
    if (totalPages <= 80) {
      return Math.min(48, totalPages);
    }
    if (totalPages <= 400) {
      return 36;
    }
    if (totalPages <= 1200) {
      return Math.min(32, 24 + Math.floor(totalPages / 120));
    }
    return Math.max(16, Math.min(28, Math.floor(totalPages / 100)));
  }

  private adaptivePrefetchRange(baseRange: number, totalPages: number): number {
    if (totalPages <= 80) {
      return Math.min(baseRange + 2, 8);
    }
    if (totalPages <= 400) {
      return Math.min(baseRange, 5);
    }
    return Math.min(3, baseRange);
  }

  private countPagesWithPreviewCache(): number {
    let n = 0;
    for (const p of this.pages) {
      if (p.hasPreviewRasterInCache()) {
        n++;
      }
    }
    return n;
  }

  private touchPreviewLru(pageIndex: number): void {
    const pos = this.previewLru.indexOf(pageIndex);
    if (pos >= 0) {
      this.previewLru.splice(pos, 1);
    }
    this.previewLru.push(pageIndex);
  }

  private removePreviewLru(pageIndex: number): void {
    const pos = this.previewLru.indexOf(pageIndex);
    if (pos >= 0) {
      this.previewLru.splice(pos, 1);
    }
  }

  /** 预览光栅被释放时同步 LRU（由 PageInfo 全量淘汰等路径调用） */
  public clearPreviewLruSlot(pageIndex: number | undefined): void {
    if (pageIndex === undefined || pageIndex < 0 || pageIndex >= this.pages.length) {
      return;
    }
    this.removePreviewLru(pageIndex);
  }

  private rebuildPreviewLruFromCaches(): void {
    const next: number[] = [];
    for (let i = 0; i < this.pages.length; i++) {
      if (this.pages[i].hasPreviewRasterInCache()) {
        next.push(i);
      }
    }
    this.previewLru = next;
  }

  private isProtectedForPreviewBudget(
    pageIndex: number,
    centerIndex: number,
    displayedPageIndices: number[]
  ): boolean {
    if (this.indexInDisplayed(displayedPageIndices, pageIndex)) {
      return true;
    }
    const r = this.lastPrefetchWindowRadius;
    return Math.abs(pageIndex - centerIndex) <= r;
  }

  /**
   * 限制全局预览光栅数量；优先淘汰 LRU 中队首且不在保护带内的页。
   */
  public enforcePreviewBudget(centerIndex: number, displayedPageIndices: number[]): void {
    const total = this.totalPageCount();
    const maxSlots =
      Math.floor(this.maxPreviewSlotsForTotal(total) * this.previewBudgetMultiplier);
    const floorSlots = Math.max(6, Math.min(maxSlots, total));
    let guard = 0;
    while (this.countPagesWithPreviewCache() > floorSlots && guard < total + 16) {
      guard++;
      let evicted = false;
      for (let i = 0; i < this.previewLru.length; i++) {
        const idx = this.previewLru[i];
        if (!this.isProtectedForPreviewBudget(idx, centerIndex, displayedPageIndices)) {
          this.previewLru.splice(i, 1);
          this.pages[idx].evictPreviewRasterOnly();
          evicted = true;
          break;
        }
      }
      if (!evicted) {
        if (!this.evictFurthestNonDisplayedPreview(centerIndex, displayedPageIndices)) {
          break;
        }
      }
    }
  }

  private evictFurthestNonDisplayedPreview(centerIndex: number, displayedPageIndices: number[]): boolean {
    let bestIdx = -1;
    let bestDist = -1;
    for (let p = 0; p < this.pages.length; p++) {
      if (!this.pages[p].hasPreviewRasterInCache()) {
        continue;
      }
      if (this.indexInDisplayed(displayedPageIndices, p)) {
        continue;
      }
      const d = Math.abs(p - centerIndex);
      if (d > bestDist) {
        bestDist = d;
        bestIdx = p;
      }
    }
    if (bestIdx < 0) {
      return false;
    }
    this.removePreviewLru(bestIdx);
    this.pages[bestIdx].evictPreviewRasterOnly();
    return true;
  }

  public notifyPreviewCacheFilled(pageIndex: number): void {
    this.touchPreviewLru(pageIndex);
    this.enforcePreviewBudget(this.lastPrefetchCenterIndex, this.lastPrefetchDisplayed);
  }

  public notePageRasterAccess(pageIndex: number): void {
    if (pageIndex < 0 || pageIndex >= this.pages.length) {
      return;
    }
    if (this.pages[pageIndex].hasPreviewRasterInCache()) {
      this.touchPreviewLru(pageIndex);
    }
  }

  /**
   * 响应系统内存压力（由 UIAbility.onMemoryLevel 经 eventHub 转发，勿在主回调内做重释放）。
   */
  public applyMemoryPressure(
    level: AbilityConstant.MemoryLevel,
    displayedPageIndices: number[],
    currentPageIndex: number
  ): void {
    const center = this.lastPrefetchCenterIndex;
    const displayed =
      displayedPageIndices.length > 0 ? displayedPageIndices.slice() : [currentPageIndex];

    if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_MODERATE) {
      this.previewBudgetMultiplier = 1.0;
      return;
    }

    if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_LOW) {
      this.previewBudgetMultiplier = 0.55;
      for (let i = 0; i < this.pages.length; i++) {
        if (this.indexInDisplayed(displayed, i)) {
          continue;
        }
        this.pages[i].evictHighResolutionCaches();
      }
      this.enforcePreviewBudget(center, displayed);
      return;
    }

    if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_CRITICAL) {
      this.previewBudgetMultiplier = 0.35;
      for (let i = 0; i < this.pages.length; i++) {
        if (this.indexInDisplayed(displayed, i)) {
          this.pages[i].evictHighResolutionCaches();
        } else {
          this.pages[i].evictAllViewerCaches();
        }
      }
      this.rebuildPreviewLruFromCaches();
      this.enforcePreviewBudget(center, displayed);
      return;
    }

    this.previewBudgetMultiplier = 0.5;
    for (let i = 0; i < this.pages.length; i++) {
      if (this.indexInDisplayed(displayed, i)) {
        continue;
      }
      this.pages[i].evictHighResolutionCaches();
    }
    this.enforcePreviewBudget(center, displayed);
  }

  public totalCount(): number {
    return this.pages.length;
  }

  public totalPageCount(): number {
    return this.pages.length;
  }

  public getData(index: number): PageInfo {
    return this.pages[index];
  }

  public registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  public unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  public push(pageInfo: PageInfo): void {
    this.pages.push(pageInfo);
    pageInfo.associatedSource = this;
    // Removed eager caching - pages will be cached on-demand via prefetchPagesAround()
    pageInfo.globalPageIndex = this.pages.length - 1;
    this.listeners.forEach(listener => listener.onDataAdd(this.pages.length - 1));
  }

  private getPageInfo(pageIndex: number): PageInfo {
    if (pageIndex < 0 || pageIndex >= this.pages.length) {
      throw new Error(`PageInfo not found for index ${pageIndex}`);
    }
    return this.pages[pageIndex] as PageInfo;
  }

  public ensureCached(
    index: number,
    renderScale: number,
    priority: taskpool.Priority): Promise<PageCache> | undefined {
    return this.getPageInfo(index).ensureCached(renderScale, priority);
  }

  /**
   * Prefetches pages around the center index and evicts caches for distant pages.
   * @param centerIndex The current page index being viewed
   * @param prefetchRange Number of pages to prefetch on each side (default: 3)
   * @param evictionRange Pages beyond this range will have their viewer caches evicted (default: 5)
   */
  public prefetchPagesAround(
    centerIndex: number,
    prefetchRange: number = 3,
    evictionRange: number = 5,
    displayedPageIndices: number[] = []
  ): void {
    const totalPages = this.totalPageCount();
    if (totalPages <= 0) {
      return;
    }
    const clampedCenter = Math.max(0, Math.min(centerIndex, totalPages - 1));
    this.lastPrefetchCenterIndex = clampedCenter;
    this.lastPrefetchDisplayed = displayedPageIndices.slice();
    this.lastPrefetchWindowRadius = Math.max(prefetchRange, 4);

    const adaptiveRange = this.adaptivePrefetchRange(prefetchRange, totalPages);

    for (let offset = -adaptiveRange; offset <= adaptiveRange; offset++) {
      const pageIndex = clampedCenter + offset;
      if (pageIndex < 0 || pageIndex >= totalPages) {
        continue;
      }
      const absOff = Math.abs(offset);
      const renderPriority = offset === 0 ? taskpool.Priority.HIGH : taskpool.Priority.MEDIUM;
      const previewPriority =
        absOff === 0 ? taskpool.Priority.HIGH :
          (absOff <= 1 ? taskpool.Priority.MEDIUM : taskpool.Priority.LOW);

      try {
        this.getPageInfo(pageIndex).ensureCached(PREVIEW_RENDER_SCALE, previewPriority);
        this.getPageInfo(pageIndex).ensureCached(MIN_RENDER_SCALE, renderPriority);
      } catch (_e) {
      }
    }

    const farFullEvictAt = evictionRange + 3;
    for (let globalIndex = 0; globalIndex < this.pages.length; globalIndex++) {
      const distance = Math.abs(globalIndex - clampedCenter);
      if (distance <= evictionRange || displayedPageIndices.includes(globalIndex)) {
        continue;
      }
      const pageInfo = this.pages[globalIndex];
      if (totalPages > 500 && distance > farFullEvictAt) {
        pageInfo.evictAllViewerCaches();
      } else {
        pageInfo.evictHighResolutionCaches();
      }
    }

    this.enforcePreviewBudget(clampedCenter, displayedPageIndices);
  }

  public async getPageCacheAsync(
    index: number,
    renderScale: number,
    onHighResReady?: (cache: PageCache) => void
  ): Promise<PageCache> {
    return await this.getPageInfo(index).getPageCacheAsync(
      renderScale,
      onHighResReady
    );
  }

  public getPageStrokesCount(index: number): number {
    return this.getPageInfo(index).strokesCount;
  }

  public getPageRawSize(index: number): Vector2 {
    const pageInfo = this.getPageInfo(index);
    return Vec2(pageInfo.pdfPage.getWidth(), pageInfo.pdfPage.getHeight());
  }

  public getPageLinks(pageIndex: number): PdfLinkAnnotation[] {
    return this.getPageInfo(pageIndex).getPageLinks();
  }

  /**
   * Returns an existing preview PixelMap for the page without triggering new work.
   */
  public getExistingPreview(index: number): PixelMap | undefined {
    return this.getPageInfo(index).getExistingPreview();
  }

  public iteratePageStrokes(index: number): Iterable<ReadonlyStroke> {
    return this.getPageInfo(index).strokes;
  }

  public addPdfAnnotations(index: number, annotationInfo: pdfService.PdfAnnotationInfo[]): pdfService.PdfAnnotation[] {
    const pageInfo = this.getPageInfo(index);
    const annotations: pdfService.PdfAnnotation[] = [];
    for (const info of annotationInfo) {
      const annotation = pageInfo.pdfPage.addAnnotation(info);
      annotations.push(annotation);
    }
    pageInfo.invalidatePdfLinks();
    this.markPageChanged(index);
    return annotations;
  }

  public removePdfAnnotations(index: number, annotations: pdfService.PdfAnnotation[]): void {
    const pageInfo = this.getPageInfo(index);
    for (const annotation of annotations) {
      pageInfo.pdfPage.removeAnnotation(annotation);
    }
    pageInfo.invalidatePdfLinks();
    this.markPageChanged(index);
  }

  public stokePage(index: number, renderingContext: CanvasRenderingContext2D) {
    this.getPageInfo(index).stroke(renderingContext);
  }

  public addStroke(index: number, pathWithPoints: Stroke): void {
    this.getPageInfo(index).strokes.push(pathWithPoints);
    this.markPageChanged(index);
  }

  public removeStroke(index: number, pathWithPoints: Stroke): void {
    const pageInfo = this.getPageInfo(index);
    const idx = pageInfo.strokes.indexOf(pathWithPoints);
    if (idx < 0) return;
    pageInfo.strokes.splice(idx, 1);
    this.markPageChanged(index);
  }

  public removeStrokeWhere(pageIndex: number, predicate: (stroke: ReadonlyStroke) => boolean): void {
    const pageInfo = this.getPageInfo(pageIndex);
    const originalLength = pageInfo.strokes.length;
    pageInfo.strokes = pageInfo.strokes.filter(stroke => !predicate(stroke));
    if (pageInfo.strokes.length == originalLength) return;
    this.markPageChanged(pageIndex);
  }

  public clearAllStrokes(): void {
    const changedPageIndices: number[] = [];
    for (let pageIndex = 0; pageIndex < this.pages.length; pageIndex++) {
      if (this.pages[pageIndex].strokes.length > 0) {
        this.pages[pageIndex].strokes = [];
        changedPageIndices.push(pageIndex);
      }
    }

    for (const pageIndex of changedPageIndices) {
      this.listeners.forEach(listener => listener.onDataChange(pageIndex));
    }
  }

  public invalidateCaches(pageIndex: number): void {
    this.getPageInfo(pageIndex).invalidateCaches();
  }

  public setPagePath(pagePath: string): void {
    for (const pageInfo of this.pages) {
      pageInfo.setPagePath(pagePath);
    }
  }

  /**
   * 在 TaskPool 中分批探测含折线批注的页码；主线程仅 await，不执行 getPage。
   */
  public async probePolylineAnnotationPageIndices(
    documentPath: string,
    openPassword: string,
    onBatchComplete?: (processedEnd: number, total: number) => void
  ): Promise<number[]> {
    const total = this.pages.length;
    if (total === 0 || documentPath.length === 0) {
      return [];
    }

    const PROBE_BATCH_SIZE = 64;
    const found: number[] = [];
    for (let start = 0; start < total; start += PROBE_BATCH_SIZE) {
      const end = Math.min(start + PROBE_BATCH_SIZE, total);
      const task = new taskpool.Task(
        probePdfPolylineAnnotationPages,
        documentPath,
        start,
        end,
        openPassword
      );
      try {
        const batchFound = await taskpool.execute(task, taskpool.Priority.MEDIUM) as number[];
        for (let i = 0; i < batchFound.length; i++) {
          found.push(batchFound[i]);
        }
      } catch (error) {
        hilog.error(0, 'PDFView', `探测折线批注页失败 [${start}, ${end}): ${error}`);
        throw new Error(`探测折线批注页失败 [${start}, ${end}): ${error}`);
      }
      onBatchComplete?.(end, total);
      await new Promise<void>((resolve) => {
        setTimeout(resolve, 0);
      });
    }
    return found;
  }

  public importPdfPolylineAnnotations(uiContext: UIContext, canvasOverSampling: number): number[] {
    return this.importPdfPolylineAnnotationsRange(uiContext, canvasOverSampling, 0, this.pages.length);
  }

  /** 按页区间导入 PDF 折线批注，供异步分批扫描大文档时调用。 */
  public importPdfPolylineAnnotationsRange(
    uiContext: UIContext,
    canvasOverSampling: number,
    startPageIndex: number,
    endPageIndex: number
  ): number[] {
    const affectedPageIndices: number[] = [];
    const start = Math.max(0, startPageIndex);
    const end = Math.min(this.pages.length, endPageIndex);
    for (let pageIndex = start; pageIndex < end; pageIndex++) {
      const importedCount = this.pages[pageIndex].importPdfPolylineAnnotations(uiContext, canvasOverSampling);
      if (importedCount > 0) {
        affectedPageIndices.push(pageIndex);
        this.markPageChanged(pageIndex);
      }
    }
    return affectedPageIndices;
  }

  public getImportedPdfPolylinePageIndices(): number[] {
    const pageIndices: number[] = [];
    for (let pageIndex = 0; pageIndex < this.pages.length; pageIndex++) {
      if (this.pages[pageIndex].importedPdfPolylineCount > 0) {
        pageIndices.push(pageIndex);
      }
    }
    return pageIndices;
  }

  public clearImportedPdfPolylineTracking(): void {
    for (const pageInfo of this.pages) {
      pageInfo.clearImportedPdfPolylineTracking();
    }
  }

  public resetAllPdfPageHandles(): void {
    for (const pageInfo of this.pages) {
      pageInfo.resetPdfPageHandle();
    }
  }

  public restoreImportedPdfPolylineAnnotations(): number[] {
    const affectedPageIndices: number[] = [];
    for (let pageIndex = 0; pageIndex < this.pages.length; pageIndex++) {
      const restoredCount = this.pages[pageIndex].restoreImportedPdfPolylineAnnotations();
      if (restoredCount > 0) {
        affectedPageIndices.push(pageIndex);
        this.markPageChanged(pageIndex);
      }
    }
    return affectedPageIndices;
  }

  /**
   * Marks the page at the given global page index as changed.
   * This is used by PageInfo when it needs to notify the data source of changes.
   * @param globalPageIndex The global page index
   */
  public markPageChanged(globalPageIndex: number): void {
    if (globalPageIndex < 0 || globalPageIndex >= this.pages.length) {
      return;
    }
    this.listeners.forEach(listener => listener.onDataChange(globalPageIndex));
  }

}
