import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { pdfService } from '@kit.PDFKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { taskpool, util } from '@kit.ArkTS';
import { getCheckIcon, showAlertDialog } from '../../components/UIComponents';
import { Stack as DataStack } from '../../components/Colletions';
import { History, NewStroke, PageStore, ReadonlyStroke, Stroke } from '../../components/PageInfo';
import { mul, pxToVp, Vec2, Vector2 } from '../../components/Numbers';
import { PDFAnnotateMode, PDFViewerViewModel, ViewerMinRenderScale } from './PDFViewerViewModel';

const DefaultAnnotationCanvasOverSampling: number = 3;
const DefaultAnnotationLineColor: string = 'rgba(255, 132, 0, 1.00)';
const DefaultAnnotationPdfLineColor: number = 3547621;
const DefaultAnnotationSubject: string = '由 Just PDF 创建的注释';

interface PDFAnnotationControllerDependencies {
  pageDataSource: PageStore;
  viewerViewModel: PDFViewerViewModel;
  document: pdfService.PdfDocument;
  getSystemPath: () => string;
  getSandBoxPath: () => string;
  getSaveTempPath: () => string;
  getUIContext: () => UIContext;
  onRequestGotoPage: (pageIndex: number) => void;
  onRedrawRequested: () => void;
  onRefreshDisplayedPages: () => Promise<void>;
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

  @Trace public hasUnsavedStrokes: boolean = false;
  @Trace public undoHistoryCount: number = 0;
  @Trace public redoHistoryCount: number = 0;

  constructor(dependencies: PDFAnnotationControllerDependencies, canvasOverSampling: number = DefaultAnnotationCanvasOverSampling) {
    this.dependencies = dependencies;
    this.canvasOverSampling = canvasOverSampling;
  }

  get annotateMode(): PDFAnnotateMode {
    return this.dependencies.viewerViewModel.annotateMode;
  }

  buildAnnotateModeMenu(): MenuElement[] {
    return [
      {
        value: '拖动',
        action: () => this.setAnnotateMode('drag'),
        symbolIcon: getCheckIcon(this.dependencies.viewerViewModel.annotateMode == 'drag')
      },
      {
        value: '绘制',
        action: () => this.setAnnotateMode('draw'),
        symbolIcon: getCheckIcon(this.dependencies.viewerViewModel.annotateMode == 'draw')
      },
      {
        value: '擦除',
        action: () => this.setAnnotateMode('erase'),
        symbolIcon: getCheckIcon(this.dependencies.viewerViewModel.annotateMode == 'erase')
      }
    ];
  }

  setAnnotateMode(mode: PDFAnnotateMode): void {
    this.dependencies.viewerViewModel.setAnnotateMode(mode);
  }

  applyStrokeStyle(ctx: CanvasRenderingContext2D): void {
    ctx.strokeStyle = DefaultAnnotationLineColor;
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
    this.activeDrawPath = NewStroke();
    this.activeDrawPath.path.moveTo(point.x, point.y);
    this.activeDrawPath.points.push(point);
  }

