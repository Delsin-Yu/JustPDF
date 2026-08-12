/**
 * PDF 光栅 Worker（池内一员）：各自持有一份 PdfDocument。
 * 调度与优先级队列在主线程 PdfRenderSession；此处同步处理单次 render。
 * 本文件不得 export（Worker 脚本约束）。
 */
import { ErrorEvent, MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import { pdfService } from '@kit.PDFKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  createEmptyHostToWorkerMessage,
  PDF_RENDER_MSG_CANCEL,
  PDF_RENDER_MSG_CANCEL_ALL,
  PDF_RENDER_MSG_OPEN,
  PDF_RENDER_MSG_OPEN_RESULT,
  PDF_RENDER_MSG_PROBE_POLYLINES,
  PDF_RENDER_MSG_PROBE_RESULT,
  PDF_RENDER_MSG_RELEASE,
  PDF_RENDER_MSG_RELEASE_RESULT,
  PDF_RENDER_MSG_RENDER,
  PDF_RENDER_MSG_RENDER_RESULT,
  PDF_RENDER_MSG_REPLACE,
  PdfRenderHostToWorkerMessage,
  PdfRenderOpenResultMessage,
  PdfRenderPageResultMessage,
  PdfRenderProbeResultMessage,
  PdfRenderReleaseResultMessage,
  RasterPriority
} from '../common/page/PdfRenderWorkerProtocol';

const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

let document: pdfService.PdfDocument | undefined = undefined;
let documentOpen: boolean = false;
let currentGeneration: number = 0;

function safePostMessage(msg: Object): void {
  try {
    workerPort.postMessage(msg);
  } catch (error) {
    const message = error instanceof Error ? error.message : '' + error;
    hilog.error(0, 'PdfRenderWorker', 'postMessage 失败: ' + message);
  }
}

function postOpenResult(
  requestId: number,
  sessionGeneration: number,
  ok: boolean,
  pageCount: number,
  parseResult: number,
  errorMessage: string
): void {
  const msg: PdfRenderOpenResultMessage = {
    type: PDF_RENDER_MSG_OPEN_RESULT,
    requestId: requestId,
    sessionGeneration: sessionGeneration,
    ok: ok,
    pageCount: pageCount,
    parseResult: parseResult,
    errorMessage: errorMessage
  };
  safePostMessage(msg);
}

function postReleaseResult(
  requestId: number,
  sessionGeneration: number,
  ok: boolean,
  errorMessage: string
): void {
  const msg: PdfRenderReleaseResultMessage = {
    type: PDF_RENDER_MSG_RELEASE_RESULT,
    requestId: requestId,
    sessionGeneration: sessionGeneration,
    ok: ok,
    errorMessage: errorMessage
  };
  safePostMessage(msg);
}

function postProbeResult(
  requestId: number,
  sessionGeneration: number,
  ok: boolean,
  pageIndices: number[],
  errorMessage: string
): void {
  const msg: PdfRenderProbeResultMessage = {
    type: PDF_RENDER_MSG_PROBE_RESULT,
    requestId: requestId,
    sessionGeneration: sessionGeneration,
    ok: ok,
    pageIndices: pageIndices,
    errorMessage: errorMessage
  };
  safePostMessage(msg);
}

function postRenderFailure(
  requestId: number,
  sessionGeneration: number,
  pageIndex: number,
  renderScale: number,
  canceled: boolean,
  errorMessage: string
): void {
  const msg: PdfRenderPageResultMessage = {
    type: PDF_RENDER_MSG_RENDER_RESULT,
    requestId: requestId,
    sessionGeneration: sessionGeneration,
    ok: false,
    canceled: canceled,
    pageIndex: pageIndex,
    renderScale: renderScale,
    baseWidth: 0,
    baseHeight: 0,
    displayWidth: 0,
    displayHeight: 0,
    pixelMap: undefined,
    layoutPixelMap: undefined,
    errorMessage: errorMessage
  };
  safePostMessage(msg);
}

function releaseDocumentInternal(): void {
  if (document !== undefined && documentOpen) {
    try {
      document.releaseDocument();
    } catch (_e) {
      /* ignore */
    }
  }
  documentOpen = false;
}

