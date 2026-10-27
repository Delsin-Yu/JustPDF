import { hilog } from '@kit.PerformanceAnalysisKit';
import { pdfService } from '@kit.PDFKit';
import pdfio from 'libjustpdfpdf.so';

export const NativeAnnotOk: number = 0;
export const NativeAnnotErrEncrypt: number = 4;

export class NativePolylineWriteItem {
  pageIndex: number = 0;
  uniqueId: string = '';
  lineColor: number = 0;
  opacity: number = 1;
  title: string = '';
  content: string = '';
  subject: string = '';
  xs: number[] = [];
  ys: number[] = [];
  borderWidth: number = 1;
  borderStyle: number = 1;
  creationTimeMs: number = 0;
  modifiedTimeMs: number = 0;
}

export class NativeBookmarkWriteItem {
  title: string = '';
  pageIndex: number = 0;
  depth: number = 0;
  titleColor: number = 0;
  isBold: boolean = false;
  isItalic: boolean = false;
  fitMode: number = 1;
  left: number = 0;
  top: number = 0;
  right: number = 0;
  bottom: number = 0;
  zoom: number = 0;
  hasLeft: boolean = false;
  hasTop: boolean = false;
  hasRight: boolean = false;
  hasBottom: boolean = false;
  hasZoom: boolean = false;
}

export function collectNativeBookmarks(document: pdfService.PdfDocument): NativeBookmarkWriteItem[] {
  const items: NativeBookmarkWriteItem[] = [];
  try {
    const roots = document.getRootBookmarks();
    for (let i = 0; i < roots.length; i++) {
      appendNativeBookmarks(roots[i], 0, items);
    }
  } catch (error) {
    hilog.error(0, 'PDFAnnotationNative', `收集书签失败: ${error}`);
    return [];
  }
  return items;
}

function appendNativeBookmarks(
  bookmark: pdfService.Bookmark,
  depth: number,
  items: NativeBookmarkWriteItem[]
): void {
  if (!bookmark.isRootBookmark()) {
    const info = bookmark.getBookmarkInfo();
    const dest = bookmark.getDestInfo();
    const item = new NativeBookmarkWriteItem();
    item.title = info.title !== undefined ? info.title : '';
    item.pageIndex = dest !== undefined ? dest.pageIndex : 0;
    item.depth = depth;
    item.titleColor = info.titleColor !== undefined ? info.titleColor : 0;
    item.isBold = info.isBold !== undefined ? info.isBold : false;
    item.isItalic = info.isItalic !== undefined ? info.isItalic : false;
    item.fitMode = dest !== undefined && dest.fitMode !== undefined
      ? dest.fitMode
      : pdfService.FitMode.FIT_MODE_XYZ;
    if (dest !== undefined && dest.left !== undefined) {
      item.left = dest.left;
      item.hasLeft = true;
    }
    if (dest !== undefined && dest.top !== undefined) {
      item.top = dest.top;
      item.hasTop = true;
    }
    if (dest !== undefined && dest.right !== undefined) {
      item.right = dest.right;
      item.hasRight = true;
    }
    if (dest !== undefined && dest.bottom !== undefined) {
      item.bottom = dest.bottom;
      item.hasBottom = true;
    }
    if (dest !== undefined && dest.zoom !== undefined) {
      item.zoom = dest.zoom;
      item.hasZoom = true;
    }
    items.push(item);
  }
  if (bookmark.hasChild()) {
    const nextDepth = bookmark.isRootBookmark() ? depth : depth + 1;
    const children = bookmark.getChildren();
    for (let i = 0; i < children.length; i++) {
      appendNativeBookmarks(children[i], nextDepth, items);
    }
  }
}

export function writeNativePolylines(
  inputPath: string,
  outputPath: string,
  items: NativePolylineWriteItem[],
  stripPageIndices: number[],
  bookmarks: NativeBookmarkWriteItem[],
  writeBookmarks: boolean
): number {
  try {
    return pdfio.writePolylines(inputPath, outputPath, items, stripPageIndices, bookmarks, writeBookmarks);
  } catch (error) {
    hilog.error(0, 'PDFAnnotationNative', `写入批注失败: ${error}`);
    return 1;
  }
}
