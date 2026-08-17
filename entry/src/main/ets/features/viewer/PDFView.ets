import { ContainerCfg, ContainerPadding, FullRect, MakeSlider, TopLeft, TopRight, toResultCode, toVisibility } from '../../common/ui/UIComponents';
import { hasUnsavedDocumentChanges, promptUnsavedChangesAction, UnsavedChangesChoice } from '../../common/ui/UnsavedChangesPrompt';
import { reloadPdfDocument } from '../../common/document/PdfDocumentLoader';
import {
  EVENT_APP_TERMINATE_REQUESTED,
  EVENT_DOCUMENT_OPEN_REQUESTED,
  isValidPendingDocumentOpenParams,
  setExitViewerOnBack,
  setPdfViewerActive,
  shouldExitViewerOnBack,
  syncPdfViewerHasUnsavedChanges,
  takePendingDocumentOpenParams
} from '../../navigation/PendingDocumentOpen';
import {
  getSessionPreferences,
  getSessionWindow,
  takeInitialPdfViewArgs
} from '../../common/session/AppSession';
import { ComponentContent, LengthMetricsUnit, OverlayManager, window } from '@kit.ArkUI';
import { pdfService } from '@kit.PDFKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fromArea, mul, pxToVp, toSizePx, Vec2, Vector2 } from '../../common/ui/Numbers';
import { readWindowSafeInsetsPx } from '../../common/ui/WindowSafeInsets';
import { preferences, uniformTypeDescriptor as utd } from '@kit.ArkData';
import { KeyCode } from '@kit.InputKit';
import { fileUri } from '@kit.CoreFileKit';
import { harmonyShare, systemShare } from '@kit.ShareKit';
import { AbilityConstant, common } from '@kit.AbilityKit';
import {
  clearContinuationReadingState,
  logContinuationLine,
  parseInitialPageIndexFromRouter,
  updateContinuationReadingState
} from '../continuation/PdfContinuation';
import {
  isContinuationPendingRouterArgs,
  parseExtraLocalPathsFromRouter
} from '../continuation/PdfContinuationRestore';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { stylusInteraction } from '@kit.Penkit';
import { taskpool } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { TutorialDialogBuilder } from '../../common/ui/TutorialDialog';
import { PageCache, selectDisplayPixelMap } from '../../common/page/PageRasterCache';
import { PdfRenderSession } from '../../common/page/PdfRenderSession';
import { PageStore } from '../../common/page/PageStore';
import { InputAction } from '../../common/ui/Input';
import { SettingsDialogBuilder } from '../../common/ui/SettingsDialog';
import { PDFAnnotationController } from '../annotation/PDFAnnotationController';
import {
  AnnotatePreparePhaseOptions,
  PageStoreStrokeStore,
  PDFAnnotationControllerDependencies,
  PDFAnnotationDocumentIO,
  PDFAnnotationHostBridge,
  PDFAnnotationPageNavigator,
  PDFAnnotationPrepareUiBridge
} from '../annotation/PDFAnnotationDependencies';
import { PDFPageTurnController } from './PDFPageTurnController';
import { PDFLinkController } from './PDFLinkController';
import { PDFDocumentSession, PDFDocumentSessionPaths } from './PDFDocumentSession';
import { PDFMetronomeController } from '../music/PDFMetronomeController';
import { PDFTunerController } from '../music/PDFTunerController';
import { PDFLinkDisplayHitArea, PDFPageSlot } from './PDFPageSlot';
import {
  FloatingMetronomeDefaultScale,
  getFloatingMetronomeTotalWidth,
  PDFMetronomePanelContent
} from '../music/PDFMetronomePanel';
import {
  FloatingTunerDefaultScale,
  getFloatingTunerTotalWidth,
  PDFTunerPanelContent
} from '../music/PDFTunerPanel';
import {
  createFloatingPanelOffset,
  FloatingPanelChrome,
  FloatingPanelClampParams,
  FloatingPanelHostGestures,
  FloatingPanelMarginVp,
  FloatingPanelOffset
} from '../panels/FloatingPanelChrome';
import {
  AnnotationPaletteOverlayParams,
  BookmarkOverlayParams,
  BuildAnnotationPaletteOverlay,
  BuildBookmarkOverlay,
  BuildMetronomeOverlay,
  BuildTunerOverlay,
  MetronomeOverlayParams,
  TunerOverlayParams
} from '../panels/FloatingPanelOverlays';
import { PDFViewerActionMenu } from './PDFViewerActionMenu';
import { PDFViewerBottomBar } from './PDFViewerBottomBar';
import { PDFAnnotateMode, PDFLinkVisualMode, PDFPageFlipMode, PDFViewerViewModel, ViewerMinRenderScale } from './PDFViewerViewModel';
import { AnnotateLongPressIndicator } from './AnnotateLongPressIndicator';
import {
  AnnotationPaletteContentWidth,
  getAnnotationPaletteContentHeight
} from '../annotation/PDFAnnotationPalette';
import { PDFBookmarkController } from '../panels/PDFBookmarkController';
import {
  BookmarkPanelContentHeight,
  BookmarkPanelContentWidth,
  BookmarkTitleDialogBuilder,
  getFloatingBookmarkTotalWidth,
  PDFBookmarkPanelContent
} from '../panels/PDFBookmarkPanel';
import { createPageViewSlots, PAGE_VIEW_SLOT_COUNT, PageViewSlot } from './PageViewSlot';
import {
  ModalBodyTextColor,
  ModalButtonPrimaryColor,
  ModalButtonSecondaryColor,
  ModalCardBackgroundColor,
  ModalCardBorderColor,
  ModalCardShadow,
  ModalDimOverlayColor,
  ModalErrorTextColor,
  ModalInputBackgroundColor,
  ModalInputCaretColor,
  ModalInputPlaceholderColor,
  ModalMutedTextColor,
  ModalTitleTextColor,
  ViewerPageBackdropColor,
  ViewerPageLoadingIndicatorColor,
  ViewerPageLoadingTextColor
} from './PDFPanelVisualConstants';
import { AnnotationColor } from '../annotation/PDFAnnotationColors';

// 双指手势结束后忽略绘制/擦除触摸的延迟（毫秒）
const DUAL_FINGER_END_PROTECTION_DELAY: number = 300;
const LONG_PRESS_DELAY_MS: number = 350;
const LONG_PRESS_DURATION_MS: number = 500;
const LONG_PRESS_MOVE_THRESHOLD: number = 10;
const LONG_PRESS_TICK_INTERVAL: number = 16;
// 屏侧翻页：平移超过该阈值（像素，与触摸坐标一致）则视为拖动手势，忽略随后触发的翻页按钮点击
const PAGE_FLIP_SUPPRESS_MOVE_PX: number = 12;
const PageFlipButtonOption: ButtonOptions = { type: ButtonType.Normal }
const PageFlipButtonSize: SizeOptions = { width: '30%', height: '100%' }
const CanvasOverSampling: number = 3;
const ShareButtonId: string = 'shareButton';
const UnifiedDockTabBarHeightVp: number = 56;
const FloatingMetronomeContentWidthVp: number = 400;
const FloatingTunerContentWidthVp: number = 392;
const DefaultTunerOffsetX: number = 24;
const DefaultTunerOffsetY: number = 112;
const DefaultPaletteScale: number = 1.0;
const PaletteMinScale: number = 0.5;
const PaletteMaxScale: number = 1.5;
const DefaultBookmarkScale: number = 1.0;
const BookmarkMinScale: number = 0.7;
const BookmarkMaxScale: number = 1.3;
const DefaultBookmarkOffsetX: number = 24;
const DefaultBookmarkOffsetY: number = 96;
const MetronomeMinScale: number = 0.35;
const MetronomeMaxScale: number = 1.5;
const TunerMinScale: number = 0.4;
const TunerMaxScale: number = 1.6;

type OverlayPanelKey = 'metronome' | 'tuner' | 'bookmark';

@Entry
@ComponentV2
struct PDFView {
  systemPath = '';
  sandBoxPath = '';
  saveTempPath = '';
  fileName = '';
  mainWindow: window.Window = getSessionWindow() as window.Window;
  document = new pdfService.PdfDocument();
  pageDataSource: PageStore = new PageStore();
  preferences: preferences.Preferences = getSessionPreferences() as preferences.Preferences;
  @Local viewerViewModel: PDFViewerViewModel = new PDFViewerViewModel();
  currentRenderScale: number = ViewerMinRenderScale;
  /** 拖拽/捏合/滑动中：主槽强制 layout 代理，避免 HQ 大纹理每帧变换 */
  private interactiveMotionDemoted: boolean = false;
  settings: RenderingContextSettings = new RenderingContextSettings(true);
  /** 主文档条三槽（@ObservedV2 + @Trace，变异槽字段即可刷新 UI） */
  @Local mainSlots: PageViewSlot[] = createPageViewSlots(this.settings);
  /** 导出/写入 PDF 进行中（右上角指示，不遮挡整页） */
  @Local isDocumentSaving: boolean = false;
  @Local documentSaveMessage: string = '';
  /** 进入批注模式：扫描/导入进行中（右上角指示；由 AnnotationController prepareUi 回调更新） */
  @Local isAnnotateModePreparing: boolean = false;
  /** 仅主线程导入/写入阶段为 true，扫描阶段用户仍可平移/绘制 */
  @Local isAnnotatePrepareBlockingEdits: boolean = false;
  @Local annotatePrepareMessage: string = '';
  transparencyTimeoutId: number | undefined = undefined;
  windowStatusCallback: ((statusType: window.WindowStatusType) => void) | undefined = undefined;
  freeWindowModeCallback: ((isInFreeWindowMode: boolean) => void) | undefined = undefined;
  lastTouchPoint: Vector2 | undefined = undefined;
  /** 当前单指拖动手势起点，用于判断屏侧翻页是否应被平移取消 */
  panSessionStartPoint: Vector2 | undefined = undefined;
  /** 在侧栏透明按钮上抬起时，若发生过平移/捏合/滚轮缩放则置为 true，以忽略误触的翻页 */
  suppressSidePageFlipFromGesture: boolean = false;
  private sliderJumpStartPageIndex: number | undefined = undefined;
  lastPinchDistance: number | undefined = undefined;
  lastPinchCenter: Vector2 | undefined = undefined;
  lastDualFingerEndTime: number = 0;
  isDualFingerActive: boolean = false;
  lastMousePoint: Vector2 | undefined = undefined;
  /** 拖动模式下鼠标左/右键按下时的位置，用于屏侧翻页与平移的区分 */
  mousePanSessionStart: Vector2 | undefined = undefined;
  activeMouseButton: number = 0; // 当前是否有双指手势激活
  placeholderPixelMap: PixelMap | undefined = undefined;
  transparentPlaceholderPixelMap: PixelMap | undefined = undefined;
  @Local documentSession: PDFDocumentSession = new PDFDocumentSession({
    document: this.document,
    pageDataSource: this.pageDataSource,
    viewerViewModel: this.viewerViewModel,
    getUIContext: () => this.getUIContext(),
    getPaths: (): PDFDocumentSessionPaths => {
      const paths: PDFDocumentSessionPaths = {
        systemPath: this.systemPath,
        sandBoxPath: this.sandBoxPath,
        saveTempPath: this.saveTempPath,
        fileName: this.fileName
      };
      return paths;
    },
    setPaths: (paths: PDFDocumentSessionPaths) => {
      this.systemPath = paths.systemPath;
      this.sandBoxPath = paths.sandBoxPath;
      this.saveTempPath = paths.saveTempPath;
      this.fileName = paths.fileName;
    },
    getDocumentLoadVersion: () => this.documentLoadVersion,
    bumpDocumentLoadVersion: () => {
      this.documentLoadVersion++;
      return this.documentLoadVersion;
    },
    cancelAnnotatePrepareSession: () => this.cancelAnnotatePrepareSession(),
    createPlaceholderPixelMap: () => this.createPlaceholderPixelMap(),
    clearLinkJumpHistory: () => this.linkController.clearLinkJumpHistory(),
    gotoPage: (targetIndex: number, deferSlideVisualReset: boolean, recordJumpHistory: boolean) =>
      this.gotoPage(targetIndex, deferSlideVisualReset, recordJumpHistory),
    refreshBookmarks: () => this.bookmarkController.refresh(),
    triggerPageFlipShadeIntro: () => this.triggerPageFlipShadeIntro(),
    startTransparencyTimeout: () => this.startTransparencyTimeout(),
    requestLeaveViewer: () => this.requestLeaveViewer()
  });
  @Local pageTurnController: PDFPageTurnController = new PDFPageTurnController({
    viewerViewModel: this.viewerViewModel,
    getUIContext: () => this.getUIContext(),
    getPageCache: (targetIndex: number, renderScale: number, loadVersion: number) =>
      this.getPageCache(targetIndex, renderScale, loadVersion),
    peekPageCache: (targetIndex: number, renderScale: number) =>
      this.pageDataSource.peekPageCache(targetIndex, renderScale),
    getCurrentRenderScale: () => this.currentRenderScale,
    getPageLoadVersion: () => this.pageLoadVersion,
    bumpPageLoadVersion: () => {
      this.pageLoadVersion++;
    },
    getPlaceholderPixelMap: () => this.placeholderPixelMap,
    getPageDisplaySize: (pageIndex: number) => this.getPageDisplaySize(pageIndex),
    setSuppressSidePageFlipFromGesture: (value: boolean) => {
      this.suppressSidePageFlipFromGesture = value;
    },
    ensureMainRowEmptySlotsMatchDisplayed: () => this.ensureMainRowEmptySlotsMatchDisplayed(),
    resetViewToFit: () => this.resetViewToFit(),
    redrawStrokes: () => this.redrawStrokes(),
    gotoPage: (targetIndex: number, deferSlideVisualReset: boolean, recordJumpHistory: boolean) =>
      this.gotoPage(targetIndex, deferSlideVisualReset, recordJumpHistory),
    getMainSlotAt: (index: number) => this.mainSlotAt(index)
  }, this.settings);
  @Local linkController: PDFLinkController = new PDFLinkController({
    viewerViewModel: this.viewerViewModel,
    pageDataSource: this.pageDataSource,
    pageTurnController: this.pageTurnController,
    getUIContext: () => this.getUIContext(),
    getMainSlots: () => this.mainSlots,
    getMainSlotAt: (index: number) => this.mainSlotAt(index),
    isDocumentLoading: () => this.documentSession.isDocumentLoading,
    isDocumentReadOnly: () => this.isDocumentReadOnly(),
    isAnnotateModePreparing: () => this.isAnnotateModePreparing,
    isPanelGestureActive: () => this.isPanelGestureActive,
    isDualFingerActive: () => this.isDualFingerActive,
    cancelLongPress: () => this.cancelLongPress(),
    setSuppressSidePageFlipFromGesture: (value: boolean) => {
      this.suppressSidePageFlipFromGesture = value;
    },
    gotoPage: (targetIndex: number, deferSlideVisualReset?: boolean, recordJumpHistory?: boolean) =>
      this.gotoPage(targetIndex, deferSlideVisualReset ?? false, recordJumpHistory ?? true)
  });
  @Local annotationController: PDFAnnotationController = new PDFAnnotationController(
    new PDFAnnotationControllerDependencies(
      new PageStoreStrokeStore(this.pageDataSource),
      new PDFAnnotationDocumentIO({
        getDocument: () => this.document,
        getSystemPath: () => this.systemPath,
        getSandBoxPath: () => this.sandBoxPath,
        getOpenPassword: () => this.documentSession.sessionPdfPassword,
        getSaveTempPath: () => this.saveTempPath,
        getFileName: () => this.fileName,
        getUIContext: () => this.getUIContext(),
        getPreferences: () => this.preferences
      }),
      new PDFAnnotationPageNavigator({
        gotoPage: (pageIndex: number) => {
          this.gotoPage(pageIndex);
        },
        getDisplayedPageIndices: () => this.viewerViewModel.displayedPageIndices,
        getTotalPageCount: () => this.viewerViewModel.totalPageCount,
        getAnnotateMode: () => this.viewerViewModel.annotateMode,
        setAnnotateMode: (mode: PDFAnnotateMode) => {
          this.viewerViewModel.setAnnotateMode(mode);
        }
      }),
      new PDFAnnotationPrepareUiBridge({
        onPreparePhase: (message: string, options?: AnnotatePreparePhaseOptions) => {
          this.isAnnotateModePreparing = true;
          this.isAnnotatePrepareBlockingEdits = options?.blocksEditing === true;
          this.annotatePrepareMessage = message;
        },
        clearPrepareStatus: () => {
          this.isAnnotateModePreparing = false;
          this.isAnnotatePrepareBlockingEdits = false;
          this.annotatePrepareMessage = '';
        }
      }),
      new PDFAnnotationHostBridge({
        onRedrawRequested: () => {
          this.redrawStrokes();
          this.syncPanelOverlays();
        },
        onRefreshDisplayedPages: () => this.refreshDisplayedPages(),
        onSavePhase: (message: string) => {
          if (!this.isDocumentSaving) {
            this.enterDocumentReadOnlyForSave();
          }
          this.isDocumentSaving = true;
          this.documentSaveMessage = message;
        }
      })
    ),
    CanvasOverSampling
  );
  @Local metronomeController: PDFMetronomeController = new PDFMetronomeController({
    getUIContext: () => this.getUIContext(),
    getHostContext: () => this.getUIContext().getHostContext() as common.UIAbilityContext,
    onVisualStateChanged: () => this.syncPanelOverlays()
  });
  @Local bookmarkController: PDFBookmarkController = new PDFBookmarkController({
    getDocument: () => this.document,
    onTreeChanged: () => this.syncPanelOverlays()
  });
  @Local tunerController: PDFTunerController = new PDFTunerController();
  @Local showTunerPanel: boolean = false;
  @Local useDockedMetronomePanel: boolean = false;
  private metronomeChrome: FloatingPanelChrome = new FloatingPanelChrome({
    initialOffsetX: 0,
    initialOffsetY: 0,
    initialScale: FloatingMetronomeDefaultScale,
    minScale: MetronomeMinScale,
    maxScale: MetronomeMaxScale
  });
  @Local metronomeViewportWidthVp: number = 0;
  @Local metronomeViewportHeightVp: number = 0;
  @Local metronomePanelHeightVp: number = 0;
  @Local useDockedTunerPanel: boolean = false;
  @Local useDockedBookmarkPanel: boolean = false;
  private tunerChrome: FloatingPanelChrome = new FloatingPanelChrome({
    initialOffsetX: DefaultTunerOffsetX,
    initialOffsetY: DefaultTunerOffsetY,
    initialScale: FloatingTunerDefaultScale,
    minScale: TunerMinScale,
    maxScale: TunerMaxScale
  });
  @Local tunerViewportWidthVp: number = 0;
  @Local tunerViewportHeightVp: number = 0;
  @Local tunerPanelHeightVp: number = 0;
  @Local dockedPanelHeightVp: number = 0;
  @Local activePanel: OverlayPanelKey = 'metronome';
  @Local isPanelGestureActive: boolean = false;
  @Local isExclusiveFullScreen: boolean = false;
  @Local isInFreeWindowMode: boolean = false;
  @Local pageFlipShadeOpacity: number = 0;
  private paletteChrome: FloatingPanelChrome = new FloatingPanelChrome({
    initialOffsetX: 0,
    initialOffsetY: 0,
    initialScale: DefaultPaletteScale,
    minScale: PaletteMinScale,
    maxScale: PaletteMaxScale
  });
  private bookmarkChrome: FloatingPanelChrome = new FloatingPanelChrome({
    initialOffsetX: DefaultBookmarkOffsetX,
    initialOffsetY: DefaultBookmarkOffsetY,
    initialScale: DefaultBookmarkScale,
    minScale: BookmarkMinScale,
    maxScale: BookmarkMaxScale
  });
  @Local bookmarkPanelHeightVp: number = 0;
  @Local bookmarkViewportWidthVp: number = 0;
  @Local bookmarkViewportHeightVp: number = 0;
  @Local longPressProgress: number = 0;
  @Local longPressPosX: number = 0;
  @Local longPressPosY: number = 0;
  @Local longPressVisible: boolean = false;
  private longPressDelayId: number | undefined = undefined;
  private longPressAnimId: number | undefined = undefined;
  private bookmarkRenameDialogController: CustomDialogController | undefined = undefined;
  private longPressStartTime: number = 0;
  private longPressTouchDown: boolean = false;
  hotkeys: InputAction[] = [];
  prefetchDebounceId: number | undefined = undefined;
  windowSizeChangeCallback: ((windowSize: window.Size) => void) | undefined = undefined;
  /** 系统栏 / 导航指示条 / 标题按钮避让（px），主要约束浮动面板，常驻控件只用 ContainerPadding */
  @Local avoidAreaTopPx: number = 0;
  @Local avoidAreaBottomPx: number = 0;
  @Local avoidAreaLeftPx: number = 0;
  @Local avoidAreaRightPx: number = 0;
  @Local titleButtonWidthVp: number = 0;
  @Local titleButtonHeightVp: number = 0;
  avoidAreaChangeCallback: ((data: window.AvoidAreaOptions) => void) | undefined = undefined;
  titleButtonRectChangeCallback: ((rect: window.TitleButtonRect) => void) | undefined = undefined;
  private overlayManager: OverlayManager | undefined = undefined;
  private metronomeOverlayContent: ComponentContent<MetronomeOverlayParams> | undefined = undefined;
  private tunerOverlayContent: ComponentContent<TunerOverlayParams> | undefined = undefined;
  private paletteOverlayContent: ComponentContent<AnnotationPaletteOverlayParams> | undefined = undefined;
  private bookmarkOverlayContent: ComponentContent<BookmarkOverlayParams> | undefined = undefined;
  private lastWindowWidthPx: number = 0;
  // 每次 gotoPage 调用时递增；用于忽略在页面切换后才完成的过期异步加载回调，
  // 避免快速翻页后显示内容与当前页码不符。
  private pageLoadVersion: number = 0;
  /**
   * 当前正在载入主槽的页索引。高分辨率异步回调按此列表写入主槽。
   */
  private mainSlotPagesBeingLoaded: number[] = [];
  private documentLoadVersion: number = 0;
  /** 隔空传送 / 碰一碰分享监听是否已注册 */
  private harmonyShareListening: boolean = false;
  /** PC/2in1 碰一碰发送需带 windowId */
  private harmonyShareKnockUsesWindowId: boolean = false;
  private harmonyShareWindowId: number = -1;
  /** PC/2in1 沙箱接收碰一碰文件 */
  private harmonyShareReceiveRegistered: boolean = false;
  /** 手写笔笔身双击监听是否已注册 */
  private stylusDoubleTapListening: boolean = false;
  private readonly stylusDoubleTapCallback = (_event: stylusInteraction.DoubleTapEvent): void => {
    this.handleStylusDoubleTap();
  };
  tutorialDialogController: CustomDialogController = new CustomDialogController({
    builder: TutorialDialogBuilder(),
    width: '60%',
    height: '90%'
  });
  settingsDialogController: CustomDialogController = new CustomDialogController({
    builder: SettingsDialogBuilder({
      showSlider: this.viewerViewModel.showSlider,
      horizontalSlideSensitivity: this.viewerViewModel.horizontalSlideSensitivity,
      linkVisualMode: this.viewerViewModel.linkVisualMode,
      onSliderToggled: (show: boolean) => {
        this.viewerViewModel.setShowSlider(show);
      },
      onHorizontalSlideSensitivityChange: (level: number) => {
        this.viewerViewModel.setHorizontalSlideSensitivity(level);
      },
      onLinkVisualModeChange: (mode: PDFLinkVisualMode) => {
        this.viewerViewModel.setLinkVisualMode(mode);
        this.linkController.applyPdfLinkVisualMode(true);
      }
    }),
    width: '85%',
  });

