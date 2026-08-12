/**
 * PdfRenderWorker 与主线程之间的消息协议。
 * 类型定义放在 common/page（Worker 脚本不可 export）。
 */

/** 与 taskpool.Priority 对应的光栅优先级（数值越大越优先） */
export enum RasterPriority {
  LOW = 0,
  MEDIUM = 1,
  HIGH = 2
}

/** 光栅 Worker 池下限（低能力设备串行） */
export const PDF_RENDER_WORKER_POOL_SIZE_MIN: number = 1;
/** 光栅 Worker 池上限（高能力设备并行预取） */
export const PDF_RENDER_WORKER_POOL_SIZE_MAX: number = 4;

export const PDF_RENDER_MSG_OPEN: string = 'open';
export const PDF_RENDER_MSG_REPLACE: string = 'replace';
export const PDF_RENDER_MSG_RELEASE: string = 'release';
export const PDF_RENDER_MSG_RENDER: string = 'render';
export const PDF_RENDER_MSG_CANCEL: string = 'cancel';
export const PDF_RENDER_MSG_CANCEL_ALL: string = 'cancelAll';
export const PDF_RENDER_MSG_PROBE_POLYLINES: string = 'probePolylines';

export const PDF_RENDER_MSG_OPEN_RESULT: string = 'openResult';
export const PDF_RENDER_MSG_RENDER_RESULT: string = 'renderResult';
export const PDF_RENDER_MSG_PROBE_RESULT: string = 'probeResult';
export const PDF_RENDER_MSG_RELEASE_RESULT: string = 'releaseResult';

/** 主线程 → Worker */
export interface PdfRenderHostToWorkerMessage {
  type: string;
  requestId: number;
  sessionGeneration: number;
  documentPath: string;
  openPassword: string;
  pageIndex: number;
  renderScale: number;
  priority: number;
  startPageIndex: number;
  endPageIndex: number;
}

/** Worker → 主线程：打开/替换结果 */
export interface PdfRenderOpenResultMessage {
  type: string;
  requestId: number;
  sessionGeneration: number;
  ok: boolean;
  pageCount: number;
  parseResult: number;
  errorMessage: string;
}

/** Worker → 主线程：释放结果 */
export interface PdfRenderReleaseResultMessage {
  type: string;
  requestId: number;
  sessionGeneration: number;
  ok: boolean;
  errorMessage: string;
}

/** Worker → 主线程：光栅结果（PixelMap 为转移对象） */
export interface PdfRenderPageResultMessage {
  type: string;
  requestId: number;
  sessionGeneration: number;
  ok: boolean;
  canceled: boolean;
  pageIndex: number;
  renderScale: number;
  baseWidth: number;
  baseHeight: number;
  displayWidth: number;
  displayHeight: number;
  pixelMap: PixelMap | undefined;
  layoutPixelMap: PixelMap | undefined;
  errorMessage: string;
}

/** Worker → 主线程：折线批注页探测结果 */
export interface PdfRenderProbeResultMessage {
  type: string;
  requestId: number;
  sessionGeneration: number;
  ok: boolean;
  pageIndices: number[];
  errorMessage: string;
}

export function createEmptyHostToWorkerMessage(): PdfRenderHostToWorkerMessage {
  const msg: PdfRenderHostToWorkerMessage = {
    type: '',
    requestId: 0,
    sessionGeneration: 0,
    documentPath: '',
    openPassword: '',
    pageIndex: 0,
    renderScale: 0,
    priority: RasterPriority.MEDIUM,
    startPageIndex: 0,
    endPageIndex: 0
  };
  return msg;
}
