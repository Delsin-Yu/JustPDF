import { deviceInfo } from '@kit.BasicServicesKit';
import { pdfService, PdfView, pdfViewManager } from '@kit.PDFKit';
import { KeyCode } from '@kit.InputKit';
import { LengthMetricsUnit, LengthUnit, SymbolGlyphModifier, window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import app from '@system.app';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HashMap } from '@kit.ArkTS';

const ButtonColor: ResourceColor = `rgba(60, 60, 60, 0.7)`;
const ButtonColorSemiTransparent: ResourceColor = 'rgba(60, 60, 60, 0.2)';
const ButtonColorHighlight: ResourceColor = 'rgba(180, 180, 180, 0.9)';
const TrackColor: ResourceColor = 'rgba(60, 60, 60, 0.4)';
const StandardOffsetValue: number = 8;
const StandardOffset: number = 8;
const ButtonFontSize: Length = '20vp';
const ButtonSizeH: number = 40;
const ButtonSizeW: number = 80;
const ButtonSize: SizeOptions = { height: ButtonSizeH, width: ButtonSizeW };
const PageFlipButtonWidth: Length = '30%';
const ScrollBarWidth: Length = '40vp';
const CanvasOverSampling: number = 3;
const PdfViewId = 'pdfview_control';
const TopLeft: AlignRuleOption = {
  top: { anchor: '__container__', align: VerticalAlign.Top },
  left: { anchor: '__container__', align: HorizontalAlign.Start },
};
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

