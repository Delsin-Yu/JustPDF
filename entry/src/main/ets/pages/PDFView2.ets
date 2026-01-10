import {
  ButtonColor,
  ButtonColorSemiTransparent,
  getCheckIcon,
  getCheckIconName,
  MakeSlider,
  StyleButton,
  StyleNumBadgeButton,
  StyleStrBadgeButton,
  StyleText,
  StyleToggle,
  toVisibility
} from './UIComponents';
import { App, LengthMetricsUnit, window } from '@kit.ArkUI';
import { pdfService } from '@kit.PDFKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HashMap, Stack, taskpool } from '@kit.ArkTS';
import { fromArea, mul, pxToVp, toSize, Vec2, Vector2 } from './Numbers';
import { preferences } from '@kit.ArkData';

// Render scale levels - minimum is 2, max 3 levels
const RENDER_SCALE_LEVELS: number[] = [2, 4, 8];
const MIN_RENDER_SCALE: number = 2;
// Thresholds for switching to higher render scale (based on viewScale)
const SCALE_THRESHOLDS: number[] = [1.5, 3.0]; // Switch to level 2 at 1.5x, level 3 at 3.0x

const ContainerSpacing: number = 8;
const ContainerCfg: RowOptions | ColumnOptions = { space: `${ContainerSpacing}px` };
// Delay in ms to ignore draw/erase touches after dual-finger gesture ends
const DUAL_FINGER_END_PROTECTION_DELAY: number = 300;
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
const CanvasOverSampling: number = 3;

interface PathWithPoints {
  path: Path2D;
  points: Array<Vector2>;
}

interface History {
  path: PathWithPoints;
  mode: 'add' | 'erase';
  pageIndex: number;
}

