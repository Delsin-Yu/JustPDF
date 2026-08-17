/**
 * 浮动面板共用几何与手势状态：拖拽、捏合缩放、边界钳制。
 * 面板内容与 Overlay 参数构建仍由调用方负责。
 */

export interface FloatingPanelOffset {
  x: number;
  y: number;
}

/** 钳制浮动面板偏移所需的视口与面板尺寸（单位 vp） */
export interface FloatingPanelClampParams {
  viewportWidthVp: number;
  viewportHeightVp: number;
  contentWidthVp: number;
  contentHeightVp: number;
  marginVp: number;
  minX: number;
  minY: number;
  safeLeftVp: number;
  safeTopVp: number;
  safeRightVp: number;
  safeBottomVp: number;
  titleWidthVp: number;
  titleHeightVp: number;
  useDocked: boolean;
  dockedOffset: FloatingPanelOffset;
}

export interface FloatingPanelChromeOptions {
  initialOffsetX: number;
  initialOffsetY: number;
  initialScale: number;
  minScale: number;
  maxScale: number;
}

/** 宿主拖拽/捏合回调（各面板 Overlay / Content 共用形状） */
export interface FloatingPanelHostGestures {
  onHostDragStart: () => void;
  onHostDragUpdate: (event: GestureEvent) => void;
  onHostDragEnd: () => void;
  onHostPinchStart: () => void;
  onHostPinchUpdate: (event: GestureEvent) => void;
  onHostPinchEnd: () => void;
}

export const FloatingPanelMarginVp: number = 10;

export function createFloatingPanelOffset(x: number, y: number): FloatingPanelOffset {
  const offset: FloatingPanelOffset = { x: x, y: y };
  return offset;
}

export function clampFloatingPanelScale(scale: number, minScale: number, maxScale: number): number {
  return Math.max(minScale, Math.min(maxScale, scale));
}

export function clampFloatingPanelOffset(
  offset: FloatingPanelOffset,
  scale: number,
  params: FloatingPanelClampParams
): FloatingPanelOffset {
  if (params.useDocked) {
    return createFloatingPanelOffset(params.dockedOffset.x, params.dockedOffset.y);
  }
  const scaledWidthVp: number = params.contentWidthVp * scale;
  const scaledHeightVp: number = params.contentHeightVp * scale;
  const minX: number = Math.max(params.minX, params.safeLeftVp + params.marginVp);
  const minY: number = Math.max(params.minY, params.safeTopVp + params.marginVp);
  const maxX: number = params.viewportWidthVp - scaledWidthVp - params.marginVp - params.safeRightVp;
  const maxY: number = params.viewportHeightVp - scaledHeightVp - params.marginVp - params.safeBottomVp;
  return createFloatingPanelOffset(
    Math.max(minX, Math.min(offset.x, Math.max(minX, maxX))),
    Math.max(minY, Math.min(offset.y, Math.max(minY, maxY)))
  );
}

/**
 * 单个浮动面板的偏移/缩放与手势中间状态。
 * 不持有 OverlayManager；由 PDFView 在手势后 sync 浮层。
 */
export class FloatingPanelChrome {
  offset: FloatingPanelOffset;
  scale: number;
  dragStartOffset: FloatingPanelOffset;
  pinchStartScale: number;
  readonly minScale: number;
  readonly maxScale: number;

  constructor(options: FloatingPanelChromeOptions) {
    this.offset = createFloatingPanelOffset(options.initialOffsetX, options.initialOffsetY);
    this.scale = options.initialScale;
    this.dragStartOffset = createFloatingPanelOffset(options.initialOffsetX, options.initialOffsetY);
    this.pinchStartScale = options.initialScale;
    this.minScale = options.minScale;
    this.maxScale = options.maxScale;
  }

  clampScale(scale: number): number {
    return clampFloatingPanelScale(scale, this.minScale, this.maxScale);
  }

  getClampedOffset(params: FloatingPanelClampParams, offset?: FloatingPanelOffset): FloatingPanelOffset {
    const source: FloatingPanelOffset = offset !== undefined ? offset : this.offset;
    return clampFloatingPanelOffset(source, this.scale, params);
  }

  /** 若偏移被钳制则写回并返回 true */
  syncOffsetToBounds(params: FloatingPanelClampParams): boolean {
    const next: FloatingPanelOffset = this.getClampedOffset(params);
    if (Math.abs(next.x - this.offset.x) < 0.001 && Math.abs(next.y - this.offset.y) < 0.001) {
      return false;
    }
    this.offset = next;
    this.dragStartOffset = createFloatingPanelOffset(next.x, next.y);
    return true;
  }

  beginDrag(params: FloatingPanelClampParams): void {
    const clamped: FloatingPanelOffset = this.getClampedOffset(params);
    this.offset = clamped;
    this.dragStartOffset = createFloatingPanelOffset(clamped.x, clamped.y);
  }

  updateDrag(event: GestureEvent, params: FloatingPanelClampParams): void {
    this.offset = this.getClampedOffset(params, createFloatingPanelOffset(
      this.dragStartOffset.x + event.offsetX * this.scale,
      this.dragStartOffset.y + event.offsetY * this.scale
    ));
  }

  beginPinch(): void {
    this.pinchStartScale = this.scale;
  }

  updatePinch(event: GestureEvent): void {
    this.scale = this.clampScale(this.pinchStartScale * event.scale);
  }

  endPinch(): void {
    this.pinchStartScale = this.scale;
  }

  /** 供 Overlay 参数使用的宿主手势回调包 */
  createHostGestures(
    onDragStart: () => void,
    onDragUpdate: (event: GestureEvent) => void,
    onDragEnd: () => void,
    onPinchStart: () => void,
    onPinchUpdate: (event: GestureEvent) => void,
    onPinchEnd: () => void
  ): FloatingPanelHostGestures {
    const gestures: FloatingPanelHostGestures = {
      onHostDragStart: onDragStart,
      onHostDragUpdate: onDragUpdate,
      onHostDragEnd: onDragEnd,
      onHostPinchStart: onPinchStart,
      onHostPinchUpdate: onPinchUpdate,
      onHostPinchEnd: onPinchEnd
    };
    return gestures;
  }
}
