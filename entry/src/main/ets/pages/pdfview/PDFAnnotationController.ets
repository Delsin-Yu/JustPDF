import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { pdfService } from '@kit.PDFKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { taskpool, util } from '@kit.ArkTS';
import { showAlertDialog } from '../../components/UIComponents';
import { Stack as DataStack } from '../../components/Colletions';
import { History, NewStroke, PageStore, ReadonlyStroke, Stroke } from '../../components/PageInfo';
import { mul, pxToVp, Vec2, Vector2 } from '../../components/Numbers';
import { PDFAnnotateMode, PDFViewerViewModel, ViewerMinRenderScale } from './PDFViewerViewModel';
import {
  AnnotationColor,
  CustomAnnotationColorId,
  DefaultAnnotationColor,
  DefaultCustomAnnotationColor,
  customDrawColorFromPersistedPdf,
  parsePersistedPdfColorLoose,
  selectedDrawColorFromPersistedPdf
} from './PDFAnnotationColors';

const RecentCustomColorCapacity: number = 10;

const AnnotationPrefSelectedPdfKey: string = 'annotationSelectedPdfColor';
const AnnotationPrefCustomPdfKey: string = 'annotationCustomPdfColor';
const AnnotationPrefRecentCustomPdfsKey: string = 'annotationRecentCustomPdfColors';

const DefaultAnnotationCanvasOverSampling: number = 3;
const DefaultAnnotationSubject: string = '由 Just PDF 创建的注释';

/**
 * 测试用：每个保存阶段额外停留时长（毫秒）。5 个阶段合计约 ≥2.5s，便于观察右上角指示器。
 * 正式发布前请改为 0。
 */
const SAVE_DEBUG_PHASE_DELAY_MS: number = 0;
/** 主线程上逐页导入（仅对探测到的页执行，通常很少）。 */
const ANNOTATE_IMPORT_PAGE_BATCH_SIZE: number = 1;
const ANNOTATE_REFRESH_PAGE_BATCH_SIZE: number = 2;

export interface AnnotatePreparePhaseOptions {
  /** 为 true 时禁止绘制/改书签（仅用于主线程写入阶段） */
  blocksEditing?: boolean;
}

interface PDFAnnotationControllerDependencies {
  pageDataSource: PageStore;
  viewerViewModel: PDFViewerViewModel;
  document: pdfService.PdfDocument;
  getSystemPath: () => string;
  getSandBoxPath: () => string;
  getOpenPassword: () => string;
  getSaveTempPath: () => string;
  getFileName: () => string;
  getUIContext: () => UIContext;
  onRequestGotoPage: (pageIndex: number) => void;
  onRedrawRequested: () => void;
  onRefreshDisplayedPages: () => Promise<void>;
  getPreferences: () => preferences.Preferences | undefined;
  /** 保存各阶段文案（用于 PDFView 右上角指示器，不阻塞 UI） */
  onSavePhase?: (message: string) => void;
  /** 进入批注模式准备各阶段文案（右上角指示器） */
  onAnnotatePreparePhase?: (message: string, options?: AnnotatePreparePhaseOptions) => void;
  /** 为 false 时中止进行中的批注模式准备（例如用户离开页面） */
  isAnnotatePrepareSessionActive?: () => boolean;
}

function yieldToUi(): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, 0);
  });
}

export interface AnnotationTransientResetResult {
  clearedDraw: boolean;
  clearedErase: boolean;
}

@ObservedV2
export class PDFAnnotationController {
  private readonly dependencies: PDFAnnotationControllerDependencies;
  private readonly canvasOverSampling: number;
  private activeDrawPath: Stroke = NewStroke();
  private pathsToErase: Set<ReadonlyStroke> = new Set<ReadonlyStroke>();
  private undoHistory: DataStack<History> = new DataStack<History>();
  private redoHistory: DataStack<History> = new DataStack<History>();
  private importedPolylinePrepared: boolean = false;
  private drawColorPersistTimer: number | undefined = undefined;

  @Trace public hasUnsavedStrokes: boolean = false;
  @Trace public undoHistoryCount: number = 0;
  @Trace public redoHistoryCount: number = 0;
  @Trace public selectedDrawColor: AnnotationColor = DefaultAnnotationColor;
  @Trace public customDrawColor: AnnotationColor = DefaultCustomAnnotationColor;
  @Trace public recentCustomColors: AnnotationColor[] = [];