function clearStack<T>(stack: Stack<T>): void {
  while (!stack.isEmpty()) {
    stack.pop();
  }
}

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
  @State annotateMode: 'drag' | 'draw' | 'erase' = 'drag';
  @State viewPan: Vector2 = Vec2(0, 0);
  @State viewScale: number = 1.0;
  @State viewportSize: Vector2 = Vec2(0, 0);
  @State showControls: boolean = true;
  private lastTouchPoint: Vector2 | undefined = undefined;
  private lastPinchDistance: number | undefined = undefined;
  private lastPinchCenter: Vector2 | undefined = undefined;
  private lastDualFingerEndTime: number = 0; // Timestamp when dual-finger gesture ended
  private readonly minScale: number = 0.5;
  private readonly maxScale: number = 9.0;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  // Drawing/annotation state
  private view1Ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private view2Ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private view3Ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private view1DrawCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private view2DrawCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private view3DrawCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private pageStrokes: HashMap<number, Array<PathWithPoints>> = new HashMap<number, Array<PathWithPoints>>();
  private activeDrawPath: PathWithPoints = { path: new Path2D(), points: [] };
  private pathsToErase: Set<PathWithPoints> = new Set();
  private undoHistory: Stack<History> = new Stack<History>();
  private redoHistory: Stack<History> = new Stack<History>();
  @State hasUnsavedStrokes: boolean = false;
  @State undoHistoryCount: number = 0;
  @State redoHistoryCount: number = 0;

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
    this.redrawStrokes();
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
    const viewSizeVp = pxToVp(this.viewSize, uiContext);
    const viewportSizeVp = pxToVp(this.viewportSize, uiContext);

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

  setPageDisplayMode(value: 'single' | 'dual' | 'dualContinuous' | 'tri' | 'triContinuous'): void {
    this.pageDisplayMode = value;
    this.gotoPage(this.currentPageIndex);
    try {
      this.preferences.putSync('pageDisplayMode', value);
      this.preferences.flushSync();
    } catch (error) {
      hilog.error(0, 'PDFView', `Err on saving page display mode: ${error}.`);
    }
  }

  setPageFlipMode(value: 'side' | 'button' | 'extern'): void {
    this.pageFlipMode = value;
    try {
      this.preferences.putSync('pageFlipMode', value);
      this.preferences.flushSync();
    } catch (error) {
      hilog.error(0, 'PDFView', `Err on saving page flip mode: ${error}.`);
    }
  }

  setAnnotateMode(value: 'drag' | 'draw' | 'erase'): void {
    this.annotateMode = value;
    try {
      this.preferences.putSync('annotateMode', value);
      this.preferences.flushSync();
    } catch (error) {
      hilog.error(0, 'PDFView', `Err on saving annotation mode: ${error}.`);
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
    const viewSizeVp = pxToVp(this.viewSize, uiContext);
    const viewportSizeVp = pxToVp(this.viewportSize, uiContext);

    // Account for scaling - the actual displayed size is viewSize * viewScale
    const scaledViewSizeVp = mul(viewSizeVp, this.viewScale);

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

  // Drawing/annotation methods
  applyStrokeStyle(ctx: CanvasRenderingContext2D): void {
    ctx.strokeStyle = 'rgba(255, 132, 0, 1.00)';
    ctx.lineWidth = 1 * CanvasOverSampling;
    ctx.lineCap = 'round';
  }

  updateUnsavedStrokesFlag(): void {
    for (const pageIndex of this.pageStrokes.keys()) {
      const strokes = this.pageStrokes.get(pageIndex);
      if (strokes.length > 0) {
        this.hasUnsavedStrokes = true;
        return;
      }
    }
    this.hasUnsavedStrokes = false;
  }

  loadPageStrokes(ctx: CanvasRenderingContext2D, pageIndex: number): void {
    if (!this.pageStrokes.hasKey(pageIndex)) {
      return;
    }
    const strokes = this.pageStrokes.get(pageIndex);
    this.applyStrokeStyle(ctx);
    strokes.forEach(stroke => ctx.stroke(stroke.path));
  }

  appendUndoHistory(history: History): void {
    this.undoHistory.push(history);
    this.undoHistoryCount = this.undoHistory.length;
    clearStack(this.redoHistory);
    this.redoHistoryCount = 0;
  }

  executeUndo(): void {
    if (this.undoHistory.isEmpty()) {
      return;
    }
    const history = this.undoHistory.pop();
    this.undoHistoryCount = this.undoHistory.length;
    
    // Navigate to the page if needed
    if (this.currentPageIndex !== history.pageIndex) {
      this.gotoPage(history.pageIndex);
    }
    
    if (history.mode === 'add') {
      // Undo an add: remove the stroke
      if (this.pageStrokes.hasKey(history.pageIndex)) {
        const strokes = this.pageStrokes.get(history.pageIndex);
        const index = strokes.indexOf(history.path);
        if (index >= 0) {
          strokes.splice(index, 1);
        }
      }
    } else if (history.mode === 'erase') {
      // Undo an erase: restore the stroke
      if (!this.pageStrokes.hasKey(history.pageIndex)) {
        this.pageStrokes.set(history.pageIndex, []);
      }
      this.pageStrokes.get(history.pageIndex).push(history.path);
    }
    
    this.redoHistory.push(history);
    this.redoHistoryCount = this.redoHistory.length;
    this.updateUnsavedStrokesFlag();
    this.redrawStrokes();
  }

  executeRedo(): void {
    if (this.redoHistory.isEmpty()) {
      return;
    }
    const history = this.redoHistory.pop();
    this.redoHistoryCount = this.redoHistory.length;
    
    // Navigate to the page if needed
    if (this.currentPageIndex !== history.pageIndex) {
      this.gotoPage(history.pageIndex);
    }
    
    if (history.mode === 'add') {
      // Redo an add: add the stroke back
      if (!this.pageStrokes.hasKey(history.pageIndex)) {
        this.pageStrokes.set(history.pageIndex, []);
      }
      this.pageStrokes.get(history.pageIndex).push(history.path);
    } else if (history.mode === 'erase') {
      // Redo an erase: remove the stroke again
      if (this.pageStrokes.hasKey(history.pageIndex)) {
        const strokes = this.pageStrokes.get(history.pageIndex);
        const index = strokes.indexOf(history.path);
        if (index >= 0) {
          strokes.splice(index, 1);
        }
      }
    }
    
    this.undoHistory.push(history);
    this.undoHistoryCount = this.undoHistory.length;
    this.updateUnsavedStrokesFlag();
    this.redrawStrokes();
  }

  async executeSave(): Promise<void> {
    // Preserve current view state to restore after save
    const savedViewScale = this.viewScale;
    const savedViewPan = Vec2(this.viewPan.x, this.viewPan.y);
    const savedPageIndex = this.currentPageIndex;
    const savedRenderScale = this.currentRenderScale;

    for (const pageIndex of this.pageStrokes.keys()) {
      const strokes = this.pageStrokes.get(pageIndex);
      if (pageIndex >= this.pages.length) {
        continue;
      }
      const pdfPage = this.pages[pageIndex];
      const pdfPageSize = Vec2(pdfPage.getWidth(), pdfPage.getHeight());

      // Touch events return coordinates in the canvas's native coordinate space (vp units)
      // Canvas native size = pdfPageSize * CanvasOverSampling (in px), convert to vp
      const uiContext = this.getUIContext();
      const canvasSizePx = mul(pdfPageSize, CanvasOverSampling);
      const canvasSizeVp = Vec2(
        uiContext.px2vp(canvasSizePx.x),
        uiContext.px2vp(canvasSizePx.y)
      );

      for (const stroke of strokes) {
        const annotationInfo = new pdfService.InkAnnotationInfo();
        annotationInfo.lineColor = 0xFFCA1A1A;

        // Transform stroke points from canvas native coordinates (vp) to PDF coordinates
        const transformedPoints: Vector2[] = [];
        for (const point of stroke.points) {
          const transformedPoint = Vec2(
            (point.x / canvasSizeVp.x) * pdfPageSize.x,
            (1 - point.y / canvasSizeVp.y) * pdfPageSize.y
          );
          transformedPoints.push(transformedPoint);
        }
        annotationInfo.inkPoints = transformedPoints;
        pdfPage.addAnnotation(annotationInfo);
      }
    }
    
    // Clear strokes and history
    this.pageStrokes.clear();
    clearStack(this.undoHistory);
    clearStack(this.redoHistory);
    this.undoHistoryCount = 0;
    this.redoHistoryCount = 0;
    this.hasUnsavedStrokes = false;

    // Save the document
    const success = this.document.saveDocument(this.sandBoxPath);
    if (!success) {
      hilog.error(0, 'PDFView', 'Error saving PDF file');
      return;
    }
    
    // Clear page cache and reload
    this.pageCache.clear();
    this.pages = [];
    
    const result = this.document.loadDocument(this.sandBoxPath);
    if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
      hilog.error(0, 'PDFView', `Error re-loading PDF file: ${result}`);
      App.terminate();
      return;
    }
    
    for (let i = 0; i < this.totalPageCount; i++) {
      const page = this.document.getPage(i);
      this.pages.push(page);
    }
    
    // Start background caching again
    this.startBackgroundCaching();
    
    // Reload current page
    await this.gotoPage(savedPageIndex);
    
    // Restore view state after page reload to minimize user interruption
    this.viewScale = savedViewScale;
    this.viewPan = savedViewPan;
    this.currentRenderScale = savedRenderScale;
    this.clampViewPan();
    
    // Check if we need higher resolution render at the restored scale
    this.checkAndUpdateRenderScale();
    
    this.redrawStrokes();
  }

  redrawStrokes(): void {
    // Clear and redraw strokes for all visible canvases
    this.view1Ctx.reset();
    this.view2Ctx.reset();
    this.view3Ctx.reset();
    this.view1DrawCtx.reset();
    this.view2DrawCtx.reset();
    this.view3DrawCtx.reset();
    
    // Load strokes for displayed pages
    for (let i = 0; i < this.displayedPageIndices.length; i++) {
      const pageIndex = this.displayedPageIndices[i];
      if (i === 0) {
        this.loadPageStrokes(this.view1Ctx, pageIndex);
      } else if (i === 1) {
        this.loadPageStrokes(this.view2Ctx, pageIndex);
      } else if (i === 2) {
        this.loadPageStrokes(this.view3Ctx, pageIndex);
      }
    }
  }

  getCanvasSize(pageIndex: number): Vector2 {
    if (pageIndex >= this.pages.length) {
      return Vec2(0, 0);
    }
    const page = this.pages[pageIndex];
    return Vec2(page.getWidth() * CanvasOverSampling, page.getHeight() * CanvasOverSampling);
  }

  getCanvasScale(viewIndex: number): ScaleOptions {
    // Get the view size (display size) and canvas size to calculate scale
    let viewSize: Vector2;
    if (viewIndex === 0) {
      viewSize = this.view1ViewSize;
    } else if (viewIndex === 1) {
      viewSize = this.view2ViewSize;
    } else {
      viewSize = this.view3ViewSize;
    }
    
    const pageIndex = this.displayedPageIndices[viewIndex] ?? 0;
    const canvasSize = this.getCanvasSize(pageIndex);
    
    if (canvasSize.x === 0 || canvasSize.y === 0) {
      return { x: 1, y: 1, centerX: 0, centerY: 0 };
    }
    
    // Scale canvas down from CanvasOverSampling size to display size
    const scaleX = viewSize.x / canvasSize.x;
    const scaleY = viewSize.y / canvasSize.y;
    
    return { x: scaleX, y: scaleY, centerX: 0, centerY: 0 };
  }

  handleDrawTouch(
    drawCtx: CanvasRenderingContext2D,
    targetCtx: CanvasRenderingContext2D,
    pageIndex: number,
    event: TouchEvent
  ): void {
    const isSingleTouch = event.touches.length === 1 && event.touches[0].id === 0;
    if (!isSingleTouch) {
      return;
    }

    // Protection: ignore touch events shortly after dual-finger gesture ends
    // This prevents accidental draw/erase when lifting one finger from pinch
    const timeSinceDualFingerEnd = Date.now() - this.lastDualFingerEndTime;
    if (timeSinceDualFingerEnd < DUAL_FINGER_END_PROTECTION_DELAY) {
      // Reset active drawing state if we were in the middle of drawing
      if (this.activeDrawPath.points.length > 0) {
        this.activeDrawPath = { path: new Path2D(), points: [] };
        drawCtx.reset();
      }
      return;
    }

    const touchPoint = Vec2(event.touches[0].x, event.touches[0].y);

    if (this.annotateMode === 'draw') {
      if (event.type === TouchType.Down) {
        this.activeDrawPath.path.moveTo(touchPoint.x, touchPoint.y);
        this.activeDrawPath.points.push(touchPoint);
      } else if (event.type === TouchType.Move) {
        this.activeDrawPath.path.lineTo(touchPoint.x, touchPoint.y);
        drawCtx.reset();
        this.applyStrokeStyle(drawCtx);
        drawCtx.stroke(this.activeDrawPath.path);
        this.activeDrawPath.points.push(touchPoint);
      } else if (event.type === TouchType.Up) {
        this.activeDrawPath.points.push(touchPoint);
        if (!this.pageStrokes.hasKey(pageIndex)) {
          this.pageStrokes.set(pageIndex, []);
        }
        this.pageStrokes.get(pageIndex).push(this.activeDrawPath);
        this.appendUndoHistory({
          path: this.activeDrawPath,
          mode: 'add',
          pageIndex: pageIndex
        });
        this.activeDrawPath = { path: new Path2D(), points: [] };
        drawCtx.reset();
        this.updateUnsavedStrokesFlag();
        this.loadPageStrokes(targetCtx, pageIndex);
      }
    } else if (this.annotateMode === 'erase') {
      if (!this.pageStrokes.hasKey(pageIndex)) {
        return;
      }

      const eraseThreshold = 20 * CanvasOverSampling;
      const strokes = this.pageStrokes.get(pageIndex);

      if (event.type === TouchType.Down) {
        this.pathsToErase.clear();
      }

      if (event.type === TouchType.Down || event.type === TouchType.Move) {
        for (const stroke of strokes) {
          if (this.pathsToErase.has(stroke)) {
            continue;
          }
          for (const point of stroke.points) {
            const dx = touchPoint.x - point.x;
            const dy = touchPoint.y - point.y;
            const distance = Math.sqrt(dx * dx + dy * dy);
            if (distance < eraseThreshold) {
              this.pathsToErase.add(stroke);
              break;
            }
          }
        }

        targetCtx.reset();
        this.applyStrokeStyle(targetCtx);
        for (const stroke of strokes) {
          if (!this.pathsToErase.has(stroke)) {
            targetCtx.stroke(stroke.path);
          }
        }
      } else if (event.type === TouchType.Up) {
        if (this.pathsToErase.size > 0) {
          const remainingStrokes = strokes.filter(stroke => !this.pathsToErase.has(stroke));
          this.pageStrokes.set(pageIndex, remainingStrokes);

          this.pathsToErase.forEach(erasedPath => {
            this.appendUndoHistory({
              path: erasedPath,
              mode: 'erase',
              pageIndex: pageIndex
            });
          });

          this.pathsToErase.clear();
          targetCtx.reset();
          this.updateUnsavedStrokesFlag();
          this.loadPageStrokes(targetCtx, pageIndex);
        }
      }
    }
  }

  handleViewAction(event: TouchEvent): void {
    const isSingleTouch = event.touches.length === 1 && event.touches[0].id === 0;
    const isDualTouch = event.touches.length === 2 && event.touches[0].id === 0 && event.touches[1].id === 1;

    if (isSingleTouch) {
      // Only handle single-touch panning in drag mode
      if (this.annotateMode !== 'drag') {
        return;
      }
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
      // Pinch-to-zoom handling - always enabled regardless of annotate mode
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

          // Calculate pinch center movement (drag component)
          const centerDeltaX = pinchCenter.x - this.lastPinchCenter.x;
          const centerDeltaY = pinchCenter.y - this.lastPinchCenter.y;

          // To keep the pinch center point stationary on screen during scaling:
          // The point under the pinch center before scaling should remain under it after scaling
          // Formula: newPan = pinchCenter - (pinchCenter - oldPan) * scaleChange
          // Then add the center movement delta for simultaneous dragging
          const newPanX = pinchCenter.x - (pinchCenter.x - this.viewPan.x) * actualScaleChange + centerDeltaX;
          const newPanY = pinchCenter.y - (pinchCenter.y - this.viewPan.y) * actualScaleChange + centerDeltaY;

          this.viewScale = newScale;
          this.viewPan = Vec2(newPanX, newPanY);
          this.clampViewPan();

          this.lastPinchDistance = pinchDistance;
          this.lastPinchCenter = pinchCenter;
        }
      } else if (event.type == TouchType.Up) {
        this.lastPinchDistance = undefined;
        this.lastPinchCenter = undefined;
        // Record when dual-finger gesture ended for accidental touch protection
        this.lastDualFingerEndTime = Date.now();
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

        RelativeContainer() {
          Image(this.view1PixelMap).alignRules(FullRect)
          Canvas(this.view1Ctx)
            .size(toSize(this.getCanvasSize(this.displayedPageIndices[0] ?? 0)))
            .scale(this.getCanvasScale(0))
            .hitTestBehavior(HitTestMode.None)
          Canvas(this.view1DrawCtx)
            .size(toSize(this.getCanvasSize(this.displayedPageIndices[0] ?? 0)))
            .scale(this.getCanvasScale(0))
            .visibility(toVisibility(this.annotateMode !== 'drag'))
            .onTouch(event => this.handleDrawTouch(this.view1DrawCtx, this.view1Ctx, this.displayedPageIndices[0] ?? 0, event))
        }
        .size(toSize(this.view1ViewSize))
        .visibility(toVisibility(true))

        RelativeContainer() {
          Image(this.view2PixelMap).alignRules(FullRect)
          Canvas(this.view2Ctx)
            .size(toSize(this.getCanvasSize(this.displayedPageIndices[1] ?? 0)))
            .scale(this.getCanvasScale(1))
            .hitTestBehavior(HitTestMode.None)
          Canvas(this.view2DrawCtx)
            .size(toSize(this.getCanvasSize(this.displayedPageIndices[1] ?? 0)))
            .scale(this.getCanvasScale(1))
            .visibility(toVisibility(this.annotateMode !== 'drag'))
            .onTouch(event => this.handleDrawTouch(this.view2DrawCtx, this.view2Ctx, this.displayedPageIndices[1] ?? 0, event))
        }
        .size(toSize(this.view2ViewSize))
        .visibility(toVisibility(this.view2Visible))

        RelativeContainer() {
          Image(this.view3PixelMap).alignRules(FullRect)
          Canvas(this.view3Ctx)
            .size(toSize(this.getCanvasSize(this.displayedPageIndices[2] ?? 0)))
            .scale(this.getCanvasScale(2))
            .hitTestBehavior(HitTestMode.None)
          Canvas(this.view3DrawCtx)
            .size(toSize(this.getCanvasSize(this.displayedPageIndices[2] ?? 0)))
            .scale(this.getCanvasScale(2))
            .visibility(toVisibility(this.annotateMode !== 'drag'))
            .onTouch(event => this.handleDrawTouch(this.view3DrawCtx, this.view3Ctx, this.displayedPageIndices[2] ?? 0, event))
        }
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
        .hitTestBehavior(HitTestMode.Transparent)
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

      Image('')
        .size(PageFlipButtonSize)
        .alignRules(TopLeft)
        .visibility(toVisibility(this.pageFlipMode == 'side'))
        .hitTestBehavior(HitTestMode.None)
        .linearGradient({
          direction: GradientDirection.Left,
          colors: [
            [Color.Transparent, 0],
            ['rgba(0, 0, 0, 0.2)', 1]
          ],
          repeating: false
        })

      Image('')
        .size(PageFlipButtonSize)
        .alignRules(TopRight)
        .visibility(toVisibility(this.pageFlipMode == 'side'))
        .hitTestBehavior(HitTestMode.None)
        .linearGradient({
          direction: GradientDirection.Right,
          colors: [
            [Color.Transparent, 0],
            ['rgba(0, 0, 0, 0.2)', 1]
          ],
          repeating: false
        })

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

          StyleButton({
            text: '拖动',
            symbol: getCheckIconName(this.annotateMode == 'drag'),
            alternateColor: this.annotateMode == 'drag' ? ButtonColorSemiTransparent : ButtonColor,
            onClickCallback: () => this.setAnnotateMode('drag')
          }).visibility(toVisibility(this.showControls))

          StyleButton({
            text: '绘制',
            symbol: getCheckIconName(this.annotateMode == 'draw'),
            alternateColor: this.annotateMode == 'draw' ? ButtonColorSemiTransparent : ButtonColor,
            onClickCallback: () => this.setAnnotateMode('draw')
          }).visibility(toVisibility(this.showControls))

          StyleButton({
            text: '擦除',
            symbol: getCheckIconName(this.annotateMode == 'erase'),
            alternateColor: this.annotateMode == 'erase' ? ButtonColorSemiTransparent : ButtonColor,
            onClickCallback: () => this.setAnnotateMode('erase')
          }).visibility(toVisibility(this.showControls))

        }.height('100%');

        Blank();

        Column(ContainerCfg) {

          Blank()

          StyleNumBadgeButton({
            text: '撤回',
            count: this.undoHistoryCount,
            onClickCallback: () => this.executeUndo()
          })
            .visibility(toVisibility(this.showControls))
          StyleNumBadgeButton({
            text: '重做',
            count: this.redoHistoryCount,
            onClickCallback: () => this.executeRedo()
          })
            .visibility(toVisibility(this.showControls))
          StyleStrBadgeButton({
            text: '保存',
            badgeText: '!',
            badgeVisibility: this.hasUnsavedStrokes,
            onClickCallback: () => this.executeSave()
          })
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