  private isDocumentReadOnly(): boolean {
    return this.isDocumentSaving || this.isAnnotatePrepareBlockingEdits;
  }

  private cancelAnnotatePrepareSession(): void {
    this.annotationController.cancelAnnotatePrepareSession();
  }

  /** 保存进行中：结束批注交互并关闭批注面板，避免与写入冲突。 */
  private enterDocumentReadOnlyForSave(): void {
    this.cancelLongPress();
    const resetResult = this.annotationController.resetTransientState();
    if (resetResult.clearedDraw) {
      this.resetMainDrawCanvases();
    }
    if (resetResult.clearedErase) {
      this.redrawStrokes();
    }
    this.viewerViewModel.closeAnnotatePalette();
    this.syncPanelOverlays();
  }

  /** 与「更多」→「保存文档」相同：选择保存位置并写入 PDF（含书签与批注）。 */
  private executeSaveDocument(): void {
    if (this.isDocumentSaving || this.isAnnotateModePreparing) {
      return;
    }
    void this.annotationController.executeSave()
      .then((saved: boolean) => {
        if (saved) {
          this.bookmarkController.markDocumentSaved();
        }
        this.syncPanelOverlays();
      })
      .catch((error: Error) => hilog.error(0, 'PDFView', `保存文档出错: ${error.message}`))
      .finally(() => {
        this.isDocumentSaving = false;
        this.documentSaveMessage = '';
      });
  }

  private getTopRightStatusMessage(): string {
    if (this.isDocumentSaving) {
      return this.documentSaveMessage.length > 0 ? this.documentSaveMessage : '正在保存…';
    }
    if (this.isAnnotateModePreparing) {
      return this.annotatePrepareMessage.length > 0 ? this.annotatePrepareMessage : '正在准备批注模式…';
    }
    return '';
  }

  @Builder
  TopRightStatusIndicatorOverlay() {
    if (this.isDocumentSaving || this.isAnnotateModePreparing) {
      Row({ space: 8 }) {
        LoadingProgress()
          .width(22)
          .height(22)
          .color(ViewerPageLoadingIndicatorColor)
        Text(this.getTopRightStatusMessage())
          .fontSize(13)
          .fontColor(ViewerPageLoadingTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .constraintSize({ maxWidth: '55%' })
      .padding({
        left: 12,
        right: 12,
        top: 8,
        bottom: 8
      })
      .backgroundColor(ModalCardBackgroundColor)
      .borderRadius(20)
      .border({ width: 1, color: ModalCardBorderColor })
      .shadow(ModalCardShadow)
      .alignRules(TopRight)
      .margin({
        top: this.getSafeTopVp() + this.titleButtonHeightVp + 12,
        right: this.getSafeRightVp() + this.titleButtonWidthVp + 16
      })
      .hitTestBehavior(HitTestMode.None)
      .zIndex(200)
    }
  }

  private hasUnsavedDocumentChanges(): boolean {
    return hasUnsavedDocumentChanges(
      this.annotationController.hasUnsavedStrokes,
      this.bookmarkController.isDirty
    );
  }

  private syncPdfViewerUnsavedState(): void {
    syncPdfViewerHasUnsavedChanges(
      this.annotationController.hasUnsavedStrokes,
      this.bookmarkController.isDirty
    );
  }

  private async saveDocumentForGuard(): Promise<boolean> {
    if (this.isDocumentSaving || this.isAnnotateModePreparing) {
      return false;
    }
    try {
      const saved: boolean = await this.annotationController.executeSave();
      if (saved) {
        this.bookmarkController.markDocumentSaved();
        this.syncPanelOverlays();
      }
      return saved;
    } catch (error) {
      hilog.error(0, 'PDFView', `保存文档出错: ${(error as Error).message}`);
      return false;
    } finally {
      this.isDocumentSaving = false;
      this.documentSaveMessage = '';
      this.syncPdfViewerUnsavedState();
    }
  }

  private async discardUnsavedChanges(): Promise<void> {
    this.annotationController.discardUnsavedStrokes();
    this.resetMainDrawCanvases();
    this.redrawStrokes();

    if (this.bookmarkController.isDirty) {
      const loadVersion = ++this.documentLoadVersion;
      const result = reloadPdfDocument(this.document, this.sandBoxPath, this.documentSession.sessionPdfPassword);
      if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
        hilog.error(0, 'PDFView', `丢弃更改时重载 PDF 失败: ${toResultCode(result)}`);
        return;
      }
      if (this.documentLoadVersion !== loadVersion) {
        return;
      }
      const totalPages = this.pageDataSource.totalCount();
      for (let i = 0; i < totalPages; i++) {
        this.pageDataSource.getData(i).evictAllViewerCaches();
        this.pageDataSource.getData(i).invalidateCaches();
      }
      this.pageDataSource.resetAllPdfPageHandles();
      this.pageDataSource.clearImportedPdfPolylineTracking();
      this.annotationController.resetImportedPolylinePrepareState();
      this.pageDataSource.setPagePath(this.sandBoxPath);
      try {
        await PdfRenderSession.getInstance().replace(
          this.sandBoxPath,
          this.documentSession.sessionPdfPassword
        );
      } catch (error) {
        const message = error instanceof Error ? error.message : 'replace failed';
        hilog.error(0, 'PDFView', '丢弃更改后 PdfRenderSession.replace 失败: ' + message);
      }
      this.bookmarkController.refresh();
      this.bookmarkController.markDocumentSaved();
      await this.refreshDisplayedPagesAfterDiscard();
    }

    this.syncPdfViewerUnsavedState();
    this.syncPanelOverlays();
  }

  private async refreshDisplayedPagesAfterDiscard(): Promise<void> {
    const displayed = this.viewerViewModel.displayedPageIndices;
    for (const pageIndex of displayed) {
      this.pageDataSource.invalidateCaches(pageIndex);
    }
    for (const pageIndex of displayed) {
      void this.pageDataSource.ensureCached(pageIndex, this.currentRenderScale, taskpool.Priority.HIGH);
    }
    await this.refreshDisplayedPages();
  }

  private async runWithUnsavedGuard(proceed: () => void | Promise<void>): Promise<void> {
    if (this.isDocumentSaving || this.isAnnotateModePreparing) {
      return;
    }
    this.syncPdfViewerUnsavedState();
    if (!this.hasUnsavedDocumentChanges()) {
      await proceed();
      return;
    }

    const choice = await promptUnsavedChangesAction(this.getUIContext());
    if (choice === UnsavedChangesChoice.Cancel) {
      return;
    }
    if (choice === UnsavedChangesChoice.Discard) {
      await this.discardUnsavedChanges();
      if (this.hasUnsavedDocumentChanges()) {
        return;
      }
      await proceed();
      return;
    }

    const saved = await this.saveDocumentForGuard();
    if (saved) {
      await proceed();
    }
  }

  private async replaceUrlToOpenDocument(params: Record<string, string>): Promise<void> {
    try {
      await this.getUIContext().getRouter().replaceUrl({
        url: 'features/viewer/PDFView',
        params: params
      });
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0, 'PDFView', `replaceUrl 打开文档失败: code=${err.code}, ${err.message}`);
    }
  }

  private requestLeaveViewer(): void {
    if (shouldExitViewerOnBack()) {
      hilog.info(0, 'PDFView', 'requestLeaveViewer: Want 返回 -> moveAbilityToBackground');
      void this.runWithUnsavedGuard(() => {
        this.returnToCallerKeepingAlive();
      });
      return;
    }
    hilog.info(0, 'PDFView', 'requestLeaveViewer: 回应用首页');
    void this.runWithUnsavedGuard(() => {
      this.backToMainMenu();
    });
  }

  /** 左下角首页按钮：始终回应用首页，不受 Want 返回态影响。 */
  private requestGoHome(): void {
    void this.runWithUnsavedGuard(() => {
      this.backToMainMenu();
    });
  }

  private requestOpenDocument(params: Record<string, string>): void {
    void this.runWithUnsavedGuard(async () => {
      await this.replaceUrlToOpenDocument(params);
    });
  }

  private onDocumentOpenRequested = (): void => {
    const params = takePendingDocumentOpenParams();
    if (params === undefined || !isValidPendingDocumentOpenParams(params)) {
      return;
    }
    // 系统 Want 再次打开文档：返回应回到调用方（Ability 保活进后台）。
    setExitViewerOnBack(true);
    this.requestOpenDocument(params);
  };

  private onAppTerminateRequested = (): void => {
    void this.runWithUnsavedGuard(() => {
      this.terminateViewerAbility();
    });
  };

  private prepareLeaveViewerUi(): void {
    this.documentSession.disableContinuationForMigration();
    clearContinuationReadingState();
    // 关闭节拍器、调音器、批注画板三个浮层并把关闭状态推到 OverlayManager，
    // 防止离开 PDFView 后这些浮层在窗口级 OverlayManager 中残留显示，
    // 也保证下一次再进入 PDFView 时浮层处于初始（隐藏）状态。
    this.cancelAnnotatePrepareSession();
    this.metronomeController.closeWindow();
    this.setTunerPanelVisible(false);
    this.viewerViewModel.closeAnnotatePalette();
    this.viewerViewModel.closeBookmarkPanel();
    this.syncPanelOverlays();
  }

  /**
   * 系统 Want 打开后的返回：优先移到后台回到调用方，不销毁 Ability。
   * 设备不支持 moveAbilityToBackground（如部分 2in1）时回退应用首页。
   */
  private returnToCallerKeepingAlive(): void {
    this.prepareLeaveViewerUi();
    // 一次性：本次 Want 返回用完即解除，避免后台再从桌面进入时系统返回仍进后台。
    setExitViewerOnBack(false);
    const abilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    abilityContext.moveAbilityToBackground().then(() => {
      hilog.info(0, 'PDFView', 'moveAbilityToBackground 成功，已回到调用方且保持进程');
    }).catch((err: BusinessError) => {
      hilog.warn(0, 'PDFView',
        `moveAbilityToBackground 失败 code=${err.code}, ${err.message}，回退应用首页`);
      this.backToMainMenu();
    });
  }

  private terminateViewerAbility(): void {
    this.prepareLeaveViewerUi();
    setExitViewerOnBack(false);
    const abilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    abilityContext.terminateSelf().catch((err: BusinessError) => {
      hilog.error(0, 'PDFView', `terminateSelf 失败: code=${err.code}, ${err.message}`);
    });
  }

  backToMainMenu(): void {
    this.prepareLeaveViewerUi();
    setExitViewerOnBack(false);
    this.getUIContext().getRouter().replaceUrl({ url: 'product/pages/Index' }).catch(() => {
    });
  }

  rebuildSettingsDialogController(): void {
    this.settingsDialogController = new CustomDialogController({
      builder: SettingsDialogBuilder({
        showSlider: this.viewerViewModel.showSlider,
        horizontalSlideSensitivity: this.viewerViewModel.horizontalSlideSensitivity,
        linkVisualMode: this.viewerViewModel.linkVisualMode,
        onSliderToggled: (show: boolean) => {
          this.viewerViewModel.setShowSlider(show);
        },
        onHorizontalSlideSensitivityChange: (level: number) => {
          this.viewerViewModel.setHorizontalSlideSensitivity(level);
        },
        onLinkVisualModeChange: (mode: PDFLinkVisualMode) => {
          this.viewerViewModel.setLinkVisualMode(mode);
          this.linkController.applyPdfLinkVisualMode(true);
        }
      }),
      width: '85%'
    });
  }

  private updatePanelDocking(windowWidthPx: number): void {
    this.lastWindowWidthPx = windowWidthPx;
    const metronomeTotalWidthPx = this.getUIContext().vp2px(getFloatingMetronomeTotalWidth(this.metronomeChrome.scale));
    const tunerTotalWidthPx = this.getUIContext().vp2px(getFloatingTunerTotalWidth(this.tunerChrome.scale));
    const bookmarkTotalWidthPx = this.getUIContext().vp2px(getFloatingBookmarkTotalWidth(this.bookmarkChrome.scale));
    const shouldDockPanels = windowWidthPx <= metronomeTotalWidthPx
      || windowWidthPx <= tunerTotalWidthPx
      || windowWidthPx <= bookmarkTotalWidthPx;
    this.useDockedMetronomePanel = shouldDockPanels;
    this.useDockedTunerPanel = shouldDockPanels;
    this.useDockedBookmarkPanel = shouldDockPanels;
  }

  private isMetronomeDockedVisible(): boolean {
    return this.useDockedMetronomePanel && this.isMetronomePanelVisible();
  }

  private isTunerDockedVisible(): boolean {
    return this.useDockedTunerPanel && this.isTunerPanelVisible();
  }

  private isBookmarkPanelVisible(): boolean {
    return this.viewerViewModel.isBookmarkPanelVisible;
  }

  private isBookmarkDockedVisible(): boolean {
    return this.useDockedBookmarkPanel && this.isBookmarkPanelVisible();
  }

  private hasAnyDockedVisiblePanel(): boolean {
    return this.isMetronomeDockedVisible() || this.isTunerDockedVisible() || this.isBookmarkDockedVisible();
  }

  private getVisibleDockedPanelCount(): number {
    let count = 0;
    if (this.isMetronomeDockedVisible()) {
      count += 1;
    }
    if (this.isTunerDockedVisible()) {
      count += 1;
    }
    if (this.isBookmarkDockedVisible()) {
      count += 1;
    }
    return count;
  }

  private isMultiDockedPanelVisible(): boolean {
    return this.getVisibleDockedPanelCount() >= 2;
  }

  private getActiveDockedPanel(): OverlayPanelKey {
    if (this.activePanel === 'metronome' && this.isMetronomeDockedVisible()) {
      return 'metronome';
    }
    if (this.activePanel === 'tuner' && this.isTunerDockedVisible()) {
      return 'tuner';
    }
    if (this.activePanel === 'bookmark' && this.isBookmarkDockedVisible()) {
      return 'bookmark';
    }
    if (this.isMetronomeDockedVisible()) {
      return 'metronome';
    }
    if (this.isTunerDockedVisible()) {
      return 'tuner';
    }
    return 'bookmark';
  }

  private isDockedPanelTabActive(panel: OverlayPanelKey): boolean {
    return this.getActiveDockedPanel() === panel;
  }

  private updateMetronomeViewportFromArea(area: Area): void {
    this.metronomeViewportWidthVp = area.width as number;
    this.metronomeViewportHeightVp = area.height as number;
  }

  private updateTunerViewportFromArea(area: Area): void {
    this.tunerViewportWidthVp = area.width as number;
    this.tunerViewportHeightVp = area.height as number;
  }

  private updateBookmarkViewportFromArea(area: Area): void {
    this.bookmarkViewportWidthVp = area.width as number;
    this.bookmarkViewportHeightVp = area.height as number;
  }

  private updateMetronomeViewport(windowSize: window.Size): void {
    this.metronomeViewportWidthVp = this.getUIContext().px2vp(windowSize.width) as number;
    this.metronomeViewportHeightVp = this.getUIContext().px2vp(windowSize.height) as number;
    this.updatePanelDocking(windowSize.width);
  }