  constructor(dependencies: PDFAnnotationControllerDependencies, canvasOverSampling: number = DefaultAnnotationCanvasOverSampling) {
    this.dependencies = dependencies;
    this.canvasOverSampling = canvasOverSampling;
  }

  // 从 stagePersistence 恢复绘制色 / 自定义色槽（在 PDFView 注入 preferences 之后调用）。
  loadDrawPreferences(): void {
    const prefs: preferences.Preferences | undefined = this.dependencies.getPreferences();
    if (!prefs) {
      return;
    }
    try {
      const customRaw: number | string | boolean =
        prefs.getSync(AnnotationPrefCustomPdfKey, DefaultCustomAnnotationColor.pdfColor) as number | string | boolean;
      const customPdf: number = parsePersistedPdfColorLoose(customRaw, DefaultCustomAnnotationColor.pdfColor);
      this.customDrawColor = customDrawColorFromPersistedPdf(customPdf);

      const selectedRaw: number | string | boolean =
        prefs.getSync(AnnotationPrefSelectedPdfKey, DefaultAnnotationColor.pdfColor) as number | string | boolean;
      const selectedPdf: number = parsePersistedPdfColorLoose(selectedRaw, DefaultAnnotationColor.pdfColor);
      this.selectedDrawColor = selectedDrawColorFromPersistedPdf(selectedPdf);

      const recentJsonRaw: number | string | boolean =
        prefs.getSync(AnnotationPrefRecentCustomPdfsKey, '[]') as number | string | boolean;
      const recentJson: string = typeof recentJsonRaw === 'string' ? recentJsonRaw : '[]';
      this.recentCustomColors = this.parseRecentCustomColorsFromJson(recentJson);
    } catch (error) {
      hilog.error(0, 'PDFAnnotationController', `加载批注颜色偏好出错: ${error}.`);
    }
  }

  private serializeRecentCustomPdfColorsJson(): string {
    const pdfs: number[] = [];
    for (let i = 0; i < this.recentCustomColors.length; i++) {
      const c: AnnotationColor = this.recentCustomColors[i];
      if (c.id === CustomAnnotationColorId) {
        pdfs.push(c.pdfColor);
      }
    }
    return JSON.stringify(pdfs);
  }

  private parseRecentCustomColorsFromJson(text: string): AnnotationColor[] {
    const colors: AnnotationColor[] = [];
    try {
      const parsed: Object = JSON.parse(text) as Object;
      if (!Array.isArray(parsed)) {
        return colors;
      }
      const arr: Object[] = parsed as Object[];
      for (let i = 0; i < arr.length && colors.length < RecentCustomColorCapacity; i++) {
        const el: Object = arr[i];
        if (typeof el !== 'number' || !Number.isFinite(el)) {
          continue;
        }
        const pdf: number = Math.max(0, Math.min(0xFFFFFF, Math.floor(el as number)));
        colors.push(customDrawColorFromPersistedPdf(pdf));
      }
    } catch (_e) {
      // 偏好损坏或格式变更时忽略，保持空列表
    }
    return colors;
  }

  private persistDrawColorPreferences(): void {
    const prefs: preferences.Preferences | undefined = this.dependencies.getPreferences();
    if (!prefs) {
      return;
    }
    try {
      prefs.putSync(AnnotationPrefSelectedPdfKey, this.selectedDrawColor.pdfColor);
      prefs.putSync(AnnotationPrefCustomPdfKey, this.customDrawColor.pdfColor);
      prefs.putSync(AnnotationPrefRecentCustomPdfsKey, this.serializeRecentCustomPdfColorsJson());
      prefs.flushSync();
    } catch (error) {
      hilog.error(0, 'PDFAnnotationController', `保存批注颜色偏好出错: ${error}.`);
    }
  }

  private cancelDrawColorPersistSchedule(): void {
    if (this.drawColorPersistTimer !== undefined) {
      clearTimeout(this.drawColorPersistTimer);
      this.drawColorPersistTimer = undefined;
    }
  }

  // 自定义色在拾色器拖动时高频更新，合并写入偏好以避免频繁 flushSync。
  private schedulePersistDrawColorPreferences(): void {
    this.cancelDrawColorPersistSchedule();
    this.drawColorPersistTimer = setTimeout((): void => {
      this.drawColorPersistTimer = undefined;
      this.persistDrawColorPreferences();
    }, 220);
  }

  // 将可能挂起的自定义色防抖写入立即落盘（关闭浮窗或提交最近色时调用）。
  flushPendingDrawColorPreferences(): void {
    this.cancelDrawColorPersistSchedule();
    this.persistDrawColorPreferences();
  }

