import { ErrorEvent, MessageEvents, worker } from '@kit.ArkTS';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PageCache } from './PageRasterCache';
import { Vec2 } from '../ui/Numbers';
import {
  createEmptyHostToWorkerMessage,
  PDF_RENDER_MSG_OPEN,
  PDF_RENDER_MSG_OPEN_RESULT,
  PDF_RENDER_MSG_PROBE_POLYLINES,
  PDF_RENDER_MSG_PROBE_RESULT,
  PDF_RENDER_MSG_RELEASE,
  PDF_RENDER_MSG_RELEASE_RESULT,
  PDF_RENDER_MSG_RENDER,
  PDF_RENDER_MSG_RENDER_RESULT,
  PDF_RENDER_MSG_REPLACE,
  PDF_RENDER_WORKER_POOL_SIZE_MAX,
  PDF_RENDER_WORKER_POOL_SIZE_MIN,
  PdfRenderHostToWorkerMessage,
  PdfRenderOpenResultMessage,
  PdfRenderPageResultMessage,
  PdfRenderProbeResultMessage,
  PdfRenderReleaseResultMessage,
  RasterPriority
} from './PdfRenderWorkerProtocol';

const WORKER_SCRIPT_URL: string = 'entry/ets/workers/PdfRenderWorker.ets';

/**
 * 按 deviceInfo.performanceClass（及 2in1 形态）决定光栅 Worker 池大小。
 * 常量信息只需读一次；池在首次 open 时创建，不随 MemoryLevel 热调整。
 */
export function resolvePdfRenderWorkerPoolSize(): number {
  const perfClass = deviceInfo.performanceClass;
  const is2in1: boolean = deviceInfo.deviceType === '2in1';
  let size: number = 2;
  if (perfClass === deviceInfo.PerformanceClassLevel.CLASS_LEVEL_HIGH) {
    size = 4;
  } else if (perfClass === deviceInfo.PerformanceClassLevel.CLASS_LEVEL_LOW) {
    size = 1;
  } else {
    // MEDIUM 或未知：默认 2；2in1 提到 3
    size = is2in1 ? 3 : 2;
  }
  if (size < PDF_RENDER_WORKER_POOL_SIZE_MIN) {
    size = PDF_RENDER_WORKER_POOL_SIZE_MIN;
  }
  if (size > PDF_RENDER_WORKER_POOL_SIZE_MAX) {
    size = PDF_RENDER_WORKER_POOL_SIZE_MAX;
  }
  return size;
}

interface PendingVoidRequest {
  resolve: () => void;
  reject: (error: Error) => void;
}

interface PendingRenderRequest {
  resolve: (cache: PageCache) => void;
  reject: (error: Error) => void;
}

interface PendingProbeRequest {
  resolve: (indices: number[]) => void;
  reject: (error: Error) => void;
}

interface QueuedRenderJob {
  requestId: number;
  sessionGeneration: number;
  pageIndex: number;
  renderScale: number;
  priority: number;
}

class WorkerSlot {
  index: number = 0;
  threadWorker: worker.ThreadWorker | undefined = undefined;
  busy: boolean = false;
  inFlightRequestId: number = -1;
}

/** 可取消的光栅请求句柄 */
export interface PdfRenderHandle {
  requestId: number;
  promise: Promise<PageCache>;
}

/**
 * 主线程侧 PDF 光栅会话：多 Worker 池 + 主机优先级队列。
 * 每名 Worker 各自 load 文档一次；render 由主机按优先级派发到空闲 Worker。
 */
export class PdfRenderSession {
  private static instance: PdfRenderSession | undefined = undefined;

  private slots: WorkerSlot[] = [];
  private nextRequestId: number = 1;
  private sessionGeneration: number = 0;
  private lastDocumentPath: string = '';
  private lastPassword: string = '';
  private documentReady: boolean = false;
  private readyChain: Promise<void> = Promise.resolve();

  /** 主机侧优先级队列（HIGH 在前） */
  private renderQueue: QueuedRenderJob[] = [];
  /** 内存压力下限制同时忙碌的 Worker 数（不销毁池） */
  private maxActiveWorkers: number = PDF_RENDER_WORKER_POOL_SIZE_MAX;

