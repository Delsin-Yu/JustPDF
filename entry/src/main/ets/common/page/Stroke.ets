import { pdfService } from '@kit.PDFKit';
import { Vector2 } from '../ui/Numbers';
import { DefaultAnnotationColor, pdfColorToCanvasColor } from '../../features/annotation/PDFAnnotationColors';
export interface ImportedPdfPolylineStrokeSource {
  kind: 'importedPdfPolyline';
  uniqueId: string;
  annotationInfo: pdfService.PolylineAnnotationInfo;
}

export type StrokeSource = ImportedPdfPolylineStrokeSource;

export interface ReadonlyStroke {
  readonly points: readonly Vector2[];
  readonly pdfLineColor: number;
  readonly canvasColor: string;
  readonly source: StrokeSource | undefined;
  stroke(renderingContext: CanvasRenderingContext2D): void;
}

export function NewStroke(pdfLineColor: number = DefaultAnnotationColor.pdfColor): Stroke {
  return new Stroke(new Path2D(), [], pdfLineColor);
}

export class Stroke implements ReadonlyStroke {
  path: Path2D;
  points: Vector2[];
  pdfLineColor: number;
  canvasColor: string;
  source: StrokeSource | undefined;

  constructor(
    path: Path2D,
    points: Vector2[],
    pdfLineColor: number = DefaultAnnotationColor.pdfColor,
    source: StrokeSource | undefined = undefined
  ) {
    this.path = path;
    this.points = points;
    this.pdfLineColor = pdfLineColor;
    this.canvasColor = pdfColorToCanvasColor(pdfLineColor);
    this.source = source;
  }

  public stroke(renderingContext: CanvasRenderingContext2D): void {
    renderingContext.strokeStyle = this.canvasColor;
    renderingContext.stroke(this.path);
  }
}

export interface History {
  path: ReadonlyStroke;
  mode: 'add' | 'erase';
  pageIndex: number;
}
