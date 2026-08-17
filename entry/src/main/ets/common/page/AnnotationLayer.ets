import { util } from '@kit.ArkTS';

export const JustPdfLayerSubject: string = 'JustPDF-Layer';
export const DefaultLayerName: string = '无图层';
export const LayerContentVersionPrefix: string = 'JP1';

export interface ParsedLayerContent {
  layerId: string;
  order: number;
  visible: boolean;
}

export class AnnotationLayer {
  id: string;
  name: string;
  visible: boolean;
  order: number;

  constructor(id: string, name: string, visible: boolean, order: number) {
    this.id = id;
    this.name = name;
    this.visible = visible;
    this.order = order;
  }
}

export class AnnotationLayerListItem {
  id: string;
  name: string;
  visible: boolean;
  order: number;
  strokeCount: number;
  isActive: boolean;
  isProtected: boolean;

  constructor(
    id: string,
    name: string,
    visible: boolean,
    order: number,
    strokeCount: number,
    isActive: boolean,
    isProtected: boolean
  ) {
    this.id = id;
    this.name = name;
    this.visible = visible;
    this.order = order;
    this.strokeCount = strokeCount;
    this.isActive = isActive;
    this.isProtected = isProtected;
  }
}

export function createDefaultLayer(): AnnotationLayer {
  return new AnnotationLayer(util.generateRandomUUID(true), DefaultLayerName, true, 0);
}

export function ensureDefaultLayer(layers: AnnotationLayer[]): AnnotationLayer {
  if (layers.length > 0) {
    return layers[0];
  }
  const layer: AnnotationLayer = createDefaultLayer();
  layers.push(layer);
  return layer;
}

export function nextLayerName(layers: AnnotationLayer[]): string {
  let n: number = 1;
  let candidate: string = '图层 ' + n.toString();
  while (layerNameExists(layers, candidate)) {
    n++;
    candidate = '图层 ' + n.toString();
  }
  return candidate;
}

export function isProtectedLayer(layers: AnnotationLayer[], layerId: string): boolean {
  if (layers.length === 0) {
    return false;
  }
  return layers[0].id === layerId;
}

function layerNameExists(layers: AnnotationLayer[], name: string): boolean {
  for (let i = 0; i < layers.length; i++) {
    if (layers[i].name === name) {
      return true;
    }
  }
  return false;
}

export function isJustPdfLayerSubject(subject: string | undefined): boolean {
  if (subject === undefined) {
    return false;
  }
  return subject === JustPdfLayerSubject;
}

export function encodeLayerContent(layerId: string, order: number, visible: boolean): string {
  const vis: string = visible ? '1' : '0';
  return LayerContentVersionPrefix + '|' + layerId + '|' + order.toString() + '|' + vis;
}

export function parseLayerContent(content: string | undefined): ParsedLayerContent | undefined {
  if (content === undefined || content.length === 0) {
    return undefined;
  }
  const parts: string[] = splitLayerContent(content);
  if (parts.length !== 4) {
    return undefined;
  }
  if (parts[0] !== LayerContentVersionPrefix) {
    return undefined;
  }
  const layerId: string = parts[1];
  if (layerId.length === 0) {
    return undefined;
  }
  const order: number = Number(parts[2]);
  if (!Number.isFinite(order)) {
    return undefined;
  }
  const visPart: string = parts[3];
  if (visPart !== '0' && visPart !== '1') {
    return undefined;
  }
  const parsed: ParsedLayerContent = {
    layerId: layerId,
    order: order,
    visible: visPart === '1'
  };
  return parsed;
}

function splitLayerContent(content: string): string[] {
  const parts: string[] = [];
  let start: number = 0;
  while (start <= content.length) {
    const sep: number = content.indexOf('|', start);
    if (sep < 0) {
      parts.push(content.substring(start));
      break;
    }
    parts.push(content.substring(start, sep));
    start = sep + 1;
  }
  return parts;
}
