export interface  Vector2 {
  x: number;
  y: number;
}

export function Vec2(x: number, y: number): Vector2 {
  return { x: x, y: y };
}

export function mul(v: Vector2, scalar: number): Vector2 {
  return Vec2(v.x * scalar, v.y * scalar);
}

export function div(v: Vector2, scalar: number): Vector2 {
  return Vec2(v.x / scalar, v.y / scalar);
}

export function toSizePx(value: Vector2): SizeOptions {
  return { width: `${value.x}px`, height: `${value.y}px` };
}

export function toSizeVp(value: Vector2): SizeOptions {
  return { width: `${value.x}vp`, height: `${value.y}vp` };
}

export function fromArea(area: Area, uiContext: UIContext): Vector2 {
  return Vec2(uiContext.vp2px(area.width as number), uiContext.vp2px(area.height as number));
}

// Convert Vector2 from pixels to viewport units
export function pxToVp(v: Vector2, uiContext: UIContext): Vector2 {
  return Vec2(uiContext.px2vp(v.x), uiContext.px2vp(v.y));
}

// Convert Vector2 from viewport units to pixels
export function vpToPx(v: Vector2, uiContext: UIContext): Vector2 {
  return Vec2(uiContext.vp2px(v.x), uiContext.vp2px(v.y));
}

export function hslToColor(h: number, s: number, l: number, alpha: number): string {
  s /= 100;
  l /= 100;

  const k = (n: number) => (n + h / 30) % 12;
  const a = s * Math.min(l, 1 - l);
  const f = (n: number) =>
    l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));

  const r = Math.round(f(0) * 255);
  const g = Math.round(f(8) * 255);
  const b = Math.round(f(4) * 255);

  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}