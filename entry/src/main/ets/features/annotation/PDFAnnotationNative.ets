import { hilog } from '@kit.PerformanceAnalysisKit';
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
}

export function writeNativePolylines(
  inputPath: string,
  outputPath: string,
  items: NativePolylineWriteItem[]
): number {
  try {
    return pdfio.writePolylines(inputPath, outputPath, items);
  } catch (error) {
    hilog.error(0, 'PDFAnnotationNative', `写入批注失败: ${error}`);
    return 1;
  }
}
