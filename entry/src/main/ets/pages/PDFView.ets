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
  toVisibility
} from './UIComponents';
import { CustomContentDialogV2, AdvancedDialogV2Button, LengthMetricsUnit, window, LengthMetrics } from '@kit.ArkUI';
import { pdfService } from '@kit.PDFKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HashMap, Stack, taskpool } from '@kit.ArkTS';
import { fromArea, generateGUID, mul, pxToVp, toSize, Vec2, Vector2 } from './Numbers';
import { preferences, uniformTypeDescriptor as utd } from '@kit.ArkData';
import { KeyCode } from '@kit.InputKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { fileUri, fileIo as fs, picker } from '@kit.CoreFileKit';
import { harmonyShare, systemShare } from '@kit.ShareKit';
import { common } from '@kit.AbilityKit';

// 渲染缩放级别 - 最小为4以获得更清晰的显示，最多2个级别
const RENDER_SCALE_LEVELS: number[] = [4, 8];
const MIN_RENDER_SCALE: number = 4;
// 切换到更高渲染缩放的阈值（基于viewScale）
const SCALE_THRESHOLDS: number[] = [2.0]; // 在2.0倍视图缩放时切换到8倍

const ContainerSpacing: number = 8;
const ContainerCfg: RowOptions | ColumnOptions = { space: `${ContainerSpacing}px` };
// 双指手势结束后忽略绘制/擦除触摸的延迟（毫秒）
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
const ShareButtonId: string = 'shareButton';

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

interface PageCache {
  page: pdfService.PdfPage;
  pixelMap: PixelMap;
  renderScale: number;
  baseSize: Vector2; // 原始页面大小（无缩放）
  displaySize: Vector2; // UI 显示大小（始终为 MIN_RENDER_SCALE）
}

// 创建多级缓存键的辅助函数
function makeCacheKey(pageIndex: number, renderScale: number): string {
  return `${pageIndex}_${renderScale}`;
}

interface KeystrokeEvent {
  keyCode: KeyCode;
  ctrlKey: boolean;
  shiftKey: boolean;
}

@Entry
@Component
struct PDFView {
  private systemPath = '';
  private sandBoxPath = '';
  private saveTempPath = '';
  private fileName = '';
  private mainWindow: window.Window = (AppStorage.get('windowStage') as window.WindowStage).getMainWindowSync();
  private document = new pdfService.PdfDocument();
  private pages: Array<pdfService.PdfPage> = [];
  // 多级缓存：键为 "pageIndex_renderScale"
  private pageCache: HashMap<string, PageCache> = new HashMap<string, PageCache>();
  private pendingTasks: HashMap<string, Promise<Object>> = new HashMap<string, Promise<Object>>();
  private preferences: preferences.Preferences = AppStorage.get('preferences') as preferences.Preferences;
  // 跟踪可见页面的当前渲染缩放级别
  private currentRenderScale: number = MIN_RENDER_SCALE;
  // 跟踪当前显示的页面
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
  @State controlsTransparency: number = 0.5;
  private transparencyTimeoutId: number | undefined = undefined;
  private lastTouchPoint: Vector2 | undefined = undefined;
  private lastPinchDistance: number | undefined = undefined;
  private lastPinchCenter: Vector2 | undefined = undefined;
  private lastDualFingerEndTime: number = 0;
  private isDualFingerActive: boolean = false;
  private lastMousePoint: Vector2 | undefined = undefined;
  private activeMouseButton: number = 0; // 当前是否有双指手势激活
  private readonly minScale: number = 0.5;
  private readonly maxScale: number = 9.0;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  // 绘制/注释状态
  private view1Ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private view2Ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private view3Ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private view1DrawCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private view2DrawCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private view3DrawCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  // 多级缓存：键为 "pageIndex_renderScale"
  private pageStrokes: HashMap<number, Array<PathWithPoints>> = new HashMap<number, Array<PathWithPoints>>();
  private activeDrawPath: PathWithPoints = { path: new Path2D(), points: [] };
  private pathsToErase: Set<PathWithPoints> = new Set();
  private undoHistory: Stack<History> = new Stack<History>();
  private redoHistory: Stack<History> = new Stack<History>();
  @State hasUnsavedStrokes: boolean = false;
  @State undoHistoryCount: number = 0;
  @State redoHistoryCount: number = 0;
  @State isExclusiveFullScreen: boolean = false;

  backToMainMenu(): void {
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' });
  }