function ensureDocumentInstance(): pdfService.PdfDocument {
  if (document === undefined) {
    document = new pdfService.PdfDocument();
  }
  return document;
}

function openOrReplaceDocument(
  msgType: string,
  requestId: number,
  sessionGeneration: number,
  documentPath: string,
  openPassword: string
): void {
  currentGeneration = sessionGeneration;

  if (msgType === PDF_RENDER_MSG_REPLACE || documentOpen) {
    releaseDocumentInternal();
  }

  const doc = ensureDocumentInstance();
  const result = doc.loadDocument(documentPath, openPassword);
  if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
    documentOpen = false;
    hilog.error(0, 'PdfRenderWorker', 'loadDocument 失败: ' + result.toString());
    postOpenResult(requestId, sessionGeneration, false, 0, result, '加载文档失败: ' + result.toString());
    return;
  }

  documentOpen = true;
  let pageCount = 0;
  try {
    pageCount = doc.getPageCount();
  } catch (_e) {
    pageCount = 0;
  }
  hilog.info(0, 'PdfRenderWorker', '文档已打开 pages=' + pageCount.toString());
  postOpenResult(requestId, sessionGeneration, true, pageCount, result, '');
}

function releaseDocumentMessage(requestId: number, sessionGeneration: number): void {
  currentGeneration = sessionGeneration;
  try {
    releaseDocumentInternal();
    postReleaseResult(requestId, sessionGeneration, true, '');
  } catch (e) {
    const err = e instanceof Error ? e.message : 'release failed';
    postReleaseResult(requestId, sessionGeneration, false, err);
  }
}

function probePolylines(
  requestId: number,
  sessionGeneration: number,
  startPageIndex: number,
  endPageIndex: number
): void {
  if (!documentOpen || document === undefined) {
    postProbeResult(requestId, sessionGeneration, false, [], '文档未打开');
    return;
  }
  if (sessionGeneration !== currentGeneration) {
    postProbeResult(requestId, sessionGeneration, false, [], 'session stale');
    return;
  }

  const affectedPageIndices: number[] = [];
  try {
    for (let pageIndex = startPageIndex; pageIndex < endPageIndex; pageIndex++) {
      const page = document.getPage(pageIndex);
      const annotations = page.getAnnotations();
      for (let i = 0; i < annotations.length; i++) {
        if (annotations[i].type === pdfService.AnnotationType.POLYLINE) {
          affectedPageIndices.push(pageIndex);
          break;
        }
      }
    }
    postProbeResult(requestId, sessionGeneration, true, affectedPageIndices, '');
  } catch (e) {
    const err = e instanceof Error ? e.message : 'probe failed';
    postProbeResult(requestId, sessionGeneration, false, [], err);
  }
}

