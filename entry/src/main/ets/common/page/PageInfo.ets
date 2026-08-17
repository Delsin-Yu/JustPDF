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
  AnnotationLayer,
  AnnotationLayerListItem,
  createDefaultLayer,
  DefaultLayerName,
  isProtectedLayer,
  nextLayerName,
  parseLayerContent
} from './AnnotationLayer';
import {
  MIN_RENDER_SCALE,
  PageCache,
  PREVIEW_RENDER_SCALE,
  releasePageCachePixelMaps
} from './PageRasterCache';
import { PdfRenderSession } from './PdfRenderSession';
import { RasterPriority } from './PdfRenderWorkerProtocol';
import { PageStore } from './PageStore';

export interface ReadonlyPageInfo {
  readonly globalPageIndex: number | undefined;
  readonly localPageIndex: number;
  readonly strokes: readonly ReadonlyStroke[];
  readonly pageThumbnail: image.PixelMap | undefined;
  retainThumbnail(preferredSize: Vector2): void;
}

interface PendingCacheTask {
  requestId: number;
  promise: Promise<PageCache>;
}

interface PendingThumbnailTask {
  requestId: number;
  promise: Promise<void>;
}

function toRasterPriority(priority: taskpool.Priority): RasterPriority {
  if (priority === taskpool.Priority.HIGH) {
    return RasterPriority.HIGH;
  }
  if (priority === taskpool.Priority.LOW) {
    return RasterPriority.LOW;
  }
  return RasterPriority.MEDIUM;
}

@Observed
export class PageInfo implements ReadonlyPageInfo {
  public readonly pageGuid: string = util.generateRandomUUID(true);
  public globalPageIndex: number | undefined;
  public localPageIndex: number;
  private _pdfPage: pdfService.PdfPage | undefined = undefined;
  private pdfDocument: pdfService.PdfDocument;
  public strokes: Stroke[] = [];
  public layers: AnnotationLayer[] = [];
  public activeLayerId: string = '';
  private deletedLayers: AnnotationLayer[] = [];
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
    this.resetLayerCatalog();
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
    const session = PdfRenderSession.getInstance();
    const promise: Promise<void> = (async (): Promise<void> => {
      const handle = await session.renderHandle(this.localPageIndex, scale, RasterPriority.LOW);
      if (this.pageThumbnailTask === undefined) {
        session.cancel(handle.requestId);
        throw new Error('canceled');
      }
      this.pageThumbnailTask.requestId = handle.requestId;
      try {
        const pageCache = await handle.promise;
        this.pageThumbnail = pageCache.pixelMap;
        if (pageCache.layoutPixelMap !== undefined) {
          try {
            pageCache.layoutPixelMap.release();
          } catch (_e) {
          }
        }
        this.pageThumbnailTask = undefined;
        if (this.associatedSource !== undefined && this.globalPageIndex !== undefined) {
          this.associatedSource.markPageChanged(this.globalPageIndex);
        }
      } catch (error) {
        this.pageThumbnailTask = undefined;
        const err = error instanceof Error ? error : new Error('' + error);
        if (err.message !== 'canceled') {
          hilog.error(0, 'PageInfo', '生成页面 ' + this.localPageIndex.toString() +
            ' 缩略图失败: ' + err.message);
        }
        throw err;
      }
    })();
    this.pageThumbnailTask = { requestId: -1, promise: promise };
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
    const session = PdfRenderSession.getInstance();
    const rasterPriority = toRasterPriority(priority);
    const promise: Promise<PageCache> = (async (): Promise<PageCache> => {
      const handle = await session.renderHandle(this.localPageIndex, renderScale, rasterPriority);
      const stillPending = this.pendingTasks.get(renderScale);
      if (stillPending === undefined) {
        session.cancel(handle.requestId);
        throw new Error('canceled');
      }
      stillPending.requestId = handle.requestId;
      try {
        const pageCache = await handle.promise;
        this.caches.set(renderScale, pageCache);
        this.pendingTasks.delete(renderScale);
        if (renderScale === PREVIEW_RENDER_SCALE && this.associatedSource !== undefined &&
          this.globalPageIndex !== undefined) {
          this.associatedSource.notifyPreviewCacheFilled(this.globalPageIndex);
        }
        return pageCache;
      } catch (error) {
        this.pendingTasks.delete(renderScale);
        const err = error instanceof Error ? error : new Error('' + error);
        if (err.message !== 'canceled') {
          hilog.error(0, 'PageInfo', '在缩放 ' + renderScale.toString() + ' 下缓存页面 ' +
            this.localPageIndex.toString() + ' 失败: ' + err.message);
        }
        throw err;
      }
    })();