  private updateTunerViewport(windowSize: window.Size): void {
    this.tunerViewportWidthVp = this.getUIContext().px2vp(windowSize.width) as number;
    this.tunerViewportHeightVp = this.getUIContext().px2vp(windowSize.height) as number;
    this.updatePanelDocking(windowSize.width);
  }

  private refreshMetronomeDockingForCurrentWindow(): void {
    try {
      const rect = this.mainWindow.getWindowProperties().windowRect;
      this.updateMetronomeViewport({
        width: rect.width,
        height: rect.height
      });
    } catch (error) {
      hilog.error(0, 'PDFView', `刷新节拍器停靠状态出错: ${error}.`);
    }
  }

  private refreshTunerDockingForCurrentWindow(): void {
    try {
      const rect = this.mainWindow.getWindowProperties().windowRect;
      this.updateTunerViewport({
        width: rect.width,
        height: rect.height
      });
    } catch (error) {
      hilog.error(0, 'PDFView', `刷新调音器停靠状态出错: ${error}.`);
    }
  }

  private focusPanel(panel: OverlayPanelKey): void {
    if (this.activePanel === panel) {
      return;
    }

    this.activePanel = panel;
    this.syncPanelOverlays();
  }

  private handleMetronomePanelHeightChanged(heightVp: number): void {
    if (Math.abs(this.metronomePanelHeightVp - heightVp) < 0.001) {
      return;
    }

    this.metronomePanelHeightVp = heightVp;
    this.syncPanelOverlays();
  }

  private handleTunerPanelHeightChanged(heightVp: number): void {
    if (Math.abs(this.tunerPanelHeightVp - heightVp) < 0.001) {
      return;
    }

    this.tunerPanelHeightVp = heightVp;
    this.syncPanelOverlays();
  }

  private isMetronomePanelVisible(): boolean {
    return this.metronomeController.showWindow ?? false;
  }

  private isTunerPanelVisible(): boolean {
    return this.showTunerPanel;
  }

  private setTunerPanelVisible(visible: boolean): void {
    if (this.showTunerPanel === visible) {
      return;
    }
    this.showTunerPanel = visible;
    this.tunerController.setPanelVisible(visible);
    if (visible) {
      const hostContext: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      void this.tunerController.startMicrophoneMonitoring(hostContext, false);
    }
  }

  private getDockedMetronomeTopOffsetVp(): number {
    return 0;
  }

  private getDockedTunerTopOffsetVp(): number {
    return 0;
  }

  private getCurrentDockedPanelHeightVp(): number {
    if (!this.hasAnyDockedVisiblePanel()) {
      return 0;
    }
    if (this.dockedPanelHeightVp > 0) {
      return this.dockedPanelHeightVp;
    }
    const tabBarHeight = this.isMultiDockedPanelVisible() ? UnifiedDockTabBarHeightVp : 0;
    if (this.getActiveDockedPanel() === 'metronome') {
      return this.metronomePanelHeightVp + tabBarHeight;
    }
    if (this.getActiveDockedPanel() === 'tuner') {
      return this.tunerPanelHeightVp + tabBarHeight;
    }
    return this.bookmarkPanelHeightVp + tabBarHeight;
  }

  private handleDockedPanelHeightChanged(heightVp: number): void {
    if (Math.abs(this.dockedPanelHeightVp - heightVp) < 0.001) {
      return;
    }
    this.dockedPanelHeightVp = heightVp;
    this.syncPanelOffsetsToBounds();
    this.syncPanelOverlays();
  }

  private getFloatingMetronomeMinYVp(): number {
    return this.getCurrentDockedPanelHeightVp();
  }

  private getFloatingTunerMinYVp(): number {
    return this.getCurrentDockedPanelHeightVp();
  }

  private getFloatingBookmarkMinYVp(): number {
    return this.getCurrentDockedPanelHeightVp();
  }

  private updateBookmarkViewport(windowSize: window.Size): void {
    this.bookmarkViewportWidthVp = this.getUIContext().px2vp(windowSize.width) as number;
    this.bookmarkViewportHeightVp = this.getUIContext().px2vp(windowSize.height) as number;
    this.updatePanelDocking(windowSize.width);
  }

  private handleBookmarkPanelHeightChanged(heightVp: number): void {
    if (Math.abs(this.bookmarkPanelHeightVp - heightVp) < 0.001) {
      return;
    }
    this.bookmarkPanelHeightVp = heightVp;
    this.syncPanelOffsetsToBounds();
    this.syncPanelOverlays();
  }

  private getSafeTopVp(): number {
    return this.getUIContext().px2vp(this.avoidAreaTopPx);
  }

  private getSafeBottomVp(): number {
    return this.getUIContext().px2vp(this.avoidAreaBottomPx);
  }

  private getSafeLeftVp(): number {
    return this.getUIContext().px2vp(this.avoidAreaLeftPx);
  }

  private getSafeRightVp(): number {
    return this.getUIContext().px2vp(this.avoidAreaRightPx);
  }

  private getMetronomeClampParams(): FloatingPanelClampParams {
    const params: FloatingPanelClampParams = {
      viewportWidthVp: this.metronomeViewportWidthVp,
      viewportHeightVp: this.metronomeViewportHeightVp,
      contentWidthVp: FloatingMetronomeContentWidthVp,
      contentHeightVp: this.metronomePanelHeightVp,
      marginVp: FloatingPanelMarginVp,
      minX: 0,
      minY: this.getFloatingMetronomeMinYVp(),
      safeLeftVp: this.getSafeLeftVp(),
      safeTopVp: this.getSafeTopVp(),
      safeRightVp: this.getSafeRightVp(),
      safeBottomVp: this.getSafeBottomVp(),
      titleWidthVp: this.titleButtonWidthVp,
      titleHeightVp: this.titleButtonHeightVp,
      useDocked: this.useDockedMetronomePanel,
      dockedOffset: createFloatingPanelOffset(0, this.getDockedMetronomeTopOffsetVp())
    };
    return params;
  }

  private getTunerClampParams(): FloatingPanelClampParams {
    const params: FloatingPanelClampParams = {
      viewportWidthVp: this.tunerViewportWidthVp,
      viewportHeightVp: this.tunerViewportHeightVp,
      contentWidthVp: FloatingTunerContentWidthVp,
      contentHeightVp: this.tunerPanelHeightVp,
      marginVp: FloatingPanelMarginVp,
      minX: 0,
      minY: this.getFloatingTunerMinYVp(),
      safeLeftVp: this.getSafeLeftVp(),
      safeTopVp: this.getSafeTopVp(),
      safeRightVp: this.getSafeRightVp(),
      safeBottomVp: this.getSafeBottomVp(),
      titleWidthVp: this.titleButtonWidthVp,
      titleHeightVp: this.titleButtonHeightVp,
      useDocked: this.useDockedTunerPanel,
      dockedOffset: createFloatingPanelOffset(0, this.getDockedTunerTopOffsetVp())
    };
    return params;
  }

  private getPaletteContentHeightVp(): number {
    return getAnnotationPaletteContentHeight(this.viewerViewModel.isAnnotationLayerPanelVisible);
  }

  private getPaletteClampParams(): FloatingPanelClampParams {
    const params: FloatingPanelClampParams = {
      viewportWidthVp: this.getUIContext().px2vp(this.viewerViewModel.viewportSize.x),
      viewportHeightVp: this.getUIContext().px2vp(this.viewerViewModel.viewportSize.y),
      contentWidthVp: AnnotationPaletteContentWidth,
      contentHeightVp: this.getPaletteContentHeightVp(),
      marginVp: FloatingPanelMarginVp,
      minX: 0,
      minY: 0,
      safeLeftVp: this.getSafeLeftVp(),
      safeTopVp: this.getSafeTopVp(),
      safeRightVp: this.getSafeRightVp(),
      safeBottomVp: this.getSafeBottomVp(),
      titleWidthVp: this.titleButtonWidthVp,
      titleHeightVp: this.titleButtonHeightVp,
      useDocked: false,
      dockedOffset: createFloatingPanelOffset(0, 0)
    };
    return params;
  }

  private getBookmarkClampParams(): FloatingPanelClampParams {
    const viewerWidthVp: number = this.getUIContext().px2vp(this.viewerViewModel.viewportSize.x);
    const viewerHeightVp: number = this.getUIContext().px2vp(this.viewerViewModel.viewportSize.y);
    const viewportWidthVp: number = viewerWidthVp > 0 ? viewerWidthVp : this.bookmarkViewportWidthVp;
    const viewportHeightVp: number = viewerHeightVp > 0 ? viewerHeightVp : this.bookmarkViewportHeightVp;
    const contentHeightVp: number = this.bookmarkPanelHeightVp > 0
      ? this.bookmarkPanelHeightVp
      : BookmarkPanelContentHeight;
    const contentWidthVp: number = BookmarkPanelContentWidth;
    const params: FloatingPanelClampParams = {
      viewportWidthVp: viewportWidthVp,
      viewportHeightVp: viewportHeightVp,
      contentWidthVp: contentWidthVp,
      contentHeightVp: contentHeightVp,
      marginVp: FloatingPanelMarginVp,
      minX: 0,
      minY: this.getFloatingBookmarkMinYVp(),
      safeLeftVp: this.getSafeLeftVp(),
      safeTopVp: this.getSafeTopVp(),
      safeRightVp: this.getSafeRightVp(),
      safeBottomVp: this.getSafeBottomVp(),
      titleWidthVp: this.titleButtonWidthVp,
      titleHeightVp: this.titleButtonHeightVp,
      useDocked: this.useDockedBookmarkPanel,
      dockedOffset: createFloatingPanelOffset(0, 0)
    };
    return params;
  }

  private syncPanelOffsetsToBounds(): void {
    this.metronomeChrome.syncOffsetToBounds(this.getMetronomeClampParams());
    this.tunerChrome.syncOffsetToBounds(this.getTunerClampParams());
    this.bookmarkChrome.syncOffsetToBounds(this.getBookmarkClampParams());
    this.paletteChrome.syncOffsetToBounds(this.getPaletteClampParams());
  }

  private beginPanelGesture(panel: OverlayPanelKey): void {
    this.focusPanel(panel);
    this.isPanelGestureActive = true;
  }

  /** 色板不参与 dock 焦点栈，仅占用工具手势锁 */
  private beginPaletteGesture(): void {
    this.isPanelGestureActive = true;
  }

  private endPanelGesture(): void {
    this.isPanelGestureActive = false;
    this.syncPanelOffsetsToBounds();
    this.syncPanelOverlays();
  }

  private createMetronomeHostGestures(): FloatingPanelHostGestures {
    return this.metronomeChrome.createHostGestures(
      () => this.handleMetronomeHostDragStart(),
      (event: GestureEvent) => this.handleMetronomeHostDragUpdate(event),
      () => this.handleMetronomeHostDragEnd(),
      () => this.handleMetronomeHostPinchStart(),
      (event: GestureEvent) => this.handleMetronomeHostPinchUpdate(event),
      () => this.handleMetronomeHostPinchEnd()
    );
  }

  private createTunerHostGestures(): FloatingPanelHostGestures {
    return this.tunerChrome.createHostGestures(
      () => this.handleTunerHostDragStart(),
      (event: GestureEvent) => this.handleTunerHostDragUpdate(event),
      () => this.handleTunerHostDragEnd(),
      () => this.handleTunerHostPinchStart(),
      (event: GestureEvent) => this.handleTunerHostPinchUpdate(event),
      () => this.handleTunerHostPinchEnd()
    );
  }

  private createPaletteHostGestures(): FloatingPanelHostGestures {
    return this.paletteChrome.createHostGestures(
      () => this.handlePaletteHostDragStart(),
      (event: GestureEvent) => this.handlePaletteHostDragUpdate(event),
      () => this.handlePaletteHostDragEnd(),
      () => this.handlePaletteHostPinchStart(),
      (event: GestureEvent) => this.handlePaletteHostPinchUpdate(event),
      () => this.handlePaletteHostPinchEnd()
    );
  }

  private createBookmarkHostGestures(): FloatingPanelHostGestures {
    return this.bookmarkChrome.createHostGestures(
      () => this.handleBookmarkHostDragStart(),
      (event: GestureEvent) => this.handleBookmarkHostDragUpdate(event),
      () => this.handleBookmarkHostDragEnd(),
      () => this.handleBookmarkHostPinchStart(),
      (event: GestureEvent) => this.handleBookmarkHostPinchUpdate(event),
      () => this.handleBookmarkHostPinchEnd()
    );
  }

  private handleMetronomeHostDragStart(): void {
    if (this.useDockedMetronomePanel) {
      return;
    }
    this.beginPanelGesture('metronome');
    this.metronomeChrome.beginDrag(this.getMetronomeClampParams());
    this.syncPanelOverlays();
  }

  private handleMetronomeHostDragUpdate(event: GestureEvent): void {
    if (this.useDockedMetronomePanel) {
      return;
    }
    this.metronomeChrome.updateDrag(event, this.getMetronomeClampParams());
    this.syncPanelOverlays();
  }

  private handleMetronomeHostDragEnd(): void {
    this.endPanelGesture();
  }

  private handleMetronomeHostPinchStart(): void {
    if (this.useDockedMetronomePanel) {
      return;
    }
    this.beginPanelGesture('metronome');
    this.metronomeChrome.beginPinch();
  }

  private handleMetronomeHostPinchUpdate(event: GestureEvent): void {
    if (this.useDockedMetronomePanel) {
      return;
    }
    this.metronomeChrome.updatePinch(event);
    if (this.lastWindowWidthPx > 0) {
      this.updatePanelDocking(this.lastWindowWidthPx);
    } else {
      this.refreshMetronomeDockingForCurrentWindow();
    }
    this.syncPanelOffsetsToBounds();
    this.syncPanelOverlays();
  }

  private handleMetronomeHostPinchEnd(): void {
    this.metronomeChrome.endPinch();
    this.endPanelGesture();
  }

  private handleTunerHostDragStart(): void {
    if (this.useDockedTunerPanel) {
      return;
    }
    this.beginPanelGesture('tuner');
    this.tunerChrome.beginDrag(this.getTunerClampParams());
    this.syncPanelOverlays();
  }

  private handleTunerHostDragUpdate(event: GestureEvent): void {
    if (this.useDockedTunerPanel) {
      return;
    }
    this.tunerChrome.updateDrag(event, this.getTunerClampParams());
    this.syncPanelOverlays();
  }

  private handleTunerHostDragEnd(): void {
    this.endPanelGesture();
  }

  private handleTunerHostPinchStart(): void {
    if (this.useDockedTunerPanel) {
      return;
    }
    this.beginPanelGesture('tuner');
    this.tunerChrome.beginPinch();
  }

  private handleTunerHostPinchUpdate(event: GestureEvent): void {
    if (this.useDockedTunerPanel) {
      return;
    }
    this.tunerChrome.updatePinch(event);
    if (this.lastWindowWidthPx > 0) {
      this.updatePanelDocking(this.lastWindowWidthPx);
    } else {
      this.refreshTunerDockingForCurrentWindow();
    }
    this.syncPanelOffsetsToBounds();
    this.syncPanelOverlays();
  }

  private handleTunerHostPinchEnd(): void {
    this.tunerChrome.endPinch();
    this.endPanelGesture();
  }

  private createMetronomeOverlayParams(): MetronomeOverlayParams {
    const hostGestures: FloatingPanelHostGestures = this.createMetronomeHostGestures();
    return new MetronomeOverlayParams({
      controller: this.metronomeController,
      showWindow: this.metronomeController.showWindow ?? false,
      useDocked: this.useDockedMetronomePanel,
      dockedTopOffsetVp: this.getDockedMetronomeTopOffsetVp(),
      hostScale: this.useDockedMetronomePanel ? 1 : this.metronomeChrome.scale,
      hostOffset: this.metronomeChrome.getClampedOffset(this.getMetronomeClampParams()),
      overlaySafeTopVp: this.getSafeTopVp(),
      overlaySafeLeftVp: this.getSafeLeftVp(),
      onInteraction: () => this.focusPanel('metronome'),
      onTouchStateChanged: (active: boolean) => {
        this.isPanelGestureActive = active;
      },
      onHostDragStart: hostGestures.onHostDragStart,
      onHostDragUpdate: hostGestures.onHostDragUpdate,
      onHostDragEnd: hostGestures.onHostDragEnd,
      onHostPinchStart: hostGestures.onHostPinchStart,
      onHostPinchUpdate: hostGestures.onHostPinchUpdate,
      onHostPinchEnd: hostGestures.onHostPinchEnd,
      onWindowAreaHeightChanged: (heightVp: number) => this.handleMetronomePanelHeightChanged(heightVp),
      onClose: () => {
        this.metronomeController.closeWindow();
        this.syncPanelOverlays();
      },
      onOpenWindow: () => {
        this.metronomeController.openWindow();
        this.syncPanelOverlays();
      }
    });
  }

  private createTunerOverlayParams(): TunerOverlayParams {
    const hostGestures: FloatingPanelHostGestures = this.createTunerHostGestures();
    return new TunerOverlayParams({
      controller: this.tunerController,
      showWindow: this.showTunerPanel,
      useDocked: this.useDockedTunerPanel,
      dockedTopOffsetVp: this.getDockedTunerTopOffsetVp(),
      hostScale: this.useDockedTunerPanel ? 1 : this.tunerChrome.scale,
      hostOffset: this.tunerChrome.getClampedOffset(this.getTunerClampParams()),
      onInteraction: () => this.focusPanel('tuner'),
      onTouchStateChanged: (active: boolean) => {
        this.isPanelGestureActive = active;
      },
      onHostDragStart: hostGestures.onHostDragStart,
      onHostDragUpdate: hostGestures.onHostDragUpdate,
      onHostDragEnd: hostGestures.onHostDragEnd,
      onHostPinchStart: hostGestures.onHostPinchStart,
      onHostPinchUpdate: hostGestures.onHostPinchUpdate,
      onHostPinchEnd: hostGestures.onHostPinchEnd,
      onWindowAreaHeightChanged: (heightVp: number) => this.handleTunerPanelHeightChanged(heightVp),
      onClose: () => {
        this.setTunerPanelVisible(false);
        this.syncPanelOverlays();
      }
    });
  }

  private ensurePanelOverlays(): void {
    try {
      this.overlayManager = this.getUIContext().getOverlayManager();
      if (!this.metronomeOverlayContent) {
        this.metronomeOverlayContent = new ComponentContent(
          this.getUIContext(),
          wrapBuilder<[MetronomeOverlayParams]>(BuildMetronomeOverlay),
          this.createMetronomeOverlayParams()
        );
      }
      if (!this.tunerOverlayContent) {
        this.tunerOverlayContent = new ComponentContent(
          this.getUIContext(),
          wrapBuilder<[TunerOverlayParams]>(BuildTunerOverlay),
          this.createTunerOverlayParams()
        );
      }
      if (!this.paletteOverlayContent) {
        this.paletteOverlayContent = new ComponentContent(
          this.getUIContext(),
          wrapBuilder<[AnnotationPaletteOverlayParams]>(BuildAnnotationPaletteOverlay),
          this.createAnnotationPaletteOverlayParams()
        );
      }
      if (!this.bookmarkOverlayContent) {
        this.bookmarkOverlayContent = new ComponentContent(
          this.getUIContext(),
          wrapBuilder<[BookmarkOverlayParams]>(BuildBookmarkOverlay),
          this.createBookmarkOverlayParams()
        );
      }
      this.syncPanelOverlays();
    } catch (error) {
      hilog.error(0, 'PDFView', `初始化浮层管理器出错: ${error}.`);
    }
  }

