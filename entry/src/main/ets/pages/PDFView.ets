import { ContainerCfg, ContainerPadding, ContainerSpacing, FullRect, MakeSlider, StyleIconButton, TopLeft, TopRight, toResultCode, toVisibility } from '../components/UIComponents';
import { ComponentContent, LengthMetricsUnit, OverlayManager, window } from '@kit.ArkUI';
import { pdfService } from '@kit.PDFKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
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
import { PDFTunerController } from './pdfview/PDFTunerController';
import { PDFPageSlot } from './pdfview/PDFPageSlot';
import {
  FloatingMetronomeDefaultScale,
  getFloatingMetronomeTotalWidth,
  PDFMetronomePanelContent
} from './pdfview/PDFMetronomePanel';
import {
  FloatingTunerDefaultScale,
  getFloatingTunerTotalWidth,
  PDFTunerPanelContent
} from './pdfview/PDFTunerPanel';
import { PDFViewerActionMenu } from './pdfview/PDFViewerActionMenu';
import { PDFViewerBottomBar } from './pdfview/PDFViewerBottomBar';
import { PDFAnnotateMode, PDFPageFlipMode, PDFViewerViewModel, ViewerMinRenderScale } from './pdfview/PDFViewerViewModel';
import { AnnotateLongPressIndicator } from './pdfview/AnnotateLongPressIndicator';
import { AnnotationPaletteContentHeight, AnnotationPaletteContentWidth, PDFAnnotationPalette } from './pdfview/PDFAnnotationPalette';
import { AnnotationColor } from './pdfview/PDFAnnotationColors';

// 双指手势结束后忽略绘制/擦除触摸的延迟（毫秒）
const DUAL_FINGER_END_PROTECTION_DELAY: number = 300;
const LONG_PRESS_DELAY_MS: number = 100;
const LONG_PRESS_DURATION_MS: number = 500;
const LONG_PRESS_MOVE_THRESHOLD: number = 10;
const LONG_PRESS_TICK_INTERVAL: number = 16;
// 屏侧翻页：平移超过该阈值（像素，与触摸坐标一致）则视为拖动手势，忽略随后触发的翻页按钮点击
const PAGE_FLIP_SUPPRESS_MOVE_PX: number = 12;
// 横向滑动翻页：主导轴判定；慢拖需要更大比例位移才提交，快拖/甩动阈值更低；甩动最低进度门槛
const PAGE_TURN_DOMINANT_RATIO: number = 0.55;
const PAGE_TURN_COMMIT_RATIO_SLOW: number = 0.22;
const PAGE_TURN_COMMIT_RATIO_FAST: number = 0.065;
const PAGE_TURN_FLICK_VP_PER_MS: number = 0.42;
const PAGE_TURN_FLICK_MIN_PROGRESS: number = 0.038;
const PAGE_TURN_ELASTIC_EXTRA_RATIO: number = 0.38;
/** 手指位移换算为翻页偏移的增益，略大于 1 可减少「拖很远才够翻页」的感觉 */
const PAGE_TURN_DRAG_GAIN: number = 1.55;
/** 横向滑动：邻条取消 / defer 收尾淡出时长（毫秒），宜短以减轻连滑时的节奏感与「浮层」感 */
const SLIDE_NEIGHBOR_FADE_OUT_MS: number = 160;

const PageFlipButtonOption: ButtonOptions = { type: ButtonType.Normal }
const PageFlipButtonSize: SizeOptions = { width: '30%', height: '100%' }
const CanvasOverSampling: number = 3;
const ShareButtonId: string = 'shareButton';
const UnifiedDockTabBarHeightVp: number = 56;
const FloatingPanelMarginVp: number = 16;
const FloatingMetronomeContentWidthVp: number = 400;
const FloatingTunerContentWidthVp: number = 360;
const DefaultTunerOffsetX: number = 24;
const DefaultTunerOffsetY: number = 112;
const DefaultPaletteScale: number = 1.0;
const PaletteMinScale: number = 0.5;
const PaletteMaxScale: number = 1.5;

type OverlayPanelKey = 'metronome' | 'tuner';
interface FloatingPanelOffset {
  x: number;
  y: number;
}

interface MetronomeOverlayOptions {
  controller: PDFMetronomeController | undefined;
  showWindow: boolean;
  useDocked: boolean;
  dockedTopOffsetVp: number;
  hostScale: number;
  hostOffset: FloatingPanelOffset;
  /** 状态栏避让（vp），仅用于播放中迷你浮动按钮顶边距 */
  overlaySafeTopVp: number;
  onInteraction: () => void;
  onTouchStateChanged: (active: boolean) => void;
  onHostDragStart: () => void;
  onHostDragUpdate: (event: GestureEvent) => void;
  onHostDragEnd: () => void;
  onHostPinchStart: () => void;
  onHostPinchUpdate: (event: GestureEvent) => void;
  onHostPinchEnd: () => void;
  onWindowAreaHeightChanged: (heightVp: number) => void;
  onClose: () => void;
  onOpenWindow: () => void;
}

interface TunerOverlayOptions {
  controller: PDFTunerController | undefined;
  showWindow: boolean;
  useDocked: boolean;
  dockedTopOffsetVp: number;
  hostScale: number;
  hostOffset: FloatingPanelOffset;
  onInteraction: () => void;
  onTouchStateChanged: (active: boolean) => void;
  onHostDragStart: () => void;
  onHostDragUpdate: (event: GestureEvent) => void;
  onHostDragEnd: () => void;
  onHostPinchStart: () => void;
  onHostPinchUpdate: (event: GestureEvent) => void;
  onHostPinchEnd: () => void;
  onWindowAreaHeightChanged: (heightVp: number) => void;
  onClose: () => void;
}

class MetronomeOverlayParams {
  controller: PDFMetronomeController | undefined;
  showWindow: boolean;
  useDocked: boolean;
  dockedTopOffsetVp: number;
  hostScale: number;
  hostOffset: FloatingPanelOffset;
  overlaySafeTopVp: number;
  onInteraction: () => void;
  onTouchStateChanged: (active: boolean) => void;
  onHostDragStart: () => void;
  onHostDragUpdate: (event: GestureEvent) => void;
  onHostDragEnd: () => void;
  onHostPinchStart: () => void;
  onHostPinchUpdate: (event: GestureEvent) => void;
  onHostPinchEnd: () => void;
  onWindowAreaHeightChanged: (heightVp: number) => void;
  onClose: () => void;
  onOpenWindow: () => void;

  constructor(options: MetronomeOverlayOptions) {
    this.controller = options.controller;
    this.showWindow = options.showWindow;
    this.useDocked = options.useDocked;
    this.dockedTopOffsetVp = options.dockedTopOffsetVp;
    this.hostScale = options.hostScale;
    this.hostOffset = options.hostOffset;
    this.overlaySafeTopVp = options.overlaySafeTopVp;
    this.onInteraction = options.onInteraction;
    this.onTouchStateChanged = options.onTouchStateChanged;
    this.onHostDragStart = options.onHostDragStart;
    this.onHostDragUpdate = options.onHostDragUpdate;
    this.onHostDragEnd = options.onHostDragEnd;
    this.onHostPinchStart = options.onHostPinchStart;
    this.onHostPinchUpdate = options.onHostPinchUpdate;
    this.onHostPinchEnd = options.onHostPinchEnd;
    this.onWindowAreaHeightChanged = options.onWindowAreaHeightChanged;
    this.onClose = options.onClose;
    this.onOpenWindow = options.onOpenWindow;
  }
}

class TunerOverlayParams {
  controller: PDFTunerController | undefined;
  showWindow: boolean;
  useDocked: boolean;
  dockedTopOffsetVp: number;
  hostScale: number;
  hostOffset: FloatingPanelOffset;
  onInteraction: () => void;
  onTouchStateChanged: (active: boolean) => void;
  onHostDragStart: () => void;
  onHostDragUpdate: (event: GestureEvent) => void;
  onHostDragEnd: () => void;
  onHostPinchStart: () => void;
  onHostPinchUpdate: (event: GestureEvent) => void;
  onHostPinchEnd: () => void;
  onWindowAreaHeightChanged: (heightVp: number) => void;
  onClose: () => void;

  constructor(options: TunerOverlayOptions) {
    this.controller = options.controller;
    this.showWindow = options.showWindow;
    this.useDocked = options.useDocked;
    this.dockedTopOffsetVp = options.dockedTopOffsetVp;
    this.hostScale = options.hostScale;
    this.hostOffset = options.hostOffset;
    this.onInteraction = options.onInteraction;
    this.onTouchStateChanged = options.onTouchStateChanged;
    this.onHostDragStart = options.onHostDragStart;
    this.onHostDragUpdate = options.onHostDragUpdate;
    this.onHostDragEnd = options.onHostDragEnd;
    this.onHostPinchStart = options.onHostPinchStart;
    this.onHostPinchUpdate = options.onHostPinchUpdate;
    this.onHostPinchEnd = options.onHostPinchEnd;
    this.onWindowAreaHeightChanged = options.onWindowAreaHeightChanged;
    this.onClose = options.onClose;
  }
}

@Builder
function BuildMetronomeOverlay(params: MetronomeOverlayParams) {
  Stack() {
    PDFMetronomePanelContent({
      controller: params.controller,
      useDocked: params.useDocked,
      dockedTopOffsetVp: params.dockedTopOffsetVp,
      hostScale: params.hostScale,
      hostOffset: params.hostOffset,
      showDragHandle: !params.useDocked,
      onInteraction: params.onInteraction,
      onTouchStateChanged: params.onTouchStateChanged,
      onWindowAreaHeightChanged: params.onWindowAreaHeightChanged,
      onHostDragStart: params.onHostDragStart,
      onHostDragUpdate: params.onHostDragUpdate,
      onHostDragEnd: params.onHostDragEnd,
      onHostPinchStart: params.onHostPinchStart,
      onHostPinchUpdate: params.onHostPinchUpdate,
      onHostPinchEnd: params.onHostPinchEnd,
      onClose: params.onClose
    })
      .visibility(toVisibility(params.showWindow && !params.useDocked))

    Column() {
      StyleIconButton({
        icon: $r('sys.symbol.clock'),
        alternateColor: (!(params.controller?.isPlaying ?? false) || (params.controller?.currentBeat ?? -1) < 0)
          ? 'rgba(35, 42, 53, 0.62)'
          : (params.controller?.floatingButtonColor ?? 'rgba(35, 42, 53, 0.62)'),
        backgroundAnimationDurationMs: params.controller?.floatingButtonTransitionDurationMs ?? 0,
        onTouchDownCallback: () => params.onInteraction(),
        onClickCallback: () => {
          params.onOpenWindow();
        }
      })
        .visibility(toVisibility(!params.showWindow && (params.controller?.isPlaying ?? false)))
        .scale({
          x: (!(params.controller?.isPlaying ?? false) || (params.controller?.currentBeat ?? -1) < 0)
            ? 1
            : (params.controller?.floatingButtonPulseScale ?? 1),
          y: (!(params.controller?.isPlaying ?? false) || (params.controller?.currentBeat ?? -1) < 0)
            ? 1
            : (params.controller?.floatingButtonPulseScale ?? 1),
          centerX: 22,
          centerY: 22
        })
        .animation({ duration: params.controller?.floatingButtonTransitionDurationMs ?? 0, curve: Curve.EaseOut })
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.92, y: 0.92 })))
        .margin(ContainerPadding)
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ top: params.overlaySafeTopVp })
  }
  .width('100%')
  .height('100%')
  .alignContent(Alignment.TopStart)
  .hitTestBehavior(HitTestMode.Transparent)
}

@Builder
function BuildTunerOverlay(params: TunerOverlayParams) {
  Stack() {
    if (params.showWindow && !params.useDocked) {
      PDFTunerPanelContent({
        controller: params.controller,
        useDocked: params.useDocked,
        dockedTopOffsetVp: params.dockedTopOffsetVp,
        hostScale: params.hostScale,
        hostOffset: params.hostOffset,
        showDragHandle: !params.useDocked,
        onInteraction: params.onInteraction,
        onTouchStateChanged: params.onTouchStateChanged,
        onWindowAreaHeightChanged: params.onWindowAreaHeightChanged,
        onHostDragStart: params.onHostDragStart,
        onHostDragUpdate: params.onHostDragUpdate,
        onHostDragEnd: params.onHostDragEnd,
        onHostPinchStart: params.onHostPinchStart,
        onHostPinchUpdate: params.onHostPinchUpdate,
        onHostPinchEnd: params.onHostPinchEnd,
        onClose: params.onClose
      })
    }
  }
  .width('100%')
  .height('100%')
  .alignContent(Alignment.TopStart)
  .hitTestBehavior(HitTestMode.Transparent)
}

