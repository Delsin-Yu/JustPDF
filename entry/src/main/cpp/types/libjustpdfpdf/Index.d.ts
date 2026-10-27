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
  borderWidth: number;
  borderStyle: number;
  creationTimeMs: number;
  modifiedTimeMs: number;
}

export interface PdfNativeBookmark {
  title: string;
  pageIndex: number;
  depth: number;
  titleColor: number;
  isBold: boolean;
  isItalic: boolean;
  fitMode: number;
  left: number;
  top: number;
  right: number;
  bottom: number;
  zoom: number;
  hasLeft: boolean;
  hasTop: boolean;
  hasRight: boolean;
  hasBottom: boolean;
  hasZoom: boolean;
}

export const writePolylines: (
  inputPath: string,
  outputPath: string,
  items: PdfNativePolyline[],
  stripPageIndices: number[],
  bookmarks: PdfNativeBookmark[],
  writeBookmarks: boolean
) => number;
