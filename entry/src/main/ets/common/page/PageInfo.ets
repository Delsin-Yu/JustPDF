import { pdfService } from '@kit.PDFKit';
import { mul, pxToVp, Vec2, Vector2 } from '../ui/Numbers';
import { taskpool, util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { DefaultAnnotationColor } from '../../features/annotation/PDFAnnotationColors';
import {
  extractPageLinksFromAnnotations,
  PdfLinkAnnotation
} from './PdfLinks';
import {
  ImportedPdfPolylineStrokeSource,
  ReadonlyStroke,
  Stroke
} from './Stroke';
import {
  cachePage,
  MIN_RENDER_SCALE,
  PageCache,
  PREVIEW_RENDER_SCALE,
  releasePageCachePixelMaps
} from './PageRasterCache';
import { PageStore } from './PageStore';

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
      this.pdfLinks = extractPageLinksFromAnnotations(this.pdfPage.getAnnotations(), this.localPageIndex);
    }
    return this.pdfLinks;
  }

  public invalidatePdfLinks(): void {
    this.pdfLinks = undefined;
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
        hilog.error(0, 'PageInfo', `生成页面 ${this.localPageIndex} 缩略图失败: ${error.message}`);
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
        hilog.error(0, 'PageInfo', `在缩放 ${renderScale} 下缓存页面 ${this.localPageIndex} 失败: ${error.message}`);
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
        releasePageCachePixelMaps(cache);
        this.caches.delete(scale);
      }
    }
    this.cancelPendingWhere((s: number) => s > PREVIEW_RENDER_SCALE);
  }

  /** 仅移除预览档光栅（用于全局预算或内存回收） */
  public evictPreviewRasterOnly(): void {
    const cache = this.caches.get(PREVIEW_RENDER_SCALE);
    if (cache !== undefined) {
      releasePageCachePixelMaps(cache);
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
      releasePageCachePixelMaps(cache);
    }
    this.caches.clear();
    this.cancelPendingTasks();
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
        hilog.error(0, 'PageInfo', `释放缩略图 PixelMap 时出错: ${error}`);
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

  /** 同步窥视已有光栅缓存（不触发新任务） */
  public peekCache(preferredScale: number): PageCache | undefined {
    const exact = this.caches.get(preferredScale);
    if (exact !== undefined) {
      return exact;
    }
    return this.getBestCachedScaleBelow(preferredScale);
  }

  public invalidateCaches(): void {
    // Release all cached PixelMaps before clearing
    for (const cache of this.caches.values()) {
      releasePageCachePixelMaps(cache);
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