  private pendingOpen: Map<number, PendingVoidRequest> = new Map();
  private pendingRelease: Map<number, PendingVoidRequest> = new Map();
  private pendingRender: Map<number, PendingRenderRequest> = new Map();
  private pendingProbe: Map<number, PendingProbeRequest> = new Map();

  static getInstance(): PdfRenderSession {
    if (PdfRenderSession.instance === undefined) {
      PdfRenderSession.instance = new PdfRenderSession();
    }
    return PdfRenderSession.instance;
  }

  isDocumentReady(): boolean {
    return this.documentReady;
  }

  async open(path: string, password: string): Promise<void> {
    const op = this.runExclusive((): Promise<void> => this.openInternal(PDF_RENDER_MSG_OPEN, path, password));
    this.readyChain = op.catch((): void => {
    });
    await op;
  }

  async replace(path: string, password?: string): Promise<void> {
    const pwd = password !== undefined ? password : this.lastPassword;
    const op = this.runExclusive((): Promise<void> => this.openInternal(PDF_RENDER_MSG_REPLACE, path, pwd));
    this.readyChain = op.catch((): void => {
    });
    await op;
  }

  async release(): Promise<void> {
    const op = this.runExclusive((): Promise<void> => this.releaseInternal());
    this.readyChain = op.catch((): void => {
    });
    await op;
  }

  async render(pageIndex: number, renderScale: number, priority: RasterPriority): Promise<PageCache> {
    const handle = await this.renderHandle(pageIndex, renderScale, priority);
    return handle.promise;
  }

  async renderHandle(pageIndex: number, renderScale: number, priority: RasterPriority): Promise<PdfRenderHandle> {
    await this.readyChain;
    if (!this.documentReady || this.slots.length === 0) {
      throw new Error('PdfRenderSession 文档未打开');
    }
    const requestId = this.allocRequestId();
    const generation = this.sessionGeneration;
    const promise = new Promise<PageCache>((resolve: (cache: PageCache) => void, reject: (error: Error) => void) => {
      const pending: PendingRenderRequest = { resolve: resolve, reject: reject };
      this.pendingRender.set(requestId, pending);
    });

    const job: QueuedRenderJob = {
      requestId: requestId,
      sessionGeneration: generation,
      pageIndex: pageIndex,
      renderScale: renderScale,
      priority: priority
    };
    this.enqueueJob(job);
    this.dispatchQueue();

    const handle: PdfRenderHandle = {
      requestId: requestId,
      promise: promise
    };
    return handle;
  }

  cancel(requestId: number): void {
    const pending = this.pendingRender.get(requestId);
    if (pending !== undefined) {
      this.pendingRender.delete(requestId);
      pending.reject(new Error('canceled'));
    }
    // 仍在主机队列中则直接移除
    for (let i = 0; i < this.renderQueue.length; i++) {
      if (this.renderQueue[i].requestId === requestId) {
        this.renderQueue.splice(i, 1);
        return;
      }
    }
    // 已派发飞行中：结果返回时按 pending 缺失丢弃
  }

  /**
   * 取消主机队列中不在 keep 集合内的光栅任务。
   * 不拒绝已派发到 Worker 的飞行中请求，以便完成后仍写入缓存。
   */
  cancelQueuedExcept(keepPageIndices: number[]): number[] {
    const cancelledIds: number[] = [];
    const kept: QueuedRenderJob[] = [];
    for (let i = 0; i < this.renderQueue.length; i++) {
      const job = this.renderQueue[i];
      if (keepPageIndices.indexOf(job.pageIndex) >= 0) {
        kept.push(job);
      } else {
        cancelledIds.push(job.requestId);
        const pending = this.pendingRender.get(job.requestId);
        if (pending !== undefined) {
          this.pendingRender.delete(job.requestId);
          pending.reject(new Error('canceled'));
        }
      }
    }
    this.renderQueue = kept;
    if (cancelledIds.length > 0) {
      hilog.info(0, 'PdfRenderSession',
        '已取消过期排队光栅 count=' + cancelledIds.length.toString());
    }
    return cancelledIds;
  }