function handleRender(
  requestId: number,
  sessionGeneration: number,
  pageIndex: number,
  renderScale: number
): void {
  if (sessionGeneration !== currentGeneration) {
    postRenderFailure(requestId, sessionGeneration, pageIndex, renderScale, true, 'session stale');
    return;
  }
  if (!documentOpen || document === undefined) {
    postRenderFailure(requestId, sessionGeneration, pageIndex, renderScale, false, '文档未打开');
    return;
  }

  try {
    const page = document.getPage(pageIndex);
    const baseWidth = page.getWidth();
    const baseHeight = page.getHeight();
    const pageArea: number = baseWidth * baseHeight;
    const maxBitmapPixels: number = 70000000;
    const layoutScale: number = 2;
    let effectiveScale: number = renderScale;
    if (pageArea > 0) {
      const maxScale: number = Math.sqrt(maxBitmapPixels / pageArea);
      if (effectiveScale > maxScale) {
        effectiveScale = Math.max(1, maxScale);
      }
    }

    const matrix = new pdfService.PdfMatrix();
    matrix.x = 0;
    matrix.y = 0;
    matrix.width = baseWidth * effectiveScale;
    matrix.height = baseHeight * effectiveScale;
    matrix.rotate = 0;
    const pixelMap = page.getCustomPagePixelMap(matrix, false, true);

    let layoutPixelMap: PixelMap | undefined = undefined;
    if (effectiveScale > layoutScale + 0.001) {
      const factor: number = layoutScale / effectiveScale;
      try {
        layoutPixelMap = pixelMap.createScaledPixelMapSync(
          factor,
          factor,
          image.AntiAliasingLevel.MEDIUM
        );
      } catch (_scaleErr) {
        layoutPixelMap = undefined;
      }
    }

    try {
      pixelMap.setTransferDetached(true);
    } catch (_detachErr) {
    }
    if (layoutPixelMap !== undefined) {
      try {
        layoutPixelMap.setTransferDetached(true);
      } catch (_detachLayoutErr) {
      }
    }

    const okMsg: PdfRenderPageResultMessage = {
      type: PDF_RENDER_MSG_RENDER_RESULT,
      requestId: requestId,
      sessionGeneration: sessionGeneration,
      ok: true,
      canceled: false,
      pageIndex: pageIndex,
      renderScale: effectiveScale,
      baseWidth: baseWidth,
      baseHeight: baseHeight,
      displayWidth: baseWidth * layoutScale,
      displayHeight: baseHeight * layoutScale,
      pixelMap: pixelMap,
      layoutPixelMap: layoutPixelMap,
      errorMessage: ''
    };
    safePostMessage(okMsg);
  } catch (e) {
    const err = e instanceof Error ? e.message : 'raster failed';
    hilog.error(0, 'PdfRenderWorker', 'render 失败: ' + err);
    postRenderFailure(requestId, sessionGeneration, pageIndex, renderScale, false, err);
  }
}

function parseInbound(data: Object): PdfRenderHostToWorkerMessage {
  const raw = data as PdfRenderHostToWorkerMessage;
  const msg = createEmptyHostToWorkerMessage();
  if (raw === undefined || raw === null) {
    return msg;
  }
  msg.type = raw.type !== undefined ? raw.type : '';
  msg.requestId = raw.requestId !== undefined ? raw.requestId : 0;
  msg.sessionGeneration = raw.sessionGeneration !== undefined ? raw.sessionGeneration : 0;
  msg.documentPath = raw.documentPath !== undefined ? raw.documentPath : '';
  msg.openPassword = raw.openPassword !== undefined ? raw.openPassword : '';
  msg.pageIndex = raw.pageIndex !== undefined ? raw.pageIndex : 0;
  msg.renderScale = raw.renderScale !== undefined ? raw.renderScale : 0;
  msg.priority = raw.priority !== undefined ? raw.priority : RasterPriority.MEDIUM;
  msg.startPageIndex = raw.startPageIndex !== undefined ? raw.startPageIndex : 0;
  msg.endPageIndex = raw.endPageIndex !== undefined ? raw.endPageIndex : 0;
  return msg;
}

workerPort.onmessage = (e: MessageEvents): void => {
  const msg = parseInbound(e.data as Object);
  if (msg.type === PDF_RENDER_MSG_OPEN || msg.type === PDF_RENDER_MSG_REPLACE) {
    openOrReplaceDocument(
      msg.type,
      msg.requestId,
      msg.sessionGeneration,
      msg.documentPath,
      msg.openPassword
    );
    return;
  }
  if (msg.type === PDF_RENDER_MSG_RELEASE) {
    releaseDocumentMessage(msg.requestId, msg.sessionGeneration);
    return;
  }
  if (msg.type === PDF_RENDER_MSG_CANCEL || msg.type === PDF_RENDER_MSG_CANCEL_ALL) {
    // 队列在主线程；飞行中的光栅无法中断，主线程丢弃结果即可
    return;
  }
  if (msg.type === PDF_RENDER_MSG_PROBE_POLYLINES) {
    probePolylines(msg.requestId, msg.sessionGeneration, msg.startPageIndex, msg.endPageIndex);
    return;
  }
  if (msg.type === PDF_RENDER_MSG_RENDER) {
    handleRender(msg.requestId, msg.sessionGeneration, msg.pageIndex, msg.renderScale);
    return;
  }
  hilog.warn(0, 'PdfRenderWorker', '未知消息类型: ' + msg.type);
};

workerPort.onerror = (err: ErrorEvent): void => {
  hilog.error(0, 'PdfRenderWorker', 'Worker 错误: ' + err.message);
};