  get annotateMode(): PDFAnnotateMode {
    return this.dependencies.viewerViewModel.annotateMode;
  }

  setAnnotateMode(mode: PDFAnnotateMode): void {
    this.dependencies.viewerViewModel.setAnnotateMode(mode);
  }

  setSelectedDrawColor(color: AnnotationColor): void {
    this.cancelDrawColorPersistSchedule();
    this.selectedDrawColor = color;
    this.persistDrawColorPreferences();
  }

  // 设置自定义颜色，同时把它作为当前选中颜色用于绘制。
  setCustomDrawColor(color: AnnotationColor): void {
    this.customDrawColor = color;
    this.selectedDrawColor = color;
    this.schedulePersistDrawColorPreferences();
  }

  // 将自定义颜色提交进最近列表；同色去重并迁移到最前，最多保留 N 项。
  pushRecentCustomColor(color: AnnotationColor): void {
    if (color.id !== CustomAnnotationColorId) {
      return;
    }
    const filtered: AnnotationColor[] = [];
    for (const existing of this.recentCustomColors) {
      if (existing.pdfColor !== color.pdfColor) {
        filtered.push(existing);
      }
    }
    filtered.unshift(color);
    while (filtered.length > RecentCustomColorCapacity) {
      filtered.pop();
    }
    this.recentCustomColors = filtered;
    this.cancelDrawColorPersistSchedule();
    this.persistDrawColorPreferences();
  }

  isImportedPolylinePrepared(): boolean {
    return this.importedPolylinePrepared;
  }

  /** 新文档加载或离开 PDFView 时调用，避免沿用上一次的「已准备」状态。 */
  resetImportedPolylinePrepareState(): void {
    this.importedPolylinePrepared = false;
  }

  async prepareImportedPolylineAnnotations(): Promise<void> {
    if (this.importedPolylinePrepared) {
      return;
    }

    const documentPath = this.dependencies.getSandBoxPath();
    const openPassword = this.dependencies.getOpenPassword();
    const totalPageCount = this.dependencies.pageDataSource.totalPageCount();
    let lastReportedPercent = -1;

    await this.reportAnnotatePreparePhase('正在扫描批注…', false);
    const candidatePageIndices = await this.dependencies.pageDataSource.probePolylineAnnotationPageIndices(
      documentPath,
      openPassword,
      (processedEnd: number, total: number) => {
        if (!this.isAnnotatePrepareSessionActive()) {
          return;
        }
        const percent = total > 0 ? Math.floor((processedEnd * 100) / total) : 100;
        if (percent !== lastReportedPercent && (percent % 5 === 0 || processedEnd >= total)) {
          lastReportedPercent = percent;
          void this.reportAnnotatePreparePhase(`正在扫描批注… ${processedEnd}/${total}`, false);
        }
      }
    );

    if (!this.isAnnotatePrepareSessionActive()) {
      return;
    }

    const uiContext = this.dependencies.getUIContext();
    const affectedPageIndices: number[] = [];

    if (candidatePageIndices.length > 0) {
      await this.reportAnnotatePreparePhase('正在导入批注…', true);
      for (let i = 0; i < candidatePageIndices.length; i += ANNOTATE_IMPORT_PAGE_BATCH_SIZE) {
        if (!this.isAnnotatePrepareSessionActive()) {
          this.dependencies.pageDataSource.restoreImportedPdfPolylineAnnotations();
          this.dependencies.onRedrawRequested();
          return;
        }
        const batchEnd = Math.min(i + ANNOTATE_IMPORT_PAGE_BATCH_SIZE, candidatePageIndices.length);
        for (let j = i; j < batchEnd; j++) {
          const pageIndex = candidatePageIndices[j];
          const batchAffected = this.dependencies.pageDataSource.importPdfPolylineAnnotationsRange(
            uiContext,
            this.canvasOverSampling,
            pageIndex,
            pageIndex + 1
          );
          for (const affectedIndex of batchAffected) {
            affectedPageIndices.push(affectedIndex);
          }
        }
        await this.reportAnnotatePreparePhase(
          `正在导入批注… ${batchEnd}/${candidatePageIndices.length}`,
          true
        );
      }
    }

    if (!this.isAnnotatePrepareSessionActive()) {
      if (affectedPageIndices.length > 0) {
        this.dependencies.pageDataSource.restoreImportedPdfPolylineAnnotations();
        this.dependencies.onRedrawRequested();
      }
      return;
    }

    if (affectedPageIndices.length === 0) {
      this.importedPolylinePrepared = true;
      return;
    }

    await this.reportAnnotatePreparePhase('正在写入预览…', true);
    if (!this.isAnnotatePrepareSessionActive()) {
      this.dependencies.pageDataSource.restoreImportedPdfPolylineAnnotations();
      this.importedPolylinePrepared = false;
      this.dependencies.onRedrawRequested();
      return;
    }

    if (!await this.writeEditRenderDocument()) {
      this.dependencies.pageDataSource.restoreImportedPdfPolylineAnnotations();
      this.importedPolylinePrepared = false;
      this.dependencies.onRedrawRequested();
      return;
    }

    await this.reportAnnotatePreparePhase('正在刷新页面…', true);
    await this.refreshEditedPages(affectedPageIndices);
    if (!this.isAnnotatePrepareSessionActive()) {
      this.dependencies.pageDataSource.restoreImportedPdfPolylineAnnotations();
      this.dependencies.onRedrawRequested();
      return;
    }
    this.importedPolylinePrepared = true;
    this.updateUnsavedStrokesFlag();
    this.dependencies.onRedrawRequested();
  }