  private syncPanelOverlays(): void {
    this.syncPdfViewerUnsavedState();
    if (!this.overlayManager || !this.metronomeOverlayContent || !this.tunerOverlayContent) {
      return;
    }

    try {
      if (!this.hasAnyDockedVisiblePanel()) {
        this.dockedPanelHeightVp = 0;
      }
      this.syncPanelOffsetsToBounds();
      this.metronomeOverlayContent.update(this.createMetronomeOverlayParams());
      this.tunerOverlayContent.update(this.createTunerOverlayParams());

      const lowerContent = this.activePanel === 'metronome' ? this.tunerOverlayContent : this.metronomeOverlayContent;
      const upperContent = this.activePanel === 'metronome' ? this.metronomeOverlayContent : this.tunerOverlayContent;
      this.overlayManager.addComponentContent(lowerContent, 0);
      this.overlayManager.addComponentContent(upperContent, 1);

      if (this.paletteOverlayContent) {
        this.paletteOverlayContent.update(this.createAnnotationPaletteOverlayParams());
        this.overlayManager.addComponentContent(this.paletteOverlayContent, 2);
      }
      if (this.bookmarkOverlayContent) {
        this.bookmarkOverlayContent.update(this.createBookmarkOverlayParams());
        this.overlayManager.addComponentContent(this.bookmarkOverlayContent, 3);
      }
    } catch (error) {
      hilog.error(0, 'PDFView', `同步浮层状态出错: ${error}.`);
    }
  }

  private disposePanelOverlays(): void {
    if (!this.overlayManager) {
      return;
    }

    try {
      // OverlayManager 是窗口级共享对象，跨页面存活。
      // 仅 removeComponentContent 只是把节点从 overlay 上卸下，前端 ComponentContent 仍持有
      // 后端节点引用，可能在再次进入 PDFView 时表现为"上次的浮层还在显示"。
      // 这里在卸载后再显式 dispose 并清空引用，确保完全释放，避免视觉残留与内存泄漏。
      if (this.metronomeOverlayContent) {
        this.overlayManager.removeComponentContent(this.metronomeOverlayContent);
        this.metronomeOverlayContent.dispose();
        this.metronomeOverlayContent = undefined;
      }
      if (this.tunerOverlayContent) {
        this.overlayManager.removeComponentContent(this.tunerOverlayContent);
        this.tunerOverlayContent.dispose();
        this.tunerOverlayContent = undefined;
      }
      if (this.paletteOverlayContent) {
        this.overlayManager.removeComponentContent(this.paletteOverlayContent);
        this.paletteOverlayContent.dispose();
        this.paletteOverlayContent = undefined;
      }
      if (this.bookmarkOverlayContent) {
        this.overlayManager.removeComponentContent(this.bookmarkOverlayContent);
        this.bookmarkOverlayContent.dispose();
        this.bookmarkOverlayContent = undefined;
      }
    } catch (error) {
      hilog.error(0, 'PDFView', `销毁浮层出错: ${error}.`);
    }
  }

