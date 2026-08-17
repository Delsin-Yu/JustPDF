import { preferences } from '@kit.ArkData';
import { pdfService } from '@kit.PDFKit';
import { taskpool } from '@kit.ArkTS';
import { PageStore } from '../../common/page/PageStore';
import { AnnotationLayer, AnnotationLayerListItem } from '../../common/page/AnnotationLayer';
import { ReadonlyStroke, Stroke } from '../../common/page/Stroke';
import { Vector2 } from '../../common/ui/Numbers';
import { PDFAnnotateMode } from '../viewer/PDFViewerViewModel';

/** 进入批注模式准备各阶段文案（右上角指示器） */
export interface AnnotatePreparePhaseOptions {
  /** 为 true 时禁止绘制/改书签（仅用于主线程写入阶段） */
  blocksEditing?: boolean;
}

/**
 * 批注控制器所需的页笔画 / 折线导入 / 页缓存窄接口（由 PageStore 适配）。
 */
export interface StrokeStore {
  totalPageCount(): number;
  getPageStrokesCount(pageIndex: number): number;
  hasUnsavedStrokeEdits(pageIndex: number): boolean;
  getPageRawSize(pageIndex: number): Vector2;
  iteratePageStrokes(pageIndex: number): Iterable<ReadonlyStroke>;
  strokePage(pageIndex: number, renderingContext: CanvasRenderingContext2D): void;
  addStroke(pageIndex: number, pathWithPoints: Stroke): void;
  removeStroke(pageIndex: number, pathWithPoints: Stroke): void;
  removeStrokeWhere(pageIndex: number, predicate: (stroke: ReadonlyStroke) => boolean): void;
  clearAllStrokes(): void;
  getPageLayers(pageIndex: number): AnnotationLayer[];
  getPageLayer(pageIndex: number, layerId: string): AnnotationLayer | undefined;
  getPageLayerItems(pageIndex: number): AnnotationLayerListItem[];
  getActiveLayerId(pageIndex: number): string;
  isPageStrokeVisible(pageIndex: number, stroke: ReadonlyStroke): boolean;
  setActiveLayer(pageIndex: number, layerId: string): boolean;
  setLayerVisible(pageIndex: number, layerId: string, visible: boolean): boolean;
  addDefaultNamedLayer(pageIndex: number): AnnotationLayer;
  renameLayer(pageIndex: number, layerId: string, name: string): boolean;
  deleteLayer(pageIndex: number, layerId: string): Stroke[];
  ensureActiveLayerVisible(pageIndex: number): boolean;
  invalidateCaches(pageIndex: number): void;
  setPagePath(pagePath: string): void;
  ensureCached(pageIndex: number, renderScale: number, priority: taskpool.Priority): void;
  probePolylineAnnotationPageIndices(
    documentPath: string,
    openPassword: string,
    onBatchComplete?: (processedEnd: number, total: number) => void
  ): Promise<number[]>;
  importPdfPolylineAnnotationsRange(
    uiContext: UIContext,
    canvasOverSampling: number,
    startPageIndex: number,
    endPageIndex: number
  ): number[];
  getImportedPdfPolylinePageIndices(): number[];
  clearImportedPdfPolylineTracking(): void;
  restoreImportedPdfPolylineAnnotations(): number[];
  addPdfAnnotations(pageIndex: number, annotationInfo: pdfService.PdfAnnotationInfo[]): pdfService.PdfAnnotation[];
  removePdfAnnotations(pageIndex: number, annotations: pdfService.PdfAnnotation[]): void;
}

/**
 * 批注保存 / 预览写入所需的文档与路径访问。
 */
export interface DocumentIO {
  getDocument(): pdfService.PdfDocument;
  getSystemPath(): string;
  getSandBoxPath(): string;
  getOpenPassword(): string;
  getSaveTempPath(): string;
  getFileName(): string;
  getUIContext(): UIContext;
  getPreferences(): preferences.Preferences | undefined;
}

/**
 * 批注撤销/重做等场景下的页导航与阅读态。
 */
export interface PageNavigator {
  gotoPage(pageIndex: number): void;
  getDisplayedPageIndices(): number[];
  getTotalPageCount(): number;
  getAnnotateMode(): PDFAnnotateMode;
  setAnnotateMode(mode: PDFAnnotateMode): void;
}

/**
 * 批注准备会话的 UI 状态回调（PDFView 仅镜像指示器状态）。
 */
export interface AnnotationPrepareUiCallbacks {
  onPreparePhase(message: string, options?: AnnotatePreparePhaseOptions): void;
  clearPrepareStatus(): void;
}

/**
 * 保存阶段与重绘/刷新宿主回调。
 */
export interface AnnotationHostCallbacks {
  onRedrawRequested(): void;
  onRefreshDisplayedPages(): Promise<void>;
  onSavePhase(message: string): void;
}

/** PageStore → StrokeStore 适配器 */
export class PageStoreStrokeStore implements StrokeStore {
  private readonly pageStore: PageStore;

  constructor(pageStore: PageStore) {
    this.pageStore = pageStore;
  }

