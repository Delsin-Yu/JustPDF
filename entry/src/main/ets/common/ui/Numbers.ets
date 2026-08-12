export interface  Vector2 {
  x: number;
  y: number;
}

export function Vec2(x: number, y: number): Vector2 {
  return { x: x, y: y };
}

export function add(v1: Vector2, v2: Vector2): Vector2 {
  return Vec2(v1.x + v2.x, v1.y + v2.y);
}

export function mul(v: Vector2, scalar: number): Vector2 {
  return Vec2(v.x * scalar, v.y * scalar);
}

export function toSizePx(value: Vector2): SizeOptions {
  return { width: `${value.x}px`, height: `${value.y}px` };
}

export function fromArea(area: Area, uiContext: UIContext): Vector2 {
  return Vec2(uiContext.vp2px(area.width as number), uiContext.vp2px(area.height as number));
}

// Convert Vector2 from pixels to viewport units
export function pxToVp(v: Vector2, uiContext: UIContext): Vector2 {
  return Vec2(uiContext.px2vp(v.x), uiContext.px2vp(v.y));
}