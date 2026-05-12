// 注释绘制可选颜色定义。
//
// PDF Kit 的 lineColor 使用 BGR 字节序：
//   pdfColor = (B << 16) | (G << 8) | R
// 例如 0xFF0000 在文档中表示蓝色，0x0000FF 表示红色。

export interface AnnotationColor {
  id: string;
  label: string;
  canvasColor: string;
  pdfColor: number;
}

export interface RgbTuple {
  r: number;
  g: number;
  b: number;
}

export const CustomAnnotationColorId: string = 'custom';

export const AnnotationColorPalette: AnnotationColor[] = [
  { id: 'orange', label: '橙色', canvasColor: 'rgba(255, 132, 0, 1.00)',   pdfColor: 0x0084FF },
  { id: 'red',    label: '红色', canvasColor: 'rgba(229, 32, 39, 1.00)',   pdfColor: 0x2720E5 },
  { id: 'yellow', label: '黄色', canvasColor: 'rgba(245, 200, 30, 1.00)',  pdfColor: 0x1EC8F5 },
  { id: 'green',  label: '绿色', canvasColor: 'rgba(45, 181, 93, 1.00)',   pdfColor: 0x5DB52D },
  { id: 'blue',   label: '蓝色', canvasColor: 'rgba(45, 110, 235, 1.00)',  pdfColor: 0xEB6E2D },
  { id: 'purple', label: '紫色', canvasColor: 'rgba(160, 60, 200, 1.00)',  pdfColor: 0xC83CA0 },
  { id: 'black',  label: '黑色', canvasColor: 'rgba(20, 20, 20, 1.00)',    pdfColor: 0x141414 },
];

export const DefaultAnnotationColor: AnnotationColor = AnnotationColorPalette[0];

export function pdfColorToCanvasColor(pdfColor: number): string {
  const b: number = (pdfColor >> 16) & 0xFF;
  const g: number = (pdfColor >> 8) & 0xFF;
  const r: number = pdfColor & 0xFF;
  return `rgba(${r}, ${g}, ${b}, 1.00)`;
}

export function findAnnotationColorByPdf(pdfColor: number): AnnotationColor | undefined {
  for (const color of AnnotationColorPalette) {
    if (color.pdfColor === pdfColor) {
      return color;
    }
  }
  return undefined;
}

export function pdfColorToRgb(pdfColor: number): RgbTuple {
  const b: number = (pdfColor >> 16) & 0xFF;
  const g: number = (pdfColor >> 8) & 0xFF;
  const r: number = pdfColor & 0xFF;
  return { r, g, b };
}

export function rgbToPdfColor(r: number, g: number, b: number): number {
  const cr: number = Math.max(0, Math.min(255, Math.round(r)));
  const cg: number = Math.max(0, Math.min(255, Math.round(g)));
  const cb: number = Math.max(0, Math.min(255, Math.round(b)));
  return ((cb & 0xFF) << 16) | ((cg & 0xFF) << 8) | (cr & 0xFF);
}

export function makeCustomAnnotationColor(r: number, g: number, b: number): AnnotationColor {
  const cr: number = Math.max(0, Math.min(255, Math.round(r)));
  const cg: number = Math.max(0, Math.min(255, Math.round(g)));
  const cb: number = Math.max(0, Math.min(255, Math.round(b)));
  return {
    id: CustomAnnotationColorId,
    label: '自定义',
    canvasColor: `rgba(${cr}, ${cg}, ${cb}, 1.00)`,
    pdfColor: ((cb & 0xFF) << 16) | ((cg & 0xFF) << 8) | (cr & 0xFF),
  };
}

// HSV 分量统一使用 [0, 1] 区间；hue 在 0 与 1 处含义相同（红色）。

export interface HsvTuple {
  h: number;
  s: number;
  v: number;
}

