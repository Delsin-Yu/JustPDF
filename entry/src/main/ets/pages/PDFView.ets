import { deviceInfo } from '@kit.BasicServicesKit';
import { pdfService, PdfView, pdfViewManager } from '@kit.PDFKit';
import { KeyCode } from '@kit.InputKit';
import { display, LengthMetricsUnit, LengthUnit, SymbolGlyphModifier, window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import app from '@system.app';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HashMap, Stack } from '@kit.ArkTS';


const BaseColor: ResourceColor = `rgba(50, 50, 50, 1)`;
const ButtonColor: ResourceColor = `rgba(50, 50, 50, 0.7)`;
const ButtonColorSemiTransparent: ResourceColor = 'rgba(50, 50, 50, 0.2)';
const ButtonColorHighlight: ResourceColor = 'rgba(160, 160, 160, 0.9)';
const TrackColor: ResourceColor = 'rgba(50, 50, 50, 0.4)';
const StandardOffset: number = 8;
const ButtonFontSize: Length = '20vp';
const HalfButtonFontSize: Length = '10vp';
const ButtonSizeH: number = 40;
const ButtonSizeW: number = 80;
const ButtonSize: SizeOptions = { height: ButtonSizeH, width: ButtonSizeW };
const ButtonSizeWWide: number = 90;
const ButtonSizeWide: SizeOptions = { height: ButtonSizeH, width: ButtonSizeWWide };
const PageFlipButtonWidth: Length = '30%';
const ScrollBarWidth: Length = '40vp';
const CanvasOverSampling: number = 3;
const PdfViewId = 'pdfview_control';
const TopLeft: AlignRuleOption = {
  top: { anchor: '__container__', align: VerticalAlign.Top },
  left: { anchor: '__container__', align: HorizontalAlign.Start },
};
const DualPageSpacing: number = 5;
const TopRight: AlignRuleOption = {
  top: { anchor: '__container__', align: VerticalAlign.Top },
  right: { anchor: '__container__', align: HorizontalAlign.End }
}
const FullRect: AlignRuleOption = {
  'top': { 'anchor': '__container__', 'align': VerticalAlign.Top },
  'bottom': { 'anchor': '__container__', 'align': VerticalAlign.Bottom },
  'left': { 'anchor': '__container__', 'align': HorizontalAlign.Start },
  'right': { 'anchor': '__container__', 'align': HorizontalAlign.End },
}

interface Vector2 {
  x: number;
  y: number;
}

interface PdfPage {
  size: Vector2;
  page: pdfService.PdfPage;
}

interface PathWithPoints {
  path: Path2D;
  points: Array<Vector2>;
}

interface PDFViewDisplayStatus {
  pageIndex: number;
  leftPageIndex: number;
  rightPageIndex: number;
  isDisplayingDualPage: boolean;
}

interface PDFViewPageMetrics {
  position: Vector2;
  size: Vector2;
  scale: Vector2;
}

interface History {
  path: PathWithPoints;
  mode: 'add' | 'erase';
  pageIndex: number;
}

function toPos(value: Vector2): Position {
  return { x: `${value.x}px`, y: `${value.y}px` };
}

function toSize(value: Vector2): SizeOptions {
  return { width: `${value.x}px`, height: `${value.y}px` };
}

function toScale(value: Vector2): ScaleOptions {
  return {
    x: value.x,
    y: value.y,
    centerX: 0,
    centerY: 0
  };
}

function toVisibility(value: boolean): Visibility {
  return value ? Visibility.Visible : Visibility.None;
}

function Float2(x: number, y: number): Vector2 {
  return { x: x, y: y };
}

function clear<T>(stack: Stack<T>): void {
  while (!stack.isEmpty()) {
    stack.pop();
  }
}

const squareSymbol = $r('sys.symbol.square');
const squareCheckedSymbol = $r('sys.symbol.checkmark_square_fill');


@Entry
@Component
struct PDFView {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private lctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private rctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private dlctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private drctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private pageStrokes = new HashMap<number, Array<PathWithPoints>>();
  private pageRawSizes = new HashMap<number, Vector2>();
  private document = new pdfService.PdfDocument();
  private pages = new HashMap<number, PdfPage>();
  private preferences: preferences.Preferences = AppStorage.get('preferences') as preferences.Preferences;
  private mainWindow: window.Window = (AppStorage.get('windowStage') as window.WindowStage).getMainWindowSync();
  private boxUnchecked: SymbolGlyphModifier = new SymbolGlyphModifier(squareSymbol)
    .fontColor([Color.White])
    .fontSize(ButtonFontSize)
    .fontWeight(FontWeight.Medium);
  private boxChecked: SymbolGlyphModifier = new SymbolGlyphModifier(squareCheckedSymbol)
    .fontColor([Color.White])
    .fontSize(ButtonFontSize)
    .fontWeight(FontWeight.Medium);
  private activeDrawPath: PathWithPoints = { path: new Path2D(), points: [] };
  private pathsToErase: Set<PathWithPoints> = new Set();
  private undoHistory: Stack<History> = new Stack<History>();
  private redoHistory: Stack<History> = new Stack<History>();
  private systemPath = '';
  private sandBoxPath = '';
  @State lPixMap: PixelMap | undefined = undefined;
  @State rPixMap: PixelMap | undefined = undefined;
  @State hasUnsavedStrokes: boolean = false;
  @State undoHistoryCount: number = 0;
  @State redoHistoryCount: number = 0;
  @State pageCount: number = 0;
  @State showControls: boolean = true;
  @State currentOperationMode: 'side' | 'button' | 'extern' = 'side';
  @State currentDrawMode: 'add' | 'erase' | 'drag' = 'add';
  @State isInDualPageMode: boolean = false;
  @State isExclusiveFullScreen: boolean = false;
  @State leftPageMetrics: PDFViewPageMetrics = {
    position: Float2(0, 0),
    size: Float2(0, 0),
    scale: Float2(0, 0)
  };
  @State rightPageMetrics: PDFViewPageMetrics = {
    position: Float2(0, 0),
    size: Float2(0, 0),
    scale: Float2(0, 0)
  };
  @State viewScale: number = 0;
  @State currentPageStatus: PDFViewDisplayStatus = {
    pageIndex: 0,
    leftPageIndex: 0,
    rightPageIndex: 0,
    isDisplayingDualPage: false
  };