  cancelAll(): void {
    const renderIds: number[] = [];
    this.pendingRender.forEach((_value: PendingRenderRequest, key: number) => {
      renderIds.push(key);
    });
    for (let i = 0; i < renderIds.length; i++) {
      const pending = this.pendingRender.get(renderIds[i]);
      if (pending !== undefined) {
        pending.reject(new Error('canceled'));
      }
    }
    this.pendingRender.clear();
    this.renderQueue = [];
  }

  /**
   * 内存压力：可选清空排队任务，并限制同时派发的 Worker 数（池本身不销毁）。
   */
  applyMemoryPressurePolicy(cancelQueued: boolean, maxActiveWorkers: number): void {
    if (cancelQueued) {
      this.cancelAll();
    }
    let cap = maxActiveWorkers;
    if (cap < 1) {
      cap = 1;
    }
    if (this.slots.length > 0 && cap > this.slots.length) {
      cap = this.slots.length;
    }
    if (this.slots.length === 0 && cap > PDF_RENDER_WORKER_POOL_SIZE_MAX) {
      cap = PDF_RENDER_WORKER_POOL_SIZE_MAX;
    }
    this.maxActiveWorkers = cap;
    hilog.info(0, 'PdfRenderSession',
      '内存压力调度 cancelQueued=' + (cancelQueued ? '1' : '0') +
        ' maxActiveWorkers=' + this.maxActiveWorkers.toString());
  }

  async probePolylines(startPageIndex: number, endPageIndex: number): Promise<number[]> {
    await this.readyChain;
    if (!this.documentReady || this.slots.length === 0) {
      throw new Error('PdfRenderSession 文档未打开');
    }
    const slot = this.slots[0];
    if (slot.threadWorker === undefined) {
      throw new Error('PdfRenderWorker 未创建');
    }

    const requestId = this.allocRequestId();
    const generation = this.sessionGeneration;
    const promise = new Promise<number[]>((resolve: (indices: number[]) => void, reject: (error: Error) => void) => {
      const pending: PendingProbeRequest = { resolve: resolve, reject: reject };
      this.pendingProbe.set(requestId, pending);
    });

    const msg = createEmptyHostToWorkerMessage();
    msg.type = PDF_RENDER_MSG_PROBE_POLYLINES;
    msg.requestId = requestId;
    msg.sessionGeneration = generation;
    msg.startPageIndex = startPageIndex;
    msg.endPageIndex = endPageIndex;
    this.postToSlot(slot, msg);
    return promise;
  }

  private runExclusive(op: () => Promise<void>): Promise<void> {
    const next = this.readyChain.then(op, op);
    this.readyChain = next.catch((): void => {
    });
    return next;
  }

  private enqueueJob(job: QueuedRenderJob): void {
    let insertAt: number = this.renderQueue.length;
    for (let i = 0; i < this.renderQueue.length; i++) {
      // 同优先级插到该档最前（LIFO），最新导航页先于过期 HIGH 任务派发
      if (this.renderQueue[i].priority <= job.priority) {
        insertAt = i;
        break;
      }
    }
    this.renderQueue.splice(insertAt, 0, job);
  }

  private dispatchQueue(): void {
    if (!this.documentReady) {
      return;
    }
    while (this.renderQueue.length > 0) {
      const slot = this.findIdleSlot();
      if (slot === undefined) {
        break;
      }
      const job = this.renderQueue.shift();
      if (job === undefined) {
        break;
      }
      if (job.sessionGeneration !== this.sessionGeneration) {
        const pending = this.pendingRender.get(job.requestId);
        if (pending !== undefined) {
          this.pendingRender.delete(job.requestId);
          pending.reject(new Error('session stale'));
        }
        continue;
      }
      if (!this.pendingRender.has(job.requestId)) {
        // 已在排队期间被 cancel
        continue;
      }
      this.dispatchJobToSlot(slot, job);
    }
  }

