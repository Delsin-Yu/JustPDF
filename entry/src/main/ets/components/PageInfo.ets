import { pdfService } from '@kit.PDFKit';
import { mul, Vec2, Vector2 } from '../components/Numbers';
import { taskpool } from '@kit.ArkTS';
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
  page: pdfService.PdfPage;
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
    page: page,
    pixelMap: pixelMap,
    renderScale: renderScale,
    baseSize: baseSize,
    displaySize: displaySize
  };
}

export interface ReadonlyPageInfo {
  readonly globalPageIndex: number | undefined;
  readonly localPageIndex: number;
  readonly pdfPage: pdfService.PdfPage;
  readonly strokes: readonly ReadonlyStroke[];
  readonly pageThumbnail: image.PixelMap | undefined;
  requestPageThumbnail(preferredSize: Vector2): void;
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

@ObservedV2
export class PageInfo implements ReadonlyPageInfo {
  public globalPageIndex: number | undefined;
  public localPageIndex: number;
  public pdfPage: pdfService.PdfPage;
  public strokes: Stroke[] = [];
  private caches: Map<number, PageCache> = new Map();
  private pendingTasks: Map<number, PendingCacheTask> = new Map();
  private pagePath: string;
  @Trace public pageThumbnail: image.PixelMap | undefined = undefined;
  private pageThumbnailTask: PendingThumbnailTask | undefined = undefined;
  public associatedSource: PageInfoDataSource | undefined = undefined;

  constructor(localPageIndex: number, pdfPage: pdfService.PdfPage, pagePath: string) {
    this.localPageIndex = localPageIndex;
    this.pdfPage = pdfPage;
    this.pagePath = pagePath;
  }

  public requestPageThumbnail(preferredSize: Vector2): void {
    hilog.warn(0, 'PDFView', `请求页面 ${this.localPageIndex} 缩略图，首选大小: ${preferredSize.x}x${preferredSize.y}`);

    if (this.pageThumbnail) return;
    if (this.pageThumbnailTask) return;

    const pageSize = Vec2(this.pdfPage.getWidth(), this.pdfPage.getHeight());
    const scaleX = preferredSize.x / pageSize.x;
    const scaleY = preferredSize.y / pageSize.y;
    const scale = Math.min(scaleX, scaleY);
    const task = new taskpool.Task(cachePage, this.pagePath, this.localPageIndex, scale);
    hilog.info(0, 'PDFView', `开始生成页面 ${this.localPageIndex} 缩略图，缩放比例: ${scale}`);
    const promise = taskpool.execute(task, taskpool.Priority.LOW)
      .then(result => {
        const pageCache = result as PageCache;
        hilog.info(0, 'PDFView', `页面 ${this.localPageIndex} 缩略图已生成 ${scale.toFixed(2)}`);
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
        hilog.debug(0, 'PDFView', `释放 PixelMap 时出错: ${error}`);
      }
    }
    this.caches.clear();
    
    // Cancel pending cache tasks
    this.cancelPendingTasks();
    
    hilog.info(0, 'PDFView', `页面 ${this.localPageIndex} 查看器缓存已清除`);
  }