  setPageIndexAndGotoPage(newIndex: number) {
    if (this.currentPageStatus.pageIndex == newIndex) {
      return;
    }
    this.currentPageStatus.pageIndex = newIndex;
    this.controller.goToPage(this.currentPageStatus.pageIndex);
  }

  /**
   * @throws
   */
  getPdfPage(pageIndex: number): Nullable<PdfPage> {
    if (this.pages.hasKey(pageIndex)) {
      return this.pages.get(pageIndex);
    }
    return undefined;
  }

  applyStrokeStyle(ctx: CanvasRenderingContext2D) {
    ctx.strokeStyle = 'rgba(255, 132, 0, 1.00)';
    ctx.lineWidth = 1 * CanvasOverSampling;
    ctx.lineCap = 'round';
  }

  updateUnsavedStrokesFlag() {
    for (const pageIndex of this.pageStrokes.keys()) {
      const strokes = this.pageStrokes.get(pageIndex);
      if (strokes.length > 0) {
        this.hasUnsavedStrokes = true;
        return;
      }
    }
    this.hasUnsavedStrokes = false;
  }

  /**
   * @throws
   */
  loadPageStrokes(ctx: CanvasRenderingContext2D, pageIndex: number) {
    if (!this.pageStrokes.hasKey(pageIndex)) {
      return;
    }
    const strokes = this.pageStrokes.get(pageIndex);
    this.applyStrokeStyle(ctx);
    strokes.forEach(stroke => ctx.stroke(stroke.path));
  }

  appendUndoHistory(history: History): void {
    this.undoHistory.push(history);
    this.undoHistoryCount = this.undoHistory.length;
    clear(this.redoHistory);
    this.redoHistoryCount = 0;
  }

  executeUndo(): void {
    if (this.undoHistory.isEmpty()) {
      return;
    }
    const history = this.undoHistory.pop();
    this.undoHistoryCount = this.undoHistory.length;
    if(this.currentPageStatus.pageIndex != history.pageIndex) {
      this.setPageIndexAndGotoPage(history.pageIndex);
    }
    if (history.mode == 'add') {
      if (this.pageStrokes.hasKey(history.pageIndex)) {
        const strokes = this.pageStrokes.get(history.pageIndex);
        const index = strokes.indexOf(history.path);
        if (index >= 0) {
          strokes.splice(index, 1);
        }
      }
    } else if (history.mode == 'erase') {
      if (!this.pageStrokes.hasKey(history.pageIndex)) {
        this.pageStrokes.set(history.pageIndex, []);
      }
      this.pageStrokes.get(history.pageIndex).push(history.path);
    }
    this.redoHistory.push(history);
    this.redoHistoryCount = this.redoHistory.length;
    this.updateUnsavedStrokesFlag();
    this.redraw();
  }

  executeRedo(): void {
    if (this.redoHistory.isEmpty()) {
      return;
    }
    const history = this.redoHistory.pop();
    this.redoHistoryCount = this.redoHistory.length;
    if(this.currentPageStatus.pageIndex != history.pageIndex) {
      this.setPageIndexAndGotoPage(history.pageIndex);
    }
    if (history.mode == 'add') {
      if (!this.pageStrokes.hasKey(history.pageIndex)) {
        this.pageStrokes.set(history.pageIndex, []);
      }
      this.pageStrokes.get(history.pageIndex).push(history.path);
    } else if (history.mode == 'erase') {
      if (this.pageStrokes.hasKey(history.pageIndex)) {
        const strokes = this.pageStrokes.get(history.pageIndex);
        const index = strokes.indexOf(history.path);
        if (index >= 0) {
          strokes.splice(index, 1);
        }
      }
    }
    this.undoHistory.push(history);
    this.undoHistoryCount = this.undoHistory.length;
    this.updateUnsavedStrokesFlag();
    this.redraw();
  }

  executeSave(): void {
    for (const pageIndex of this.pageStrokes.keys()) {
      const strokes = this.pageStrokes.get(pageIndex);
      const pdfPage = this.getPdfPage(pageIndex);
      if (pdfPage == null) {
        continue;
      }
      const pdfPageSize = pdfPage.size;
      const pdfRawPageSize = this.pageRawSizes.get(pageIndex);
      if (pdfRawPageSize == undefined) {
        continue;
      }
      for (const stroke of strokes) {
        let annotationInfo = new pdfService.InkAnnotationInfo();
        annotationInfo.lineColor = 0xFFCA1A1A;

        // Transform stroke points from canvas coordinates to PDF coordinates
        const transformedPoints: Vector2[] = [];
        for (const point of stroke.points) {
          let transformedPoint = Float2(
            (point.x / pdfRawPageSize.x) * pdfPageSize.x,
            (1 - point.y / pdfRawPageSize.y) * pdfPageSize.y
          );
          transformedPoints.push(transformedPoint);
        };
        annotationInfo.inkPoints = transformedPoints;
        pdfPage.page.addAnnotation(annotationInfo);
      };
    };
    this.pageStrokes.clear();
    clear(this.undoHistory);
    clear(this.redoHistory);
    this.undoHistoryCount = 0;
    this.redoHistoryCount = 0;
    this.hasUnsavedStrokes = false;

    let pageCount = this.document.getPageCount();
    for (let index = 0; index < pageCount; index++) {
      let page = this.document.getPage(index);
      let annotations = page.getAnnotations();
      annotations.forEach(annotation => {
        hilog.info(0, 'PDFView', `Annotation on page ${index}: type=${annotation.type}`);
      });
    }

    let success = this.document.saveDocument(this.sandBoxPath); //TODO: Error Handling
    if (!success) {
      hilog.error(0, 'PDFView', `Err on saving pdf file`)
    }
    this.controller.releaseDocument();
    this.controller.loadDocument(this.sandBoxPath).then(result => {
      if (result != pdfService.ParseResult.PARSE_SUCCESS) {
        hilog.error(0, 'PDFView', `Err on re-loading pdf file: ${result}`)
        app.terminate();
        return;
      }
      this.controller.setPageContinuous(false);
      this.controller.goToPage(this.currentPageStatus.pageIndex);
      this.redraw();
      this.controller.setPageFit(pdfService.PageFit.FIT_HEIGHT);
    });
  }