  private countBusySlots(): number {
    let busy = 0;
    for (let i = 0; i < this.slots.length; i++) {
      if (this.slots[i].busy) {
        busy++;
      }
    }
    return busy;
  }

  private findIdleSlot(): WorkerSlot | undefined {
    if (this.countBusySlots() >= this.maxActiveWorkers) {
      return undefined;
    }
    for (let i = 0; i < this.slots.length; i++) {
      if (!this.slots[i].busy && this.slots[i].threadWorker !== undefined) {
        return this.slots[i];
      }
    }
    return undefined;
  }

  private dispatchJobToSlot(slot: WorkerSlot, job: QueuedRenderJob): void {
    slot.busy = true;
    slot.inFlightRequestId = job.requestId;
    const msg = createEmptyHostToWorkerMessage();
    msg.type = PDF_RENDER_MSG_RENDER;
    msg.requestId = job.requestId;
    msg.sessionGeneration = job.sessionGeneration;
    msg.pageIndex = job.pageIndex;
    msg.renderScale = job.renderScale;
    msg.priority = job.priority;
    try {
      this.postToSlot(slot, msg);
    } catch (error) {
      slot.busy = false;
      slot.inFlightRequestId = -1;
      const pending = this.pendingRender.get(job.requestId);
      if (pending !== undefined) {
        this.pendingRender.delete(job.requestId);
        const message = error instanceof Error ? error.message : '' + error;
        pending.reject(new Error(message));
      }
      this.dispatchQueue();
    }
  }

  private markSlotIdleByRequest(requestId: number): void {
    for (let i = 0; i < this.slots.length; i++) {
      const slot = this.slots[i];
      if (slot.inFlightRequestId === requestId) {
        slot.busy = false;
        slot.inFlightRequestId = -1;
        return;
      }
    }
  }

  private async openInternal(msgType: string, path: string, password: string): Promise<void> {
    this.ensurePool();
    this.rejectAllPending(new Error('document replaced'));
    this.renderQueue = [];
    this.resetSlotBusyFlags();
    this.sessionGeneration++;
    this.documentReady = false;
    this.lastDocumentPath = path;
    this.lastPassword = password;

    const generation = this.sessionGeneration;
    const opens: Promise<void>[] = [];
    for (let i = 0; i < this.slots.length; i++) {
      opens.push(this.openOneSlot(this.slots[i], msgType, path, password, generation));
    }
    try {
      await Promise.all(opens);
    } catch (error) {
      this.documentReady = false;
      // 部分 Worker 可能已打开：整池释放后由上层重试
      try {
        await this.releaseInternal();
      } catch (_releaseErr) {
      }
      if (error instanceof Error) {
        throw error;
      }
      throw new Error('' + error);
    }
    this.documentReady = true;
    hilog.info(0, 'PdfRenderSession',
      'Worker 池已就绪 size=' + this.slots.length.toString() + ' path=' + path);
    this.dispatchQueue();
  }

  private openOneSlot(
    slot: WorkerSlot,
    msgType: string,
    path: string,
    password: string,
    generation: number
  ): Promise<void> {
    const requestId = this.allocRequestId();
    const promise = new Promise<void>((resolve: () => void, reject: (error: Error) => void) => {
      const pending: PendingVoidRequest = { resolve: resolve, reject: reject };
      this.pendingOpen.set(requestId, pending);
    });
    const msg = createEmptyHostToWorkerMessage();
    msg.type = msgType;
    msg.requestId = requestId;
    msg.sessionGeneration = generation;
    msg.documentPath = path;
    msg.openPassword = password;
    this.postToSlot(slot, msg);
    return promise;
  }

  private async releaseInternal(): Promise<void> {
    if (this.slots.length === 0) {
      this.documentReady = false;
      this.lastDocumentPath = '';
      return;
    }

    this.rejectAllPending(new Error('document released'));
    this.renderQueue = [];
    this.sessionGeneration++;
    this.documentReady = false;

    const generation = this.sessionGeneration;
    const releases: Promise<void>[] = [];
    for (let i = 0; i < this.slots.length; i++) {
      releases.push(this.releaseOneSlot(this.slots[i], generation));
    }
    try {
      await Promise.all(releases);
    } finally {
      this.terminatePool();
      this.lastDocumentPath = '';
    }
  }