  totalPageCount(): number {
    return this.pageStore.totalPageCount();
  }

  getPageStrokesCount(pageIndex: number): number {
    return this.pageStore.getPageStrokesCount(pageIndex);
  }

  hasUnsavedStrokeEdits(pageIndex: number): boolean {
    return this.pageStore.hasUnsavedStrokeEdits(pageIndex);
  }

  getPageRawSize(pageIndex: number): Vector2 {
    return this.pageStore.getPageRawSize(pageIndex);
  }

  iteratePageStrokes(pageIndex: number): Iterable<ReadonlyStroke> {
    return this.pageStore.iteratePageStrokes(pageIndex);
  }

  strokePage(pageIndex: number, renderingContext: CanvasRenderingContext2D): void {
    this.pageStore.strokePage(pageIndex, renderingContext);
  }

  addStroke(pageIndex: number, pathWithPoints: Stroke): void {
    this.pageStore.addStroke(pageIndex, pathWithPoints);
  }

  removeStroke(pageIndex: number, pathWithPoints: Stroke): void {
    this.pageStore.removeStroke(pageIndex, pathWithPoints);
  }

  removeStrokeWhere(pageIndex: number, predicate: (stroke: ReadonlyStroke) => boolean): void {
    this.pageStore.removeStrokeWhere(pageIndex, predicate);
  }

  clearAllStrokes(): void {
    this.pageStore.clearAllStrokes();
  }

  getPageLayers(pageIndex: number): AnnotationLayer[] {
    return this.pageStore.getPageLayers(pageIndex);
  }

  getPageLayer(pageIndex: number, layerId: string): AnnotationLayer | undefined {
    return this.pageStore.getPageLayer(pageIndex, layerId);
  }

  getPageLayerItems(pageIndex: number): AnnotationLayerListItem[] {
    return this.pageStore.getPageLayerItems(pageIndex);
  }

  getActiveLayerId(pageIndex: number): string {
    return this.pageStore.getActiveLayerId(pageIndex);
  }

  isPageStrokeVisible(pageIndex: number, stroke: ReadonlyStroke): boolean {
    return this.pageStore.isPageStrokeVisible(pageIndex, stroke);
  }

  setActiveLayer(pageIndex: number, layerId: string): boolean {
    return this.pageStore.setActiveLayer(pageIndex, layerId);
  }

  setLayerVisible(pageIndex: number, layerId: string, visible: boolean): boolean {
    return this.pageStore.setLayerVisible(pageIndex, layerId, visible);
  }

  addDefaultNamedLayer(pageIndex: number): AnnotationLayer {
    return this.pageStore.addDefaultNamedLayer(pageIndex);
  }

  renameLayer(pageIndex: number, layerId: string, name: string): boolean {
    return this.pageStore.renameLayer(pageIndex, layerId, name);
  }

  deleteLayer(pageIndex: number, layerId: string): Stroke[] {
    return this.pageStore.deleteLayer(pageIndex, layerId);
  }

  ensureActiveLayerVisible(pageIndex: number): boolean {
    return this.pageStore.ensureActiveLayerVisible(pageIndex);
  }

  invalidateCaches(pageIndex: number): void {
    this.pageStore.invalidateCaches(pageIndex);
  }

  setPagePath(pagePath: string): void {
    this.pageStore.setPagePath(pagePath);
  }

  ensureCached(pageIndex: number, renderScale: number, priority: taskpool.Priority): void {
    this.pageStore.ensureCached(pageIndex, renderScale, priority);
  }

  probePolylineAnnotationPageIndices(
    documentPath: string,
    openPassword: string,
    onBatchComplete?: (processedEnd: number, total: number) => void
  ): Promise<number[]> {
    return this.pageStore.probePolylineAnnotationPageIndices(documentPath, openPassword, onBatchComplete);
  }

  importPdfPolylineAnnotationsRange(
    uiContext: UIContext,
    canvasOverSampling: number,
    startPageIndex: number,
    endPageIndex: number
  ): number[] {
    return this.pageStore.importPdfPolylineAnnotationsRange(
      uiContext,
      canvasOverSampling,
      startPageIndex,
      endPageIndex
    );
  }

  getImportedPdfPolylinePageIndices(): number[] {
    return this.pageStore.getImportedPdfPolylinePageIndices();
  }

  clearImportedPdfPolylineTracking(): void {
    this.pageStore.clearImportedPdfPolylineTracking();
  }

  restoreImportedPdfPolylineAnnotations(): number[] {
    return this.pageStore.restoreImportedPdfPolylineAnnotations();
  }

  addPdfAnnotations(pageIndex: number, annotationInfo: pdfService.PdfAnnotationInfo[]): pdfService.PdfAnnotation[] {
    return this.pageStore.addPdfAnnotations(pageIndex, annotationInfo);
  }

  removePdfAnnotations(pageIndex: number, annotations: pdfService.PdfAnnotation[]): void {
    this.pageStore.removePdfAnnotations(pageIndex, annotations);
  }
}