  private isAnnotatePrepareSessionActive(): boolean {
    const checker = this.dependencies.isAnnotatePrepareSessionActive;
    return checker === undefined || checker();
  }

  private async reportAnnotatePreparePhase(message: string, blocksEditing: boolean): Promise<void> {
    this.dependencies.onAnnotatePreparePhase?.(message, { blocksEditing: blocksEditing });
    await yieldToUi();
  }

  applyStrokeStyle(ctx: CanvasRenderingContext2D): void {
    // 笔画颜色由各 Stroke 在渲染时自行设置；这里只统一线宽与端点样式。
    ctx.lineWidth = 1 * this.canvasOverSampling;
    ctx.lineCap = 'round';
  }

  loadPageStrokes(ctx: CanvasRenderingContext2D, pageIndex: number): void {
    if (this.dependencies.pageDataSource.getPageStrokesCount(pageIndex) === 0) {
      return;
    }
    this.applyStrokeStyle(ctx);
    this.dependencies.pageDataSource.stokePage(pageIndex, ctx);
  }

  resetTransientState(): AnnotationTransientResetResult {
    const result: AnnotationTransientResetResult = {
      clearedDraw: this.activeDrawPath.points.length > 0,
      clearedErase: this.pathsToErase.size > 0
    };
    if (result.clearedDraw) {
      this.activeDrawPath = NewStroke();
    }
    if (result.clearedErase) {
      this.pathsToErase.clear();
    }
    return result;
  }

  startDraw(point: Vector2): void {
    this.activeDrawPath = NewStroke(this.selectedDrawColor.pdfColor);
    this.activeDrawPath.path.moveTo(point.x, point.y);
    this.activeDrawPath.points.push(point);
  }

  extendDraw(point: Vector2, drawCtx: CanvasRenderingContext2D): void {
    // 防御：若 startDraw 未被执行就收到 Move（例如 Down 事件被双指/手势门禁过滤、
    // 或 resetTransientState 清空了占位笔画），则把首个 Move 视为隐式起点，
    // 并按当前选中颜色重建笔画——避免落入残留占位笔画的默认颜色（DefaultAnnotationColor），
    // 即“切到自定义后偶发的第二笔变回橙色”问题。
    if (this.activeDrawPath.points.length === 0) {
      this.activeDrawPath = NewStroke(this.selectedDrawColor.pdfColor);
      this.activeDrawPath.path.moveTo(point.x, point.y);
      this.activeDrawPath.points.push(point);
      return;
    }
    this.activeDrawPath.path.lineTo(point.x, point.y);
    drawCtx.reset();
    this.applyStrokeStyle(drawCtx);
    this.activeDrawPath.stroke(drawCtx);
    this.activeDrawPath.points.push(point);
  }

  finishDraw(pageIndex: number, point: Vector2, drawCtx: CanvasRenderingContext2D, targetCtx: CanvasRenderingContext2D): void {
    this.activeDrawPath.points.push(point);

    let pathLength = 0;
    for (let i = 1; i < this.activeDrawPath.points.length; i++) {
      const p1 = this.activeDrawPath.points[i - 1];
      const p2 = this.activeDrawPath.points[i];
      const dx = p2.x - p1.x;
      const dy = p2.y - p1.y;
      pathLength += Math.sqrt(dx * dx + dy * dy);
    }

    const minPathLength = 2 * this.canvasOverSampling;
    if (pathLength >= minPathLength) {
      this.dependencies.pageDataSource.addStroke(pageIndex, this.activeDrawPath);
      this.appendUndoHistory({
        path: this.activeDrawPath,
        mode: 'add',
        pageIndex: pageIndex
      });
      this.updateUnsavedStrokesFlag();
      this.loadPageStrokes(targetCtx, pageIndex);
    }

    this.activeDrawPath = NewStroke();
    drawCtx.reset();
  }