  private releaseOneSlot(slot: WorkerSlot, generation: number): Promise<void> {
    if (slot.threadWorker === undefined) {
      return Promise.resolve();
    }
    const requestId = this.allocRequestId();
    const promise = new Promise<void>((resolve: () => void, reject: (error: Error) => void) => {
      const pending: PendingVoidRequest = { resolve: resolve, reject: reject };
      this.pendingRelease.set(requestId, pending);
    });
    const msg = createEmptyHostToWorkerMessage();
    msg.type = PDF_RENDER_MSG_RELEASE;
    msg.requestId = requestId;
    msg.sessionGeneration = generation;
    this.postToSlot(slot, msg);
    return promise;
  }

  private ensurePool(): void {
    if (this.slots.length > 0) {
      return;
    }
    const poolSize: number = resolvePdfRenderWorkerPoolSize();
    this.maxActiveWorkers = poolSize;
    for (let i = 0; i < poolSize; i++) {
      const slot = new WorkerSlot();
      slot.index = i;
      const tw = new worker.ThreadWorker(WORKER_SCRIPT_URL);
      const slotIndex = i;
      tw.onmessage = (e: MessageEvents): void => {
        this.handleWorkerMessage(e);
      };
      tw.onerror = (err: ErrorEvent): void => {
        hilog.error(0, 'PdfRenderSession',
          'Worker[' + slotIndex.toString() + '] onerror: ' + err.message);
      };
      tw.onexit = (): void => {
        hilog.info(0, 'PdfRenderSession', 'Worker[' + slotIndex.toString() + '] 已退出');
      };
      slot.threadWorker = tw;
      this.slots.push(slot);
    }
    hilog.info(0, 'PdfRenderSession',
      '已创建 Worker 池 size=' + poolSize.toString() +
        ' performanceClass=' + deviceInfo.performanceClass.toString() +
        ' deviceType=' + deviceInfo.deviceType);
  }

  private resetSlotBusyFlags(): void {
    for (let i = 0; i < this.slots.length; i++) {
      this.slots[i].busy = false;
      this.slots[i].inFlightRequestId = -1;
    }
  }

  private terminatePool(): void {
    for (let i = 0; i < this.slots.length; i++) {
      const slot = this.slots[i];
      const tw = slot.threadWorker;
      slot.threadWorker = undefined;
      slot.busy = false;
      slot.inFlightRequestId = -1;
      if (tw !== undefined) {
        try {
          tw.terminate();
        } catch (_e) {
        }
      }
    }
    this.slots = [];
    this.documentReady = false;
  }

  private postToSlot(slot: WorkerSlot, msg: PdfRenderHostToWorkerMessage): void {
    const tw = slot.threadWorker;
    if (tw === undefined) {
      throw new Error('PdfRenderWorker[' + slot.index.toString() + '] 未创建');
    }
    try {
      tw.postMessage(msg);
    } catch (error) {
      const message = error instanceof Error ? error.message : '' + error;
      hilog.error(0, 'PdfRenderSession', 'postMessage 失败: ' + message);
      throw new Error('postMessage 失败: ' + message);
    }
  }

  private allocRequestId(): number {
    const id = this.nextRequestId;
    this.nextRequestId++;
    return id;
  }

  private rejectAllPending(error: Error): void {
    this.pendingOpen.forEach((pending: PendingVoidRequest) => {
      pending.reject(error);
    });
    this.pendingOpen.clear();
    this.pendingRelease.forEach((pending: PendingVoidRequest) => {
      pending.reject(error);
    });
    this.pendingRelease.clear();
    this.pendingRender.forEach((pending: PendingRenderRequest) => {
      pending.reject(error);
    });
    this.pendingRender.clear();
    this.pendingProbe.forEach((pending: PendingProbeRequest) => {
      pending.reject(error);
    });
    this.pendingProbe.clear();
  }

