import { pdfService } from '@kit.PDFKit';

/** 判断打开失败是否因需要密码。 */
export function pdfLoadNeedsPassword(parseResult: pdfService.ParseResult, filePath: string): boolean {
  if (parseResult === pdfService.ParseResult.PARSE_ERROR_PASSWORD) {
    return true;
  }
  if (parseResult === pdfService.ParseResult.PARSE_SUCCESS) {
    return false;
  }
  try {
    const probe = new pdfService.PdfDocument();
    return probe.isEncrypted(filePath);
  } catch (_e) {
    return false;
  }
}

/** 在已 load 的文档上尝试释放后重新加载；调用方负责处理非密码类错误。 */
export function reloadPdfDocument(
  document: pdfService.PdfDocument,
  filePath: string,
  password: string
): pdfService.ParseResult {
  try {
    document.releaseDocument();
  } catch (_e) {
    /* 首次加载失败时可能无可释放文档 */
  }
  return document.loadDocument(filePath, password);
}