  redraw(): void {
    this.lctx.reset();
    this.rctx.reset();
    if (this.currentPageStatus.isDisplayingDualPage) {
      this.loadPageStrokes(this.lctx, this.currentPageStatus.leftPageIndex);
      this.loadPageStrokes(this.rctx, this.currentPageStatus.rightPageIndex);
    } else {
      this.loadPageStrokes(this.lctx, this.currentPageStatus.leftPageIndex);
    }
  }

  // addHalfDiagonalPath(): void {
  //
  //   let rawPageSize = this.pageRawSizes.get(this.currentPageStatus.leftPageIndex);
  //   const leftPageCenterX = rawPageSize.x / 2;
  //   const leftPageCenterY = rawPageSize.y / 2;
  //   this.activeDrawPath.path.moveTo(0, 0);
  //   this.activeDrawPath.path.lineTo(leftPageCenterX, leftPageCenterY);
  //   this.activeDrawPath.points.push(Float2(0, 0));
  //   this.activeDrawPath.points.push(Float2(leftPageCenterX, leftPageCenterY));
  //   // Then add it to the current page's strokes and undo history
  //   if (!this.pageStrokes.hasKey(this.currentPageStatus.leftPageIndex)) {
  //     this.pageStrokes.set(this.currentPageStatus.leftPageIndex, []);
  //   }
  //   this.pageStrokes.get(this.currentPageStatus.leftPageIndex).push(this.activeDrawPath);
  //   this.appendUndoHistory({
  //     path: this.activeDrawPath,
  //     mode: 'add',
  //     pageIndex: this.currentPageStatus.leftPageIndex
  //   });
  //   this.activeDrawPath = { path: new Path2D(), points: [] };
  //   this.updateUnsavedStrokesFlag();
  //   this.redraw();
  // }

