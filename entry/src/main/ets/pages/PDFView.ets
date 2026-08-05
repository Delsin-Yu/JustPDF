import { ContainerCfg, ContainerPadding, ContainerSpacing, FullRect, MakeSlider, StyleIconButton, TopLeft, TopRight, toResultCode, toVisibility } from '../components/UIComponents';
import { hasUnsavedDocumentChanges, promptUnsavedChangesAction, UnsavedChangesChoice } from '../components/UnsavedChangesPrompt';
import {
  EVENT_APP_TERMINATE_REQUESTED,
  EVENT_DOCUMENT_OPEN_REQUESTED,
  isValidPendingDocumentOpenParams,
  setExitViewerOnBack,
  setPdfViewerActive,
  shouldExitViewerOnBack,
  syncPdfViewerHasUnsavedChanges,
  takePendingDocumentOpenParams
} from '../navigation/PendingDocumentOpen';
import { pdfLoadNeedsPassword, reloadPdfDocument } from '../components/PdfDocumentLoader';
import { ComponentContent, LengthMetricsUnit, OverlayManager, window } from '@kit.ArkUI';
import { pdfService } from '@kit.PDFKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fromArea, mul, pxToVp, toSizePx, Vec2, Vector2 } from '../components/Numbers';
import { preferences, uniformTypeDescriptor as utd } from '@kit.ArkData';
import { KeyCode } from '@kit.InputKit';
import { fileUri } from '@kit.CoreFileKit';
import { harmonyShare, systemShare } from '@kit.ShareKit';
import { AbilityConstant, common } from '@kit.AbilityKit';
import {
  clearContinuationReadingState,
  logAppStorageContinuationState,
  logContinuationError,
  logContinuationLine,
  logContinuationWarn,
  parseInitialPageIndexFromRouter,
  PdfContinuationPayload,
  updateContinuationReadingState
} from '../continuation/PdfContinuation';
import { ensureDistributedDataSyncPermission } from '../continuation/PdfContinuationPermission';
import {
  isContinuationPendingRouterArgs,
  parseExtraLocalPathsFromRouter,
  resolveContinuationPdfParams
} from '../continuation/PdfContinuationRestore';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { stylusInteraction } from '@kit.Penkit';
import { taskpool } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { TutorialDialogBuilder } from '../components/TutorialDialog';
import { PageCache, PageInfo, PageStore, PdfLinkAnnotation, PdfLinkRectangle } from '../components/PageInfo';
import { InputAction } from '../components/Input';
import { SettingsDialogBuilder } from '../components/SettingsDialog';
import { AnnotatePreparePhaseOptions, PDFAnnotationController } from './pdfview/PDFAnnotationController';
import { PDFMetronomeController } from './pdfview/PDFMetronomeController';
import { PDFTunerController } from './pdfview/PDFTunerController';
import { PDFLinkJumpHistory } from './pdfview/PDFLinkJumpHistory';
import { PDFLinkDisplayHitArea, PDFPageSlot } from './pdfview/PDFPageSlot';
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
import { PDFAnnotateMode, PDFLinkVisualMode, PDFPageFlipMode, PDFViewerViewModel, ViewerMinRenderScale } from './pdfview/PDFViewerViewModel';
import { AnnotateLongPressIndicator } from './pdfview/AnnotateLongPressIndicator';
import { AnnotationPaletteContentHeight, AnnotationPaletteContentWidth, PDFAnnotationPalette } from './pdfview/PDFAnnotationPalette';
import { PDFBookmarkController, PDFBookmarkListItem } from './pdfview/PDFBookmarkController';
import {
  BookmarkPanelContentHeight,
  BookmarkPanelContentWidth,
  BookmarkTitleDialogBuilder,
  getFloatingBookmarkTotalWidth,
  PDFBookmarkPanelContent
} from './pdfview/PDFBookmarkPanel';
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
} from './pdfview/PDFPanelVisualConstants';
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
const PdfLinkDebugLogEnabled: boolean = true;
const PdfLinkFadeVisibleMs: number = 500;
const PdfLinkFadeOutMs: number = 1300;
const DefaultBookmarkScale: number = 1.0;
const BookmarkMinScale: number = 0.7;
const BookmarkMaxScale: number = 1.3;
const DefaultBookmarkOffsetX: number = 24;
const DefaultBookmarkOffsetY: number = 96;

type OverlayPanelKey = 'metronome' | 'tuner' | 'bookmark';
interface FloatingPanelOffset {
  x: number;
  y: number;
}

interface PDFLinkSlotRect {
  x: number;
  y: number;
  width: number;
  height: number;
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
  readOnly: boolean;
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
  readOnly: boolean;
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
    this.readOnly = options.readOnly;
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
        readOnly: params.readOnly,
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

interface BookmarkOverlayOptions {
  showWindow: boolean;
  readOnly: boolean;
  useDocked: boolean;
  dockedTopOffsetVp: number;
  entries: PDFBookmarkListItem[];
  selectedId: string;
  hasUnsavedBookmarks: boolean;
  hostScale: number;
  hostOffset: FloatingPanelOffset;
  onSelect: (id: string) => void;
  onNavigate: (pageIndex: number) => void;
  onAddAtCurrentPage: () => void;
  onDeleteSelected: () => void;
  onRenameSelected: () => void;
  onSaveDocument: () => void;
  onClose: () => void;
  onTouchStateChanged: (active: boolean) => void;
  onWindowAreaHeightChanged: (heightVp: number) => void;
  onHostDragStart: () => void;
  onHostDragUpdate: (event: GestureEvent) => void;
  onHostDragEnd: () => void;
  onHostPinchStart: () => void;
  onHostPinchUpdate: (event: GestureEvent) => void;
  onHostPinchEnd: () => void;
}

class BookmarkOverlayParams {
  showWindow: boolean;
  readOnly: boolean;
  useDocked: boolean;
  dockedTopOffsetVp: number;
  entries: PDFBookmarkListItem[];
  selectedId: string;
  hasUnsavedBookmarks: boolean;
  hostScale: number;
  hostOffset: FloatingPanelOffset;
  onSelect: (id: string) => void;
  onNavigate: (pageIndex: number) => void;
  onAddAtCurrentPage: () => void;
  onDeleteSelected: () => void;
  onRenameSelected: () => void;
  onSaveDocument: () => void;
  onClose: () => void;
  onTouchStateChanged: (active: boolean) => void;
  onWindowAreaHeightChanged: (heightVp: number) => void;
  onHostDragStart: () => void;
  onHostDragUpdate: (event: GestureEvent) => void;
  onHostDragEnd: () => void;
  onHostPinchStart: () => void;
  onHostPinchUpdate: (event: GestureEvent) => void;
  onHostPinchEnd: () => void;