export interface PDFAnnotationDocumentIOCallbacks {
  getDocument: () => pdfService.PdfDocument;
  getSystemPath: () => string;
  getSandBoxPath: () => string;
  getOpenPassword: () => string;
  getSaveTempPath: () => string;
  getFileName: () => string;
  getUIContext: () => UIContext;
  getPreferences: () => preferences.Preferences | undefined;
}

/** 宿主路径 / PdfDocument / Preferences → DocumentIO */
export class PDFAnnotationDocumentIO implements DocumentIO {
  private readonly callbacks: PDFAnnotationDocumentIOCallbacks;

  constructor(callbacks: PDFAnnotationDocumentIOCallbacks) {
    this.callbacks = callbacks;
  }

  getDocument(): pdfService.PdfDocument {
    return this.callbacks.getDocument();
  }

  getSystemPath(): string {
    return this.callbacks.getSystemPath();
  }

  getSandBoxPath(): string {
    return this.callbacks.getSandBoxPath();
  }

  getOpenPassword(): string {
    return this.callbacks.getOpenPassword();
  }

  getSaveTempPath(): string {
    return this.callbacks.getSaveTempPath();
  }

  getFileName(): string {
    return this.callbacks.getFileName();
  }

  getUIContext(): UIContext {
    return this.callbacks.getUIContext();
  }

  getPreferences(): preferences.Preferences | undefined {
    return this.callbacks.getPreferences();
  }
}

export interface PDFAnnotationPageNavigatorCallbacks {
  gotoPage: (pageIndex: number) => void;
  getDisplayedPageIndices: () => number[];
  getTotalPageCount: () => number;
  getAnnotateMode: () => PDFAnnotateMode;
  setAnnotateMode: (mode: PDFAnnotateMode) => void;
}

/** 宿主翻页 / 批注模式 → PageNavigator */
export class PDFAnnotationPageNavigator implements PageNavigator {
  private readonly callbacks: PDFAnnotationPageNavigatorCallbacks;

  constructor(callbacks: PDFAnnotationPageNavigatorCallbacks) {
    this.callbacks = callbacks;
  }

  gotoPage(pageIndex: number): void {
    this.callbacks.gotoPage(pageIndex);
  }

  getDisplayedPageIndices(): number[] {
    return this.callbacks.getDisplayedPageIndices();
  }

  getTotalPageCount(): number {
    return this.callbacks.getTotalPageCount();
  }

  getAnnotateMode(): PDFAnnotateMode {
    return this.callbacks.getAnnotateMode();
  }

  setAnnotateMode(mode: PDFAnnotateMode): void {
    this.callbacks.setAnnotateMode(mode);
  }
}

export interface PDFAnnotationPrepareUiCallbackFns {
  onPreparePhase: (message: string, options?: AnnotatePreparePhaseOptions) => void;
  clearPrepareStatus: () => void;
}

export class PDFAnnotationPrepareUiBridge implements AnnotationPrepareUiCallbacks {
  private readonly callbacks: PDFAnnotationPrepareUiCallbackFns;

  constructor(callbacks: PDFAnnotationPrepareUiCallbackFns) {
    this.callbacks = callbacks;
  }

  onPreparePhase(message: string, options?: AnnotatePreparePhaseOptions): void {
    this.callbacks.onPreparePhase(message, options);
  }

  clearPrepareStatus(): void {
    this.callbacks.clearPrepareStatus();
  }
}

export interface PDFAnnotationHostCallbackFns {
  onRedrawRequested: () => void;
  onRefreshDisplayedPages: () => Promise<void>;
  onSavePhase: (message: string) => void;
}

export class PDFAnnotationHostBridge implements AnnotationHostCallbacks {
  private readonly callbacks: PDFAnnotationHostCallbackFns;

  constructor(callbacks: PDFAnnotationHostCallbackFns) {
    this.callbacks = callbacks;
  }

  onRedrawRequested(): void {
    this.callbacks.onRedrawRequested();
  }

  onRefreshDisplayedPages(): Promise<void> {
    return this.callbacks.onRefreshDisplayedPages();
  }

  onSavePhase(message: string): void {
    this.callbacks.onSavePhase(message);
  }
}

/**
 * PDFAnnotationController 的具名依赖包：窄接口组合，避免直接闭包 PDFView 大量 @Local。
 */
export class PDFAnnotationControllerDependencies {
  readonly strokes: StrokeStore;
  readonly documentIO: DocumentIO;
  readonly pageNavigator: PageNavigator;
  readonly prepareUi: AnnotationPrepareUiCallbacks;
  readonly host: AnnotationHostCallbacks;

  constructor(
    strokes: StrokeStore,
    documentIO: DocumentIO,
    pageNavigator: PageNavigator,
    prepareUi: AnnotationPrepareUiCallbacks,
    host: AnnotationHostCallbacks
  ) {
    this.strokes = strokes;
    this.documentIO = documentIO;
    this.pageNavigator = pageNavigator;
    this.prepareUi = prepareUi;
    this.host = host;
  }
}