  /**
   * @throws
   */
  handleDrawTouch(
    drawCtx: CanvasRenderingContext2D,
    targetCtx: CanvasRenderingContext2D,
    pageIndex: number,
    event: TouchEvent
  ): void {
    const isSingleTouch = event.touches.length === 1 && event.touches[0].id === 0;
    if (!isSingleTouch) {
      return;
    }
    const touchPoint = Float2(event.touches[0].x, event.touches[0].y);

    if (this.currentDrawMode == 'add') {
      if (event.type == TouchType.Down) {
        this.activeDrawPath.path.moveTo(touchPoint.x, touchPoint.y);
        this.activeDrawPath.points.push(touchPoint);
      } else if (event.type == TouchType.Move) {
        this.activeDrawPath.path.lineTo(touchPoint.x, touchPoint.y);
        drawCtx.reset();
        this.applyStrokeStyle(drawCtx);
        drawCtx.stroke(this.activeDrawPath.path);
        this.activeDrawPath.points.push(touchPoint);
      } else if (event.type == TouchType.Up) {
        this.activeDrawPath.points.push(touchPoint);
        if (!this.pageStrokes.hasKey(pageIndex)) {
          this.pageStrokes.set(pageIndex, []);
        }
        this.pageStrokes.get(pageIndex).push(this.activeDrawPath);
        this.appendUndoHistory({
          path: this.activeDrawPath,
          mode: 'add',
          pageIndex: pageIndex
        });
        this.activeDrawPath = { path: new Path2D(), points: [] };
        drawCtx.reset();
        this.updateUnsavedStrokesFlag();
        this.loadPageStrokes(targetCtx, pageIndex);
      }
    } else {
      if (!this.pageStrokes.hasKey(pageIndex)) {
        return;
      }

      const eraseThreshold = 20 * CanvasOverSampling;
      const strokes = this.pageStrokes.get(pageIndex);

      if (event.type == TouchType.Down) {
        this.pathsToErase.clear();
      }

      if (event.type == TouchType.Down || event.type == TouchType.Move) {
        for (const stroke of strokes) {
          if (this.pathsToErase.has(stroke)) {
            continue;
          }
          for (const point of stroke.points) {
            const dx = touchPoint.x - point.x;
            const dy = touchPoint.y - point.y;
            const distance = Math.sqrt(dx * dx + dy * dy);
            if (distance < eraseThreshold) {
              this.pathsToErase.add(stroke);
              break;
            }
          }
        }

        targetCtx.reset();
        this.applyStrokeStyle(targetCtx);
        for (const stroke of strokes) {
          if (!this.pathsToErase.has(stroke)) {
            targetCtx.stroke(stroke.path);
          }
        }
      } else if (event.type == TouchType.Up) {
        if (this.pathsToErase.size > 0) {
          const remainingStrokes = strokes.filter(stroke => !this.pathsToErase.has(stroke));
          this.pageStrokes.set(pageIndex, remainingStrokes);

          this.pathsToErase.forEach(erasedPath => {
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
      }
    }
  }

  updateCurrentPageStatus(newPageIndex: number): void {
    this.currentPageStatus.pageIndex = newPageIndex;
    let isDualPageMode = this.isInDualPageMode;
    const pageIndexIsLastPage = newPageIndex == this.pageCount - 1;
    if (isDualPageMode && (pageIndexIsLastPage || newPageIndex == this.pageCount - 2)) {
      isDualPageMode = this.pageCount % 2 == 0;
    }
    this.currentPageStatus.isDisplayingDualPage = isDualPageMode;
    if (isDualPageMode) {
      let leftPageIndex = 0;
      let rightPageIndex = 0;
      if (pageIndexIsLastPage) {
        leftPageIndex = newPageIndex - 1;
        rightPageIndex = newPageIndex;
      } else {
        if (newPageIndex % 2 == 0) {
          leftPageIndex = newPageIndex;
          rightPageIndex = newPageIndex + 1;
        } else {
          leftPageIndex = newPageIndex - 1;
          rightPageIndex = newPageIndex;
        }
      }
      this.currentPageStatus.leftPageIndex = leftPageIndex;
      this.currentPageStatus.rightPageIndex = rightPageIndex;
      this.controller.setPageSpacing(DualPageSpacing, 0);
    } else {
      this.currentPageStatus.leftPageIndex = newPageIndex;
      this.currentPageStatus.rightPageIndex = -1;
      this.controller.setPageSpacing(0, 0);
    }
  }

  recordPageRawSize(pageIndex: number, size: Vector2): void {
    if(this.pageRawSizes.hasKey(pageIndex)) return;
    this.pageRawSizes.set(pageIndex, {
      x: Math.round(size.x),
      y: Math.round(size.y)
    });
  }

  aboutToAppear() {
    this.controller.registerPageChangedListener(newPageIndex => {
      const pageInfo = this.getPdfPage(newPageIndex);
      if (pageInfo != null) {
        const pdfPage = pageInfo.page;
        const scale = 4;
        const pdfPageWidth = Math.ceil(pdfPage?.getWidth() * scale);
        const pdfPageHeight = Math.ceil(pdfPage?.getHeight() * scale);
        const pdfMatrix = new pdfService.PdfMatrix();
        pdfMatrix.width = pdfPageWidth;
        pdfMatrix.height = pdfPageHeight;
        pdfMatrix.rotate = 0;
        this.pixMap = pageInfo.page.getCustomPagePixelMap(pdfMatrix, false, true);
      }
      this.updateCurrentPageStatus(newPageIndex);
      this.controller.setPageFit(pdfService.PageFit.FIT_WIDTH);
      this.controller.setPageFit(pdfService.PageFit.FIT_HEIGHT);
      this.redraw();
    });
    const args = this.getUIContext().getRouter().getParams() as Record<string, string>;
    this.systemPath = args['systemPath'];
    this.sandBoxPath = args['sandboxPath'];
    this.controller.registerScaleChangedListener(scale => this.viewScale = scale);
    this.controller.registerScrollListener(scrollParam => {
      const centerX = scrollParam.pdfWidth < scrollParam.viewWidth;
      const centerY = scrollParam.pdfHeight < scrollParam.viewHeight;

      const extraX = Math.max(scrollParam.pdfWidth - scrollParam.viewWidth, 0);
      const extraY = Math.max(scrollParam.pdfHeight - scrollParam.viewHeight, 0);

      let leftX = -scrollParam.offsetX * extraX;
      let leftY = -scrollParam.offsetY * extraY;

      const space = this.controller.getPageHorizontalSpacing() * this.viewScale;
      if (this.currentPageStatus.isDisplayingDualPage) {

        const rawLeftPageSize = this.getPdfPage(this.currentPageStatus.leftPageIndex)?.size;
        const rawRightPageSize = this.getPdfPage(this.currentPageStatus.rightPageIndex)?.size;
        if (rawLeftPageSize == null || rawRightPageSize == null) {
          return;
        }

        const rawPdfWidth = rawLeftPageSize.x + rawRightPageSize.x;
        const rawPdfHeight = Math.max(rawLeftPageSize.y, rawRightPageSize.y);

        const scaledPdfWidth = scrollParam.pdfWidth - space;
        const scaledPdfHeight = scrollParam.pdfHeight;

        const leftPageWidth = scaledPdfWidth * (rawLeftPageSize.x / rawPdfWidth);
        const rightPageWidth = scaledPdfWidth * (rawRightPageSize.x / rawPdfWidth);

        const leftPageHeight = rawLeftPageSize.y * scaledPdfHeight / rawPdfHeight;
        const rightPageHeight = rawRightPageSize.y * scaledPdfHeight / rawPdfHeight;

        this.leftPageMetrics.size = Float2(
          rawLeftPageSize.x * CanvasOverSampling,
          rawLeftPageSize.y * CanvasOverSampling
        );
        this.rightPageMetrics.size = Float2(
          rawRightPageSize.x * CanvasOverSampling,
          rawRightPageSize.y * CanvasOverSampling
        );
        this.leftPageMetrics.scale = Float2(
          leftPageWidth / rawLeftPageSize.x / CanvasOverSampling,
          leftPageHeight / rawLeftPageSize.y / CanvasOverSampling
        );
        this.rightPageMetrics.scale = Float2(
          rightPageWidth / rawRightPageSize.x / CanvasOverSampling,
          rightPageHeight / rawRightPageSize.y / CanvasOverSampling
        );

        if (centerX) {
          leftX = (scrollParam.viewWidth - scrollParam.pdfWidth) / 2;
        }
        const rightX = leftX + leftPageWidth + space;
        let rightY = leftY;
        if (centerY) {
          if (leftPageHeight > rightPageHeight) {
            leftY = (scrollParam.viewHeight - scrollParam.pdfHeight) / 2;
            rightY =
              (scrollParam.viewHeight - scrollParam.pdfHeight + Math.abs((leftPageHeight - rightPageHeight))) / 2;
          } else {
            leftY = (scrollParam.viewHeight - scrollParam.pdfHeight + Math.abs((leftPageHeight - rightPageHeight))) / 2;
            rightY = (scrollParam.viewHeight - scrollParam.pdfHeight) / 2;
          }
        } else {
          if (leftPageHeight > rightPageHeight) {
            rightY += Math.abs((leftPageHeight - rightPageHeight)) / 2;
          } else {
            leftY += Math.abs((leftPageHeight - rightPageHeight)) / 2;
          }
        }

        this.leftPageMetrics.position = Float2(leftX, leftY);
        this.rightPageMetrics.position = Float2(rightX, rightY);

        this.recordPageRawSize(this.currentPageStatus.leftPageIndex, {
          x: leftPageWidth,
          y: scaledPdfHeight
        });
        this.recordPageRawSize(this.currentPageStatus.rightPageIndex, {
          x: rightPageWidth,
          y: scaledPdfHeight
        });


        hilog.info(0, "PDFView", `Left Page Pos: (${this.leftPageMetrics.position.x.toFixed(2)}, ${this.leftPageMetrics.position.y.toFixed(2)}), Size: (${this.leftPageMetrics.size.x.toFixed(2)}, ${this.leftPageMetrics.size.y.toFixed(2)}), RawSize: (${rawLeftPageSize.x.toFixed(2)}, ${rawLeftPageSize.y.toFixed(2)}) Scale: (${this.leftPageMetrics.scale.x.toFixed(2)}, ${this.leftPageMetrics.scale.y.toFixed(2)})`);
        hilog.info(0, "PDFView", `Right Page Pos: (${this.rightPageMetrics.position.x.toFixed(2)}, ${this.rightPageMetrics.position.y.toFixed(2)}), Size: (${this.rightPageMetrics.size.x.toFixed(2)}, ${this.rightPageMetrics.size.y.toFixed(2)}), RawSize: (${rawRightPageSize.x.toFixed(2)}, ${rawRightPageSize.y.toFixed(2)}) Scale: (${this.rightPageMetrics.scale.x.toFixed(2)}, ${this.rightPageMetrics.scale.y.toFixed(2)})`);

        // hilog.info(0, "PDFView", `(${this.leftPageCanvasPosition.x},${this.leftPageCanvasPosition.y},${this.leftPageCanvasSize.width},${this.leftPageCanvasSize.height}), (${this.rightPageCanvasPosition.x},${this.rightPageCanvasPosition.y},${this.rightPageCanvasSize.width},${this.rightPageCanvasSize.height})`);

      } else {
        const leftPageSize = this.getPdfPage(this.currentPageStatus.pageIndex)?.size;
        if (leftPageSize == null) {
          return;
        }

        if (centerX) {
          leftX = (scrollParam.viewWidth - scrollParam.pdfWidth) / 2;
        }
        if (centerY) {
          leftY = (scrollParam.viewHeight - scrollParam.pdfHeight) / 2;
        }
        this.leftPageMetrics.position = Float2(leftX, leftY);
        const rawLeftPageWidth = leftPageSize.x;
        const rawLeftPageHeight = leftPageSize.y;
        this.leftPageMetrics.size = Float2(
          rawLeftPageWidth * CanvasOverSampling,
          rawLeftPageHeight * CanvasOverSampling
        );
        this.leftPageMetrics.scale = Float2(
          scrollParam.pdfWidth / rawLeftPageWidth / CanvasOverSampling,
          scrollParam.pdfHeight / rawLeftPageHeight / CanvasOverSampling
        );
        this.recordPageRawSize(this.currentPageStatus.pageIndex, {
          x: scrollParam.pdfWidth,
          y: scrollParam.pdfHeight
        });

        hilog.info(0, "PDFView", `Left Page Pos: (${this.leftPageMetrics.position.x.toFixed(2)}, ${this.leftPageMetrics.position.y.toFixed(2)}), Size: (${this.leftPageMetrics.size.x.toFixed(2)}, ${this.leftPageMetrics.size.y.toFixed(2)}), RawSize: (${rawLeftPageWidth.toFixed(2)}, ${rawLeftPageHeight.toFixed(2)}) Scale: (${this.leftPageMetrics.scale.x.toFixed(2)}, ${this.leftPageMetrics.scale.y.toFixed(2)})`);

        // hilog.info(0, "PDFView", `(${this.leftPageCanvasPosition.x},${this.leftPageCanvasPosition.y},${this.leftPageCanvasSize.width},${this.leftPageCanvasSize.height})`);
      }
    });

    this.document = new pdfService.PdfDocument();
    this.document.loadDocument(this.sandBoxPath);
    const documentPages = this.document.getPageCount();
    for (let i = 0; i < documentPages; i++) {
      const page = this.document.getPage(i);
      this.pages.set(i, { size: Float2(page.getWidth(), page.getHeight()), page: page });
    }

    this.controller.loadDocument(this.sandBoxPath)
      .then(parseResult => {
        if (parseResult != pdfService.ParseResult.PARSE_SUCCESS) {
          hilog.error(0, 'PDFView', `Err on loading pdf file: ${parseResult}`)
          app.terminate();
          return;
        }
        this.pageCount = this.controller.getPageCount();
        if (this.pageCount == 0) {
          hilog.error(0, 'PDFView', `Err on loading pdf file: empty document`)
          app.terminate();
          return;
        }
        this.applyDualPageMode();
        this.updateCurrentPageStatus(0);
        this.redraw();
      });
    this.showControls = this.preferences.getSync('showControls', Visibility.Visible) as boolean;
    this.currentOperationMode = this.preferences.getSync('currentOperationMode', 'side') as 'side' | 'button' | 'extern';
    this.currentDrawMode = this.preferences.getSync('currentDrawMode', 'add') as 'add' | 'erase';
    this.isInDualPageMode = this.preferences.getSync('isInDualPageMode', false) as boolean;
    this.mainWindow.on('windowStatusChange', (statusType: window.WindowStatusType) => this.isExclusiveFullScreen =
      statusType == window.WindowStatusType.FULL_SCREEN);
  }

  onBackPress(): boolean | void {
    app.terminate();
  }

  applyDualPageMode(): void {
    this.controller.setPageLayout(this.isInDualPageMode ? pdfService.PageLayout.LAYOUT_DOUBLE :
      pdfService.PageLayout.LAYOUT_SINGLE)
    if (!this.isInDualPageMode) {
      return;
    }
    const currentPageIndex = this.currentPageStatus.pageIndex;
    if (currentPageIndex % 2 == 0) {
      return;
    }
    this.setPageIndexAndGotoPage(currentPageIndex - 1);
  }

  aboutToDisappear(): void {
    this.controller.releaseDocument();
  }

  gotoFirstPage() {
    this.setPageIndexAndGotoPage(0);
  }

  gotoLastPage() {
    this.setPageIndexAndGotoPage(this.pageCount - 1)
  }

  gotoPreviousPage() {
    let newPageIndex = 0;
    if (this.isInDualPageMode) {
      newPageIndex = this.currentPageStatus.pageIndex - 2;
      newPageIndex = Math.max(newPageIndex, 0);
      if (newPageIndex == this.currentPageStatus.pageIndex) {
        return;
      }
    } else {
      newPageIndex = this.currentPageStatus.pageIndex - 1;
      if (newPageIndex < 0) {
        return;
      }
    }
    this.setPageIndexAndGotoPage(newPageIndex);
  }

  gotoNextPage() {
    let newPageIndex = 0;
    if (this.isInDualPageMode) {
      newPageIndex = this.currentPageStatus.pageIndex + 2;
      newPageIndex = Math.min(newPageIndex, this.pageCount - 1);
      if (newPageIndex == this.currentPageStatus.pageIndex) {
        return;
      }
    } else {
      newPageIndex = this.currentPageStatus.pageIndex + 1;
      if (newPageIndex >= this.pageCount) {
        return;
      }
    }
    this.setPageIndexAndGotoPage(newPageIndex);
  }

  applyOperationMode(mode: 'side' | 'button' | 'extern') {
    this.currentOperationMode = mode;
    this.preferences.putSync('currentOperationMode', this.currentOperationMode);
    this.preferences.flushSync();
  }

  getCheckIcon(mode: 'side' | 'button' | 'extern'): SymbolGlyphModifier {
    if (mode == this.currentOperationMode) {
      return this.boxChecked;
    }
    return this.boxUnchecked;
  }

  build() {
    RelativeContainer() {

      Row(){
        Image(this.lPixMap)
          .objectFit(ImageFit.Fill)
        Image(this.rPixMap)
          .objectFit(ImageFit.Fill)
      }.alignSelf(ItemAlign.Center)

      //#region SidePageTurn Button

      Button({ type: ButtonType.Normal })
        .size({ width: PageFlipButtonWidth, height: '100%' })
        .onClick(() => this.gotoPreviousPage())
        .alignRules(TopLeft)
        .visibility(toVisibility(this.currentOperationMode == 'side'))
        .hitTestBehavior(HitTestMode.Transparent)
        .backgroundColor(Color.Transparent)


      Button({ type: ButtonType.Normal })
        .size({ width: PageFlipButtonWidth, height: '100%' })
        .onClick(() => this.gotoNextPage())
        .alignRules(TopRight)
        .visibility(toVisibility(this.currentOperationMode == 'side'))
        .hitTestBehavior(HitTestMode.Transparent)
        .backgroundColor(Color.Transparent)

      Image('')
        .size({ width: PageFlipButtonWidth, height: '100%' })
        .alignRules(TopLeft)
        .visibility(toVisibility(this.currentOperationMode == 'side'))
        .hitTestBehavior(HitTestMode.None)
        .linearGradient({
          direction: GradientDirection.Left,
          colors: [
            [Color.Transparent, 0],
            ['rgba(0, 0, 0, 0.2)', 1]
          ],
          repeating: false
        })

      Image('')
        .size({ width: PageFlipButtonWidth, height: '100%' })
        .alignRules(TopRight)
        .visibility(toVisibility(this.currentOperationMode == 'side'))
        .hitTestBehavior(HitTestMode.None)
        .linearGradient({
          direction: GradientDirection.Right,
          colors: [
            [Color.Transparent, 0],
            ['rgba(0, 0, 0, 0.2)', 1]
          ],
          repeating: false
        })


      //#endregion

      Canvas(this.lctx)
        .hitTestBehavior(HitTestMode.None)
        // .backgroundColor('rgba(255,0,0,0.1)')
        .alignRules(TopLeft)
        .offset(toPos(this.leftPageMetrics.position))
        .size(toSize(this.leftPageMetrics.size))
        .scale(toScale(this.leftPageMetrics.scale))

      Canvas(this.rctx)
        .hitTestBehavior(HitTestMode.None)
        // .backgroundColor('rgba(0,255,0,0.1)')
        .alignRules(TopLeft)
        .offset(toPos(this.rightPageMetrics.position))
        .size(toSize(this.rightPageMetrics.size))
        .scale(toScale(this.rightPageMetrics.scale))
        .visibility(toVisibility((this.currentPageStatus.isDisplayingDualPage)))

      Canvas(this.dlctx)
        .hitTestBehavior(HitTestMode.Block)
        .alignRules(TopLeft)
        .offset(toPos(this.leftPageMetrics.position))
        .size(toSize(this.leftPageMetrics.size))
        .scale(toScale(this.leftPageMetrics.scale))
        .visibility(toVisibility(this.currentDrawMode !== 'drag'))
        .onTouch(event => this.handleDrawTouch(this.dlctx, this.lctx, this.currentPageStatus.leftPageIndex, event))

      Canvas(this.drctx)
        .hitTestBehavior(HitTestMode.Block)
        .alignRules(TopLeft)
        .offset(toPos(this.rightPageMetrics.position))
        .size(toSize(this.rightPageMetrics.size))
        .scale(toScale(this.rightPageMetrics.scale))
        .visibility(toVisibility(this.currentDrawMode !== 'drag' && this.currentPageStatus.isDisplayingDualPage))
        .onTouch(event => this.handleDrawTouch(this.drctx, this.rctx, this.currentPageStatus.rightPageIndex, event))

      Row({ space: StandardOffset }) {
        Column({ space: StandardOffset }) {

          Toggle({ type: ToggleType.Button, isOn: this.isInDualPageMode }) {
            Text("双页")
              .fontSize(ButtonFontSize)
              .fontWeight(FontWeight.Bold)
          }
          .visibility(toVisibility(this.showControls))
          .onChange(isOn => {
            this.isInDualPageMode = isOn;
            this.preferences.putSync('isInDualPageMode', this.isInDualPageMode);
            this.preferences.flushSync();
            this.applyDualPageMode();
            this.updateCurrentPageStatus(this.currentPageStatus.pageIndex);
          })
          .size(ButtonSize)
          .hitTestBehavior(HitTestMode.Block)
          .monopolizeEvents(true)
          .backgroundColor(ButtonColor)
          .selectedColor(ButtonColorHighlight)

          Button("模式")
            .visibility(toVisibility(this.showControls))
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
            .size(ButtonSize)
            .hitTestBehavior(HitTestMode.Block)
            .monopolizeEvents(true)
            .backgroundColor(ButtonColor)
            .bindMenu([
              {
                value: "屏侧翻页",
                action: () => this.applyOperationMode('side'),
                symbolIcon: this.getCheckIcon('side')
              },
              {
                value: "按钮翻页",
                action: () => this.applyOperationMode('button'),
                symbolIcon: this.getCheckIcon('button')
              },
              {
                value: "外设翻页",
                action: () => this.applyOperationMode('extern'),
                symbolIcon: this.getCheckIcon('extern')
              }
            ], {
              backgroundColor: ButtonColor,
              outlineColor: Color.Transparent
            })

          Blank();

          Button("视口")
            .visibility(toVisibility(this.showControls))
            .onClick(() => this.controller.setPageFit(pdfService.PageFit.FIT_PAGE))
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
            .size(ButtonSize)
            .hitTestBehavior(HitTestMode.Block)
            .monopolizeEvents(true)
            .backgroundColor(ButtonColor)

          Button("首页")
            .visibility(toVisibility(this.showControls))
            .onClick(() => this.gotoFirstPage())
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
            .size(ButtonSize)
            .hitTestBehavior(HitTestMode.Block)
            .monopolizeEvents(true)
            .backgroundColor(ButtonColor)

          Button("尾页")
            .visibility(toVisibility(this.showControls))
            .onClick(() => this.gotoLastPage())
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
            .size(ButtonSize)
            .hitTestBehavior(HitTestMode.Block)
            .monopolizeEvents(true)
            .backgroundColor(ButtonColor)

          Button(this.showControls ? "收起" : "展开")
            .onClick(() => {
              this.showControls = !this.showControls;
              this.preferences.putSync('showControls', this.showControls);
              this.preferences.flushSync();
            })
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
            .size(ButtonSize)
            .hitTestBehavior(HitTestMode.Block)
            .monopolizeEvents(true)
            .backgroundColor(this.showControls ? ButtonColor : ButtonColorSemiTransparent)

        }.height('100%')
        Column({ space: StandardOffset }) {
          Blank()
          Button() {
            Text() {
              Span("拖动")
                .fontColor(Color.White)
              SymbolSpan(this.currentDrawMode == 'drag' ? squareCheckedSymbol : squareSymbol)
                .fontColor([Color.White])
            }
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
          }
          .size(ButtonSizeWide)
          .hitTestBehavior(HitTestMode.Block)
          .monopolizeEvents(true)
          .backgroundColor(this.currentDrawMode == 'drag' ? ButtonColorHighlight : ButtonColor)
          .onClick(() => {
            this.currentDrawMode = 'drag';
            this.preferences.putSync('currentDrawMode', this.currentDrawMode);
            this.preferences.flushSync();
          })

          Button() {
            Text() {
              Span("绘制")
                .fontColor(Color.White)
              SymbolSpan(this.currentDrawMode == 'add' ? squareCheckedSymbol : squareSymbol)
                .fontColor([Color.White])
            }
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
          }
          .size(ButtonSizeWide)
          .hitTestBehavior(HitTestMode.Block)
          .monopolizeEvents(true)
          .backgroundColor(this.currentDrawMode == 'add' ? ButtonColorHighlight : ButtonColor)
          .onClick(() => {
            this.currentDrawMode = 'add';
            this.preferences.putSync('currentDrawMode', this.currentDrawMode);
            this.preferences.flushSync();
          })

          Button() {
            Text() {
              Span("擦除")
                .fontColor(Color.White)
              SymbolSpan(this.currentDrawMode == 'erase' ? squareCheckedSymbol : squareSymbol)
                .fontColor([Color.White])
            }
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
          }
          .size(ButtonSizeWide)
          .hitTestBehavior(HitTestMode.Block)
          .monopolizeEvents(true)
          .backgroundColor(this.currentDrawMode == 'erase' ? ButtonColorHighlight : ButtonColor)
          .onClick(() => {
            this.currentDrawMode = 'erase';
            this.preferences.putSync('currentDrawMode', this.currentDrawMode);
            this.preferences.flushSync();
          })
        }.height('100%')
        Blank()
        Column({ space: StandardOffset }) {
          Blank()
          Badge({
            count: this.undoHistoryCount,
            maxCount: 2147483647,
            position: BadgePosition.RightTop,
            style: { badgeColor: BaseColor, borderColor: Color.Transparent, fontSize: HalfButtonFontSize }
          }) {
            Button(`撤回`)
              .fontSize(ButtonFontSize)
              .fontWeight(FontWeight.Bold)
              .size(ButtonSizeWide)
              .hitTestBehavior(HitTestMode.Block)
              .monopolizeEvents(true)
              .backgroundColor(ButtonColor)
              .onClick(() => this.executeUndo())
          }
          .size(ButtonSizeWide)

          Badge({
            count: this.redoHistoryCount,
            maxCount: 2147483647,
            position: BadgePosition.RightTop,
            style: { badgeColor: BaseColor, borderColor: Color.Transparent, fontSize: HalfButtonFontSize }
          }) {
            Button(`重做`)
              .fontSize(ButtonFontSize)
              .fontWeight(FontWeight.Bold)
              .size(ButtonSizeWide)
              .hitTestBehavior(HitTestMode.Block)
              .monopolizeEvents(true)
              .backgroundColor(ButtonColor)
              .onClick(() => this.executeRedo())
          }
          .size(ButtonSizeWide)

          Badge({
            value: '!',
            position: BadgePosition.RightTop,
            style: {
              badgeColor: BaseColor,
              borderColor: Color.Transparent,
              fontSize: HalfButtonFontSize,
              fontWeight: FontWeight.Bold,
              badgeSize: this.hasUnsavedStrokes ? null : 0
            }
          }) {
            Button(`保存`)
              .fontSize(ButtonFontSize)
              .fontWeight(FontWeight.Bold)
              .size(ButtonSizeWide)
              .hitTestBehavior(HitTestMode.Block)
              .monopolizeEvents(true)
              .backgroundColor(ButtonColor)
              .onClick(() => this.executeSave())
          }
          .size(ButtonSizeWide)

          Button("<")
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
            .size(ButtonSizeWide)
            .hitTestBehavior(HitTestMode.Block)
            .monopolizeEvents(true)
            .backgroundColor(ButtonColor)
            .onClick(() => this.gotoPreviousPage())
            .visibility(toVisibility(this.currentOperationMode == 'button'))

        }.height('100%')

        Column({ space: StandardOffset }) {

          Toggle({ type: ToggleType.Button, isOn: this.isExclusiveFullScreen }) {
            Text(!this.isExclusiveFullScreen ? "全屏" : "窗口")
              .fontSize(ButtonFontSize)
              .fontWeight(FontWeight.Bold)
          }
          .visibility((deviceInfo.deviceType == "phone" || !this.showControls) ? Visibility.Hidden : Visibility.Visible)
          .onChange(isOn => {
            if (isOn) {
              this.mainWindow.maximize();
            } else {
              this.mainWindow.recover();
            }
          })
          .size(ButtonSize)
          .hitTestBehavior(HitTestMode.Block)
          .monopolizeEvents(true)
          .backgroundColor(ButtonColor)
          .selectedColor(ButtonColorHighlight)
          .alignSelf(ItemAlign.End)

          Blank()

          Slider({
            value: this.currentPageStatus.pageIndex,
            min: 0,
            max: this.pageCount - 1,
            style: SliderStyle.InSet,
            direction: Axis.Vertical,
            reverse: true
          })
            .monopolizeEvents(true)
            .visibility(toVisibility(this.showControls && this.pageCount > 1))
            .showSteps(true)
            .showTips(true)
            .trackThickness(ScrollBarWidth)
            .height('50%')
            .alignSelf(ItemAlign.End)
            .trackColor(TrackColor)
            .selectedColor(ButtonColor)
            .onChange((value, _) => {
              if ((value != this.pageCount - 1) && this.isInDualPageMode && (value % 2 != 0)) {
                value -= 1;
              }
              this.setPageIndexAndGotoPage(value)
            })

          Text(`${this.currentPageStatus.pageIndex + 1}/${this.pageCount}`)
            .size(ButtonSize)
            .hitTestBehavior(HitTestMode.Block)
            .monopolizeEvents(true)
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
            .textShadow({
              type: ShadowType.BLUR,
              radius: 8,
              offsetX: 2,
              offsetY: 5
            })
            .textAlign(TextAlign.Center)
            .alignSelf(ItemAlign.End)

          Button(">")
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
            .size(ButtonSize)
            .hitTestBehavior(HitTestMode.Block)
            .monopolizeEvents(true)
            .backgroundColor(ButtonColor)
            .onClick(() => this.gotoNextPage())
            .visibility(toVisibility(this.currentOperationMode == 'button'))

          // Button('Debug')
          //   .onClick(() => this.addHalfDiagonalPath())


        }.height('100%')
      }
      .hitTestBehavior(HitTestMode.Transparent)
      .alignRules(FullRect)
      .margin(
        {
          left: StandardOffset,
          right: StandardOffset,
          top: StandardOffset,
          bottom: StandardOffset,
        }
      )

    }
    .size({ width: '100%', height: '100%' })
    .backgroundColor($r('sys.color.white'))
    .onKeyEvent(keyEvent => {
      if (keyEvent.type != KeyType.Down) {
        return;
      }
      if (this == null) {
        return;
      }

      let isCtrlPressed = false;

      if (keyEvent.getModifierKeyState != null) {
        isCtrlPressed = keyEvent.getModifierKeyState(['ctrl']);
      }

      switch (keyEvent.keyCode) {
        case KeyCode.KEYCODE_DPAD_UP:
        case KeyCode.KEYCODE_DPAD_LEFT:
          keyEvent.stopPropagation();
          if (isCtrlPressed) {
            this.gotoFirstPage();
          } else {
            this.gotoPreviousPage();
          }
          break;
        case KeyCode.KEYCODE_DPAD_DOWN:
        case KeyCode.KEYCODE_DPAD_RIGHT:
        case KeyCode.KEYCODE_SPACE:
          keyEvent.stopPropagation();
          if (isCtrlPressed) {
            this.gotoLastPage();
          } else {
            this.gotoNextPage();
          }
          break;
      }
    })
  }
}