  startErase(): void {
    this.pathsToErase.clear();
  }

  previewErase(pageIndex: number, point: Vector2, targetCtx: CanvasRenderingContext2D): void {
    if (this.dependencies.pageDataSource.getPageStrokesCount(pageIndex) === 0) {
      return;
    }

    const eraseThreshold = 20 * this.canvasOverSampling;
    for (const stroke of this.dependencies.pageDataSource.iteratePageStrokes(pageIndex)) {
      if (this.pathsToErase.has(stroke)) {
        continue;
      }
      for (const strokePoint of stroke.points) {
        const dx = point.x - strokePoint.x;
        const dy = point.y - strokePoint.y;
        const distance = Math.sqrt(dx * dx + dy * dy);
        if (distance < eraseThreshold) {
          this.pathsToErase.add(stroke);
          break;
        }
      }
    }

    targetCtx.reset();
    this.applyStrokeStyle(targetCtx);
    for (const stroke of this.dependencies.pageDataSource.iteratePageStrokes(pageIndex)) {
      if (!this.pathsToErase.has(stroke)) {
        stroke.stroke(targetCtx);
      }
    }
  }

  finishErase(pageIndex: number, targetCtx: CanvasRenderingContext2D): void {
    if (this.pathsToErase.size === 0) {
      return;
    }

    this.dependencies.pageDataSource.removeStrokeWhere(pageIndex, stroke => this.pathsToErase.has(stroke));
    this.pathsToErase.forEach((erasedPath: ReadonlyStroke) => {
      this.appendUndoHistory({
        path: erasedPath,
        mode: 'erase',
        pageIndex: pageIndex
      });
    });

    this.pathsToErase.clear();
    targetCtx.reset();
    this.updateUnsavedStrokesFlag();
    this.loadPageStrokes(targetCtx, pageIndex);
  }

  executeUndo(): void {
    const history = this.undoHistory.pop();
    if (!history) {
      return;
    }

    this.undoHistoryCount = this.undoHistory.length;
    if (!this.dependencies.viewerViewModel.displayedPageIndices.includes(history.pageIndex)) {
      this.dependencies.onRequestGotoPage(history.pageIndex);
    }

    if (history.mode === 'add') {
      this.dependencies.pageDataSource.removeStroke(history.pageIndex, history.path as Stroke);
    } else if (history.mode === 'erase') {
      this.dependencies.pageDataSource.addStroke(history.pageIndex, history.path as Stroke);
    }

    this.redoHistory.push(history);
    this.redoHistoryCount = this.redoHistory.length;
    this.updateUnsavedStrokesFlag();
    this.dependencies.onRedrawRequested();
  }

  executeRedo(): void {
    const history = this.redoHistory.pop();
    if (!history) {
      return;
    }

    this.redoHistoryCount = this.redoHistory.length;
    if (!this.dependencies.viewerViewModel.displayedPageIndices.includes(history.pageIndex)) {
      this.dependencies.onRequestGotoPage(history.pageIndex);
    }

    if (history.mode === 'add') {
      this.dependencies.pageDataSource.addStroke(history.pageIndex, history.path as Stroke);
    } else if (history.mode === 'erase') {
      this.dependencies.pageDataSource.removeStroke(history.pageIndex, history.path as Stroke);
    }

    this.undoHistory.push(history);
    this.undoHistoryCount = this.undoHistory.length;
    this.updateUnsavedStrokesFlag();
    this.dependencies.onRedrawRequested();
  }

  private async reportSavePhase(message: string): Promise<void> {
    this.dependencies.onSavePhase?.(message);
    await yieldToUi();
    if (SAVE_DEBUG_PHASE_DELAY_MS > 0) {
      await new Promise<void>((resolve) => {
        setTimeout(resolve, SAVE_DEBUG_PHASE_DELAY_MS);
      });
    }
  }