enum OperationMode {
  SidePageTurn,
  ButtonPageTurn,
  ExternalPageTurn,
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

@Entry
@Component
struct PDFView {
  private controller: pdfViewManager.PdfController = new pdfViewManager.PdfController();
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private lctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private rctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private dlctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private drctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private pageStrokes = new HashMap<number, Array<PathWithPoints>>();
  private pages = new HashMap<number, PdfPage>();
  private preferences: preferences.Preferences = AppStorage.get('preferences') as preferences.Preferences;
  private mainWindow: window.Window = (AppStorage.get('windowStage') as window.WindowStage).getMainWindowSync();
  private boxUnchecked: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.square')).fontColor([Color.White]).fontSize(16).fontWeight(FontWeight.Regular);
  private boxChecked: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.checkmark_square_fill')).fontColor([Color.White]).fontSize(16).fontWeight(FontWeight.Regular);
  private activeDrawPath: PathWithPoints = { path: new Path2D(), points: [] };
  @State pageCount: number = 0;
  @State showControls: Visibility = Visibility.Visible;
  @State currentOperationMode: OperationMode = OperationMode.SidePageTurn;
  @State enableAnnotation: boolean = false;
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
    ctx.strokeStyle = 'rgb(255,0,0)';
    ctx.lineWidth = 2 * CanvasOverSampling;
    ctx.lineCap = 'round';
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
      this.activeDrawPath = { path: new Path2D(), points: [] };
      drawCtx.reset();
      this.loadPageStrokes(targetCtx, pageIndex);
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
    } else {
      this.currentPageStatus.leftPageIndex = newPageIndex;
      this.currentPageStatus.rightPageIndex = -1;
    }
  }

  aboutToAppear() {
    this.controller.registerPageChangedListener(newPageIndex => {
      this.updateCurrentPageStatus(newPageIndex);
      this.lctx.reset();
      this.rctx.reset();
      if (this.currentPageStatus.isDisplayingDualPage) {
        this.loadPageStrokes(this.lctx, this.currentPageStatus.leftPageIndex);
        this.loadPageStrokes(this.rctx, this.currentPageStatus.rightPageIndex);
      } else {
        this.loadPageStrokes(this.lctx, this.currentPageStatus.leftPageIndex);
      }
    });
    const args = this.getUIContext().getRouter().getParams() as Record<string, string>;
    const systemPath = args['systemPath'];
    const sandboxPath = args['sandboxPath'];
    this.controller.registerScaleChangedListener(scale => this.viewScale = scale);
    this.controller.registerScrollListener(scrollParam => {
      //hilog.info(0, "PDFView", `s: ${this.viewScale.toFixed(2)} x: ${scrollParam.offsetX.toFixed(2)}, y: ${scrollParam.offsetY.toFixed(2)}, vw: ${scrollParam.viewWidth.toFixed(2)}, vh: ${scrollParam.viewHeight.toFixed(2)}, pw: ${scrollParam.pdfWidth.toFixed(2)}, ph: ${scrollParam.pdfHeight.toFixed(2)}`);
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

        // hilog.info(0, "PDFView", `(${this.leftPageCanvasPosition.x},${this.leftPageCanvasPosition.y},${this.leftPageCanvasSize.width},${this.leftPageCanvasSize.height})`);
      }
    });

    const document = new pdfService.PdfDocument();
    document.loadDocument(sandboxPath);
    const documentPages = document.getPageCount();
    for (let i = 0; i < documentPages; i++) {
      const page = document.getPage(i);
      this.pages.set(i, { size: Float2(page.getWidth(), page.getHeight()), page: page });
    }
    document.releaseDocument();

    this.controller.loadDocument(sandboxPath)
      .then(parseResult => {
        if (parseResult != pdfService.ParseResult.PARSE_SUCCESS) {
          hilog.error(0, 'PDFView', `Err on loading pdf file: ${parseResult}`)
          app.terminate();
          return;
        }
        this.pageCount = this.controller.getPageCount();
        this.applyDualPageMode();
        this.updateCurrentPageStatus(0);
        if (this.currentPageStatus.isDisplayingDualPage) {
          this.loadPageStrokes(this.lctx, this.currentPageStatus.leftPageIndex);
          this.loadPageStrokes(this.rctx, this.currentPageStatus.rightPageIndex);
        } else {
          this.loadPageStrokes(this.lctx, this.currentPageStatus.leftPageIndex);
        }
      });
    this.showControls = this.preferences.getSync('showControls', Visibility.Visible) as Visibility;
    this.currentOperationMode =
      this.preferences.getSync('currentOperationMode', OperationMode.SidePageTurn) as OperationMode;
    this.enableAnnotation = this.preferences.getSync('enableAnnotation', false) as boolean;
    this.isInDualPageMode = this.preferences.getSync('isInDualPageMode', false) as boolean;
    this.mainWindow.on('windowStatusChange', (statusType: window.WindowStatusType) => this.isExclusiveFullScreen =
      statusType == window.WindowStatusType.FULL_SCREEN);
  }

  isSidePageTurn(): boolean {
    return this.currentOperationMode == OperationMode.SidePageTurn;
  }

  isButtonPageTurn(): boolean {
    return this.currentOperationMode == OperationMode.ButtonPageTurn;
  }

  isExternalPageTurn(): boolean {
    return this.currentOperationMode == OperationMode.ExternalPageTurn;
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

  applyOperationMode(mode: OperationMode): void {
    this.currentOperationMode = mode;
    this.preferences.putSync('currentOperationMode', this.currentOperationMode);
    this.preferences.flushSync();
  }

  getCheckIcon(mode: OperationMode, enableAnnotation: boolean): SymbolGlyphModifier {
    if (mode == this.currentOperationMode && enableAnnotation == this.enableAnnotation) {
      return this.boxChecked;
    }
    return this.boxUnchecked;
  }

  build() {
    RelativeContainer() {

      PdfView({
        controller: this.controller,
        pageFit: pdfService.PageFit.FIT_PAGE,
        isContinuous: false,
        pageLayout: pdfService.PageLayout.LAYOUT_SINGLE
      })
        .size({ width: '100%', height: '100%' })
        .id(PdfViewId)

      //#region SidePageTurn Button

      Button({ type: ButtonType.Normal })
        .size({ width: PageFlipButtonWidth, height: '100%' })
        .backgroundColor('rgba(0, 0, 0, 0.02)')
        .onClick(() => this.gotoPreviousPage())
        .alignRules(TopLeft)
        .visibility(this.isSidePageTurn() ? Visibility.Visible : Visibility.None)

      Button({ type: ButtonType.Normal })
        .size({ width: PageFlipButtonWidth, height: '100%' })
        .backgroundColor('rgba(0, 0, 0, 0.02)')
        .onClick(() => this.gotoNextPage())
        .alignRules(TopRight)
        .visibility(this.isSidePageTurn() ? Visibility.Visible : Visibility.None)

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
        .hitTestBehavior(this.enableAnnotation ? HitTestMode.Block : HitTestMode.None)
        .alignRules(TopLeft)
        .offset(toPos(this.leftPageMetrics.position))
        .size(toSize(this.leftPageMetrics.size))
        .scale(toScale(this.leftPageMetrics.scale))
        .visibility(toVisibility(this.enableAnnotation))
        .onTouch(event => this.handleDrawTouch(this.dlctx, this.lctx, this.currentPageStatus.leftPageIndex, event))

      Canvas(this.drctx)
        .hitTestBehavior(this.enableAnnotation ? HitTestMode.Block : HitTestMode.None)
        .alignRules(TopLeft)
        .offset(toPos(this.rightPageMetrics.position))
        .size(toSize(this.rightPageMetrics.size))
        .scale(toScale(this.rightPageMetrics.scale))
        .visibility(toVisibility(this.enableAnnotation && this.currentPageStatus.isDisplayingDualPage))
        .onTouch(event => this.handleDrawTouch(this.drctx, this.rctx, this.currentPageStatus.rightPageIndex, event))

      Row({ space: StandardOffset }) {
        Column({ space: StandardOffset }) {

          Toggle({ type: ToggleType.Button, isOn: this.isInDualPageMode }) {
            Text("双页")
              .fontSize(ButtonFontSize)
              .fontWeight(FontWeight.Bold)
          }
          .visibility(this.showControls)
          .onChange(isOn => {
            this.isInDualPageMode = isOn;
            this.preferences.putSync('isInDualPageMode', this.isInDualPageMode);
            this.preferences.flushSync();
            this.applyDualPageMode();
            this.updateCurrentPageStatus(this.currentPageStatus.pageIndex);
          })
          .size(ButtonSize)
          .backgroundColor(ButtonColor)
          .selectedColor(ButtonColorHighlight)

          Button("模式")
            .visibility(this.showControls)
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
            .size(ButtonSize)
            .backgroundColor(ButtonColor)
            .bindMenu([
              {
                value: "屏侧翻页",
                action: () => this.applyOperationMode(OperationMode.SidePageTurn),
                symbolIcon: this.getCheckIcon(OperationMode.SidePageTurn, false)
              },
              {
                value: "按钮翻页",
                action: () => this.applyOperationMode(OperationMode.ButtonPageTurn),
                symbolIcon: this.getCheckIcon(OperationMode.ButtonPageTurn, false)
              },
              {
                value: "外设翻页",
                action: () => this.applyOperationMode(OperationMode.ExternalPageTurn),
                symbolIcon: this.getCheckIcon(OperationMode.ExternalPageTurn, false)
              }
            ], {
              backgroundColor: ButtonColor,
              outlineColor: Color.Transparent
            })

          Toggle({ type: ToggleType.Button, isOn: this.enableAnnotation }) {
            Text("标注")
              .fontSize(ButtonFontSize)
              .fontWeight(FontWeight.Bold)
          }
          .visibility(this.showControls)
          .onChange(isOn => {
            this.enableAnnotation = isOn;
            this.preferences.putSync('enableAnnotation', this.isInDualPageMode);
            this.preferences.flushSync();
          })
          .size(ButtonSize)
          .backgroundColor(ButtonColor)
          .selectedColor(ButtonColorHighlight)

          Blank();

          Button("视口")
            .visibility(this.showControls)
            .onClick(() => this.controller.setPageFit(pdfService.PageFit.FIT_PAGE))
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
            .size(ButtonSize)
            .backgroundColor(ButtonColor)

          Button("首页")
            .visibility(this.showControls)
            .onClick(() => this.gotoFirstPage())
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
            .size(ButtonSize)
            .backgroundColor(ButtonColor)

          Button("尾页")
            .visibility(this.showControls)
            .onClick(() => this.gotoLastPage())
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
            .size(ButtonSize)
            .backgroundColor(ButtonColor)

          Button(this.showControls == Visibility.Visible ? "收起" : "展开")
            .onClick(() => {
              if (this.showControls == Visibility.Visible) {
                this.showControls = Visibility.None;
              } else {
                this.showControls = Visibility.Visible;
              }
              this.preferences.putSync('showControls', this.showControls);
              this.preferences.flushSync();
            })
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
            .size(ButtonSize)
            .backgroundColor(this.showControls == Visibility.Visible ? ButtonColor : ButtonColorSemiTransparent)

        }.height('100%')

        Column({ space: StandardOffset }) {

          Flex({
            direction: FlexDirection.Row,
            wrap: FlexWrap.Wrap,
            justifyContent: FlexAlign.Center,
            space: {
              main: { value: StandardOffsetValue, unit: LengthUnit.VP },
              cross: { value: StandardOffsetValue, unit: LengthUnit.VP },
            }
          }) {

            Button("绘制")
              .fontSize(ButtonFontSize)
              .fontWeight(FontWeight.Bold)
              .size(ButtonSize)
              .backgroundColor(ButtonColor)

            Button("擦除")
              .fontSize(ButtonFontSize)
              .fontWeight(FontWeight.Bold)
              .size(ButtonSize)
              .backgroundColor(ButtonColor)

            Button("撤回")
              .fontSize(ButtonFontSize)
              .fontWeight(FontWeight.Bold)
              .size(ButtonSize)
              .backgroundColor(ButtonColor)

            Button("重做")
              .fontSize(ButtonFontSize)
              .fontWeight(FontWeight.Bold)
              .size(ButtonSize)
              .backgroundColor(ButtonColor)

          }
          .align(Alignment.Center)
          .visibility(toVisibility(this.enableAnnotation))

        }.height('100%').layoutWeight(1)

        Column({ space: StandardOffset }) {

          Toggle({ type: ToggleType.Button, isOn: this.isExclusiveFullScreen }) {
            Text(!this.isExclusiveFullScreen ? "全屏" : "窗口")
              .fontSize(ButtonFontSize)
              .fontWeight(FontWeight.Bold)
          }
          .visibility((deviceInfo.deviceType == "phone" || this.showControls) ? Visibility.Hidden : Visibility.Visible)
          .onChange(isOn => {
            if (isOn) {
              this.mainWindow.maximize();
            } else {
              this.mainWindow.recover();
            }
          })
          .size(ButtonSize)
          .backgroundColor(ButtonColor)
          .selectedColor(ButtonColorHighlight)
          .alignSelf(ItemAlign.End)

          Column().layoutWeight(1)

          Slider({
            value: this.currentPageStatus.pageIndex,
            min: 0,
            max: this.pageCount - 1,
            style: SliderStyle.InSet,
            direction: Axis.Vertical,
            reverse: true
          })
            .monopolizeEvents(true)
            .visibility(this.showControls)
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

          RelativeContainer() {
            Button("<")
              .fontSize(ButtonFontSize)
              .fontWeight(FontWeight.Bold)
              .size(ButtonSize)
              .backgroundColor(ButtonColor)
              .onClick(() => this.gotoPreviousPage())
              .alignRules(TopLeft)
              .offset({
                left: -(ButtonSizeW + StandardOffset)
              })
            Button(">")
              .fontSize(ButtonFontSize)
              .fontWeight(FontWeight.Bold)
              .size(ButtonSize)
              .backgroundColor(ButtonColor)
              .onClick(() => this.gotoNextPage())
          }
          .size(ButtonSize)
          .visibility(this.isButtonPageTurn() ? Visibility.Visible : Visibility.None)

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