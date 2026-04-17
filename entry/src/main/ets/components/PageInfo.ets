import { pdfService } from '@kit.PDFKit';
import { mul, Vec2, Vector2 } from '../components/Numbers';
import { taskpool, util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';

export interface ReadonlyStroke {
  readonly points: readonly Vector2[];
  stroke(renderingContext: CanvasRenderingContext2D): void;
}

export function NewStroke(): Stroke {
  return new Stroke(new Path2D(), []);
}

export class Stroke implements ReadonlyStroke {
  path: Path2D;
  points: Vector2[];

  constructor(path: Path2D, points: Vector2[]) {
    this.path = path;
    this.points = points;
  }

  public stroke(renderingContext: CanvasRenderingContext2D): void {
    renderingContext.stroke(this.path);
  }
}

export interface History {
  path: ReadonlyStroke;
  mode: 'add' | 'erase';
  pageIndex: number;
}

export interface PageCache {
  pixelMap: PixelMap;
  renderScale: number;
  baseSize: Vector2; // 原始页面大小（无缩放）
  displaySize: Vector2; // UI 显示大小（始终为 MIN_RENDER_SCALE）
}

@Concurrent
function cachePage(documentPath: string, documentIndex: number, renderScale: number = 2): PageCache {

  const document = new pdfService.PdfDocument();
  const result = document.loadDocument(documentPath);
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

    // 显示大小始终为 MIN_RENDER_SCALE (2)，以保持一致的 UI 缩放
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

export const MIN_RENDER_SCALE: number = 4;

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

  constructor(localPageIndex: number, pdfDocument: pdfService.PdfDocument, pagePath: string) {
    this.localPageIndex = localPageIndex;
    this.pdfDocument = pdfDocument;
    this.pagePath = pagePath;
  }

  public retainThumbnail(preferredSize: Vector2): void {
    hilog.warn(0, 'PDFView', `请求页面 ${this.localPageIndex} 缩略图，首选大小: ${preferredSize.x}x${preferredSize.y}`);

    // Increment reference count for this thumbnail request
    this.thumbnailRefCount++;
    hilog.warn(0, 'PDFView', `页面 ${this.localPageIndex} 缩略图引用计数增加到 ${this.thumbnailRefCount}`);

    if (this.pageThumbnail) return;
    if (this.pageThumbnailTask) return;

    const pageSize = Vec2(this.pdfPage.getWidth(), this.pdfPage.getHeight());
    const scaleX = preferredSize.x / pageSize.x;
    const scaleY = preferredSize.y / pageSize.y;
    const scale = Math.min(scaleX, scaleY);
    const task = new taskpool.Task(cachePage, this.pagePath, this.localPageIndex, scale);
    hilog.warn(0, 'PDFView', `开始生成页面 ${this.localPageIndex} 缩略图，缩放比例: ${scale}`);
    const promise = taskpool.execute(task, taskpool.Priority.LOW)
      .then(result => {
        const pageCache = result as PageCache;
        hilog.warn(0, 'PDFView', `页面 ${this.localPageIndex} 缩略图已生成 ${scale.toFixed(2)}`);
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
   * @param sandboxPath Path to the PDF file
   * @param renderScale The render scale to cache at
   * @param priority Task priority (LOW for background, HIGH for immediate)
   * @returns Promise that resolves when caching is complete, or undefined if already cached/pending
   */
  public ensureCached(
    renderScale: number,
    priority: taskpool.Priority
  ): Promise<PageCache> | undefined {
    // Skip if already cached or has pending task
    if (this.caches.has(renderScale) || this.pendingTasks.has(renderScale)) {
      return undefined;
    }

    const task = new taskpool.Task(cachePage, this.pagePath, this.localPageIndex, renderScale);
    const promise = taskpool.execute(task, priority)
      .then(result => {
        const pageCache = result as PageCache;
        this.caches.set(renderScale, pageCache as PageCache);
        this.pendingTasks.delete(renderScale);
        hilog.info(0, 'PDFView', `页面 ${this.localPageIndex} 已在缩放 ${renderScale} 下缓存`);
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
      } catch (error) {
        // Task may have already completed or been cancelled
        hilog.debug(0, 'PDFView', `取消任务时出错: ${error}`);
      }
    }
    this.pendingTasks.clear();
  }

  /**
   * Evicts all viewer caches, releasing PixelMaps and cancelling pending tasks.
   * Used to free memory for pages that are far from the current view.
   */
  public evictViewerCache(): void {
    // Release all cached PixelMaps
    for (const cache of this.caches.values()) {
      try {
        cache.pixelMap.release();
      } catch (error) {
        hilog.warn(0, 'PDFView', `释放 PixelMap 时出错: ${error}`);
      }
    }
    this.caches.clear();
    
    // Cancel pending cache tasks
    this.cancelPendingTasks();
    
    hilog.warn(0, 'PDFView', `页面 ${this.localPageIndex} 查看器缓存已清除`);
  }

  /**
   * Releases a reference to the thumbnail. When the reference count reaches zero,
   * the PixelMap is released and any pending thumbnail task is cancelled.
   * Used to free memory when the thumbnail scrolls out of view.
   */
  public releaseThumbnail(): void {
    // Decrement reference count
    this.thumbnailRefCount--;
    hilog.warn(0, 'PDFView', `页面 ${this.localPageIndex} 缩略图引用计数减少到 ${this.thumbnailRefCount}`);

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
        hilog.error(0, 'PDFView', `取消缩略图任务时出错: ${error}`);
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
    
    hilog.warn(0, 'PDFView', `页面 ${this.localPageIndex} 缩略图已清除`);
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
    // Check if already cached
    const cached = this.caches.get(renderScale);
    if (cached !== undefined) {
      return cached;
    }

    // Check if there's a pending task
    const pendingTask = this.pendingTasks.get(renderScale);
    if (pendingTask !== undefined) {
      return await pendingTask.promise;
    }

    // Get fallback cache (lowest render scale available)
    const fallbackCache = this.getLowestRenderScaleCache();

    // Determine priority based on render scale
    const priority = renderScale === MIN_RENDER_SCALE
      ? taskpool.Priority.HIGH
      : taskpool.Priority.MEDIUM;

    // Create and execute the caching task
    const task = new taskpool.Task(cachePage, this.pagePath, this.localPageIndex, renderScale);
    const promise = taskpool.execute(task, priority)
      .then(result => {
        let pageCache: PageCache = result as PageCache;
        this.caches.set(renderScale, pageCache);
        this.pendingTasks.delete(renderScale);
        hilog.info(0, 'PDFView', `页面 ${this.localPageIndex} 已在缩放 ${renderScale} 下缓存`);
        return pageCache;
      })
      .catch((error: Error) => {
        this.pendingTasks.delete(renderScale);
        hilog.error(0, 'PDFView', `在缩放 ${renderScale} 下缓存页面 ${this.localPageIndex} 失败: ${error.message}`);
        throw error;
      });

    this.pendingTasks.set(renderScale, { task, promise });

    // If we have a fallback cache, return it immediately while high-res loads in background
    if (fallbackCache !== undefined) {
      // Set up callback to update display when high-res is ready
      if (onHighResReady) {
        promise.then((highResCache) => {
          onHighResReady(highResCache as PageCache);
        });
      }
      return fallbackCache;
    }

    // Otherwise wait for the promise to complete
    return await promise as PageCache;
  }

  get strokesCount(): number {
    return this.strokes.length;
  }
}

export class PageStore implements IDataSource {
  private pages: PageInfo[] = [];
  private listeners: DataChangeListener[] = [];

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
    
    // Prefetch pages within range
    for (let offset = -prefetchRange; offset <= prefetchRange; offset++) {
      const pageIndex = centerIndex + offset;
      if (pageIndex < 0 || pageIndex >= totalPages) continue;
      
      // Determine priority: HIGH for center, MEDIUM for adjacent
      const priority = offset === 0
        ? taskpool.Priority.HIGH
        : taskpool.Priority.MEDIUM;
      
      try {
        this.getPageInfo(pageIndex).ensureCached(MIN_RENDER_SCALE, priority);
      } catch (error) {
        hilog.debug(0, 'PDFView', `预取页面 ${pageIndex} 时出错: ${error}`);
      }
    }
    
    // Evict viewer caches for pages outside eviction range
    for (let globalIndex = 0; globalIndex < this.pages.length; globalIndex++) {
      const pageInfo = this.pages[globalIndex];
      const distance = Math.abs(globalIndex - centerIndex);
      if (distance > evictionRange && !displayedPageIndices.includes(globalIndex)) {
        pageInfo.evictViewerCache();
      }
    }
    
    hilog.info(0, 'PDFView', `预取页面 ${centerIndex} 周围 ±${prefetchRange}，清除 ±${evictionRange} 外的缓存`);
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
    this.markPageChanged(index);
    return annotations;
  }

  public removePdfAnnotations(index: number, annotations: pdfService.PdfAnnotation[]): void {
    const pageInfo = this.getPageInfo(index);
    for (const annotation of annotations) {
      pageInfo.pdfPage.removeAnnotation(annotation);
    }
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