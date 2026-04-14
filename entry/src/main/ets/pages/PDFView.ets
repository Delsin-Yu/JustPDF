import { ButtonColor, ButtonColorSemiTransparent, ContainerCfg, ContainerPadding, ContainerSpacing, FullRect, getCheckIcon, MakeSlider, showAlertDialog, StyleButton, StyleIconBadgeButton, StyleIconButton, StyleNumBadgeButton, StyleStrBadgeButton, StyleText, TopLeft, TopRight, toResultCode, toVisibility } from '../components/UIComponents';
import { LengthMetricsUnit, window } from '@kit.ArkUI';
import { pdfService } from '@kit.PDFKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { taskpool, util } from '@kit.ArkTS';
import { fromArea, mul, pxToVp, toSizePx, Vec2, Vector2 } from '../components/Numbers';
import { preferences, uniformTypeDescriptor as utd } from '@kit.ArkData';
import { KeyCode } from '@kit.InputKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { fileUri, fileIo as fs, picker } from '@kit.CoreFileKit';
import { harmonyShare, systemShare } from '@kit.ShareKit';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { TutorialDialogBuilder } from '../components/TutorialDialog';
import { History, NewStroke, PageCache, PageGroup, PageInfo, PageInfoDataSource, ReadonlyStroke, Stroke } from '../components/PageInfo';
import { InputAction } from '../components/Input';
import { Stack as DataStack } from '../components/Colletions';
import { SettingsDialogBuilder } from '../components/SettingsDialog';

// 渲染缩放级别 - 最小为4以获得更清晰的显示，最多2个级别
const RENDER_SCALE_LEVELS: number[] = [4, 8];
const MIN_RENDER_SCALE: number = 4;
// 切换到更高渲染缩放的阈值（基于viewScale）
const SCALE_THRESHOLDS: number[] = [2.0]; // 在2.0倍视图缩放时切换到8倍

// 双指手势结束后忽略绘制/擦除触摸的延迟（毫秒）
const DUAL_FINGER_END_PROTECTION_DELAY: number = 300;

const PageFlipButtonOption: ButtonOptions = { type: ButtonType.Normal }
const PageFlipButtonSize: SizeOptions = { width: '30%', height: '100%' }
const CanvasOverSampling: number = 3;
const ShareButtonId: string = 'shareButton';

@Entry
@Component
struct PDFView {
  systemPath = '';
  sandBoxPath = '';
  saveTempPath = '';
  fileName = '';
  mainWindow: window.Window = (AppStorage.get('window') as window.Window);
  document = new pdfService.PdfDocument();
  pageGroups: PageInfoDataSource = new PageInfoDataSource();
  preferences: preferences.Preferences = AppStorage.get('preferences') as preferences.Preferences;
  currentRenderScale: number = MIN_RENDER_SCALE;
  displayedPageIndices: number[] = [];
  @State view1PixelMap: PixelMap | undefined = undefined;
  @State view2PixelMap: PixelMap | undefined = undefined;
  @State view3PixelMap: PixelMap | undefined = undefined;
  @State view2Visible: boolean = false;
  @State view3Visible: boolean = false;
  @State view1Loading: boolean = false;
  @State view2Loading: boolean = false;
  @State view3Loading: boolean = false;
  @State view1ViewSize: Vector2 = Vec2(0, 0);
  @State view2ViewSize: Vector2 = Vec2(0, 0);
  @State view3ViewSize: Vector2 = Vec2(0, 0);
  @State viewSize: Vector2 = Vec2(0, 0);
  @State currentPageIndex: number = 0;
  @State isDocumentLoading: boolean = true;
  @State loadError: string = '';
  @State totalPageCount: number = 0;
  @State pageDisplayMode: 'single' | 'dual' | 'dualContinuous' | 'tri' | 'triContinuous' = 'single';
  @State pageFlipMode: 'side' | 'button' | 'extern' = 'side';
  @State annotateMode: 'drag' | 'draw' | 'erase' = 'drag';
  @State viewPan: Vector2 = Vec2(0, 0);
  @State viewScale: number = 1.0;
  @State viewportSize: Vector2 = Vec2(0, 0);
  @State showControls: boolean = true;
  @State showSlider: boolean = true;
  @State controlsTransparency: number = 0.5;
  transparencyTimeoutId: number | undefined = undefined;
  windowStatusCallback: ((statusType: window.WindowStatusType) => void) | undefined = undefined;
  lastTouchPoint: Vector2 | undefined = undefined;
  lastPinchDistance: number | undefined = undefined;
  lastPinchCenter: Vector2 | undefined = undefined;
  lastDualFingerEndTime: number = 0;
  isDualFingerActive: boolean = false;
  lastMousePoint: Vector2 | undefined = undefined;
  activeMouseButton: number = 0; // 当前是否有双指手势激活
  readonly minScale: number = 0.5;
  readonly maxScale: number = 9.0;
  settings: RenderingContextSettings = new RenderingContextSettings(true);
  // 绘制/注释状态
  view1Ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  view2Ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  view3Ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  view1DrawCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  view2DrawCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  view3DrawCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  placeholderPixelMap: PixelMap | undefined = undefined;
  activeDrawPath: Stroke = NewStroke();
  pathsToErase: Set<ReadonlyStroke> = new Set();
  undoHistory: DataStack<History> = new DataStack<History>();
  redoHistory: DataStack<History> = new DataStack<History>();
  @State hasUnsavedStrokes: boolean = false;
  @State undoHistoryCount: number = 0;
  @State redoHistoryCount: number = 0;
  @State isExclusiveFullScreen: boolean = false;
  @State menuExpanded: boolean = false;
  hotkeys: InputAction[] = [];
  prefetchDebounceId: number | undefined = undefined;
  private documentLoadVersion: number = 0;
  tutorialDialogController: CustomDialogController = new CustomDialogController({
    builder: TutorialDialogBuilder(),
    width: '60%',
    height: '90%'
  });
  settingsDialogController: CustomDialogController = new CustomDialogController({
    builder: SettingsDialogBuilder({
      pageDisplayMode: this.pageDisplayMode,
      pageFlipMode: this.pageFlipMode,
      showSlider: this.showSlider,
      onPageDisplayModeChanged: (mode) => this.setPageDisplayMode(mode),
      onPageFlipModeChanged: (mode) => this.setPageFlipMode(mode),
      onSliderToggled: (show: boolean) => {
        this.showSlider = show;
        try {
          this.preferences.putSync('showSlider', show);
          this.preferences.flushSync();
        } catch (error) {
          hilog.error(0, 'PDFView', `保存滑块偏好出错: ${error}.`);
        }
      }
    }),
    width: '40%',
  });

