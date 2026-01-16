import { pdfService } from '@kit.PDFKit';
import { mul, Vec2, Vector2 } from '../components/Numbers';
import { taskpool } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

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
function cachePage(sandboxPath: string, pageIndex: number, renderScale: number = 2): PageCache {
  const document = new pdfService.PdfDocument();
  const result = document.loadDocument(sandboxPath);
  if (result != pdfService.ParseResult.PARSE_SUCCESS) {
    throw new Error(`加载文档失败: ${result}`);
  }

  const page = document.getPage(pageIndex);
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

}

export class PageInfo implements ReadonlyPageInfo {
  public pageIndex: number;
  public pdfPage: pdfService.PdfPage;
  public strokes: Stroke[] = [];
  private caches: Map<number, PageCache> = new Map();
  private pendingTasks: Map<number, Promise<PageCache>> = new Map();

  constructor(pageIndex: number, pdfPage: pdfService.PdfPage) {
    this.pageIndex = pageIndex;
    this.pdfPage = pdfPage;
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
    sandboxPath: string,
    renderScale: number,
    priority: taskpool.Priority
  ): Promise<PageCache> | undefined {
    // Skip if already cached or has pending task
    if (this.caches.has(renderScale) || this.pendingTasks.has(renderScale)) {
      return undefined;
    }

    const task = new taskpool.Task(cachePage, sandboxPath, this.pageIndex, renderScale);
    const promise = taskpool.execute(task, priority)
      .then(pageCache => {
        this.caches.set(renderScale, pageCache as PageCache);
        this.pendingTasks.delete(renderScale);
        hilog.info(0, 'PDFView', `页面 ${this.pageIndex} 已在缩放 ${renderScale} 下缓存`);
        return pageCache as PageCache;
      })
      .catch((error: Error) => {
        this.pendingTasks.delete(renderScale);
        hilog.error(0, 'PDFView', `在缩放 ${renderScale} 下缓存页面 ${this.pageIndex} 失败: ${error.message}`);
        throw error;
      });

    this.pendingTasks.set(renderScale, promise as Promise<PageCache>);
    return promise as Promise<PageCache>;
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
    sandboxPath: string,
    renderScale: number,
    minRenderScale: number,
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
      return await pendingTask;
    }

    // Get fallback cache (lowest render scale available)
    const fallbackCache = this.getLowestRenderScaleCache();

    // Determine priority based on render scale
    const priority = renderScale === minRenderScale
      ? taskpool.Priority.HIGH
      : taskpool.Priority.MEDIUM;

    // Create and execute the caching task
    const task = new taskpool.Task(cachePage, sandboxPath, this.pageIndex, renderScale);
    const promise = taskpool.execute(task, priority)
      .then(pageCache => {
        this.caches.set(renderScale, pageCache as PageCache);
        this.pendingTasks.delete(renderScale);
        hilog.info(0, 'PDFView', `页面 ${this.pageIndex} 已在缩放 ${renderScale} 下缓存`);
        return pageCache;
      })
      .catch((error: Error) => {
        this.pendingTasks.delete(renderScale);
        hilog.error(0, 'PDFView', `在缩放 ${renderScale} 下缓存页面 ${this.pageIndex} 失败: ${error.message}`);
        throw error;
      });

    this.pendingTasks.set(renderScale, promise as Promise<PageCache>);

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

export class PageInfoDataSource implements IDataSource {
  private list: PageInfo[] = [];
  private listeners: DataChangeListener[] = [];

  public totalCount(): number {
    return this.list.length;
  }

  public getData(index: number): ReadonlyPageInfo {
    return this.list[index];
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
    this.list.push(pageInfo);
    this.listeners.forEach(listener => listener.onDataChange(this.list.length - 1));
  }

  public ensureCached(index: number, sandboxPath: string,
    renderScale: number,
    priority: taskpool.Priority): Promise<PageCache> | undefined {
    const pageInfo = this.list[index];
    return pageInfo.ensureCached(sandboxPath, renderScale, priority);
  }

  public async getPageCacheAsync(
    index: number,
    sandboxPath: string,
    renderScale: number,
    minRenderScale: number,
    onHighResReady?: (cache: PageCache) => void
  ): Promise<PageCache> {
    const pageInfo = this.list[index];
    return await pageInfo.getPageCacheAsync(
      sandboxPath,
      renderScale,
      minRenderScale,
      onHighResReady
    );
  }

  public getPageStrokesCount(index: number): number {
    const pageInfo = this.list[index];
    return pageInfo.strokesCount;
  }

  public getPageRawSize(index: number): Vector2 {
    const pageInfo = this.list[index];
    return Vec2(pageInfo.pdfPage.getWidth(), pageInfo.pdfPage.getHeight());
  }

  public iteratePageStrokes(index: number): Iterable<ReadonlyStroke> {
    const pageInfo = this.list[index];
    return pageInfo.strokes;
  }

  public addPdfAnnotations(index: number, annotationInfo: pdfService.PdfAnnotationInfo[]): pdfService.PdfAnnotation[] {
    const pageInfo = this.list[index];
    const annotations: pdfService.PdfAnnotation[] = [];
    for (const info of annotationInfo) {
      const annotation = pageInfo.pdfPage.addAnnotation(info);
      annotations.push(annotation);
    }
    this.markChanged(index);
    return annotations;
  }

  public removePdfAnnotations(index: number, annotations: pdfService.PdfAnnotation[]): void {
    const pageInfo = this.list[index];
    for (const annotation of annotations) {
      pageInfo.pdfPage.removeAnnotation(annotation);
    }
    this.markChanged(index);
  }

  public stokePage(index: number, renderingContext: CanvasRenderingContext2D) {
    const pageInfo = this.list[index];
    pageInfo.stroke(renderingContext);
  }

  public addStroke(index: number, pathWithPoints: Stroke): void {
    const pageInfo = this.list[index];
    pageInfo.strokes.push(pathWithPoints);
    this.markChanged(index);
  }

  public removeStroke(index: number, pathWithPoints: Stroke): void {
    const pageInfo = this.list[index];
    const idx = pageInfo.strokes.indexOf(pathWithPoints);
    if (idx >= 0) {
      pageInfo.strokes.splice(idx, 1);
      this.markChanged(index);
    }
  }

  public removeStrokeWhere(index: number, predicate: (stroke: ReadonlyStroke) => boolean): void {
    const pageInfo = this.list[index];
    const originalLength = pageInfo.strokes.length;
    pageInfo.strokes = pageInfo.strokes.filter(stroke => !predicate(stroke));
    if (pageInfo.strokes.length !== originalLength) {
      this.markChanged(index);
    }
  }

  public clearAllStrokes(): void {
    for (let i = 0; i < this.list.length; i++) {
      const pageInfo = this.list[i];
      pageInfo.strokes = [];
      this.markChanged(i);
    }
  }

  public invalidateCaches(index: number): void {
    const pageInfo = this.list[index];
    pageInfo.invalidateCaches();
  }

  private markChanged(index: number): void {
    this.listeners.forEach(listener => listener.onDataChange(index));
  }

  public iteratePages(): Iterable<ReadonlyPageInfo> {
    return this.list;
  }
}