interface AnnotationPaletteOverlayOptions {
  showWindow: boolean;
  annotateMode: PDFAnnotateMode;
  undoCount: number;
  redoCount: number;
  hasUnsaved: boolean;
  hostScale: number;
  hostOffset: FloatingPanelOffset;
  drawColor: AnnotationColor;
  customDrawColor: AnnotationColor;
  recentCustomColors: AnnotationColor[];
  onSetMode: (mode: PDFAnnotateMode) => void;
  onSelectDrawColor: (color: AnnotationColor) => void;
  onSetCustomDrawColor: (color: AnnotationColor) => void;
  onCommitRecentCustomColor: (color: AnnotationColor) => void;
  onUndo: () => void;
  onRedo: () => void;
  onSave: () => void;
  onClose: () => void;
  onTouchStateChanged: (active: boolean) => void;
  onHostDragStart: () => void;
  onHostDragUpdate: (event: GestureEvent) => void;
  onHostDragEnd: () => void;
  onHostPinchStart: () => void;
  onHostPinchUpdate: (event: GestureEvent) => void;
  onHostPinchEnd: () => void;
}

class AnnotationPaletteOverlayParams {
  showWindow: boolean;
  annotateMode: PDFAnnotateMode;
  undoCount: number;
  redoCount: number;
  hasUnsaved: boolean;
  hostScale: number;
  hostOffset: FloatingPanelOffset;
  drawColor: AnnotationColor;
  customDrawColor: AnnotationColor;
  recentCustomColors: AnnotationColor[];
  onSetMode: (mode: PDFAnnotateMode) => void;
  onSelectDrawColor: (color: AnnotationColor) => void;
  onSetCustomDrawColor: (color: AnnotationColor) => void;
  onCommitRecentCustomColor: (color: AnnotationColor) => void;
  onUndo: () => void;
  onRedo: () => void;
  onSave: () => void;
  onClose: () => void;
  onTouchStateChanged: (active: boolean) => void;
  onHostDragStart: () => void;
  onHostDragUpdate: (event: GestureEvent) => void;
  onHostDragEnd: () => void;
  onHostPinchStart: () => void;
  onHostPinchUpdate: (event: GestureEvent) => void;
  onHostPinchEnd: () => void;

  constructor(options: AnnotationPaletteOverlayOptions) {
    this.showWindow = options.showWindow;
    this.annotateMode = options.annotateMode;
    this.undoCount = options.undoCount;
    this.redoCount = options.redoCount;
    this.hasUnsaved = options.hasUnsaved;
    this.hostScale = options.hostScale;
    this.hostOffset = options.hostOffset;
    this.drawColor = options.drawColor;
    this.customDrawColor = options.customDrawColor;
    this.recentCustomColors = options.recentCustomColors;
    this.onSetMode = options.onSetMode;
    this.onSelectDrawColor = options.onSelectDrawColor;
    this.onSetCustomDrawColor = options.onSetCustomDrawColor;
    this.onCommitRecentCustomColor = options.onCommitRecentCustomColor;
    this.onUndo = options.onUndo;
    this.onRedo = options.onRedo;
    this.onSave = options.onSave;
    this.onClose = options.onClose;
    this.onTouchStateChanged = options.onTouchStateChanged;
    this.onHostDragStart = options.onHostDragStart;
    this.onHostDragUpdate = options.onHostDragUpdate;
    this.onHostDragEnd = options.onHostDragEnd;
    this.onHostPinchStart = options.onHostPinchStart;
    this.onHostPinchUpdate = options.onHostPinchUpdate;
    this.onHostPinchEnd = options.onHostPinchEnd;
  }
}

@Builder
function BuildAnnotationPaletteOverlay(params: AnnotationPaletteOverlayParams) {
  Stack() {
    if (params.showWindow) {
      PDFAnnotationPalette({
        annotateMode: params.annotateMode,
        undoCount: params.undoCount,
        redoCount: params.redoCount,
        hasUnsaved: params.hasUnsaved,
        hostScale: params.hostScale,
        hostOffset: params.hostOffset,
        drawColor: params.drawColor,
        customDrawColor: params.customDrawColor,
        recentCustomColors: params.recentCustomColors,
        onSetMode: params.onSetMode,
        onSelectDrawColor: params.onSelectDrawColor,
        onSetCustomDrawColor: params.onSetCustomDrawColor,
        onCommitRecentCustomColor: params.onCommitRecentCustomColor,
        onUndo: params.onUndo,
        onRedo: params.onRedo,
        onSave: params.onSave,
        onClose: params.onClose,
        onTouchStateChanged: params.onTouchStateChanged,
        onHostDragStart: params.onHostDragStart,
        onHostDragUpdate: params.onHostDragUpdate,
        onHostDragEnd: params.onHostDragEnd,
        onHostPinchStart: params.onHostPinchStart,
        onHostPinchUpdate: params.onHostPinchUpdate,
        onHostPinchEnd: params.onHostPinchEnd
      })
    }
  }
  .width('100%')
  .height('100%')
  .alignContent(Alignment.TopStart)
  .hitTestBehavior(HitTestMode.Transparent)
}