  constructor(options: BookmarkOverlayOptions) {
    this.showWindow = options.showWindow;
    this.readOnly = options.readOnly;
    this.useDocked = options.useDocked;
    this.dockedTopOffsetVp = options.dockedTopOffsetVp;
    this.entries = options.entries;
    this.selectedId = options.selectedId;
    this.hasUnsavedBookmarks = options.hasUnsavedBookmarks;
    this.hostScale = options.hostScale;
    this.hostOffset = options.hostOffset;
    this.onSelect = options.onSelect;
    this.onNavigate = options.onNavigate;
    this.onAddAtCurrentPage = options.onAddAtCurrentPage;
    this.onDeleteSelected = options.onDeleteSelected;
    this.onRenameSelected = options.onRenameSelected;
    this.onSaveDocument = options.onSaveDocument;
    this.onClose = options.onClose;
    this.onTouchStateChanged = options.onTouchStateChanged;
    this.onWindowAreaHeightChanged = options.onWindowAreaHeightChanged;
    this.onHostDragStart = options.onHostDragStart;
    this.onHostDragUpdate = options.onHostDragUpdate;
    this.onHostDragEnd = options.onHostDragEnd;
    this.onHostPinchStart = options.onHostPinchStart;
    this.onHostPinchUpdate = options.onHostPinchUpdate;
    this.onHostPinchEnd = options.onHostPinchEnd;
  }
}

@Builder
function BuildBookmarkOverlay(params: BookmarkOverlayParams) {
  Stack() {
    if (params.showWindow && !params.useDocked) {
      PDFBookmarkPanelContent({
        entries: params.entries,
        selectedId: params.selectedId,
        hasUnsavedBookmarks: params.hasUnsavedBookmarks,
        readOnly: params.readOnly,
        useDocked: false,
        dockedTopOffsetVp: 0,
        hostScale: params.hostScale,
        hostOffset: params.hostOffset,
        showDragHandle: true,
        onSelect: params.onSelect,
        onNavigate: params.onNavigate,
        onAddAtCurrentPage: params.onAddAtCurrentPage,
        onDeleteSelected: params.onDeleteSelected,
        onRenameSelected: params.onRenameSelected,
        onSave: params.onSaveDocument,
        onClose: params.onClose,
        onTouchStateChanged: params.onTouchStateChanged,
        onWindowAreaHeightChanged: params.onWindowAreaHeightChanged,
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
  /** 当前会话打开加密 PDF 的密码；不写 preferences，离开阅读页即丢弃。 */
  private sessionPdfPassword: string = '';
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
  /** 导出/写入 PDF 进行中（右上角指示，不遮挡整页） */
  @Local isDocumentSaving: boolean = false;
  @Local documentSaveMessage: string = '';
  /** 进入批注模式：扫描/导入进行中（右上角指示） */
  @Local isAnnotateModePreparing: boolean = false;
  /** 仅主线程导入/写入阶段为 true，扫描阶段用户仍可平移/绘制 */
  @Local isAnnotatePrepareBlockingEdits: boolean = false;
  @Local annotatePrepareMessage: string = '';
  /** 当前有效的批注准备会话 id；与 annotatePrepareSessionToken 不一致则中止扫描 */
  private annotatePrepareActiveToken: number = 0;
  private annotatePrepareSessionToken: number = 0;
  @Local loadError: string = '';
  @Local showPasswordGate: boolean = false;
  @Local passwordGateInput: string = '';
  @Local passwordGateErrorHint: string = '';
  private documentInitStarted: boolean = false;
  /** 跨设备接续恢复时的起始页（0-based） */
  private continuationInitialPageIndex: number = 0;
  /** 目标端：沙箱 PDF 尚未落地，需在 initializeDocument 中轮询 distributedFilesDir */
  private continuationPending: boolean = false;
  private continuationExtraLocalPaths: string[] = [];
  /** 避免翻页时重复刷接续 sync 日志 */
  private lastContinuationLoggedPageIndex: number = -1;
  private passwordPromptResolver: ((password: string | null) => void) | undefined = undefined;
  transparencyTimeoutId: number | undefined = undefined;
  windowStatusCallback: ((statusType: window.WindowStatusType) => void) | undefined = undefined;
  freeWindowModeCallback: ((isInFreeWindowMode: boolean) => void) | undefined = undefined;
  lastTouchPoint: Vector2 | undefined = undefined;
  /** 当前单指拖动手势起点，用于判断屏侧翻页是否应被平移取消 */
  panSessionStartPoint: Vector2 | undefined = undefined;
  /** 在侧栏透明按钮上抬起时，若发生过平移/捏合/滚轮缩放则置为 true，以忽略误触的翻页 */
  suppressSidePageFlipFromGesture: boolean = false;
  /** 当前触摸序列是否始于 PDF 链接热区；用于避免父级长按/侧翻与链接点击交叉触发。 */
  pdfLinkPressCandidateActive: boolean = false;
  private pdfLinkPressCandidateResetToken: number = 0;
  private linkJumpHistory: PDFLinkJumpHistory = new PDFLinkJumpHistory();
  @Local linkJumpCanGoBack: boolean = false;
  @Local linkJumpCanGoForward: boolean = false;
  @Local showLinkJumpHistory: boolean = false;
  @Local linkJumpNavRevision: number = 0;
  private sliderJumpStartPageIndex: number | undefined = undefined;
  private pdfLinkDebugState: Map<string, string> = new Map();
  @Local pdfLinkVisualOpacity: number = 0;
  private pdfLinkFadeTimeoutId: number | undefined = undefined;
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
    getOpenPassword: () => this.sessionPdfPassword,
    getSaveTempPath: () => this.saveTempPath,
    getFileName: () => this.fileName,
    getUIContext: () => this.getUIContext(),
    onRequestGotoPage: (pageIndex: number) => {
      this.gotoPage(pageIndex);
    },
    onRedrawRequested: () => {
      this.redrawStrokes();
      this.syncPanelOverlays();
    },
    onRefreshDisplayedPages: () => this.refreshDisplayedPages(),
    getPreferences: () => this.preferences,
    onSavePhase: (message: string) => {
      if (!this.isDocumentSaving) {
        this.enterDocumentReadOnlyForSave();
      }
      this.isDocumentSaving = true;
      this.documentSaveMessage = message;
    },
    onAnnotatePreparePhase: (message: string, options?: AnnotatePreparePhaseOptions) => {
      this.isAnnotateModePreparing = true;
      this.isAnnotatePrepareBlockingEdits = options?.blocksEditing === true;
      this.annotatePrepareMessage = message;
    },
    isAnnotatePrepareSessionActive: () => this.isAnnotatePrepareSessionActive()
  }, CanvasOverSampling);
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
  @Local metronomePanelScale: number = FloatingMetronomeDefaultScale;
  @Local metronomePanelOffset: FloatingPanelOffset = { x: 0, y: 0 };
  @Local metronomeViewportWidthVp: number = 0;
  @Local metronomeViewportHeightVp: number = 0;
  @Local metronomePanelHeightVp: number = 0;
  @Local useDockedTunerPanel: boolean = false;
  @Local useDockedBookmarkPanel: boolean = false;
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
  @Local bookmarkPanelScale: number = DefaultBookmarkScale;
  @Local bookmarkPanelOffset: FloatingPanelOffset = { x: DefaultBookmarkOffsetX, y: DefaultBookmarkOffsetY };
  @Local bookmarkPanelHeightVp: number = 0;
  @Local bookmarkViewportWidthVp: number = 0;
  @Local bookmarkViewportHeightVp: number = 0;
  @Local longPressProgress: number = 0;
  @Local longPressPosX: number = 0;
  @Local longPressPosY: number = 0;
  @Local longPressVisible: boolean = false;
  private longPressDelayId: number | undefined = undefined;
  private longPressAnimId: number | undefined = undefined;
  private paletteDragStartOffset: FloatingPanelOffset = { x: 0, y: 0 };
  private palettePinchStartScale: number = DefaultPaletteScale;
  private bookmarkDragStartOffset: FloatingPanelOffset = { x: DefaultBookmarkOffsetX, y: DefaultBookmarkOffsetY };
  private bookmarkPinchStartScale: number = DefaultBookmarkScale;
  private bookmarkRenameDialogController: CustomDialogController | undefined = undefined;
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
  private bookmarkOverlayContent: ComponentContent<BookmarkOverlayParams> | undefined = undefined;
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
        this.applyPdfLinkVisualMode(true);
      }
    }),
    width: '40%',
  });

  private isDocumentReadOnly(): boolean {
    return this.isDocumentSaving || this.isAnnotatePrepareBlockingEdits;
  }

  private isAnnotatePrepareSessionActive(): boolean {
    return this.annotatePrepareActiveToken > 0
      && this.annotatePrepareActiveToken === this.annotatePrepareSessionToken;
  }

  private beginAnnotatePrepareSession(): number {
    const sessionToken = ++this.annotatePrepareSessionToken;
    this.annotatePrepareActiveToken = sessionToken;
    return sessionToken;
  }

  private endAnnotatePrepareSession(sessionToken: number): void {
    if (sessionToken !== this.annotatePrepareActiveToken) {
      return;
    }
    this.annotatePrepareActiveToken = 0;
    this.isAnnotateModePreparing = false;
    this.isAnnotatePrepareBlockingEdits = false;
    this.annotatePrepareMessage = '';
  }

  private cancelAnnotatePrepareSession(): void {
    this.annotatePrepareSessionToken++;
    this.annotatePrepareActiveToken = 0;
    this.isAnnotateModePreparing = false;
    this.isAnnotatePrepareBlockingEdits = false;
    this.annotatePrepareMessage = '';
    this.annotationController.resetImportedPolylinePrepareState();
  }

  /** 保存进行中：结束批注交互并关闭批注面板，避免与写入冲突。 */
  private enterDocumentReadOnlyForSave(): void {
    this.cancelLongPress();
    const resetResult = this.annotationController.resetTransientState();
    if (resetResult.clearedDraw) {
      this.view1DrawCtx.reset();
      this.view2DrawCtx.reset();
      this.view3DrawCtx.reset();
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
        top: this.getUIContext().px2vp(this.avoidAreaTopPx) + 12,
        right: 16
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
    this.view1DrawCtx.reset();
    this.view2DrawCtx.reset();
    this.view3DrawCtx.reset();
    this.redrawStrokes();

    if (this.bookmarkController.isDirty) {
      const loadVersion = ++this.documentLoadVersion;
      const result = reloadPdfDocument(this.document, this.sandBoxPath, this.sessionPdfPassword);
      if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
        hilog.error(0, 'PDFView', `丢弃更改时重载 PDF 失败: ${toResultCode(result)}`);
        return;
      }
      if (this.documentLoadVersion !== loadVersion) {
        return;
      }
      const totalPages = this.pageDataSource.totalCount();
      for (let i = 0; i < totalPages; i++) {
        this.pageDataSource.getData(i).evictViewerCache();
        this.pageDataSource.getData(i).invalidateCaches();
      }
      this.pageDataSource.resetAllPdfPageHandles();
      this.pageDataSource.clearImportedPdfPolylineTracking();
      this.annotationController.resetImportedPolylinePrepareState();
      this.pageDataSource.setPagePath(this.sandBoxPath);
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
        url: 'pages/PDFView',
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
    this.disableContinuationForMigration();
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
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' }).catch(() => {
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
          this.applyPdfLinkVisualMode(true);
        }
      }),
      width: '40%'
    });
  }

  private updatePanelDocking(windowWidthPx: number): void {
    this.lastWindowWidthPx = windowWidthPx;
    const metronomeTotalWidthPx = this.getUIContext().vp2px(getFloatingMetronomeTotalWidth(this.metronomePanelScale));
    const tunerTotalWidthPx = this.getUIContext().vp2px(getFloatingTunerTotalWidth(this.tunerPanelScale));
    const bookmarkTotalWidthPx = this.getUIContext().vp2px(getFloatingBookmarkTotalWidth(this.bookmarkPanelScale));
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

    const nextBookmarkOffset = this.getClampedBookmarkOffset();
    if (Math.abs(nextBookmarkOffset.x - this.bookmarkPanelOffset.x) >= 0.001
      || Math.abs(nextBookmarkOffset.y - this.bookmarkPanelOffset.y) >= 0.001) {
      this.bookmarkPanelOffset = nextBookmarkOffset;
      this.bookmarkDragStartOffset = { x: nextBookmarkOffset.x, y: nextBookmarkOffset.y };
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
    this.continuationInitialPageIndex = parseInitialPageIndexFromRouter(args);
    this.continuationPending = isContinuationPendingRouterArgs(args);
    this.continuationExtraLocalPaths = parseExtraLocalPathsFromRouter(args);
    logContinuationLine(
      `PDFView.aboutToAppear fileName=${this.fileName}, sandboxLen=${this.sandBoxPath.length}, ` +
      `continuationPending=${this.continuationPending}, ` +
      `continuationInitialPageIndex=${this.continuationInitialPageIndex}`
    );
    if (this.sandBoxPath.length > 0) {
      updateContinuationReadingState(
        this.sandBoxPath,
        this.systemPath,
        this.fileName,
        this.continuationInitialPageIndex
      );
    }

    // Lightweight setup that won't block the UI
    try {
      this.viewerViewModel.loadPreferences(this.preferences);
      this.applyPdfLinkVisualMode(false);
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
        this.updateBookmarkViewport(_windowSize);
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
    if (!this.documentInitStarted) {
      this.documentInitStarted = true;
      this.initializeDocument();
    }
    this.enableContinuationForMigration();
    this.immersiveListening();
  }

  private enableContinuationForMigration(): void {
    logContinuationLine('PDFView.onPageShow -> setMissionContinueState(ACTIVE)');
    logAppStorageContinuationState('PDFView.onPageShow.进入');
    try {
      const abilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      void ensureDistributedDataSyncPermission(abilityContext, true);
      abilityContext.setMissionContinueState(AbilityConstant.ContinueState.ACTIVE, (result) => {
        if (result.code !== 0) {
          logContinuationWarn(`setMissionContinueState(ACTIVE) 失败 code=${result.code}, msg=${result.message ?? ''}`);
        } else {
          logContinuationLine('setMissionContinueState(ACTIVE) 成功');
        }
      });
    } catch (error) {
      logContinuationError(`setMissionContinueState(ACTIVE) 异常: ${error}`);
    }
  }

  private disableContinuationForMigration(): void {
    logContinuationLine('PDFView.aboutToDisappear -> setMissionContinueState(INACTIVE)');
    try {
      const abilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      abilityContext.setMissionContinueState(AbilityConstant.ContinueState.INACTIVE, (result) => {
        if (result.code !== 0) {
          logContinuationWarn(`setMissionContinueState(INACTIVE) 失败 code=${result.code}`);
        } else {
          logContinuationLine('setMissionContinueState(INACTIVE) 成功');
        }
      });
    } catch (error) {
      logContinuationError(`setMissionContinueState(INACTIVE) 异常: ${error}`);
    }
  }

  private syncContinuationReadingState(): void {
    if (this.isDocumentLoading) {
      logContinuationWarn('syncContinuationReadingState 跳过：文档仍在加载');
      return;
    }
    if (this.sandBoxPath.length === 0) {
      logContinuationWarn('syncContinuationReadingState 跳过：sandBoxPath 为空');
      return;
    }
    const pageIndex = this.viewerViewModel.currentPageIndex;
    updateContinuationReadingState(
      this.sandBoxPath,
      this.systemPath,
      this.fileName,
      pageIndex
    );
    if (pageIndex !== this.lastContinuationLoggedPageIndex) {
      this.lastContinuationLoggedPageIndex = pageIndex;
      logContinuationLine(`syncContinuationReadingState pageIndex=${pageIndex}, fileName=${this.fileName}`);
      logAppStorageContinuationState('PDFView.sync后');
    }
  }

  private async initializeDocument(): Promise<void> {
    this.loadError = '';
    this.sessionPdfPassword = '';
    this.cancelAnnotatePrepareSession();
    const loadVersion = ++this.documentLoadVersion;

    if (this.continuationPending) {
      this.continuationPending = false;
      const abilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const syncGranted = await ensureDistributedDataSyncPermission(abilityContext, true);
      if (!syncGranted) {
        if (this.documentLoadVersion === loadVersion) {
          this.loadError = '需要「分布式数据同步」权限才能完成跨设备接续';
          this.isDocumentLoading = false;
        }
        return;
      }
      const payload: PdfContinuationPayload = {
        fileRef: this.systemPath,
        pageIndex: this.continuationInitialPageIndex,
        fileName: this.fileName
      };
      logContinuationLine('initializeDocument 接续目标端，等待分布式 PDF 落地');
      const resolved = await resolveContinuationPdfParams(
        abilityContext,
        payload,
        this.continuationExtraLocalPaths
      );
      if (this.documentLoadVersion !== loadVersion) {
        return;
      }
      if (resolved === null) {
        this.loadError =
          '接续文件尚未到达本机。请确认双端同一华为账号、已开启 Wi‑Fi/蓝牙与系统「接续」，并已授予分布式同步权限。';
        this.isDocumentLoading = false;
        return;
      }
      this.systemPath = resolved['systemPath'];
      this.sandBoxPath = resolved['sandboxPath'];
      this.saveTempPath = resolved['saveTempPath'];
      this.fileName = resolved['fileName'];
      logContinuationLine(`initializeDocument 接续文件已落地 sandbox=${this.sandBoxPath}`);
    }

    const loaded = await this.loadDocumentWithPasswordPrompt(loadVersion);
    if (!loaded) {
      return;
    }
    if (this.documentLoadVersion != loadVersion) {
      return;
    }
    this.viewerViewModel.setTotalPageCount(this.document.getPageCount());
    for (let i = 0; i < this.viewerViewModel.totalPageCount; i++) {
      this.pageDataSource.push(new PageInfo(i, this.document, this.sandBoxPath, this.sessionPdfPassword));
    }

    await this.createPlaceholderPixelMap();
    let startPage = this.continuationInitialPageIndex;
    if (startPage >= this.viewerViewModel.totalPageCount) {
      const clamped = this.viewerViewModel.getLastNavigableIndex();
      logContinuationWarn(
        `initializeDocument 起始页 ${startPage} 超出总页数 ${this.viewerViewModel.totalPageCount}，改为 ${clamped}`
      );
      startPage = clamped;
    }
    this.clearLinkJumpHistory();
    logContinuationLine(`initializeDocument gotoPage startPage=${startPage}, totalPages=${this.viewerViewModel.totalPageCount}`);
    await this.gotoPage(startPage, false, false);
    this.syncContinuationReadingState();
    this.bookmarkController.refresh();
    this.isDocumentLoading = false;
    this.triggerPageFlipShadeIntro();
    this.startTransparencyTimeout();
  }

  /**
   * 尝试加载 PDF；若加密则循环弹出密码框直至成功或用户取消。
   * 密码仅保存在 sessionPdfPassword，不写入 preferences。
   */
  private async loadDocumentWithPasswordPrompt(loadVersion: number): Promise<boolean> {
    let password = '';
    let passwordErrorHint = '';

    while (true) {
      const result = password.length === 0
        ? this.document.loadDocument(this.sandBoxPath, '')
        : reloadPdfDocument(this.document, this.sandBoxPath, password);

      if (result === pdfService.ParseResult.PARSE_SUCCESS) {
        this.sessionPdfPassword = password;
        return true;
      }

      if (!pdfLoadNeedsPassword(result, this.sandBoxPath)) {
        const resultText = toResultCode(result);
        hilog.error(0, 'PDFView', `加载 PDF 文件出错: ${resultText}`);
        if (this.documentLoadVersion === loadVersion) {
          this.loadError = `无法加载 PDF 文件: ${resultText}`;
          this.isDocumentLoading = false;
        }
        return false;
      }

      if (result === pdfService.ParseResult.PARSE_ERROR_PASSWORD) {
        try {
          this.document.releaseDocument();
        } catch (_e) {
          /* ignore */
        }
      }

      if (this.documentLoadVersion !== loadVersion) {
        return false;
      }

      const entered = await this.waitForPasswordGateInput(passwordErrorHint);

      if (entered === null) {
        if (this.documentLoadVersion === loadVersion) {
          this.isDocumentLoading = false;
          this.requestLeaveViewer();
        }
        return false;
      }

      password = entered;
      passwordErrorHint = '密码错误，请重试';
    }
  }

  /** 在阅读页内嵌密码门（不用 CustomDialog，避免页面未完成构建时 open 崩溃）。 */
  private waitForPasswordGateInput(errorHint: string): Promise<string | null> {
    return new Promise<string | null>((resolve) => {
      this.passwordGateInput = '';
      this.passwordGateErrorHint = errorHint;
      this.showPasswordGate = true;
      this.passwordPromptResolver = resolve;
    });
  }

  private resolvePasswordGate(password: string | null): void {
    this.showPasswordGate = false;
    const resolver = this.passwordPromptResolver;
    this.passwordPromptResolver = undefined;
    resolver?.(password);
  }

  private confirmPasswordGate(): void {
    this.resolvePasswordGate(this.passwordGateInput);
  }

  private cancelPasswordGate(): void {
    this.resolvePasswordGate(null);
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
        if (this.passwordGateErrorHint.length > 0) {
          Text(this.passwordGateErrorHint)
            .fontSize(13)
            .fontColor(ModalErrorTextColor)
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        TextInput({ text: this.passwordGateInput, placeholder: '密码' })
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
            this.passwordGateInput = value;
          })
          .onSubmit((_enterKey: EnterKeyType, _event: SubmitEvent) => {
            this.confirmPasswordGate();
          })
        Row({ space: 12 }) {
          Button('取消')
            .type(ButtonType.Capsule)
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .fontColor(ModalTitleTextColor)
            .backgroundColor(ModalButtonSecondaryColor)
            .onClick(() => this.cancelPasswordGate())
          Button('确定')
            .type(ButtonType.Capsule)
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(ModalTitleTextColor)
            .backgroundColor(ModalButtonPrimaryColor)
            .onClick(() => this.confirmPasswordGate())
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
    this.sessionPdfPassword = '';
    this.resolvePasswordGate(null);
    this.documentInitStarted = false;
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

    // 清除透明度定时器
    if (this.transparencyTimeoutId) {
      clearTimeout(this.transparencyTimeoutId);
      this.transparencyTimeoutId = undefined;
    }
    this.clearPdfLinkFadeTimeout();
    this.clearLinkJumpHistory();

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
    if (!this.sandBoxPath || this.isDocumentLoading) {
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
      void this.gotoPage(t, true, false);
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

  private clampSlideTuning(value: number, lo: number, hi: number): number {
    return Math.max(lo, Math.min(hi, value));
  }

  /** -1（钝）～+1（敏），由设置中 0～10 档映射 */
  private getHorizontalSlideSensK(): number {
    const level = this.clampSlideTuning(this.viewerViewModel.horizontalSlideSensitivity, 0, 10);
    return (level - 5) / 5;
  }

  private getSlideDragGainEff(): number {
    const k = this.getHorizontalSlideSensK();
    return this.clampSlideTuning(PAGE_TURN_DRAG_GAIN * (1 + 0.28 * k), 1.12, 1.98);
  }

  private getSlideCommitRatioSlowEff(): number {
    const k = this.getHorizontalSlideSensK();
    return this.clampSlideTuning(PAGE_TURN_COMMIT_RATIO_SLOW * (1 - 0.35 * k), 0.13, 0.34);
  }

  private getSlideCommitRatioFastEff(): number {
    const k = this.getHorizontalSlideSensK();
    return this.clampSlideTuning(PAGE_TURN_COMMIT_RATIO_FAST * (1 - 0.45 * k), 0.034, 0.12);
  }

  private getSlideSpeedRefVpPerMsEff(): number {
    const k = this.getHorizontalSlideSensK();
    return this.clampSlideTuning(0.52 * (1 - 0.22 * k), 0.36, 0.64);
  }

  private getSlideFlickVpPerMsEff(): number {
    const k = this.getHorizontalSlideSensK();
    return this.clampSlideTuning(PAGE_TURN_FLICK_VP_PER_MS * (1 - 0.34 * k), 0.25, 0.58);
  }

  private getSlideFlickMinProgressEff(): number {
    const k = this.getHorizontalSlideSensK();
    return this.clampSlideTuning(PAGE_TURN_FLICK_MIN_PROGRESS * (1 - 0.34 * k), 0.022, 0.058);
  }

  /** 速度越快，所需 |offset|/viewport 比例越低；单位 vp/ms */
  private getDynamicCommitProgressThreshold(speedVpPerMs: number): number {
    const refV = this.getSlideSpeedRefVpPerMsEff();
    const fast = this.getSlideCommitRatioFastEff();
    const slow = this.getSlideCommitRatioSlowEff();
    const s = Math.min(1, Math.abs(speedVpPerMs) / refV);
    return fast + (slow - fast) * (1 - s);
  }

  private shouldFlickCommit(direction: number, progress: number): boolean {
    if (progress < this.getSlideFlickMinProgressEff()) {
      return false;
    }
    const v = this.slideVelocityVpPerMs;
    const flick = this.getSlideFlickVpPerMsEff();
    if (direction === -1) {
      return v <= -flick;
    }
    if (direction === 1) {
      return v >= flick;
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
      this.applyElasticPageTurnOffset(firstHorizDeltaVp * this.getSlideDragGainEff(), viewportWvp);
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
        this.pageTurnOffsetVp + dvp.x * this.getSlideDragGainEff(),
        viewportWvp
      );
      const now = Date.now();
      if (this.lastSlideSampleTimeMs > 0) {
        const dtMs = Math.max(1, now - this.lastSlideSampleTimeMs);
        const instVpPerMs = (dvp.x * this.getSlideDragGainEff()) / dtMs;
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
      void this.gotoPage(targetPage, true, false);
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
        void this.gotoPage(targetPage, true, false);
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

  private pdfRectToSlotRect(rect: PdfLinkRectangle, rawPageSize: Vector2, viewSize: Vector2): PDFLinkSlotRect | undefined {
    if (rawPageSize.x <= 0 || rawPageSize.y <= 0 || viewSize.x <= 0 || viewSize.y <= 0) {
      return undefined;
    }
    if (!Number.isFinite(rect.left) || !Number.isFinite(rect.right) ||
      !Number.isFinite(rect.bottom) || !Number.isFinite(rect.top)) {
      return undefined;
    }

    const left = Math.min(rect.left, rect.right);
    const right = Math.max(rect.left, rect.right);
    const bottom = Math.min(rect.bottom, rect.top);
    const top = Math.max(rect.bottom, rect.top);
    const x = left / rawPageSize.x * viewSize.x;
    const y = (1 - top / rawPageSize.y) * viewSize.y;
    const width = (right - left) / rawPageSize.x * viewSize.x;
    const height = (top - bottom) / rawPageSize.y * viewSize.y;

    if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(width) || !Number.isFinite(height) ||
      width <= 0 || height <= 0) {
      return undefined;
    }
    return { x: x, y: y, width: width, height: height };
  }

  private logPdfLinkDebug(key: string, message: string): void {
    if (!PdfLinkDebugLogEnabled) {
      return;
    }
    const previous = this.pdfLinkDebugState.get(key);
    if (previous === message) {
      return;
    }
    this.pdfLinkDebugState.set(key, message);
    hilog.info(0, 'PDFView', `PDFLinkDebug[${key}] ${message}`);
  }

  private clearPdfLinkFadeTimeout(): void {
    if (this.pdfLinkFadeTimeoutId !== undefined) {
      clearTimeout(this.pdfLinkFadeTimeoutId);
      this.pdfLinkFadeTimeoutId = undefined;
    }
  }

  private applyPdfLinkVisualMode(showForCurrentPage: boolean): void {
    this.clearPdfLinkFadeTimeout();
    if (this.viewerViewModel.linkVisualMode === 'hidden') {
      this.pdfLinkVisualOpacity = 0;
      return;
    }
    if (this.viewerViewModel.linkVisualMode === 'always') {
      this.pdfLinkVisualOpacity = 1;
      return;
    }
    if (showForCurrentPage) {
      this.triggerPdfLinkVisualPageEnter();
    } else {
      this.pdfLinkVisualOpacity = 0;
    }
  }

  private triggerPdfLinkVisualPageEnter(): void {
    this.clearPdfLinkFadeTimeout();
    if (this.viewerViewModel.linkVisualMode === 'hidden') {
      this.pdfLinkVisualOpacity = 0;
      return;
    }
    if (this.viewerViewModel.linkVisualMode === 'always') {
      this.pdfLinkVisualOpacity = 1;
      return;
    }

    this.pdfLinkVisualOpacity = 1;
    this.pdfLinkFadeTimeoutId = setTimeout(() => {
      this.pdfLinkFadeTimeoutId = undefined;
      this.getUIContext().animateTo({
        duration: PdfLinkFadeOutMs,
        curve: Curve.EaseOut
      }, () => {
        this.pdfLinkVisualOpacity = 0;
      });
    }, PdfLinkFadeVisibleMs);
  }

  private getLinkOverlayRenderDisabledReason(): string {
    if (this.viewerViewModel.annotateMode !== 'drag') {
      return `annotateMode=${this.viewerViewModel.annotateMode}`;
    }
    if (this.isDocumentLoading) {
      return 'documentLoading';
    }
    if (this.isDocumentReadOnly()) {
      return 'documentReadOnly';
    }
    if (this.isAnnotateModePreparing) {
      return 'annotatePreparing';
    }
    if (this.isPanelGestureActive) {
      return 'panelGestureActive';
    }
    return '';
  }

  private getLinkOverlayDisabledReason(): string {
    const renderReason = this.getLinkOverlayRenderDisabledReason();
    if (renderReason.length > 0) {
      return renderReason;
    }
    if (this.pageTurnDragActive) {
      return 'pageTurnDragActive';
    }
    if (this.pageTurnCommitAnimating) {
      return 'pageTurnCommitAnimating';
    }
    if (this.slideGotoInFlight) {
      return 'slideGotoInFlight';
    }
    if (this.pendingSlideGotoTarget !== undefined) {
      return `pendingSlideGotoTarget=${this.pendingSlideGotoTarget}`;
    }
    if (Math.abs(this.pageTurnOffsetVp) >= 0.001) {
      return `pageTurnOffsetVp=${this.pageTurnOffsetVp}`;
    }
    if (this.transPrevIndices.length > 0 || this.transNextIndices.length > 0) {
      return `transitionStrips=prev${this.transPrevIndices.length}/next${this.transNextIndices.length}`;
    }
    return '';
  }

  private getPdfLinkActivationDisabledReason(): string {
    const overlayReason = this.getLinkOverlayDisabledReason();
    if (overlayReason.length > 0) {
      return overlayReason;
    }
    if (this.view1Loading || this.view2Loading || this.view3Loading) {
      return `slotLoading=${this.view1Loading}/${this.view2Loading}/${this.view3Loading}`;
    }
    if (this.isDualFingerActive) {
      return 'dualFingerActive';
    }
    return '';
  }

  private isMainSlotCommittedVisible(viewIndex: number): boolean {
    if (viewIndex < 0 || viewIndex >= this.viewerViewModel.displayedPageIndices.length) {
      return false;
    }
    if (viewIndex === 1) {
      return this.viewerViewModel.shouldShowSecondSlot();
    }
    if (viewIndex === 2) {
      return this.viewerViewModel.shouldShowThirdSlot();
    }
    return viewIndex === 0;
  }

  private getMainSlotViewSize(viewIndex: number): Vector2 {
    if (viewIndex === 0) {
      return this.view1ViewSize;
    }
    if (viewIndex === 1) {
      return this.view2ViewSize;
    }
    if (viewIndex === 2) {
      return this.view3ViewSize;
    }
    return Vec2(0, 0);
  }

  private getLinkHitAreasForSlot(viewIndex: number): PDFLinkDisplayHitArea[] {
    if (!this.isMainSlotCommittedVisible(viewIndex)) {
      return [];
    }

    const pageIndex = this.viewerViewModel.displayedPageIndices[viewIndex];
    if (pageIndex === undefined || pageIndex < 0 || pageIndex >= this.pageDataSource.totalPageCount()) {
      return [];
    }

    const viewSize = this.getMainSlotViewSize(viewIndex);
    const rawPageSize = this.pageDataSource.getPageRawSize(pageIndex);
    const links = this.pageDataSource.getPageLinks(pageIndex);
    const hitAreas: PDFLinkDisplayHitArea[] = [];
    for (let i = 0; i < links.length; i++) {
      const link: PdfLinkAnnotation = links[i];
      const slotRect = this.pdfRectToSlotRect(link.rect, rawPageSize, viewSize);
      if (slotRect === undefined) {
        this.logPdfLinkDebug(`slot-${viewIndex}-link-${i}`, `skip invalid display rect: page=${pageIndex}, raw=(${rawPageSize.x},${rawPageSize.y}), view=(${viewSize.x},${viewSize.y}), pdfRect=(${link.rect.left},${link.rect.bottom},${link.rect.right},${link.rect.top})`);
        continue;
      }
      hitAreas.push({
        id: `${pageIndex}-${link.uniqueId ?? i}-${slotRect.x}-${slotRect.y}-${slotRect.width}-${slotRect.height}`,
        x: slotRect.x,
        y: slotRect.y,
        width: slotRect.width,
        height: slotRect.height,
        target: link.target
      });
    }
    const overlayReason = this.getLinkOverlayRenderDisabledReason();
    this.logPdfLinkDebug(
      `slot-${viewIndex}`,
      `page=${pageIndex}, raw=(${rawPageSize.x},${rawPageSize.y}), view=(${viewSize.x},${viewSize.y}), links=${links.length}, hitAreas=${hitAreas.length}, overlay=${overlayReason.length === 0 ? 'enabled' : `disabled:${overlayReason}`}`
    );
    return hitAreas;
  }

  private isLinkOverlayEnabled(): boolean {
    return this.getLinkOverlayRenderDisabledReason().length === 0;
  }

  private isPdfLinkActivationAllowed(): boolean {
    return this.getPdfLinkActivationDisabledReason().length === 0;
  }

  private handlePdfLinkPressStart(hitArea: PDFLinkDisplayHitArea): void {
    const disabledReason = this.getPdfLinkActivationDisabledReason();
    if (disabledReason.length > 0) {
      hilog.info(0, 'PDFView', `PDF 链接按下被忽略: id=${hitArea.id}, reason=${disabledReason}`);
      return;
    }
    this.pdfLinkPressCandidateResetToken++;
    this.pdfLinkPressCandidateActive = true;
    this.cancelLongPress();
    this.suppressSidePageFlipFromGesture = true;
    hilog.info(0, 'PDFView', `PDF 链接按下候选开始: id=${hitArea.id}, target=${hitArea.target.kind}`);
  }

  private handlePdfLinkPressCancel(hitArea: PDFLinkDisplayHitArea): void {
    this.pdfLinkPressCandidateResetToken++;
    this.pdfLinkPressCandidateActive = false;
    this.cancelLongPress();
    hilog.info(0, 'PDFView', `PDF 链接按下候选取消: id=${hitArea.id}`);
  }

  private cancelPdfLinkPressCandidateForDrag(dx: number, dy: number): void {
    if (!this.pdfLinkPressCandidateActive) {
      return;
    }
    this.pdfLinkPressCandidateResetToken++;
    this.pdfLinkPressCandidateActive = false;
    this.cancelLongPress();
    // Keep side-flip suppressed for this sequence: a drag that began on a link should not flip on release.
    this.suppressSidePageFlipFromGesture = true;
    hilog.info(0, 'PDFView', `PDF 链接按下候选因拖动取消: dx=${dx}, dy=${dy}`);
  }

  private schedulePdfLinkPressCandidateReset(): void {
    const token = ++this.pdfLinkPressCandidateResetToken;
    setTimeout(() => {
      if (this.pdfLinkPressCandidateResetToken === token) {
        this.pdfLinkPressCandidateActive = false;
      }
    }, 0);
  }

  private canActivatePdfLinkFromCurrentGesture(): boolean {
    return this.pdfLinkPressCandidateActive && this.isPdfLinkActivationAllowed();
  }

  private openExternalPdfLinkUri(uri: string): void {
    const targetUri = uri.trim();
    const lowerUri = targetUri.toLowerCase();
    if (!lowerUri.startsWith('http://') && !lowerUri.startsWith('https://')) {
      hilog.warn(0, 'PDFView', `忽略不支持的 PDF 链接 URI: ${uri}`);
      return;
    }

    try {
      const abilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      abilityContext.openLink(targetUri)
        .catch((error: BusinessError) => {
          hilog.error(0, 'PDFView', `打开 PDF 外部链接失败: ${error.code} ${error.message}`);
        });
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0, 'PDFView', `打开 PDF 外部链接异常: ${err.code} ${err.message}`);
    }
  }

  private activatePdfLink(hitArea: PDFLinkDisplayHitArea): void {
    if (!this.canActivatePdfLinkFromCurrentGesture()) {
      hilog.info(0, 'PDFView', `PDF 链接激活被忽略: id=${hitArea.id}, candidate=${this.pdfLinkPressCandidateActive}, reason=${this.getPdfLinkActivationDisabledReason()}`);
      this.pdfLinkPressCandidateResetToken++;
      this.pdfLinkPressCandidateActive = false;
      return;
    }
    this.pdfLinkPressCandidateResetToken++;
    this.pdfLinkPressCandidateActive = false;
    this.cancelLongPress();
    this.suppressSidePageFlipFromGesture = true;

    const target = hitArea.target;
    if (target.kind === 'gotoPage') {
      hilog.info(0, 'PDFView', `PDF 链接激活: gotoPage=${target.pageIndex}, id=${hitArea.id}`);
      void this.gotoPage(target.pageIndex);
      return;
    }
    if (target.kind === 'uri') {
      hilog.info(0, 'PDFView', `PDF 链接激活: uri=${target.uri}, id=${hitArea.id}`);
      this.openExternalPdfLinkUri(target.uri);
      return;
    }
    hilog.warn(0, 'PDFView', '忽略未知 PDF 链接目标。');
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

  async gotoPage(targetIndex: number, deferSlideVisualReset: boolean = false, recordJumpHistory: boolean = true): Promise<void> {
    this.pendingSlideGotoTarget = undefined;
    if (targetIndex < 0 || targetIndex >= this.viewerViewModel.totalPageCount) {
      if (deferSlideVisualReset) {
        this.resetHorizontalSlidePreview();
        this.slideGotoInFlight = false;
      }
      return;
    }

    const clampedTarget = Math.max(0, Math.min(targetIndex, Math.max(0, this.viewerViewModel.totalPageCount - 1)));
    if (recordJumpHistory) {
      this.recordLinkJumpHistory(this.viewerViewModel.currentPageIndex, clampedTarget);
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
    this.triggerPdfLinkVisualPageEnter();
    this.mainSlotPagesBeingLoaded = [];
    this.syncContinuationReadingState();
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
    this.gotoPage(this.viewerViewModel.navigateToPreviousPage(), false, false);
  }

  navigateNextPage(): void {
    this.gotoPage(this.viewerViewModel.navigateToNextPage(), false, false);
  }

  private syncLinkJumpNavState(): void {
    this.linkJumpCanGoBack = this.linkJumpHistory.canGoBack();
    this.linkJumpCanGoForward = this.linkJumpHistory.canGoForward();
    this.showLinkJumpHistory = this.linkJumpCanGoBack || this.linkJumpCanGoForward;
    this.linkJumpNavRevision++;
  }

  private clearLinkJumpHistory(): void {
    this.linkJumpHistory.clear();
    this.syncLinkJumpNavState();
  }

  private recordLinkJumpHistory(fromPageIndex: number, toPageIndex: number): void {
    this.linkJumpHistory.recordJump(fromPageIndex, toPageIndex);
    this.syncLinkJumpNavState();
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
        this.recordLinkJumpHistory(fromPage, newValue);
      });
      return;
    }
    void this.gotoPage(newValue, false, false);
  }

  private navigatePdfLinkBack(): void {
    const target = this.linkJumpHistory.popBack(this.viewerViewModel.currentPageIndex);
    if (target === undefined) {
      return;
    }
    this.syncLinkJumpNavState();
    void this.gotoPage(target, false, false).then(() => this.syncLinkJumpNavState());
  }

  private navigatePdfLinkForward(): void {
    const target = this.linkJumpHistory.popForward(this.viewerViewModel.currentPageIndex);
    if (target === undefined) {
      return;
    }
    this.syncLinkJumpNavState();
    void this.gotoPage(target, false, false).then(() => this.syncLinkJumpNavState());
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
          this.interruptHorizontalSlideForNewTouch();
        }
        const startedOnPdfLink = this.pdfLinkPressCandidateActive;
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
            this.cancelPdfLinkPressCandidateForDrag(sx, sy);
          }
        }
        if (this.longPressTouchDown && this.lastTouchPoint !== undefined) {
          const dx = touchPoint.x - this.longPressPosX;
          const dy = touchPoint.y - this.longPressPosY;
          if (Math.sqrt(dx * dx + dy * dy) > LONG_PRESS_MOVE_THRESHOLD) {
            this.cancelLongPress();
          }
        }
        if (this.pdfLinkPressCandidateActive) {
          this.cancelLongPress();
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
      } else if (event.type == TouchType.Up || event.type === TouchType.Cancel) {
        this.cancelLongPress();
        if (this.viewerViewModel.pageFlipMode === 'horizontalSlide') {
          this.finalizeHorizontalSlideOnUp();
        }
        this.lastTouchPoint = undefined;
        this.panSessionStartPoint = undefined;
        this.schedulePdfLinkPressCandidateReset();
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
      this.schedulePdfLinkPressCandidateReset();
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
    if (this.isDocumentSaving) {
      return;
    }
    if (this.isAnnotateModePreparing) {
      return;
    }
    this.viewerViewModel.openAnnotatePalette(explicitTool);
    this.initPalettePosition();
    this.syncPanelOverlays();

    if (this.annotationController.isImportedPolylinePrepared()) {
      return;
    }

    const sessionToken = this.beginAnnotatePrepareSession();
    this.isAnnotateModePreparing = true;
    this.annotatePrepareMessage = '正在准备批注模式…';
    void this.annotationController.prepareImportedPolylineAnnotations()
      .then(() => this.syncPanelOverlays())
      .catch((error: Error) => hilog.error(0, 'PDFView', `导入已有折线批注出错: ${error.message}`))
      .finally(() => {
        this.endAnnotatePrepareSession(sessionToken);
        this.syncPanelOverlays();
      });
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
      readOnly: this.isDocumentReadOnly(),
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

  private getClampedBookmarkOffset(offset: FloatingPanelOffset = this.bookmarkPanelOffset): FloatingPanelOffset {
    if (this.useDockedBookmarkPanel) {
      return { x: 0, y: 0 };
    }
    const scaledW = getFloatingBookmarkTotalWidth(this.bookmarkPanelScale);
    const scaledH = (this.bookmarkPanelHeightVp > 0 ? this.bookmarkPanelHeightVp : BookmarkPanelContentHeight)
      * this.bookmarkPanelScale;
    const viewportWidthVp = this.bookmarkViewportWidthVp > 0
      ? this.bookmarkViewportWidthVp
      : this.getUIContext().px2vp(this.viewerViewModel.viewportSize.x);
    const viewportHeightVp = this.bookmarkViewportHeightVp > 0
      ? this.bookmarkViewportHeightVp
      : this.getUIContext().px2vp(this.viewerViewModel.viewportSize.y);
    const minY = this.getFloatingBookmarkMinYVp();
    const maxX = viewportWidthVp - scaledW - FloatingPanelMarginVp;
    const maxY = viewportHeightVp - scaledH - FloatingPanelMarginVp;
    return {
      x: Math.max(0, Math.min(offset.x, Math.max(0, maxX))),
      y: Math.max(minY, Math.min(offset.y, Math.max(minY, maxY)))
    };
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
    this.focusPanel('bookmark');
    this.isPanelGestureActive = true;
    const clampedOffset = this.getClampedBookmarkOffset();
    this.bookmarkPanelOffset = clampedOffset;
    this.bookmarkDragStartOffset = { x: clampedOffset.x, y: clampedOffset.y };
    this.syncPanelOverlays();
  }

  private handleBookmarkHostDragUpdate(event: GestureEvent): void {
    this.bookmarkPanelOffset = this.getClampedBookmarkOffset({
      x: this.bookmarkDragStartOffset.x + event.offsetX * this.bookmarkPanelScale,
      y: this.bookmarkDragStartOffset.y + event.offsetY * this.bookmarkPanelScale
    });
    this.syncPanelOverlays();
  }

  private handleBookmarkHostDragEnd(): void {
    this.isPanelGestureActive = false;
    this.syncPanelOverlays();
  }

  private handleBookmarkHostPinchStart(): void {
    this.isPanelGestureActive = true;
    this.bookmarkPinchStartScale = this.bookmarkPanelScale;
  }

  private handleBookmarkHostPinchUpdate(event: GestureEvent): void {
    this.bookmarkPanelScale = Math.max(BookmarkMinScale, Math.min(BookmarkMaxScale, this.bookmarkPinchStartScale * event.scale));
    this.bookmarkPanelOffset = this.getClampedBookmarkOffset();
    this.syncPanelOverlays();
  }

  private handleBookmarkHostPinchEnd(): void {
    this.bookmarkPinchStartScale = this.bookmarkPanelScale;
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
    return new BookmarkOverlayParams({
      showWindow: this.viewerViewModel.isBookmarkPanelVisible,
      readOnly: this.isDocumentReadOnly(),
      useDocked: this.useDockedBookmarkPanel,
      dockedTopOffsetVp: 0,
      entries: this.bookmarkController.entries,
      selectedId: this.bookmarkController.selectedId,
      hasUnsavedBookmarks: this.bookmarkController.isDirty,
      hostScale: this.useDockedBookmarkPanel ? 1 : this.bookmarkPanelScale,
      hostOffset: this.getClampedBookmarkOffset(),
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
      onHostDragStart: () => this.handleBookmarkHostDragStart(),
      onHostDragUpdate: (event: GestureEvent) => this.handleBookmarkHostDragUpdate(event),
      onHostDragEnd: () => this.handleBookmarkHostDragEnd(),
      onHostPinchStart: () => this.handleBookmarkHostPinchStart(),
      onHostPinchUpdate: (event: GestureEvent) => this.handleBookmarkHostPinchUpdate(event),
      onHostPinchEnd: () => this.handleBookmarkHostPinchEnd()
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
      this.view1DrawCtx.reset();
      this.view2DrawCtx.reset();
      this.view3DrawCtx.reset();
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
            pixelMap: this.view1PixelMap,
            loading: this.view1Loading,
            viewSize: this.view1ViewSize,
            canvasSize: this.getCanvasSize(this.viewerViewModel.displayedPageIndices[0] ?? 0),
            canvasScale: this.getCanvasScale(0),
            visible: true,
            drawCanvasVisible: this.viewerViewModel.annotateMode !== 'drag' && !this.isDocumentReadOnly(),
            annotateCtx: this.view1Ctx,
            drawCtx: this.view1DrawCtx,
            onDrawTouch: (event: TouchEvent) => this.handleDrawTouch(this.view1DrawCtx, this.view1Ctx, this.viewerViewModel.displayedPageIndices[0] ?? 0, event),
            onDrawMouse: (event: MouseEvent) => this.handleDrawMouse(this.view1DrawCtx, this.view1Ctx, this.viewerViewModel.displayedPageIndices[0] ?? 0, event),
            linkHitAreas: this.getLinkHitAreasForSlot(0),
            linkOverlayEnabled: this.isLinkOverlayEnabled(),
            linkVisualOpacity: this.pdfLinkVisualOpacity,
            onLinkPressStart: (hitArea: PDFLinkDisplayHitArea) => this.handlePdfLinkPressStart(hitArea),
            onLinkPressCancel: (hitArea: PDFLinkDisplayHitArea) => this.handlePdfLinkPressCancel(hitArea),
            onLinkActivated: (hitArea: PDFLinkDisplayHitArea) => this.activatePdfLink(hitArea)
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
            drawCanvasVisible: this.viewerViewModel.annotateMode !== 'drag' && !this.isDocumentReadOnly(),
            annotateCtx: this.view2Ctx,
            drawCtx: this.view2DrawCtx,
            onDrawTouch: (event: TouchEvent) => this.handleDrawTouch(this.view2DrawCtx, this.view2Ctx, this.viewerViewModel.displayedPageIndices[1] ?? 0, event),
            onDrawMouse: (event: MouseEvent) => this.handleDrawMouse(this.view2DrawCtx, this.view2Ctx, this.viewerViewModel.displayedPageIndices[1] ?? 0, event),
            linkHitAreas: this.getLinkHitAreasForSlot(1),
            linkOverlayEnabled: this.isLinkOverlayEnabled(),
            linkVisualOpacity: this.pdfLinkVisualOpacity,
            onLinkPressStart: (hitArea: PDFLinkDisplayHitArea) => this.handlePdfLinkPressStart(hitArea),
            onLinkPressCancel: (hitArea: PDFLinkDisplayHitArea) => this.handlePdfLinkPressCancel(hitArea),
            onLinkActivated: (hitArea: PDFLinkDisplayHitArea) => this.activatePdfLink(hitArea)
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
            drawCanvasVisible: this.viewerViewModel.annotateMode !== 'drag' && !this.isDocumentReadOnly(),
            annotateCtx: this.view3Ctx,
            drawCtx: this.view3DrawCtx,
            onDrawTouch: (event: TouchEvent) => this.handleDrawTouch(this.view3DrawCtx, this.view3Ctx, this.viewerViewModel.displayedPageIndices[2] ?? 0, event),
            onDrawMouse: (event: MouseEvent) => this.handleDrawMouse(this.view3DrawCtx, this.view3Ctx, this.viewerViewModel.displayedPageIndices[2] ?? 0, event),
            linkHitAreas: this.getLinkHitAreasForSlot(2),
            linkOverlayEnabled: this.isLinkOverlayEnabled(),
            linkVisualOpacity: this.pdfLinkVisualOpacity,
            onLinkPressStart: (hitArea: PDFLinkDisplayHitArea) => this.handlePdfLinkPressStart(hitArea),
            onLinkPressCancel: (hitArea: PDFLinkDisplayHitArea) => this.handlePdfLinkPressCancel(hitArea),
            onLinkActivated: (hitArea: PDFLinkDisplayHitArea) => this.activatePdfLink(hitArea)
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
                showLinkJumpHistory: this.showLinkJumpHistory,
                canGoLinkJumpBack: this.linkJumpCanGoBack,
                canGoLinkJumpForward: this.linkJumpCanGoForward,
                onLinkJumpBack: () => this.navigatePdfLinkBack(),
                onLinkJumpForward: () => this.navigatePdfLinkForward(),
                linkJumpNavRevision: this.linkJumpNavRevision,
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

      if (this.isDocumentLoading) {
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

          if (this.showPasswordGate) {
            this.PasswordGateOverlay()
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(ViewerPageBackdropColor)
      }

      if (this.loadError != '') {
        Column() {
          Column({ space: 20 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
              .fontSize(48)
              .fontColor([ModalErrorTextColor])
            Text('加载失败')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(ModalTitleTextColor)
            Text(this.loadError)
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