  @Builder
  private buildDockedPanelTab(label: string, panel: OverlayPanelKey) {
    Button(label)
      .type(ButtonType.Capsule)
      .layoutWeight(1)
      .height(34)
      .fontSize(14)
      .fontWeight(this.isDockedPanelTabActive(panel) ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(Color.White)
      .backgroundColor(this.isDockedPanelTabActive(panel) ? 'rgba(77, 166, 255, 0.32)' : 'rgba(255, 255, 255, 0.08)')
      .border({
        width: 1,
        color: this.isDockedPanelTabActive(panel) ? 'rgba(77, 166, 255, 0.48)' : 'rgba(255, 255, 255, 0.05)'
      })
      .onClick(() => this.focusPanel(panel))
  }

  @Builder
  private buildDockedPanels() {
    Column() {
      if (this.hasAnyDockedVisiblePanel()) {
        Column({ space: 0 }) {
          if (this.isMultiDockedPanelVisible()) {
            Row({ space: 10 }) {
              if (this.isMetronomeDockedVisible()) {
                this.buildDockedPanelTab('节拍器', 'metronome')
              }
              if (this.isTunerDockedVisible()) {
                this.buildDockedPanelTab('调音器', 'tuner')
              }
              if (this.isBookmarkDockedVisible()) {
                this.buildDockedPanelTab('书签', 'bookmark')
              }
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 12,
              bottom: 10
            })
            .backgroundColor('rgba(8, 10, 14, 0.84)')
            .border({ width: 1, color: 'rgba(255, 255, 255, 0.07)' })
          }

          Scroll() {
            Column() {
              if (this.getActiveDockedPanel() === 'metronome' && this.isMetronomeDockedVisible()) {
                PDFMetronomePanelContent({
                  controller: this.metronomeController,
                  useDocked: true,
                  dockedTopOffsetVp: 0,
                  hostScale: 1,
                  hostOffset: { x: 0, y: 0 },
                  showDragHandle: false,
                  onInteraction: () => this.focusPanel('metronome'),
                  onTouchStateChanged: (active: boolean) => {
                    this.isPanelGestureActive = active;
                  },
                  onWindowAreaHeightChanged: (heightVp: number) => this.handleMetronomePanelHeightChanged(heightVp),
                  onHostDragStart: () => this.handleMetronomeHostDragStart(),
                  onHostDragUpdate: (event: GestureEvent) => this.handleMetronomeHostDragUpdate(event),
                  onHostDragEnd: () => this.handleMetronomeHostDragEnd(),
                  onHostPinchStart: () => this.handleMetronomeHostPinchStart(),
                  onHostPinchUpdate: (event: GestureEvent) => this.handleMetronomeHostPinchUpdate(event),
                  onHostPinchEnd: () => this.handleMetronomeHostPinchEnd(),
                  onClose: () => {
                    this.metronomeController.closeWindow();
                    this.syncPanelOverlays();
                  }
                })
              } else if (this.getActiveDockedPanel() === 'tuner' && this.isTunerDockedVisible()) {
                PDFTunerPanelContent({
                  controller: this.tunerController,
                  useDocked: true,
                  dockedTopOffsetVp: 0,
                  hostScale: 1,
                  hostOffset: { x: 0, y: 0 },
                  showDragHandle: false,
                  onInteraction: () => this.focusPanel('tuner'),
                  onTouchStateChanged: (active: boolean) => {
                    this.isPanelGestureActive = active;
                  },
                  onWindowAreaHeightChanged: (heightVp: number) => this.handleTunerPanelHeightChanged(heightVp),
                  onHostDragStart: () => this.handleTunerHostDragStart(),
                  onHostDragUpdate: (event: GestureEvent) => this.handleTunerHostDragUpdate(event),
                  onHostDragEnd: () => this.handleTunerHostDragEnd(),
                  onHostPinchStart: () => this.handleTunerHostPinchStart(),
                  onHostPinchUpdate: (event: GestureEvent) => this.handleTunerHostPinchUpdate(event),
                  onHostPinchEnd: () => this.handleTunerHostPinchEnd(),
                  onClose: () => {
                    this.setTunerPanelVisible(false);
                    this.syncPanelOverlays();
                  }
                })
              } else if (this.isBookmarkDockedVisible()) {
                PDFBookmarkPanelContent({
                  entries: this.bookmarkController.entries,
                  selectedId: this.bookmarkController.selectedId,
                  hasUnsavedBookmarks: this.bookmarkController.isDirty,
                  useDocked: true,
                  dockedTopOffsetVp: 0,
                  hostScale: 1,
                  hostOffset: { x: 0, y: 0 },
                  showDragHandle: false,
                  onSelect: (id: string) => {
                    this.bookmarkController.setSelectedId(id);
                    this.syncPanelOverlays();
                  },
                  onNavigate: (pageIndex: number) => {
                    void this.gotoPage(pageIndex);
                  },
                  readOnly: this.isDocumentReadOnly(),
                  onAddAtCurrentPage: () => {
                    if (this.isDocumentReadOnly()) {
                      return;
                    }
                    this.bookmarkController.addBookmarkAtPage(
                      this.viewerViewModel.currentPageIndex,
                      this.viewerViewModel.totalPageCount
                    );
                    this.syncPanelOverlays();
                  },
                  onDeleteSelected: () => {
                    if (this.isDocumentReadOnly()) {
                      return;
                    }
                    this.bookmarkController.removeSelected();
                    this.syncPanelOverlays();
                  },
                  onRenameSelected: () => {
                    if (this.isDocumentReadOnly()) {
                      return;
                    }
                    this.openBookmarkRenameDialog();
                  },
                  onSave: () => this.executeSaveDocument(),
                  onClose: () => {
                    this.viewerViewModel.closeBookmarkPanel();
                    this.syncPanelOverlays();
                  },
                  onTouchStateChanged: (active: boolean) => {
                    this.isPanelGestureActive = active;
                  },
                  onWindowAreaHeightChanged: (heightVp: number) => this.handleBookmarkPanelHeightChanged(heightVp),
                  onHostDragStart: () => this.handleBookmarkHostDragStart(),
                  onHostDragUpdate: (event: GestureEvent) => this.handleBookmarkHostDragUpdate(event),
                  onHostDragEnd: () => this.handleBookmarkHostDragEnd(),
                  onHostPinchStart: () => this.handleBookmarkHostPinchStart(),
                  onHostPinchUpdate: (event: GestureEvent) => this.handleBookmarkHostPinchUpdate(event),
                  onHostPinchEnd: () => this.handleBookmarkHostPinchEnd()
                })
              }
            }
            .width('100%')
            .height(LayoutPolicy.wrapContent)
            .justifyContent(FlexAlign.Start)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .layoutWeight(1)
          .align(Alignment.TopStart)
          .scrollable(ScrollDirection.Vertical)
          .scrollBar(BarState.Auto)
        }
        .width('100%')
        .constraintSize({ maxHeight: '100%' })
        .align(Alignment.TopStart)
        .padding({
          top: Math.max(this.getSafeTopVp(), this.titleButtonHeightVp),
          left: this.getSafeLeftVp(),
          right: this.getSafeRightVp()
        })
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          this.handleDockedPanelHeightChanged(newValue.height as number);
        })
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -14 })))
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  aboutToAppear(): void {
    let args = this.getUIContext().getRouter().getParams() as Record<string, string>;
    if (args == null || args['sandboxPath'] == null || args['sandboxPath'] == '') {
      const initialArgs = takeInitialPdfViewArgs();
      if (initialArgs !== undefined) {
        args = initialArgs;
      }
    }
    this.systemPath = args['systemPath'];
    this.sandBoxPath = args['sandboxPath'];
    this.saveTempPath = args['saveTempPath'];
    this.fileName = args['fileName'];
    const continuationInitialPageIndex = parseInitialPageIndexFromRouter(args);
    const continuationPending = isContinuationPendingRouterArgs(args);
    const continuationExtraLocalPaths = parseExtraLocalPathsFromRouter(args);
    this.documentSession.configureFromRouterArgs(
      continuationInitialPageIndex,
      continuationPending,
      continuationExtraLocalPaths
    );
    logContinuationLine(
      'PDFView.aboutToAppear fileName=' + this.fileName + ', sandboxLen=' + this.sandBoxPath.length.toString() +
      ', continuationPending=' + continuationPending.toString() +
      ', continuationInitialPageIndex=' + continuationInitialPageIndex.toString()
    );
    if (this.sandBoxPath.length > 0) {
      updateContinuationReadingState(
        this.sandBoxPath,
        this.systemPath,
        this.fileName,
        continuationInitialPageIndex
      );
    }

    // Lightweight setup that won't block the UI
    try {
      this.viewerViewModel.loadPreferences(this.preferences);
      this.linkController.applyPdfLinkVisualMode(false);
      this.annotationController.loadDrawPreferences();
      this.rebuildSettingsDialogController();
      this.metronomeController.initialize(this.preferences);
      this.tunerController.initialize(this.preferences);
      this.tunerController.setPanelVisible(this.showTunerPanel);
    } catch (e) {
      hilog.error(0, 'PDFView', `加载用户偏好出错: ${e}.`);
    }

    try {
      this.windowStatusCallback = (statusType: window.WindowStatusType) => this.isExclusiveFullScreen = statusType == window.WindowStatusType.FULL_SCREEN;
      this.mainWindow.on('windowStatusChange', this.windowStatusCallback);
      this.isExclusiveFullScreen = this.mainWindow.getWindowStatus() == window.WindowStatusType.FULL_SCREEN;

      this.freeWindowModeCallback = (isInFreeWindowMode: boolean) => this.isInFreeWindowMode = isInFreeWindowMode;
      this.mainWindow.on('freeWindowModeChange', this.freeWindowModeCallback);
      this.isInFreeWindowMode = this.mainWindow.isInFreeWindowMode();
      this.useDockedMetronomePanel = false;
      this.useDockedTunerPanel = false;
      this.windowSizeChangeCallback = (_windowSize: window.Size) => {
        this.syncAvoidAreasFromMainWindow();
        this.updateMetronomeViewport(_windowSize);
        this.updateTunerViewport(_windowSize);
        this.updateBookmarkViewport(_windowSize);
        this.syncPanelOffsetsToBounds();
        this.syncPanelOverlays();
      };
      this.mainWindow.on('windowSizeChange', this.windowSizeChangeCallback);
      this.avoidAreaChangeCallback = (_data: window.AvoidAreaOptions) => {
        this.syncAvoidAreasFromMainWindow();
      };
      this.titleButtonRectChangeCallback = (_rect: window.TitleButtonRect) => {
        this.syncAvoidAreasFromMainWindow();
      };
      this.syncAvoidAreasFromMainWindow();
      this.mainWindow.on('avoidAreaChange', this.avoidAreaChangeCallback);
      try {
        this.mainWindow.on('windowTitleButtonRectChange', this.titleButtonRectChangeCallback);
      } catch (_e) {
        this.titleButtonRectChangeCallback = undefined;
      }
    } catch (error) {
      hilog.error(0, 'PDFView', `获取窗口状态出错: ${error}.`);
    }

    this.ensurePanelOverlays();
    setPdfViewerActive(true);
    this.syncPdfViewerUnsavedState();

    const context = this.getUIContext().getHostContext() as Context;
    context.eventHub.on('onBackGround', this.onBackGround);
    context.eventHub.on('memoryPressure', this.onMemoryPressure);
    context.eventHub.on(EVENT_DOCUMENT_OPEN_REQUESTED, this.onDocumentOpenRequested);
    context.eventHub.on(EVENT_APP_TERMINATE_REQUESTED, this.onAppTerminateRequested);

    // 翻页遮罩：切到屏侧翻页时先显示渐变遮罩再渐出
    this.viewerViewModel.onPageFlipModeChanged = (mode: PDFPageFlipMode) => {
      if (mode === 'side') {
        this.triggerPageFlipShadeIntro();
      }
    };

    // Register hotkeys
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_DPAD_UP, KeyCode.KEYCODE_DPAD_LEFT], false, false, () => this.navigatePrevPage()));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_DPAD_DOWN, KeyCode.KEYCODE_DPAD_RIGHT, KeyCode.KEYCODE_SPACE], false, false, () => this.navigateNextPage()));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_Z], true, false, () => {
      if (this.isDocumentReadOnly()) {
        return;
      }
      this.annotationController.executeUndo();
      this.syncPanelOverlays();
    }));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_Z], true, true, () => {
      if (this.isDocumentReadOnly()) {
        return;
      }
      this.annotationController.executeRedo();
      this.syncPanelOverlays();
    }));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_Y], true, false, () => {
      if (this.isDocumentReadOnly()) {
        return;
      }
      this.annotationController.executeRedo();
      this.syncPanelOverlays();
    }));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_S], true, false, () => this.executeSaveDocument()));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_DPAD_UP, KeyCode.KEYCODE_DPAD_LEFT], true, false, () => this.gotoPage(0)));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_DPAD_DOWN, KeyCode.KEYCODE_DPAD_RIGHT, KeyCode.KEYCODE_SPACE], true, false, () => this.gotoPage(this.viewerViewModel.getLastNavigableIndex())));

    this.registerStylusDoubleTapListening();

    // 文档加载在 onPageShow 启动，避免 aboutToAppear 中弹窗导致 CustomDialog 空指针崩溃
  }

  onPageShow(): void {
    try {
      const rect = this.mainWindow.getWindowProperties().windowRect;
      this.windowSizeChangeCallback?.({
        width: rect.width,
        height: rect.height
      });
      this.syncAvoidAreasFromMainWindow();
      this.syncPanelOverlays();
    } catch (error) {
      hilog.error(0, 'PDFView', `获取窗口大小出错: ${error}.`);
    }
    if (!this.documentSession.documentInitStarted) {
      this.documentSession.documentInitStarted = true;
      this.documentSession.initializeDocument();
    }
    this.documentSession.enableContinuationForMigration();
    this.immersiveListening();
  }

  @Builder
  PasswordGateOverlay() {
    Column() {
      Column({ space: 16 }) {
        Text('输入 PDF 密码')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(ModalTitleTextColor)
          .width('100%')
          .textAlign(TextAlign.Center)
        Text(this.fileName)
          .fontSize(14)
          .fontColor(ModalMutedTextColor)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Center)
        if (this.documentSession.passwordGateErrorHint.length > 0) {
          Text(this.documentSession.passwordGateErrorHint)
            .fontSize(13)
            .fontColor(ModalErrorTextColor)
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        TextInput({ text: this.documentSession.passwordGateInput, placeholder: '密码' })
          .type(InputType.Password)
          .enterKeyType(EnterKeyType.Done)
          .defaultFocus(true)
          .showPasswordIcon(true)
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontColor(ModalTitleTextColor)
          .placeholderColor(ModalInputPlaceholderColor)
          .backgroundColor(ModalInputBackgroundColor)
          .caretColor(ModalInputCaretColor)
          .borderRadius(14)
          .padding({ left: 14, right: 14 })
          .onChange((value: string) => {
            this.documentSession.passwordGateInput = value;
          })
          .onSubmit((_enterKey: EnterKeyType, _event: SubmitEvent) => {
            this.documentSession.confirmPasswordGate();
          })
        Row({ space: 12 }) {
          Button('取消')
            .type(ButtonType.Capsule)
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .fontColor(ModalTitleTextColor)
            .backgroundColor(ModalButtonSecondaryColor)
            .onClick(() => this.documentSession.cancelPasswordGate())
          Button('确定')
            .type(ButtonType.Capsule)
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(ModalTitleTextColor)
            .backgroundColor(ModalButtonPrimaryColor)
            .onClick(() => this.documentSession.confirmPasswordGate())
        }
        .width('100%')
      }
      .width('80%')
      .constraintSize({ maxWidth: 400, minWidth: 280 })
      .padding(28)
      .borderRadius(18)
      .backgroundColor(ModalCardBackgroundColor)
      .border({ width: 1, color: ModalCardBorderColor })
      .shadow(ModalCardShadow)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 24, right: 24 })
    .backgroundColor(ModalDimOverlayColor)
  }

  /**
   * 拦截系统返回：应用内打开回首页；系统 Want 打开则移到后台回到调用方（不销毁）。
   */
  onBackPress(): boolean {
    this.requestLeaveViewer();
    return true;
  }

  aboutToDisappear(): void {
    // 不在此处 clearContinuationReadingState：系统发起接续时可能先销毁页面再调 onContinue
    this.cancelAnnotatePrepareSession();
    this.documentSession.resetSessionOnLeave();
    this.documentSession.disableContinuationForMigration();
    this.disposePanelOverlays();
    this.metronomeController.cleanup();
    this.tunerController.cleanup();
    this.immersiveDisablingListening();
    this.unregisterStylusDoubleTapListening();
    setPdfViewerActive(false);
    syncPdfViewerHasUnsavedChanges(false, false);

    const context = this.getUIContext().getHostContext() as Context;
    context.eventHub.off('onBackGround', this.onBackGround);
    context.eventHub.off('memoryPressure', this.onMemoryPressure);
    context.eventHub.off(EVENT_DOCUMENT_OPEN_REQUESTED, this.onDocumentOpenRequested);
    context.eventHub.off(EVENT_APP_TERMINATE_REQUESTED, this.onAppTerminateRequested);

    // 取消注册窗口状态监听
    if (this.windowStatusCallback) {
      try {
        this.mainWindow.off('windowStatusChange', this.windowStatusCallback);
      } catch (_e) { /* ignore */
      }
    }

    if (this.freeWindowModeCallback) {
      try {
        this.mainWindow.off('freeWindowModeChange', this.freeWindowModeCallback);
      } catch (_e) { /* ignore */
      }
    }

    if (this.windowSizeChangeCallback) {
      try {
        this.mainWindow.off('windowSizeChange', this.windowSizeChangeCallback);
      } catch (_e) { /* ignore */
      }
    }

    if (this.avoidAreaChangeCallback) {
      try {
        this.mainWindow.off('avoidAreaChange', this.avoidAreaChangeCallback);
      } catch (_e) { /* ignore */
      }
      this.avoidAreaChangeCallback = undefined;
    }

    if (this.titleButtonRectChangeCallback) {
      try {
        this.mainWindow.off('windowTitleButtonRectChange', this.titleButtonRectChangeCallback);
      } catch (_e) { /* ignore */
      }
      this.titleButtonRectChangeCallback = undefined;
    }

    // 清除透明度定时器
    if (this.transparencyTimeoutId) {
      clearTimeout(this.transparencyTimeoutId);
      this.transparencyTimeoutId = undefined;
    }
    this.linkController.clearPdfLinkFadeTimeout();
    this.linkController.clearLinkJumpHistory();

    // 清除预取防抖定时器
    if (this.prefetchDebounceId) {
      clearTimeout(this.prefetchDebounceId);
      this.prefetchDebounceId = undefined;
    }

    // 释放所有页面缓存和缩略图
    const totalPages = this.pageDataSource.totalCount();
    for (let i = 0; i < totalPages; i++) {
      const page = this.pageDataSource.getData(i);
      page.evictAllViewerCaches();
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

    // 释放 Worker 光栅会话（cancel + releaseDocument + terminate）
    PdfRenderSession.getInstance().cancelAll();
    void PdfRenderSession.getInstance().release().catch((error: Error) => {
      hilog.error(0, 'PDFView', 'PdfRenderSession.release 失败: ' + error.message);
    });

    // 释放主文档
    this.document.releaseDocument();
  }

  onPageHide(): void {
    const context = this.getUIContext().getHostContext() as Context;
    context.eventHub.emit('onBackGround');
  }

  onBackGround = () => {
    this.metronomeController.stopPlayback();
    this.immersiveDisablingListening();
  }

  /** 系统内存压力：在微任务中释放光栅，避免阻塞 Ability 回调主线程 */
  onMemoryPressure = (level: AbilityConstant.MemoryLevel): void => {
    setTimeout((): void => {
      try {
        this.pageDataSource.applyMemoryPressure(
          level,
          this.viewerViewModel.displayedPageIndices,
          this.viewerViewModel.currentPageIndex
        );
      } catch (e) {
        hilog.error(0, 'PDFView', `applyMemoryPressure 失败: ${e}`);
      }
    }, 0);
  };

  makeSharedData(): systemShare.SharedData {
    const pdfUtd: string = utd.getUniformDataTypeByFilenameExtension('.pdf');
    const shareData: systemShare.SharedData = new systemShare.SharedData({
      utd: pdfUtd,
      uri: fileUri.getUriFromPath(this.sandBoxPath),
      title: this.fileName,
      description: `共 ${this.viewerViewModel.totalPageCount} 页`
    });
    return shareData;
  }

  immersiveCallback = (sharableTarget: harmonyShare.SharableTarget) => {
    if (!this.sandBoxPath || this.documentSession.isDocumentLoading) {
      hilog.warn(0, 'PDFView', '文档未就绪，忽略隔空传送/碰一碰分享');
      return;
    }
    try {
      sharableTarget.share(this.makeSharedData());
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0, 'PDFView', `分享当前 PDF 失败: ${err.code} ${err.message}`);
    }
  }

  private resolveHarmonyShareWindowId(): number {
    try {
      const windowId = this.mainWindow.getWindowProperties().id;
      this.harmonyShareWindowId = windowId;
      return windowId;
    } catch (error) {
      hilog.error(0, 'PDFView', `获取分享窗口 ID 失败: ${error}`);
      return -1;
    }
  }

  private knockShareNeedsWindowId(): boolean {
    return deviceInfo.deviceType === '2in1';
  }

  private registerKnockFileReceive(windowId: number): void {
    if (!this.knockShareNeedsWindowId() || this.harmonyShareReceiveRegistered || windowId < 0) {
      return;
    }
    const recvCapability: harmonyShare.RecvCapabilityRegistry = {
      windowId: windowId,
      capabilities: [
        { utd: utd.UniformDataType.PDF, maxSupportedCount: 1 },
        { utd: utd.UniformDataType.FILE, maxSupportedCount: 1 }
      ]
    };
    try {
      harmonyShare.on('dataReceive', recvCapability, (receiveTarget: harmonyShare.ReceivableTarget) => {
        const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
        const receiveDirUri = fileUri.getUriFromPath(hostContext.filesDir);
        receiveTarget.receive(receiveDirUri, {
          onDataReceived: (shareData: systemShare.SharedData) => {
            this.openKnockReceivedPdf(shareData);
          },
          onResult: (resultCode: harmonyShare.ShareResultCode) => {
            if (resultCode !== harmonyShare.ShareResultCode.SHARE_SUCCESS) {
              hilog.error(0, 'PDFView', `碰一碰接收失败: ${resultCode}`);
            }
          }
        });
      });
      this.harmonyShareReceiveRegistered = true;
    } catch (error) {
      hilog.error(0, 'PDFView', `注册碰一碰沙箱接收失败: ${error}`);
    }
  }

  private openKnockReceivedPdf(shareData: systemShare.SharedData): void {
    const records = shareData.getRecords();
    if (records.length === 0 || !records[0].uri) {
      return;
    }
    const record = records[0];
    const sharedUri: string = record.uri as string;
    let sandboxPath: string = sharedUri;
    try {
      const resolvedPath: string = new fileUri.FileUri(sharedUri).path;
      if (resolvedPath.length > 0) {
        sandboxPath = resolvedPath;
      }
    } catch (_error) {
    }
    if (!sandboxPath.toLowerCase().endsWith('.pdf')) {
      hilog.warn(0, 'PDFView', `碰一碰接收忽略非 PDF: ${sandboxPath}`);
      return;
    }
    const baseName = sandboxPath.split('/').pop() ?? 'received.pdf';
    const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const saveTempPath = `${hostContext.tempDir}/saveTemp_${baseName}`;
    const params: Record<string, string> = {
      'systemPath': sharedUri,
      'sandboxPath': sandboxPath,
      'saveTempPath': saveTempPath,
      'fileName': record.title ?? baseName
    };
    this.requestOpenDocument(params);
  }

  private unregisterKnockFileReceive(): void {
    if (!this.harmonyShareReceiveRegistered || this.harmonyShareWindowId < 0) {
      return;
    }
    try {
      harmonyShare.off('dataReceive', {
        windowId: this.harmonyShareWindowId,
        capabilities: [
          { utd: utd.UniformDataType.PDF, maxSupportedCount: 1 },
          { utd: utd.UniformDataType.FILE, maxSupportedCount: 1 }
        ]
      });
    } catch (error) {
      hilog.error(0, 'PDFView', `取消碰一碰沙箱接收失败: ${error}`);
    }
    this.harmonyShareReceiveRegistered = false;
  }

  /** 从主窗口同步状态栏与导航指示条避让（px）；仅约束交互控件 */
  private syncAvoidAreasFromMainWindow(): void {
    try {
      const insets = readWindowSafeInsetsPx(this.mainWindow);
      const changed = insets.top !== this.avoidAreaTopPx
        || insets.bottom !== this.avoidAreaBottomPx
        || insets.left !== this.avoidAreaLeftPx
        || insets.right !== this.avoidAreaRightPx
        || insets.titleWidthVp !== this.titleButtonWidthVp
        || insets.titleHeightVp !== this.titleButtonHeightVp;
      this.avoidAreaTopPx = insets.top;
      this.avoidAreaBottomPx = insets.bottom;
      this.avoidAreaLeftPx = insets.left;
      this.avoidAreaRightPx = insets.right;
      this.titleButtonWidthVp = insets.titleWidthVp;
      this.titleButtonHeightVp = insets.titleHeightVp;
      if (changed) {
        this.syncPanelOffsetsToBounds();
        this.syncPanelOverlays();
      }
    } catch (_e) {
    }
  }

  immersiveListening(): void {
    if (!canIUse('SystemCapability.Collaboration.HarmonyShare') || this.harmonyShareListening) {
      return;
    }
    const windowId = this.resolveHarmonyShareWindowId();
    if (windowId < 0) {
      return;
    }
    const sendCapability: harmonyShare.SendCapabilityRegistry = { windowId: windowId };
    try {
      harmonyShare.on('gesturesShare', sendCapability, this.immersiveCallback);
      this.harmonyShareKnockUsesWindowId = this.knockShareNeedsWindowId();
      if (this.harmonyShareKnockUsesWindowId) {
        harmonyShare.on('knockShare', sendCapability, this.immersiveCallback);
        this.registerKnockFileReceive(windowId);
      } else {
        harmonyShare.on('knockShare', this.immersiveCallback);
      }
      this.harmonyShareListening = true;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0, 'PDFView', `注册隔空传送/碰一碰监听失败: ${err.code} ${err.message}`);
    }
  }

  immersiveDisablingListening(): void {
    if (!canIUse('SystemCapability.Collaboration.HarmonyShare') || !this.harmonyShareListening) {
      return;
    }
    try {
      if (this.harmonyShareWindowId >= 0) {
        const sendCapability: harmonyShare.SendCapabilityRegistry = { windowId: this.harmonyShareWindowId };
        harmonyShare.off('gesturesShare', sendCapability, this.immersiveCallback);
        if (this.harmonyShareKnockUsesWindowId) {
          harmonyShare.off('knockShare', sendCapability, this.immersiveCallback);
        } else {
          harmonyShare.off('knockShare', this.immersiveCallback);
        }
      } else {
        harmonyShare.off('gesturesShare', this.immersiveCallback);
        harmonyShare.off('knockShare', this.immersiveCallback);
      }
      this.unregisterKnockFileReceive();
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0, 'PDFView', `取消隔空传送/碰一碰监听失败: ${err.code} ${err.message}`);
    }
    this.harmonyShareListening = false;
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
      if (loadVersion !== this.pageLoadVersion) {
        return;
      }
      // 更新相应视图的 pixelMap
      const displayIndex = this.viewerViewModel.displayedPageIndices.indexOf(pageIndex);
      const slot = this.mainSlotAt(displayIndex);
      if (slot !== undefined) {
        this.applyRasterCacheToSlot(slot, cache);
      }
    }
    // 根据更新的 displaySizes 重新计算 viewSize
    this.updateViewerViewSize();
  }

  private readPixelMapWidth(pixelMap: PixelMap | undefined): number {
    if (pixelMap === undefined) {
      return 0;
    }
    try {
      return pixelMap.getImageInfoSync().size.width;
    } catch (_e) {
      return 0;
    }
  }

  /**
   * 将光栅缓存铺到槽位。
   * 小缩放过采样或交互手势中：用 layoutPixelMap，避免 HQ 大纹理上屏/每帧变换。
   */
  private applyRasterCacheToSlot(slot: PageViewSlot, cache: PageCache): void {
    const bitmapW: number = this.readPixelMapWidth(cache.pixelMap);
    const viewScale: number = this.viewerViewModel.viewScale;
    const screenW: number = cache.displaySize.x * viewScale;
    const oversampleRatio: number = screenW > 0.001 ? bitmapW / screenW : 1;
    const preferLayout: boolean =
      this.interactiveMotionDemoted || oversampleRatio > 1.35;
    if (preferLayout && cache.layoutPixelMap !== undefined) {
      slot.applyDisplay(selectDisplayPixelMap(cache, true), cache.displaySize, false);
      return;
    }
    slot.applyCache(cache);
  }

  /** 拖拽/捏合/滑动开始：主条+邻条降到 layout，避免 HQ 纹理跟手变换 */
  private beginInteractiveMotionDemote(): void {
    if (this.interactiveMotionDemoted) {
      return;
    }
    this.interactiveMotionDemoted = true;
    for (let i = 0; i < this.viewerViewModel.displayedPageIndices.length; i++) {
      const pageIndex: number = this.viewerViewModel.displayedPageIndices[i];
      const slot = this.mainSlotAt(i);
      const cache = this.pageDataSource.peekPageCache(pageIndex, this.currentRenderScale);
      if (slot === undefined || cache === undefined || cache.layoutPixelMap === undefined) {
        continue;
      }
      slot.applyDisplay(cache.layoutPixelMap, cache.displaySize, false);
    }
    this.pageTurnController.demoteTransitionSlotsToLayout();
  }

  /** 手势结束：按当前 viewScale 恢复 HQ/layout 选择 */
  private endInteractiveMotionDemote(): void {
    if (!this.interactiveMotionDemoted) {
      return;
    }
    this.interactiveMotionDemoted = false;
    void this.updateDisplayedPagesAtScale(this.currentRenderScale);
  }

  updateViewerViewSize(): void {
    this.viewerViewModel.updateViewSize(
      this.mainSlots[0].viewSize,
      this.mainSlots[1].viewSize,
      this.mainSlots[2].viewSize
    );
  }

  /** 安全取主槽；越界返回 undefined */
  private mainSlotAt(index: number): PageViewSlot | undefined {
    if (index < 0 || index >= this.mainSlots.length) {
      return undefined;
    }
    return this.mainSlots[index];
  }

  private resetMainDrawCanvases(): void {
    for (let i = 0; i < this.mainSlots.length; i++) {
      this.mainSlots[i].resetDrawCanvas();
    }
  }

  private resetMainCanvases(): void {
    for (let i = 0; i < this.mainSlots.length; i++) {
      this.mainSlots[i].resetCanvases();
    }
  }

  /**
   * 高分辨率就绪时解析主槽索引：load 未完成前以 mainSlotPagesBeingLoaded 为准，否则以 displayed 为准。
   * @returns 槽位 0..2，或 -1 表示不应写入主槽
   */
  private resolveMainSlotIndexForPage(targetIndex: number): number {
    if (this.mainSlotPagesBeingLoaded.length > 0) {
      return this.mainSlotPagesBeingLoaded.indexOf(targetIndex);
    }
    return this.viewerViewModel.displayedPageIndices.indexOf(targetIndex);
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
        const displayIndex = this.resolveMainSlotIndexForPage(targetIndex);
        const mainSlot = this.mainSlotAt(displayIndex);
        if (mainSlot !== undefined) {
          // Automatically update display when high-res version is ready
          this.applyRasterCacheToSlot(mainSlot, highResCache);
        }
        this.pageTurnController.applyTransitionHighResIfNeeded(targetIndex, highResCache);
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

  // 根据页面原始大小计算显示大小（与光栅 Worker 中的 displaySize 计算一致）
  private getPageDisplaySize(pageIndex: number): Vector2 {
    const rawSize = this.pageDataSource.getPageRawSize(pageIndex);
    return mul(rawSize, 2);
  }

  /**
   * 按当前 displayed 与期望槽位数对齐空主槽（透明占位或清除）。
   * 仅用于横向滑动 defer 收尾：在恢复主层可见前调用。
   */
  private ensureMainRowEmptySlotsMatchDisplayed(): void {
    const indices = this.viewerViewModel.displayedPageIndices;
    const expectedSlots = this.viewerViewModel.getExpectedSlotCount();
    const refPage = indices.length > 0 ? indices[indices.length - 1] : 0;

    for (let slot = 1; slot < PAGE_VIEW_SLOT_COUNT; slot++) {
      if (indices.length > slot) {
        continue;
      }
      if (expectedSlots >= slot + 1) {
        this.mainSlots[slot].applyDisplay(
          this.transparentPlaceholderPixelMap,
          this.getPageDisplaySize(refPage),
          false
        );
      } else {
        this.mainSlots[slot].applyDisplay(undefined, Vec2(0, 0), false);
      }
    }

    this.updateViewerViewSize();
  }

  // 立即铺主槽占位（白色/透明），不等待 Worker
  private applyMainSlotPlaceholders(indices: number[], seedFromActiveTransitionStrip: boolean = false): void {
    this.mainSlotPagesBeingLoaded = indices.slice();
    for (let i = 0; i < this.mainSlots.length; i++) {
      this.mainSlots[i].clearLoading();
    }

    // 根据显示模式确定期望的槽位数，剩余页面不足时仍用白色占位保持布局稳定
    const expectedSlots: number = this.viewerViewModel.getExpectedSlotCount();

    const seeded: boolean[] = seedFromActiveTransitionStrip
      ? this.pageTurnController.trySeedMainViewsFromTransition(indices)
      : [false, false, false];

    for (let slot = 0; slot < PAGE_VIEW_SLOT_COUNT; slot++) {
      if (indices.length > slot) {
        if (!seeded[slot]) {
          this.mainSlots[slot].applyDisplay(
            this.placeholderPixelMap,
            this.getPageDisplaySize(indices[slot]),
            true
          );
        }
      } else if (slot === 0) {
        this.mainSlots[0].clearPixelMap();
      } else if (expectedSlots >= slot + 1) {
        // 空占位：透明区域保持与最后一个实际页面相同大小，避免多页模式下末尾出现布局跳变
        this.mainSlots[slot].applyDisplay(
          this.transparentPlaceholderPixelMap,
          this.getPageDisplaySize(indices[indices.length - 1]),
          false
        );
      } else {
        this.mainSlots[slot].applyDisplay(undefined, Vec2(0, 0), false);
      }
    }

    this.updateViewerViewSize();
  }

  // 将光栅填入主槽；若导航已被更新的 gotoPage 取代则丢弃结果
  private async loadCachesIntoMainSlots(indices: number[], loadVersion: number): Promise<void> {
    const tasks: Array<Promise<void>> = [];

    for (let slot = 0; slot < indices.length && slot < PAGE_VIEW_SLOT_COUNT; slot++) {
      const pageIndex = indices[slot];
      const slotIndex = slot;
      tasks.push(this.getPageCache(pageIndex, this.currentRenderScale, loadVersion)
        .then(cache => {
          if (loadVersion !== this.pageLoadVersion) {
            return;
          }
          this.applyRasterCacheToSlot(this.mainSlots[slotIndex], cache);
        })
        .catch((_e: Error) => {
        }));
    }

    await Promise.all(tasks);

    if (loadVersion !== this.pageLoadVersion) {
      this.mainSlotPagesBeingLoaded = [];
      return;
    }

    this.updateViewerViewSize();
  }

  async gotoPage(targetIndex: number, deferSlideVisualReset: boolean = false, recordJumpHistory: boolean = true): Promise<void> {
    this.pageTurnController.clearPendingSlideGotoTarget();
    if (targetIndex < 0 || targetIndex >= this.viewerViewModel.totalPageCount) {
      if (deferSlideVisualReset) {
        this.pageTurnController.resetHorizontalSlidePreview();
        this.pageTurnController.slideGotoInFlight = false;
      }
      return;
    }

    const clampedTarget = Math.max(0, Math.min(targetIndex, Math.max(0, this.viewerViewModel.totalPageCount - 1)));
    if (recordJumpHistory) {
      this.linkController.recordLinkJumpHistory(this.viewerViewModel.currentPageIndex, clampedTarget);
    }
    const indicesToLoad = this.viewerViewModel.getDisplayedIndicesForTargetPage(clampedTarget);

    // 取消上一次导航结束时安排的预取，否则 300ms 后仍以「旧中心」淘汰远页，
    // 会取消当前正在 load 的目标页 taskpool 任务（日志: task has been canceled），导致停在某页永不 commit。
    if (this.prefetchDebounceId !== undefined) {
      clearTimeout(this.prefetchDebounceId);
      this.prefetchDebounceId = undefined;
    }

    if (!deferSlideVisualReset) {
      this.viewerViewModel.clearSlideNavEffectiveStartIndex();
      this.pageTurnController.resetHorizontalSlidePreview();
      this.pageTurnController.slideGotoInFlight = false;
    }

    // 递增加载版本以使上一个 gotoPage 发起的所有异步回调失效
    this.pageLoadVersion++;
    const navToken = this.pageLoadVersion;

    if (deferSlideVisualReset) {
      this.pageTurnController.markSlideGotoInFlight(navToken);
    }

    // 导航到新页面时重置渲染缩放（先于 load，避免仍按旧缩放取缓存）
    this.currentRenderScale = ViewerMinRenderScale;

    // 丢掉已过期的排队光栅，避免滑块连跳后落地页排在中间页之后
    this.pageDataSource.cancelQueuedPendingExcept(indicesToLoad);

    // 先铺占位再 commit，滑块与页码跟上手指；位图仍按 navToken 异步填入
    this.applyMainSlotPlaceholders(indicesToLoad, deferSlideVisualReset);
    this.viewerViewModel.commitPageTarget(clampedTarget);
    if (this.viewerViewModel.isAnnotatePaletteVisible) {
      this.noteAnnotationPageInteraction(clampedTarget);
    }
    this.linkController.triggerPdfLinkVisualPageEnter();
    this.documentSession.syncContinuationReadingState();
    // displayed 已切换：须立刻按新 indices 重绘笔画层，否则透明 Image 下仍会叠上一套槽位的旧画布（双页末槽尤其明显）。
    this.redrawStrokes();

    await this.loadCachesIntoMainSlots(indicesToLoad, navToken);

    if (navToken !== this.pageLoadVersion) {
      this.mainSlotPagesBeingLoaded = [];
      if (deferSlideVisualReset) {
        this.pageTurnController.clearSlideGotoInFlightIfToken(navToken);
      }
      return;
    }

    this.mainSlotPagesBeingLoaded = [];

    // Debounce prefetch/eviction to avoid cache churn during rapid scrolling
    if (this.prefetchDebounceId !== undefined) {
      clearTimeout(this.prefetchDebounceId);
    }
    this.prefetchDebounceId = setTimeout(() => {
      this.prefetchDebounceId = undefined;
      this.pageDataSource.prefetchPagesAround(
        clampedTarget,
        5,
        15,
        this.viewerViewModel.displayedPageIndices,
        this.currentRenderScale,
        1
      );
    }, 300);

    if (deferSlideVisualReset) {
      this.pageTurnController.fadeDeferSlideGotoTeardown(navToken);
    } else {
      this.resetViewToFit();
      this.redrawStrokes();
    }
  }

  resetViewToFit(): void {
    this.viewerViewModel.resetViewToFit(this.getUIContext());
  }

  navigatePrevPage(): void {
    this.gotoPage(this.viewerViewModel.navigateToPreviousPage(), false, false);
  }

  navigateNextPage(): void {
    this.gotoPage(this.viewerViewModel.navigateToNextPage(), false, false);
  }

  private handlePageSliderChange(newValue: number, mode: SliderChangeMode): void {
    if (mode === SliderChangeMode.Begin) {
      this.sliderJumpStartPageIndex = this.viewerViewModel.currentPageIndex;
      void this.gotoPage(newValue, false, false);
      return;
    }
    if (mode === SliderChangeMode.Moving) {
      void this.gotoPage(newValue, false, false);
      return;
    }
    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      const fromPage = this.sliderJumpStartPageIndex ?? this.viewerViewModel.currentPageIndex;
      this.sliderJumpStartPageIndex = undefined;
      void this.gotoPage(newValue, false, false).then(() => {
        this.linkController.recordLinkJumpHistory(fromPage, newValue);
      });
      return;
    }
    void this.gotoPage(newValue, false, false);
  }

  /** 屏侧透明翻页区：若当前手势为平移/捏合/滚轮缩放则消费一次点击而不翻页 */
  navigatePrevPageFromSideFlipZone(): void {
    if (this.suppressSidePageFlipFromGesture) {
      this.suppressSidePageFlipFromGesture = false;
      return;
    }
    this.navigatePrevPage();
  }

  navigateNextPageFromSideFlipZone(): void {
    if (this.suppressSidePageFlipFromGesture) {
      this.suppressSidePageFlipFromGesture = false;
      return;
    }
    this.navigateNextPage();
  }

  async refreshDisplayedPages(): Promise<void> {
    for (let i = 0; i < this.viewerViewModel.displayedPageIndices.length; i++) {
      const pageIndex = this.viewerViewModel.displayedPageIndices[i];
      const cache = await this.getPageCache(pageIndex, this.currentRenderScale);
      const slot = this.mainSlotAt(i);
      if (slot !== undefined) {
        this.applyRasterCacheToSlot(slot, cache);
      }
    }
    this.updateViewerViewSize();
    this.redrawStrokes();
  }

  redrawStrokes(): void {
    // 清除并重新绘制所有可见画布的笔画
    this.resetMainCanvases();

    // 加载显示页面的笔画
    for (let i = 0; i < this.viewerViewModel.displayedPageIndices.length; i++) {
      const pageIndex = this.viewerViewModel.displayedPageIndices[i];
      const slot = this.mainSlotAt(i);
      if (slot !== undefined) {
        this.annotationController.loadPageStrokes(slot.annotateCtx, pageIndex);
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
    const slot = this.mainSlotAt(viewIndex);
    const viewSize: Vector2 = slot !== undefined ? slot.viewSize : Vec2(0, 0);

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

  private transitionRowMaxHeightPx(): number {
    let h = 0;
    for (let i = 0; i < this.mainSlots.length; i++) {
      h = Math.max(h, this.mainSlots[i].viewSize.y);
    }
    const prevN = this.pageTurnController.transPrevIndices.length;
    for (let i = 0; i < prevN && i < this.pageTurnController.transPrevSlots.length; i++) {
      h = Math.max(h, this.pageTurnController.transPrevSlots[i].viewSize.y);
    }
    const nextN = this.pageTurnController.transNextIndices.length;
    for (let i = 0; i < nextN && i < this.pageTurnController.transNextSlots.length; i++) {
      h = Math.max(h, this.pageTurnController.transNextSlots[i].viewSize.y);
    }
    return h;
  }

  /** 主文档层声明尺寸只使用当前页面组，预览层用独立 overlay 尺寸，避免影响 fit/pan。 */
  private getStripLayoutSizePx(): Vector2 {
    return this.viewerViewModel.viewSize;
  }

  private getTransitionPageIndex(side: 'next' | 'prev', viewIndex: number): number {
    const arr = side === 'next' ? this.pageTurnController.transNextIndices : this.pageTurnController.transPrevIndices;
    return arr[viewIndex] ?? 0;
  }

  getTransitionCanvasScale(side: 'next' | 'prev', viewIndex: number): ScaleOptions {
    const slot = this.pageTurnController.transitionSlotAt(side, viewIndex);
    const viewSize: Vector2 = slot !== undefined ? slot.viewSize : Vec2(0, 0);
    const pageIndex = this.getTransitionPageIndex(side, viewIndex);
    const canvasSize = this.getCanvasSize(pageIndex);
    if (canvasSize.x === 0 || canvasSize.y === 0) {
      return { x: 1, y: 1, centerX: 0, centerY: 0 };
    }
    const scaleX = viewSize.x / canvasSize.x;
    const scaleY = viewSize.y / canvasSize.y;
    return { x: scaleX, y: scaleY, centerX: 0, centerY: 0 };
  }

  private transitionSlotVisible(side: 'next' | 'prev', viewIndex: number): boolean {
    const arr = side === 'next' ? this.pageTurnController.transNextIndices : this.pageTurnController.transPrevIndices;
    return viewIndex < arr.length;
  }

  handleDrawTouch(
    drawCtx: CanvasRenderingContext2D,
    targetCtx: CanvasRenderingContext2D,
    pageIndex: number,
    event: TouchEvent
  ): void {
    if (this.isDocumentReadOnly()) {
      return;
    }
    if (this.isPanelGestureActive) {
      const resetResult = this.annotationController.resetTransientState();
      if (resetResult.clearedDraw) {
        drawCtx.reset();
      }
      if (resetResult.clearedErase) {
        this.redrawStrokes();
      }
      return;
    }

    // 手写笔触点 id 常非 0；仅用 id===0 会拒绝整段笔迹（见 ArkUI TouchObject / sourceTool）。
    if (!this.isSinglePointerForDrawTouch(event)) {
      return;
    }

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

    const touchPoint: Vector2 = Vec2(event.touches[0].x, event.touches[0].y);

    if (this.annotationController.annotateMode === 'draw') {
      if (event.type === TouchType.Down) {
        this.noteAnnotationPageInteraction(pageIndex);
        this.annotationController.startDraw(touchPoint);
      } else if (event.type === TouchType.Move) {
        this.annotationController.extendDraw(touchPoint, drawCtx);
      } else if (event.type === TouchType.Up) {
        this.annotationController.finishDraw(pageIndex, touchPoint, drawCtx, targetCtx);
        this.syncPanelOverlays();
      }
    } else if (this.annotationController.annotateMode === 'erase') {
      if (this.pageDataSource.getPageStrokesCount(pageIndex) === 0) {
        return;
      }

      if (event.type === TouchType.Down) {
        this.noteAnnotationPageInteraction(pageIndex);
        this.annotationController.startErase();
      }

      if (event.type === TouchType.Down || event.type === TouchType.Move) {
        this.annotationController.previewErase(pageIndex, touchPoint, targetCtx);
      } else if (event.type === TouchType.Up) {
        this.annotationController.finishErase(pageIndex, targetCtx);
        this.syncPanelOverlays();
      }
    }
  }

  // 单指绘制：手指要求 id===0；手写笔用 SourceTool.Pen 识别，不要求 id。
  private isSinglePointerForDrawTouch(event: TouchEvent): boolean {
    if (event.touches.length !== 1) {
      return false;
    }
    return event.touches[0].id === 0 || event.sourceTool === SourceTool.Pen;
  }

  private isPointInsidePaletteVp(vpX: number, vpY: number): boolean {
    if (!this.viewerViewModel.isAnnotatePaletteVisible) {
      return false;
    }
    const offset = this.paletteChrome.getClampedOffset(this.getPaletteClampParams());
    const margin = 10;
    const w = AnnotationPaletteContentWidth * this.paletteChrome.scale;
    const h = this.getPaletteContentHeightVp() * this.paletteChrome.scale;
    return vpX >= offset.x + margin && vpX <= offset.x + margin + w
      && vpY >= offset.y + margin && vpY <= offset.y + margin + h;
  }

  handleViewAction(event: TouchEvent): void {
    if (this.isPanelGestureActive) {
      return;
    }

    if (event.touches.length > 0 &&
      this.isPointInsidePaletteVp(
        this.getUIContext().px2vp(event.touches[0].x),
        this.getUIContext().px2vp(event.touches[0].y)
      )) {
      return;
    }

    const isSingleFingerTouch = event.touches.length === 1 && event.touches[0].id === 0;
    const isPenSingleTouch = event.touches.length === 1 && event.sourceTool === SourceTool.Pen;
    const isDualTouch = event.touches.length === 2 && event.touches[0].id === 0 && event.touches[1].id === 1;
    const isTripleTouch =
      event.touches.length === 3 && event.touches[0].id === 0 && event.touches[1].id === 1 && event.touches[2].id === 2;

    if (isTripleTouch) {
      if (!this.isDocumentReadOnly()
        && event.type === TouchType.Down
        && (this.annotationController.annotateMode === 'draw' || this.annotationController.annotateMode === 'erase')) {
        this.annotationController.executeUndo();
        this.syncPanelOverlays();
      }
      return;
    }

    // 拖动模式下手写笔点页面：仅打开批注（绘制仍走 Canvas onTouch，避免与透明层重复派发导致毛刺）。
    if (isPenSingleTouch && event.type === TouchType.Down && this.viewerViewModel.annotateMode === 'drag') {
      this.cancelLongPress();
      this.enterAnnotateMode();
      return;
    }

    if (isSingleFingerTouch && this.viewerViewModel.annotateMode === 'drag') {
      const touchPoint = Vec2(event.touches[0].x, event.touches[0].y);
      const uiCtx = this.getUIContext();
      if (event.type == TouchType.Down) {
        if (this.viewerViewModel.pageFlipMode === 'horizontalSlide') {
          this.pageTurnController.interruptHorizontalSlideForNewTouch();
        }
        const startedOnPdfLink = this.linkController.pdfLinkPressCandidateActive;
        this.lastTouchPoint = touchPoint;
        this.panSessionStartPoint = touchPoint;
        this.suppressSidePageFlipFromGesture = startedOnPdfLink;
        if (!startedOnPdfLink && !this.viewerViewModel.isAnnotatePaletteVisible && !this.isDocumentReadOnly()) {
          this.startLongPressDetection(touchPoint.x, touchPoint.y);
        }
      } else if (event.type == TouchType.Move) {
        if (this.panSessionStartPoint !== undefined) {
          const sx = touchPoint.x - this.panSessionStartPoint.x;
          const sy = touchPoint.y - this.panSessionStartPoint.y;
          if (sx * sx + sy * sy > PAGE_FLIP_SUPPRESS_MOVE_PX * PAGE_FLIP_SUPPRESS_MOVE_PX) {
            this.suppressSidePageFlipFromGesture = true;
            this.linkController.cancelPdfLinkPressCandidateForDrag(sx, sy);
          }
        }
        if (this.longPressTouchDown && this.lastTouchPoint !== undefined) {
          const dx = touchPoint.x - this.longPressPosX;
          const dy = touchPoint.y - this.longPressPosY;
          if (Math.sqrt(dx * dx + dy * dy) > LONG_PRESS_MOVE_THRESHOLD) {
            this.cancelLongPress();
          }
        }
        if (this.linkController.pdfLinkPressCandidateActive) {
          this.cancelLongPress();
        }
        if (this.lastTouchPoint !== undefined) {
          const delta = Vec2(
            touchPoint.x - this.lastTouchPoint.x,
            touchPoint.y - this.lastTouchPoint.y
          );
          this.beginInteractiveMotionDemote();
          if (this.viewerViewModel.pageFlipMode === 'horizontalSlide') {
            const dvp = pxToVp(delta, uiCtx);
            this.pageTurnController.handleHorizontalSlideDragMove(delta, dvp);
          } else {
            this.viewerViewModel.panBy(delta, uiCtx);
          }
          this.lastTouchPoint = touchPoint;
        }
      } else if (event.type == TouchType.Up || event.type === TouchType.Cancel) {
        this.cancelLongPress();
        if (this.viewerViewModel.pageFlipMode === 'horizontalSlide') {
          this.pageTurnController.finalizeHorizontalSlideOnUp();
        }
        this.endInteractiveMotionDemote();
        this.lastTouchPoint = undefined;
        this.panSessionStartPoint = undefined;
        this.linkController.schedulePdfLinkPressCandidateReset();
      }
    } else if (isDualTouch) {
      this.cancelLongPress();
      this.pageTurnController.resetHorizontalSlidePreview();
      this.suppressSidePageFlipFromGesture = true;
      this.panSessionStartPoint = undefined;
      // 捏合放大处理 - 始终启用，不受注释模式影响
      // 标记双指手势激活，防止在绘制/擦除模式下意外创建笔画
      this.isDualFingerActive = true;

      // 立即中断并清除任何进行中的绘制/擦除操作
      const resetResult = this.annotationController.resetTransientState();
      if (resetResult.clearedDraw) {
        this.resetMainDrawCanvases();
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
        this.beginInteractiveMotionDemote();
      } else if (event.type == TouchType.Move) {
        if (this.lastPinchDistance !== undefined && this.lastPinchCenter !== undefined) {
          // 计算缩放变化
          const scaleRatio = pinchDistance / this.lastPinchDistance;

          // 计算捏合中心运动（拖动分量）
          const centerDeltaX = pinchCenter.x - this.lastPinchCenter.x;
          const centerDeltaY = pinchCenter.y - this.lastPinchCenter.y;
          this.beginInteractiveMotionDemote();
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
        this.endInteractiveMotionDemote();
        // 检查捏合结束后是否需要以不同的缩放重新渲染
        this.checkAndUpdateRenderScale();
      }
      // 在捏合模式下清除单指触摸跟踪
      this.lastTouchPoint = undefined;
    } else {
      // 重置所有触摸跟踪
      this.lastTouchPoint = undefined;
      this.panSessionStartPoint = undefined;
      this.linkController.schedulePdfLinkPressCandidateReset();
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
    if (this.isPanelGestureActive || this.isPointInsidePaletteVp(event.x, event.y)) {
      return;
    }

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
      if (this.viewerViewModel.annotateMode === 'drag' && (isLeftButton || isRightButton)) {
        this.mousePanSessionStart = mousePoint;
        this.suppressSidePageFlipFromGesture = false;
      }
    } else if (event.action === MouseAction.Move) {
      if (this.lastMousePoint !== undefined && this.activeMouseButton !== 0) {
        const delta = Vec2(
          mousePoint.x - this.lastMousePoint.x,
          mousePoint.y - this.lastMousePoint.y
        );

        if (this.viewerViewModel.annotateMode === 'drag') {
          if (this.activeMouseButton === 1 || this.activeMouseButton === 2) {
            if (this.mousePanSessionStart !== undefined) {
              const sx = mousePoint.x - this.mousePanSessionStart.x;
              const sy = mousePoint.y - this.mousePanSessionStart.y;
              if (sx * sx + sy * sy > PAGE_FLIP_SUPPRESS_MOVE_PX * PAGE_FLIP_SUPPRESS_MOVE_PX) {
                this.suppressSidePageFlipFromGesture = true;
              }
            }
            this.beginInteractiveMotionDemote();
            this.viewerViewModel.panBy(delta, this.getUIContext());
          }
        } else {
          if (this.activeMouseButton === 2) {
            this.beginInteractiveMotionDemote();
            this.viewerViewModel.panBy(delta, this.getUIContext());
          }
        }

        this.lastMousePoint = mousePoint;
      }
    } else if (event.action === MouseAction.Release) {
      this.endInteractiveMotionDemote();
      this.lastMousePoint = undefined;
      this.activeMouseButton = 0;
      this.mousePanSessionStart = undefined;
    }
  }

  handleDrawMouse(
    drawCtx: CanvasRenderingContext2D,
    targetCtx: CanvasRenderingContext2D,
    pageIndex: number,
    event: MouseEvent
  ): void {
    if (this.isDocumentReadOnly()) {
      return;
    }
    if (this.isPanelGestureActive) {
      return;
    }

    const isLeftButton = event.button === MouseButton.Left;
    if (!isLeftButton) {
      return;
    }

    const mousePoint = Vec2(event.x, event.y);

    if (this.annotationController.annotateMode === 'draw') {
      if (event.action === MouseAction.Press) {
        this.noteAnnotationPageInteraction(pageIndex);
        this.annotationController.startDraw(mousePoint);
      } else if (event.action === MouseAction.Move && this.activeMouseButton === 1) {
        this.annotationController.extendDraw(mousePoint, drawCtx);
      } else if (event.action === MouseAction.Release) {
        this.annotationController.finishDraw(pageIndex, mousePoint, drawCtx, targetCtx);
        this.syncPanelOverlays();
      }
    } else if (this.annotationController.annotateMode === 'erase') {
      if (this.pageDataSource.getPageStrokesCount(pageIndex) == 0) {
        return;
      }

      if (event.action === MouseAction.Press) {
        this.noteAnnotationPageInteraction(pageIndex);
        this.annotationController.startErase();
      }

      if (event.action === MouseAction.Press || (event.action === MouseAction.Move && this.activeMouseButton === 1)) {
        this.annotationController.previewErase(pageIndex, mousePoint, targetCtx);
      } else if (event.action === MouseAction.Release) {
        this.annotationController.finishErase(pageIndex, targetCtx);
        this.syncPanelOverlays();
      }
    }
  }

  handleMouseAxisEvent(event: AxisEvent): void {
    const scrollAmount = -event.getVerticalAxisValue();
    if (scrollAmount != undefined && scrollAmount != 0) {
      const mousePoint = Vec2(event.x, event.y);
      const zoomFactor = scrollAmount > 0 ? 1.1 : 0.9;
      this.suppressSidePageFlipFromGesture = true;
      this.viewerViewModel.zoomAround(mousePoint, zoomFactor, Vec2(0, 0), this.getUIContext());

      this.checkAndUpdateRenderScale();
    }
  }

  cancelLongPress(): void {
    if (this.longPressDelayId !== undefined) {
      clearTimeout(this.longPressDelayId);
      this.longPressDelayId = undefined;
    }
    if (this.longPressAnimId !== undefined) {
      clearInterval(this.longPressAnimId);
      this.longPressAnimId = undefined;
    }
    this.longPressTouchDown = false;
    this.longPressVisible = false;
    this.longPressProgress = 0;
  }

  startLongPressDetection(x: number, y: number): void {
    this.cancelLongPress();
    this.longPressTouchDown = true;
    this.longPressPosX = x;
    this.longPressPosY = y;

    this.longPressDelayId = setTimeout(() => {
      if (!this.longPressTouchDown) {
        return;
      }
      this.longPressVisible = true;
      this.longPressStartTime = Date.now();
      this.longPressAnimId = setInterval(() => {
        if (!this.longPressTouchDown) {
          this.cancelLongPress();
          return;
        }
        const elapsed = Date.now() - this.longPressStartTime;
        this.longPressProgress = Math.min(1, elapsed / LONG_PRESS_DURATION_MS);
        if (this.longPressProgress >= 1) {
          this.cancelLongPress();
          this.enterAnnotateMode();
        }
      }, LONG_PRESS_TICK_INTERVAL);
    }, LONG_PRESS_DELAY_MS);
  }

  enterAnnotateMode(explicitTool?: PDFAnnotateMode): void {
    if (this.isDocumentSaving) {
      return;
    }
    if (this.isAnnotateModePreparing) {
      return;
    }
    this.viewerViewModel.openAnnotatePalette(explicitTool);
    this.noteAnnotationPageInteraction(this.viewerViewModel.currentPageIndex);
    this.initPalettePosition();
    this.syncPanelOverlays();

    if (this.annotationController.isImportedPolylinePrepared()) {
      return;
    }

    void this.annotationController.startPrepareImportedPolylineSession()
      .then(() => this.syncPanelOverlays())
      .catch((error: Error) => hilog.error(0, 'PDFView', '导入已有折线批注出错: ' + error.message))
      .finally(() => {
        this.syncPanelOverlays();
      });
  }

  initPalettePosition(): void {
    if (this.paletteChrome.offset.x !== 0 || this.paletteChrome.offset.y !== 0) {
      return;
    }
    const viewportWidthVp = this.getUIContext().px2vp(this.viewerViewModel.viewportSize.x);
    const viewportHeightVp = this.getUIContext().px2vp(this.viewerViewModel.viewportSize.y);
    const scaledW = AnnotationPaletteContentWidth * this.paletteChrome.scale;
    const scaledH = this.getPaletteContentHeightVp() * this.paletteChrome.scale;
    this.paletteChrome.offset = createFloatingPanelOffset(
      Math.max(0, (viewportWidthVp - scaledW) / 2),
      Math.max(0, viewportHeightVp - scaledH - 80)
    );
    this.paletteChrome.syncOffsetToBounds(this.getPaletteClampParams());
  }

  private handlePaletteHostDragStart(): void {
    this.beginPaletteGesture();
    this.paletteChrome.beginDrag(this.getPaletteClampParams());
    this.syncPanelOverlays();
  }

  private handlePaletteHostDragUpdate(event: GestureEvent): void {
    this.paletteChrome.updateDrag(event, this.getPaletteClampParams());
    this.syncPanelOverlays();
  }

  private handlePaletteHostDragEnd(): void {
    this.endPanelGesture();
  }

  private handlePaletteHostPinchStart(): void {
    this.beginPaletteGesture();
    this.paletteChrome.beginPinch();
  }

  private handlePaletteHostPinchUpdate(event: GestureEvent): void {
    this.paletteChrome.updatePinch(event);
    this.paletteChrome.offset = this.paletteChrome.getClampedOffset(this.getPaletteClampParams());
    this.syncPanelOverlays();
  }

  private handlePaletteHostPinchEnd(): void {
    this.paletteChrome.endPinch();
    this.endPanelGesture();
  }

  private noteAnnotationPageInteraction(pageIndex: number): void {
    this.annotationController.setLayerPanelPageIndex(pageIndex);
    this.syncPanelOverlays();
  }

  private createAnnotationPaletteOverlayParams(): AnnotationPaletteOverlayParams {
    const hostGestures: FloatingPanelHostGestures = this.createPaletteHostGestures();
    const paletteOffset: FloatingPanelOffset = this.paletteChrome.getClampedOffset(this.getPaletteClampParams());
    return new AnnotationPaletteOverlayParams({
      showWindow: this.viewerViewModel.isAnnotatePaletteVisible,
      readOnly: this.isDocumentReadOnly(),
      annotateMode: this.viewerViewModel.annotateMode,
      undoCount: this.annotationController.undoHistoryCount,
      redoCount: this.annotationController.redoHistoryCount,
      hasUnsaved: this.annotationController.hasUnsavedStrokes,
      hostScale: this.paletteChrome.scale,
      hostOffset: paletteOffset,
      drawColor: this.annotationController.selectedDrawColor,
      customDrawColor: this.annotationController.customDrawColor,
      recentCustomColors: this.annotationController.recentCustomColors,
      onSetMode: (mode: PDFAnnotateMode) => this.handlePaletteSetMode(mode),
      onSelectDrawColor: (color: AnnotationColor) => {
        if (this.isDocumentReadOnly()) {
          return;
        }
        this.annotationController.setSelectedDrawColor(color);
        this.syncPanelOverlays();
      },
      onSetCustomDrawColor: (color: AnnotationColor) => {
        if (this.isDocumentReadOnly()) {
          return;
        }
        this.annotationController.setCustomDrawColor(color);
        this.syncPanelOverlays();
      },
      onCommitRecentCustomColor: (color: AnnotationColor) => {
        if (this.isDocumentReadOnly()) {
          return;
        }
        this.annotationController.pushRecentCustomColor(color);
        this.annotationController.flushPendingDrawColorPreferences();
        this.syncPanelOverlays();
      },
      onUndo: () => {
        if (this.isDocumentReadOnly()) {
          return;
        }
        this.annotationController.executeUndo();
        this.syncPanelOverlays();
      },
      onRedo: () => {
        if (this.isDocumentReadOnly()) {
          return;
        }
        this.annotationController.executeRedo();
        this.syncPanelOverlays();
      },
      onSave: () => this.executeSaveDocument(),
      onClose: () => {
        this.annotationController.flushPendingDrawColorPreferences();
        this.viewerViewModel.closeAnnotatePalette();
        this.syncPanelOverlays();
      },
      layerPanelVisible: this.viewerViewModel.isAnnotationLayerPanelVisible,
      layerItems: this.annotationController.layerItems,
      onToggleLayerPanel: () => {
        this.viewerViewModel.toggleAnnotationLayerPanel();
        this.syncPanelOverlays();
      },
      onSelectLayer: (id: string) => {
        this.annotationController.setActiveLayer(id);
        this.syncPanelOverlays();
      },
      onToggleLayerVisible: (id: string, visible: boolean) => {
        if (this.isDocumentReadOnly()) {
          return;
        }
        this.annotationController.setLayerVisible(id, visible);
        this.syncPanelOverlays();
      },
      onAddLayer: () => {
        if (this.isDocumentReadOnly()) {
          return;
        }
        this.annotationController.addLayer();
        this.syncPanelOverlays();
      },
      onRenameLayer: (id: string, name: string) => {
        if (this.isDocumentReadOnly()) {
          return;
        }
        this.annotationController.renameLayer(id, name);
        this.syncPanelOverlays();
      },
      onDeleteLayer: (id: string) => {
        if (this.isDocumentReadOnly()) {
          return;
        }
        this.annotationController.deleteLayer(id);
        this.syncPanelOverlays();
      },
      onTouchStateChanged: (active: boolean) => {
        this.isPanelGestureActive = active;
      },
      onHostDragStart: hostGestures.onHostDragStart,
      onHostDragUpdate: hostGestures.onHostDragUpdate,
      onHostDragEnd: hostGestures.onHostDragEnd,
      onHostPinchStart: hostGestures.onHostPinchStart,
      onHostPinchUpdate: hostGestures.onHostPinchUpdate,
      onHostPinchEnd: hostGestures.onHostPinchEnd
    });
  }

  private openBookmarkRenameDialog(): void {
    if (this.isDocumentReadOnly()) {
      return;
    }
    if (this.bookmarkController.selectedId.length === 0) {
      return;
    }
    this.bookmarkRenameDialogController = new CustomDialogController({
      builder: BookmarkTitleDialogBuilder({
        initialTitle: this.bookmarkController.getSelectedTitle(),
        onCancel: () => {},
        onConfirm: (title: string) => {
          this.bookmarkController.renameSelected(title);
          this.syncPanelOverlays();
        }
      }),
      alignment: DialogAlignment.Center,
      autoCancel: true,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.38)'
    });
    this.bookmarkRenameDialogController.open();
  }

  private handleBookmarkHostDragStart(): void {
    this.beginPanelGesture('bookmark');
    this.bookmarkChrome.beginDrag(this.getBookmarkClampParams());
    this.syncPanelOverlays();
  }

  private handleBookmarkHostDragUpdate(event: GestureEvent): void {
    this.bookmarkChrome.updateDrag(event, this.getBookmarkClampParams());
    this.syncPanelOverlays();
  }

  private handleBookmarkHostDragEnd(): void {
    this.isPanelGestureActive = false;
    this.syncPanelOverlays();
  }

  private handleBookmarkHostPinchStart(): void {
    this.isPanelGestureActive = true;
    this.bookmarkChrome.beginPinch();
  }

  private handleBookmarkHostPinchUpdate(event: GestureEvent): void {
    this.bookmarkChrome.updatePinch(event);
    this.bookmarkChrome.offset = this.bookmarkChrome.getClampedOffset(this.getBookmarkClampParams());
    this.syncPanelOverlays();
  }

  private handleBookmarkHostPinchEnd(): void {
    this.bookmarkChrome.endPinch();
    this.isPanelGestureActive = false;
    this.syncPanelOverlays();
  }

  private toggleBookmarkPanel(): void {
    this.focusPanel('bookmark');
    this.viewerViewModel.toggleBookmarkPanel();
    if (this.viewerViewModel.isBookmarkPanelVisible) {
      try {
        const rect = this.mainWindow.getWindowProperties().windowRect;
        this.updateBookmarkViewport({ width: rect.width, height: rect.height });
      } catch (_e) {
        /* ignore */
      }
    }
    this.syncPanelOverlays();
  }

  private createBookmarkOverlayParams(): BookmarkOverlayParams {
    const hostGestures: FloatingPanelHostGestures = this.createBookmarkHostGestures();
    return new BookmarkOverlayParams({
      showWindow: this.viewerViewModel.isBookmarkPanelVisible,
      readOnly: this.isDocumentReadOnly(),
      useDocked: this.useDockedBookmarkPanel,
      dockedTopOffsetVp: 0,
      entries: this.bookmarkController.entries,
      selectedId: this.bookmarkController.selectedId,
      hasUnsavedBookmarks: this.bookmarkController.isDirty,
      hostScale: this.useDockedBookmarkPanel ? 1 : this.bookmarkChrome.scale,
      hostOffset: this.bookmarkChrome.getClampedOffset(this.getBookmarkClampParams()),
      onSelect: (id: string) => {
        this.bookmarkController.setSelectedId(id);
        this.syncPanelOverlays();
      },
      onNavigate: (pageIndex: number) => {
        void this.gotoPage(pageIndex);
      },
      onAddAtCurrentPage: () => {
        if (this.isDocumentReadOnly()) {
          return;
        }
        this.bookmarkController.addBookmarkAtPage(
          this.viewerViewModel.currentPageIndex,
          this.viewerViewModel.totalPageCount
        );
        this.viewerViewModel.openBookmarkPanel();
        this.syncPanelOverlays();
      },
      onDeleteSelected: () => {
        if (this.isDocumentReadOnly()) {
          return;
        }
        this.bookmarkController.removeSelected();
        this.syncPanelOverlays();
      },
      onRenameSelected: () => this.openBookmarkRenameDialog(),
      onSaveDocument: () => this.executeSaveDocument(),
      onClose: () => {
        this.viewerViewModel.closeBookmarkPanel();
        this.syncPanelOverlays();
      },
      onTouchStateChanged: (active: boolean) => {
        this.isPanelGestureActive = active;
      },
      onWindowAreaHeightChanged: (heightVp: number) => this.handleBookmarkPanelHeightChanged(heightVp),
      onHostDragStart: hostGestures.onHostDragStart,
      onHostDragUpdate: hostGestures.onHostDragUpdate,
      onHostDragEnd: hostGestures.onHostDragEnd,
      onHostPinchStart: hostGestures.onHostPinchStart,
      onHostPinchUpdate: hostGestures.onHostPinchUpdate,
      onHostPinchEnd: hostGestures.onHostPinchEnd
    });
  }

  handlePaletteSetMode(mode: PDFAnnotateMode): void {
    if (this.isDocumentReadOnly()) {
      return;
    }
    if (this.viewerViewModel.annotateMode === mode) {
      this.viewerViewModel.closeAnnotatePalette();
    } else {
      this.viewerViewModel.setAnnotateMode(mode);
    }
    this.syncPanelOverlays();
  }

  private registerStylusDoubleTapListening(): void {
    if (!canIUse('SystemCapability.Stylus.StylusService') || this.stylusDoubleTapListening) {
      return;
    }
    try {
      stylusInteraction.on('doubleTap', this.stylusDoubleTapCallback);
      this.stylusDoubleTapListening = true;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0, 'PDFView', `注册手写笔双击监听失败: ${err.code} ${err.message}`);
    }
  }

  private unregisterStylusDoubleTapListening(): void {
    if (!canIUse('SystemCapability.Stylus.StylusService') || !this.stylusDoubleTapListening) {
      return;
    }
    try {
      stylusInteraction.off('doubleTap', this.stylusDoubleTapCallback);
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0, 'PDFView', `注销手写笔双击监听失败: ${err.code} ${err.message}`);
    }
    this.stylusDoubleTapListening = false;
  }

  private cancelActiveAnnotationGesture(): void {
    const resetResult = this.annotationController.resetTransientState();
    if (resetResult.clearedDraw) {
      this.resetMainDrawCanvases();
    }
    if (resetResult.clearedErase) {
      this.redrawStrokes();
    }
  }

  private handleStylusDoubleTap(): void {
    if (this.isDocumentReadOnly()) {
      return;
    }
    if (!this.viewerViewModel.isAnnotatePaletteVisible) {
      return;
    }
    const mode = this.viewerViewModel.annotateMode;
    if (mode !== 'draw' && mode !== 'erase') {
      return;
    }
    this.cancelActiveAnnotationGesture();
    const nextMode: PDFAnnotateMode = mode === 'draw' ? 'erase' : 'draw';
    this.viewerViewModel.setAnnotateMode(nextMode);
    this.syncPanelOverlays();
  }

  startTransparencyTimeout(): void {
    if (this.transparencyTimeoutId) {
      clearTimeout(this.transparencyTimeoutId);
    }
    this.viewerViewModel.controlsTransparency = 1;
    this.transparencyTimeoutId = setTimeout(() => this.viewerViewModel.controlsTransparency = 0.5, 1000 * 3);
  }

  triggerPageFlipShadeIntro(): void {
    if (this.viewerViewModel.pageFlipMode !== 'side' || this.viewerViewModel.annotateMode !== 'drag') {
      return;
    }
    this.pageFlipShadeOpacity = 1;
    setTimeout(() => {
      this.getUIContext().animateTo({
        duration: 800,
        curve: Curve.EaseOut
      }, () => {
        this.pageFlipShadeOpacity = 0;
      });
    }, 200);
  }

  build() {
    Stack() {
      RelativeContainer() {

        Row(ContainerCfg) {

          PDFPageSlot({
            pixelMap: this.mainSlots[0].pixelMap,
            loading: this.mainSlots[0].loading,
            viewSize: this.mainSlots[0].viewSize,
            canvasSize: this.getCanvasSize(this.viewerViewModel.displayedPageIndices[0] ?? 0),
            canvasScale: this.getCanvasScale(0),
            visible: true,
            drawCanvasVisible: this.viewerViewModel.annotateMode !== 'drag' && !this.isDocumentReadOnly(),
            annotateCtx: this.mainSlots[0].annotateCtx,
            drawCtx: this.mainSlots[0].drawCtx,
            onDrawTouch: (event: TouchEvent) => this.handleDrawTouch(this.mainSlots[0].drawCtx, this.mainSlots[0].annotateCtx, this.viewerViewModel.displayedPageIndices[0] ?? 0, event),
            onDrawMouse: (event: MouseEvent) => this.handleDrawMouse(this.mainSlots[0].drawCtx, this.mainSlots[0].annotateCtx, this.viewerViewModel.displayedPageIndices[0] ?? 0, event),
            linkHitAreas: this.linkController.getLinkHitAreasForSlot(0),
            linkOverlayEnabled: this.linkController.isLinkOverlayEnabled(),
            linkVisualOpacity: this.linkController.pdfLinkVisualOpacity,
            onLinkPressStart: (hitArea: PDFLinkDisplayHitArea) => this.linkController.handlePdfLinkPressStart(hitArea),
            onLinkPressCancel: (hitArea: PDFLinkDisplayHitArea) => this.linkController.handlePdfLinkPressCancel(hitArea),
            onLinkActivated: (hitArea: PDFLinkDisplayHitArea) => this.linkController.activatePdfLink(hitArea)
          })

          PDFPageSlot({
            pixelMap: this.mainSlots[1].pixelMap,
            loading: this.mainSlots[1].loading,
            viewSize: this.mainSlots[1].viewSize,
            canvasSize: this.getCanvasSize(this.viewerViewModel.displayedPageIndices[1] ?? 0),
            canvasScale: this.getCanvasScale(1),
            visible: this.viewerViewModel.shouldShowSecondSlot() &&
              this.viewerViewModel.displayedPageIndices.length >= 2,
            occupyLayoutWhenHidden: this.viewerViewModel.shouldShowSecondSlot(),
            drawCanvasVisible: this.viewerViewModel.annotateMode !== 'drag' && !this.isDocumentReadOnly(),
            annotateCtx: this.mainSlots[1].annotateCtx,
            drawCtx: this.mainSlots[1].drawCtx,
            onDrawTouch: (event: TouchEvent) => this.handleDrawTouch(this.mainSlots[1].drawCtx, this.mainSlots[1].annotateCtx, this.viewerViewModel.displayedPageIndices[1] ?? 0, event),
            onDrawMouse: (event: MouseEvent) => this.handleDrawMouse(this.mainSlots[1].drawCtx, this.mainSlots[1].annotateCtx, this.viewerViewModel.displayedPageIndices[1] ?? 0, event),
            linkHitAreas: this.linkController.getLinkHitAreasForSlot(1),
            linkOverlayEnabled: this.linkController.isLinkOverlayEnabled(),
            linkVisualOpacity: this.linkController.pdfLinkVisualOpacity,
            onLinkPressStart: (hitArea: PDFLinkDisplayHitArea) => this.linkController.handlePdfLinkPressStart(hitArea),
            onLinkPressCancel: (hitArea: PDFLinkDisplayHitArea) => this.linkController.handlePdfLinkPressCancel(hitArea),
            onLinkActivated: (hitArea: PDFLinkDisplayHitArea) => this.linkController.activatePdfLink(hitArea)
          })

          PDFPageSlot({
            pixelMap: this.mainSlots[2].pixelMap,
            loading: this.mainSlots[2].loading,
            viewSize: this.mainSlots[2].viewSize,
            canvasSize: this.getCanvasSize(this.viewerViewModel.displayedPageIndices[2] ?? 0),
            canvasScale: this.getCanvasScale(2),
            visible: this.viewerViewModel.shouldShowThirdSlot() &&
              this.viewerViewModel.displayedPageIndices.length >= 3,
            occupyLayoutWhenHidden: this.viewerViewModel.shouldShowThirdSlot(),
            drawCanvasVisible: this.viewerViewModel.annotateMode !== 'drag' && !this.isDocumentReadOnly(),
            annotateCtx: this.mainSlots[2].annotateCtx,
            drawCtx: this.mainSlots[2].drawCtx,
            onDrawTouch: (event: TouchEvent) => this.handleDrawTouch(this.mainSlots[2].drawCtx, this.mainSlots[2].annotateCtx, this.viewerViewModel.displayedPageIndices[2] ?? 0, event),
            onDrawMouse: (event: MouseEvent) => this.handleDrawMouse(this.mainSlots[2].drawCtx, this.mainSlots[2].annotateCtx, this.viewerViewModel.displayedPageIndices[2] ?? 0, event),
            linkHitAreas: this.linkController.getLinkHitAreasForSlot(2),
            linkOverlayEnabled: this.linkController.isLinkOverlayEnabled(),
            linkVisualOpacity: this.linkController.pdfLinkVisualOpacity,
            onLinkPressStart: (hitArea: PDFLinkDisplayHitArea) => this.linkController.handlePdfLinkPressStart(hitArea),
            onLinkPressCancel: (hitArea: PDFLinkDisplayHitArea) => this.linkController.handlePdfLinkPressCancel(hitArea),
            onLinkActivated: (hitArea: PDFLinkDisplayHitArea) => this.linkController.activatePdfLink(hitArea)
          })
        }
        .alignItems(VerticalAlign.Top)
        .clip(false)
        .alignRules(TopLeft)
        .offset(this.viewerViewModel.viewPan)
        .size(toSizePx(this.getStripLayoutSizePx()))
        .scale({
          x: this.viewerViewModel.viewScale,
          y: this.viewerViewModel.viewScale,
          centerX: 0,
          centerY: 0
        })
        .translate({ x: this.pageTurnController.pageTurnOffsetVp, y: 0 })
        .opacity(this.pageTurnController.getSlideCurrentStripOpacity())

        // 左侧预览条叠在主文档层之上，否则主条全宽时会挡住左侧邻条的可视区域。
        if (this.pageTurnController.transPrevIndices.length > 0) {
          Row(ContainerCfg) {
            PDFPageSlot({
              pixelMap: this.pageTurnController.transPrevSlots[0].pixelMap,
              loading: this.pageTurnController.transPrevSlots[0].loading,
              viewSize: this.pageTurnController.transPrevSlots[0].viewSize,
              canvasSize: this.getCanvasSize(this.getTransitionPageIndex('prev', 0)),
              canvasScale: this.getTransitionCanvasScale('prev', 0),
              visible: this.transitionSlotVisible('prev', 0),
              drawCanvasVisible: false,
              annotateCtx: this.pageTurnController.transPreviewAnnotateCtx,
              drawCtx: this.pageTurnController.transPreviewDrawCtx,
              onDrawTouch: (_e: TouchEvent) => {
              },
              onDrawMouse: (_e: MouseEvent) => {
              }
            })
            PDFPageSlot({
              pixelMap: this.pageTurnController.transPrevSlots[1].pixelMap,
              loading: this.pageTurnController.transPrevSlots[1].loading,
              viewSize: this.pageTurnController.transPrevSlots[1].viewSize,
              canvasSize: this.getCanvasSize(this.getTransitionPageIndex('prev', 1)),
              canvasScale: this.getTransitionCanvasScale('prev', 1),
              visible: this.transitionSlotVisible('prev', 1),
              drawCanvasVisible: false,
              annotateCtx: this.pageTurnController.transPreviewAnnotateCtx,
              drawCtx: this.pageTurnController.transPreviewDrawCtx,
              onDrawTouch: (_e: TouchEvent) => {
              },
              onDrawMouse: (_e: MouseEvent) => {
              }
            })
            PDFPageSlot({
              pixelMap: this.pageTurnController.transPrevSlots[2].pixelMap,
              loading: this.pageTurnController.transPrevSlots[2].loading,
              viewSize: this.pageTurnController.transPrevSlots[2].viewSize,
              canvasSize: this.getCanvasSize(this.getTransitionPageIndex('prev', 2)),
              canvasScale: this.getTransitionCanvasScale('prev', 2),
              visible: this.transitionSlotVisible('prev', 2),
              drawCanvasVisible: false,
              annotateCtx: this.pageTurnController.transPreviewAnnotateCtx,
              drawCtx: this.pageTurnController.transPreviewDrawCtx,
              onDrawTouch: (_e: TouchEvent) => {
              },
              onDrawMouse: (_e: MouseEvent) => {
              }
            })
          }
          .alignItems(VerticalAlign.Top)
          .clip(false)
          .alignRules(TopLeft)
          .offset(this.viewerViewModel.viewPan)
          .size(toSizePx(this.pageTurnController.getTransitionStripSizePx('prev')))
          .scale({
            x: this.viewerViewModel.viewScale,
            y: this.viewerViewModel.viewScale,
            centerX: 0,
            centerY: 0
          })
          .translate({ x: this.pageTurnController.getPreviewStripTranslateVp('prev'), y: 0 })
          .opacity(this.pageTurnController.getSlidePrevStripOpacity())
          .hitTestBehavior(HitTestMode.None)
        }

        if (this.pageTurnController.transNextIndices.length > 0) {
          Row(ContainerCfg) {
            PDFPageSlot({
              pixelMap: this.pageTurnController.transNextSlots[0].pixelMap,
              loading: this.pageTurnController.transNextSlots[0].loading,
              viewSize: this.pageTurnController.transNextSlots[0].viewSize,
              canvasSize: this.getCanvasSize(this.getTransitionPageIndex('next', 0)),
              canvasScale: this.getTransitionCanvasScale('next', 0),
              visible: this.transitionSlotVisible('next', 0),
              drawCanvasVisible: false,
              annotateCtx: this.pageTurnController.transPreviewAnnotateCtx,
              drawCtx: this.pageTurnController.transPreviewDrawCtx,
              onDrawTouch: (_e: TouchEvent) => {
              },
              onDrawMouse: (_e: MouseEvent) => {
              }
            })
            PDFPageSlot({
              pixelMap: this.pageTurnController.transNextSlots[1].pixelMap,
              loading: this.pageTurnController.transNextSlots[1].loading,
              viewSize: this.pageTurnController.transNextSlots[1].viewSize,
              canvasSize: this.getCanvasSize(this.getTransitionPageIndex('next', 1)),
              canvasScale: this.getTransitionCanvasScale('next', 1),
              visible: this.transitionSlotVisible('next', 1),
              drawCanvasVisible: false,
              annotateCtx: this.pageTurnController.transPreviewAnnotateCtx,
              drawCtx: this.pageTurnController.transPreviewDrawCtx,
              onDrawTouch: (_e: TouchEvent) => {
              },
              onDrawMouse: (_e: MouseEvent) => {
              }
            })
            PDFPageSlot({
              pixelMap: this.pageTurnController.transNextSlots[2].pixelMap,
              loading: this.pageTurnController.transNextSlots[2].loading,
              viewSize: this.pageTurnController.transNextSlots[2].viewSize,
              canvasSize: this.getCanvasSize(this.getTransitionPageIndex('next', 2)),
              canvasScale: this.getTransitionCanvasScale('next', 2),
              visible: this.transitionSlotVisible('next', 2),
              drawCanvasVisible: false,
              annotateCtx: this.pageTurnController.transPreviewAnnotateCtx,
              drawCtx: this.pageTurnController.transPreviewDrawCtx,
              onDrawTouch: (_e: TouchEvent) => {
              },
              onDrawMouse: (_e: MouseEvent) => {
              }
            })
          }
          .alignItems(VerticalAlign.Top)
          .clip(false)
          .alignRules(TopLeft)
          .offset(this.viewerViewModel.viewPan)
          .size(toSizePx(this.pageTurnController.getTransitionStripSizePx('next')))
          .scale({
            x: this.viewerViewModel.viewScale,
            y: this.viewerViewModel.viewScale,
            centerX: 0,
            centerY: 0
          })
          .translate({ x: this.pageTurnController.getPreviewStripTranslateVp('next'), y: 0 })
          .opacity(this.pageTurnController.getSlideNextStripOpacity())
          .hitTestBehavior(HitTestMode.None)
        }

        Flex()
          .size({ width: '100%', height: '100%' })
          .onAreaChange((_, newVal) => {
            this.updateMetronomeViewportFromArea(newVal);
            this.updateTunerViewportFromArea(newVal);
            this.updateBookmarkViewportFromArea(newVal);
            this.syncPanelOverlays();
            this.viewerViewModel.setViewportSize(fromArea(newVal, this.getUIContext()));
            if (!this.pageTurnController.shouldDeferViewportFitReset()) {
              this.resetViewToFit();
            }
          })
          .hitTestBehavior(HitTestMode.Transparent)
          .onTouch(event => this.handleViewAction(event))
          .onMouse(event => this.handleMouseEvent(event))
          .onAxisEvent(event => this.handleMouseAxisEvent(event))

        Column() {
          Button(PageFlipButtonOption)
            .width('100%')
            .height('100%')
            .onClick(() => this.navigatePrevPageFromSideFlipZone())
            .backgroundColor(Color.Transparent)
            .hitTestBehavior(HitTestMode.Transparent)
        }
        .size(PageFlipButtonSize)
        .padding({
          top: this.getSafeTopVp(),
          bottom: this.getSafeBottomVp(),
          left: this.getSafeLeftVp()
        })
        .alignRules(TopLeft)
        .hitTestBehavior(HitTestMode.Transparent)
        .visibility(toVisibility(this.viewerViewModel.pageFlipMode == 'side' && this.viewerViewModel.annotateMode == 'drag'))

        Column() {
          Button(PageFlipButtonOption)
            .width('100%')
            .height('100%')
            .onClick(() => this.navigateNextPageFromSideFlipZone())
            .backgroundColor(Color.Transparent)
            .hitTestBehavior(HitTestMode.Transparent)
        }
        .size(PageFlipButtonSize)
        .padding({
          top: this.getSafeTopVp(),
          bottom: this.getSafeBottomVp(),
          right: this.getSafeRightVp()
        })
        .alignRules(TopRight)
        .hitTestBehavior(HitTestMode.Transparent)
        .visibility(toVisibility(this.viewerViewModel.pageFlipMode == 'side' && this.viewerViewModel.annotateMode == 'drag'))

        Image('')
          .size(PageFlipButtonSize)
          .alignRules(TopLeft)
          .visibility(toVisibility(this.viewerViewModel.pageFlipMode == 'side' && this.viewerViewModel.annotateMode == 'drag'))
          .hitTestBehavior(HitTestMode.None)
          .opacity(this.pageFlipShadeOpacity)
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
          .visibility(toVisibility(this.viewerViewModel.pageFlipMode == 'side' && this.viewerViewModel.annotateMode == 'drag'))
          .hitTestBehavior(HitTestMode.None)
          .opacity(this.pageFlipShadeOpacity)
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
                value: this.viewerViewModel.currentPageIndex,
                min: 0,
                max: this.viewerViewModel.totalPageCount - 1,
                onChangeCallback: (newValue: number, mode: SliderChangeMode) => this.handlePageSliderChange(newValue, mode)
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
                isExclusiveFullScreen: this.isExclusiveFullScreen,
                showFullscreenButton: this.isInFreeWindowMode,
                pageDisplayModeText: this.viewerViewModel.getPageDisplayModeText(),
                pageFlipModeText: this.viewerViewModel.getPageFlipModeText(),
                shareButtonId: ShareButtonId,
                displayModeMenu: this.viewerViewModel.buildPageDisplayModeMenu(() => {
                  this.gotoPage(this.viewerViewModel.currentPageIndex);
                }),
                flipModeMenu: this.viewerViewModel.buildPageFlipModeMenu(),
                jumpMenu: this.viewerViewModel.buildJumpMenu(() => {
                  this.resetViewToFit();
                }, (pageIndex: number) => {
                  this.gotoPage(pageIndex);
                }),
                onTutorial: () => {
                  this.tutorialDialogController.open();
                },
                onSettings: () => {
                  this.rebuildSettingsDialogController();
                  this.settingsDialogController.open();
                },
                onToggleFullscreen: () => {
                  this.isExclusiveFullScreen = !this.isExclusiveFullScreen;
                  if (this.isExclusiveFullScreen) {
                    this.mainWindow.maximize(window.MaximizePresentation.ENTER_IMMERSIVE).catch();
                  } else {
                    this.mainWindow.recover().catch();
                  }
                },
                onShare: () => {
                  this.executeShare();
                },
                onToggleMetronome: () => {
                  this.focusPanel('metronome');
                  this.metronomeController.toggleWindow();
                  this.syncPanelOverlays();
                },
                onToggleTuner: () => {
                  this.focusPanel('tuner');
                  this.setTunerPanelVisible(!this.showTunerPanel);
                  this.syncPanelOverlays();
                },
                onAnnotate: () => {
                  this.enterAnnotateMode();
                },
                onBookmarks: () => {
                  this.toggleBookmarkPanel();
                },
                showBookmarkShortcut: this.bookmarkController.hasBookmarks,
                hasUnsavedBookmarks: this.bookmarkController.isDirty,
                hasUnsavedDocument: this.bookmarkController.isDirty
                  || this.annotationController.hasUnsavedStrokes,
                hasUnsavedAnnotations: this.annotationController.hasUnsavedStrokes,
                onToggleBookmark: () => this.toggleBookmarkPanel(),
                onSaveAnnotation: () => this.executeSaveDocument(),
                showLinkJumpHistory: this.linkController.showLinkJumpHistory,
                canGoLinkJumpBack: this.linkController.linkJumpCanGoBack,
                canGoLinkJumpForward: this.linkController.linkJumpCanGoForward,
                onLinkJumpBack: () => this.linkController.navigatePdfLinkBack(),
                onLinkJumpForward: () => this.linkController.navigatePdfLinkForward(),
                linkJumpNavRevision: this.linkController.linkJumpNavRevision,
                onGoHome: () => this.requestGoHome()
              })

              Blank()

              PDFViewerBottomBar({
                showControls: this.viewerViewModel.showControls,
                pageFlipMode: this.viewerViewModel.pageFlipMode,
                annotateMode: this.viewerViewModel.annotateMode,
                currentPageIndex: this.viewerViewModel.currentPageIndex,
                totalPageCount: this.viewerViewModel.totalPageCount,
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

        this.TopRightStatusIndicatorOverlay()
      }

      if (this.documentSession.isDocumentLoading) {
        Stack({ alignContent: Alignment.Center }) {
          Column() {
            LoadingProgress()
              .width(64)
              .height(64)
              .color(ViewerPageLoadingIndicatorColor)
            Text(`正在加载 ${this.fileName}`)
              .fontSize(16)
              .fontColor(ViewerPageLoadingTextColor)
              .margin({ top: 12 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)

          if (this.documentSession.showPasswordGate) {
            this.PasswordGateOverlay()
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(ViewerPageBackdropColor)
      }

      if (this.documentSession.loadError != '') {
        Column() {
          Column({ space: 20 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
              .fontSize(48)
              .fontColor([ModalErrorTextColor])
            Text('加载失败')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(ModalTitleTextColor)
            Text(this.documentSession.loadError)
              .fontSize(14)
              .fontColor(ModalBodyTextColor)
              .textAlign(TextAlign.Center)
              .width('100%')
            Button('返回')
              .type(ButtonType.Capsule)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(ModalTitleTextColor)
              .backgroundColor(ModalButtonPrimaryColor)
              .width(140)
              .height(40)
              .margin({ top: 4 })
              .onClick(() => this.requestLeaveViewer())
          }
          .width('80%')
          .constraintSize({ maxWidth: 400, minWidth: 280 })
          .padding(32)
          .borderRadius(18)
          .backgroundColor(ModalCardBackgroundColor)
          .border({ width: 1, color: ModalCardBorderColor })
          .shadow(ModalCardShadow)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 24, right: 24 })
        .backgroundColor(ViewerPageBackdropColor)
      }

      AnnotateLongPressIndicator({
        progress: this.longPressProgress,
        posX: this.longPressPosX,
        posY: this.longPressPosY,
        visible: this.longPressVisible
      })

      this.buildDockedPanels()
    }
    .hitTestBehavior(HitTestMode.Transparent)
    .size({ width: '100%', height: '100%' })
    .backgroundColor(ViewerPageBackdropColor)
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
