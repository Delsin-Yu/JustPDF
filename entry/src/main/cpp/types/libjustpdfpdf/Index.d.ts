export interface PdfNativePolyline {
  pageIndex: number;
  uniqueId: string;
  lineColor: number;
  opacity: number;
  title: string;
  content: string;
  subject: string;
  xs: number[];
  ys: number[];
}

export const writePolylines: (inputPath: string, outputPath: string, items: PdfNativePolyline[]) => number;
