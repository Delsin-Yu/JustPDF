import { pdfService } from '@kit.PDFKit';
import { AbilityConstant } from '@kit.AbilityKit';
import { Vec2, Vector2 } from '../ui/Numbers';
import { taskpool } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PageInfo } from './PageInfo';
import { PdfLinkAnnotation } from './PdfLinks';
import { ReadonlyStroke, Stroke } from './Stroke';
import { AnnotationLayer, AnnotationLayerListItem, nextLayerName } from './AnnotationLayer';
import {
  MIN_RENDER_SCALE,
  PageCache,
  PREVIEW_RENDER_SCALE
} from './PageRasterCache';
import {
  MemoryPressurePolicy,
  MemoryPressureSeverity,
  resolveMemoryPressurePolicy
} from './PageMemoryPressure';
import { PdfRenderSession } from './PdfRenderSession';
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
  /** 内存压力下收紧预取半径 */
  private prefetchRangeMultiplier: number = 1.0;
  /** 内存压力下跳过远离中心的预览档预取 */
  private skipDistantPreviewPrefetch: boolean = false;

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
   * 策略按 MemoryLevel（含 API 24 后台档）与 deviceInfo.performanceClass 动态生成。
   */
  public applyMemoryPressure(
    level: AbilityConstant.MemoryLevel,
    displayedPageIndices: number[],
    currentPageIndex: number
  ): void {
    const center = this.lastPrefetchCenterIndex;
    const displayed =
      displayedPageIndices.length > 0 ? displayedPageIndices.slice() : [currentPageIndex];
    const policy: MemoryPressurePolicy = resolveMemoryPressurePolicy(level);

    this.previewBudgetMultiplier = policy.previewBudgetMultiplier;
    this.prefetchRangeMultiplier = policy.prefetchRangeMultiplier;
    this.skipDistantPreviewPrefetch = policy.skipDistantPreviewPrefetch;

    PdfRenderSession.getInstance().applyMemoryPressurePolicy(
      policy.cancelWorkerQueue,
      policy.maxActiveWorkers
    );

    if (policy.severity === MemoryPressureSeverity.NONE) {
      hilog.info(0, 'PageStore', '内存压力恢复：预览预算与预取已放宽');
      return;
    }

    for (let i = 0; i < this.pages.length; i++) {
      const onScreen = this.indexInDisplayed(displayed, i);
      if (onScreen) {
        if (policy.evictDisplayedHighRes) {
          this.pages[i].evictHighResolutionCaches();
        }
      } else if (policy.evictOffscreenAll) {
        this.pages[i].evictAllViewerCaches();
      } else if (policy.evictOffscreenHighRes) {
        this.pages[i].evictHighResolutionCaches();
      }
    }

    if (policy.evictOffscreenAll || policy.evictDisplayedHighRes) {
      this.rebuildPreviewLruFromCaches();
    }
    this.enforcePreviewBudget(center, displayed);
    hilog.info(0, 'PageStore',
      '内存压力淘汰 level=' + level.toString() +
        ' severity=' + policy.severity.toString() +
        ' budget=' + policy.previewBudgetMultiplier.toString() +
        ' maxWorkers=' + policy.maxActiveWorkers.toString());
  }

  /** IDataSource 要求的条目数。 */
  public totalCount(): number {
    return this.pages.length;
  }

  public totalPageCount(): number {
    return this.totalCount();
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
   * 取消不在 keep 集合内的排队光栅，并清掉对应 PageInfo pending。
   * 飞行中任务不取消，完成后仍写入缓存。
   */
  public cancelQueuedPendingExcept(keepPageIndices: number[]): void {
    const cancelledIds = PdfRenderSession.getInstance().cancelQueuedExcept(keepPageIndices);
    for (let i = 0; i < this.pages.length; i++) {
      if (this.indexInDisplayed(keepPageIndices, i)) {
        continue;
      }
      this.pages[i].abandonQueuedPending(cancelledIds);
    }
  }

  /**
   * Prefetches pages around the center index and evicts caches for distant pages.
   * @param centerIndex The current page index being viewed
   * @param prefetchRange Number of pages to prefetch on each side (default: 3)
   * @param evictionRange Pages beyond this range will have their viewer caches evicted (default: 5)
   * @param readingScale 当前阅读档光栅（仅对显示页与近邻全分辨率预取）
   * @param fullResRadius 中心两侧全分辨率半径；更远页只拉预览档
   */
  public prefetchPagesAround(
    centerIndex: number,
    prefetchRange: number = 3,
    evictionRange: number = 5,
    displayedPageIndices: number[] = [],
    readingScale: number = MIN_RENDER_SCALE,
    fullResRadius: number = 1
  ): void {
    const totalPages = this.totalPageCount();
    if (totalPages <= 0) {
      return;
    }
    const clampedCenter = Math.max(0, Math.min(centerIndex, totalPages - 1));
    this.lastPrefetchCenterIndex = clampedCenter;
    this.lastPrefetchDisplayed = displayedPageIndices.slice();
    this.lastPrefetchWindowRadius = Math.max(prefetchRange, 4);

    const scaledPrefetch = Math.max(1, Math.floor(prefetchRange * this.prefetchRangeMultiplier));
    const adaptiveRange = this.adaptivePrefetchRange(scaledPrefetch, totalPages);

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
      const wantFullRes: boolean =
        absOff <= fullResRadius || this.indexInDisplayed(displayedPageIndices, pageIndex);
      const wantPreview: boolean = !this.skipDistantPreviewPrefetch || absOff <= 1 || wantFullRes;

      try {
        if (wantPreview) {
          this.getPageInfo(pageIndex).ensureCached(PREVIEW_RENDER_SCALE, previewPriority);
        }
        if (wantFullRes) {
          this.getPageInfo(pageIndex).ensureCached(readingScale, renderPriority);
        }
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

  public hasUnsavedStrokeEdits(index: number): boolean {
    return this.getPageInfo(index).hasUnsavedStrokeEdits();
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

  /** 同步窥视页面光栅缓存（不触发新任务） */
  public peekPageCache(index: number, preferredScale: number): PageCache | undefined {
    return this.getPageInfo(index).peekCache(preferredScale);
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

  public strokePage(index: number, renderingContext: CanvasRenderingContext2D) {
    this.getPageInfo(index).stroke(renderingContext);
  }

  public addStroke(index: number, pathWithPoints: Stroke): void {
    const pageInfo = this.getPageInfo(index);
    pageInfo.ensureLayerForStroke(pathWithPoints);
    pageInfo.strokes.push(pathWithPoints);
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
      const hadStrokes: boolean = this.pages[pageIndex].strokes.length > 0;
      this.pages[pageIndex].strokes = [];
      this.pages[pageIndex].resetLayerCatalog();
      if (hadStrokes) {
        changedPageIndices.push(pageIndex);
      }
    }

    for (const pageIndex of changedPageIndices) {
      this.listeners.forEach(listener => listener.onDataChange(pageIndex));
    }
  }

  public getPageLayers(pageIndex: number): AnnotationLayer[] {
    return this.getPageInfo(pageIndex).layers;
  }

  public getPageLayer(pageIndex: number, layerId: string): AnnotationLayer | undefined {
    return this.getPageInfo(pageIndex).findLayer(layerId);
  }

  public getPageLayerItems(pageIndex: number): AnnotationLayerListItem[] {
    return this.getPageInfo(pageIndex).toLayerListItems();
  }

  public getActiveLayerId(pageIndex: number): string {
    return this.getPageInfo(pageIndex).activeLayerId;
  }

  public isPageStrokeVisible(pageIndex: number, stroke: ReadonlyStroke): boolean {
    return this.getPageInfo(pageIndex).isStrokeVisible(stroke);
  }

  public setActiveLayer(pageIndex: number, layerId: string): boolean {
    const changed: boolean = this.getPageInfo(pageIndex).setActiveLayer(layerId);
    if (changed) {
      this.markPageChanged(pageIndex);
    }
    return changed;
  }

  public setLayerVisible(pageIndex: number, layerId: string, visible: boolean): boolean {
    const changed: boolean = this.getPageInfo(pageIndex).setLayerVisible(layerId, visible);
    if (changed) {
      this.markPageChanged(pageIndex);
    }
    return changed;
  }

  public addLayer(pageIndex: number, name: string): AnnotationLayer {
    const layer: AnnotationLayer = this.getPageInfo(pageIndex).addNamedLayer(name);
    this.markPageChanged(pageIndex);
    return layer;
  }

  public addDefaultNamedLayer(pageIndex: number): AnnotationLayer {
    const pageInfo = this.getPageInfo(pageIndex);
    return this.addLayer(pageIndex, nextLayerName(pageInfo.layers));
  }

  public renameLayer(pageIndex: number, layerId: string, name: string): boolean {
    const changed: boolean = this.getPageInfo(pageIndex).renameLayer(layerId, name);
    if (changed) {
      this.markPageChanged(pageIndex);
    }
    return changed;
  }

  public deleteLayer(pageIndex: number, layerId: string): Stroke[] {
    const pageInfo = this.getPageInfo(pageIndex);
    if (pageInfo.isProtectedLayer(layerId)) {
      return [];
    }
    const removed: Stroke[] = pageInfo.deleteLayer(layerId);
    this.markPageChanged(pageIndex);
    return removed;
  }

  public ensureActiveLayerVisible(pageIndex: number): boolean {
    const pageInfo = this.getPageInfo(pageIndex);
    const layer: AnnotationLayer | undefined = pageInfo.findLayer(pageInfo.activeLayerId);
    if (layer !== undefined && !layer.visible) {
      layer.visible = true;
      this.markPageChanged(pageIndex);
      return true;
    }
    return false;
  }

  public invalidateCaches(pageIndex: number): void {
    this.getPageInfo(pageIndex).invalidateCaches();
  }

  public setPagePath(pagePath: string): void {
    for (const pageInfo of this.pages) {
      pageInfo.setPagePath(pagePath);
    }
    // 保存/编辑预览可能改写磁盘内容或切换路径，Worker 需 reload
    void PdfRenderSession.getInstance().replace(pagePath).catch((error: Error) => {
      hilog.error(0, 'PageStore', 'PdfRenderSession.replace 失败: ' + error.message);
    });
  }

  /**
   * 在光栅 Worker 中分批探测含折线批注的页码（复用已打开文档，避免反复 loadDocument）。
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

    const session = PdfRenderSession.getInstance();
    if (!session.isDocumentReady()) {
      await session.open(documentPath, openPassword);
    }

    const PROBE_BATCH_SIZE = 64;
    const found: number[] = [];
    for (let start = 0; start < total; start += PROBE_BATCH_SIZE) {
      const end = Math.min(start + PROBE_BATCH_SIZE, total);
      try {
        const batchFound = await session.probePolylines(start, end);
        for (let i = 0; i < batchFound.length; i++) {
          found.push(batchFound[i]);
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : '' + error;
        hilog.error(0, 'PageStore', '探测折线批注页失败 [' + start.toString() + ', ' +
          end.toString() + '): ' + message);
        throw new Error('探测折线批注页失败 [' + start.toString() + ', ' +
          end.toString() + '): ' + message);
      }
      if (onBatchComplete !== undefined) {
        onBatchComplete(end, total);
      }
      await new Promise<void>((resolve: () => void) => {
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
