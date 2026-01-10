import {
  getCheckIcon,
  MakeSlider,
  StyleButton,
  StyleNumBadgeButton,
  StyleStrBadgeButton,
  StyleText,
  StyleToggle,
  toVisibility
} from './UIComponents';
import { App, window } from '@kit.ArkUI';
import { pdfService } from '@kit.PDFKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HashMap, taskpool } from '@kit.ArkTS';
import { fromArea, mul, toSize, Vec2, Vector2 } from './Numbers';
import { preferences } from '@kit.ArkData';

// Render scale levels - minimum is 2, max 3 levels
const RENDER_SCALE_LEVELS: number[] = [2, 4, 8];
const MIN_RENDER_SCALE: number = 2;
// Thresholds for switching to higher render scale (based on viewScale)
const SCALE_THRESHOLDS: number[] = [1.5, 3.0]; // Switch to level 2 at 1.5x, level 3 at 3.0x

const ContainerSpacing: number = 8;
const ContainerCfg: RowOptions | ColumnOptions = { space: `${ContainerSpacing}px` };
const ContainerPadding: Padding = {
  left: `${ContainerSpacing}px`,
  right: `${ContainerSpacing}px`,
  top: `${ContainerSpacing}px`,
  bottom: `${ContainerSpacing}px`
}
const TopLeft: AlignRuleOption = {
  top: { anchor: '__container__', align: VerticalAlign.Top },
  left: { anchor: '__container__', align: HorizontalAlign.Start },
};
const TopRight: AlignRuleOption = {
  top: { anchor: '__container__', align: VerticalAlign.Top },
  right: { anchor: '__container__', align: HorizontalAlign.End }
}
const FullRect: AlignRuleOption = {
  'top': { 'anchor': '__container__', 'align': VerticalAlign.Top },
  'bottom': { 'anchor': '__container__', 'align': VerticalAlign.Bottom },
  'left': { 'anchor': '__container__', 'align': HorizontalAlign.Start },
  'right': { 'anchor': '__container__', 'align': HorizontalAlign.End },
}
const PageFlipButtonOption: ButtonOptions = { type: ButtonType.Normal }
const PageFlipButtonSize: SizeOptions = { width: '30%', height: '100%' }