  private handleWorkerMessage(e: MessageEvents): void {
    const dataObject: Object = e.data as Object;
    const typeField = (dataObject as PdfRenderOpenResultMessage).type;
    if (typeField === PDF_RENDER_MSG_OPEN_RESULT) {
      this.handleOpenResult(dataObject as PdfRenderOpenResultMessage);
      return;
    }
    if (typeField === PDF_RENDER_MSG_RELEASE_RESULT) {
      this.handleReleaseResult(dataObject as PdfRenderReleaseResultMessage);
      return;
    }
    if (typeField === PDF_RENDER_MSG_RENDER_RESULT) {
      this.handleRenderResult(dataObject as PdfRenderPageResultMessage);
      return;
    }
    if (typeField === PDF_RENDER_MSG_PROBE_RESULT) {
      this.handleProbeResult(dataObject as PdfRenderProbeResultMessage);
      return;
    }
    hilog.warn(0, 'PdfRenderSession', '未知 Worker 消息');
  }

  private handleOpenResult(msg: PdfRenderOpenResultMessage): void {
    const pending = this.pendingOpen.get(msg.requestId);
    if (pending === undefined) {
      return;
    }
    this.pendingOpen.delete(msg.requestId);
    if (msg.sessionGeneration !== this.sessionGeneration) {
      pending.reject(new Error('session stale'));
      return;
    }
    if (!msg.ok) {
      pending.reject(new Error(msg.errorMessage.length > 0 ? msg.errorMessage : '打开文档失败'));
      return;
    }
    pending.resolve();
  }

  private handleReleaseResult(msg: PdfRenderReleaseResultMessage): void {
    const pending = this.pendingRelease.get(msg.requestId);
    if (pending === undefined) {
      return;
    }
    this.pendingRelease.delete(msg.requestId);
    if (!msg.ok) {
      pending.reject(new Error(msg.errorMessage.length > 0 ? msg.errorMessage : '释放文档失败'));
      return;
    }
    pending.resolve();
  }

  private handleRenderResult(msg: PdfRenderPageResultMessage): void {
    this.markSlotIdleByRequest(msg.requestId);
    const pending = this.pendingRender.get(msg.requestId);
    if (pending === undefined) {
      this.releaseTransferredMaps(msg.pixelMap, msg.layoutPixelMap);
      this.dispatchQueue();
      return;
    }
    this.pendingRender.delete(msg.requestId);
    if (msg.sessionGeneration !== this.sessionGeneration || msg.canceled || !msg.ok || msg.pixelMap === undefined) {
      this.releaseTransferredMaps(msg.pixelMap, msg.layoutPixelMap);
      pending.reject(new Error(
        msg.canceled ? 'canceled' : (msg.errorMessage.length > 0 ? msg.errorMessage : '光栅失败')
      ));
      this.dispatchQueue();
      return;
    }

    const cache: PageCache = {
      pixelMap: msg.pixelMap,
      layoutPixelMap: msg.layoutPixelMap,
      renderScale: msg.renderScale,
      baseSize: Vec2(msg.baseWidth, msg.baseHeight),
      displaySize: Vec2(msg.displayWidth, msg.displayHeight)
    };
    pending.resolve(cache);
    this.dispatchQueue();
  }

  private handleProbeResult(msg: PdfRenderProbeResultMessage): void {
    const pending = this.pendingProbe.get(msg.requestId);
    if (pending === undefined) {
      return;
    }
    this.pendingProbe.delete(msg.requestId);
    if (msg.sessionGeneration !== this.sessionGeneration || !msg.ok) {
      pending.reject(new Error(msg.errorMessage.length > 0 ? msg.errorMessage : '探测失败'));
      return;
    }
    pending.resolve(msg.pageIndices);
  }

  private releaseTransferredMaps(pixelMap: PixelMap | undefined, layoutPixelMap: PixelMap | undefined): void {
    if (pixelMap !== undefined) {
      try {
        pixelMap.release();
      } catch (_e) {
      }
    }
    if (layoutPixelMap !== undefined) {
      try {
        layoutPixelMap.release();
      } catch (_e) {
      }
    }
  }
}