@Entry
@ComponentV2
struct PDFView {
  systemPath = '';
  sandBoxPath = '';
  saveTempPath = '';
  fileName = '';
  mainWindow: window.Window = (AppStorage.get('window') as window.Window);
  document = new pdfService.PdfDocument();
  pageDataSource: PageStore = new PageStore();
  preferences: preferences.Preferences = AppStorage.get('preferences') as preferences.Preferences;
  @Local viewerViewModel: PDFViewerViewModel = new PDFViewerViewModel();
  currentRenderScale: number = ViewerMinRenderScale;
  @Local view1PixelMap: PixelMap | undefined = undefined;
  @Local view2PixelMap: PixelMap | undefined = undefined;
  @Local view3PixelMap: PixelMap | undefined = undefined;
  @Local view1Loading: boolean = false;
  @Local view2Loading: boolean = false;
  @Local view3Loading: boolean = false;
  @Local view1ViewSize: Vector2 = Vec2(0, 0);
  @Local view2ViewSize: Vector2 = Vec2(0, 0);
  @Local view3ViewSize: Vector2 = Vec2(0, 0);
  @Local isDocumentLoading: boolean = true;
  @Local loadError: string = '';
  transparencyTimeoutId: number | undefined = undefined;
  windowStatusCallback: ((statusType: window.WindowStatusType) => void) | undefined = undefined;
  freeWindowModeCallback: ((isInFreeWindowMode: boolean) => void) | undefined = undefined;
  lastTouchPoint: Vector2 | undefined = undefined;
  /** 当前单指拖动手势起点，用于判断屏侧翻页是否应被平移取消 */
  panSessionStartPoint: Vector2 | undefined = undefined;
  /** 在侧栏透明按钮上抬起时，若发生过平移/捏合/滚轮缩放则置为 true，以忽略误触的翻页 */
  suppressSidePageFlipFromGesture: boolean = false;
  /** 横向滑动翻页：vp 偏移（负值表示露出右侧下一套） */
  @Local pageTurnOffsetVp: number = 0;
  /** 提交收尾时临时锁定预览层位置，使主层归零不牵动预览层。 */
  @Local pageTurnPreviewOffsetLocked: boolean = false;
  @Local pageTurnPreviewOffsetVp: number = 0;
  /** 一次滑动会话内使用固定几何量，避免 gotoPage 更新 viewSize 时牵动预览层。 */
  @Local pageTurnMainAdvanceVp: number = 0;
  @Local pageTurnPrevAdvanceVp: number = 0;
  /** 当前手势是否在横向翻页拖动中（松手前不 commitPage） */
  pageTurnDragActive: boolean = false;
  /** -1 下一套，+1 上一套，0 未定向 */
  pageTurnDirection: number = 0;
  /** 横向翻页手势的平滑水平速度（vp/ms），用于动态提交阈值与甩动判定 */
  slideVelocityVpPerMs: number = 0;
  lastSlideSampleTimeMs: number = 0;
  /** 松手后「收尾」动画期间为 true，用于交叉淡化与避免提前拆掉条带 */
  @Local pageTurnCommitAnimating: boolean = false;
  /** 收尾动画：0=当前页不透明 / 目标页透明，1=当前淡出、目标淡入完成（与位移同一 animateTo 插值） */
  @Local pageTurnCrossfadeT: number = 0;
  /** 横向滑动邻条预览：短促出现淡入（非跟手）；取消/提交/重置前须回到 1 以免与 offset 回弹打架 */
  @Local pageTurnNeighborAppearOpacity: number = 1;
  private slideNeighborAppearFadeGen: number = 0;
  /** defer 的 gotoPage 正在 await load；与 slideGotoCompletionToken 配对避免被过期的异步 return 误清 */
  slideGotoInFlight: boolean = false;
  private slideGotoCompletionToken: number = 0;
  /** 提交位移动画与 onFinish 配对；递增即视为用户打断，可立即开始下一次滑动。 */
  private slideCommitAnimGen: number = 0;
  /** 已提交但尚未进入 gotoPage 的目标页（仅提交动画期间有效）。 */
  private pendingSlideGotoTarget: number | undefined = undefined;
  transitionNeighborGen: number = 0;
  @Local transNextIndices: number[] = [];
  @Local transPrevIndices: number[] = [];
  @Local transNext1PixelMap: PixelMap | undefined = undefined;
  @Local transNext2PixelMap: PixelMap | undefined = undefined;
  @Local transNext3PixelMap: PixelMap | undefined = undefined;
  @Local transPrev1PixelMap: PixelMap | undefined = undefined;
  @Local transPrev2PixelMap: PixelMap | undefined = undefined;
  @Local transPrev3PixelMap: PixelMap | undefined = undefined;
  @Local transNext1Loading: boolean = false;
  @Local transNext2Loading: boolean = false;
  @Local transNext3Loading: boolean = false;
  @Local transPrev1Loading: boolean = false;
  @Local transPrev2Loading: boolean = false;
  @Local transPrev3Loading: boolean = false;
  @Local transNext1ViewSize: Vector2 = Vec2(0, 0);
  @Local transNext2ViewSize: Vector2 = Vec2(0, 0);
  @Local transNext3ViewSize: Vector2 = Vec2(0, 0);
  @Local transPrev1ViewSize: Vector2 = Vec2(0, 0);
  @Local transPrev2ViewSize: Vector2 = Vec2(0, 0);
  @Local transPrev3ViewSize: Vector2 = Vec2(0, 0);
  transPreviewAnnotateCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true), LengthMetricsUnit.PX);
  transPreviewDrawCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true), LengthMetricsUnit.PX);
  lastPinchDistance: number | undefined = undefined;
  lastPinchCenter: Vector2 | undefined = undefined;
  lastDualFingerEndTime: number = 0;
  isDualFingerActive: boolean = false;
  lastMousePoint: Vector2 | undefined = undefined;
  /** 拖动模式下鼠标左/右键按下时的位置，用于屏侧翻页与平移的区分 */
  mousePanSessionStart: Vector2 | undefined = undefined;
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
  @Local annotationController: PDFAnnotationController = new PDFAnnotationController({
    pageDataSource: this.pageDataSource,
    viewerViewModel: this.viewerViewModel,
    document: this.document,
    getSystemPath: () => this.systemPath,
    getSandBoxPath: () => this.sandBoxPath,
    getSaveTempPath: () => this.saveTempPath,
    getFileName: () => this.fileName,
    getUIContext: () => this.getUIContext(),
    onRequestGotoPage: (pageIndex: number) => {
      this.gotoPage(pageIndex);
    },
    onRedrawRequested: () => this.redrawStrokes(),
    onRefreshDisplayedPages: () => this.refreshDisplayedPages(),
    getPreferences: () => this.preferences
  }, CanvasOverSampling);
  @Local metronomeController: PDFMetronomeController = new PDFMetronomeController({
    getUIContext: () => this.getUIContext(),
    getHostContext: () => this.getUIContext().getHostContext() as common.UIAbilityContext,
    onVisualStateChanged: () => this.syncPanelOverlays()
  });
  @Local tunerController: PDFTunerController = new PDFTunerController();
  @Local showTunerPanel: boolean = false;
  @Local useDockedMetronomePanel: boolean = false;
  @Local metronomePanelScale: number = FloatingMetronomeDefaultScale;
  @Local metronomePanelOffset: FloatingPanelOffset = { x: 0, y: 0 };
  @Local metronomeViewportWidthVp: number = 0;
  @Local metronomeViewportHeightVp: number = 0;
  @Local metronomePanelHeightVp: number = 0;
  @Local useDockedTunerPanel: boolean = false;
  @Local tunerPanelScale: number = FloatingTunerDefaultScale;
  @Local tunerPanelOffset: FloatingPanelOffset = { x: DefaultTunerOffsetX, y: DefaultTunerOffsetY };
  @Local tunerViewportWidthVp: number = 0;
  @Local tunerViewportHeightVp: number = 0;
  @Local tunerPanelHeightVp: number = 0;
  @Local dockedPanelHeightVp: number = 0;
  @Local activePanel: OverlayPanelKey = 'metronome';
  @Local isPanelGestureActive: boolean = false;
  @Local isExclusiveFullScreen: boolean = false;
  @Local isInFreeWindowMode: boolean = false;
  @Local pageFlipShadeOpacity: number = 0;
  @Local palettePanelScale: number = DefaultPaletteScale;
  @Local palettePanelOffset: FloatingPanelOffset = { x: 0, y: 0 };
  @Local longPressProgress: number = 0;
  @Local longPressPosX: number = 0;
  @Local longPressPosY: number = 0;
  @Local longPressVisible: boolean = false;
  private longPressDelayId: number | undefined = undefined;
  private longPressAnimId: number | undefined = undefined;
  private paletteDragStartOffset: FloatingPanelOffset = { x: 0, y: 0 };
  private palettePinchStartScale: number = DefaultPaletteScale;
  private longPressStartTime: number = 0;
  private longPressTouchDown: boolean = false;
  hotkeys: InputAction[] = [];
  prefetchDebounceId: number | undefined = undefined;
  windowSizeChangeCallback: ((windowSize: window.Size) => void) | undefined = undefined;
  /** 系统栏避让高度（px），与窗口 getWindowAvoidArea 一致，用于根布局 padding */
  @Local avoidAreaTopPx: number = 0;
  @Local avoidAreaBottomPx: number = 0;
  avoidAreaChangeCallback: ((data: window.AvoidAreaOptions) => void) | undefined = undefined;
  private overlayManager: OverlayManager | undefined = undefined;
  private metronomeOverlayContent: ComponentContent<MetronomeOverlayParams> | undefined = undefined;
  private tunerOverlayContent: ComponentContent<TunerOverlayParams> | undefined = undefined;
  private paletteOverlayContent: ComponentContent<AnnotationPaletteOverlayParams> | undefined = undefined;
  private metronomeDragStartOffset: FloatingPanelOffset = { x: 0, y: 0 };
  private tunerDragStartOffset: FloatingPanelOffset = { x: DefaultTunerOffsetX, y: DefaultTunerOffsetY };
  private metronomePinchStartScale: number = FloatingMetronomeDefaultScale;
  private tunerPinchStartScale: number = FloatingTunerDefaultScale;
  private lastWindowWidthPx: number = 0;
  // 每次 gotoPage 调用时递增；用于忽略在页面切换后才完成的过期异步加载回调，
  // 避免快速翻页后显示内容与当前页码不符。
  private pageLoadVersion: number = 0;
  /**
   * 与 loadAndDisplayPages 同步：commit 前 displayedPageIndices 仍为旧套，
   * 高分辨率异步回调须按此列表写入主槽，避免少页视图时空槽被旧页位图盖一帧。
   */
  private mainSlotPagesBeingLoaded: number[] = [];
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
    // 关闭节拍器、调音器、批注画板三个浮层并把关闭状态推到 OverlayManager，
    // 防止离开 PDFView 后这些浮层在窗口级 OverlayManager 中残留显示，
    // 也保证下一次再进入 PDFView 时浮层处于初始（隐藏）状态。
    this.metronomeController.closeWindow();
    this.setTunerPanelVisible(false);
    this.viewerViewModel.closeAnnotatePalette();
    this.syncPanelOverlays();
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

  private updatePanelDocking(windowWidthPx: number): void {
    this.lastWindowWidthPx = windowWidthPx;
    const metronomeTotalWidthPx = this.getUIContext().vp2px(getFloatingMetronomeTotalWidth(this.metronomePanelScale));
    const tunerTotalWidthPx = this.getUIContext().vp2px(getFloatingTunerTotalWidth(this.tunerPanelScale));
    const shouldDockBoth = windowWidthPx <= metronomeTotalWidthPx || windowWidthPx <= tunerTotalWidthPx;
    this.useDockedMetronomePanel = shouldDockBoth;
    this.useDockedTunerPanel = shouldDockBoth;
  }

  private isMetronomeDockedVisible(): boolean {
    return this.useDockedMetronomePanel && this.isMetronomePanelVisible();
  }

  private isTunerDockedVisible(): boolean {
    return this.useDockedTunerPanel && this.isTunerPanelVisible();
  }

  private hasAnyDockedVisiblePanel(): boolean {
    return this.isMetronomeDockedVisible() || this.isTunerDockedVisible();
  }

  private isUnifiedDockedPanelVisible(): boolean {
    return this.isMetronomeDockedVisible() && this.isTunerDockedVisible();
  }

  private getActiveDockedPanel(): OverlayPanelKey {
    if (this.activePanel === 'metronome' && this.isMetronomeDockedVisible()) {
      return 'metronome';
    }
    if (this.activePanel === 'tuner' && this.isTunerDockedVisible()) {
      return 'tuner';
    }
    if (this.isMetronomeDockedVisible()) {
      return 'metronome';
    }
    return 'tuner';
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
    if (this.isUnifiedDockedPanelVisible()) {
      return (this.getActiveDockedPanel() === 'metronome' ? this.metronomePanelHeightVp : this.tunerPanelHeightVp)
        + UnifiedDockTabBarHeightVp;
    }
    if (this.isMetronomeDockedVisible()) {
      return this.metronomePanelHeightVp;
    }
    return this.tunerPanelHeightVp;
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

  private clampMetronomeScale(scale: number): number {
    return Math.max(0.35, Math.min(1.5, scale));
  }

  private clampTunerScale(scale: number): number {
    return Math.max(0.4, Math.min(1.6, scale));
  }

  private getClampedMetronomeOffset(offset: FloatingPanelOffset = this.metronomePanelOffset): FloatingPanelOffset {
    if (this.useDockedMetronomePanel) {
      return { x: 0, y: this.getDockedMetronomeTopOffsetVp() };
    }

    const scaledWidthVp = FloatingMetronomeContentWidthVp * this.metronomePanelScale;
    const scaledHeightVp = this.metronomePanelHeightVp * this.metronomePanelScale;
    const minX = 0;
    const minY = this.getFloatingMetronomeMinYVp();
    const maxX = this.metronomeViewportWidthVp - scaledWidthVp - FloatingPanelMarginVp;
    const maxY = this.metronomeViewportHeightVp - scaledHeightVp - FloatingPanelMarginVp;
    return {
      x: Math.max(minX, Math.min(offset.x, Math.max(minX, maxX))),
      y: Math.max(minY, Math.min(offset.y, Math.max(minY, maxY)))
    };
  }

  private getClampedTunerOffset(offset: FloatingPanelOffset = this.tunerPanelOffset): FloatingPanelOffset {
    if (this.useDockedTunerPanel) {
      return { x: 0, y: this.getDockedTunerTopOffsetVp() };
    }

    const scaledWidthVp = FloatingTunerContentWidthVp * this.tunerPanelScale;
    const scaledHeightVp = this.tunerPanelHeightVp * this.tunerPanelScale;
    const minX = 0;
    const minY = this.getFloatingTunerMinYVp();
    const maxX = this.tunerViewportWidthVp - scaledWidthVp - FloatingPanelMarginVp;
    const maxY = this.tunerViewportHeightVp - scaledHeightVp - FloatingPanelMarginVp;
    return {
      x: Math.max(minX, Math.min(offset.x, Math.max(minX, maxX))),
      y: Math.max(minY, Math.min(offset.y, Math.max(minY, maxY)))
    };
  }

  private syncPanelOffsetsToBounds(): void {
    const nextMetronomeOffset = this.getClampedMetronomeOffset();
    if (Math.abs(nextMetronomeOffset.x - this.metronomePanelOffset.x) >= 0.001
      || Math.abs(nextMetronomeOffset.y - this.metronomePanelOffset.y) >= 0.001) {
      this.metronomePanelOffset = nextMetronomeOffset;
      this.metronomeDragStartOffset = { x: nextMetronomeOffset.x, y: nextMetronomeOffset.y };
    }

    const nextTunerOffset = this.getClampedTunerOffset();
    if (Math.abs(nextTunerOffset.x - this.tunerPanelOffset.x) >= 0.001
      || Math.abs(nextTunerOffset.y - this.tunerPanelOffset.y) >= 0.001) {
      this.tunerPanelOffset = nextTunerOffset;
      this.tunerDragStartOffset = { x: nextTunerOffset.x, y: nextTunerOffset.y };
    }
  }

  private beginPanelGesture(panel: OverlayPanelKey): void {
    this.focusPanel(panel);
    this.isPanelGestureActive = true;
  }

  private endPanelGesture(): void {
    this.isPanelGestureActive = false;
    this.syncPanelOffsetsToBounds();
    this.syncPanelOverlays();
  }

  private handleMetronomeHostDragStart(): void {
    if (this.useDockedMetronomePanel) {
      return;
    }
    this.beginPanelGesture('metronome');
    const clampedOffset = this.getClampedMetronomeOffset();
    this.metronomePanelOffset = clampedOffset;
    this.metronomeDragStartOffset = { x: clampedOffset.x, y: clampedOffset.y };
    this.syncPanelOverlays();
  }

  private handleMetronomeHostDragUpdate(event: GestureEvent): void {
    if (this.useDockedMetronomePanel) {
      return;
    }
    this.metronomePanelOffset = this.getClampedMetronomeOffset({
      x: this.metronomeDragStartOffset.x + event.offsetX * this.metronomePanelScale,
      y: this.metronomeDragStartOffset.y + event.offsetY * this.metronomePanelScale
    });
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
    this.metronomePinchStartScale = this.metronomePanelScale;
  }

  private handleMetronomeHostPinchUpdate(event: GestureEvent): void {
    if (this.useDockedMetronomePanel) {
      return;
    }
    this.metronomePanelScale = this.clampMetronomeScale(this.metronomePinchStartScale * event.scale);
    if (this.lastWindowWidthPx > 0) {
      this.updatePanelDocking(this.lastWindowWidthPx);
    } else {
      this.refreshMetronomeDockingForCurrentWindow();
    }
    this.syncPanelOffsetsToBounds();
    this.syncPanelOverlays();
  }

  private handleMetronomeHostPinchEnd(): void {
    this.metronomePinchStartScale = this.metronomePanelScale;
    this.endPanelGesture();
  }

  private handleTunerHostDragStart(): void {
    if (this.useDockedTunerPanel) {
      return;
    }
    this.beginPanelGesture('tuner');
    const clampedOffset = this.getClampedTunerOffset();
    this.tunerPanelOffset = clampedOffset;
    this.tunerDragStartOffset = { x: clampedOffset.x, y: clampedOffset.y };
    this.syncPanelOverlays();
  }

  private handleTunerHostDragUpdate(event: GestureEvent): void {
    if (this.useDockedTunerPanel) {
      return;
    }
    this.tunerPanelOffset = this.getClampedTunerOffset({
      x: this.tunerDragStartOffset.x + event.offsetX * this.tunerPanelScale,
      y: this.tunerDragStartOffset.y + event.offsetY * this.tunerPanelScale
    });
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
    this.tunerPinchStartScale = this.tunerPanelScale;
  }

  private handleTunerHostPinchUpdate(event: GestureEvent): void {
    if (this.useDockedTunerPanel) {
      return;
    }
    this.tunerPanelScale = this.clampTunerScale(this.tunerPinchStartScale * event.scale);
    if (this.lastWindowWidthPx > 0) {
      this.updatePanelDocking(this.lastWindowWidthPx);
    } else {
      this.refreshTunerDockingForCurrentWindow();
    }
    this.syncPanelOffsetsToBounds();
    this.syncPanelOverlays();
  }

  private handleTunerHostPinchEnd(): void {
    this.tunerPinchStartScale = this.tunerPanelScale;
    this.endPanelGesture();
  }

  private createMetronomeOverlayParams(): MetronomeOverlayParams {
    return new MetronomeOverlayParams({
      controller: this.metronomeController,
      showWindow: this.metronomeController.showWindow ?? false,
      useDocked: this.useDockedMetronomePanel,
      dockedTopOffsetVp: this.getDockedMetronomeTopOffsetVp(),
      hostScale: this.useDockedMetronomePanel ? 1 : this.metronomePanelScale,
      hostOffset: this.getClampedMetronomeOffset(),
      overlaySafeTopVp: this.getUIContext().px2vp(this.avoidAreaTopPx),
      onInteraction: () => this.focusPanel('metronome'),
      onTouchStateChanged: (active: boolean) => {
        this.isPanelGestureActive = active;
      },
      onHostDragStart: () => this.handleMetronomeHostDragStart(),
      onHostDragUpdate: (event: GestureEvent) => this.handleMetronomeHostDragUpdate(event),
      onHostDragEnd: () => this.handleMetronomeHostDragEnd(),
      onHostPinchStart: () => this.handleMetronomeHostPinchStart(),
      onHostPinchUpdate: (event: GestureEvent) => this.handleMetronomeHostPinchUpdate(event),
      onHostPinchEnd: () => this.handleMetronomeHostPinchEnd(),
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
    return new TunerOverlayParams({
      controller: this.tunerController,
      showWindow: this.showTunerPanel,
      useDocked: this.useDockedTunerPanel,
      dockedTopOffsetVp: this.getDockedTunerTopOffsetVp(),
      hostScale: this.useDockedTunerPanel ? 1 : this.tunerPanelScale,
      hostOffset: this.getClampedTunerOffset(),
      onInteraction: () => this.focusPanel('tuner'),
      onTouchStateChanged: (active: boolean) => {
        this.isPanelGestureActive = active;
      },
      onHostDragStart: () => this.handleTunerHostDragStart(),
      onHostDragUpdate: (event: GestureEvent) => this.handleTunerHostDragUpdate(event),
      onHostDragEnd: () => this.handleTunerHostDragEnd(),
      onHostPinchStart: () => this.handleTunerHostPinchStart(),
      onHostPinchUpdate: (event: GestureEvent) => this.handleTunerHostPinchUpdate(event),
      onHostPinchEnd: () => this.handleTunerHostPinchEnd(),
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
      this.syncPanelOverlays();
    } catch (error) {
      hilog.error(0, 'PDFView', `初始化浮层管理器出错: ${error}.`);
    }
  }

  private syncPanelOverlays(): void {
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
          if (this.isUnifiedDockedPanelVisible()) {
            Row({ space: 10 }) {
              this.buildDockedPanelTab('节拍器', 'metronome')
              this.buildDockedPanelTab('调音器', 'tuner')
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
              } else if (this.isTunerDockedVisible()) {
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
        this.updateMetronomeViewport(_windowSize);
        this.updateTunerViewport(_windowSize);
        this.syncPanelOffsetsToBounds();
        this.syncPanelOverlays();
      };
      this.mainWindow.on('windowSizeChange', this.windowSizeChangeCallback);
      this.avoidAreaChangeCallback = (_data: window.AvoidAreaOptions) => {
        this.syncAvoidAreasFromMainWindow();
      };
      this.syncAvoidAreasFromMainWindow();
      this.mainWindow.on('avoidAreaChange', this.avoidAreaChangeCallback);
    } catch (error) {
      hilog.error(0, 'PDFView', `获取窗口状态出错: ${error}.`);
    }

    this.ensurePanelOverlays();
    this.immersiveListening();
    const context = this.getUIContext().getHostContext() as Context;
    context.eventHub.on('onBackGround', this.onBackGround);

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
      this.annotationController.executeUndo();
      this.syncPanelOverlays();
    }));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_Z], true, true, () => {
      this.annotationController.executeRedo();
      this.syncPanelOverlays();
    }));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_Y], true, false, () => {
      this.annotationController.executeRedo();
      this.syncPanelOverlays();
    }));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_S], true, false, () => this.annotationController.executeSave()));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_DPAD_UP, KeyCode.KEYCODE_DPAD_LEFT], true, false, () => this.gotoPage(0)));
    this.hotkeys.push(new InputAction([KeyCode.KEYCODE_DPAD_DOWN, KeyCode.KEYCODE_DPAD_RIGHT, KeyCode.KEYCODE_SPACE], true, false, () => this.gotoPage(this.viewerViewModel.getLastNavigableIndex())));

    // Defer heavy document loading so UI can render the loading indicator first
    this.initializeDocument();
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
    this.triggerPageFlipShadeIntro();
    this.startTransparencyTimeout();
  }

  /**
   * 拦截系统返回键，回到主页而非退出应用
   */
  onBackPress(): boolean {
    this.backToMainMenu();
    return true;
  }

  aboutToDisappear(): void {
    this.disposePanelOverlays();
    this.metronomeController.cleanup();
    this.tunerController.cleanup();
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

  /** 从主窗口同步状态栏与导航指示条避让高度（px）；用于节拍器迷你浮标，根布局不再整体 padding */
  private syncAvoidAreasFromMainWindow(): void {
    try {
      const systemArea = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const navArea = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const nextTop = systemArea.topRect.height;
      const nextBottom = navArea.bottomRect.height;
      const changed = nextTop !== this.avoidAreaTopPx || nextBottom !== this.avoidAreaBottomPx;
      this.avoidAreaTopPx = nextTop;
      this.avoidAreaBottomPx = nextBottom;
      if (changed) {
        this.syncPanelOverlays();
      }
    } catch (_e) {
    }
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
        if (displayIndex < 0) {
          return;
        }
        // Automatically update display when high-res version is ready
        if (displayIndex === 0) {
          this.view1PixelMap = highResCache.pixelMap;
        } else if (displayIndex === 1) {
          this.view2PixelMap = highResCache.pixelMap;
        } else if (displayIndex === 2) {
          this.view3PixelMap = highResCache.pixelMap;
        }
        this.applyTransitionHighResIfNeeded(targetIndex, highResCache);
      }
    );
  }

  private applyTransitionHighResIfNeeded(targetIndex: number, cache: PageCache): void {
    const ni = this.transNextIndices.indexOf(targetIndex);
    if (ni === 0) {
      this.transNext1PixelMap = cache.pixelMap;
      this.transNext1ViewSize = cache.displaySize;
    } else if (ni === 1) {
      this.transNext2PixelMap = cache.pixelMap;
      this.transNext2ViewSize = cache.displaySize;
    } else if (ni === 2) {
      this.transNext3PixelMap = cache.pixelMap;
      this.transNext3ViewSize = cache.displaySize;
    }
    const pi = this.transPrevIndices.indexOf(targetIndex);
    if (pi === 0) {
      this.transPrev1PixelMap = cache.pixelMap;
      this.transPrev1ViewSize = cache.displaySize;
    } else if (pi === 1) {
      this.transPrev2PixelMap = cache.pixelMap;
      this.transPrev2ViewSize = cache.displaySize;
    } else if (pi === 2) {
      this.transPrev3PixelMap = cache.pixelMap;
      this.transPrev3ViewSize = cache.displaySize;
    }
  }

  private clearTransitionPixelMaps(): void {
    this.transNext1PixelMap = undefined;
    this.transNext2PixelMap = undefined;
    this.transNext3PixelMap = undefined;
    this.transPrev1PixelMap = undefined;
    this.transPrev2PixelMap = undefined;
    this.transPrev3PixelMap = undefined;
    this.transNext1Loading = false;
    this.transNext2Loading = false;
    this.transNext3Loading = false;
    this.transPrev1Loading = false;
    this.transPrev2Loading = false;
    this.transPrev3Loading = false;
  }

  private resetHorizontalSlidePreview(): void {
    this.clearHorizontalSlidePreviewState();
  }

  /** 立即清除横向滑动预览条带（无淡出） */
  private clearHorizontalSlidePreviewState(): void {
    this.pendingSlideGotoTarget = undefined;
    // 使尚未完成的 loadTransitionNeighbor 回调全部失效，避免收尾后仍 assign / 再触发淡入造成邻条 Next/Prev 闪跳
    this.transitionNeighborGen++;
    this.pageTurnDragActive = false;
    this.pageTurnDirection = 0;
    this.pageTurnOffsetVp = 0;
    this.pageTurnPreviewOffsetLocked = false;
    this.pageTurnPreviewOffsetVp = 0;
    this.pageTurnMainAdvanceVp = 0;
    this.pageTurnPrevAdvanceVp = 0;
    this.slideVelocityVpPerMs = 0;
    this.lastSlideSampleTimeMs = 0;
    this.pageTurnCommitAnimating = false;
    this.pageTurnCrossfadeT = 0;
    this.transNextIndices = [];
    this.transPrevIndices = [];
    this.clearTransitionPixelMaps();
    this.viewerViewModel.clearSlideNavEffectiveStartIndex();
    this.slideNeighborAppearFadeGen++;
    this.pageTurnNeighborAppearOpacity = 1;
  }

  /**
   * 单指新按下时打断尚未结束的提交动画或 defer goto 收尾，便于连续快速滑动翻页。
   * 与 slideCommitAnimGen / pageLoadVersion 配合丢弃已过期的 animateTo 与 load 回调。
   */
  private interruptHorizontalSlideForNewTouch(): void {
    if (this.viewerViewModel.pageFlipMode !== 'horizontalSlide') {
      return;
    }
    this.slideCommitAnimGen++;
    if (this.pageTurnCommitAnimating && this.pendingSlideGotoTarget !== undefined) {
      const t = this.pendingSlideGotoTarget;
      this.pendingSlideGotoTarget = undefined;
      const dir = this.pageTurnDirection;
      this.pageTurnOffsetVp = this.computeCommitSlideEndOffsetVp(dir);
      this.pageTurnCrossfadeT = 1;
      this.pageTurnCommitAnimating = false;
      this.pageTurnNeighborAppearOpacity = 1;
      void this.gotoPage(t, true);
      return;
    }
    this.pageTurnCommitAnimating = false;
    this.pageTurnCrossfadeT = 0;
    this.pendingSlideGotoTarget = undefined;
    if (this.slideGotoInFlight) {
      this.pageLoadVersion++;
      this.slideGotoInFlight = false;
      this.slideGotoCompletionToken = 0;
      this.clearHorizontalSlidePreviewState();
    } else {
      this.resetHorizontalSlidePreview();
    }
  }

  /** defer goto 收尾：邻条淡出后再清条带并 resetViewToFit，避免视口与条带位移叠帧闪动 */
  private fadeDeferSlideGotoTeardown(navToken: number): void {
    const hasStrip = this.transPrevIndices.length > 0 || this.transNextIndices.length > 0;
    if (!hasStrip) {
      this.ensureMainRowEmptySlotsMatchDisplayed();
      this.clearHorizontalSlidePreviewState();
      this.resetViewToFit();
      this.redrawStrokes();
      if (this.slideGotoCompletionToken === navToken) {
        this.slideGotoInFlight = false;
      }
      return;
    }
    // 先于淡出再 bump：否则仍挂着的 loadTransitionNeighbor 会在 await 结束后误触发 startSlideNeighborPreviewFadeIn / assign
    this.transitionNeighborGen++;
    this.slideNeighborAppearFadeGen++;
    const g = this.slideNeighborAppearFadeGen;
    // 预览层先钉在中心盖住一帧级别的主层重绘窗口；主层再独立归零并恢复可见。
    this.lockCommittedPreviewAtCenter();
    // 邻条常窄于双页主行全宽，恢复主层可见前强制对齐空槽，避免右侧仍一帧旧位图。
    this.ensureMainRowEmptySlotsMatchDisplayed();
    this.pageTurnCommitAnimating = false;
    this.pageTurnCrossfadeT = 0;
    this.pageTurnOffsetVp = 0;
    this.pageTurnNeighborAppearOpacity = 1;
    setTimeout(() => {
      if (g !== this.slideNeighborAppearFadeGen || this.slideGotoCompletionToken !== navToken) {
        return;
      }
      this.getUIContext().animateTo({
        duration: SLIDE_NEIGHBOR_FADE_OUT_MS,
        curve: Curve.EaseIn,
        onFinish: () => {
          if (g !== this.slideNeighborAppearFadeGen) {
            return;
          }
          this.clearHorizontalSlidePreviewState();
          this.resetViewToFit();
          this.redrawStrokes();
          if (this.slideGotoCompletionToken === navToken) {
            this.slideGotoInFlight = false;
          }
        }
      }, () => {
        this.pageTurnNeighborAppearOpacity = 0;
      });
    }, 0);
  }

  /**
   * 邻条挂载（占位或真实图）时立即显示为不透明。
   * 不再做长淡入：连滑时反复 0→1 会与主条位移叠出「浮层脉冲」；与主条保持全不透明一起更接近连续拖动。
   */
  private startSlideNeighborPreviewFadeIn(): void {
    if (this.viewerViewModel.pageFlipMode !== 'horizontalSlide') {
      return;
    }
    this.slideNeighborAppearFadeGen++;
    this.pageTurnNeighborAppearOpacity = 1;
  }

  /** 左侧邻条：预览透明度由 pageTurnNeighborAppearOpacity 控制 */
  private getSlidePrevStripOpacity(): number {
    if (this.transPrevIndices.length > 0) {
      return this.pageTurnNeighborAppearOpacity;
    }
    return 1;
  }

  /**
   * 中间主条不透明度。
   * 提交动画期间不再淡出主条：否则邻条叠在上层、主条渐隐，连滑时像「手指上飘着一块页、底下还在翻」；
   * 仅靠位移与邻条即可衔接，观感更接近连续纸带。
   */
  private getSlideCurrentStripOpacity(): number {
    return 1;
  }

  /** 右侧邻条：预览透明度由 pageTurnNeighborAppearOpacity 控制 */
  private getSlideNextStripOpacity(): number {
    if (this.transNextIndices.length > 0) {
      return this.pageTurnNeighborAppearOpacity;
    }
    return 1;
  }

  private getStripAdvanceForCommitVp(): number {
    const ui = this.getUIContext();
    return ui.px2vp((this.viewerViewModel.viewSize.x + ContainerSpacing) * this.viewerViewModel.viewScale);
  }

  private snapshotPageTurnGeometry(): void {
    const ui = this.getUIContext();
    const scale = this.viewerViewModel.viewScale;
    this.pageTurnMainAdvanceVp = ui.px2vp((this.viewerViewModel.viewSize.x + ContainerSpacing) * scale);
    this.pageTurnPrevAdvanceVp = ui.px2vp((this.getPrevStripWidthPx() + ContainerSpacing) * scale);
  }

  /** 松手后动画应收尾的相对偏移（不含 baseline）：下一套为负、上一套为正 */
  private computeCommitSlideEndOffsetVp(direction: number): number {
    const adv = this.pageTurnMainAdvanceVp > 0 ? this.pageTurnMainAdvanceVp : this.getStripAdvanceForCommitVp();
    if (direction === -1) {
      return -adv;
    }
    if (direction === 1) {
      return adv;
    }
    return 0;
  }

  /** 速度越快，所需 |offset|/viewport 比例越低；单位 vp/ms */
  private getDynamicCommitProgressThreshold(speedVpPerMs: number): number {
    const refV = 0.52;
    const s = Math.min(1, Math.abs(speedVpPerMs) / refV);
    return PAGE_TURN_COMMIT_RATIO_FAST + (PAGE_TURN_COMMIT_RATIO_SLOW - PAGE_TURN_COMMIT_RATIO_FAST) * (1 - s);
  }

  private shouldFlickCommit(direction: number, progress: number): boolean {
    if (progress < PAGE_TURN_FLICK_MIN_PROGRESS) {
      return false;
    }
    const v = this.slideVelocityVpPerMs;
    if (direction === -1) {
      return v <= -PAGE_TURN_FLICK_VP_PER_MS;
    }
    if (direction === 1) {
      return v >= PAGE_TURN_FLICK_VP_PER_MS;
    }
    return false;
  }

  private getPrevStripWidthPx(): number {
    const g = ContainerSpacing;
    const n = this.transPrevIndices.length;
    if (n === 0) {
      return 0;
    }
    let w = 0;
    if (n >= 1) {
      w += this.transPrev1ViewSize.x;
    }
    if (n >= 2) {
      w += g + this.transPrev2ViewSize.x;
    }
    if (n >= 3) {
      w += g + this.transPrev3ViewSize.x;
    }
    return w;
  }

  private getNextStripWidthPx(): number {
    const g = ContainerSpacing;
    const n = this.transNextIndices.length;
    if (n === 0) {
      return 0;
    }
    let w = 0;
    if (n >= 1) {
      w += this.transNext1ViewSize.x;
    }
    if (n >= 2) {
      w += g + this.transNext2ViewSize.x;
    }
    if (n >= 3) {
      w += g + this.transNext3ViewSize.x;
    }
    return w;
  }

  private getTransitionStripSizePx(side: 'next' | 'prev'): Vector2 {
    if (side === 'next') {
      const h = Math.max(this.transNext1ViewSize.y, Math.max(this.transNext2ViewSize.y, this.transNext3ViewSize.y));
      return Vec2(this.getNextStripWidthPx(), h);
    }
    const h = Math.max(this.transPrev1ViewSize.y, Math.max(this.transPrev2ViewSize.y, this.transPrev3ViewSize.y));
    return Vec2(this.getPrevStripWidthPx(), h);
  }

  /** 预览层作为主文档层的兄弟节点，偏移只表达相对主层的位置，不参与 viewSize/fit 计算。 */
  private getPreviewStripTranslateVp(side: 'next' | 'prev'): number {
    const ui = this.getUIContext();
    const scale = this.viewerViewModel.viewScale;
    const slideOffsetVp = this.pageTurnPreviewOffsetLocked ? this.pageTurnPreviewOffsetVp : this.pageTurnOffsetVp;
    if (side === 'next') {
      const usingSnapshot = this.pageTurnMainAdvanceVp > 0;
      const advanceVp = usingSnapshot
        ? this.pageTurnMainAdvanceVp
        : ui.px2vp((this.viewerViewModel.viewSize.x + ContainerSpacing) * scale);
      const result = slideOffsetVp + advanceVp;
      return result;
    }
    const usingSnapshot = this.pageTurnPrevAdvanceVp > 0;
    const advanceVp = usingSnapshot
      ? this.pageTurnPrevAdvanceVp
      : ui.px2vp((this.getPrevStripWidthPx() + ContainerSpacing) * scale);
    const result = slideOffsetVp - advanceVp;
    return result;
  }

  /** 收尾时把目标预览层钉在主层位置，之后主层可独立归零并在其下方完成绘制。 */
  private lockCommittedPreviewAtCenter(): void {
    const ui = this.getUIContext();
    const scale = this.viewerViewModel.viewScale;
    if (this.pageTurnDirection === -1 && this.transNextIndices.length > 0) {
      const usingSnapshot = this.pageTurnMainAdvanceVp > 0;
      const advanceVp = usingSnapshot
        ? this.pageTurnMainAdvanceVp
        : ui.px2vp((this.viewerViewModel.viewSize.x + ContainerSpacing) * scale);
      this.pageTurnPreviewOffsetVp = -advanceVp;
      this.pageTurnPreviewOffsetLocked = true;
      return;
    }
    if (this.pageTurnDirection === 1 && this.transPrevIndices.length > 0) {
      const usingSnapshot = this.pageTurnPrevAdvanceVp > 0;
      const advanceVp = usingSnapshot
        ? this.pageTurnPrevAdvanceVp
        : ui.px2vp((this.getPrevStripWidthPx() + ContainerSpacing) * scale);
      this.pageTurnPreviewOffsetVp = advanceVp;
      this.pageTurnPreviewOffsetLocked = true;
      return;
    }
    this.pageTurnPreviewOffsetLocked = false;
    this.pageTurnPreviewOffsetVp = 0;
  }

  private applyElasticPageTurnOffset(rawVp: number, viewportWvp: number): number {
    if (viewportWvp < 1) {
      return rawVp;
    }
    const soft = viewportWvp;
    const hard = viewportWvp * (1 + PAGE_TURN_ELASTIC_EXTRA_RATIO);
    const sign = rawVp >= 0 ? 1 : -1;
    const ax = Math.abs(rawVp);
    if (ax <= soft) {
      return rawVp;
    }
    const over = ax - soft;
    const damp = soft + Math.sqrt(over) * (10 + viewportWvp * 0.04);
    return sign * Math.min(damp, hard);
  }

  private beginPageTurnSession(direction: number, firstHorizDeltaVp: number, viewportWvp: number): void {
    this.slideNeighborAppearFadeGen++;
    this.pageTurnNeighborAppearOpacity = 1;
    this.pageTurnDragActive = true;
    this.pageTurnDirection = direction;
    this.pageTurnPreviewOffsetLocked = false;
    this.pageTurnPreviewOffsetVp = 0;
    this.suppressSidePageFlipFromGesture = true;
    this.pageTurnOffsetVp =
      this.applyElasticPageTurnOffset(firstHorizDeltaVp * PAGE_TURN_DRAG_GAIN, viewportWvp);
    this.transitionNeighborGen++;
    const gen = this.transitionNeighborGen;
    this.slideVelocityVpPerMs = 0;
    this.lastSlideSampleTimeMs = Date.now();
    if (direction < 0) {
      this.transPrevIndices = [];
      void this.loadTransitionNeighbor('next', gen);
    } else {
      this.transNextIndices = [];
      void this.loadTransitionNeighbor('prev', gen);
    }
  }

  private async loadTransitionNeighbor(kind: 'next' | 'prev', gen: number): Promise<void> {
    const indices = kind === 'next' ? this.viewerViewModel.peekNextSetIndices() : this.viewerViewModel.peekPrevSetIndices();
    if (indices.length === 0) {
      return;
    }
    if (kind === 'next') {
      this.transNextIndices = indices;
      this.applyTransitionPlaceholders('next', indices);
    } else {
      this.transPrevIndices = indices;
      this.applyTransitionPlaceholders('prev', indices);
    }
    this.startSlideNeighborPreviewFadeIn();
    const loadVersion = this.pageLoadVersion;
    const tasks: Array<Promise<void>> = [];
    for (let i = 0; i < indices.length; i++) {
      const pageIndex = indices[i];
      const slot = i;
      tasks.push(this.getPageCache(pageIndex, this.currentRenderScale, loadVersion)
        .then(cache => {
          if (gen !== this.transitionNeighborGen || loadVersion !== this.pageLoadVersion) {
            return;
          }
          this.assignTransitionSlot(kind, slot, cache);
        }));
    }
    await Promise.all(tasks);
    if (gen !== this.transitionNeighborGen) {
      return;
    }
  }

  private applyTransitionPlaceholders(kind: 'next' | 'prev', indices: number[]): void {
    for (let i = 0; i < indices.length; i++) {
      const sz = this.getPageDisplaySize(indices[i]);
      if (kind === 'next') {
        if (i === 0) {
          this.transNext1PixelMap = this.placeholderPixelMap;
          this.transNext1ViewSize = sz;
          this.transNext1Loading = true;
        } else if (i === 1) {
          this.transNext2PixelMap = this.placeholderPixelMap;
          this.transNext2ViewSize = sz;
          this.transNext2Loading = true;
        } else if (i === 2) {
          this.transNext3PixelMap = this.placeholderPixelMap;
          this.transNext3ViewSize = sz;
          this.transNext3Loading = true;
        }
      } else {
        if (i === 0) {
          this.transPrev1PixelMap = this.placeholderPixelMap;
          this.transPrev1ViewSize = sz;
          this.transPrev1Loading = true;
        } else if (i === 1) {
          this.transPrev2PixelMap = this.placeholderPixelMap;
          this.transPrev2ViewSize = sz;
          this.transPrev2Loading = true;
        } else if (i === 2) {
          this.transPrev3PixelMap = this.placeholderPixelMap;
          this.transPrev3ViewSize = sz;
          this.transPrev3Loading = true;
        }
      }
    }
  }

  private assignTransitionSlot(kind: 'next' | 'prev', slot: number, cache: PageCache): void {
    if (kind === 'next') {
      if (slot === 0) {
        this.transNext1PixelMap = cache.pixelMap;
        this.transNext1ViewSize = cache.displaySize;
        this.transNext1Loading = false;
      } else if (slot === 1) {
        this.transNext2PixelMap = cache.pixelMap;
        this.transNext2ViewSize = cache.displaySize;
        this.transNext2Loading = false;
      } else if (slot === 2) {
        this.transNext3PixelMap = cache.pixelMap;
        this.transNext3ViewSize = cache.displaySize;
        this.transNext3Loading = false;
      }
    } else {
      if (slot === 0) {
        this.transPrev1PixelMap = cache.pixelMap;
        this.transPrev1ViewSize = cache.displaySize;
        this.transPrev1Loading = false;
      } else if (slot === 1) {
        this.transPrev2PixelMap = cache.pixelMap;
        this.transPrev2ViewSize = cache.displaySize;
        this.transPrev2Loading = false;
      } else if (slot === 2) {
        this.transPrev3PixelMap = cache.pixelMap;
        this.transPrev3ViewSize = cache.displaySize;
        this.transPrev3Loading = false;
      }
    }
  }

  private handleHorizontalSlideDragMove(deltaPx: Vector2, dvp: Vector2): void {
    const ui = this.getUIContext();
    const vvm = this.viewerViewModel;
    const viewportWvp = vvm.getPanClampBounds(ui).viewportSizeVp.x;
    const dominantH = Math.abs(dvp.x) * PAGE_TURN_DOMINANT_RATIO >= Math.abs(dvp.y);

    if (this.pageTurnDragActive) {
      vvm.panByDeltaVp(Vec2(0, dvp.y), ui);
      this.pageTurnOffsetVp = this.applyElasticPageTurnOffset(
        this.pageTurnOffsetVp + dvp.x * PAGE_TURN_DRAG_GAIN,
        viewportWvp
      );
      const now = Date.now();
      if (this.lastSlideSampleTimeMs > 0) {
        const dtMs = Math.max(1, now - this.lastSlideSampleTimeMs);
        const instVpPerMs = (dvp.x * PAGE_TURN_DRAG_GAIN) / dtMs;
        this.slideVelocityVpPerMs = 0.42 * this.slideVelocityVpPerMs + 0.58 * instVpPerMs;
      }
      this.lastSlideSampleTimeMs = now;
      if (this.pageTurnDirection === -1 && this.transNextIndices.length === 0) {
        this.transitionNeighborGen++;
        void this.loadTransitionNeighbor('next', this.transitionNeighborGen);
      } else if (this.pageTurnDirection === 1 && this.transPrevIndices.length === 0) {
        this.transitionNeighborGen++;
        void this.loadTransitionNeighbor('prev', this.transitionNeighborGen);
      }
      return;
    }

    const canH = vvm.canPanHorizontally(ui);
    const nextIdx = vvm.peekNextSetIndices();
    const prevIdx = vvm.peekPrevSetIndices();
    const startNext = dominantH && dvp.x < 0 && nextIdx.length > 0 &&
      (!canH || vvm.isAtHorizontalScrollRightEnd(ui));
    const startPrev = dominantH && dvp.x > 0 && prevIdx.length > 0 &&
      (!canH || vvm.isAtHorizontalScrollLeftEnd(ui));

    if (startNext) {
      this.beginPageTurnSession(-1, dvp.x, viewportWvp);
      vvm.panByDeltaVp(Vec2(0, dvp.y), ui);
      return;
    }
    if (startPrev) {
      this.beginPageTurnSession(1, dvp.x, viewportWvp);
      vvm.panByDeltaVp(Vec2(0, dvp.y), ui);
      return;
    }

    vvm.panBy(deltaPx, ui);
  }

  private finalizeHorizontalSlideOnUp(): void {
    const ui = this.getUIContext();
    if (!this.pageTurnDragActive) {
      return;
    }
    const viewportWvp = this.viewerViewModel.getPanClampBounds(ui).viewportSizeVp.x;
    const progress = Math.abs(this.pageTurnOffsetVp) / Math.max(1, viewportWvp);
    const ratioReq = this.getDynamicCommitProgressThreshold(this.slideVelocityVpPerMs);
    const dir = this.pageTurnDirection;
    const committed =
      (dir !== 0 && progress >= ratioReq) || this.shouldFlickCommit(dir, progress);
    this.pageTurnDragActive = false;

    if (!committed || dir === 0) {
      this.pendingSlideGotoTarget = undefined;
      this.pageTurnCommitAnimating = false;
      this.pageTurnCrossfadeT = 0;
      const hasPreviewStrip = this.transPrevIndices.length > 0 || this.transNextIndices.length > 0;
      this.slideNeighborAppearFadeGen++;
      const cancelAnimGen = this.slideNeighborAppearFadeGen;
      this.getUIContext().animateTo({
        duration: 200,
        curve: Curve.EaseInOut,
        onFinish: () => {
          if (cancelAnimGen !== this.slideNeighborAppearFadeGen) {
            return;
          }
          if (!hasPreviewStrip) {
            this.clearHorizontalSlidePreviewState();
          }
        }
      }, () => {
        this.pageTurnOffsetVp = 0;
      });
      if (hasPreviewStrip) {
        this.getUIContext().animateTo({
          duration: SLIDE_NEIGHBOR_FADE_OUT_MS,
          curve: Curve.EaseIn,
          onFinish: () => {
            if (cancelAnimGen !== this.slideNeighborAppearFadeGen) {
              return;
            }
            this.clearHorizontalSlidePreviewState();
          }
        }, () => {
          this.pageTurnNeighborAppearOpacity = 0;
        });
      }
      return;
    }

    const targetNext = this.viewerViewModel.navigateToNextPage();
    const targetPrev = Math.max(0, this.viewerViewModel.navigateToPreviousPage());
    const targetPage = dir === -1 ? targetNext : targetPrev;
    this.pendingSlideGotoTarget = targetPage;
    this.viewerViewModel.setSlideNavEffectiveStartIndex(targetPage);
    this.snapshotPageTurnGeometry();

    const endOff = this.computeCommitSlideEndOffsetVp(dir);
    const startOff = this.pageTurnOffsetVp;
    const dist = Math.abs(endOff - startOff);
    if (dist < 0.75) {
      this.slideNeighborAppearFadeGen++;
      this.pageTurnNeighborAppearOpacity = 1;
      this.pageTurnCommitAnimating = true;
      this.pageTurnCrossfadeT = 1;
      void this.gotoPage(targetPage, true);
      return;
    }
    const dur = Math.round(Math.min(520, Math.max(240, 220 + (dist / Math.max(1, viewportWvp)) * 320)));
    this.slideNeighborAppearFadeGen++;
    this.pageTurnNeighborAppearOpacity = 1;
    this.pageTurnCommitAnimating = true;
    this.pageTurnCrossfadeT = 0;
    const commitAnimGuard = this.slideCommitAnimGen;
    this.getUIContext().animateTo({
      duration: dur,
      curve: Curve.EaseOut,
      onFinish: () => {
        if (commitAnimGuard !== this.slideCommitAnimGen) {
          return;
        }
        // 位移到位后再 goto：主条不再做淡出，由邻条与位移承担过渡，goto 后 reset 偏移。
        void this.gotoPage(targetPage, true);
      }
    }, () => {
      this.pageTurnOffsetVp = endOff;
      this.pageTurnCrossfadeT = 1;
    });
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

  private assignViewSlotFromTransNext(mainSlot: number, transSlot: number): boolean {
    let pm: PixelMap | undefined;
    let vs: Vector2;
    let loading: boolean;
    if (transSlot === 0) {
      pm = this.transNext1PixelMap;
      vs = this.transNext1ViewSize;
      loading = this.transNext1Loading;
    } else if (transSlot === 1) {
      pm = this.transNext2PixelMap;
      vs = this.transNext2ViewSize;
      loading = this.transNext2Loading;
    } else {
      pm = this.transNext3PixelMap;
      vs = this.transNext3ViewSize;
      loading = this.transNext3Loading;
    }
    if (pm === undefined) {
      return false;
    }
    if (mainSlot === 0) {
      this.view1PixelMap = pm;
      this.view1ViewSize = vs;
      this.view1Loading = loading;
    } else if (mainSlot === 1) {
      this.view2PixelMap = pm;
      this.view2ViewSize = vs;
      this.view2Loading = loading;
    } else {
      this.view3PixelMap = pm;
      this.view3ViewSize = vs;
      this.view3Loading = loading;
    }
    return true;
  }

  private assignViewSlotFromTransPrev(mainSlot: number, transSlot: number): boolean {
    let pm: PixelMap | undefined;
    let vs: Vector2;
    let loading: boolean;
    if (transSlot === 0) {
      pm = this.transPrev1PixelMap;
      vs = this.transPrev1ViewSize;
      loading = this.transPrev1Loading;
    } else if (transSlot === 1) {
      pm = this.transPrev2PixelMap;
      vs = this.transPrev2ViewSize;
      loading = this.transPrev2Loading;
    } else {
      pm = this.transPrev3PixelMap;
      vs = this.transPrev3ViewSize;
      loading = this.transPrev3Loading;
    }
    if (pm === undefined) {
      return false;
    }
    if (mainSlot === 0) {
      this.view1PixelMap = pm;
      this.view1ViewSize = vs;
      this.view1Loading = loading;
    } else if (mainSlot === 1) {
      this.view2PixelMap = pm;
      this.view2ViewSize = vs;
      this.view2Loading = loading;
    } else {
      this.view3PixelMap = pm;
      this.view3ViewSize = vs;
      this.view3Loading = loading;
    }
    return true;
  }

  /**
   * 从横向滑动邻条带拷贝已解码的 PixelMap 到主槽，避免 commit 后、占位替换前仍画上一套图（目标→旧页→目标）。
   */
  private trySeedMainViewsFromTransition(indices: number[]): boolean[] {
    const seeded: boolean[] = [false, false, false];
    const preferPrevStrip = this.pageTurnDirection === 1;
    const nSlots = Math.min(3, indices.length);
    for (let mainSlot = 0; mainSlot < nSlots; mainSlot++) {
      const pageIndex = indices[mainSlot];
      let done = false;
      if (!preferPrevStrip) {
        const jn = this.transNextIndices.indexOf(pageIndex);
        if (jn >= 0) {
          done = this.assignViewSlotFromTransNext(mainSlot, jn);
        }
        if (!done) {
          const jp = this.transPrevIndices.indexOf(pageIndex);
          if (jp >= 0) {
            done = this.assignViewSlotFromTransPrev(mainSlot, jp);
          }
        }
      } else {
        const jp = this.transPrevIndices.indexOf(pageIndex);
        if (jp >= 0) {
          done = this.assignViewSlotFromTransPrev(mainSlot, jp);
        }
        if (!done) {
          const jn = this.transNextIndices.indexOf(pageIndex);
          if (jn >= 0) {
            done = this.assignViewSlotFromTransNext(mainSlot, jn);
          }
        }
      }
      seeded[mainSlot] = done;
    }
    return seeded;
  }

  /**
   * 按当前 displayed 与期望槽位数对齐空主槽（透明占位或清除）。
   * 仅用于横向滑动 defer 收尾：在恢复主层可见前调用。
   */
  private ensureMainRowEmptySlotsMatchDisplayed(): void {
    const indices = this.viewerViewModel.displayedPageIndices;
    const expectedSlots = this.viewerViewModel.getExpectedSlotCount();
    const refPage = indices.length > 0 ? indices[indices.length - 1] : 0;

    if (indices.length <= 1) {
      if (expectedSlots >= 2) {
        this.view2PixelMap = this.transparentPlaceholderPixelMap;
        this.view2ViewSize = this.getPageDisplaySize(refPage);
        this.view2Loading = false;
      } else {
        this.view2PixelMap = undefined;
        this.view2ViewSize = Vec2(0, 0);
      }
    }

    if (indices.length <= 2) {
      if (expectedSlots >= 3) {
        this.view3PixelMap = this.transparentPlaceholderPixelMap;
        this.view3ViewSize = this.getPageDisplaySize(refPage);
        this.view3Loading = false;
      } else {
        this.view3PixelMap = undefined;
        this.view3ViewSize = Vec2(0, 0);
      }
    }

    this.updateViewerViewSize();
  }

  // 加载页面缓存并更新视图状态
  private async loadAndDisplayPages(indices: number[], seedFromActiveTransitionStrip: boolean = false): Promise<void> {
    // 捕获当前加载版本；若在异步过程中 gotoPage 再次被调用则放弃过期的状态更新
    const loadVersion = this.pageLoadVersion;
    this.mainSlotPagesBeingLoaded = indices.slice();
    // 立即设置占位白色矩形并预计算目标页面尺寸
    this.view1Loading = false;
    this.view2Loading = false;
    this.view3Loading = false;

    // 根据显示模式确定期望的槽位数，剩余页面不足时仍用白色占位保持布局稳定
    const expectedSlots: number = this.viewerViewModel.getExpectedSlotCount();

    const seeded: boolean[] = seedFromActiveTransitionStrip
      ? this.trySeedMainViewsFromTransition(indices)
      : [false, false, false];

    if (indices.length > 0) {
      if (!seeded[0]) {
        this.view1PixelMap = this.placeholderPixelMap;
        this.view1ViewSize = this.getPageDisplaySize(indices[0]);
        this.view1Loading = true;
      }
    } else {
      this.view1PixelMap = undefined;
    }

    if (indices.length > 1) {
      if (!seeded[1]) {
        this.view2PixelMap = this.placeholderPixelMap;
        this.view2ViewSize = this.getPageDisplaySize(indices[1]);
        this.view2Loading = true;
      }
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
      if (!seeded[2]) {
        this.view3PixelMap = this.placeholderPixelMap;
        this.view3ViewSize = this.getPageDisplaySize(indices[2]);
        this.view3Loading = true;
      }
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
          if (loadVersion !== this.pageLoadVersion) {
            return;
          }
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
          if (loadVersion !== this.pageLoadVersion) {
            return;
          }
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
          if (loadVersion !== this.pageLoadVersion) {
            return;
          }
          this.view3PixelMap = cache.pixelMap;
          this.view3ViewSize = cache.displaySize;
          this.view3Loading = false;
        })
      )
    }

    await Promise.all(tasks);

    // 若在加载期间已切到其他页面，不再更新视图大小
    if (loadVersion !== this.pageLoadVersion) {
      this.mainSlotPagesBeingLoaded = [];
      return;
    }

    // 更新总体视图大小
    this.updateViewerViewSize();
  }

  async gotoPage(targetIndex: number, deferSlideVisualReset: boolean = false): Promise<void> {
    this.pendingSlideGotoTarget = undefined;
    if (targetIndex < 0 || targetIndex >= this.viewerViewModel.totalPageCount) {
      if (deferSlideVisualReset) {
        this.resetHorizontalSlidePreview();
        this.slideGotoInFlight = false;
      }
      return;
    }

    const clampedTarget = Math.max(0, Math.min(targetIndex, Math.max(0, this.viewerViewModel.totalPageCount - 1)));
    const indicesToLoad = this.viewerViewModel.getDisplayedIndicesForTargetPage(clampedTarget);

    if (!deferSlideVisualReset) {
      this.viewerViewModel.clearSlideNavEffectiveStartIndex();
      this.resetHorizontalSlidePreview();
      this.slideGotoInFlight = false;
    }

    // 递增加载版本以使上一个 gotoPage 发起的所有异步回调失效
    this.pageLoadVersion++;
    const navToken = this.pageLoadVersion;

    if (deferSlideVisualReset) {
      this.slideGotoInFlight = true;
      this.slideGotoCompletionToken = navToken;
    }

    // 导航到新页面时重置渲染缩放（先于 load，避免仍按旧缩放取缓存）
    this.currentRenderScale = ViewerMinRenderScale;

    // 先加载位图再 commit，避免 displayed 已指向新页而主槽仍画上一套造成「目标→旧页→目标」闪动
    await this.loadAndDisplayPages(indicesToLoad, deferSlideVisualReset);

    if (navToken !== this.pageLoadVersion) {
      this.mainSlotPagesBeingLoaded = [];
      if (deferSlideVisualReset && this.slideGotoCompletionToken === navToken) {
        this.slideGotoInFlight = false;
      }
      return;
    }

    this.viewerViewModel.commitPageTarget(clampedTarget);
    this.mainSlotPagesBeingLoaded = [];
    // displayed 已切换：须立刻按新 indices 重绘笔画层，否则透明 Image 下仍会叠上一套槽位的旧画布（双页末槽尤其明显）。
    this.redrawStrokes();

    // Debounce prefetch/eviction to avoid cache churn during rapid scrolling
    if (this.prefetchDebounceId !== undefined) {
      clearTimeout(this.prefetchDebounceId);
    }
    this.prefetchDebounceId = setTimeout(() => {
      this.prefetchDebounceId = undefined;
      this.pageDataSource.prefetchPagesAround(clampedTarget, 5, 15, this.viewerViewModel.displayedPageIndices);
    }, 300);

    if (deferSlideVisualReset) {
      this.fadeDeferSlideGotoTeardown(navToken);
    } else {
      this.resetViewToFit();
      this.redrawStrokes();
    }
  }

  resetViewToFit(): void {
    this.viewerViewModel.resetViewToFit(this.getUIContext());
  }

  /** 横向滑动过程中不让布局回调抢先重置 fit，交给提交/取消收尾统一处理。 */
  private shouldDeferViewportFitReset(): boolean {
    return this.viewerViewModel.pageFlipMode === 'horizontalSlide' &&
      (this.pageTurnDragActive || this.pageTurnCommitAnimating || this.slideGotoInFlight);
  }

  navigatePrevPage(): void {
    this.gotoPage(this.viewerViewModel.navigateToPreviousPage());
  }

  navigateNextPage(): void {
    this.gotoPage(this.viewerViewModel.navigateToNextPage());
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

  private transitionRowMaxHeightPx(): number {
    let h = Math.max(this.view1ViewSize.y, Math.max(this.view2ViewSize.y, this.view3ViewSize.y));
    if (this.transPrevIndices.length >= 1) {
      h = Math.max(h, this.transPrev1ViewSize.y);
    }
    if (this.transPrevIndices.length >= 2) {
      h = Math.max(h, this.transPrev2ViewSize.y);
    }
    if (this.transPrevIndices.length >= 3) {
      h = Math.max(h, this.transPrev3ViewSize.y);
    }
    if (this.transNextIndices.length >= 1) {
      h = Math.max(h, this.transNext1ViewSize.y);
    }
    if (this.transNextIndices.length >= 2) {
      h = Math.max(h, this.transNext2ViewSize.y);
    }
    if (this.transNextIndices.length >= 3) {
      h = Math.max(h, this.transNext3ViewSize.y);
    }
    return h;
  }

  /** 主文档层声明尺寸只使用当前页面组，预览层用独立 overlay 尺寸，避免影响 fit/pan。 */
  private getStripLayoutSizePx(): Vector2 {
    return this.viewerViewModel.viewSize;
  }

  private getTransitionPageIndex(side: 'next' | 'prev', viewIndex: number): number {
    const arr = side === 'next' ? this.transNextIndices : this.transPrevIndices;
    return arr[viewIndex] ?? 0;
  }

  getTransitionCanvasScale(side: 'next' | 'prev', viewIndex: number): ScaleOptions {
    let viewSize: Vector2;
    if (side === 'next') {
      viewSize = viewIndex === 0 ? this.transNext1ViewSize : (viewIndex === 1 ? this.transNext2ViewSize : this.transNext3ViewSize);
    } else {
      viewSize = viewIndex === 0 ? this.transPrev1ViewSize : (viewIndex === 1 ? this.transPrev2ViewSize : this.transPrev3ViewSize);
    }
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
    const arr = side === 'next' ? this.transNextIndices : this.transPrevIndices;
    return viewIndex < arr.length;
  }

  handleDrawTouch(
    drawCtx: CanvasRenderingContext2D,
    targetCtx: CanvasRenderingContext2D,
    pageIndex: number,
    event: TouchEvent
  ): void {
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
    const offset = this.getClampedPaletteOffset();
    const margin = 10;
    const w = AnnotationPaletteContentWidth * this.palettePanelScale;
    const h = AnnotationPaletteContentHeight * this.palettePanelScale;
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
      if (event.type === TouchType.Down && (this.annotationController.annotateMode === 'draw' || this.annotationController.annotateMode === 'erase')) {
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
          this.interruptHorizontalSlideForNewTouch();
        }
        this.lastTouchPoint = touchPoint;
        this.panSessionStartPoint = touchPoint;
        this.suppressSidePageFlipFromGesture = false;
        if (!this.viewerViewModel.isAnnotatePaletteVisible) {
          this.startLongPressDetection(touchPoint.x, touchPoint.y);
        }
      } else if (event.type == TouchType.Move) {
        if (this.panSessionStartPoint !== undefined) {
          const sx = touchPoint.x - this.panSessionStartPoint.x;
          const sy = touchPoint.y - this.panSessionStartPoint.y;
          if (sx * sx + sy * sy > PAGE_FLIP_SUPPRESS_MOVE_PX * PAGE_FLIP_SUPPRESS_MOVE_PX) {
            this.suppressSidePageFlipFromGesture = true;
          }
        }
        if (this.longPressTouchDown && this.lastTouchPoint !== undefined) {
          const dx = touchPoint.x - this.longPressPosX;
          const dy = touchPoint.y - this.longPressPosY;
          if (Math.sqrt(dx * dx + dy * dy) > LONG_PRESS_MOVE_THRESHOLD) {
            this.cancelLongPress();
          }
        }
        if (this.lastTouchPoint !== undefined) {
          const delta = Vec2(
            touchPoint.x - this.lastTouchPoint.x,
            touchPoint.y - this.lastTouchPoint.y
          );
          if (this.viewerViewModel.pageFlipMode === 'horizontalSlide') {
            const dvp = pxToVp(delta, uiCtx);
            this.handleHorizontalSlideDragMove(delta, dvp);
          } else {
            this.viewerViewModel.panBy(delta, uiCtx);
          }
          this.lastTouchPoint = touchPoint;
        }
      } else if (event.type == TouchType.Up) {
        this.cancelLongPress();
        if (this.viewerViewModel.pageFlipMode === 'horizontalSlide') {
          this.finalizeHorizontalSlideOnUp();
        }
        this.lastTouchPoint = undefined;
        this.panSessionStartPoint = undefined;
      }
    } else if (isDualTouch) {
      this.cancelLongPress();
      this.resetHorizontalSlidePreview();
      this.suppressSidePageFlipFromGesture = true;
      this.panSessionStartPoint = undefined;
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
      this.panSessionStartPoint = undefined;
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
      this.mousePanSessionStart = undefined;
    }
  }

  handleDrawMouse(
    drawCtx: CanvasRenderingContext2D,
    targetCtx: CanvasRenderingContext2D,
    pageIndex: number,
    event: MouseEvent
  ): void {
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
    this.viewerViewModel.openAnnotatePalette(explicitTool);
    this.initPalettePosition();
    this.syncPanelOverlays();
    this.annotationController.prepareImportedPolylineAnnotations()
      .then(() => this.syncPanelOverlays())
      .catch((error: Error) => hilog.error(0, 'PDFView', `导入已有折线批注出错: ${error.message}`));
  }

  initPalettePosition(): void {
    if (this.palettePanelOffset.x !== 0 || this.palettePanelOffset.y !== 0) {
      return;
    }
    const viewportWidthVp = this.getUIContext().px2vp(this.viewerViewModel.viewportSize.x);
    const viewportHeightVp = this.getUIContext().px2vp(this.viewerViewModel.viewportSize.y);
    const scaledW = AnnotationPaletteContentWidth * this.palettePanelScale;
    const scaledH = AnnotationPaletteContentHeight * this.palettePanelScale;
    this.palettePanelOffset = {
      x: Math.max(0, (viewportWidthVp - scaledW) / 2),
      y: Math.max(0, viewportHeightVp - scaledH - 80)
    };
  }

  private getClampedPaletteOffset(offset: FloatingPanelOffset = this.palettePanelOffset): FloatingPanelOffset {
    const viewportWidthVp = this.getUIContext().px2vp(this.viewerViewModel.viewportSize.x);
    const viewportHeightVp = this.getUIContext().px2vp(this.viewerViewModel.viewportSize.y);
    const scaledW = AnnotationPaletteContentWidth * this.palettePanelScale;
    const scaledH = AnnotationPaletteContentHeight * this.palettePanelScale;
    return {
      x: Math.max(0, Math.min(viewportWidthVp - scaledW, offset.x)),
      y: Math.max(0, Math.min(viewportHeightVp - scaledH, offset.y))
    };
  }

  private handlePaletteHostDragStart(): void {
    this.beginPanelGesture('metronome');
    const clampedOffset = this.getClampedPaletteOffset();
    this.palettePanelOffset = clampedOffset;
    this.paletteDragStartOffset = { x: clampedOffset.x, y: clampedOffset.y };
    this.syncPanelOverlays();
  }

  private handlePaletteHostDragUpdate(event: GestureEvent): void {
    this.palettePanelOffset = this.getClampedPaletteOffset({
      x: this.paletteDragStartOffset.x + event.offsetX * this.palettePanelScale,
      y: this.paletteDragStartOffset.y + event.offsetY * this.palettePanelScale
    });
    this.syncPanelOverlays();
  }

  private handlePaletteHostDragEnd(): void {
    this.endPanelGesture();
  }

  private handlePaletteHostPinchStart(): void {
    this.beginPanelGesture('metronome');
    this.palettePinchStartScale = this.palettePanelScale;
  }

  private handlePaletteHostPinchUpdate(event: GestureEvent): void {
    this.palettePanelScale = Math.max(PaletteMinScale, Math.min(PaletteMaxScale, this.palettePinchStartScale * event.scale));
    this.palettePanelOffset = this.getClampedPaletteOffset();
    this.syncPanelOverlays();
  }

  private handlePaletteHostPinchEnd(): void {
    this.palettePinchStartScale = this.palettePanelScale;
    this.endPanelGesture();
  }

  private clampPaletteScale(scale: number): number {
    return Math.max(PaletteMinScale, Math.min(PaletteMaxScale, scale));
  }

  private createAnnotationPaletteOverlayParams(): AnnotationPaletteOverlayParams {
    return new AnnotationPaletteOverlayParams({
      showWindow: this.viewerViewModel.isAnnotatePaletteVisible,
      annotateMode: this.viewerViewModel.annotateMode,
      undoCount: this.annotationController.undoHistoryCount,
      redoCount: this.annotationController.redoHistoryCount,
      hasUnsaved: this.annotationController.hasUnsavedStrokes,
      hostScale: this.palettePanelScale,
      hostOffset: this.getClampedPaletteOffset(),
      drawColor: this.annotationController.selectedDrawColor,
      customDrawColor: this.annotationController.customDrawColor,
      recentCustomColors: this.annotationController.recentCustomColors,
      onSetMode: (mode: PDFAnnotateMode) => this.handlePaletteSetMode(mode),
      onSelectDrawColor: (color: AnnotationColor) => {
        this.annotationController.setSelectedDrawColor(color);
        this.syncPanelOverlays();
      },
      onSetCustomDrawColor: (color: AnnotationColor) => {
        this.annotationController.setCustomDrawColor(color);
        this.syncPanelOverlays();
      },
      onCommitRecentCustomColor: (color: AnnotationColor) => {
        this.annotationController.pushRecentCustomColor(color);
        this.annotationController.flushPendingDrawColorPreferences();
        this.syncPanelOverlays();
      },
      onUndo: () => {
        this.annotationController.executeUndo();
        this.syncPanelOverlays();
      },
      onRedo: () => {
        this.annotationController.executeRedo();
        this.syncPanelOverlays();
      },
      onSave: () => {
        this.annotationController.executeSave()
          .then(() => this.syncPanelOverlays())
          .catch((error: Error) => hilog.error(0, 'PDFView', `保存批注出错: ${error.message}`));
      },
      onClose: () => {
        this.annotationController.flushPendingDrawColorPreferences();
        this.viewerViewModel.closeAnnotatePalette();
        this.syncPanelOverlays();
      },
      onTouchStateChanged: (active: boolean) => {
        this.isPanelGestureActive = active;
      },
      onHostDragStart: () => this.handlePaletteHostDragStart(),
      onHostDragUpdate: (event: GestureEvent) => this.handlePaletteHostDragUpdate(event),
      onHostDragEnd: () => this.handlePaletteHostDragEnd(),
      onHostPinchStart: () => this.handlePaletteHostPinchStart(),
      onHostPinchUpdate: (event: GestureEvent) => this.handlePaletteHostPinchUpdate(event),
      onHostPinchEnd: () => this.handlePaletteHostPinchEnd()
    });
  }

  handlePaletteSetMode(mode: PDFAnnotateMode): void {
    if (this.viewerViewModel.annotateMode === mode) {
      this.viewerViewModel.closeAnnotatePalette();
    } else {
      this.viewerViewModel.setAnnotateMode(mode);
    }
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
            visible: this.viewerViewModel.shouldShowSecondSlot() &&
              this.viewerViewModel.displayedPageIndices.length >= 2,
            occupyLayoutWhenHidden: this.viewerViewModel.shouldShowSecondSlot(),
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
            visible: this.viewerViewModel.shouldShowThirdSlot() &&
              this.viewerViewModel.displayedPageIndices.length >= 3,
            occupyLayoutWhenHidden: this.viewerViewModel.shouldShowThirdSlot(),
            drawCanvasVisible: this.viewerViewModel.annotateMode !== 'drag',
            annotateCtx: this.view3Ctx,
            drawCtx: this.view3DrawCtx,
            onDrawTouch: (event: TouchEvent) => this.handleDrawTouch(this.view3DrawCtx, this.view3Ctx, this.viewerViewModel.displayedPageIndices[2] ?? 0, event),
            onDrawMouse: (event: MouseEvent) => this.handleDrawMouse(this.view3DrawCtx, this.view3Ctx, this.viewerViewModel.displayedPageIndices[2] ?? 0, event)
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
        .translate({ x: this.pageTurnOffsetVp, y: 0 })
        .opacity(this.getSlideCurrentStripOpacity())

        // 左侧预览条叠在主文档层之上，否则主条全宽时会挡住左侧邻条的可视区域。
        if (this.transPrevIndices.length > 0) {
          Row(ContainerCfg) {
            PDFPageSlot({
              pixelMap: this.transPrev1PixelMap,
              loading: this.transPrev1Loading,
              viewSize: this.transPrev1ViewSize,
              canvasSize: this.getCanvasSize(this.getTransitionPageIndex('prev', 0)),
              canvasScale: this.getTransitionCanvasScale('prev', 0),
              visible: this.transitionSlotVisible('prev', 0),
              drawCanvasVisible: false,
              annotateCtx: this.transPreviewAnnotateCtx,
              drawCtx: this.transPreviewDrawCtx,
              onDrawTouch: (_e: TouchEvent) => {
              },
              onDrawMouse: (_e: MouseEvent) => {
              }
            })
            PDFPageSlot({
              pixelMap: this.transPrev2PixelMap,
              loading: this.transPrev2Loading,
              viewSize: this.transPrev2ViewSize,
              canvasSize: this.getCanvasSize(this.getTransitionPageIndex('prev', 1)),
              canvasScale: this.getTransitionCanvasScale('prev', 1),
              visible: this.transitionSlotVisible('prev', 1),
              drawCanvasVisible: false,
              annotateCtx: this.transPreviewAnnotateCtx,
              drawCtx: this.transPreviewDrawCtx,
              onDrawTouch: (_e: TouchEvent) => {
              },
              onDrawMouse: (_e: MouseEvent) => {
              }
            })
            PDFPageSlot({
              pixelMap: this.transPrev3PixelMap,
              loading: this.transPrev3Loading,
              viewSize: this.transPrev3ViewSize,
              canvasSize: this.getCanvasSize(this.getTransitionPageIndex('prev', 2)),
              canvasScale: this.getTransitionCanvasScale('prev', 2),
              visible: this.transitionSlotVisible('prev', 2),
              drawCanvasVisible: false,
              annotateCtx: this.transPreviewAnnotateCtx,
              drawCtx: this.transPreviewDrawCtx,
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
          .size(toSizePx(this.getTransitionStripSizePx('prev')))
          .scale({
            x: this.viewerViewModel.viewScale,
            y: this.viewerViewModel.viewScale,
            centerX: 0,
            centerY: 0
          })
          .translate({ x: this.getPreviewStripTranslateVp('prev'), y: 0 })
          .opacity(this.getSlidePrevStripOpacity())
          .hitTestBehavior(HitTestMode.None)
        }

        if (this.transNextIndices.length > 0) {
          Row(ContainerCfg) {
            PDFPageSlot({
              pixelMap: this.transNext1PixelMap,
              loading: this.transNext1Loading,
              viewSize: this.transNext1ViewSize,
              canvasSize: this.getCanvasSize(this.getTransitionPageIndex('next', 0)),
              canvasScale: this.getTransitionCanvasScale('next', 0),
              visible: this.transitionSlotVisible('next', 0),
              drawCanvasVisible: false,
              annotateCtx: this.transPreviewAnnotateCtx,
              drawCtx: this.transPreviewDrawCtx,
              onDrawTouch: (_e: TouchEvent) => {
              },
              onDrawMouse: (_e: MouseEvent) => {
              }
            })
            PDFPageSlot({
              pixelMap: this.transNext2PixelMap,
              loading: this.transNext2Loading,
              viewSize: this.transNext2ViewSize,
              canvasSize: this.getCanvasSize(this.getTransitionPageIndex('next', 1)),
              canvasScale: this.getTransitionCanvasScale('next', 1),
              visible: this.transitionSlotVisible('next', 1),
              drawCanvasVisible: false,
              annotateCtx: this.transPreviewAnnotateCtx,
              drawCtx: this.transPreviewDrawCtx,
              onDrawTouch: (_e: TouchEvent) => {
              },
              onDrawMouse: (_e: MouseEvent) => {
              }
            })
            PDFPageSlot({
              pixelMap: this.transNext3PixelMap,
              loading: this.transNext3Loading,
              viewSize: this.transNext3ViewSize,
              canvasSize: this.getCanvasSize(this.getTransitionPageIndex('next', 2)),
              canvasScale: this.getTransitionCanvasScale('next', 2),
              visible: this.transitionSlotVisible('next', 2),
              drawCanvasVisible: false,
              annotateCtx: this.transPreviewAnnotateCtx,
              drawCtx: this.transPreviewDrawCtx,
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
          .size(toSizePx(this.getTransitionStripSizePx('next')))
          .scale({
            x: this.viewerViewModel.viewScale,
            y: this.viewerViewModel.viewScale,
            centerX: 0,
            centerY: 0
          })
          .translate({ x: this.getPreviewStripTranslateVp('next'), y: 0 })
          .opacity(this.getSlideNextStripOpacity())
          .hitTestBehavior(HitTestMode.None)
        }

        Flex()
          .size({ width: '100%', height: '100%' })
          .onAreaChange((_, newVal) => {
            this.updateMetronomeViewportFromArea(newVal);
            this.updateTunerViewportFromArea(newVal);
            this.syncPanelOverlays();
            this.viewerViewModel.setViewportSize(fromArea(newVal, this.getUIContext()));
            if (!this.shouldDeferViewportFitReset()) {
              this.resetViewToFit();
            }
          })
          .hitTestBehavior(HitTestMode.Transparent)
          .onTouch(event => this.handleViewAction(event))
          .onMouse(event => this.handleMouseEvent(event))
          .onAxisEvent(event => this.handleMouseAxisEvent(event))

        Button(PageFlipButtonOption)
          .size(PageFlipButtonSize)
          .onClick(() => this.navigatePrevPageFromSideFlipZone())
          .alignRules(TopLeft)
          .backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.Transparent)
          .visibility(toVisibility(this.viewerViewModel.pageFlipMode == 'side' && this.viewerViewModel.annotateMode == 'drag'))

        Button(PageFlipButtonOption)
          .size(PageFlipButtonSize)
          .onClick(() => this.navigateNextPageFromSideFlipZone())
          .alignRules(TopRight)
          .backgroundColor(Color.Transparent)
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
                onSaveAnnotation: () => {
                  this.annotationController.executeSave()
                    .then(() => this.syncPanelOverlays())
                    .catch((error: Error) => hilog.error(0, 'PDFView', `保存批注出错: ${error.message}`));
                }
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