export function hsvToRgb(h: number, s: number, v: number): RgbTuple {
  let nh: number = h - Math.floor(h);
  if (nh < 0) {
    nh += 1;
  }
  const ns: number = Math.max(0, Math.min(1, s));
  const nv: number = Math.max(0, Math.min(1, v));

  const i: number = Math.floor(nh * 6);
  const f: number = nh * 6 - i;
  const p: number = nv * (1 - ns);
  const q: number = nv * (1 - f * ns);
  const t: number = nv * (1 - (1 - f) * ns);

  let r: number = 0;
  let g: number = 0;
  let b: number = 0;
  switch (i % 6) {
    case 0: r = nv; g = t; b = p; break;
    case 1: r = q; g = nv; b = p; break;
    case 2: r = p; g = nv; b = t; break;
    case 3: r = p; g = q; b = nv; break;
    case 4: r = t; g = p; b = nv; break;
    case 5: r = nv; g = p; b = q; break;
    default: r = nv; g = t; b = p; break;
  }
  return { r: Math.round(r * 255), g: Math.round(g * 255), b: Math.round(b * 255) };
}

export function rgbToHsv(r: number, g: number, b: number): HsvTuple {
  const rn: number = Math.max(0, Math.min(255, r)) / 255;
  const gn: number = Math.max(0, Math.min(255, g)) / 255;
  const bn: number = Math.max(0, Math.min(255, b)) / 255;
  const max: number = Math.max(rn, Math.max(gn, bn));
  const min: number = Math.min(rn, Math.min(gn, bn));
  const delta: number = max - min;

  let h: number = 0;
  if (delta > 0) {
    if (max === rn) {
      h = ((gn - bn) / delta) % 6;
    } else if (max === gn) {
      h = (bn - rn) / delta + 2;
    } else {
      h = (rn - gn) / delta + 4;
    }
    h /= 6;
    if (h < 0) {
      h += 1;
    }
  }
  const s: number = max === 0 ? 0 : delta / max;
  const v: number = max;
  return { h, s, v };
}

export function rgbToHex(r: number, g: number, b: number): string {
  const cr: number = Math.max(0, Math.min(255, Math.round(r)));
  const cg: number = Math.max(0, Math.min(255, Math.round(g)));
  const cb: number = Math.max(0, Math.min(255, Math.round(b)));
  const toHexByte: (n: number) => string = (n: number) => {
    const s: string = n.toString(16).toUpperCase();
    return s.length < 2 ? '0' + s : s;
  };
  return toHexByte(cr) + toHexByte(cg) + toHexByte(cb);
}

export function parseHexColor(hex: string): RgbTuple | undefined {
  let cleaned: string = hex.trim();
  if (cleaned.startsWith('#')) {
    cleaned = cleaned.substring(1);
  }
  if (cleaned.length !== 6) {
    return undefined;
  }
  const r: number = parseInt(cleaned.substring(0, 2), 16);
  const g: number = parseInt(cleaned.substring(2, 4), 16);
  const b: number = parseInt(cleaned.substring(4, 6), 16);
  if (isNaN(r) || isNaN(g) || isNaN(b)) {
    return undefined;
  }
  return { r, g, b };
}

// 默认的自定义颜色——纯灰 (0.5, 0.5, 0.5)。
export const DefaultCustomAnnotationColor: AnnotationColor = makeCustomAnnotationColor(128, 128, 128);

// 从偏好存储中解析 PDF BGR 颜色值（number / string 等）。
export function parsePersistedPdfColorLoose(raw: number | string | boolean, fallback: number): number {
  if (typeof raw === 'number' && Number.isFinite(raw)) {
    return Math.max(0, Math.min(0xFFFFFF, Math.floor(raw)));
  }
  if (typeof raw === 'string') {
    const n: number = parseInt(raw, 10);
    if (Number.isFinite(n)) {
      return Math.max(0, Math.min(0xFFFFFF, n));
    }
  }
  return fallback;
}

// 自定义色槽：始终还原为 id=custom 的 AnnotationColor。
export function customDrawColorFromPersistedPdf(pdfColor: number): AnnotationColor {
  const rgb: RgbTuple = pdfColorToRgb(pdfColor);
  return makeCustomAnnotationColor(rgb.r, rgb.g, rgb.b);
}

// 当前绘制色：预设表命中则用预设项，否则按自定义色处理。
export function selectedDrawColorFromPersistedPdf(pdfColor: number): AnnotationColor {
  const preset: AnnotationColor | undefined = findAnnotationColorByPdf(pdfColor);
  if (preset !== undefined) {
    return preset;
  }
  return customDrawColorFromPersistedPdf(pdfColor);
}