    this.pendingTasks.set(renderScale, { requestId: -1, promise: promise });
    return promise;
  }

  /**
   * 丢弃已从主机队列取消、或尚未拿到 requestId 的 pending。
   * 飞行中任务保留，避免快速滑回同一页时重复派发。
   */
  public abandonQueuedPending(cancelledRequestIds: number[]): void {
    const scalesToDrop: number[] = [];
    for (const pair of this.pendingTasks.entries()) {
      const scale = pair[0];
      const pendingTask = pair[1];
      if (pendingTask.requestId < 0 || cancelledRequestIds.indexOf(pendingTask.requestId) >= 0) {
        scalesToDrop.push(scale);
      }
    }
    for (let i = 0; i < scalesToDrop.length; i++) {
      this.pendingTasks.delete(scalesToDrop[i]);
    }
  }

  /**
   * Cancels all pending cache tasks.
   */
  public cancelPendingTasks(): void {
    const session = PdfRenderSession.getInstance();
    for (const pendingTask of this.pendingTasks.values()) {
      if (pendingTask.requestId >= 0) {
        session.cancel(pendingTask.requestId);
      }
    }
    this.pendingTasks.clear();
  }

  private cancelPendingWhere(predicate: (scale: number) => boolean): void {
    const session = PdfRenderSession.getInstance();
    const scales: number[] = [];
    for (const pair of this.pendingTasks.entries()) {
      if (predicate(pair[0])) {
        scales.push(pair[0]);
      }
    }
    for (const scale of scales) {
      const pendingTask = this.pendingTasks.get(scale);
      if (pendingTask !== undefined) {
        if (pendingTask.requestId >= 0) {
          session.cancel(pendingTask.requestId);
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
    if (this.pageThumbnailTask !== undefined) {
      if (this.pageThumbnailTask.requestId >= 0) {
        PdfRenderSession.getInstance().cancel(this.pageThumbnailTask.requestId);
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

  public resetLayerCatalog(): void {
    const layer: AnnotationLayer = createDefaultLayer();
    this.layers = [layer];
    this.activeLayerId = layer.id;
    this.deletedLayers = [];
  }

  public findLayer(layerId: string): AnnotationLayer | undefined {
    for (let i = 0; i < this.layers.length; i++) {
      if (this.layers[i].id === layerId) {
        return this.layers[i];
      }
    }
    return undefined;
  }

  public isLayerVisible(layerId: string): boolean {
    if (layerId.length === 0) {
      return this.ensureDefaultLayerPresent().visible;
    }
    const layer: AnnotationLayer | undefined = this.findLayer(layerId);
    if (layer === undefined) {
      return true;
    }
    return layer.visible;
  }

  public isStrokeVisible(stroke: ReadonlyStroke): boolean {
    return this.isLayerVisible(stroke.layerId);
  }

  public ensureDefaultLayerPresent(): AnnotationLayer {
    if (this.layers.length === 0) {
      this.resetLayerCatalog();
    }
    return this.layers[0];
  }

  public ensureLayerForStroke(stroke: Stroke): void {
    if (stroke.layerId.length === 0) {
      stroke.layerId = this.ensureDefaultLayerPresent().id;
      return;
    }
    if (this.findLayer(stroke.layerId) !== undefined) {
      return;
    }
    for (let i = 0; i < this.deletedLayers.length; i++) {
      if (this.deletedLayers[i].id === stroke.layerId) {
        this.layers.push(this.deletedLayers[i]);
        this.deletedLayers.splice(i, 1);
        this.sortLayersInPlace(this.layers);
        return;
      }
    }
    this.layers.push(new AnnotationLayer(stroke.layerId, nextLayerName(this.layers), true, this.layers.length));
  }

  public setActiveLayer(layerId: string): boolean {
    if (this.findLayer(layerId) === undefined) {
      return false;
    }
    if (this.activeLayerId === layerId) {
      return false;
    }
    this.activeLayerId = layerId;
    return true;
  }

  public setLayerVisible(layerId: string, visible: boolean): boolean {
    const layer: AnnotationLayer | undefined = this.findLayer(layerId);
    if (layer === undefined) {
      return false;
    }
    if (layer.visible === visible) {
      return false;
    }
    layer.visible = visible;
    return true;
  }

  public addNamedLayer(name: string): AnnotationLayer {
    const trimmed: string = name.trim();
    const layerName: string = trimmed.length > 0 ? trimmed : nextLayerName(this.layers);
    const layer: AnnotationLayer = new AnnotationLayer(
      util.generateRandomUUID(true),
      layerName,
      true,
      this.layers.length
    );
    this.layers.push(layer);
    this.activeLayerId = layer.id;
    return layer;
  }

  public isProtectedLayer(layerId: string): boolean {
    return isProtectedLayer(this.layers, layerId);
  }

  public renameLayer(layerId: string, name: string): boolean {
    const trimmed: string = name.trim();
    if (trimmed.length === 0) {
      return false;
    }
    if (this.isProtectedLayer(layerId)) {
      return false;
    }
    const layer: AnnotationLayer | undefined = this.findLayer(layerId);
    if (layer === undefined) {
      return false;
    }
    layer.name = trimmed;
    return true;
  }

  public deleteLayer(layerId: string): Stroke[] {
    if (this.isProtectedLayer(layerId)) {
      return [];
    }
    const layer: AnnotationLayer | undefined = this.findLayer(layerId);
    if (layer === undefined) {
      return [];
    }
    const removed: Stroke[] = [];
    const kept: Stroke[] = [];
    for (let i = 0; i < this.strokes.length; i++) {
      if (this.strokes[i].layerId === layerId) {
        removed.push(this.strokes[i]);
      } else {
        kept.push(this.strokes[i]);
      }
    }
    this.strokes = kept;
    this.deletedLayers.push(layer);
    const remaining: AnnotationLayer[] = [];
    for (let i = 0; i < this.layers.length; i++) {
      if (this.layers[i].id !== layerId) {
        remaining.push(this.layers[i]);
      }
    }
    this.layers = remaining;
    if (this.layers.length === 0) {
      this.resetLayerCatalog();
    } else if (this.activeLayerId === layerId) {
      this.activeLayerId = this.pickActiveLayerId();
    }
    return removed;
  }

  public toLayerListItems(): AnnotationLayerListItem[] {
    const items: AnnotationLayerListItem[] = [];
    for (let i = 0; i < this.layers.length; i++) {
      const layer: AnnotationLayer = this.layers[i];
      items.push(new AnnotationLayerListItem(
        layer.id,
        layer.name,
        layer.visible,
        layer.order,
        this.countStrokesOnLayer(layer.id),
        layer.id === this.activeLayerId,
        i === 0
      ));
    }
    return items;
  }

  public rebuildLayersFromStrokes(): void {
    const collected: AnnotationLayer[] = [];
    let defaultLayer: AnnotationLayer | undefined = undefined;

    for (let i = 0; i < this.strokes.length; i++) {
      const stroke: Stroke = this.strokes[i];
      const sourceInfo: pdfService.PolylineAnnotationInfo | undefined = this.getImportedSourceInfo(stroke);
      const parsed = sourceInfo !== undefined ? parseLayerContent(sourceInfo.content) : undefined;

      if (parsed !== undefined) {
        stroke.layerId = parsed.layerId;
        if (this.findLayerIn(collected, parsed.layerId) === undefined) {
          let name: string = DefaultLayerName;
          if (sourceInfo !== undefined && sourceInfo.title !== undefined && sourceInfo.title.length > 0) {
            name = sourceInfo.title;
          }
          collected.push(new AnnotationLayer(parsed.layerId, name, parsed.visible, parsed.order));
        }
        continue;
      }

      if (stroke.layerId.length > 0) {
        if (this.findLayerIn(collected, stroke.layerId) === undefined) {
          const previous: AnnotationLayer | undefined = this.findLayer(stroke.layerId);
          if (previous !== undefined) {
            collected.push(new AnnotationLayer(previous.id, previous.name, previous.visible, previous.order));
          } else {
            collected.push(new AnnotationLayer(stroke.layerId, nextLayerName(collected), true, collected.length));
          }
        }
        continue;
      }

      if (defaultLayer === undefined) {
        defaultLayer = createDefaultLayer();
        collected.push(defaultLayer);
      }
      stroke.layerId = defaultLayer.id;
    }

    if (collected.length === 0) {
      this.resetLayerCatalog();
      return;
    }

    const ordered: AnnotationLayer[] = this.placeProtectedDefaultFirst(collected, defaultLayer);
    for (let i = 0; i < ordered.length; i++) {
      ordered[i].order = i;
    }
    this.layers = ordered;
    this.deletedLayers = [];
    this.activeLayerId = this.pickActiveLayerId();
  }

  private countStrokesOnLayer(layerId: string): number {
    let count: number = 0;
    for (let i = 0; i < this.strokes.length; i++) {
      if (this.strokes[i].layerId === layerId) {
        count++;
      }
    }
    return count;
  }

  private pickActiveLayerId(): string {
    if (this.findLayer(this.activeLayerId) !== undefined) {
      return this.activeLayerId;
    }
    for (let i = this.layers.length - 1; i >= 0; i--) {
      if (this.layers[i].visible) {
        return this.layers[i].id;
      }
    }
    return this.layers[this.layers.length - 1].id;
  }

  private findLayerIn(layers: AnnotationLayer[], layerId: string): AnnotationLayer | undefined {
    for (let i = 0; i < layers.length; i++) {
      if (layers[i].id === layerId) {
        return layers[i];
      }
    }
    return undefined;
  }

  private sortLayersInPlace(layers: AnnotationLayer[]): void {
    layers.sort((left: AnnotationLayer, right: AnnotationLayer) => {
      return left.order - right.order;
    });
  }

  private placeProtectedDefaultFirst(
    collected: AnnotationLayer[],
    defaultLayer: AnnotationLayer | undefined
  ): AnnotationLayer[] {
    let protectedLayer: AnnotationLayer | undefined = defaultLayer;
    if (protectedLayer === undefined) {
      for (let i = 0; i < collected.length; i++) {
        if (collected[i].name === DefaultLayerName) {
          protectedLayer = collected[i];
          break;
        }
      }
    }
    if (protectedLayer === undefined) {
      protectedLayer = createDefaultLayer();
    } else {
      protectedLayer.name = DefaultLayerName;
    }
    const ordered: AnnotationLayer[] = [protectedLayer];
    this.sortLayersInPlace(collected);
    for (let i = 0; i < collected.length; i++) {
      if (collected[i].id !== protectedLayer.id) {
        ordered.push(collected[i]);
      }
    }
    return ordered;
  }

  private getImportedSourceInfo(stroke: ReadonlyStroke): pdfService.PolylineAnnotationInfo | undefined {
    if (stroke.source === undefined || stroke.source.kind !== 'importedPdfPolyline') {
      return undefined;
    }
    return stroke.source.annotationInfo;
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
    this.rebuildLayersFromStrokes();
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
    this.rebuildLayersFromStrokes();
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
    const parsed = parseLayerContent(annotationInfo.content);
    const layerId: string = parsed !== undefined ? parsed.layerId : '';
    return new Stroke(path, points, pdfLineColor, source, layerId);
  }

  public stroke(renderingContext: CanvasRenderingContext2D): void {
    const orderedLayers: AnnotationLayer[] = [];
    for (let i = 0; i < this.layers.length; i++) {
      orderedLayers.push(this.layers[i]);
    }
    this.sortLayersInPlace(orderedLayers);
    const defaultLayerId: string = this.ensureDefaultLayerPresent().id;

    for (let i = 0; i < orderedLayers.length; i++) {
      const layer: AnnotationLayer = orderedLayers[i];
      if (!layer.visible) {
        continue;
      }
      for (let j = 0; j < this.strokes.length; j++) {
        const stroke: Stroke = this.strokes[j];
        if (this.strokeBelongsToLayer(stroke, layer.id, defaultLayerId)) {
          stroke.stroke(renderingContext);
        }
      }
    }

    for (let j = 0; j < this.strokes.length; j++) {
      const stroke: Stroke = this.strokes[j];
      if (stroke.layerId.length > 0 && this.findLayer(stroke.layerId) === undefined) {
        stroke.stroke(renderingContext);
      }
    }
  }

  private strokeBelongsToLayer(stroke: ReadonlyStroke, layerId: string, defaultLayerId: string): boolean {
    if (stroke.layerId === layerId) {
      return true;
    }
    return stroke.layerId.length === 0 && layerId === defaultLayerId;
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

  public hasUnsavedStrokeEdits(): boolean {
    let importedRemaining: number = 0;
    for (let i = 0; i < this.strokes.length; i++) {
      const source = this.strokes[i].source;
      if (source !== undefined && source.kind === 'importedPdfPolyline') {
        importedRemaining++;
      } else {
        return true;
      }
    }
    return importedRemaining !== this.importedPdfPolylineSources.length;
  }
}