@Concurrent
function cachePage(sandboxPath: string, pageIndex: number, renderScale: number = 2): PageCache {
  const document = new pdfService.PdfDocument();
  const result = document.loadDocument(sandboxPath);
  if (result != pdfService.ParseResult.PARSE_SUCCESS) {
    throw new Error(`Failed to load document: ${result}`);
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

  // Display size is always at MIN_RENDER_SCALE (2) for consistent UI sizing
  const displaySize = mul(baseSize, 2);

  return {
    page: page,
    pixelMap: pixelMap,
    renderScale: renderScale,
    baseSize: baseSize,
    displaySize: displaySize
  };
}

interface PageCache {
  page: pdfService.PdfPage;
  pixelMap: PixelMap;
  renderScale: number;
  baseSize: Vector2;    // Original page size without scaling
  displaySize: Vector2; // Size for UI display (always at MIN_RENDER_SCALE)
}

// Helper to create cache key for multi-level caching
function makeCacheKey(pageIndex: number, renderScale: number): string {
  return `${pageIndex}_${renderScale}`;
}

@Entry
@Component
struct PDFView2 {
  private systemPath = '';
  private sandBoxPath = '';
  private mainWindow: window.Window = (AppStorage.get('windowStage') as window.WindowStage).getMainWindowSync();
  private document = new pdfService.PdfDocument();
  private pages: Array<pdfService.PdfPage> = [];
  // Multi-level cache: key is "pageIndex_renderScale"
  private pageCache: HashMap<string, PageCache> = new HashMap<string, PageCache>();
  private pendingTasks: HashMap<string, Promise<Object>> = new HashMap<string, Promise<Object>>();
  private preferences: preferences.Preferences = AppStorage.get('preferences') as preferences.Preferences;
  // Track current render scale level for visible pages
  private currentRenderScale: number = MIN_RENDER_SCALE;
  // Track which pages are currently displayed
  private displayedPageIndices: number[] = [];
  @State view1PixelMap: PixelMap | undefined = undefined;
  @State view2PixelMap: PixelMap | undefined = undefined;
  @State view3PixelMap: PixelMap | undefined = undefined;
  @State view2Visible: boolean = false;
  @State view3Visible: boolean = false;
  @State view1ViewSize: Vector2 = Vec2(0, 0);
  @State view2ViewSize: Vector2 = Vec2(0, 0);
  @State view3ViewSize: Vector2 = Vec2(0, 0);
  @State viewSize: Vector2 = Vec2(0, 0);
  @State currentPageIndex: number = 0;
  @State totalPageCount: number = 0;
  @State pageDisplayMode: 'single' | 'dual' | 'dualContinuous' | 'tri' | 'triContinuous' = 'single';
  @State pageFlipMode: 'side' | 'button' | 'extern' = 'side';
  @State viewPan: Vector2 = Vec2(0, 0);
  @State viewScale: number = 1.0;
  @State viewportSize: Vector2 = Vec2(0, 0);
  @State showControls: boolean = true;
  private lastTouchPoint: Vector2 | undefined = undefined;
  private lastPinchDistance: number | undefined = undefined;
  private lastPinchCenter: Vector2 | undefined = undefined;
  private readonly minScale: number = 0.5;
  private readonly maxScale: number = 9.0;

  aboutToAppear(): void {
    const args = this.getUIContext().getRouter().getParams() as Record<string, string>;
    this.systemPath = args['systemPath'];
    this.sandBoxPath = args['sandboxPath'];
    const result = this.document.loadDocument(this.sandBoxPath);
    if (result != pdfService.ParseResult.PARSE_SUCCESS) {
      hilog.error(0, 'PDFView', `Err on loading pdf file: ${result}`)
      App.terminate();
      return;
    }
    this.totalPageCount = this.document.getPageCount();

    for (let i = 0; i < this.totalPageCount; i++) {
      const page = this.document.getPage(i);
      this.pages.push(page);
    }
    this.gotoPage(0);
    // Start background caching using TaskPool
    this.startBackgroundCaching();
  }

  startBackgroundCaching(): void {
    // Cache pages in the background at minimum scale with lower priority
    for (let i = 0; i < this.totalPageCount; i++) {
      const cacheKey = makeCacheKey(i, MIN_RENDER_SCALE);
      if (!this.pageCache.hasKey(cacheKey) && !this.pendingTasks.hasKey(cacheKey)) {
        const task = new taskpool.Task(cachePage, this.sandBoxPath, i, MIN_RENDER_SCALE);
        const promise = taskpool.execute(task, taskpool.Priority.LOW)
          .then(pageCache => {
            this.pageCache.set(cacheKey, pageCache as PageCache);
            this.pendingTasks.remove(cacheKey);
            hilog.info(0, 'PDFView', `Page ${i} cached at scale ${MIN_RENDER_SCALE}`);
            return pageCache;
          })
          .catch((error: Error) => {
            this.pendingTasks.remove(cacheKey);
            hilog.error(0, 'PDFView', `Failed to cache page ${i}: ${error.message}`);
            throw error;
          });
        this.pendingTasks.set(cacheKey, promise);
      }
    }
  }

  // Determine the appropriate render scale based on current view scale
  getRenderScaleForViewScale(viewScale: number): number {
    if (viewScale > SCALE_THRESHOLDS[1]) {
      return RENDER_SCALE_LEVELS[2]; // 8x
    } else if (viewScale > SCALE_THRESHOLDS[0]) {
      return RENDER_SCALE_LEVELS[1]; // 4x
    }
    return RENDER_SCALE_LEVELS[0]; // 2x (minimum)
  }

  // Check if current displayed pages need re-rendering at a different scale
  async checkAndUpdateRenderScale(): Promise<void> {
    const requiredScale = this.getRenderScaleForViewScale(this.viewScale);
    
    if (requiredScale !== this.currentRenderScale) {
      hilog.info(0, 'PDFView', `Scale change detected: ${this.currentRenderScale} -> ${requiredScale}`);
      this.currentRenderScale = requiredScale;
      // Re-render currently displayed pages at new scale
      await this.updateDisplayedPagesAtScale(requiredScale);
    }
  }

  // Update displayed pages at the specified render scale
  async updateDisplayedPagesAtScale(renderScale: number): Promise<void> {
    for (const pageIndex of this.displayedPageIndices) {
      const cache = await this.getPageCache(pageIndex, renderScale);
      // Update the corresponding view's pixelMap
      const displayIndex = this.displayedPageIndices.indexOf(pageIndex);
      if (displayIndex === 0) {
        this.view1PixelMap = cache.pixelMap;
        this.view1ViewSize = cache.displaySize;
      } else if (displayIndex === 1) {
        this.view2PixelMap = cache.pixelMap;
        this.view2ViewSize = cache.displaySize;
      } else if (displayIndex === 2) {
        this.view3PixelMap = cache.pixelMap;
        this.view3ViewSize = cache.displaySize;
      }
    }
    // Recalculate viewSize based on updated displaySizes
    this.updateViewSize();
  }

  // Update the total viewSize based on current display mode and view sizes
  updateViewSize(): void {
    if (this.pageDisplayMode === 'single') {
      this.viewSize = this.view1ViewSize;
    } else if (this.view3Visible) {
      this.viewSize = Vec2(
        this.view1ViewSize.x + ContainerSpacing + this.view2ViewSize.x + ContainerSpacing + this.view3ViewSize.x,
        Math.max(this.view1ViewSize.y, this.view2ViewSize.y, this.view3ViewSize.y)
      );
    } else if (this.view2Visible) {
      this.viewSize = Vec2(
        this.view1ViewSize.x + ContainerSpacing + this.view2ViewSize.x,
        Math.max(this.view1ViewSize.y, this.view2ViewSize.y)
      );
    } else {
      this.viewSize = this.view1ViewSize;
    }
  }

  async getPageCache(targetIndex: number, renderScale: number = MIN_RENDER_SCALE): Promise<PageCache> {
    const cacheKey = makeCacheKey(targetIndex, renderScale);
    
    // If already cached at requested scale, return immediately
    if (this.pageCache.hasKey(cacheKey)) {
      return this.pageCache.get(cacheKey);
    }

    // If a task is pending for this exact key, wait for it
    if (this.pendingTasks.hasKey(cacheKey)) {
      return await this.pendingTasks.get(cacheKey) as PageCache;
    }

    // Check if we have a lower resolution version to return temporarily
    // while we render the higher resolution in background
    let fallbackCache: PageCache | undefined = undefined;
    for (const scale of RENDER_SCALE_LEVELS) {
      if (scale < renderScale) {
        const fallbackKey = makeCacheKey(targetIndex, scale);
        if (this.pageCache.hasKey(fallbackKey)) {
          fallbackCache = this.pageCache.get(fallbackKey);
        }
      }
    }

    // Create a task for the requested render scale
    const priority = renderScale === MIN_RENDER_SCALE 
      ? taskpool.Priority.HIGH 
      : taskpool.Priority.MEDIUM;
    
    const task = new taskpool.Task(cachePage, this.sandBoxPath, targetIndex, renderScale);
    const promise = taskpool.execute(task, priority)
      .then(pageCache => {
        this.pageCache.set(cacheKey, pageCache as PageCache);
        this.pendingTasks.remove(cacheKey);
        hilog.info(0, 'PDFView', `Page ${targetIndex} cached at scale ${renderScale}`);
        return pageCache;
      })
      .catch((error: Error) => {
        this.pendingTasks.remove(cacheKey);
        hilog.error(0, 'PDFView', `Failed to cache page ${targetIndex} at scale ${renderScale}: ${error.message}`);
        throw error;
      });

    this.pendingTasks.set(cacheKey, promise);
    
    // If we have a fallback, return it immediately and let the higher-res load in background
    if (fallbackCache !== undefined) {
      // Schedule an update when the high-res version is ready
      promise.then((highResCache) => {
        // Update the displayed pixelMap if this page is still visible
        if (this.displayedPageIndices.includes(targetIndex)) {
          const displayIndex = this.displayedPageIndices.indexOf(targetIndex);
          const cache = highResCache as PageCache;
          if (displayIndex === 0) {
            this.view1PixelMap = cache.pixelMap;
          } else if (displayIndex === 1) {
            this.view2PixelMap = cache.pixelMap;
          } else if (displayIndex === 2) {
            this.view3PixelMap = cache.pixelMap;
          }
        }
      });
      return fallbackCache;
    }
    
    return await promise as PageCache;
  }

  async gotoPage(targetIndex: number): Promise<void> {
    if (targetIndex < 0 || targetIndex >= this.totalPageCount) {
      return;
    }

    this.currentPageIndex = targetIndex;
    // Reset render scale when navigating to new page
    this.currentRenderScale = MIN_RENDER_SCALE;

    if (this.pageDisplayMode === 'single') {
      this.displayedPageIndices = [targetIndex];
      const view1Page = await this.getPageCache(targetIndex, this.currentRenderScale);
      this.view1PixelMap = view1Page.pixelMap;
      this.view1ViewSize = view1Page.displaySize;
      this.view2PixelMap = undefined;
      this.view3PixelMap = undefined;
      this.view2Visible = false;
      this.view3Visible = false;
      this.viewSize = view1Page.displaySize;
    } else if (this.pageDisplayMode === 'dual') {
      let index1: number;
      let index2: number | undefined;

      if (targetIndex % 2 === 0) {
        index1 = targetIndex;
        index2 = targetIndex + 1 < this.totalPageCount ? targetIndex + 1 : undefined;
      } else {
        index1 = targetIndex - 1;
        index2 = targetIndex;
      }

      this.displayedPageIndices = index2 !== undefined ? [index1, index2] : [index1];
      const view1Page = await this.getPageCache(index1, this.currentRenderScale);
      this.view1PixelMap = view1Page.pixelMap;
      this.view1ViewSize = view1Page.displaySize;

      if (index2 !== undefined) {
        const view2Page = await this.getPageCache(index2, this.currentRenderScale);
        this.view2PixelMap = view2Page.pixelMap;
        this.view2ViewSize = view2Page.displaySize;
        this.view2Visible = true;
        this.viewSize = Vec2(
          view1Page.displaySize.x + ContainerSpacing + view2Page.displaySize.x,
          Math.max(view1Page.displaySize.y, view2Page.displaySize.y)
        );
      } else {
        this.view2PixelMap = undefined;
        this.view2Visible = false;
        this.viewSize = view1Page.displaySize;
      }
      this.view3PixelMap = undefined;
      this.view3Visible = false;
    } else if (this.pageDisplayMode === 'dualContinuous') {
      this.displayedPageIndices = targetIndex + 1 < this.totalPageCount 
        ? [targetIndex, targetIndex + 1] 
        : [targetIndex];
      const view1Page = await this.getPageCache(targetIndex, this.currentRenderScale);
      this.view1PixelMap = view1Page.pixelMap;
      this.view1ViewSize = view1Page.displaySize;

      if (targetIndex + 1 < this.totalPageCount) {
        const view2Page = await this.getPageCache(targetIndex + 1, this.currentRenderScale);
        this.view2PixelMap = view2Page.pixelMap;
        this.view2ViewSize = view2Page.displaySize;
        this.view2Visible = true;
        this.viewSize = Vec2(
          view1Page.displaySize.x + ContainerSpacing + view2Page.displaySize.x,
          Math.max(view1Page.displaySize.y, view2Page.displaySize.y)
        );
      } else {
        this.view2PixelMap = undefined;
        this.view2Visible = false;
        this.viewSize = view1Page.displaySize;
      }
      this.view3PixelMap = undefined;
      this.view3Visible = false;
    } else if (this.pageDisplayMode === 'tri') {
      let index1: number;
      let index2: number | undefined;
      let index3: number | undefined;

      const groupIndex = Math.floor(targetIndex / 3);
      index1 = groupIndex * 3;
      index2 = index1 + 1 < this.totalPageCount ? index1 + 1 : undefined;
      index3 = index1 + 2 < this.totalPageCount ? index1 + 2 : undefined;

      this.displayedPageIndices = [index1];
      if (index2 !== undefined) this.displayedPageIndices.push(index2);
      if (index3 !== undefined) this.displayedPageIndices.push(index3);

      const view1Page = await this.getPageCache(index1, this.currentRenderScale);
      this.view1PixelMap = view1Page.pixelMap;
      this.view1ViewSize = view1Page.displaySize;

      if (index2 !== undefined) {
        const view2Page = await this.getPageCache(index2, this.currentRenderScale);
        this.view2PixelMap = view2Page.pixelMap;
        this.view2ViewSize = view2Page.displaySize;
        this.view2Visible = true;
      } else {
        this.view2PixelMap = undefined;
        this.view2Visible = false;
      }

      if (index3 !== undefined) {
        const view3Page = await this.getPageCache(index3, this.currentRenderScale);
        this.view3PixelMap = view3Page.pixelMap;
        this.view3ViewSize = view3Page.displaySize;
        this.view3Visible = true;
        this.viewSize = Vec2(
          view1Page.displaySize.x + ContainerSpacing + this.view2ViewSize.x + ContainerSpacing + view3Page.displaySize.x,
          Math.max(view1Page.displaySize.y, this.view2ViewSize.y, view3Page.displaySize.y)
        );
      } else {
        this.view3PixelMap = undefined;
        this.view3Visible = false;
        this.viewSize = Vec2(
          view1Page.displaySize.x + (index2 !== undefined ? ContainerSpacing + this.view2ViewSize.x : 0),
          Math.max(view1Page.displaySize.y, index2 !== undefined ? this.view2ViewSize.y : 0)
        );
      }
    } else if (this.pageDisplayMode === 'triContinuous') {
      this.displayedPageIndices = [targetIndex];
      if (targetIndex + 1 < this.totalPageCount) this.displayedPageIndices.push(targetIndex + 1);
      if (targetIndex + 2 < this.totalPageCount) this.displayedPageIndices.push(targetIndex + 2);

      const view1Page = await this.getPageCache(targetIndex, this.currentRenderScale);
      this.view1PixelMap = view1Page.pixelMap;
      this.view1ViewSize = view1Page.displaySize;

      if (targetIndex + 1 < this.totalPageCount) {
        const view2Page = await this.getPageCache(targetIndex + 1, this.currentRenderScale);
        this.view2PixelMap = view2Page.pixelMap;
        this.view2ViewSize = view2Page.displaySize;
        this.view2Visible = true;
      } else {
        this.view2PixelMap = undefined;
        this.view2Visible = false;
      }

      if (targetIndex + 2 < this.totalPageCount) {
        const view3Page = await this.getPageCache(targetIndex + 2, this.currentRenderScale);
        this.view3PixelMap = view3Page.pixelMap;
        this.view3ViewSize = view3Page.displaySize;
        this.view3Visible = true;
        this.viewSize = Vec2(
          view1Page.displaySize.x + ContainerSpacing + this.view2ViewSize.x + ContainerSpacing + view3Page.displaySize.x,
          Math.max(view1Page.displaySize.y, this.view2ViewSize.y, view3Page.displaySize.y)
        );
      } else {
        this.view3PixelMap = undefined;
        this.view3Visible = false;
        this.viewSize = Vec2(
          view1Page.displaySize.x + (targetIndex + 1 < this.totalPageCount ? ContainerSpacing + this.view2ViewSize.x : 0),
          Math.max(view1Page.displaySize.y, targetIndex + 1 < this.totalPageCount ? this.view2ViewSize.y : 0)
        );
      }
    }

    // Reset view to fit content in viewport
    this.resetViewToFit();
  }

  resetViewToFit(): void {
    // Calculate appropriate scale to fit content in viewport
    this.viewScale = this.calculateFitScale();
    // Reset pan and clamp to ensure content is properly positioned
    this.viewPan = Vec2(0, 0);
    this.clampViewPan();
  }

  calculateFitScale(): number {
    // viewSize is in px units, viewportSize is in px units
    // Calculate scale that fits content within viewport while maintaining aspect ratio
    const uiContext = this.getUIContext();
    const viewSizeVp = Vec2(uiContext.px2vp(this.viewSize.x), uiContext.px2vp(this.viewSize.y));
    const viewportSizeVp = Vec2(uiContext.px2vp(this.viewportSize.x), uiContext.px2vp(this.viewportSize.y));

    // Avoid division by zero
    if (viewSizeVp.x <= 0 || viewSizeVp.y <= 0 || viewportSizeVp.x <= 0 || viewportSizeVp.y <= 0) {
      return 1.0;
    }

    // Calculate scale factors for both dimensions
    const scaleX = viewportSizeVp.x / viewSizeVp.x;
    const scaleY = viewportSizeVp.y / viewSizeVp.y;

    // Use the smaller scale to ensure content fits entirely within viewport
    const fitScale = Math.min(scaleX, scaleY);

    // Clamp to min/max scale limits
    return Math.max(this.minScale, Math.min(this.maxScale, fitScale));
  }

  setPageDisplayMode(value: 'single' | 'dual' | 'dualContinuous' | 'tri' | 'triContinuous') {
    this.pageDisplayMode = value;
    this.gotoPage(this.currentPageIndex);
    try {
      this.preferences.putSync('pageDisplayMode', value);
      this.preferences.flushSync();
    } catch (error) {
      hilog.error(0, 'PDFView', `Err on saving page display mode: ${error}.`);
    }
  }

  setPageFlipMode(value: 'side' | 'button' | 'extern') {
    this.pageFlipMode = value;
    try {
      this.preferences.putSync('pageFlipMode', value);
      this.preferences.flushSync();
    } catch (error) {
      hilog.error(0, 'PDFView', `Err on saving page flip mode: ${error}.`);
    }
  }

  gotoPrevPage(): void {
    if (this.pageDisplayMode === 'single' || this.pageDisplayMode === 'dualContinuous' ||
      this.pageDisplayMode === 'triContinuous') {
      // Navigate one page back
      this.gotoPage(this.currentPageIndex - 1);
    } else if (this.pageDisplayMode === 'dual') {
      // Navigate to previous pair's left page
      const currentPair = Math.floor(this.currentPageIndex / 2);
      const prevPairLeftIndex = Math.max(0, (currentPair - 1) * 2);
      this.gotoPage(prevPairLeftIndex);
    } else if (this.pageDisplayMode === 'tri') {
      // Navigate to previous group's first page
      const currentGroup = Math.floor(this.currentPageIndex / 3);
      const prevGroupFirstIndex = Math.max(0, (currentGroup - 1) * 3);
      this.gotoPage(prevGroupFirstIndex);
    }
  }

  gotoNextPage(): void {
    if (this.pageDisplayMode === 'single' || this.pageDisplayMode === 'dualContinuous' ||
      this.pageDisplayMode === 'triContinuous') {
      // Navigate one page forward
      this.gotoPage(this.currentPageIndex + 1);
    } else if (this.pageDisplayMode === 'dual') {
      // Navigate to next pair's left page
      const currentPair = Math.floor(this.currentPageIndex / 2);
      const nextPairLeftIndex = (currentPair + 1) * 2;
      this.gotoPage(nextPairLeftIndex);
    } else if (this.pageDisplayMode === 'tri') {
      // Navigate to next group's first page
      const currentGroup = Math.floor(this.currentPageIndex / 3);
      const nextGroupFirstIndex = (currentGroup + 1) * 3;
      this.gotoPage(nextGroupFirstIndex);
    }
  }

  clampViewPan(): void {
    // viewPan is in vp units (used by offset() and touch events)
    // viewSize and viewportSize are in px units
    // Convert px to vp for comparison using px2vp
    const uiContext = this.getUIContext();
    const viewSizeVp = Vec2(uiContext.px2vp(this.viewSize.x), uiContext.px2vp(this.viewSize.y));
    const viewportSizeVp = Vec2(uiContext.px2vp(this.viewportSize.x), uiContext.px2vp(this.viewportSize.y));

    // Account for scaling - the actual displayed size is viewSize * viewScale
    const scaledViewSizeVp = Vec2(viewSizeVp.x * this.viewScale, viewSizeVp.y * this.viewScale);

    // If content is smaller than viewport, center it
    // If content is larger than viewport, allow scrolling but clamp to boundaries
    let clampedX = this.viewPan.x;
    let clampedY = this.viewPan.y;

    if (scaledViewSizeVp.x <= viewportSizeVp.x) {
      // Content fits horizontally - center it
      clampedX = (viewportSizeVp.x - scaledViewSizeVp.x) / 2;
    } else {
      // Content is larger - clamp to boundaries
      const minX = -(scaledViewSizeVp.x - viewportSizeVp.x);
      const maxX = 0;
      clampedX = Math.max(minX, Math.min(maxX, this.viewPan.x));
    }

    if (scaledViewSizeVp.y <= viewportSizeVp.y) {
      // Content fits vertically - center it
      clampedY = (viewportSizeVp.y - scaledViewSizeVp.y) / 2;
    } else {
      // Content is larger - clamp to boundaries
      const minY = -(scaledViewSizeVp.y - viewportSizeVp.y);
      const maxY = 0;
      clampedY = Math.max(minY, Math.min(maxY, this.viewPan.y));
    }

    this.viewPan = Vec2(clampedX, clampedY);
  }

  handleViewAction(event: TouchEvent): void {
    const isSingleTouch = event.touches.length === 1 && event.touches[0].id === 0;
    const isDualTouch = event.touches.length === 2 && event.touches[0].id === 0 && event.touches[1].id === 1;
    if (isSingleTouch) {
      const touchPoint = Vec2(event.touches[0].x, event.touches[0].y);
      // Drag the view (this.viewPan)
      if (event.type == TouchType.Down) {
        this.lastTouchPoint = touchPoint;
      } else if (event.type == TouchType.Move) {
        if (this.lastTouchPoint !== undefined) {
          const delta = Vec2(
            touchPoint.x - this.lastTouchPoint.x,
            touchPoint.y - this.lastTouchPoint.y
          );
          this.viewPan = Vec2(
            this.viewPan.x + delta.x,
            this.viewPan.y + delta.y
          );
          this.clampViewPan();
          this.lastTouchPoint = touchPoint;
        }
      } else if (event.type == TouchType.Up) {
        this.lastTouchPoint = undefined;
      }
    } else if (isDualTouch) {
      // Pinch-to-zoom handling
      const touch1 = Vec2(event.touches[0].x, event.touches[0].y);
      const touch2 = Vec2(event.touches[1].x, event.touches[1].y);
      const pinchCenter = Vec2((touch1.x + touch2.x) / 2, (touch1.y + touch2.y) / 2);
      const pinchDistance = Math.sqrt(
        Math.pow(touch2.x - touch1.x, 2) + Math.pow(touch2.y - touch1.y, 2)
      );

      if (event.type == TouchType.Down) {
        // Start of pinch gesture
        this.lastPinchDistance = pinchDistance;
        this.lastPinchCenter = pinchCenter;
      } else if (event.type == TouchType.Move) {
        if (this.lastPinchDistance !== undefined && this.lastPinchCenter !== undefined) {
          // Calculate scale change
          const scaleRatio = pinchDistance / this.lastPinchDistance;
          const newScale = Math.max(this.minScale, Math.min(this.maxScale, this.viewScale * scaleRatio));
          const actualScaleChange = newScale / this.viewScale;

          // To keep the pinch center point stationary on screen:
          // The point under the pinch center before scaling should remain under it after scaling
          // Formula: newPan = pinchCenter - (pinchCenter - oldPan) * scaleChange
          const newPanX = pinchCenter.x - (pinchCenter.x - this.viewPan.x) * actualScaleChange;
          const newPanY = pinchCenter.y - (pinchCenter.y - this.viewPan.y) * actualScaleChange;

          this.viewScale = newScale;
          this.viewPan = Vec2(newPanX, newPanY);
          this.clampViewPan();

          this.lastPinchDistance = pinchDistance;
          this.lastPinchCenter = pinchCenter;
        }
      } else if (event.type == TouchType.Up) {
        this.lastPinchDistance = undefined;
        this.lastPinchCenter = undefined;
        // Check if we need to re-render at a different scale after pinch ends
        this.checkAndUpdateRenderScale();
      }
      // Clear single touch tracking when in pinch mode
      this.lastTouchPoint = undefined;
    } else {
      // Reset all touch tracking
      this.lastTouchPoint = undefined;
      this.lastPinchDistance = undefined;
      this.lastPinchCenter = undefined;
    }
  }

  build() {
    RelativeContainer() {

      Row(ContainerCfg) {
        Image(this.view1PixelMap)
          .size(toSize(this.view1ViewSize))
          .visibility(toVisibility(true))
        Image(this.view2PixelMap)
          .size(toSize(this.view2ViewSize))
          .visibility(toVisibility(this.view2Visible))
        Image(this.view3PixelMap)
          .size(toSize(this.view3ViewSize))
          .visibility(toVisibility(this.view3Visible))
      }
      .alignRules(TopLeft)
      .offset(this.viewPan)
      .size(toSize(this.viewSize))
      .scale({
        x: this.viewScale,
        y: this.viewScale,
        centerX: 0,
        centerY: 0
      })

      Flex()
        .size({ width: '100%', height: '100%' })
        .onAreaChange((_, newVal) => {
          this.viewportSize = fromArea(newVal, this.getUIContext());
          this.resetViewToFit();
        })
        .onTouch(event => this.handleViewAction(event))

      Button(PageFlipButtonOption)
        .size(PageFlipButtonSize)
        .onClick(() => this.gotoPrevPage())
        .alignRules(TopLeft)
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.Transparent)
        .visibility(toVisibility(this.pageFlipMode == 'side'))

      Button(PageFlipButtonOption)
        .size(PageFlipButtonSize)
        .onClick(() => this.gotoNextPage())
        .alignRules(TopRight)
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.Transparent)
        .visibility(toVisibility(this.pageFlipMode == 'side'))

      Row(ContainerCfg) {
        Column(ContainerCfg) {

          StyleButton({
            text: '显示', menuElement: [
              {
                value: "单页",
                action: () => this.setPageDisplayMode('single'),
                symbolIcon: getCheckIcon(this.pageDisplayMode == 'single')
              },
              {
                value: "双页",
                action: () => this.setPageDisplayMode('dual'),
                symbolIcon: getCheckIcon(this.pageDisplayMode == 'dual')
              },
              {
                value: "双页连续",
                action: () => this.setPageDisplayMode('dualContinuous'),
                symbolIcon: getCheckIcon(this.pageDisplayMode == 'dualContinuous')
              },
              {
                value: "三页",
                action: () => this.setPageDisplayMode('tri'),
                symbolIcon: getCheckIcon(this.pageDisplayMode == 'tri')
              },
              {
                value: "三页连续",
                action: () => this.setPageDisplayMode('triContinuous'),
                symbolIcon: getCheckIcon(this.pageDisplayMode == 'triContinuous')
              }]
          })
            .visibility(toVisibility(this.showControls))
          StyleButton({
            text: '模式', menuElement: [
              {
                value: "屏侧翻页",
                action: () => this.setPageFlipMode('side'),
                symbolIcon: getCheckIcon(this.pageFlipMode == 'side')
              },
              {
                value: "按钮翻页",
                action: () => this.setPageFlipMode('button'),
                symbolIcon: getCheckIcon(this.pageFlipMode == 'button')
              },
              {
                value: "外设翻页",
                action: () => this.setPageFlipMode('extern'),
                symbolIcon: getCheckIcon(this.pageFlipMode == 'extern')
              }]
          })
            .visibility(toVisibility(this.showControls))

          Blank()

          StyleButton({ text: '视口', onClickCallback: () => this.resetViewToFit() })
            .visibility(toVisibility(this.showControls))
          StyleButton({ text: '首页', onClickCallback: () => this.gotoPage(0) })
            .visibility(toVisibility(this.showControls))
          StyleButton({ text: '尾页', onClickCallback: () => this.gotoPage(this.totalPageCount - 1) })
            .visibility(toVisibility(this.showControls))
          StyleToggle({
            text: this.showControls ? '收起' : '展开',
            onChangeCallback: value => this.showControls = !value
          })

        }.height('100%')

        Column(ContainerCfg) {

          Blank()

          StyleButton({ text: '拖动' })
            .visibility(toVisibility(this.showControls))
          StyleButton({ text: '绘制' })
            .visibility(toVisibility(this.showControls))
          StyleButton({ text: '擦除' })
            .visibility(toVisibility(this.showControls))

        }.height('100%');

        Blank();

        Column(ContainerCfg) {

          Blank()

          StyleNumBadgeButton({ text: '撤回', count: 1, maxCount: 10 })
            .visibility(toVisibility(this.showControls))
          StyleNumBadgeButton({ text: '重做', count: 2, maxCount: 10 })
            .visibility(toVisibility(this.showControls))
          StyleStrBadgeButton({ text: '保存', badgeText: '!' })
            .visibility(toVisibility(this.showControls))
          StyleButton({ text: '<', onClickCallback: () => this.gotoPrevPage() })
            .visibility(toVisibility(this.pageFlipMode == 'button'))

        }.height('100%');

        Column(ContainerCfg) {

          StyleToggle({ text: '全屏' })
            .visibility(toVisibility(this.showControls))

          Blank()

          MakeSlider(
            {
              value: this.currentPageIndex,
              min: 0,
              max: this.totalPageCount - 1,
              onChangeCallback: newValue => this.gotoPage(newValue)
            }
          )
            .visibility(toVisibility(this.showControls))
          StyleText({ text: `${this.currentPageIndex + 1}/${this.totalPageCount}` })
          StyleButton({ text: '>', onClickCallback: () => this.gotoNextPage() })
            .visibility(toVisibility(this.pageFlipMode == 'button'))

        }.height('100%');
      }
      .alignRules(FullRect)
      .margin(ContainerPadding)
      .hitTestBehavior(HitTestMode.Transparent)

    }.hitTestBehavior(HitTestMode.Transparent)
    .size({ width: '100%', height: '100%' })
    .backgroundColor($r('sys.color.white'))
  }
}