  async executeSave(): Promise<boolean> {
    const saveUri = await this.pickSaveUri();
    if (!saveUri || saveUri.length === 0) {
      return false;
    }

    await this.reportSavePhase('正在准备批注…');
    const affectedPage = this.collectAffectedAnnotations();

    await this.reportSavePhase('正在写入 PDF…');
    if (!(await this.saveDocumentToTemp(affectedPage))) {
      return false;
    }

    await this.reportSavePhase('正在导出到所选位置…');
    if (!(await this.copyTempToSaveUri(saveUri, affectedPage))) {
      await this.writeEditRenderDocument();
      return false;
    }

    await this.reportSavePhase('正在完成保存…');
    if (!(await this.commitTempToSandbox(affectedPage))) {
      return false;
    }

    this.dependencies.pageDataSource.clearAllStrokes();
    this.dependencies.pageDataSource.clearImportedPdfPolylineTracking();
    this.dependencies.pageDataSource.setPagePath(this.dependencies.getSandBoxPath());
    this.clearHistory();
    this.hasUnsavedStrokes = false;
    this.importedPolylinePrepared = false;

    await this.reportSavePhase('正在刷新页面…');
    await this.refreshAfterSave(Array.from(affectedPage.keys()));
    return true;
  }

  private appendUndoHistory(history: History): void {
    this.undoHistory.push(history);
    this.undoHistoryCount = this.undoHistory.length;
    this.redoHistory.clear();
    this.redoHistoryCount = 0;
  }

  private updateUnsavedStrokesFlag(): void {
    for (let i = 0; i < this.dependencies.viewerViewModel.totalPageCount; i++) {
      if (this.dependencies.pageDataSource.getPageStrokesCount(i) > 0) {
        this.hasUnsavedStrokes = true;
        return;
      }
    }
    this.hasUnsavedStrokes = false;
  }

  private clearHistory(): void {
    this.undoHistory.clear();
    this.redoHistory.clear();
    this.undoHistoryCount = 0;
    this.redoHistoryCount = 0;
  }

  private async pickSaveUri(): Promise<string> {
    const documentPicker = new picker.DocumentViewPicker();
    const saveOptions = new picker.DocumentSaveOptions();
    saveOptions.defaultFilePathUri = this.dependencies.getSystemPath();
    saveOptions.fileSuffixChoices = ['PDF 文档|.pdf'];
    saveOptions.newFileNames = [this.dependencies.getFileName()];

    try {
      const result = await documentPicker.save(saveOptions);
      if (!result || result.length === 0) {
        return '';
      }
      const uri = result[0];
      const fileName = this.extractFileNameFromUri(uri);
      if (!this.isValidFileName(fileName)) {
        hilog.warn(0, 'PDFView', '用户尝试使用无效文件名保存');
        await showAlertDialog('文件名无效', '文件名不能为空。请输入有效的文件名。', this.dependencies.getUIContext());
        return '';
      }
      return uri;
    } catch (error) {
      hilog.error(0, 'PDFView', `保存对话框错误: ${JSON.stringify(error)}`);
      return '';
    }
  }

  /**
   * 从 URI 中提取文件名部分。
   */
  private extractFileNameFromUri(uri: string): string {
    const queryIndex = uri.indexOf('?');
    const cleanUri = queryIndex >= 0 ? uri.substring(0, queryIndex) : uri;
    const lastSlash = cleanUri.lastIndexOf('/');
    return lastSlash >= 0 ? cleanUri.substring(lastSlash + 1) : cleanUri;
  }

  /**
   * 验证文件名是否有效（不为空、不为空白、不只是扩展名如 ".pdf"）。
   */
  private isValidFileName(fileName: string): boolean {
    if (!fileName || fileName.trim().length === 0) {
      return false;
    }
    // 仅当有点号且点号在开头时（如 ".pdf"）视为无效
    const dotIndex = fileName.indexOf('.');
    if (dotIndex === 0) {
      return false;
    }
    return true;
  }

  private collectAffectedAnnotations(): Map<number, pdfService.PdfAnnotation[]> {
    const affectedPage = new Map<number, pdfService.PdfAnnotation[]>();
    const totalPageCount = this.dependencies.pageDataSource.totalPageCount();
    const importedPageIndices = this.dependencies.pageDataSource.getImportedPdfPolylinePageIndices();

    for (let pageIndex = 0; pageIndex < totalPageCount; pageIndex++) {
      if (this.dependencies.pageDataSource.getPageStrokesCount(pageIndex) == 0 && !importedPageIndices.includes(pageIndex)) {
        continue;
      }

      const pdfPageSize = this.dependencies.pageDataSource.getPageRawSize(pageIndex);
      const canvasSizePx = mul(pdfPageSize, this.canvasOverSampling);
      const canvasSizeVp = pxToVp(canvasSizePx, this.dependencies.getUIContext());
      const annotationsToAdd: pdfService.PolylineAnnotationInfo[] = [];

      for (const stroke of this.dependencies.pageDataSource.iteratePageStrokes(pageIndex)) {
        annotationsToAdd.push(this.makePolylineAnnotationInfo(stroke, pdfPageSize, canvasSizeVp));
      }

      const annotations = annotationsToAdd.length > 0
        ? this.dependencies.pageDataSource.addPdfAnnotations(pageIndex, annotationsToAdd)
        : [];
      affectedPage.set(pageIndex, annotations);
    }

    return affectedPage;
  }

