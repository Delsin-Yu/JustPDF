import { unifiedDataChannel, uniformTypeDescriptor as utd } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'PdfDropOpen';

function isPdfUriHint(text: string): boolean {
  const lower: string = text.toLowerCase();
  return lower.indexOf('.pdf') >= 0 || lower.indexOf('com.adobe.pdf') >= 0;
}

function readOriUri(value: Object): string {
  const maybe: Record<string, string | number | boolean> = value as Record<string, string | number | boolean>;
  const oriUri: string | number | boolean | undefined = maybe['oriUri'];
  if (typeof oriUri === 'string' && oriUri.length > 0) {
    return oriUri;
  }
  return '';
}

function uriFromRecord(record: unifiedDataChannel.UnifiedRecord): string {
  try {
    const fileUriEntry: Object = record.getEntry(utd.UniformDataType.FILE_URI) as Object;
    const fromEntry: string = readOriUri(fileUriEntry);
    if (fromEntry.length > 0) {
      return fromEntry;
    }
  } catch (_error) {
  }
  try {
    const value: Object = record.getValue() as Object;
    if (typeof value === 'string') {
      return value;
    }
    return readOriUri(value);
  } catch (_error) {
  }
  return '';
}

/**
 * 从拖放事件取出第一个 PDF URI。非 PDF 返回空串。
 */
export function extractFirstPdfUriFromDragEvent(event: DragEvent): string {
  try {
    const data: unifiedDataChannel.UnifiedData = event.getData();
    const records: Array<unifiedDataChannel.UnifiedRecord> = data.getRecords();
    for (let i = 0; i < records.length; i++) {
      const record: unifiedDataChannel.UnifiedRecord = records[i];
      const uri: string = uriFromRecord(record);
      if (uri.length > 0 && isPdfUriHint(uri)) {
        return uri;
      }
      const typeId: string = record.getType();
      if ((typeId === utd.UniformDataType.PDF || typeId === utd.UniformDataType.FILE_URI) &&
        uri.length > 0) {
        return uri;
      }
    }
  } catch (error) {
    hilog.warn(0, TAG, `解析拖入 PDF 失败: ${error}`);
  }
  return '';
}

export function pdfDropAcceptedTypes(): string[] {
  return [utd.UniformDataType.PDF, utd.UniformDataType.FILE_URI];
}