  extendDraw(point: Vector2, drawCtx: CanvasRenderingContext2D): void {
    this.activeDrawPath.path.lineTo(point.x, point.y);
    drawCtx.reset();
    this.applyStrokeStyle(drawCtx);
    drawCtx.stroke(this.activeDrawPath.path);
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

  async executeSave(): Promise<void> {
    const saveUri = await this.pickSaveUri();
    if (!saveUri || saveUri.length === 0) {
      return;
    }

    const affectedPage = this.collectAffectedAnnotations();
    if (!(await this.saveDocumentToSandbox(affectedPage))) {
      return;
    }

    if (!(await this.copySandboxToSaveUri(saveUri, affectedPage))) {
      return;
    }

    this.dependencies.pageDataSource.clearAllStrokes();
    this.clearHistory();
    this.hasUnsavedStrokes = false;
    await this.refreshAfterSave(Array.from(affectedPage.keys()));
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

    try {
      const result = await documentPicker.save(saveOptions);
      if (result && result.length > 0) {
        return result[0];
      }
      hilog.info(0, 'PDFView', '用户取消保存操作');
      return '';
    } catch (error) {
      hilog.error(0, 'PDFView', `保存对话框错误: ${JSON.stringify(error)}`);
      return '';
    }
  }

  private collectAffectedAnnotations(): Map<number, pdfService.PdfAnnotation[]> {
    const affectedPage = new Map<number, pdfService.PdfAnnotation[]>();
    const totalPageCount = this.dependencies.pageDataSource.totalPageCount();

    for (let pageIndex = 0; pageIndex < totalPageCount; pageIndex++) {
      if (this.dependencies.pageDataSource.getPageStrokesCount(pageIndex) == 0) {
        continue;
      }

      const pdfPageSize = this.dependencies.pageDataSource.getPageRawSize(pageIndex);
      const canvasSizePx = mul(pdfPageSize, this.canvasOverSampling);
      const canvasSizeVp = pxToVp(canvasSizePx, this.dependencies.getUIContext());
      const annotationsToAdd: pdfService.PolylineAnnotationInfo[] = [];

      for (const stroke of this.dependencies.pageDataSource.iteratePageStrokes(pageIndex)) {
        const transformedPoints: Vector2[] = [];
        for (const point of stroke.points) {
          transformedPoints.push(Vec2(
            (point.x / canvasSizeVp.x) * pdfPageSize.x,
            (1 - point.y / canvasSizeVp.y) * pdfPageSize.y
          ));
        }

        const annotationInfo = new pdfService.PolylineAnnotationInfo();
        annotationInfo.subject = DefaultAnnotationSubject;
        annotationInfo.creationDate = new Date(Date.now());
        annotationInfo.modifiedTime = new Date(Date.now());
        annotationInfo.vertexes = transformedPoints;
        annotationInfo.lineColor = DefaultAnnotationPdfLineColor;
        annotationInfo.uniqueId = util.generateRandomUUID(true);
        annotationInfo.flag = pdfService.AnnotationFlag.PRINTED;
        annotationsToAdd.push(annotationInfo);
      }

      const annotations = this.dependencies.pageDataSource.addPdfAnnotations(pageIndex, annotationsToAdd);
      affectedPage.set(pageIndex, annotations);
    }

    return affectedPage;
  }

  private async saveDocumentToSandbox(affectedPage: Map<number, pdfService.PdfAnnotation[]>): Promise<boolean> {
    await this.cleanupTempSaveFile();

    const success = this.dependencies.document.saveDocument(this.dependencies.getSaveTempPath());
    if (!success) {
      hilog.error(0, 'PDFView', '保存 PDF 文件到临时路径时出错');
      this.removeAddedAnnotations(affectedPage);
      return false;
    }

    try {
      await fs.rename(this.dependencies.getSaveTempPath(), this.dependencies.getSandBoxPath());
      return true;
    } catch (error) {
      hilog.error(0, 'PDFView', `将临时文件重命名到沙箱路径时出错: ${error}`);
      try {
        await fs.unlink(this.dependencies.getSaveTempPath());
      } catch (unlinkError) {
        hilog.error(0, 'PDFView', `删除临时文件时出错: ${unlinkError}`);
      }
      await this.revertChanges(affectedPage);
      return false;
    }
  }

  private async copySandboxToSaveUri(saveUri: string, affectedPage: Map<number, pdfService.PdfAnnotation[]>): Promise<boolean> {
    let srcFile: fs.File | undefined = undefined;
    let dstFile: fs.File | undefined = undefined;

    try {
      srcFile = await fs.open(this.dependencies.getSandBoxPath(), fs.OpenMode.READ_ONLY);
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
      await this.revertChanges(affectedPage);
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
      await this.revertChanges(affectedPage);
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