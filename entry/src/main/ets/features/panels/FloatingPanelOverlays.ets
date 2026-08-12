/**
 * 浮动面板 Overlay 参数与 @Builder：节拍器 / 调音器 / 批注色板 / 书签。
 * 拖拽钳制状态见 FloatingPanelChrome；PDFView 只负责可见性与参数填充。
 */

import { ContainerPadding, StyleIconButton, toVisibility } from '../../common/ui/UIComponents';
import { PDFMetronomePanelContent } from '../music/PDFMetronomePanel';
import { PDFMetronomeController } from '../music/PDFMetronomeController';
import { PDFTunerPanelContent } from '../music/PDFTunerPanel';
import { PDFTunerController } from '../music/PDFTunerController';
import { PDFAnnotationPalette } from '../annotation/PDFAnnotationPalette';
import { AnnotationColor } from '../annotation/PDFAnnotationColors';
import { PDFAnnotateMode } from '../viewer/PDFViewerViewModel';
import { PDFBookmarkListItem } from './PDFBookmarkController';
import { PDFBookmarkPanelContent } from './PDFBookmarkPanel';
import { FloatingPanelOffset } from './FloatingPanelChrome';

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

export class MetronomeOverlayParams {
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

export class TunerOverlayParams {
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

export class AnnotationPaletteOverlayParams {
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

export class BookmarkOverlayParams {
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
export function BuildMetronomeOverlay(params: MetronomeOverlayParams) {
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
export function BuildTunerOverlay(params: TunerOverlayParams) {
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

@Builder
export function BuildAnnotationPaletteOverlay(params: AnnotationPaletteOverlayParams) {
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

@Builder
export function BuildBookmarkOverlay(params: BookmarkOverlayParams) {
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