  private makePolylineAnnotationInfo(
    stroke: ReadonlyStroke,
    pdfPageSize: Vector2,
    canvasSizeVp: Vector2
  ): pdfService.PolylineAnnotationInfo {
    const transformedPoints: Vector2[] = [];
    for (const point of stroke.points) {
      transformedPoints.push(Vec2(
        (point.x / canvasSizeVp.x) * pdfPageSize.x,
        (1 - point.y / canvasSizeVp.y) * pdfPageSize.y
      ));
    }

    const annotationInfo = new pdfService.PolylineAnnotationInfo();
    const sourceInfo = stroke.source?.kind === 'importedPdfPolyline' ? stroke.source.annotationInfo : undefined;
    if (sourceInfo) {
      annotationInfo.subject = sourceInfo.subject;
      annotationInfo.creationDate = sourceInfo.creationDate;
      annotationInfo.content = sourceInfo.content;
      annotationInfo.border = sourceInfo.border;
      annotationInfo.flag = sourceInfo.flag;
      annotationInfo.title = sourceInfo.title;
      annotationInfo.opacity = sourceInfo.opacity;
      annotationInfo.lineColor = sourceInfo.lineColor;
      annotationInfo.uniqueId = stroke.source?.uniqueId && stroke.source.uniqueId.length > 0
        ? stroke.source.uniqueId
        : (sourceInfo.uniqueId && sourceInfo.uniqueId.length > 0 ? sourceInfo.uniqueId : util.generateRandomUUID(true));
    } else {
      annotationInfo.subject = DefaultAnnotationSubject;
      annotationInfo.creationDate = new Date(Date.now());
      annotationInfo.lineColor = stroke.pdfLineColor;
      annotationInfo.uniqueId = util.generateRandomUUID(true);
      annotationInfo.flag = pdfService.AnnotationFlag.PRINTED;
    }
    annotationInfo.modifiedTime = new Date(Date.now());
    annotationInfo.vertexes = transformedPoints;
    return annotationInfo;
  }

  private async saveDocumentToTemp(affectedPage: Map<number, pdfService.PdfAnnotation[]>): Promise<boolean> {
    await this.cleanupTempSaveFile();
    await yieldToUi();

    const success = this.dependencies.document.saveDocument(this.dependencies.getSaveTempPath());
    await yieldToUi();
    if (!success) {
      hilog.error(0, 'PDFView', '保存 PDF 文件到临时路径时出错');
      this.removeAddedAnnotations(affectedPage);
      return false;
    }

    return true;
  }

  private async copyTempToSaveUri(saveUri: string, affectedPage: Map<number, pdfService.PdfAnnotation[]>): Promise<boolean> {
    let srcFile: fs.File | undefined = undefined;
    let dstFile: fs.File | undefined = undefined;

    try {
      srcFile = await fs.open(this.dependencies.getSaveTempPath(), fs.OpenMode.READ_ONLY);
      dstFile = await fs.open(saveUri, fs.OpenMode.WRITE_ONLY);
    } catch (error) {
      if (srcFile) {
        try {
          await fs.close(srcFile);
        } catch (closeError) {
          hilog.error(0, 'PDFView', `关闭源文件时出错: ${closeError}`);
        }
      }
      if (dstFile) {
        try {
          await fs.close(dstFile);
        } catch (closeError) {
          hilog.error(0, 'PDFView', `关闭目标文件时出错: ${closeError}`);
        }
      }
      hilog.error(0, 'PDFView', `打开文件时出错: ${error}`);
      this.removeAddedAnnotations(affectedPage);
      return false;
    }

    try {
      await fs.copyFile(srcFile.fd, dstFile.fd);
      await fs.close(srcFile);
      await fs.close(dstFile);
      return true;
    } catch (error) {
      hilog.error(0, 'PDFView', `保存 PDF 文件到选定位置 ${saveUri} 时出错: ${error}`);
      await showAlertDialog('保存失败', `无法将 PDF 文件保存到选定位置。请检查权限或存储空间，然后重试。\n错误信息: ${error}`, this.dependencies.getUIContext());
      this.removeAddedAnnotations(affectedPage);
      return false;
    }
  }

