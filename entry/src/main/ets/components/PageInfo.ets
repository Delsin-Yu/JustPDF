import { pdfService } from '@kit.PDFKit';
import { Vector2 } from '../components/Numbers';

export interface PathWithPoints {
  path: Path2D;
  points: Vector2[];
}

export interface History {
  path: PathWithPoints;
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

export class PageInfo {
  pageIndex: number;
  pdfPage: pdfService.PdfPage;
  private caches: Map<number, PageCache> = new Map();
  private pendingTasks: Map<number, Promise<PageCache>> = new Map();
  strokes: PathWithPoints[] = [];

  constructor(pageIndex: number, pdfPage: pdfService.PdfPage) {
    this.pageIndex = pageIndex;
    this.pdfPage = pdfPage;
  }

  getCache(renderScale: number): PageCache | undefined {
    return this.caches.get(renderScale);
  }

  setCache(renderScale: number, cache: PageCache): void {
    this.caches.set(renderScale, cache);
  }

  hasCache(renderScale: number): boolean {
    return this.caches.has(renderScale);
  }

  hasPendingTask(renderScale: number): boolean {
    return this.pendingTasks.has(renderScale);
  }

  getPendingTask(renderScale: number): Promise<PageCache> | undefined {
    return this.pendingTasks.get(renderScale);
  }

  setPendingTask(renderScale: number, task: Promise<PageCache>): void {
    this.pendingTasks.set(renderScale, task);
  }

  removePendingTask(renderScale: number): void {
    this.pendingTasks.delete(renderScale);
  }

  getAnyCache(): PageCache | undefined {
    if (this.caches.size > 0) {
      return this.caches.values().next().value;
    }
    return undefined;
  }

  getLowestRenderScaleCache(): PageCache | undefined {
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

  clearCaches(): void {
    this.caches.clear();
  }

  clearPendingTasks(): void {
    this.pendingTasks.clear();
  }
}