  backToMainMenu(): void {
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' }).catch(() => {
    });
  }

  aboutToAppear(): void {
    const args = this.getUIContext().getRouter().getParams() as Record<string, string>;
    this.systemPath = args['systemPath'];
    this.sandBoxPath = args['sandboxPath'];
    this.saveTempPath = args['saveTempPath'];
    this.fileName = args['fileName'];

    // Lightweight setup that won't block the UI
    try {
      this.showControls = this.preferences.getSync('showControls', true) as boolean;
      this.showSlider = this.preferences.getSync('showSlider', true) as boolean;
      this.pageDisplayMode = this.preferences.getSync('pageDisplayMode', 'single') as 'single' | 'dual' | 'dualContinuous' | 'tri' | 'triContinuous';
      this.pageFlipMode = this.preferences.getSync('pageFlipMode', 'side') as 'side' | 'button' | 'extern';
      this.annotateMode = this.preferences.getSync('annotateMode', 'drag') as 'drag' | 'draw' | 'erase';
    } catch (e) {
      hilog.error(0, 'PDFView', `加载用户偏好出错: ${e}.`);
    }

    try {
      this.windowStatusCallback = (statusType: window.WindowStatusType) => this.isExclusiveFullScreen = statusType == window.WindowStatusType.FULL_SCREEN;
      this.mainWindow.on('windowStatusChange', this.windowStatusCallback);
      this.isExclusiveFullScreen = this.mainWindow.getWindowStatus() == window.WindowStatusType.FULL_SCREEN;
    } catch (error) {
      hilog.error(0, 'PDFView', `获取窗口状态出错: ${error}.`);
    }

    this.immersiveListening();
    const context = this.getUIContext().getHostContext() as Context;
    context.eventHub.on('onBackGround', this.onBackGround);

    // Register hotkeys
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_DPAD_UP, KeyCode.KEYCODE_DPAD_LEFT], false, false, () => this.gotoPrevPage()));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_DPAD_DOWN, KeyCode.KEYCODE_DPAD_RIGHT, KeyCode.KEYCODE_SPACE], false, false, () => this.gotoNextPage()));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_Z], true, false, () => this.executeUndo()));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_Z], true, true, () => this.executeRedo()));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_Y], true, false, () => this.executeRedo()));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_S], true, false, () => this.executeSave()));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_DPAD_UP, KeyCode.KEYCODE_DPAD_LEFT], true, false, () => this.gotoPage(0)));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_DPAD_DOWN, KeyCode.KEYCODE_DPAD_RIGHT, KeyCode.KEYCODE_SPACE], true, false, () => this.gotoPage(this.totalPageCount - 1)));

    // Defer heavy document loading so UI can render the loading indicator first
    this.initializeDocument();
  }

  private async initializeDocument(): Promise<void> {
    this.loadError = '';
    const loadVersion = ++this.documentLoadVersion;
    const result = this.document.loadDocument(this.sandBoxPath);
    if (result != pdfService.ParseResult.PARSE_SUCCESS) {
      let resultText = toResultCode(result);
      hilog.error(0, 'PDFView', `加载 PDF 文件出错: ${resultText}`);
      if (this.documentLoadVersion == loadVersion) {
        this.loadError = `无法加载 PDF 文件: ${resultText}`;
        this.isDocumentLoading = false;
      }
      return;
    }
    this.totalPageCount = this.document.getPageCount();
    const pages = new Array<PageInfo>();
    const pageGroup = new PageGroup(this.fileName, pages);
    for (let i = 0; i < this.totalPageCount; i++) {
      pages.push(new PageInfo(i, this.document, this.sandBoxPath));
    }
    this.pageGroups.push(pageGroup);

    // Register page reorder callback
    this.pageGroups.onPageReordered = (oldIndex: number, newIndex: number) => this.handlePageReordered(oldIndex, newIndex);

    await this.createPlaceholderPixelMap();
    await this.gotoPage(0);
    this.isDocumentLoading = false;
    this.startTransparencyTimeout();
  }

  aboutToDisappear(): void {
    this.immersiveDisablingListening();
    const context = this.getUIContext().getHostContext() as Context;
    context.eventHub.off('onBackGround', this.onBackGround);

    // 取消注册窗口状态监听
    if (this.windowStatusCallback) {
      try {
        this.mainWindow.off('windowStatusChange', this.windowStatusCallback);
      } catch (_e) { /* ignore */ }
    }

    // 清除透明度定时器
    if (this.transparencyTimeoutId) {
      clearTimeout(this.transparencyTimeoutId);
      this.transparencyTimeoutId = undefined;
    }

    // 清除预取防抖定时器
    if (this.prefetchDebounceId) {
      clearTimeout(this.prefetchDebounceId);
      this.prefetchDebounceId = undefined;
    }

    // 释放所有页面缓存和缩略图
    const totalGroups = this.pageGroups.totalCount();
    for (let i = 0; i < totalGroups; i++) {
      const group = this.pageGroups.getData(i);
      for (const page of group.pages) {
        page.evictViewerCache();
        page.releaseThumbnail();
      }
    }

    // 释放占位符 PixelMap
    if (this.placeholderPixelMap) {
      this.placeholderPixelMap.release();
      this.placeholderPixelMap = undefined;
    }

    // 释放主文档
    this.document.releaseDocument();
    hilog.info(0, 'PDFView', '页面销毁，已释放所有资源');
  }

  onPageHide(): void {
    const context = this.getUIContext().getHostContext() as Context;
    context.eventHub.emit('onBackGround');
  }

  onBackGround = () => {
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

  immersiveCallback = (sharableTarget: harmonyShare.SharableTarget) => {
    sharableTarget.share(this.makeSharedData());
  }

  immersiveListening() {
    harmonyShare.on('knockShare', this.immersiveCallback);
    harmonyShare.on('gesturesShare', this.immersiveCallback);
  }

  immersiveDisablingListening() {
    harmonyShare.off('knockShare', this.immersiveCallback);
    harmonyShare.off('gesturesShare', this.immersiveCallback);
  }

  checkHotkey(keyCode: KeyCode, isCtrlPressed: boolean, isShiftPressed: boolean): (() => void) | null {
    for (const hotkey of this.hotkeys) {
      if (hotkey.keyCodes.includes(keyCode) && hotkey.ctrl === isCtrlPressed && hotkey.shift === isShiftPressed) {
        return hotkey.action;
      }
    }
    return null;
  }

  getShowControlsText(): string {
    switch (this.annotateMode) {
      case 'drag':
        return '拖动';
      case 'draw':
        return '绘制';
      case 'erase':
        return '擦除';
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
    // Use PageInfo's async caching method with callback for automatic high-res display update
    return await this.pageGroups.getPageCacheAsync(
      targetIndex,
      renderScale,
      (highResCache: PageCache) => {
        // Automatically update display when high-res version is ready
        if (this.displayedPageIndices.includes(targetIndex)) {
          const displayIndex = this.displayedPageIndices.indexOf(targetIndex);
          if (displayIndex === 0) {
            this.view1PixelMap = highResCache.pixelMap;
          } else if (displayIndex === 1) {
            this.view2PixelMap = highResCache.pixelMap;
          } else if (displayIndex === 2) {
            this.view3PixelMap = highResCache.pixelMap;
          }
        }
      }
    );
  }

  // 根据显示模式计算要显示的页面索引
  private calculateDisplayIndices(targetIndex: number): number[] {
    switch (this.pageDisplayMode) {
      case 'single':
        return [targetIndex];

      case 'dual': {
        const index1 = targetIndex % 2 === 0 ? targetIndex : targetIndex - 1;
        const indices = [index1];
        if (index1 + 1 < this.totalPageCount) {
          indices.push(index1 + 1);
        }
        return indices;
      }

      case 'dualContinuous': {
        const indices = [targetIndex];
        if (targetIndex + 1 < this.totalPageCount) {
          indices.push(targetIndex + 1);
        }
        return indices;
      }

      case 'tri': {
        const groupIndex = Math.floor(targetIndex / 3);
        const index1 = groupIndex * 3;
        const indices = [index1];
        if (index1 + 1 < this.totalPageCount) {
          indices.push(index1 + 1);
        }
        if (index1 + 2 < this.totalPageCount) {
          indices.push(index1 + 2);
        }
        return indices;
      }

      case 'triContinuous': {
        const indices = [targetIndex];
        if (targetIndex + 1 < this.totalPageCount) {
          indices.push(targetIndex + 1);
        }
        if (targetIndex + 2 < this.totalPageCount) {
          indices.push(targetIndex + 2);
        }
        return indices;
      }
    }
  }

  // 创建 1x1 白色像素图作为页面加载时的占位符
  private async createPlaceholderPixelMap(): Promise<void> {
    const buffer = new ArrayBuffer(4);
    const view = new Uint8Array(buffer);
    view[0] = 255; // R
    view[1] = 255; // G
    view[2] = 255; // B
    view[3] = 255; // A
    const opts: image.InitializationOptions = {
      size: { width: 1, height: 1 },
      pixelFormat: image.PixelMapFormat.RGBA_8888
    };
    this.placeholderPixelMap = await image.createPixelMap(buffer, opts);
  }

  // 根据页面原始大小计算显示大小（与 cachePage 中的 displaySize 计算一致）
  private getPageDisplaySize(pageIndex: number): Vector2 {
    const rawSize = this.pageGroups.getPageRawSize(pageIndex);
    return mul(rawSize, 2);
  }

  // 加载页面缓存并更新视图状态
  private async loadAndDisplayPages(indices: number[]): Promise<void> {
    // 立即设置占位白色矩形并预计算目标页面尺寸
    this.view2Visible = false;
    this.view3Visible = false;
    this.view1Loading = false;
    this.view2Loading = false;
    this.view3Loading = false;

    if (indices.length > 0) {
      this.view1PixelMap = this.placeholderPixelMap;
      this.view1ViewSize = this.getPageDisplaySize(indices[0]);
      this.view1Loading = true;
    } else {
      this.view1PixelMap = undefined;
    }

    if (indices.length > 1) {
      this.view2PixelMap = this.placeholderPixelMap;
      this.view2ViewSize = this.getPageDisplaySize(indices[1]);
      this.view2Visible = true;
      this.view2Loading = true;
    } else {
      this.view2PixelMap = undefined;
    }

    if (indices.length > 2) {
      this.view3PixelMap = this.placeholderPixelMap;
      this.view3ViewSize = this.getPageDisplaySize(indices[2]);
      this.view3Visible = true;
      this.view3Loading = true;
    } else {
      this.view3PixelMap = undefined;
    }

    // 使用占位符尺寸立即更新总体视图大小
    this.updateViewSize();

    const tasks: Array<Promise<void>> = [];

    // 异步加载第一个页面
    if (indices.length > 0) {
      tasks.push(this.getPageCache(indices[0], this.currentRenderScale)
        .then(cache => {
          this.view1PixelMap = cache.pixelMap;
          this.view1ViewSize = cache.displaySize;
          this.view1Loading = false;
        })
      )
    }

    // 异步加载第二个页面
    if (indices.length > 1) {
      tasks.push(this.getPageCache(indices[1], this.currentRenderScale)
        .then(cache => {
          this.view2PixelMap = cache.pixelMap;
          this.view2ViewSize = cache.displaySize;
          this.view2Loading = false;
        })
      )
    }

    // 异步加载第三个页面
    if (indices.length > 2) {
      tasks.push(this.getPageCache(indices[2], this.currentRenderScale)
        .then(cache => {
          this.view3PixelMap = cache.pixelMap;
          this.view3ViewSize = cache.displaySize;
          this.view3Loading = false;
        })
      )
    }

    await Promise.all(tasks);

    // 更新总体视图大小
    this.updateViewSize();
  }

  async gotoPage(targetIndex: number): Promise<void> {
    if (targetIndex < 0 || targetIndex >= this.totalPageCount) {
      return;
    }

    this.currentPageIndex = targetIndex;
    // 导航到新页面时重置渲染缩放
    this.currentRenderScale = MIN_RENDER_SCALE;

    // 计算要显示的页面索引
    this.displayedPageIndices = this.calculateDisplayIndices(targetIndex);

    // Debounce prefetch/eviction to avoid cache churn during rapid scrolling
    if (this.prefetchDebounceId !== undefined) {
      clearTimeout(this.prefetchDebounceId);
    }
    this.prefetchDebounceId = setTimeout(() => {
      this.prefetchDebounceId = undefined;
      this.pageGroups.prefetchPagesAround(targetIndex, 5, 15, this.displayedPageIndices);
    }, 300);

    // 加载并显示页面
    await this.loadAndDisplayPages(this.displayedPageIndices);

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
    for (let i = 0; i < this.totalPageCount; i++) {
      if (this.pageGroups.getPageStrokesCount(i) > 0) {
        this.hasUnsavedStrokes = true;
        return;
      }
    }
    this.hasUnsavedStrokes = false;
  }

  loadPageStrokes(ctx: CanvasRenderingContext2D, pageIndex: number): void {
    if (this.pageGroups.getPageStrokesCount(pageIndex) === 0) {
      return;
    }
    this.applyStrokeStyle(ctx);
    this.pageGroups.stokePage(pageIndex, ctx);
  }

  appendUndoHistory(history: History): void {
    this.undoHistory.push(history);
    this.undoHistoryCount = this.undoHistory.length;
    this.redoHistory.clear();
    this.redoHistoryCount = 0;
  }

  executeUndo(): void {
    const history = this.undoHistory.pop();

    if (!history) {
      return;
    }

    this.undoHistoryCount = this.undoHistory.length;

    const needsPageNavigation = !this.displayedPageIndices.includes(history.pageIndex);
    if (needsPageNavigation) {
      this.gotoPage(history.pageIndex);
    }

    if (history.mode === 'add') {
      this.pageGroups.removeStroke(history.pageIndex, history.path as Stroke);
    } else if (history.mode === 'erase') {
      this.pageGroups.addStroke(history.pageIndex, history.path as Stroke);
    }

    this.redoHistory.push(history);
    this.redoHistoryCount = this.redoHistory.length;
    this.updateUnsavedStrokesFlag();
    this.redrawStrokes();
  }

  executeRedo(): void {
    const history = this.redoHistory.pop();

    if (!history) {
      return;
    }

    this.redoHistoryCount = this.redoHistory.length;

    const needsPageNavigation = !this.displayedPageIndices.includes(history.pageIndex);
    if (needsPageNavigation) {
      this.gotoPage(history.pageIndex);
    }

    if (history.mode === 'add') {
      this.pageGroups.addStroke(history.pageIndex, history.path as Stroke);
    } else if (history.mode === 'erase') {
      this.pageGroups.removeStroke(history.pageIndex, history.path as Stroke);
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

    const affectedPage = new Map<number, pdfService.PdfAnnotation[]>();

    const totalPageCount = this.pageGroups.totalPageCount();
    for (let pageIndex = 0; pageIndex < totalPageCount; pageIndex++) {
      if (this.pageGroups.getPageStrokesCount(pageIndex) == 0) {
        continue;
      }
      const pdfPageSize = this.pageGroups.getPageRawSize(pageIndex);
      const uiContext = this.getUIContext();
      const canvasSizePx = mul(pdfPageSize, CanvasOverSampling);
      const canvasSizeVp = pxToVp(canvasSizePx, uiContext);

      const annotationsToAdd: pdfService.PolylineAnnotationInfo[] = [];
      for (const stroke of this.pageGroups.iteratePageStrokes(pageIndex)) {
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
        annotationInfo.uniqueId = util.generateRandomUUID(true);
        annotationInfo.flag = pdfService.AnnotationFlag.PRINTED;
        annotationsToAdd.push(annotationInfo);
      }
      const annotations = this.pageGroups.addPdfAnnotations(pageIndex, annotationsToAdd);
      affectedPage.set(pageIndex, annotations);
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
        const annotations = affectedPage.get(pageIndex);
        if (!annotations) {
          continue;
        }
        this.pageGroups.removePdfAnnotations(pageIndex, annotations);
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
      await showAlertDialog('保存失败', '无法将 PDF 文件保存到选定位置。请检查权限或存储空间，然后重试。', this.getUIContext());
      this.revertChanges(affectedPage);
      return;
    }

    this.pageGroups.clearAllStrokes();
    this.undoHistory.clear();
    this.redoHistory.clear();
    this.undoHistoryCount = 0;
    this.redoHistoryCount = 0;
    this.hasUnsavedStrokes = false;

    this.invalidateAffectedPages(Array.from(affectedPage.keys()));
  }

  async revertChanges(affectedPage: Map<number, pdfService.PdfAnnotation[]>): Promise<void> {
    for (const pageIndex of affectedPage.keys()) {
      const annotations = affectedPage.get(pageIndex);
      if (!annotations) {
        continue;
      }
      this.pageGroups.removePdfAnnotations(pageIndex, annotations);
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
      this.pageGroups.invalidateCaches(pageIndex);
    }

    const currentPageAffected = this.displayedPageIndices.some(idx =>
    affectedPageIndices.includes(idx)
    );

    for (const pageIndex of affectedPageIndices) {
      this.pageGroups.ensureCached(pageIndex, MIN_RENDER_SCALE, taskpool.Priority.HIGH);
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
    controller.show(context, { anchor: ShareButtonId }).catch(() => {
    });
  }

  getCanvasSize(pageIndex: number): Vector2 {
    if (pageIndex >= this.pageGroups.totalPageCount()) {
      return Vec2(0, 0);
    }
    const pageRawSize = this.pageGroups.getPageRawSize(pageIndex);
    return mul(pageRawSize, CanvasOverSampling);
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
        this.activeDrawPath = NewStroke();
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
          this.pageGroups.addStroke(pageIndex, this.activeDrawPath);
          this.appendUndoHistory({
            path: this.activeDrawPath,
            mode: 'add',
            pageIndex: pageIndex
          });
          this.updateUnsavedStrokesFlag();
          this.loadPageStrokes(targetCtx, pageIndex);
        }
        this.activeDrawPath = NewStroke();
        drawCtx.reset();
      }
    } else if (this.annotateMode === 'erase') {
      if (this.pageGroups.getPageStrokesCount(pageIndex) === 0) {
        return;
      }

      const eraseThreshold = 20 * CanvasOverSampling;

      if (event.type === TouchType.Down) {
        this.pathsToErase.clear();
      }

      if (event.type === TouchType.Down || event.type === TouchType.Move) {
        for (const stroke of this.pageGroups.iteratePageStrokes(pageIndex)) {
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
        for (const stroke of this.pageGroups.iteratePageStrokes(pageIndex)) {
          if (!this.pathsToErase.has(stroke)) {
            stroke.stroke(targetCtx);
          }
        }
      } else if (event.type === TouchType.Up) {
        if (this.pathsToErase.size > 0) {
          this.pageGroups.removeStrokeWhere(pageIndex, stroke => this.pathsToErase.has(stroke));

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
        this.activeDrawPath = NewStroke();
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
          this.pageGroups.addStroke(pageIndex, this.activeDrawPath);
          this.appendUndoHistory({
            path: this.activeDrawPath,
            mode: 'add',
            pageIndex: pageIndex
          });
          this.updateUnsavedStrokesFlag();
          this.loadPageStrokes(targetCtx, pageIndex);
        }
        this.activeDrawPath = NewStroke();
        drawCtx.reset();
      }
    } else if (this.annotateMode === 'erase') {
      if (this.pageGroups.getPageStrokesCount(pageIndex) == 0) {
        return;
      }

      const eraseThreshold = 20 * CanvasOverSampling;

      if (event.action === MouseAction.Press) {
        this.pathsToErase.clear();
      }

      if (event.action === MouseAction.Press || (event.action === MouseAction.Move && this.activeMouseButton === 1)) {
        for (const stroke of this.pageGroups.iteratePageStrokes(pageIndex)) {
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
        for (const stroke of this.pageGroups.iteratePageStrokes(pageIndex)) {
          if (!this.pathsToErase.has(stroke)) {
            stroke.stroke(targetCtx);
          }
        }
      } else if (event.action === MouseAction.Release) {
        if (this.pathsToErase.size > 0) {
          this.pageGroups.removeStrokeWhere(pageIndex, stroke => this.pathsToErase.has(stroke));
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

  handlePageReordered(oldIndex: number, newIndex: number): void {
    hilog.info(0, 'PDFView', `处理页面重新排序: ${oldIndex} -> ${newIndex}`);

    // Determine if the current page was affected by the reorder
    const currentPage = this.currentPageIndex;
    let newCurrentPage = currentPage;

    if (currentPage === oldIndex) {
      // The current page was moved
      newCurrentPage = newIndex > oldIndex ? newIndex - 1 : newIndex;
    } else if (oldIndex < currentPage && newIndex >= currentPage) {
      // A page before the current page was moved to after it
      newCurrentPage = currentPage - 1;
    } else if (oldIndex > currentPage && newIndex <= currentPage) {
      // A page after the current page was moved to before or at it
      newCurrentPage = currentPage + 1;
    }

    // If the current page index changed, navigate to the new position
    if (newCurrentPage !== currentPage) {
      this.gotoPage(newCurrentPage);
    } else {
      // Even if the current page didn't change, we might need to refresh
      // if displayed pages were reordered (for dual/tri modes)
      const affectedRange = [
        Math.min(oldIndex, newIndex),
        Math.max(oldIndex, newIndex)
      ];
      const currentDisplayRange = [
        Math.min(...this.displayedPageIndices),
        Math.max(...this.displayedPageIndices)
      ];

      // Check if reorder affected any displayed pages
      const rangesOverlap = affectedRange[0] <= currentDisplayRange[1] &&
        affectedRange[1] >= currentDisplayRange[0];

      if (rangesOverlap) {
        this.gotoPage(this.currentPageIndex);
      }
    }
  }

  build() {
    Stack() {
      RelativeContainer() {

      Row(ContainerCfg) {

        RelativeContainer() {
          Image(this.view1PixelMap).alignRules(FullRect).draggable(false)
          Canvas(this.view1Ctx)
            .size(toSizePx(this.getCanvasSize(this.displayedPageIndices[0] ?? 0)))
            .scale(this.getCanvasScale(0))
            .hitTestBehavior(HitTestMode.None)
          Canvas(this.view1DrawCtx)
            .size(toSizePx(this.getCanvasSize(this.displayedPageIndices[0] ?? 0)))
            .scale(this.getCanvasScale(0))
            .visibility(toVisibility(this.annotateMode !== 'drag'))
            .onTouch(event => this.handleDrawTouch(this.view1DrawCtx, this.view1Ctx, this.displayedPageIndices[0] ?? 0,
              event))
            .onMouse(event => this.handleDrawMouse(this.view1DrawCtx, this.view1Ctx, this.displayedPageIndices[0] ?? 0,
              event))
          if (this.view1Loading) {
            Column() {
              LoadingProgress()
                .width(36)
                .height(36)
            }
            .width('100%')
            .height(120)
            .justifyContent(FlexAlign.End)
            .padding({ bottom: 12 })
            .linearGradient({ direction: GradientDirection.Bottom, colors: [['#00000000', 0.0], ['#33000000', 1.0]] })
            .alignRules({ bottom: { anchor: '__container__', align: VerticalAlign.Bottom } })
            .hitTestBehavior(HitTestMode.None)
          }
        }
        .size(toSizePx(this.view1ViewSize))
        .visibility(toVisibility(true))

        RelativeContainer() {
          Image(this.view2PixelMap).alignRules(FullRect).draggable(false)
          Canvas(this.view2Ctx)
            .size(toSizePx(this.getCanvasSize(this.displayedPageIndices[1] ?? 0)))
            .scale(this.getCanvasScale(1))
            .hitTestBehavior(HitTestMode.None)
          Canvas(this.view2DrawCtx)
            .size(toSizePx(this.getCanvasSize(this.displayedPageIndices[1] ?? 0)))
            .scale(this.getCanvasScale(1))
            .visibility(toVisibility(this.annotateMode !== 'drag'))
            .onTouch(event => this.handleDrawTouch(this.view2DrawCtx, this.view2Ctx, this.displayedPageIndices[1] ?? 0,
              event))
            .onMouse(event => this.handleDrawMouse(this.view2DrawCtx, this.view2Ctx, this.displayedPageIndices[1] ?? 0,
              event))
          if (this.view2Loading) {
            Column() {
              LoadingProgress()
                .width(36)
                .height(36)
            }
            .width('100%')
            .height(120)
            .justifyContent(FlexAlign.End)
            .padding({ bottom: 12 })
            .linearGradient({ direction: GradientDirection.Bottom, colors: [['#00000000', 0.0], ['#33000000', 1.0]] })
            .alignRules({ bottom: { anchor: '__container__', align: VerticalAlign.Bottom } })
            .hitTestBehavior(HitTestMode.None)
          }
        }
        .size(toSizePx(this.view2ViewSize))
        .visibility(toVisibility(this.view2Visible))

        RelativeContainer() {
          Image(this.view3PixelMap).alignRules(FullRect).draggable(false)
          Canvas(this.view3Ctx)
            .size(toSizePx(this.getCanvasSize(this.displayedPageIndices[2] ?? 0)))
            .scale(this.getCanvasScale(2))
            .hitTestBehavior(HitTestMode.None)
          Canvas(this.view3DrawCtx)
            .size(toSizePx(this.getCanvasSize(this.displayedPageIndices[2] ?? 0)))
            .scale(this.getCanvasScale(2))
            .visibility(toVisibility(this.annotateMode !== 'drag'))
            .onTouch(event => this.handleDrawTouch(this.view3DrawCtx, this.view3Ctx, this.displayedPageIndices[2] ?? 0,
              event))
            .onMouse(event => this.handleDrawMouse(this.view3DrawCtx, this.view3Ctx, this.displayedPageIndices[2] ?? 0,
              event))
          if (this.view3Loading) {
            Column() {
              LoadingProgress()
                .width(36)
                .height(36)
            }
            .width('100%')
            .height(120)
            .justifyContent(FlexAlign.End)
            .padding({ bottom: 12 })
            .linearGradient({ direction: GradientDirection.Bottom, colors: [['#00000000', 0.0], ['#33000000', 1.0]] })
            .alignRules({ bottom: { anchor: '__container__', align: VerticalAlign.Bottom } })
            .hitTestBehavior(HitTestMode.None)
          }
        }
        .size(toSizePx(this.view3ViewSize))
        .visibility(toVisibility(this.view3Visible))
      }
      .alignRules(TopLeft)
      .offset(this.viewPan)
      .size(toSizePx(this.viewSize))
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


      Stack() {
        // Slider - positioned at right, vertically centered, independent of bottom bar
        Column(ContainerCfg) {
          Blank().layoutWeight(1)
          MakeSlider(
            {
              value: this.currentPageIndex,
              min: 0,
              max: this.totalPageCount - 1,
              onChangeCallback: newValue => this.gotoPage(newValue)
            }
          ).visibility(toVisibility(this.showControls && this.showSlider))
          Blank().height(60)
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.End)
        .hitTestBehavior(HitTestMode.Transparent)

        // Bottom bar
        Column() {
          Blank().layoutWeight(1)
          Row(ContainerCfg) {
          // Bottom-left: expandable menu
          Column({ space: ContainerSpacing }) {
            if (this.menuExpanded) {
              StyleIconButton({
                icon: $r('sys.symbol.questionmark_circle'),
                label: '教程',
                onClickCallback: () => {
                  this.menuExpanded = false;
                  this.tutorialDialogController.open();
                }
              }).transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 })))

              if (deviceInfo.deviceType != 'phone') {
                StyleIconButton({
                  icon: this.isExclusiveFullScreen ? $r('sys.symbol.arrow_down_right_and_arrow_up_left') : $r('sys.symbol.arrow_up_left_and_arrow_down_right'),
                  label: this.isExclusiveFullScreen ? '窗口' : '全屏',
                  onClickCallback: () => {
                    this.isExclusiveFullScreen = !this.isExclusiveFullScreen;
                    if (this.isExclusiveFullScreen) {
                      this.mainWindow.maximize().catch();
                    } else {
                      this.mainWindow.recover().catch();
                    }
                  }
                }).transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 })))
              }

              StyleIconButton({
                icon: $r('sys.symbol.share'),
                label: '分享',
                onClickCallback: () => {
                  animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                    this.menuExpanded = false;
                  });
                  this.executeShare();
                }
              }).transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 })))

              StyleIconButton({
                icon: $r('sys.symbol.gearshape'),
                label: '设置',
                onClickCallback: () => {
                  this.menuExpanded = false;
                  this.settingsDialogController.open();
                }
              }).transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 })))

              StyleIconButton({
                icon: $r('sys.symbol.arrow_right'),
                label: '跳转',
                menuElement: [
                  {
                    value: "重置视口",
                    action: () => this.resetViewToFit(),
                  },
                  {
                    value: "跳转首页",
                    action: () => this.gotoPage(0),
                  },
                  {
                    value: "跳转尾页",
                    action: () => this.gotoPage(this.totalPageCount - 1),
                  }],
                menuPlacement: Placement.RightBottom
              }).transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 })))

              StyleIconButton({
                icon: $r('sys.symbol.pencil_waveform'),
                label: this.getShowControlsText(),
                menuElement: [
                  {
                    value: "拖动",
                    action: () => this.setAnnotateMode('drag'),
                    symbolIcon: getCheckIcon(this.annotateMode == 'drag')
                  },
                  {
                    value: "绘制",
                    action: () => this.setAnnotateMode('draw'),
                    symbolIcon: getCheckIcon(this.annotateMode == 'draw')
                  },
                  {
                    value: "擦除",
                    action: () => this.setAnnotateMode('erase'),
                    symbolIcon: getCheckIcon(this.annotateMode == 'erase')
                  }],
                menuPlacement: Placement.RightBottom
              }).transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 })))
            }

            StyleIconButton({
              icon: this.menuExpanded ? $r('sys.symbol.xmark') : $r('sys.symbol.more'),
              alternateColor: this.menuExpanded ? ButtonColor : ButtonColorSemiTransparent,
              onClickCallback: () => {
                animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                  this.menuExpanded = !this.menuExpanded;
                });
              }
            }).id(ShareButtonId)
          }
          .alignItems(HorizontalAlign.Start)

          Blank()

          StyleIconBadgeButton({
            icon: $r('sys.symbol.undo'),
            count: this.undoHistoryCount,
            onClickCallback: () => this.executeUndo()
          }).visibility(toVisibility(this.showControls && (this.undoHistoryCount > 0 || this.redoHistoryCount > 0 || this.hasUnsavedStrokes)))
            .enabled(this.undoHistoryCount > 0)
            .opacity(this.undoHistoryCount > 0 ? 1.0 : 0.4)
          StyleIconBadgeButton({
            icon: $r('sys.symbol.redo'),
            count: this.redoHistoryCount,
            onClickCallback: () => this.executeRedo()
          }).visibility(toVisibility(this.showControls && (this.undoHistoryCount > 0 || this.redoHistoryCount > 0 || this.hasUnsavedStrokes)))
            .enabled(this.redoHistoryCount > 0)
            .opacity(this.redoHistoryCount > 0 ? 1.0 : 0.4)
          StyleIconButton({
            icon: $r('sys.symbol.save'),
            onClickCallback: () => this.executeSave()
          }).visibility(toVisibility(this.showControls && (this.undoHistoryCount > 0 || this.redoHistoryCount > 0 || this.hasUnsavedStrokes)))
            .enabled(this.hasUnsavedStrokes)
            .opacity(this.hasUnsavedStrokes ? 1.0 : 0.4)
          StyleButton({ text: '<', onClickCallback: () => this.gotoPrevPage() })
            .visibility(toVisibility(this.pageFlipMode == 'button'))
          StyleButton({ text: '>', onClickCallback: () => this.gotoNextPage() })
            .visibility(toVisibility(this.pageFlipMode == 'button'))
          StyleText({ text: `${this.currentPageIndex + 1}/${this.totalPageCount}` }).visibility(toVisibility(this.pageFlipMode != 'button'))

        }.width('100%').alignItems(VerticalAlign.Bottom)
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }
      .alignContent(Alignment.BottomStart)
      .alignRules(FullRect)
      .margin(ContainerPadding)
      .hitTestBehavior(HitTestMode.Transparent)
      .opacity(this.controlsTransparency)
    }
    .hitTestBehavior(HitTestMode.Transparent)
    .size({ width: '100%', height: '100%' })
    .backgroundColor($r('sys.color.white'))
    .focusable(true)
    .defaultFocus(true)
    .focusOnTouch(true)
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

      const action = this.checkHotkey(keyEvent.keyCode, isCtrlPressed, isShiftPressed);
      if (action !== null) {
        keyEvent.stopPropagation();
        action();
      }
    })
    .onTouchTestDone(() => this.startTransparencyTimeout())

      if (this.isDocumentLoading) {
        Column() {
          LoadingProgress()
            .width(64)
            .height(64)
          Text(`正在加载 ${this.fileName}`)
            .fontSize(16)
            .fontColor(Color.Gray)
            .margin({ top: 12 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('sys.color.white'))
      }

      if (this.loadError != '') {
        Column() {
          Column({ space: 20 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
              .fontSize(48)
              .fontColor([Color.Red])
            Text('加载失败')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
            Text(this.loadError)
              .fontSize(14)
              .fontColor('#999999')
              .textAlign(TextAlign.Center)
              .constraintSize({ maxWidth: 260 })
            Button('返回')
              .type(ButtonType.Capsule)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .width(120)
              .margin({ top: 4 })
              .onClick(() => this.backToMainMenu())
          }
          .padding(32)
          .borderRadius(16)
          .backgroundColor('#F5F5F5')
          .shadow({ radius: 8, color: 'rgba(0, 0, 0, 0.1)', offsetY: 2 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('sys.color.white'))
      }
    }
    .width('100%')
    .height('100%')
  }
}