  private async commitTempToSandbox(affectedPage: Map<number, pdfService.PdfAnnotation[]>): Promise<boolean> {
    try {
      await fs.rename(this.dependencies.getSaveTempPath(), this.dependencies.getSandBoxPath());
      return true;
    } catch (error) {
      hilog.error(0, 'PDFView', `将临时文件重命名到沙箱路径时出错: ${error}`);
      this.removeAddedAnnotations(affectedPage);
      return false;
    }
  }

  private async cleanupTempSaveFile(): Promise<void> {
    try {
      await fs.unlink(this.dependencies.getSaveTempPath());
    } catch (error) {
      if (error.code !== 13900002) {
        hilog.warn(0, 'PDFView', `清理临时文件时出现非致命错误: ${error}`);
      }
    }
  }

  private removeAddedAnnotations(affectedPage: Map<number, pdfService.PdfAnnotation[]>): void {
    for (const pageIndex of affectedPage.keys()) {
      const annotations = affectedPage.get(pageIndex);
      if (!annotations) {
        continue;
      }
      this.dependencies.pageDataSource.removePdfAnnotations(pageIndex, annotations);
    }
  }

  private async revertChanges(affectedPage: Map<number, pdfService.PdfAnnotation[]>): Promise<void> {
    this.removeAddedAnnotations(affectedPage);

    const success = this.dependencies.document.saveDocument(this.dependencies.getSaveTempPath());
    if (!success) {
      hilog.error(0, 'PDFView', '保存回退 PDF 文件时出错');
      return;
    }

    try {
      await fs.rename(this.dependencies.getSaveTempPath(), this.dependencies.getSandBoxPath());
    } catch (error) {
      hilog.error(0, 'PDFView', `重命名回退文件时出错: ${error}`);
      try {
        await fs.unlink(this.dependencies.getSaveTempPath());
      } catch (unlinkError) {
        hilog.error(0, 'PDFView', `删除临时回退文件时出错: ${unlinkError}`);
      }
    }
  }

  private async writeEditRenderDocument(): Promise<boolean> {
    await this.cleanupTempSaveFile();
    const success = this.dependencies.document.saveDocument(this.dependencies.getSaveTempPath());
    if (!success) {
      hilog.error(0, 'PDFView', '保存编辑预览 PDF 文件时出错');
      return false;
    }
    this.dependencies.pageDataSource.setPagePath(this.dependencies.getSaveTempPath());
    return true;
  }

  private async refreshEditedPages(affectedPageIndices: number[]): Promise<void> {
    if (affectedPageIndices.length === 0) {
      return;
    }

    for (let i = 0; i < affectedPageIndices.length; i++) {
      if (!this.isAnnotatePrepareSessionActive()) {
        return;
      }
      const pageIndex = affectedPageIndices[i];
      this.dependencies.pageDataSource.invalidateCaches(pageIndex);
      this.dependencies.pageDataSource.ensureCached(pageIndex, ViewerMinRenderScale, taskpool.Priority.HIGH);
      if ((i + 1) % ANNOTATE_REFRESH_PAGE_BATCH_SIZE === 0) {
        await yieldToUi();
      }
    }

    const currentPageAffected = this.dependencies.viewerViewModel.displayedPageIndices.some((pageIndex: number) =>
      affectedPageIndices.includes(pageIndex)
    );
    if (currentPageAffected) {
      await this.dependencies.onRefreshDisplayedPages();
    }
  }

  private async refreshAfterSave(affectedPageIndices: number[]): Promise<void> {
    if (affectedPageIndices.length === 0) {
      return;
    }

    for (const pageIndex of affectedPageIndices) {
      this.dependencies.pageDataSource.invalidateCaches(pageIndex);
    }

    const currentPageAffected = this.dependencies.viewerViewModel.displayedPageIndices.some((pageIndex: number) =>
      affectedPageIndices.includes(pageIndex)
    );

    for (const pageIndex of affectedPageIndices) {
      this.dependencies.pageDataSource.ensureCached(pageIndex, ViewerMinRenderScale, taskpool.Priority.HIGH);
    }

    if (currentPageAffected) {
      await this.dependencies.onRefreshDisplayedPages();
    }
  }
}