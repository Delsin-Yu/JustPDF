import {
  createFloatingPanelOffset,
  FloatingPanelChrome,
  FloatingPanelClampParams,
  FloatingPanelHostGestures,
  FloatingPanelMarginVp,
  FloatingPanelOffset
} from '../panels/FloatingPanelChrome';
import {
  getPianoContentWidthVp,
  PDFPianoController,
  PianoEstimatedContentHeightVp,
  PianoMaxWhiteKeyCount,
  PianoMinWhiteKeyCount,
  PianoPanelPaddingVp,
  PianoResizeGapVp,
  PianoResizeHandleWidthVp,
  PianoResizeSide,
  PianoWhiteKeyWidthVp
} from './PDFPianoController';
import { FloatingPianoDefaultScale, FloatingPianoMaxScale, FloatingPianoMinScale } from './PDFPianoPanel';

export interface PDFPianoHostViewport {
  viewportWidthVp: number;
  viewportHeightVp: number;
  safeLeftVp: number;
  safeTopVp: number;
  safeRightVp: number;
  safeBottomVp: number;
  titleWidthVp: number;
  titleHeightVp: number;
}

/** 钢琴浮层几何：拖拽/捏合/贴底居中/左右拉伸后的钳制。不持有 OverlayManager。 */
export class PDFPianoHost {
  readonly chrome: FloatingPanelChrome;
  panelHeightVp: number = 0;
  lastContentWidthVp: number = getPianoContentWidthVp(15);
  private hasPlacedInitial: boolean = false;

  constructor() {
    this.chrome = new FloatingPanelChrome({
      initialOffsetX: 0,
      initialOffsetY: 0,
      initialScale: FloatingPianoDefaultScale,
      minScale: FloatingPianoMinScale,
      maxScale: FloatingPianoMaxScale
    });
  }

  syncWidthFromController(controller: PDFPianoController): void {
    this.lastContentWidthVp = getPianoContentWidthVp(controller.whiteKeyCount);
  }

  getContentWidthVp(controller: PDFPianoController): number {
    return getPianoContentWidthVp(controller.whiteKeyCount);
  }

  getContentHeightVp(): number {
    if (this.panelHeightVp > 0) {
      return this.panelHeightVp;
    }
    return PianoEstimatedContentHeightVp;
  }

  getClampParams(viewport: PDFPianoHostViewport, controller: PDFPianoController): FloatingPanelClampParams {
    const params: FloatingPanelClampParams = {
      viewportWidthVp: viewport.viewportWidthVp,
      viewportHeightVp: viewport.viewportHeightVp,
      contentWidthVp: this.getContentWidthVp(controller),
      contentHeightVp: this.getContentHeightVp(),
      marginVp: FloatingPanelMarginVp,
      minX: 0,
      minY: 0,
      safeLeftVp: viewport.safeLeftVp,
      safeTopVp: viewport.safeTopVp,
      safeRightVp: viewport.safeRightVp,
      safeBottomVp: viewport.safeBottomVp,
      titleWidthVp: viewport.titleWidthVp,
      titleHeightVp: viewport.titleHeightVp,
      useDocked: false,
      dockedOffset: createFloatingPanelOffset(0, 0)
    };
    return params;
  }

  initBottomCenterIfNeeded(viewport: PDFPianoHostViewport, controller: PDFPianoController): void {
    if (this.hasPlacedInitial) {
      return;
    }
    if (viewport.viewportWidthVp <= 0 || viewport.viewportHeightVp <= 0) {
      return;
    }
    const scaledWidthVp: number = this.getContentWidthVp(controller) * this.chrome.scale;
    const scaledHeightVp: number = this.getContentHeightVp() * this.chrome.scale;
    const nextX: number = Math.max(0, (viewport.viewportWidthVp - scaledWidthVp) / 2);
    const nextY: number = Math.max(
      0,
      viewport.viewportHeightVp - scaledHeightVp - FloatingPanelMarginVp - viewport.safeBottomVp
    );
    this.chrome.offset = createFloatingPanelOffset(nextX, nextY);
    this.chrome.syncOffsetToBounds(this.getClampParams(viewport, controller));
    this.hasPlacedInitial = true;
  }

  applyResize(side: PianoResizeSide, viewport: PDFPianoHostViewport, controller: PDFPianoController): void {
    const maxKeys: number = this.computeMaxWhiteKeysForViewport(viewport);
    controller.clampWhiteKeyCount(maxKeys, side);
    const nextWidth: number = this.getContentWidthVp(controller);
    const previousWidth: number = this.lastContentWidthVp;
    if (side === 'left') {
      const widthDelta: number = nextWidth - previousWidth;
      this.chrome.offset = createFloatingPanelOffset(
        this.chrome.offset.x - widthDelta * this.chrome.scale,
        this.chrome.offset.y
      );
    }
    this.lastContentWidthVp = nextWidth;
    this.chrome.syncOffsetToBounds(this.getClampParams(viewport, controller));
  }

  onPanelHeightChanged(heightVp: number, viewport: PDFPianoHostViewport, controller: PDFPianoController): void {
    if (Math.abs(heightVp - this.panelHeightVp) < 0.001) {
      return;
    }
    this.panelHeightVp = heightVp;
    this.chrome.syncOffsetToBounds(this.getClampParams(viewport, controller));
  }

  getClampedOffset(viewport: PDFPianoHostViewport, controller: PDFPianoController): FloatingPanelOffset {
    return this.chrome.getClampedOffset(this.getClampParams(viewport, controller));
  }

  createHostGestures(
    onDragStart: () => void,
    onDragUpdate: (event: GestureEvent) => void,
    onDragEnd: () => void,
    onPinchStart: () => void,
    onPinchUpdate: (event: GestureEvent) => void,
    onPinchEnd: () => void
  ): FloatingPanelHostGestures {
    return this.chrome.createHostGestures(
      onDragStart,
      onDragUpdate,
      onDragEnd,
      onPinchStart,
      onPinchUpdate,
      onPinchEnd
    );
  }

  private computeMaxWhiteKeysForViewport(viewport: PDFPianoHostViewport): number {
    const availableWidthVp: number =
      viewport.viewportWidthVp - viewport.safeLeftVp - viewport.safeRightVp - FloatingPanelMarginVp * 2;
    const layoutWidthVp: number = availableWidthVp / Math.max(this.chrome.scale, 0.01);
    const keysWidthVp: number = layoutWidthVp - PianoPanelPaddingVp * 2 - PianoResizeHandleWidthVp * 2 -
      PianoResizeGapVp * 2;
    return Math.min(
      PianoMaxWhiteKeyCount,
      Math.max(PianoMinWhiteKeyCount, Math.floor(keysWidthVp / PianoWhiteKeyWidthVp))
    );
  }
}