  /**
   * Evicts the thumbnail, releasing the PixelMap and cancelling any pending thumbnail task.
   * Used to free memory when the thumbnail scrolls out of view.
   */
  public evictThumbnail(): void {
    // Cancel pending thumbnail task if any
    if (this.pageThumbnailTask) {
      try {
        taskpool.cancel(this.pageThumbnailTask.task);
      } catch (error) {
        hilog.debug(0, 'PDFView', `取消缩略图任务时出错: ${error}`);
      }
      this.pageThumbnailTask = undefined;
    }
    
    // Release the thumbnail PixelMap
    if (this.pageThumbnail) {
      try {
        this.pageThumbnail.release();
      } catch (error) {
        hilog.debug(0, 'PDFView', `释放缩略图 PixelMap 时出错: ${error}`);
      }
      this.pageThumbnail = undefined;
    }
    
    hilog.info(0, 'PDFView', `页面 ${this.localPageIndex} 缩略图已清除`);
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

  public invalidateCaches(): void {
    this.caches.clear();
    this.pendingTasks.clear();
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

export interface ReadonlyPageGroup extends IDataSource {
  readonly groupName: string;
  readonly pages: readonly ReadonlyPageInfo[];
}

@ObservedV2
export class PageGroup implements ReadonlyPageGroup {
  public groupName: string;
  public pages: PageInfo[];
  private listeners: DataChangeListener[] = [];

  constructor(groupName: string, pages: PageInfo[]) {
    this.groupName = groupName;
    this.pages = pages;
  }

  totalCount(): number {
    return this.pages.length;
  }

  getData(index: number): PageInfo {
    return this.pages[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  public markAllPagesChanged(): void {
    // hilog.error(0, "PDFView", `标记 PageGroup ${this.groupName} 所有页面为已更改 ${this.listeners.length}`);
    for (let i = 0; i < this.pages.length; i++) {
      this.listeners.forEach(listener => listener.onDataChange(i));
    }
  }

  public markChanged(pageInfo: ReadonlyPageInfo): void {
    const pageIndex = this.pages.indexOf(pageInfo as PageInfo);
    // hilog.error(0, "PDFView", `标记 PageGroup ${this.groupName} 页面 ${pageIndex} 为已更改 ${this.listeners.length}`);
    if (pageIndex >= 0) {
      this.listeners.forEach(listener => listener.onDataChange(pageIndex));
    }
  }
}

export class PageInfoDataSource implements IDataSource {
  private pageGroups: PageGroup[] = [];
  private listeners: DataChangeListener[] = [];

  public totalCount(): number {
    return this.pageGroups.length;
  }

  public totalPageCount(): number {
    let count = 0;
    for (const group of this.pageGroups) {
      count += group.pages.length;
    }
    return count;
  }

  public getData(index: number): PageGroup {
    return this.pageGroups[index];
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

  public push(pageGroup: PageGroup): void {
    this.pageGroups.push(pageGroup);
    // Calculate the starting global page index for this new group
    let pageCounter = 0;
    for (let i = 0; i < this.pageGroups.length - 1; i++) {
      pageCounter += this.pageGroups[i].pages.length;
    }
    for (const pageInfo of pageGroup.pages) {
      pageInfo.associatedSource = this;
      // Removed eager caching - pages will be cached on-demand via prefetchPagesAround()
      pageInfo.globalPageIndex = pageCounter;
      pageCounter++;
    }
    this.listeners.forEach(listener => listener.onDataAdd(this.pageGroups.length - 1));
  }

  private getPageInfo(pageIndex: number): [PageGroup, PageInfo, number] {
    let pageCounter = 0;
    for (let groupIndex = 0; groupIndex < this.pageGroups.length; groupIndex++) {
      const group = this.pageGroups[groupIndex];
      if (pageIndex < pageCounter + group.pages.length) {
        return [group, group.pages[pageIndex - pageCounter] as PageInfo, groupIndex];
      }
      pageCounter += group.pages.length;
    }
    throw new Error(`PageInfo not found for index ${pageIndex}`);
  }

  public ensureCached(
    index: number,
    renderScale: number,
    priority: taskpool.Priority): Promise<PageCache> | undefined {
    const result = this.getPageInfo(index);
    return result[1].ensureCached(renderScale, priority);
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
    evictionRange: number = 5
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
        const result = this.getPageInfo(pageIndex);
        result[1].ensureCached(MIN_RENDER_SCALE, priority);
      } catch (error) {
        hilog.debug(0, 'PDFView', `预取页面 ${pageIndex} 时出错: ${error}`);
      }
    }
    
    // Evict viewer caches for pages outside eviction range
    // Note: Thumbnails are managed separately via evictThumbnail() in PageManagerDialog
    let pageCounter = 0;
    for (const group of this.pageGroups) {
      for (const pageInfo of group.pages) {
        const globalIndex = pageCounter;
        const distance = Math.abs(globalIndex - centerIndex);
        
        if (distance > evictionRange) {
          pageInfo.evictViewerCache();
        }
        
        pageCounter++;
      }
    }
    
    hilog.info(0, 'PDFView', `预取页面 ${centerIndex} 周围 ±${prefetchRange}，清除 ±${evictionRange} 外的缓存`);
  }

  public async getPageCacheAsync(
    index: number,
    renderScale: number,
    onHighResReady?: (cache: PageCache) => void
  ): Promise<PageCache> {
    const result = this.getPageInfo(index);
    return await result[1].getPageCacheAsync(
      renderScale,
      onHighResReady
    );
  }

  public getPageStrokesCount(index: number): number {
    const result = this.getPageInfo(index);
    return result[1].strokesCount;
  }

  public getPageRawSize(index: number): Vector2 {
    const result = this.getPageInfo(index);
    return Vec2(result[1].pdfPage.getWidth(), result[1].pdfPage.getHeight());
  }

  public iteratePageStrokes(index: number): Iterable<ReadonlyStroke> {
    const result = this.getPageInfo(index);
    return result[1].strokes;
  }

  public addPdfAnnotations(index: number, annotationInfo: pdfService.PdfAnnotationInfo[]): pdfService.PdfAnnotation[] {
    const result = this.getPageInfo(index);
    const annotations: pdfService.PdfAnnotation[] = [];
    for (const info of annotationInfo) {
      const annotation = result[1].pdfPage.addAnnotation(info);
      annotations.push(annotation);
    }
    this.notifyPageChanged(result[0], result[1], result[2]);
    return annotations;
  }

  public removePdfAnnotations(index: number, annotations: pdfService.PdfAnnotation[]): void {
    const result = this.getPageInfo(index);
    for (const annotation of annotations) {
      result[1].pdfPage.removeAnnotation(annotation);
    }
    this.notifyPageChanged(result[0], result[1], result[2]);
  }

  public stokePage(index: number, renderingContext: CanvasRenderingContext2D) {
    const result = this.getPageInfo(index);
    result[1].stroke(renderingContext);
  }

  public addStroke(index: number, pathWithPoints: Stroke): void {
    const result = this.getPageInfo(index);
    result[1].strokes.push(pathWithPoints);
    this.notifyPageChanged(result[0], result[1], result[2]);
  }

  public removeStroke(index: number, pathWithPoints: Stroke): void {
    const result = this.getPageInfo(index);
    const idx = result[1].strokes.indexOf(pathWithPoints);
    if (idx < 0) return;
    result[1].strokes.splice(idx, 1);
    this.notifyPageChanged(result[0], result[1], result[2]);
  }

  public removeStrokeWhere(pageIndex: number, predicate: (stroke: ReadonlyStroke) => boolean): void {
    const result = this.getPageInfo(pageIndex);
    const originalLength = result[1].strokes.length;
    result[1].strokes = result[1].strokes.filter(stroke => !predicate(stroke));
    if (result[1].strokes.length == originalLength) return;
    this.notifyPageChanged(result[0], result[1], result[2]);
  }

  public clearAllStrokes(): void {
    // Track which groups actually had strokes cleared
    const changedGroupIndices: number[] = [];
    
    for (let pageGroupIndex = 0; pageGroupIndex < this.pageGroups.length; pageGroupIndex++) {
      const pageGroup = this.pageGroups[pageGroupIndex];
      let groupHadStrokes = false;
      
      for (const page of pageGroup.pages) {
        if (page.strokes.length > 0) {
          page.strokes = [];
          groupHadStrokes = true;
        }
      }
      
      if (groupHadStrokes) {
        changedGroupIndices.push(pageGroupIndex);
      }
    }
    
    // Only notify for groups that actually changed
    for (const groupIndex of changedGroupIndices) {
      this.pageGroups[groupIndex].markAllPagesChanged();
      this.notifyPageGroupChanged(groupIndex);
    }
  }

  public invalidateCaches(pageIndex: number): void {
    const result = this.getPageInfo(pageIndex);
    result[1].invalidateCaches();
  }

  private notifyPageGroupChanged(groupIndex: number): void {
    // hilog.error(0, "PDFView", `通知 PageGroup ${groupIndex} 数据变更 ${this.listeners.length}`);
    this.listeners.forEach(listener => listener.onDataChange(groupIndex));
  }

  /**
   * Notifies both PageGroup and PageInfoDataSource listeners about a page change.
   * This is the preferred method for notifying changes to a specific page.
   * @param group The PageGroup containing the page
   * @param pageInfo The PageInfo that changed
   * @param groupIndex The index of the group in pageGroups
   */
  private notifyPageChanged(group: PageGroup, pageInfo: PageInfo, groupIndex: number): void {
    group.markChanged(pageInfo);
    this.notifyPageGroupChanged(groupIndex);
  }

  /**
   * Marks the page at the given global page index as changed.
   * This is used by PageInfo when it needs to notify the data source of changes.
   * @param globalPageIndex The global page index
   */
  public markPageChanged(globalPageIndex: number): void {
    let pageCounter = 0;
    for (let groupIndex = 0; groupIndex < this.pageGroups.length; groupIndex++) {
      const group = this.pageGroups[groupIndex];
      if (globalPageIndex < pageCounter + group.pages.length) {
        const localPageIndex = globalPageIndex - pageCounter;
        const pageInfo = group.pages[localPageIndex];
        this.notifyPageChanged(group, pageInfo, groupIndex);
        return;
      }
      pageCounter += group.pages.length;
    }
  }
}