  showAlertDialog(title: string, message: string): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      this.getUIContext().showAlertDialog({
        title: title,
        message: message,
        confirm: {
          defaultFocus: true,
          action: () => resolve(),
          value: $r('sys.string.general_confirm')
        }
      });
    });
  }

  aboutToAppear(): void {
    const args = this.getUIContext().getRouter().getParams() as Record<string, string>;
    this.systemPath = args['systemPath'];
    this.sandBoxPath = args['sandboxPath'];
    this.saveTempPath = args['saveTempPath'];
    this.fileName = args['fileName'];
    const result = this.document.loadDocument(this.sandBoxPath);
    if (result != pdfService.ParseResult.PARSE_SUCCESS) {

      let resultText: string;
      switch (result) {
        case pdfService.ParseResult.PARSE_ERROR_FILE:
          resultText = '文件错误';
          break;
        case pdfService.ParseResult.PARSE_ERROR_FORMAT:
          resultText = '格式错误';
          break;
        case pdfService.ParseResult.PARSE_ERROR_PASSWORD:
          resultText = '暂不支持加密的 PDF 文件';
          break;
        case pdfService.ParseResult.PARSE_ERROR_HANDLER:
          resultText = '处理程序错误';
          break;
        case pdfService.ParseResult.PARSE_ERROR_CERT:
          resultText = '证书错误';
          break;
      }

      hilog.error(0, 'PDFView', `加载 PDF 文件出错: ${resultText}`)
      this.showAlertDialog('加载错误', `无法加载 PDF 文件: ${resultText}`)
        .then(() => {
          this.backToMainMenu();
        });
      return;
    }
    this.totalPageCount = this.document.getPageCount();

    for (let i = 0; i < this.totalPageCount; i++) {
      const page = this.document.getPage(i);
      this.pages.push(page);
    }

    // 加载首选项
    this.showControls = this.preferences.getSync('showControls', true) as boolean;
    this.pageDisplayMode = this.preferences.getSync('pageDisplayMode',
      'single') as 'single' | 'dual' | 'dualContinuous' | 'tri' | 'triContinuous';
    this.pageFlipMode = this.preferences.getSync('pageFlipMode', 'side') as 'side' | 'button' | 'extern';
    this.annotateMode = this.preferences.getSync('annotateMode', 'drag') as 'drag' | 'draw' | 'erase';
    this.mainWindow.on('windowStatusChange', (statusType: window.WindowStatusType) => this.isExclusiveFullScreen =
      statusType == window.WindowStatusType.FULL_SCREEN);
    try {
      this.isExclusiveFullScreen = this.mainWindow.getWindowStatus() == window.WindowStatusType.FULL_SCREEN;
    } catch (error) {
    }

    this.immersiveListening();
    const context = this.getUIContext().getHostContext() as Context;
    context.eventHub.on('onBackGround', this.onBackGround);

    this.gotoPage(0);
    // 使用TaskPool启动后台缓存
    this.startBackgroundCaching();
    this.startTransparencyTimeout();
  }

  aboutToDisappear(): void {
    this.immersiveDisablingListening();
    const context = this.getUIContext().getHostContext() as Context;
    context.eventHub.off('onBackGround', this.onBackGround);
  }

  onPageHide(): void {
    const context = this.getUIContext().getHostContext() as Context;
    context.eventHub.emit('onBackGround');
  }

  private onBackGround = () => {
    this.immersiveDisablingListening();
  }

  makeSharedData(): systemShare.SharedData {
    const shareData: systemShare.SharedData = new systemShare.SharedData({
      utd: utd.UniformDataType.PDF,
      uri: fileUri.getUriFromPath(this.sandBoxPath),
      title: this.fileName,
      description: `共 ${this.totalPageCount} 页`
    });
    return shareData;
  }

  private immersiveCallback = (sharableTarget: harmonyShare.SharableTarget) => {
    sharableTarget.share(this.makeSharedData());
  }

  private immersiveListening() {
    harmonyShare.on('knockShare', this.immersiveCallback);
    harmonyShare.on('gesturesShare', this.immersiveCallback);
  }

  private immersiveDisablingListening() {
    harmonyShare.off('knockShare', this.immersiveCallback);
    harmonyShare.off('gesturesShare', this.immersiveCallback);
  }

  startBackgroundCaching(): void {
    // 以最小缩放尺度在后台缓存页面，优先级较低
    for (let i = 0; i < this.totalPageCount; i++) {
      const cacheKey = makeCacheKey(i, MIN_RENDER_SCALE);
      if (!this.pageCache.hasKey(cacheKey) && !this.pendingTasks.hasKey(cacheKey)) {
        const task = new taskpool.Task(cachePage, this.sandBoxPath, i, MIN_RENDER_SCALE);
        const promise = taskpool.execute(task, taskpool.Priority.LOW)
          .then(pageCache => {
            this.pageCache.set(cacheKey, pageCache as PageCache);
            this.pendingTasks.remove(cacheKey);
            hilog.info(0, 'PDFView', `页面 ${i} 已在缩放 ${MIN_RENDER_SCALE} 下缓存`);
            return pageCache;
          })
          .catch((error: Error) => {
            this.pendingTasks.remove(cacheKey);
            hilog.error(0, 'PDFView', `缓存页面 ${i} 失败: ${error.message}`);
            throw error;
          });
        this.pendingTasks.set(cacheKey, promise);
      }
    }
  }

  // 根据当前视图缩放确定适当的渲染缩放
  getRenderScaleForViewScale(viewScale: number): number {
    if (viewScale > SCALE_THRESHOLDS[0]) {
      return RENDER_SCALE_LEVELS[1]; // 8x
    }
    return RENDER_SCALE_LEVELS[0]; // 4x (minimum)
  }

  // 检查当前显示的页面是否需要以不同的缩放重新渲染
  async checkAndUpdateRenderScale(): Promise<void> {
    const requiredScale = this.getRenderScaleForViewScale(this.viewScale);

    if (requiredScale !== this.currentRenderScale) {
      hilog.info(0, 'PDFView', `检测到缩放变化: ${this.currentRenderScale} -> ${requiredScale}`);
      this.currentRenderScale = requiredScale;
      // 以新缩放重新渲染当前显示的页面
      await this.updateDisplayedPagesAtScale(requiredScale);
    }
  }

  // 以指定的渲染缩放更新显示的页面
  async updateDisplayedPagesAtScale(renderScale: number): Promise<void> {
    for (const pageIndex of this.displayedPageIndices) {
      const cache = await this.getPageCache(pageIndex, renderScale);
      // 更新相应视图的 pixelMap
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
    // 根据更新的 displaySizes 重新计算 viewSize
    this.updateViewSize();
  }

  // 根据当前显示模式和视图大小更新总体viewSize
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

    // 如果已在请求的缩放尺度缓存，立即返回
    if (this.pageCache.hasKey(cacheKey)) {
      return this.pageCache.get(cacheKey);
    }

    // 如果为此确切的键有待处理任务，等待它
    if (this.pendingTasks.hasKey(cacheKey)) {
      return await this.pendingTasks.get(cacheKey) as PageCache;
    }

    // 检查我们是否有低分辨率版本可以暂时返回
    // 当我们在后台渲染高分辨率时
    let fallbackCache: PageCache | undefined = undefined;
    for (const scale of RENDER_SCALE_LEVELS) {
      if (scale < renderScale) {
        const fallbackKey = makeCacheKey(targetIndex, scale);
        if (this.pageCache.hasKey(fallbackKey)) {
          fallbackCache = this.pageCache.get(fallbackKey);
        }
      }
    }

    // 为请求的渲染缩放创建任务
    const priority = renderScale === MIN_RENDER_SCALE
      ? taskpool.Priority.HIGH
      : taskpool.Priority.MEDIUM;

    const task = new taskpool.Task(cachePage, this.sandBoxPath, targetIndex, renderScale);
    const promise = taskpool.execute(task, priority)
      .then(pageCache => {
        this.pageCache.set(cacheKey, pageCache as PageCache);
        this.pendingTasks.remove(cacheKey);
        hilog.info(0, 'PDFView', `页面 ${targetIndex} 已在缩放 ${renderScale} 下缓存`);
        return pageCache;
      })
      .catch((error: Error) => {
        this.pendingTasks.remove(cacheKey);
        hilog.error(0, 'PDFView', `在缩放 ${renderScale} 下缓存页面 ${targetIndex} 失败: ${error.message}`);
        throw error;
      });

    this.pendingTasks.set(cacheKey, promise);

    // 如果我们有备选方案，立即返回它并让高分辨率版本在后台加载
    if (fallbackCache !== undefined) {
      // 在高分辨率版本准备好时安排更新
      promise.then((highResCache) => {
        // 如果此页面仍然可见，更新显示的 pixelMap
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
    // 导航到新页面时重置渲染缩放
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
      if (index2 !== undefined) {
        this.displayedPageIndices.push(index2);
      }
      if (index3 !== undefined) {
        this.displayedPageIndices.push(index3);
      }

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
          view1Page.displaySize.x + ContainerSpacing + this.view2ViewSize.x + ContainerSpacing +
          view3Page.displaySize.x,
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
      if (targetIndex + 1 < this.totalPageCount) {
        this.displayedPageIndices.push(targetIndex + 1);
      }
      if (targetIndex + 2 < this.totalPageCount) {
        this.displayedPageIndices.push(targetIndex + 2);
      }

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
          view1Page.displaySize.x + ContainerSpacing + this.view2ViewSize.x + ContainerSpacing +
          view3Page.displaySize.x,
          Math.max(view1Page.displaySize.y, this.view2ViewSize.y, view3Page.displaySize.y)
        );
      } else {
        this.view3PixelMap = undefined;
        this.view3Visible = false;
        this.viewSize = Vec2(
          view1Page.displaySize.x +
            (targetIndex + 1 < this.totalPageCount ? ContainerSpacing + this.view2ViewSize.x : 0),
          Math.max(view1Page.displaySize.y, targetIndex + 1 < this.totalPageCount ? this.view2ViewSize.y : 0)
        );
      }
    }

    // 重置视图以适应视口中的内容
    this.resetViewToFit();
    this.redrawStrokes();
  }

  resetViewToFit(): void {
    // 计算适当的缩放以使内容适应视口
    this.viewScale = this.calculateFitScale();
    // 重置平移并固定以确保内容正确定位
    this.viewPan = Vec2(0, 0);
    this.clampViewPan();
  }

  calculateFitScale(): number {
    // viewSize 以 px 单位，viewportSize 以 px 单位
    // 计算使内容适应视口同时保持纵横比的缩放
    const uiContext = this.getUIContext();
    const viewSizeVp = pxToVp(this.viewSize, uiContext);
    const viewportSizeVp = pxToVp(this.viewportSize, uiContext);

    // 避免零除法
    if (viewSizeVp.x <= 0 || viewSizeVp.y <= 0 || viewportSizeVp.x <= 0 || viewportSizeVp.y <= 0) {
      return 1.0;
    }

    // 计算两个维度的缩放因子
    const scaleX = viewportSizeVp.x / viewSizeVp.x;
    const scaleY = viewportSizeVp.y / viewSizeVp.y;

    // 使用较小的缩放以确保内容完全适应视口
    const fitScale = Math.min(scaleX, scaleY);

    // 固定到最小/最大缩放限制
    return Math.max(this.minScale, Math.min(this.maxScale, fitScale));
  }

  setPageDisplayMode(value: 'single' | 'dual' | 'dualContinuous' | 'tri' | 'triContinuous'): void {
    this.pageDisplayMode = value;
    this.gotoPage(this.currentPageIndex);
    try {
      this.preferences.putSync('pageDisplayMode', value);
      this.preferences.flushSync();
    } catch (error) {
      hilog.error(0, 'PDFView', `保存页面显示模式出错: ${error}.`);
    }
  }

  setPageFlipMode(value: 'side' | 'button' | 'extern'): void {
    this.pageFlipMode = value;
    try {
      this.preferences.putSync('pageFlipMode', value);
      this.preferences.flushSync();
    } catch (error) {
      hilog.error(0, 'PDFView', `保存翻页模式出错: ${error}.`);
    }
  }

  setAnnotateMode(value: 'drag' | 'draw' | 'erase'): void {
    this.annotateMode = value;
    try {
      this.preferences.putSync('annotateMode', value);
      this.preferences.flushSync();
    } catch (error) {
      hilog.error(0, 'PDFView', `保存注释模式出错: ${error}.`);
    }
  }

  setShowControls(value: boolean): void {
    this.showControls = value;
    try {
      this.preferences.putSync('showControls', value);
      this.preferences.flushSync();
    } catch (error) {
      hilog.error(0, 'PDFView', `保存显示控件出错: ${error}.`);
    }
  }

  gotoPrevPage(): void {
    if (this.pageDisplayMode === 'single' || this.pageDisplayMode === 'dualContinuous' ||
      this.pageDisplayMode === 'triContinuous') {
      // 向后导航一页
      this.gotoPage(this.currentPageIndex - 1);
    } else if (this.pageDisplayMode === 'dual') {
      // 导航到前一对的左页
      const currentPair = Math.floor(this.currentPageIndex / 2);
      const prevPairLeftIndex = Math.max(0, (currentPair - 1) * 2);
      this.gotoPage(prevPairLeftIndex);
    } else if (this.pageDisplayMode === 'tri') {
      // 导航到前一组的第一页
      const currentGroup = Math.floor(this.currentPageIndex / 3);
      const prevGroupFirstIndex = Math.max(0, (currentGroup - 1) * 3);
      this.gotoPage(prevGroupFirstIndex);
    }
  }

  gotoNextPage(): void {
    if (this.pageDisplayMode === 'single' || this.pageDisplayMode === 'dualContinuous' ||
      this.pageDisplayMode === 'triContinuous') {
      // 向前导航一页
      this.gotoPage(this.currentPageIndex + 1);
    } else if (this.pageDisplayMode === 'dual') {
      // 导航到下一对的左页
      const currentPair = Math.floor(this.currentPageIndex / 2);
      const nextPairLeftIndex = (currentPair + 1) * 2;
      this.gotoPage(nextPairLeftIndex);
    } else if (this.pageDisplayMode === 'tri') {
      // 导航到下一组的第一页
      const currentGroup = Math.floor(this.currentPageIndex / 3);
      const nextGroupFirstIndex = (currentGroup + 1) * 3;
      this.gotoPage(nextGroupFirstIndex);
    }
  }

  clampViewPan(): void {
    // viewPan 以 vp 单位（由 offset() 和触摸事件使用）
    // viewSize 和 viewportSize 以 px 单位
    // 使用 px2vp 转换 px 为 vp 进行比较
    const uiContext = this.getUIContext();
    const viewSizeVp = pxToVp(this.viewSize, uiContext);
    const viewportSizeVp = pxToVp(this.viewportSize, uiContext);

    // 计入缩放 - 实际显示大小为 viewSize * viewScale
    const scaledViewSizeVp = mul(viewSizeVp, this.viewScale);

    // 允许滚动超出边界的距离（以视口百分比计算）
    const boundaryRelaxation = 0.25; // 25% of viewport
    const relaxX = viewportSizeVp.x * boundaryRelaxation;
    const relaxY = viewportSizeVp.y * boundaryRelaxation;

    // 如果内容小于视口，居中显示
    // 如果内容大于视口，允许滚动但固定到边界（带有放松距离）
    let clampedX = this.viewPan.x;
    let clampedY = this.viewPan.y;

    if (scaledViewSizeVp.x <= viewportSizeVp.x) {
      // 内容水平适应 - 居中显示
      clampedX = (viewportSizeVp.x - scaledViewSizeVp.x) / 2;
    } else {
      // 内容更大 - 固定到边界（带有放松距离）
      const minX = -(scaledViewSizeVp.x - viewportSizeVp.x) - relaxX;
      const maxX = relaxX;
      clampedX = Math.max(minX, Math.min(maxX, this.viewPan.x));
    }

    if (scaledViewSizeVp.y <= viewportSizeVp.y) {
      // 内容垂直适应 - 居中显示
      clampedY = (viewportSizeVp.y - scaledViewSizeVp.y) / 2;
    } else {
      // 内容更大 - 固定到边界（带有放松距离）
      const minY = -(scaledViewSizeVp.y - viewportSizeVp.y) - relaxY;
      const maxY = relaxY;
      clampedY = Math.max(minY, Math.min(maxY, this.viewPan.y));
    }

    this.viewPan = Vec2(clampedX, clampedY);
  }

  // 绘制/注释方法
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

    const needsPageNavigation = !this.displayedPageIndices.includes(history.pageIndex);
    if (needsPageNavigation) {
      this.gotoPage(history.pageIndex);
    }

    if (history.mode === 'add') {
      // 撤销添加：移除笔画
      if (this.pageStrokes.hasKey(history.pageIndex)) {
        const strokes = this.pageStrokes.get(history.pageIndex);
        const index = strokes.indexOf(history.path);
        if (index >= 0) {
          strokes.splice(index, 1);
        }
      }
    } else if (history.mode === 'erase') {
      // 撤销擦除：恢复笔画
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

    const needsPageNavigation = !this.displayedPageIndices.includes(history.pageIndex);
    if (needsPageNavigation) {
      this.gotoPage(history.pageIndex);
    }

    if (history.mode === 'add') {
      // 重做添加：重新添加笔画
      if (!this.pageStrokes.hasKey(history.pageIndex)) {
        this.pageStrokes.set(history.pageIndex, []);
      }
      this.pageStrokes.get(history.pageIndex).push(history.path);
    } else if (history.mode === 'erase') {
      // 重做擦除：再次移除笔画
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
    const documentPicker = new picker.DocumentViewPicker();
    const saveOptions = new picker.DocumentSaveOptions();
    saveOptions.defaultFilePathUri = this.systemPath;
    saveOptions.fileSuffixChoices = ['PDF 文档|.pdf'];

    let saveUri: string = '';
    try {
      const result = await documentPicker.save(saveOptions);
      if (result && result.length > 0) {
        saveUri = result[0];
      } else {
        hilog.info(0, 'PDFView', '用户取消保存操作');
        return;
      }
    } catch (error) {
      hilog.error(0, 'PDFView', `保存对话框错误: ${JSON.stringify(error)}`);
      return;
    }

    if (!saveUri || saveUri.length === 0) {
      hilog.error(0, 'PDFView', '未选择有效的保存位置');
      return;
    }

    const affectedPage = new HashMap<number, pdfService.PdfAnnotation[]>();
    for (const pageIndex of this.pageStrokes.keys()) {
      if (pageIndex >= this.pages.length) {
        continue;
      }
      const strokes = this.pageStrokes.get(pageIndex);
      if (strokes.length > 0) {
        affectedPage.set(pageIndex, []);
      }
      const pdfPage = this.pages[pageIndex];
      const pdfPageSize = Vec2(pdfPage.getWidth(), pdfPage.getHeight());

      const uiContext = this.getUIContext();
      const canvasSizePx = mul(pdfPageSize, CanvasOverSampling);
      const canvasSizeVp = pxToVp(canvasSizePx, uiContext);

      for (const stroke of strokes) {
        const transformedPoints: Vector2[] = [];
        for (const point of stroke.points) {
          const transformedPoint = Vec2(
            (point.x / canvasSizeVp.x) * pdfPageSize.x,
            (1 - point.y / canvasSizeVp.y) * pdfPageSize.y
          );
          transformedPoints.push(transformedPoint);
        }
        const annotationInfo = new pdfService.PolylineAnnotationInfo();
        annotationInfo.subject = '由 Just PDF 创建的注释';
        annotationInfo.creationDate = new Date(Date.now());
        annotationInfo.modifiedTime = new Date(Date.now());
        annotationInfo.vertexes = transformedPoints;
        annotationInfo.lineColor = 3547621;
        annotationInfo.uniqueId = generateGUID();
        annotationInfo.flag = pdfService.AnnotationFlag.PRINTED;
        const annotation = pdfPage.addAnnotation(annotationInfo);
        affectedPage.get(pageIndex).push(annotation);
      }
    }

    // Clean up any existing temporary file before saving
    try {
      await fs.unlink(this.saveTempPath);
    } catch (error) {
      // Ignore if file doesn't exist
      if (error.code !== 13900002) {
        hilog.warn(0, 'PDFView', `清理临时文件时出现非致命错误: ${error}`);
      }
    }

    const success = this.document.saveDocument(this.saveTempPath);
    if (!success) {
      hilog.error(0, 'PDFView', `保存 PDF 文件到临时路径时出错`);
      for (const pageIndex of affectedPage.keys()) {
        const pdfPage = this.pages[pageIndex];
        const annotations = affectedPage.get(pageIndex);
        for (const annotation of annotations) {
          pdfPage.removeAnnotation(annotation);
        }
      }
      return;
    }

    try {
      await fs.rename(this.saveTempPath, this.sandBoxPath);
    } catch (error) {
      hilog.error(0, 'PDFView', `将临时文件重命名到沙箱路径时出错: ${error}`);
      try {
        await fs.unlink(this.saveTempPath);
      } catch (unlinkError) {
        hilog.error(0, 'PDFView', `删除临时文件时出错: ${unlinkError}`);
      }
      this.revertChanges(affectedPage);
      return;
    }

    let srcFile: fs.File | undefined;
    let dstFile: fs.File | undefined;

    try {
      srcFile = await fs.open(this.sandBoxPath, fs.OpenMode.READ_ONLY);
      dstFile = await fs.open(saveUri, fs.OpenMode.WRITE_ONLY);
    } catch (error) {
      if (srcFile) {
        await fs.close(srcFile);
      }
      if (dstFile) {
        await fs.close(dstFile);
      }
      hilog.error(0, 'PDFView', `打开文件时出错: ${error}`);
      this.revertChanges(affectedPage);
      return;
    }

    try {
      await fs.copyFile(srcFile.fd, dstFile.fd);
      await fs.close(srcFile);
      await fs.close(dstFile);
    } catch (err) {
      hilog.error(0, 'PDFView', `保存 PDF 文件到选定位置 ${saveUri} 时出错: ${err}`);
      await this.showAlertDialog('保存失败', '无法将 PDF 文件保存到选定位置。请检查权限或存储空间，然后重试。');
      this.revertChanges(affectedPage);
      return;
    }

    this.pageStrokes.clear();
    clearStack(this.undoHistory);
    clearStack(this.redoHistory);
    this.undoHistoryCount = 0;
    this.redoHistoryCount = 0;
    this.hasUnsavedStrokes = false;

    this.invalidateAffectedPages(Array.from(affectedPage.keys()));
  }

  async revertChanges(affectedPage: HashMap<number, pdfService.PdfAnnotation[]>): Promise<void> {
    for (const pageIndex of affectedPage.keys()) {
      const pdfPage = this.pages[pageIndex];
      const annotations = affectedPage.get(pageIndex);
      for (const annotation of annotations) {
        pdfPage.removeAnnotation(annotation);
      }
    }
    const success = this.document.saveDocument(this.saveTempPath);
    if (success) {
      try {
        await fs.rename(this.saveTempPath, this.sandBoxPath);
      } catch (error) {
        hilog.error(0, 'PDFView', `重命名回退文件时出错: ${error}`);
        try {
          await fs.unlink(this.saveTempPath);
        } catch (unlinkError) {
          hilog.error(0, 'PDFView', `删除临时回退文件时出错: ${unlinkError}`);
        }
      }
    } else {
      hilog.error(0, 'PDFView', `保存回退 PDF 文件时出错`);
    }
  }

  invalidateAffectedPages(affectedPageIndices: number[]): void {
    if (affectedPageIndices.length === 0) {
      return;
    }

    for (const pageIndex of affectedPageIndices) {
      for (const scale of RENDER_SCALE_LEVELS) {
        const cacheKey = makeCacheKey(pageIndex, scale);
        if (this.pageCache.hasKey(cacheKey)) {
          this.pageCache.remove(cacheKey);
        }
        if (this.pendingTasks.hasKey(cacheKey)) {
          this.pendingTasks.remove(cacheKey);
        }
      }
    }

    const currentPageAffected = this.displayedPageIndices.some(idx =>
    affectedPageIndices.includes(idx)
    );

    for (const pageIndex of affectedPageIndices) {
      const cacheKey = makeCacheKey(pageIndex, MIN_RENDER_SCALE);
      if (!this.pageCache.hasKey(cacheKey) && !this.pendingTasks.hasKey(cacheKey)) {
        const task = new taskpool.Task(cachePage, this.sandBoxPath, pageIndex, MIN_RENDER_SCALE);
        const promise = taskpool.execute(task, taskpool.Priority.HIGH)
          .then(pageCache => {
            this.pageCache.set(cacheKey, pageCache as PageCache);
            this.pendingTasks.remove(cacheKey);
            hilog.info(0, 'PDFView', `页面 ${pageIndex} 已在缩放 ${MIN_RENDER_SCALE} 下重新缓存`);
            return pageCache;
          })
          .catch((error: Error) => {
            this.pendingTasks.remove(cacheKey);
            hilog.error(0, 'PDFView', `重新缓存页面 ${pageIndex} 失败: ${error.message}`);
            throw error;
          });
        this.pendingTasks.set(cacheKey, promise);
      }
    }

    if (currentPageAffected) {
      this.refreshDisplayedPages();
    }
  }

  async refreshDisplayedPages(): Promise<void> {
    for (let i = 0; i < this.displayedPageIndices.length; i++) {
      const pageIndex = this.displayedPageIndices[i];
      const cache = await this.getPageCache(pageIndex, this.currentRenderScale);
      if (i === 0) {
        this.view1PixelMap = cache.pixelMap;
        this.view1ViewSize = cache.displaySize;
      } else if (i === 1) {
        this.view2PixelMap = cache.pixelMap;
        this.view2ViewSize = cache.displaySize;
      } else if (i === 2) {
        this.view3PixelMap = cache.pixelMap;
        this.view3ViewSize = cache.displaySize;
      }
    }
    this.updateViewSize();
    this.redrawStrokes();
  }

  redrawStrokes(): void {
    // 清除并重新绘制所有可见画布的笔画
    this.view1Ctx.reset();
    this.view2Ctx.reset();
    this.view3Ctx.reset();
    this.view1DrawCtx.reset();
    this.view2DrawCtx.reset();
    this.view3DrawCtx.reset();

    // 加载显示页面的笔画
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

  executeShare(): void {
    let controller: systemShare.ShareController = new systemShare.ShareController(this.makeSharedData());
    // 获取UIAbility上下文对象
    let uiContext: UIContext = this.getUIContext();
    let context = uiContext.getHostContext() as common.UIAbilityContext;
    controller.show(context, { anchor: ShareButtonId });
  }

  getCanvasSize(pageIndex: number): Vector2 {
    if (pageIndex >= this.pages.length) {
      return Vec2(0, 0);
    }
    const page = this.pages[pageIndex];
    return Vec2(page.getWidth() * CanvasOverSampling, page.getHeight() * CanvasOverSampling);
  }

  getCanvasScale(viewIndex: number): ScaleOptions {
    // 获取视图大小（显示大小）和画布大小以计算缩放
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
      return {
        x: 1,
        y: 1,
        centerX: 0,
        centerY: 0
      };
    }

    // 从 CanvasOverSampling 大小缩放画布到显示大小
    const scaleX = viewSize.x / canvasSize.x;
    const scaleY = viewSize.y / canvasSize.y;

    return {
      x: scaleX,
      y: scaleY,
      centerX: 0,
      centerY: 0
    };
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

    // 保护：忽略双指手势激活期间或结束后不久的触摸事件
    // 这防止了在捏合开始时（第二根手指触碰前）和结束时（抬起一根手指后）的意外绘制/擦除
    const timeSinceDualFingerEnd = Date.now() - this.lastDualFingerEndTime;
    if (this.isDualFingerActive || timeSinceDualFingerEnd < DUAL_FINGER_END_PROTECTION_DELAY) {
      // 如果我们在绘制中，重置活动绘制状态
      if (this.activeDrawPath.points.length > 0) {
        this.activeDrawPath = { path: new Path2D(), points: [] };
        drawCtx.reset();
      }
      // 如果在擦除模式中，清除待擦除的路径
      if (this.pathsToErase.size > 0) {
        this.pathsToErase.clear();
        this.redrawStrokes();
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

        let pathLength = 0;
        for (let i = 1; i < this.activeDrawPath.points.length; i++) {
          const p1 = this.activeDrawPath.points[i - 1];
          const p2 = this.activeDrawPath.points[i];
          const dx = p2.x - p1.x;
          const dy = p2.y - p1.y;
          pathLength += Math.sqrt(dx * dx + dy * dy);
        }

        const minPathLength = 2 * CanvasOverSampling;
        if (pathLength >= minPathLength) {
          if (!this.pageStrokes.hasKey(pageIndex)) {
            this.pageStrokes.set(pageIndex, []);
          }
          this.pageStrokes.get(pageIndex).push(this.activeDrawPath);
          this.appendUndoHistory({
            path: this.activeDrawPath,
            mode: 'add',
            pageIndex: pageIndex
          });
          this.updateUnsavedStrokesFlag();
          this.loadPageStrokes(targetCtx, pageIndex);
        }
        this.activeDrawPath = { path: new Path2D(), points: [] };
        drawCtx.reset();
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
    const isTripleTouch =
      event.touches.length === 3 && event.touches[0].id === 0 && event.touches[1].id === 1 && event.touches[2].id === 2;

    if (isTripleTouch) {
      if (event.type === TouchType.Down && (this.annotateMode === 'draw' || this.annotateMode === 'erase')) {
        this.executeUndo();
      }
      return;
    }

    if (isSingleTouch) {
      // 仅在拖动模式下处理单指平移
      if (this.annotateMode !== 'drag') {
        return;
      }
      const touchPoint = Vec2(event.touches[0].x, event.touches[0].y);
      // 拖动视图（this.viewPan）
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
      // 捏合放大处理 - 始终启用，不受注释模式影响
      // 标记双指手势激活，防止在绘制/擦除模式下意外创建笔画
      this.isDualFingerActive = true;

      // 立即中断并清除任何进行中的绘制/擦除操作
      if (this.activeDrawPath.points.length > 0) {
        this.activeDrawPath = { path: new Path2D(), points: [] };
        this.view1DrawCtx.reset();
        this.view2DrawCtx.reset();
        this.view3DrawCtx.reset();
      }
      if (this.pathsToErase.size > 0) {
        this.pathsToErase.clear();
        this.redrawStrokes();
      }

      const touch1 = Vec2(event.touches[0].x, event.touches[0].y);
      const touch2 = Vec2(event.touches[1].x, event.touches[1].y);
      const pinchCenter = Vec2((touch1.x + touch2.x) / 2, (touch1.y + touch2.y) / 2);
      const pinchDistance = Math.sqrt(
        Math.pow(touch2.x - touch1.x, 2) + Math.pow(touch2.y - touch1.y, 2)
      );

      if (event.type == TouchType.Down) {
        // 捏合手势的开始
        this.lastPinchDistance = pinchDistance;
        this.lastPinchCenter = pinchCenter;
      } else if (event.type == TouchType.Move) {
        if (this.lastPinchDistance !== undefined && this.lastPinchCenter !== undefined) {
          // 计算缩放变化
          const scaleRatio = pinchDistance / this.lastPinchDistance;
          const newScale = Math.max(this.minScale, Math.min(this.maxScale, this.viewScale * scaleRatio));
          const actualScaleChange = newScale / this.viewScale;

          // 计算捏合中心运动（拖动分量）
          const centerDeltaX = pinchCenter.x - this.lastPinchCenter.x;
          const centerDeltaY = pinchCenter.y - this.lastPinchCenter.y;

          // 为了在缩放期间保持捏合中心点在屏幕上静止：
          // 缩放前捏合中心下的点应在缩放后保持在它下面
          // 公式：newPan = pinchCenter - (pinchCenter - oldPan) * scaleChange
          // 然后添加中心移动增量以进行同时拖动
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
        // 记录双指手势结束的时间以进行意外触摸保护
        this.lastDualFingerEndTime = Date.now();
        // 标记双指手势结束
        this.isDualFingerActive = false;
        // 检查捏合结束后是否需要以不同的缩放重新渲染
        this.checkAndUpdateRenderScale();
      }
      // 在捏合模式下清除单指触摸跟踪
      this.lastTouchPoint = undefined;
    } else {
      // 重置所有触摸跟踪
      this.lastTouchPoint = undefined;
      this.lastPinchDistance = undefined;
      this.lastPinchCenter = undefined;
      // 如果双指手势之前处于激活状态，记录结束时间
      if (this.isDualFingerActive) {
        this.lastDualFingerEndTime = Date.now();
        this.isDualFingerActive = false;
      }
    }
  }

  handleMouseEvent(event: MouseEvent): void {
    const mousePoint = Vec2(event.x, event.y);
    const isLeftButton = event.button === MouseButton.Left;
    const isRightButton = event.button === MouseButton.Right;

    if (event.action === MouseAction.Press) {
      this.lastMousePoint = mousePoint;
      if (isLeftButton) {
        this.activeMouseButton = 1;
      } else if (isRightButton) {
        this.activeMouseButton = 2;
      }
    } else if (event.action === MouseAction.Move) {
      if (this.lastMousePoint !== undefined && this.activeMouseButton !== 0) {
        const delta = Vec2(
          mousePoint.x - this.lastMousePoint.x,
          mousePoint.y - this.lastMousePoint.y
        );

        if (this.annotateMode === 'drag') {
          if (this.activeMouseButton === 1 || this.activeMouseButton === 2) {
            this.viewPan = Vec2(
              this.viewPan.x + delta.x,
              this.viewPan.y + delta.y
            );
            this.clampViewPan();
          }
        } else {
          if (this.activeMouseButton === 2) {
            this.viewPan = Vec2(
              this.viewPan.x + delta.x,
              this.viewPan.y + delta.y
            );
            this.clampViewPan();
          }
        }

        this.lastMousePoint = mousePoint;
      }
    } else if (event.action === MouseAction.Release) {
      this.lastMousePoint = undefined;
      this.activeMouseButton = 0;
    }
  }

  handleDrawMouse(
    drawCtx: CanvasRenderingContext2D,
    targetCtx: CanvasRenderingContext2D,
    pageIndex: number,
    event: MouseEvent
  ): void {
    const isLeftButton = event.button === MouseButton.Left;
    if (!isLeftButton) {
      return;
    }

    const mousePoint = Vec2(event.x, event.y);

    if (this.annotateMode === 'draw') {
      if (event.action === MouseAction.Press) {
        this.activeDrawPath.path.moveTo(mousePoint.x, mousePoint.y);
        this.activeDrawPath.points.push(mousePoint);
      } else if (event.action === MouseAction.Move && this.activeMouseButton === 1) {
        this.activeDrawPath.path.lineTo(mousePoint.x, mousePoint.y);
        drawCtx.reset();
        this.applyStrokeStyle(drawCtx);
        drawCtx.stroke(this.activeDrawPath.path);
        this.activeDrawPath.points.push(mousePoint);
      } else if (event.action === MouseAction.Release) {
        this.activeDrawPath.points.push(mousePoint);

        let pathLength = 0;
        for (let i = 1; i < this.activeDrawPath.points.length; i++) {
          const p1 = this.activeDrawPath.points[i - 1];
          const p2 = this.activeDrawPath.points[i];
          const dx = p2.x - p1.x;
          const dy = p2.y - p1.y;
          pathLength += Math.sqrt(dx * dx + dy * dy);
        }

        const minPathLength = 2 * CanvasOverSampling;
        if (pathLength >= minPathLength) {
          if (!this.pageStrokes.hasKey(pageIndex)) {
            this.pageStrokes.set(pageIndex, []);
          }
          this.pageStrokes.get(pageIndex).push(this.activeDrawPath);
          this.appendUndoHistory({
            path: this.activeDrawPath,
            mode: 'add',
            pageIndex: pageIndex
          });
          this.updateUnsavedStrokesFlag();
          this.loadPageStrokes(targetCtx, pageIndex);
        }
        this.activeDrawPath = { path: new Path2D(), points: [] };
        drawCtx.reset();
      }
    } else if (this.annotateMode === 'erase') {
      if (!this.pageStrokes.hasKey(pageIndex)) {
        return;
      }

      const eraseThreshold = 20 * CanvasOverSampling;
      const strokes = this.pageStrokes.get(pageIndex);

      if (event.action === MouseAction.Press) {
        this.pathsToErase.clear();
      }

      if (event.action === MouseAction.Press || (event.action === MouseAction.Move && this.activeMouseButton === 1)) {
        for (const stroke of strokes) {
          if (this.pathsToErase.has(stroke)) {
            continue;
          }
          for (const point of stroke.points) {
            const dx = mousePoint.x - point.x;
            const dy = mousePoint.y - point.y;
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
      } else if (event.action === MouseAction.Release) {
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

  handleMouseAxisEvent(event: AxisEvent): void {
    const scrollAmount = -event.getVerticalAxisValue();
    if (scrollAmount != undefined && scrollAmount != 0) {
      const mousePoint = Vec2(event.x, event.y);
      const zoomFactor = scrollAmount > 0 ? 1.1 : 0.9;
      const newScale = Math.max(this.minScale, Math.min(this.maxScale, this.viewScale * zoomFactor));
      const actualScaleChange = newScale / this.viewScale;

      const newPanX = mousePoint.x - (mousePoint.x - this.viewPan.x) * actualScaleChange;
      const newPanY = mousePoint.y - (mousePoint.y - this.viewPan.y) * actualScaleChange;

      this.viewScale = newScale;
      this.viewPan = Vec2(newPanX, newPanY);
      this.clampViewPan();

      this.checkAndUpdateRenderScale();
    }
  }

  startTransparencyTimeout(): void {
    if (this.transparencyTimeoutId) {
      clearTimeout(this.transparencyTimeoutId);
    }
    this.controlsTransparency = 1;
    this.transparencyTimeoutId = setTimeout(() => this.controlsTransparency = 0.5, 1000 * 3);
  }

  @Builder
  tutorialDialogBuilder(): void {
    CustomContentDialogV2({
      primaryTitle: 'Just PDF 使用教程',
      contentBuilder: () => {
        this.buildTutorialContent();
      },
      buttons: [
        new AdvancedDialogV2Button({
          content: '关闭',
          buttonStyle: ButtonStyleMode.TEXTUAL,
          role: ButtonRole.NORMAL,
        })
      ],
    })
  }

  level2Color = '#4DA6FF';
  level3Color = '#66FF99';
  level4Color = '#99FFCC';
  level5Color = '#FFA500';
  level6Color = '#FFD700';

  @Builder
  buildTutorialContent(): void {
    Scroll() {
      Text() {
        Span('Just PDF 是为音乐演奏从业者设计的 PDF 阅读器，提供简洁、流畅的阅读及标注体验，以及对常见翻谱器的支持。\n\n')

        Span('打开 PDF 文件\n\n').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.level2Color)

        Span('从应用内打开\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)
        Span('1. 启动 Just PDF 应用\n')
        Span('2. 点击"选择文件"按钮\n')
        Span('3. 从文件选择器中选择您要查看的 PDF 文件\n\n')

        Span('从文件管理器打开\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)
        Span('• 在文件管理器中找到 PDF 文件\n')
        Span('• 点击文件并选择使用 Just PDF 打开\n\n')

        Span('界面控制\n\n').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.level2Color)

        Span('显示/隐藏控件\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)
        Span('• 点击"收起"按钮可隐藏大部分控制按钮\n')
        Span('• 点击"展开"按钮可重新显示控制按钮\n')
        Span('• 隐藏控件可获得更大的阅读区域\n\n')

        Span('全屏模式\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)
        Span('• 点击"全屏"按钮进入全屏模式（仅限平板的智慧多窗模式和二合一设备）\n')
        Span('• 点击"窗口"按钮退出全屏模式\n')
        Span('• 全屏模式下获得最大的阅读空间\n\n')

        Span('页面显示模式\n\n').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.level2Color)

        Span('Just PDF 提供五种页面显示模式，您可以通过点击"显示"按钮选择：\n\n')

        Span('单页模式\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)
        Span('• 仅显示一页\n\n')

        Span('双页模式\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)
        Span('• 同时显示两页（类似打开的书本）\n')
        Span('• 页面按对分组（第 1-2 页，第 3-4 页，等等）\n\n')

        Span('双页连续模式\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)
        Span('• 在显示当前页的同时，同时显示下一页\n')
        Span('• 连续浏览，不按对分组（第 1-2 页，第 2-3 页，等等）\n\n')

        Span('三页模式\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)
        Span('• 同时显示三页\n')
        Span('• 页面按组分组（第 1-3 页，第 4-6 页，等等）\n\n')

        Span('三页连续模式\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)
        Span('• 在显示当前页的同时，同时显示下两页\n')
        Span('• 连续浏览，不按组分组（第 1-3 页，第 2-4 页，等等）\n\n')

        Span('页面导航\n\n').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.level2Color)

        Span('翻页模式\n\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)

        Span('Just PDF 提供三种翻页方式，通过"模式"按钮选择：\n\n')

        Span('屏侧翻页\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.level4Color)
        Span('• 点击屏幕左侧 30% 区域：上一页\n')
        Span('• 点击屏幕右侧 30% 区域：下一页\n')
        Span('• 屏幕边缘会显示渐变提示\n\n')

        Span('按钮翻页\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.level4Color)
        Span('• 使用屏幕右下角的 < 和 > 按钮翻页\n\n')

        Span('外设翻页\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.level4Color)
        Span('• 仅使用键盘方向键，蓝牙或外接或设备翻页\n')
        Span('• 隐藏屏幕翻页控件，获得更清爽的阅读体验\n\n')

        Span('快速导航\n\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)

        Span('• ')
        Span('首页按钮').fontWeight(FontWeight.Bold).fontColor(this.level5Color)
        Span('：立即跳转到第一页\n')
        Span('• ')
        Span('尾页按钮').fontWeight(FontWeight.Bold).fontColor(this.level5Color)
        Span('：立即跳转到最后一页\n')
        Span('• ')
        Span('页面滑块').fontWeight(FontWeight.Bold).fontColor(this.level5Color)
        Span('：拖动右侧的垂直滑块快速跳转到任意页面\n\n')

        Span('缩放和平移\n\n').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.level2Color)

        Span('双指缩放\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)
        Span('• 使用两根手指在屏幕上捏合或展开来缩放页面\n\n')

        Span('拖动平移\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)
        Span('• 在"拖动"模式下，使用单指拖动来移动页面\n\n')

        Span('视口重置\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)
        Span('• 点击"视口"按钮可将页面重置为适应屏幕的大小和位置\n\n')

        Span('注释功能\n\n').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.level2Color)

        Span('Just PDF 提供基础、仅添加的PDF的注释工具，让您可以迅速的在 PDF 上做标记。\n\n')

        Span('注释模式\n\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)

        Span('通过右侧的模式按钮切换：\n\n')

        Span('拖动模式\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.level4Color)
        Span('• 默认模式，用于浏览和导航\n')
        Span('• 可以使用单指或双指拖动移动页面\n')
        Span('• 可以使用双指缩放\n\n')

        Span('绘制模式\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.level4Color)
        Span('• 在 PDF 页面上绘制橙色标记\n')
        Span('• 使用单指在屏幕上滑动即可绘制\n')
        Span('• 使用双指来缩放以及拖动页面\n\n')

        Span('擦除模式\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.level4Color)
        Span('• 擦除之前绘制的标记\n')
        Span('• 触摸或滑过笔画即可擦除\n')
        Span('• 擦除范围会高亮显示\n')
        Span('• 仅能够擦除此次添加的注释（橙色），不会影响到已经保存的注释\n\n')

        Span('注释提示\n\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)

        Span('• 在绘制或擦除模式下，双指缩放会自动暂停注释操作\n')
        Span('• 使用三指同时触摸屏幕可快速撤销上一次操作\n')
        Span('• 切换页面时，注释会自动保存到对应页面\n')
        Span('• 未保存的注释会在"保存"按钮上显示提醒标记（!）\n\n')

        Span('撤销和重做\n\n').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.level2Color)

        Span('撤销操作\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)
        Span('• 点击"撤回"按钮撤销上一次绘制或擦除操作\n')
        Span('• 按钮上的数字显示可撤销的操作数量\n')
        Span('• 支持跨页面撤销\n')
        Span('• 快捷键：')
        Span('Ctrl + Z').fontFamily("monospace").fontColor(this.level6Color)
        Span('\n')
        Span('• 手势：三指同时触摸屏幕\n\n')

        Span('重做操作\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)
        Span('• 点击"重做"按钮恢复已撤销的操作\n')
        Span('• 按钮上的数字显示可重做的操作数量\n')
        Span('• 快捷键：')
        Span('Ctrl + Shift + Z').fontFamily("monospace").fontColor(this.level6Color)
        Span(' 或 ')
        Span('Ctrl + Y').fontFamily("monospace").fontColor(this.level6Color)
        Span('\n\n')

        Span('注意事项\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)
        Span('• 执行新的绘制或擦除操作会清空重做历史\n')
        Span('• 撤销/重做会自动导航到相关页面\n\n')

        Span('保存和分享\n\n').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.level2Color)

        Span('保存注释\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)
        Span('1. 点击"保存"按钮\n')
        Span('2. 选择保存位置和文件名\n')
        Span('3. 应用会将所有注释嵌入到 PDF 文件中\n')
        Span('4. 保存成功后，注释历史会被清空\n\n')

        Span('注意：\n').fontWeight(FontWeight.Bold).fontColor(this.level5Color)
        Span('• 保存按钮上的感叹号（!）表示有未保存的注释\n')
        Span('• 保存的注释会作为 PDF 标准注释，可在其他 PDF 阅读器中查看\n')
        Span('• 快捷键：')
        Span('Ctrl + S').fontFamily("monospace").fontColor(this.level6Color)
        Span('\n\n')

        Span('分享文件\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)
        Span('• 点击"分享"按钮打开系统分享面板\n')
        Span('• 支持通过各种方式分享当前 PDF 文件\n')
        Span('• 支持 HarmonyOS 特有的碰一碰分享和手势分享功能\n\n')

        Span('键盘快捷键\n\n').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.level2Color)

        Span('Just PDF 支持以下键盘快捷键（适用于平板和二合一设备）：\n\n')

        Span('导航\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)
        Span('• ')
        Span('↑').fontFamily("monospace").fontColor(this.level6Color)
        Span(' 或 ')
        Span('←').fontFamily("monospace").fontColor(this.level6Color)
        Span('：上一页\n')
        Span('• ')
        Span('↓').fontFamily("monospace").fontColor(this.level6Color)
        Span(' 或 ')
        Span('→').fontFamily("monospace").fontColor(this.level6Color)
        Span(' 或 ')
        Span('空格').fontFamily("monospace").fontColor(this.level6Color)
        Span('：下一页\n')
        Span('• ')
        Span('Ctrl + ↑').fontFamily("monospace").fontColor(this.level6Color)
        Span(' 或 ')
        Span('Ctrl + ←').fontFamily("monospace").fontColor(this.level6Color)
        Span('：跳转到首页\n')
        Span('• ')
        Span('Ctrl + ↓').fontFamily("monospace").fontColor(this.level6Color)
        Span(' 或 ')
        Span('Ctrl + →').fontFamily("monospace").fontColor(this.level6Color)
        Span('：跳转到尾页\n\n')

        Span('编辑\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.level3Color)
        Span('• ')
        Span('Ctrl + Z').fontFamily("monospace").fontColor(this.level6Color)
        Span('：撤销\n')
        Span('• ')
        Span('Ctrl + Shift + Z').fontFamily("monospace").fontColor(this.level6Color)
        Span(' 或 ')
        Span('Ctrl + Y').fontFamily("monospace").fontColor(this.level6Color)
        Span('：重做\n')
        Span('• ')
        Span('Ctrl + S').fontFamily("monospace").fontColor(this.level6Color)
        Span('：保存\n\n')

        Span('常见问题\n\n').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.level2Color)

        Span('Q: 为什么我的注释没有保存？\n').fontWeight(FontWeight.Bold).fontColor(this.level5Color)
        Span('A: 请确保点击"保存"按钮并选择保存位置。注释只有在保存后才会永久嵌入 PDF 文件。\n\n')

        Span('Q: 如何删除错误的标注？\n').fontWeight(FontWeight.Bold).fontColor(this.level5Color)
        Span('A: 切换到"擦除"模式，然后触摸要删除的笔画。或者使用"撤回"按钮撤销最近的操作。\n\n')

        Span('感谢使用 Just PDF！如有任何问题或建议，欢迎反馈。').fontStyle(FontStyle.Italic).fontColor('#CCCCCC')
      }.fontSize(10+6)
      .lineSpacing(LengthMetrics.vp(5))
      .width('100%')
      .padding(20)
    }
    .width('100%')
    .height('100%')
  }

  build() {
    RelativeContainer() {

      Row(ContainerCfg) {

        RelativeContainer() {
          Image(this.view1PixelMap).alignRules(FullRect).draggable(false)
          Canvas(this.view1Ctx)
            .size(toSize(this.getCanvasSize(this.displayedPageIndices[0] ?? 0)))
            .scale(this.getCanvasScale(0))
            .hitTestBehavior(HitTestMode.None)
          Canvas(this.view1DrawCtx)
            .size(toSize(this.getCanvasSize(this.displayedPageIndices[0] ?? 0)))
            .scale(this.getCanvasScale(0))
            .visibility(toVisibility(this.annotateMode !== 'drag'))
            .onTouch(event => this.handleDrawTouch(this.view1DrawCtx, this.view1Ctx, this.displayedPageIndices[0] ?? 0,
              event))
            .onMouse(event => this.handleDrawMouse(this.view1DrawCtx, this.view1Ctx, this.displayedPageIndices[0] ?? 0,
              event))
        }
        .size(toSize(this.view1ViewSize))
        .visibility(toVisibility(true))

        RelativeContainer() {
          Image(this.view2PixelMap).alignRules(FullRect).draggable(false)
          Canvas(this.view2Ctx)
            .size(toSize(this.getCanvasSize(this.displayedPageIndices[1] ?? 0)))
            .scale(this.getCanvasScale(1))
            .hitTestBehavior(HitTestMode.None)
          Canvas(this.view2DrawCtx)
            .size(toSize(this.getCanvasSize(this.displayedPageIndices[1] ?? 0)))
            .scale(this.getCanvasScale(1))
            .visibility(toVisibility(this.annotateMode !== 'drag'))
            .onTouch(event => this.handleDrawTouch(this.view2DrawCtx, this.view2Ctx, this.displayedPageIndices[1] ?? 0,
              event))
            .onMouse(event => this.handleDrawMouse(this.view2DrawCtx, this.view2Ctx, this.displayedPageIndices[1] ?? 0,
              event))
        }
        .size(toSize(this.view2ViewSize))
        .visibility(toVisibility(this.view2Visible))

        RelativeContainer() {
          Image(this.view3PixelMap).alignRules(FullRect).draggable(false)
          Canvas(this.view3Ctx)
            .size(toSize(this.getCanvasSize(this.displayedPageIndices[2] ?? 0)))
            .scale(this.getCanvasScale(2))
            .hitTestBehavior(HitTestMode.None)
          Canvas(this.view3DrawCtx)
            .size(toSize(this.getCanvasSize(this.displayedPageIndices[2] ?? 0)))
            .scale(this.getCanvasScale(2))
            .visibility(toVisibility(this.annotateMode !== 'drag'))
            .onTouch(event => this.handleDrawTouch(this.view3DrawCtx, this.view3Ctx, this.displayedPageIndices[2] ?? 0,
              event))
            .onMouse(event => this.handleDrawMouse(this.view3DrawCtx, this.view3Ctx, this.displayedPageIndices[2] ?? 0,
              event))
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
        .onMouse(event => this.handleMouseEvent(event))
        .onAxisEvent(event => this.handleMouseAxisEvent(event))

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
          StyleButton({
            text: this.showControls ? '收起' : '展开',
            alternateColor: this.showControls ? ButtonColor : ButtonColorSemiTransparent,
            onClickCallback: () => {
              this.setShowControls(!this.showControls);
            }
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
        }.height('100%')

        Blank();

        Column(ContainerCfg) {
          Blank()

          StyleNumBadgeButton({
            text: '撤回',
            count: this.undoHistoryCount,
            onClickCallback: () => this.executeUndo()
          }).visibility(toVisibility(this.showControls))

          StyleNumBadgeButton({
            text: '重做',
            count: this.redoHistoryCount,
            onClickCallback: () => this.executeRedo()
          }).visibility(toVisibility(this.showControls))

          StyleStrBadgeButton({
            text: '保存',
            badgeText: '!',
            badgeVisibility: this.hasUnsavedStrokes,
            onClickCallback: () => this.executeSave()
          }).visibility(toVisibility(this.showControls))

          StyleButton({ text: '<', onClickCallback: () => this.gotoPrevPage() })
            .visibility(toVisibility(this.pageFlipMode == 'button'))
        }.height('100%')

        Column(ContainerCfg) {

          StyleButton({
            text: this.isExclusiveFullScreen ? '窗口' : '全屏',
            onClickCallback: () => {
              this.isExclusiveFullScreen = !this.isExclusiveFullScreen;
              if (this.isExclusiveFullScreen) {
                this.mainWindow.maximize().catch();
              } else {
                this.mainWindow.recover().catch();
              }
            }
          }).visibility(toVisibility(this.showControls && deviceInfo.deviceType != "phone"))
          StyleButton({
            text: '分享',
            onClickCallback: () => this.executeShare()
          }).visibility(toVisibility(this.showControls)).id(ShareButtonId)
          StyleButton({
            text: '教程',
            onClickCallback: () => {
              this.getUIContext().getPromptAction().openCustomDialog({
                builder: () => this.tutorialDialogBuilder()
              })
            }
          }).visibility(toVisibility(this.showControls))

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
      .opacity(this.controlsTransparency)

    }
    .hitTestBehavior(HitTestMode.Transparent)
    .size({ width: '100%', height: '100%' })
    .backgroundColor($r('sys.color.white'))
    .onKeyEvent(keyEvent => {
      if (keyEvent.type != KeyType.Down) {
        return;
      }
      if (this == null) {
        return;
      }

      let isCtrlPressed = false;
      let isShiftPressed = false;

      if (keyEvent.getModifierKeyState != null) {
        try {
          isCtrlPressed = keyEvent.getModifierKeyState(['ctrl']);
          isShiftPressed = keyEvent.getModifierKeyState(['shift']);
        } catch (error) {
        }
      }
      switch (keyEvent.keyCode) {
        case KeyCode.KEYCODE_DPAD_UP:
        case KeyCode.KEYCODE_DPAD_LEFT:
          keyEvent.stopPropagation();
          if (isCtrlPressed) {
            this.gotoPage(0);
          } else {
            this.gotoPrevPage();
          }
          break;
        case KeyCode.KEYCODE_DPAD_DOWN:
        case KeyCode.KEYCODE_DPAD_RIGHT:
        case KeyCode.KEYCODE_SPACE:
          keyEvent.stopPropagation();
          if (isCtrlPressed) {
            this.gotoPage(this.totalPageCount - 1);
          } else {
            this.gotoNextPage();
          }
          break;
        case KeyCode.KEYCODE_Z:
          if (isCtrlPressed) {
            keyEvent.stopPropagation();
            if (isShiftPressed) {
              this.executeRedo();
            } else {
              this.executeUndo();
            }
          }
          break;
        case KeyCode.KEYCODE_Y:
          if (isCtrlPressed) {
            keyEvent.stopPropagation();
            this.executeRedo();
          }
          break;
        case KeyCode.KEYCODE_S:
          if (isCtrlPressed) {
            keyEvent.stopPropagation();
            this.executeSave();
          }
      }
    })
    .onTouchTestDone(() => this.startTransparencyTimeout())
  }
}