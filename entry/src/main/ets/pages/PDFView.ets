import { ContainerCfg, ContainerPadding, FullRect, MakeSlider, showAlertDialog, TopLeft, TopRight, toResultCode, toVisibility } from '../components/UIComponents';
import { LengthMetricsUnit, window } from '@kit.ArkUI';
import { pdfService } from '@kit.PDFKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { taskpool } from '@kit.ArkTS';
import { fromArea, mul, pxToVp, toSizePx, Vec2, Vector2 } from '../components/Numbers';
import { preferences, uniformTypeDescriptor as utd } from '@kit.ArkData';
import { KeyCode } from '@kit.InputKit';
import { fileUri } from '@kit.CoreFileKit';
import { harmonyShare, systemShare } from '@kit.ShareKit';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { TutorialDialogBuilder } from '../components/TutorialDialog';
import { PageCache, PageInfo, PageStore } from '../components/PageInfo';
import { InputAction } from '../components/Input';
import { SettingsDialogBuilder } from '../components/SettingsDialog';
import { PDFAnnotationController } from './pdfview/PDFAnnotationController';
import { PDFMetronomeController } from './pdfview/PDFMetronomeController';
import { PDFPageSlot } from './pdfview/PDFPageSlot';
import { PDFMetronomePanel } from './pdfview/PDFMetronomePanel';
import { PDFViewerActionMenu } from './pdfview/PDFViewerActionMenu';
import { PDFViewerBottomBar } from './pdfview/PDFViewerBottomBar';
import { PDFViewerViewModel, ViewerMinRenderScale } from './pdfview/PDFViewerViewModel';

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
  pageDataSource: PageStore = new PageStore();
  preferences: preferences.Preferences = AppStorage.get('preferences') as preferences.Preferences;
  viewerViewModel: PDFViewerViewModel = new PDFViewerViewModel();
  currentRenderScale: number = ViewerMinRenderScale;
  @State view1PixelMap: PixelMap | undefined = undefined;
  @State view2PixelMap: PixelMap | undefined = undefined;
  @State view3PixelMap: PixelMap | undefined = undefined;
  @State view1Loading: boolean = false;
  @State view2Loading: boolean = false;
  @State view3Loading: boolean = false;
  @State view1ViewSize: Vector2 = Vec2(0, 0);
  @State view2ViewSize: Vector2 = Vec2(0, 0);
  @State view3ViewSize: Vector2 = Vec2(0, 0);
  @State isDocumentLoading: boolean = true;
  @State loadError: string = '';
  transparencyTimeoutId: number | undefined = undefined;
  windowStatusCallback: ((statusType: window.WindowStatusType) => void) | undefined = undefined;
  lastTouchPoint: Vector2 | undefined = undefined;
  lastPinchDistance: number | undefined = undefined;
  lastPinchCenter: Vector2 | undefined = undefined;
  lastDualFingerEndTime: number = 0;
  isDualFingerActive: boolean = false;
  lastMousePoint: Vector2 | undefined = undefined;
  activeMouseButton: number = 0; // 当前是否有双指手势激活
  settings: RenderingContextSettings = new RenderingContextSettings(true);
  // 绘制/注释状态
  view1Ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  view2Ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  view3Ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  view1DrawCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  view2DrawCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  view3DrawCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  placeholderPixelMap: PixelMap | undefined = undefined;
  transparentPlaceholderPixelMap: PixelMap | undefined = undefined;
  annotationController: PDFAnnotationController = new PDFAnnotationController({
    pageDataSource: this.pageDataSource,
    viewerViewModel: this.viewerViewModel,
    document: this.document,
    getSystemPath: () => this.systemPath,
    getSandBoxPath: () => this.sandBoxPath,
    getSaveTempPath: () => this.saveTempPath,
    getUIContext: () => this.getUIContext(),
    onRequestGotoPage: (pageIndex: number) => {
      this.gotoPage(pageIndex);
    },
    onRedrawRequested: () => this.redrawStrokes(),
    onRefreshDisplayedPages: () => this.refreshDisplayedPages()
  }, CanvasOverSampling);
  metronomeController: PDFMetronomeController = new PDFMetronomeController({
    getUIContext: () => this.getUIContext(),
    getHostContext: () => this.getUIContext().getHostContext() as common.UIAbilityContext
  });
  @State isExclusiveFullScreen: boolean = false;
  hotkeys: InputAction[] = [];
  prefetchDebounceId: number | undefined = undefined;
  // 每次 gotoPage 调用时递增；用于忽略在页面切换后才完成的过期异步加载回调，
  // 避免快速翻页后显示内容与当前页码不符。
  private pageLoadVersion: number = 0;
  private documentLoadVersion: number = 0;
  tutorialDialogController: CustomDialogController = new CustomDialogController({
    builder: TutorialDialogBuilder(),
    width: '60%',
    height: '90%'
  });
  settingsDialogController: CustomDialogController = new CustomDialogController({
    builder: SettingsDialogBuilder({
      showSlider: this.viewerViewModel.showSlider,
      onSliderToggled: (show: boolean) => {
        this.viewerViewModel.setShowSlider(show);
      }
    }),
    width: '40%',
  });

  backToMainMenu(): void {
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' }).catch(() => {
    });
  }

  rebuildSettingsDialogController(): void {
    this.settingsDialogController = new CustomDialogController({
      builder: SettingsDialogBuilder({
        showSlider: this.viewerViewModel.showSlider,
        onSliderToggled: (show: boolean) => {
          this.viewerViewModel.setShowSlider(show);
        }
      }),
      width: '40%'
    });
  }

  aboutToAppear(): void {
    let args = this.getUIContext().getRouter().getParams() as Record<string, string>;
    if ((args == null || args['sandboxPath'] == null || args['sandboxPath'] == '')
      && AppStorage.has('initialPdfViewArgs')) {
      args = AppStorage.get<Record<string, string>>('initialPdfViewArgs') as Record<string, string>;
      AppStorage.delete('initialPdfViewArgs');
    }
    this.systemPath = args['systemPath'];
    this.sandBoxPath = args['sandboxPath'];
    this.saveTempPath = args['saveTempPath'];
    this.fileName = args['fileName'];

    // Lightweight setup that won't block the UI
    try {
      this.viewerViewModel.loadPreferences(this.preferences);
      this.rebuildSettingsDialogController();
      this.metronomeController.initialize(this.preferences);
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
  this.hotkeys.push(new InputAction([KeyCode.KEYCODE_DPAD_UP, KeyCode.KEYCODE_DPAD_LEFT], false, false, () => this.navigatePrevPage()));
  this.hotkeys.push(new InputAction([KeyCode.KEYCODE_DPAD_DOWN, KeyCode.KEYCODE_DPAD_RIGHT, KeyCode.KEYCODE_SPACE], false, false, () => this.navigateNextPage()));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_Z], true, false, () => this.annotationController.executeUndo()));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_Z], true, true, () => this.annotationController.executeRedo()));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_Y], true, false, () => this.annotationController.executeRedo()));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_S], true, false, () => this.annotationController.executeSave()));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_DPAD_UP, KeyCode.KEYCODE_DPAD_LEFT], true, false, () => this.gotoPage(0)));
  this.hotkeys.push(new InputAction([KeyCode.KEYCODE_DPAD_DOWN, KeyCode.KEYCODE_DPAD_RIGHT, KeyCode.KEYCODE_SPACE], true, false, () => this.gotoPage(this.viewerViewModel.getLastNavigableIndex())));

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
    this.viewerViewModel.setTotalPageCount(this.document.getPageCount());
    for (let i = 0; i < this.viewerViewModel.totalPageCount; i++) {
      this.pageDataSource.push(new PageInfo(i, this.document, this.sandBoxPath));
    }

    await this.createPlaceholderPixelMap();
    await this.gotoPage(0);
    this.isDocumentLoading = false;
    this.startTransparencyTimeout();
  }

  aboutToDisappear(): void {
    this.metronomeController.cleanup();
    this.immersiveDisablingListening();
    const context = this.getUIContext().getHostContext() as Context;
    context.eventHub.off('onBackGround', this.onBackGround);

    // 取消注册窗口状态监听
    if (this.windowStatusCallback) {
      try {
        this.mainWindow.off('windowStatusChange', this.windowStatusCallback);
      } catch (_e) { /* ignore */
      }
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
    const totalPages = this.pageDataSource.totalCount();
    for (let i = 0; i < totalPages; i++) {
      const page = this.pageDataSource.getData(i);
      page.evictViewerCache();
      page.releaseThumbnail();
    }

    // 释放占位符 PixelMap
    if (this.placeholderPixelMap) {
      this.placeholderPixelMap.release();
      this.placeholderPixelMap = undefined;
    }
    if (this.transparentPlaceholderPixelMap) {
      this.transparentPlaceholderPixelMap.release();
      this.transparentPlaceholderPixelMap = undefined;
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
    this.metronomeController.stopPlayback();
    this.immersiveDisablingListening();
  }

  makeSharedData(): systemShare.SharedData {
    const shareData: systemShare.SharedData = new systemShare.SharedData({
      utd: utd.UniformDataType.PDF,
      uri: fileUri.getUriFromPath(this.sandBoxPath),
      title: this.fileName,
      description: `共 ${this.viewerViewModel.totalPageCount} 页`
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

  // 检查当前显示的页面是否需要以不同的缩放重新渲染
  async checkAndUpdateRenderScale(): Promise<void> {
    const requiredScale = this.viewerViewModel.getRenderScaleForViewScale();

    if (requiredScale !== this.currentRenderScale) {
      hilog.info(0, 'PDFView', `检测到缩放变化: ${this.currentRenderScale} -> ${requiredScale}`);
      this.currentRenderScale = requiredScale;
      // 以新缩放重新渲染当前显示的页面
      await this.updateDisplayedPagesAtScale(requiredScale);
    }
  }

  // 以指定的渲染缩放更新显示的页面
  async updateDisplayedPagesAtScale(renderScale: number): Promise<void> {
    const loadVersion = this.pageLoadVersion;
    for (const pageIndex of this.viewerViewModel.displayedPageIndices) {
      const cache = await this.getPageCache(pageIndex, renderScale, loadVersion);
      // 在等待期间若已发生页面切换则丢弃结果
      if (loadVersion !== this.pageLoadVersion) return;
      // 更新相应视图的 pixelMap
      const displayIndex = this.viewerViewModel.displayedPageIndices.indexOf(pageIndex);
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
    this.updateViewerViewSize();
  }

  updateViewerViewSize(): void {
    this.viewerViewModel.updateViewSize(this.view1ViewSize, this.view2ViewSize, this.view3ViewSize);
  }

  async getPageCache(targetIndex: number, renderScale: number = ViewerMinRenderScale,
    loadVersion: number = this.pageLoadVersion): Promise<PageCache> {
    // Use PageInfo's async caching method with callback for automatic high-res display update
    return await this.pageDataSource.getPageCacheAsync(
      targetIndex,
      renderScale,
      (highResCache: PageCache) => {
        // 如果在高分辨率渲染完成前用户已切换到其他页面，则丢弃此次更新
        if (loadVersion !== this.pageLoadVersion) {
          return;
        }
        // Automatically update display when high-res version is ready
        if (this.viewerViewModel.displayedPageIndices.includes(targetIndex)) {
          const displayIndex = this.viewerViewModel.displayedPageIndices.indexOf(targetIndex);
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

  // 创建占位像素图：白色（加载中）和透明（空槽位）
  private async createPlaceholderPixelMap(): Promise<void> {
    const opts: image.InitializationOptions = {
      size: { width: 1, height: 1 },
      pixelFormat: image.PixelMapFormat.RGBA_8888
    };
    const whiteBuffer = new ArrayBuffer(4);
    const whiteView = new Uint8Array(whiteBuffer);
    whiteView[0] = 255; // R
    whiteView[1] = 255; // G
    whiteView[2] = 255; // B
    whiteView[3] = 255; // A
    this.placeholderPixelMap = await image.createPixelMap(whiteBuffer, opts);
    const transparentBuffer = new ArrayBuffer(4);
    // 所有字节默认为 0，即透明黑色 (RGBA 0,0,0,0)
    this.transparentPlaceholderPixelMap = await image.createPixelMap(transparentBuffer, opts);
  }

  // 根据页面原始大小计算显示大小（与 cachePage 中的 displaySize 计算一致）
  private getPageDisplaySize(pageIndex: number): Vector2 {
    const rawSize = this.pageDataSource.getPageRawSize(pageIndex);
    return mul(rawSize, 2);
  }

  // 加载页面缓存并更新视图状态
  private async loadAndDisplayPages(indices: number[]): Promise<void> {
    // 捕获当前加载版本；若在异步过程中 gotoPage 再次被调用则放弃过期的状态更新
    const loadVersion = this.pageLoadVersion;
    // 立即设置占位白色矩形并预计算目标页面尺寸
    this.view1Loading = false;
    this.view2Loading = false;
    this.view3Loading = false;

    // 根据显示模式确定期望的槽位数，剩余页面不足时仍用白色占位保持布局稳定
    const expectedSlots: number = this.viewerViewModel.getExpectedSlotCount();

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
      this.view2Loading = true;
    } else if (expectedSlots >= 2) {
      // 空占位：透明区域保持与最后一个实际页面相同大小，避免多页模式下末尾出现布局跳变
      this.view2PixelMap = this.transparentPlaceholderPixelMap;
      this.view2ViewSize = this.getPageDisplaySize(indices[indices.length - 1]);
      this.view2Loading = false;
    } else {
      this.view2PixelMap = undefined;
      this.view2ViewSize = Vec2(0, 0);
    }

    if (indices.length > 2) {
      this.view3PixelMap = this.placeholderPixelMap;
      this.view3ViewSize = this.getPageDisplaySize(indices[2]);
      this.view3Loading = true;
    } else if (expectedSlots >= 3) {
      // 空占位：透明区域保持与最后一个实际页面相同大小，避免多页模式下末尾出现布局跳变
      this.view3PixelMap = this.transparentPlaceholderPixelMap;
      this.view3ViewSize = this.getPageDisplaySize(indices[indices.length - 1]);
      this.view3Loading = false;
    } else {
      this.view3PixelMap = undefined;
      this.view3ViewSize = Vec2(0, 0);
    }

    // 使用占位符尺寸立即更新总体视图大小
    this.updateViewerViewSize();

    const tasks: Array<Promise<void>> = [];

    // 异步加载第一个页面
    if (indices.length > 0) {
      tasks.push(this.getPageCache(indices[0], this.currentRenderScale, loadVersion)
        .then(cache => {
          if (loadVersion !== this.pageLoadVersion) return;
          this.view1PixelMap = cache.pixelMap;
          this.view1ViewSize = cache.displaySize;
          this.view1Loading = false;
        })
      )
    }

    // 异步加载第二个页面
    if (indices.length > 1) {
      tasks.push(this.getPageCache(indices[1], this.currentRenderScale, loadVersion)
        .then(cache => {
          if (loadVersion !== this.pageLoadVersion) return;
          this.view2PixelMap = cache.pixelMap;
          this.view2ViewSize = cache.displaySize;
          this.view2Loading = false;
        })
      )
    }

    // 异步加载第三个页面
    if (indices.length > 2) {
      tasks.push(this.getPageCache(indices[2], this.currentRenderScale, loadVersion)
        .then(cache => {
          if (loadVersion !== this.pageLoadVersion) return;
          this.view3PixelMap = cache.pixelMap;
          this.view3ViewSize = cache.displaySize;
          this.view3Loading = false;
        })
      )
    }

    await Promise.all(tasks);

    // 若在加载期间已切到其他页面，不再更新视图大小
    if (loadVersion !== this.pageLoadVersion) return;

    // 更新总体视图大小
    this.updateViewerViewSize();
  }

  async gotoPage(targetIndex: number): Promise<void> {
    if (targetIndex < 0 || targetIndex >= this.viewerViewModel.totalPageCount) {
      return;
    }

    // 递增加载版本以使上一个 gotoPage 发起的所有异步回调失效
    this.pageLoadVersion++;

    this.viewerViewModel.commitPageTarget(targetIndex);
    // 导航到新页面时重置渲染缩放
    this.currentRenderScale = ViewerMinRenderScale;

    // Debounce prefetch/eviction to avoid cache churn during rapid scrolling
    if (this.prefetchDebounceId !== undefined) {
      clearTimeout(this.prefetchDebounceId);
    }
    this.prefetchDebounceId = setTimeout(() => {
      this.prefetchDebounceId = undefined;
      this.pageDataSource.prefetchPagesAround(targetIndex, 5, 15, this.viewerViewModel.displayedPageIndices);
    }, 300);

    // 加载并显示页面
    await this.loadAndDisplayPages(this.viewerViewModel.displayedPageIndices);

    // 重置视图以适应视口中的内容
    this.resetViewToFit();
    this.redrawStrokes();
  }

  resetViewToFit(): void {
    this.viewerViewModel.resetViewToFit(this.getUIContext());
  }

  navigatePrevPage(): void {
    this.gotoPage(this.viewerViewModel.navigateToPreviousPage());
  }

  navigateNextPage(): void {
    this.gotoPage(this.viewerViewModel.navigateToNextPage());
  }

  async refreshDisplayedPages(): Promise<void> {
    for (let i = 0; i < this.viewerViewModel.displayedPageIndices.length; i++) {
      const pageIndex = this.viewerViewModel.displayedPageIndices[i];
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
    this.updateViewerViewSize();
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
    for (let i = 0; i < this.viewerViewModel.displayedPageIndices.length; i++) {
      const pageIndex = this.viewerViewModel.displayedPageIndices[i];
      if (i === 0) {
        this.annotationController.loadPageStrokes(this.view1Ctx, pageIndex);
      } else if (i === 1) {
        this.annotationController.loadPageStrokes(this.view2Ctx, pageIndex);
      } else if (i === 2) {
        this.annotationController.loadPageStrokes(this.view3Ctx, pageIndex);
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
    if (pageIndex >= this.pageDataSource.totalPageCount()) {
      return Vec2(0, 0);
    }
    const pageRawSize = this.pageDataSource.getPageRawSize(pageIndex);
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

    const pageIndex = this.viewerViewModel.displayedPageIndices[viewIndex] ?? 0;
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
      const resetResult = this.annotationController.resetTransientState();
      if (resetResult.clearedDraw) {
        drawCtx.reset();
      }
      if (resetResult.clearedErase) {
        this.redrawStrokes();
      }
      return;
    }

    const touchPoint = Vec2(event.touches[0].x, event.touches[0].y);

    if (this.annotationController.annotateMode === 'draw') {
      if (event.type === TouchType.Down) {
        this.annotationController.startDraw(touchPoint);
      } else if (event.type === TouchType.Move) {
        this.annotationController.extendDraw(touchPoint, drawCtx);
      } else if (event.type === TouchType.Up) {
        this.annotationController.finishDraw(pageIndex, touchPoint, drawCtx, targetCtx);
      }
    } else if (this.annotationController.annotateMode === 'erase') {
      if (this.pageDataSource.getPageStrokesCount(pageIndex) === 0) {
        return;
      }

      if (event.type === TouchType.Down) {
        this.annotationController.startErase();
      }

      if (event.type === TouchType.Down || event.type === TouchType.Move) {
        this.annotationController.previewErase(pageIndex, touchPoint, targetCtx);
      } else if (event.type === TouchType.Up) {
        this.annotationController.finishErase(pageIndex, targetCtx);
      }
    }
  }

  handleViewAction(event: TouchEvent): void {
    const isSingleTouch = event.touches.length === 1 && event.touches[0].id === 0;
    const isDualTouch = event.touches.length === 2 && event.touches[0].id === 0 && event.touches[1].id === 1;
    const isTripleTouch =
      event.touches.length === 3 && event.touches[0].id === 0 && event.touches[1].id === 1 && event.touches[2].id === 2;

    if (isTripleTouch) {
      if (event.type === TouchType.Down && (this.annotationController.annotateMode === 'draw' || this.annotationController.annotateMode === 'erase')) {
        this.annotationController.executeUndo();
      }
      return;
    }

    if (isSingleTouch) {
      // 仅在拖动模式下处理单指平移
      if (this.viewerViewModel.annotateMode !== 'drag') {
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
          this.viewerViewModel.panBy(delta, this.getUIContext());
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
      const resetResult = this.annotationController.resetTransientState();
      if (resetResult.clearedDraw) {
        this.view1DrawCtx.reset();
        this.view2DrawCtx.reset();
        this.view3DrawCtx.reset();
      }
      if (resetResult.clearedErase) {
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

          // 计算捏合中心运动（拖动分量）
          const centerDeltaX = pinchCenter.x - this.lastPinchCenter.x;
          const centerDeltaY = pinchCenter.y - this.lastPinchCenter.y;
          this.viewerViewModel.zoomAround(pinchCenter, scaleRatio, Vec2(centerDeltaX, centerDeltaY), this.getUIContext());

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

        if (this.viewerViewModel.annotateMode === 'drag') {
          if (this.activeMouseButton === 1 || this.activeMouseButton === 2) {
            this.viewerViewModel.panBy(delta, this.getUIContext());
          }
        } else {
          if (this.activeMouseButton === 2) {
            this.viewerViewModel.panBy(delta, this.getUIContext());
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

    if (this.annotationController.annotateMode === 'draw') {
      if (event.action === MouseAction.Press) {
        this.annotationController.startDraw(mousePoint);
      } else if (event.action === MouseAction.Move && this.activeMouseButton === 1) {
        this.annotationController.extendDraw(mousePoint, drawCtx);
      } else if (event.action === MouseAction.Release) {
        this.annotationController.finishDraw(pageIndex, mousePoint, drawCtx, targetCtx);
      }
    } else if (this.annotationController.annotateMode === 'erase') {
      if (this.pageDataSource.getPageStrokesCount(pageIndex) == 0) {
        return;
      }

      if (event.action === MouseAction.Press) {
        this.annotationController.startErase();
      }

      if (event.action === MouseAction.Press || (event.action === MouseAction.Move && this.activeMouseButton === 1)) {
        this.annotationController.previewErase(pageIndex, mousePoint, targetCtx);
      } else if (event.action === MouseAction.Release) {
        this.annotationController.finishErase(pageIndex, targetCtx);
      }
    }
  }

  handleMouseAxisEvent(event: AxisEvent): void {
    const scrollAmount = -event.getVerticalAxisValue();
    if (scrollAmount != undefined && scrollAmount != 0) {
      const mousePoint = Vec2(event.x, event.y);
      const zoomFactor = scrollAmount > 0 ? 1.1 : 0.9;
      this.viewerViewModel.zoomAround(mousePoint, zoomFactor, Vec2(0, 0), this.getUIContext());

      this.checkAndUpdateRenderScale();
    }
  }

  startTransparencyTimeout(): void {
    if (this.transparencyTimeoutId) {
      clearTimeout(this.transparencyTimeoutId);
    }
    this.viewerViewModel.controlsTransparency = 1;
    this.transparencyTimeoutId = setTimeout(() => this.viewerViewModel.controlsTransparency = 0.5, 1000 * 3);
  }

  build() {
    Stack() {
      RelativeContainer() {

        Row(ContainerCfg) {

          PDFPageSlot({
            pixelMap: this.view1PixelMap,
            loading: this.view1Loading,
            viewSize: this.view1ViewSize,
            canvasSize: this.getCanvasSize(this.viewerViewModel.displayedPageIndices[0] ?? 0),
            canvasScale: this.getCanvasScale(0),
            visible: true,
            drawCanvasVisible: this.viewerViewModel.annotateMode !== 'drag',
            annotateCtx: this.view1Ctx,
            drawCtx: this.view1DrawCtx,
            onDrawTouch: (event: TouchEvent) => this.handleDrawTouch(this.view1DrawCtx, this.view1Ctx, this.viewerViewModel.displayedPageIndices[0] ?? 0, event),
            onDrawMouse: (event: MouseEvent) => this.handleDrawMouse(this.view1DrawCtx, this.view1Ctx, this.viewerViewModel.displayedPageIndices[0] ?? 0, event)
          })

          PDFPageSlot({
            pixelMap: this.view2PixelMap,
            loading: this.view2Loading,
            viewSize: this.view2ViewSize,
            canvasSize: this.getCanvasSize(this.viewerViewModel.displayedPageIndices[1] ?? 0),
            canvasScale: this.getCanvasScale(1),
            visible: this.viewerViewModel.shouldShowSecondSlot(),
            drawCanvasVisible: this.viewerViewModel.annotateMode !== 'drag',
            annotateCtx: this.view2Ctx,
            drawCtx: this.view2DrawCtx,
            onDrawTouch: (event: TouchEvent) => this.handleDrawTouch(this.view2DrawCtx, this.view2Ctx, this.viewerViewModel.displayedPageIndices[1] ?? 0, event),
            onDrawMouse: (event: MouseEvent) => this.handleDrawMouse(this.view2DrawCtx, this.view2Ctx, this.viewerViewModel.displayedPageIndices[1] ?? 0, event)
          })

          PDFPageSlot({
            pixelMap: this.view3PixelMap,
            loading: this.view3Loading,
            viewSize: this.view3ViewSize,
            canvasSize: this.getCanvasSize(this.viewerViewModel.displayedPageIndices[2] ?? 0),
            canvasScale: this.getCanvasScale(2),
            visible: this.viewerViewModel.shouldShowThirdSlot(),
            drawCanvasVisible: this.viewerViewModel.annotateMode !== 'drag',
            annotateCtx: this.view3Ctx,
            drawCtx: this.view3DrawCtx,
            onDrawTouch: (event: TouchEvent) => this.handleDrawTouch(this.view3DrawCtx, this.view3Ctx, this.viewerViewModel.displayedPageIndices[2] ?? 0, event),
            onDrawMouse: (event: MouseEvent) => this.handleDrawMouse(this.view3DrawCtx, this.view3Ctx, this.viewerViewModel.displayedPageIndices[2] ?? 0, event)
          })
        }
        .alignRules(TopLeft)
        .offset(this.viewerViewModel.viewPan)
        .size(toSizePx(this.viewerViewModel.viewSize))
        .scale({
          x: this.viewerViewModel.viewScale,
          y: this.viewerViewModel.viewScale,
          centerX: 0,
          centerY: 0
        })

        Flex()
          .size({ width: '100%', height: '100%' })
          .onAreaChange((_, newVal) => {
            this.viewerViewModel.setViewportSize(fromArea(newVal, this.getUIContext()));
            this.resetViewToFit();
          })
          .hitTestBehavior(HitTestMode.Transparent)
          .onTouch(event => this.handleViewAction(event))
          .onMouse(event => this.handleMouseEvent(event))
          .onAxisEvent(event => this.handleMouseAxisEvent(event))

        Button(PageFlipButtonOption)
          .size(PageFlipButtonSize)
          .onClick(() => this.navigatePrevPage())
          .alignRules(TopLeft)
          .backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.Transparent)
          .visibility(toVisibility(this.viewerViewModel.pageFlipMode == 'side'))

        Button(PageFlipButtonOption)
          .size(PageFlipButtonSize)
          .onClick(() => this.navigateNextPage())
          .alignRules(TopRight)
          .backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.Transparent)
          .visibility(toVisibility(this.viewerViewModel.pageFlipMode == 'side'))

        Image('')
          .size(PageFlipButtonSize)
          .alignRules(TopLeft)
          .visibility(toVisibility(this.viewerViewModel.pageFlipMode == 'side'))
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
          .visibility(toVisibility(this.viewerViewModel.pageFlipMode == 'side'))
          .hitTestBehavior(HitTestMode.None)
          .linearGradient({
            direction: GradientDirection.Right,
            colors: [
              [Color.Transparent, 0],
              ['rgba(0, 0, 0, 0.2)', 1]
            ],
            repeating: false
          })
        PDFMetronomePanel({
          controller: this.metronomeController
        })
        .alignRules(TopLeft)
        .margin(ContainerPadding)
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)

        Stack() {
          // Slider - positioned at right, vertically centered, independent of bottom bar
          Column(ContainerCfg) {
            Blank().layoutWeight(1)
            MakeSlider(
              {
                value: this.viewerViewModel.currentPageIndex,
                min: 0,
                max: this.viewerViewModel.totalPageCount - 1,
                onChangeCallback: newValue => this.gotoPage(newValue)
              }
            ).visibility(toVisibility(this.viewerViewModel.showControls && this.viewerViewModel.showSlider))
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
              PDFViewerActionMenu({
                menuExpanded: this.viewerViewModel.menuExpanded,
                isExclusiveFullScreen: this.isExclusiveFullScreen,
                pageDisplayModeText: this.viewerViewModel.getPageDisplayModeText(),
                pageFlipModeText: this.viewerViewModel.getPageFlipModeText(),
                annotateModeText: this.viewerViewModel.getAnnotateModeText(),
                shareButtonId: ShareButtonId,
                displayModeMenu: this.viewerViewModel.buildPageDisplayModeMenu(() => this.gotoPage(this.viewerViewModel.currentPageIndex)),
                flipModeMenu: this.viewerViewModel.buildPageFlipModeMenu(),
                jumpMenu: this.viewerViewModel.buildJumpMenu(() => this.resetViewToFit(), (pageIndex: number) => this.gotoPage(pageIndex)),
                annotateModeMenu: this.annotationController.buildAnnotateModeMenu(),
                onTutorial: () => {
                  this.viewerViewModel.setMenuExpanded(false);
                  this.tutorialDialogController.open();
                },
                onSettings: () => {
                  this.viewerViewModel.setMenuExpanded(false);
                  this.rebuildSettingsDialogController();
                  this.settingsDialogController.open();
                },
                onToggleFullscreen: () => {
                  this.isExclusiveFullScreen = !this.isExclusiveFullScreen;
                  if (this.isExclusiveFullScreen) {
                    this.mainWindow.maximize().catch();
                  } else {
                    this.mainWindow.recover().catch();
                  }
                },
                onShare: () => {
                  this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                    this.viewerViewModel.setMenuExpanded(false);
                  });
                  this.executeShare();
                },
                onToggleMetronome: () => {
                  this.metronomeController.toggleWindow();
                  this.viewerViewModel.setMenuExpanded(false);
                },
                onToggleMenu: () => {
                  this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                    this.viewerViewModel.setMenuExpanded(!this.viewerViewModel.menuExpanded);
                  });
                }
              })

              Blank()

              PDFViewerBottomBar({
                showControls: this.viewerViewModel.showControls,
                undoHistoryCount: this.annotationController.undoHistoryCount,
                redoHistoryCount: this.annotationController.redoHistoryCount,
                hasUnsavedStrokes: this.annotationController.hasUnsavedStrokes,
                pageFlipMode: this.viewerViewModel.pageFlipMode,
                currentPageIndex: this.viewerViewModel.currentPageIndex,
                totalPageCount: this.viewerViewModel.totalPageCount,
                onUndo: () => this.annotationController.executeUndo(),
                onRedo: () => this.annotationController.executeRedo(),
                onSave: () => this.annotationController.executeSave(),
                onPrevPage: () => this.navigatePrevPage(),
                onNextPage: () => this.navigateNextPage()
              })

            }.width('100%').alignItems(VerticalAlign.Bottom)
          }
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
        }
        .alignRules(FullRect)
        .margin(ContainerPadding)
        .hitTestBehavior(HitTestMode.Transparent)
        .opacity(this.viewerViewModel.controlsTransparency)
      }

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
    .width('100%')
    .height('100%')
  }
}