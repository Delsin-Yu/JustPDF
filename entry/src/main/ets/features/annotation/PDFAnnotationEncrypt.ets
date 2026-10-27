import { pdfService } from '@kit.PDFKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 探测路径上的 PDF 是否带 /Encrypt，不打开阅读器文档。 */
export function pdfFileIsEncrypted(path: string): boolean {
  try {
    const probe = new pdfService.PdfDocument();
    return probe.isEncrypted(path);
  } catch (_error) {
    return false;
  }
}

/** PDFKit setPdfPassword 只接受 ASCII 0–127。 */
export function isAsciiPdfPassword(password: string): boolean {
  for (let i = 0; i < password.length; i++) {
    if (password.charCodeAt(i) > 127) {
      return false;
    }
  }
  return true;
}

/**
 * 用独立 PdfDocument 解密导出为无密码文件。
 * 不触碰阅读器里的文档，避免 addAnnotation / removeSecurity 污染当前会话。
 */
export function exportDecryptedPdf(inputPath: string, outputPath: string, password: string): boolean {
  const document = new pdfService.PdfDocument();
  try {
    const result = document.loadDocument(inputPath, password);
    if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
      hilog.error(0, 'PDFAnnotationEncrypt', '解密导出加载失败 result=' + result.toString());
      return false;
    }
    if (!document.removeSecurity()) {
      hilog.error(0, 'PDFAnnotationEncrypt', '解密导出 removeSecurity 失败');
      document.releaseDocument();
      return false;
    }
    const saved = document.saveDocument(outputPath);
    document.releaseDocument();
    if (!saved) {
      hilog.error(0, 'PDFAnnotationEncrypt', '解密导出 saveDocument 失败');
    }
    return saved;
  } catch (error) {
    hilog.error(0, 'PDFAnnotationEncrypt', `解密导出出错: ${error}`);
    try {
      document.releaseDocument();
    } catch (_releaseError) {
      // 加载失败时可能无可释放文档
    }
    return false;
  }
}

/**
 * 把无密码 PDF 用 AES-256 加上打开时的密码。
 * 在刚 load 的独立文档上调用，不经过 addAnnotation。
 */
export function encryptPdfWithPassword(inputPath: string, outputPath: string, password: string): boolean {
  const document = new pdfService.PdfDocument();
  try {
    const result = document.loadDocument(inputPath, '');
    if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
      hilog.error(0, 'PDFAnnotationEncrypt', '重新加密加载失败 result=' + result.toString());
      return false;
    }
    if (!document.setPdfPassword(password)) {
      hilog.error(0, 'PDFAnnotationEncrypt', 'setPdfPassword 失败');
      document.releaseDocument();
      return false;
    }
    const saved = document.saveDocument(outputPath);
    document.releaseDocument();
    if (!saved) {
      hilog.error(0, 'PDFAnnotationEncrypt', '重新加密 saveDocument 失败');
    }
    return saved;
  } catch (error) {
    hilog.error(0, 'PDFAnnotationEncrypt', `重新加密出错: ${error}`);
    try {
      document.releaseDocument();
    } catch (_releaseError) {
      // 加载失败时可能无可释放文档
    }
    return false;
  }
}
