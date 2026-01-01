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

enum OperationMode {
  SidePageTurn,
  ButtonPageTurn,
  ExternalPageTurn,
}

interface Float2 {
  x: number;
  y: number;
}

interface PdfPage {
  size: Float2;
  page: pdfService.PdfPage;
}

@Entry
@Component
struct PDFView {
  private controller: pdfViewManager.PdfController = new pdfViewManager.PdfController();
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private lRCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private rRCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private pageStrokes = new HashMap<number, Array<Float32Array>>();
  private pages = new HashMap<number, PdfPage>();
  @State pageCount: number = 0;
  @State pageIndex: number = 0;
  @State showControls: Visibility = Visibility.Visible;
  @State currentOperationMode: OperationMode = OperationMode.SidePageTurn;
  @State enableAnnotation: boolean = false;
  @State isInDualPageMode: boolean = false;
  @State isExclusiveFullScreen: boolean = false;
  @State leftPageCanvasPosition: Float2 = { x: 0, y: 0 };
  @State rightPageCanvasPosition: Float2 = { x: 0, y: 0 };
  @State leftPageCanvasSize: Float2 = { x: 0, y: 0 };
  @State rightPageCanvasSize: Float2 = { x: 0, y: 0 };
  @State leftPageCanvasScale: Float2 = { x: 0, y: 0 };
  @State rightPageCanvasScale: Float2 = { x: 0, y: 0 };
  @State viewScale: number = 0;
  preferences: preferences.Preferences = AppStorage.get('preferences') as preferences.Preferences;
  mainWindow: window.Window = (AppStorage.get('windowStage') as window.WindowStage).getMainWindowSync();
  boxUnchecked: SymbolGlyphModifier =
    new SymbolGlyphModifier($r('sys.symbol.square'))
      .fontColor([Color.White])
      .fontSize(16)
      .fontWeight(FontWeight.Regular);
  boxChecked: SymbolGlyphModifier =
    new SymbolGlyphModifier($r('sys.symbol.checkmark_square_fill'))
      .fontColor([Color.White])
      .fontSize(16)
      .fontWeight(FontWeight.Regular);

  setPageIndexAndGotoPage(newIndex: number) {
    if (this.pageIndex == newIndex) {
      return;
    }
    this.pageIndex = newIndex;
    this.controller.goToPage(this.pageIndex);
  }

  isDualPageEnabled(): boolean {
    let isDualPage = this.isInDualPageMode;

    let pageIndexIsLastPage = this.pageIndex == this.pageCount - 1;

    if (pageIndexIsLastPage || this.pageIndex == this.pageCount - 2) {
      isDualPage = this.pageCount % 2 == 0;
    }
    return isDualPage;
  }

  getPdfPage(pageIndex: number): Nullable<PdfPage> {
    if (this.pages.hasKey(pageIndex)) {
      return this.pages.get(pageIndex);
    }
    return undefined;
  }

  getPageStrokes(pageIndex: number): Array<Float32Array> {
    if (this.pageStrokes.hasKey(pageIndex)) {
      return this.pageStrokes.get(pageIndex);
    }
    let strokes: Array<Float32Array> = [];
    let page = this.getPdfPage(pageIndex);
    if (page == null) {
      return strokes;
    }

    const w = page.size.x;
    const h = page.size.y;
    const cx = w / 2;
    const cy = h / 2;

    const p1: Float2 = { x: 0, y: 0 };
    const p2: Float2 = { x: w, y: h };
    const q1: Float2 = { x: w, y: 0 };
    const q2: Float2 = { x: 0, y: h };

    const angle = -(15 * pageIndex) * Math.PI / 180;
    const cosA = Math.cos(angle);
    const sinA = Math.sin(angle);
    const rotate = (x: number, y: number) => {
      const dx = x - cx;
      const dy = y - cy;
      return { x: cx + dx * cosA - dy * sinA, y: cy + dx * sinA + dy * cosA } as Float2;
    };

    const rp1 = rotate(p1.x, p1.y);
    const rp2 = rotate(p2.x, p2.y);
    const stroke1 = new Float32Array([rp1.x, rp1.y, rp2.x, rp2.y]);

    const rq1 = rotate(q1.x, q1.y);
    const rq2 = rotate(q2.x, q2.y);
    const stroke2 = new Float32Array([rq1.x, rq1.y, rq2.x, rq2.y]);

    strokes.push(stroke1);
    strokes.push(stroke2);
    this.pageStrokes.set(pageIndex, strokes);
    return strokes;
  }

  clearCtx(ctx: CanvasRenderingContext2D) {
    ctx.reset();
  }

  loadPageStrokes(ctx: CanvasRenderingContext2D, pageIndex: number) {
    let strokes = this.getPageStrokes(pageIndex);
    ctx.strokeStyle = 'red';
    ctx.lineWidth = 2 * CanvasOverSampling;
    for (let stroke of strokes) {
      ctx.beginPath();
      let pointCount = stroke.length / 2;
      if (pointCount <= 0) {
        continue;
      }
      const x0 = stroke[0] * CanvasOverSampling;
      const y0 = stroke[1] * CanvasOverSampling;
      // Move to first point
      ctx.moveTo(x0, y0);
      if (pointCount == 1) {
        // Single-point stroke: draw a small filled circle as a dot
        ctx.fillStyle = 'red';
        ctx.arc(x0, y0, 2 * CanvasOverSampling, 0, 2 * Math.PI);
        ctx.fill();
      } else {
        for (let i = 1; i < pointCount; i++) {
          const xi = stroke[i * 2] * CanvasOverSampling;
          const yi = stroke[i * 2 + 1] * CanvasOverSampling;
          ctx.lineTo(xi, yi);
        }
        ctx.stroke();
      }
    }
  }

  loadCurrentViewStrokes(pageIndex: number) {
    let isDualPage = this.isInDualPageMode;

    let pageIndexIsLastPage = pageIndex == this.pageCount - 1;

    if (isDualPage && pageIndexIsLastPage || pageIndex == this.pageCount - 2) {
      isDualPage = this.pageCount % 2 == 0;
    }

    this.clearCtx(this.lRCtx);
    this.clearCtx(this.rRCtx);

    if (isDualPage) {
      let leftPageIndex = 0;
      let rightPageIndex = 0;
      if (pageIndexIsLastPage) {
        leftPageIndex = pageIndex - 1;
        rightPageIndex = pageIndex;
      } else {
        leftPageIndex = pageIndex;
        rightPageIndex = pageIndex + 1;
      }

      this.loadPageStrokes(this.lRCtx, leftPageIndex);
      this.loadPageStrokes(this.rRCtx, rightPageIndex);
    } else {
      this.loadPageStrokes(this.lRCtx, pageIndex);
    }
  }

  aboutToAppear() {
    this.controller.registerPageChangedListener(newPageIndex => {
      this.pageIndex = newPageIndex
      this.loadCurrentViewStrokes(newPageIndex);
    });
    let args = this.getUIContext().getRouter().getParams() as Record<string, string>;
    let systemPath = args['systemPath'];
    let sandboxPath = args['sandboxPath'];
    this.controller.registerScaleChangedListener(scale => this.viewScale = scale);
    this.controller.registerScrollListener(scrollParam => {
      //hilog.info(0, "PDFView", `s: ${this.viewScale.toFixed(2)} x: ${scrollParam.offsetX.toFixed(2)}, y: ${scrollParam.offsetY.toFixed(2)}, vw: ${scrollParam.viewWidth.toFixed(2)}, vh: ${scrollParam.viewHeight.toFixed(2)}, pw: ${scrollParam.pdfWidth.toFixed(2)}, ph: ${scrollParam.pdfHeight.toFixed(2)}`);
      let centerX = scrollParam.pdfWidth < scrollParam.viewWidth;
      let centerY = scrollParam.pdfHeight < scrollParam.viewHeight;

      let extraX = Math.max(scrollParam.pdfWidth - scrollParam.viewWidth, 0);
      let extraY = Math.max(scrollParam.pdfHeight - scrollParam.viewHeight, 0);

      let leftX = -scrollParam.offsetX * extraX;
      let leftY = -scrollParam.offsetY * extraY;

      let isDualPage = this.isInDualPageMode;

      let pageIndexIsLastPage = this.pageIndex == this.pageCount - 1;

      if (isDualPage && pageIndexIsLastPage || this.pageIndex == this.pageCount - 2) {
        isDualPage = this.pageCount % 2 == 0;
      }

      let space = this.controller.getPageHorizontalSpacing() * this.viewScale;
      if (isDualPage) {

        let leftPageIndex = 0;
        let rightPageIndex = 0;
        if (pageIndexIsLastPage) {
          leftPageIndex = this.pageIndex - 1;
          rightPageIndex = this.pageIndex;
        } else {
          leftPageIndex = this.pageIndex;
          rightPageIndex = this.pageIndex + 1;
        }

        let rawLeftPageSize = this.getPdfPage(leftPageIndex)?.size;
        let rawRightPageSize = this.getPdfPage(rightPageIndex)?.size;
        if (rawLeftPageSize == null || rawRightPageSize == null) {
          return;
        }

        let rawPdfWidth = rawLeftPageSize.x + rawRightPageSize.x;
        let rawPdfHeight = Math.max(rawLeftPageSize.y, rawRightPageSize.y);

        let scaledPdfWidth = scrollParam.pdfWidth - space;
        let scaledPdfHeight = scrollParam.pdfHeight;

        let leftPageWidth = scaledPdfWidth * (rawLeftPageSize.x / rawPdfWidth);
        let rightPageWidth = scaledPdfWidth * (rawRightPageSize.x / rawPdfWidth);

        let leftPageHeight = rawLeftPageSize.y * scaledPdfHeight / rawPdfHeight;
        let rightPageHeight = rawRightPageSize.y * scaledPdfHeight / rawPdfHeight;

        this.leftPageCanvasSize = {
          x: rawLeftPageSize.x * CanvasOverSampling,
          y: rawLeftPageSize.y * CanvasOverSampling
        };
        this.rightPageCanvasSize = {
          x: rawRightPageSize.x * CanvasOverSampling,
          y: rawRightPageSize.y * CanvasOverSampling
        };
        this.leftPageCanvasScale = {
          x: leftPageWidth / rawLeftPageSize.x / CanvasOverSampling,
          y: leftPageHeight / rawLeftPageSize.y / CanvasOverSampling,
        };
        this.rightPageCanvasScale = {
          x: rightPageWidth / rawRightPageSize.x / CanvasOverSampling,
          y: rightPageHeight / rawRightPageSize.y / CanvasOverSampling,
        };

        if (centerX) {
          leftX = (scrollParam.viewWidth - scrollParam.pdfWidth) / 2;
        }
        let rightX = leftX + leftPageWidth + space;
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

        this.leftPageCanvasPosition = { x: leftX, y: leftX };
        this.rightPageCanvasPosition = { x: rightX, y: rightX };

        // hilog.info(0, "PDFView", `(${this.leftPageCanvasPosition.x},${this.leftPageCanvasPosition.y},${this.leftPageCanvasSize.width},${this.leftPageCanvasSize.height}), (${this.rightPageCanvasPosition.x},${this.rightPageCanvasPosition.y},${this.rightPageCanvasSize.width},${this.rightPageCanvasSize.height})`);

      } else {
        let leftPageSize = this.getPdfPage(this.pageIndex)?.size;
        if (leftPageSize == null) {
          return;
        }

        if (centerX) {
          leftX = (scrollParam.viewWidth - scrollParam.pdfWidth) / 2;
        }
        if (centerY) {
          leftY = (scrollParam.viewHeight - scrollParam.pdfHeight) / 2;
        }
        this.leftPageCanvasPosition = { x: leftX, y: leftY };
        let rawLeftPageWidth = leftPageSize.x;
        let rawLeftPageHeight = leftPageSize.y;
        this.leftPageCanvasSize = {
          x: rawLeftPageWidth * CanvasOverSampling,
          y: rawLeftPageHeight * CanvasOverSampling
        };
        this.leftPageCanvasScale = {
          x: scrollParam.pdfWidth / rawLeftPageWidth / CanvasOverSampling,
          y: scrollParam.pdfHeight / rawLeftPageHeight / CanvasOverSampling,
        };

        // hilog.info(0, "PDFView", `(${this.leftPageCanvasPosition.x},${this.leftPageCanvasPosition.y},${this.leftPageCanvasSize.width},${this.leftPageCanvasSize.height})`);

      }

    });
    let document = new pdfService.PdfDocument();
    document.loadDocument(sandboxPath);
    let documentPages = document.getPageCount();
    for (let i = 0; i < documentPages; i++) {
      let page = document.getPage(i);
      this.pages.set(i, { size: { x: page.getWidth(), y: page.getHeight() }, page: page });
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
        this.loadCurrentViewStrokes(this.pageIndex);
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
    let currentPageIndex = this.pageIndex;
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
      newPageIndex = this.pageIndex - 2;
      newPageIndex = Math.max(newPageIndex, 0);
      if (newPageIndex == this.pageIndex) {
        return;
      }
    } else {
      newPageIndex = this.pageIndex - 1;
      if (newPageIndex < 0) {
        return;
      }
    }
    this.setPageIndexAndGotoPage(newPageIndex);
  }

  gotoNextPage() {
    let newPageIndex = 0;
    if (this.isInDualPageMode) {
      newPageIndex = this.pageIndex + 2;
      newPageIndex = Math.min(newPageIndex, this.pageCount - 1);
      if (newPageIndex == this.pageIndex) {
        return;
      }
    } else {
      newPageIndex = this.pageIndex + 1;
      if (newPageIndex >= this.pageCount) {
        return;
      }
    }
    this.setPageIndexAndGotoPage(newPageIndex);
  }

  applyOperationMode(mode: OperationMode, enableAnnotation: boolean): void {
    this.currentOperationMode = mode;
    this.enableAnnotation = enableAnnotation;
    this.preferences.putSync('currentOperationMode', this.currentOperationMode);
    this.preferences.putSync('enableAnnotation', this.enableAnnotation);
    this.preferences.flushSync();
    if (enableAnnotation) {
      this.controller.enableAnnotation(pdfViewManager.SupportedAnnotationType.POLYGON,
        Color.Red);
    } else {
      this.controller.disableAnnotation();
    }
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
      }).width('100%').height('100%').id(PdfViewId)

      Canvas(this.lRCtx)
        .hitTestBehavior(HitTestMode.Transparent)
        // .backgroundColor('rgba(255,0,0,0.1)')
        .alignRules(
          {
            'top': { 'anchor': '__container__', 'align': VerticalAlign.Top },
            'left': { 'anchor': '__container__', 'align': HorizontalAlign.Start },
          }
        )
        .offset({x: `${this.leftPageCanvasPosition.x}px`, y: `${this.leftPageCanvasPosition.y}px`})
        .size({width: `${this.leftPageCanvasSize.x}px`, height: `${this.leftPageCanvasSize.y}px`})
        .scale({x: this.leftPageCanvasScale.x, y: this.leftPageCanvasScale.y, centerX: 0, centerY: 0})

      Canvas(this.rRCtx)
        .hitTestBehavior(HitTestMode.Transparent)
        // .backgroundColor('rgba(0,255,0,0.1)')
        .alignRules(
          {
            'top': { 'anchor': '__container__', 'align': VerticalAlign.Top },
            'left': { 'anchor': '__container__', 'align': HorizontalAlign.Start },
          }
        )
        .offset({x: `${this.rightPageCanvasPosition.x}px`, y: `${this.rightPageCanvasPosition.y}px`})
        .size({width: `${this.rightPageCanvasSize.x}px`, height: `${this.rightPageCanvasSize.y}px`})
        .scale({x: this.rightPageCanvasScale.x, y: this.rightPageCanvasScale.y, centerX: 0, centerY: 0})
        .visibility(this.isDualPageEnabled() ? Visibility.Visible : Visibility.Hidden)

      //#region SidePageTurn Button

      Button({ type: ButtonType.Normal })
        .fontSize(ButtonFontSize)
        .fontWeight(FontWeight.Bold)
        .size({ width: PageFlipButtonWidth, height: '100%' })
        .backgroundColor(Color.Transparent)
        .onClick(() => this.gotoPreviousPage())
        .alignRules({
          top: { anchor: '__container__', align: VerticalAlign.Top },
          left: { anchor: '__container__', align: HorizontalAlign.Start }
        })
        .visibility(this.isSidePageTurn() ? Visibility.Visible : Visibility.None)

      Button({ type: ButtonType.Normal })
        .fontSize(ButtonFontSize)
        .fontWeight(FontWeight.Bold)
        .size({ width: PageFlipButtonWidth, height: '100%' })
        .backgroundColor(Color.Transparent)
        .onClick(() => this.gotoNextPage())
        .alignRules({
          top: { anchor: '__container__', align: VerticalAlign.Top },
          right: { anchor: '__container__', align: HorizontalAlign.End }
        })
        .visibility(this.isSidePageTurn() ? Visibility.Visible : Visibility.None)

      //#endregion

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
                action: () => this.applyOperationMode(OperationMode.SidePageTurn, false),
                symbolIcon: this.getCheckIcon(OperationMode.SidePageTurn, false)
              },
              {
                value: "按钮翻页",
                action: () => this.applyOperationMode(OperationMode.ButtonPageTurn, false),
                symbolIcon: this.getCheckIcon(OperationMode.ButtonPageTurn, false)
              },
              {
                value: "外设翻页",
                action: () => this.applyOperationMode(OperationMode.ExternalPageTurn, false),
                symbolIcon: this.getCheckIcon(OperationMode.ExternalPageTurn, false)
              },
              // {
              //   value: "按钮翻页（标注）",
              //   action: () => this.applyOperationMode(OperationMode.ButtonPageTurn, true),
              //   symbolIcon: this.getCheckIcon(OperationMode.ButtonPageTurn, true)
              // },
              // {
              //   value: "外设翻页（标注）",
              //   action: () => this.applyOperationMode(OperationMode.ExternalPageTurn, true),
              //   symbolIcon: this.getCheckIcon(OperationMode.ExternalPageTurn, true)
              // }
            ], {
              backgroundColor: ButtonColor,
              outlineColor: Color.Transparent
            })

          Column().layoutWeight(1)

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

        }.height('100%').hitTestBehavior(HitTestMode.Transparent)

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
          .visibility(this.enableAnnotation ? Visibility.Visible : Visibility.Hidden)

        }.height('100%').hitTestBehavior(HitTestMode.Transparent).layoutWeight(1)

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
            value: this.pageIndex,
            min: 0,
            max: this.pageCount - 1,
            style: SliderStyle.InSet,
            direction: Axis.Vertical,
            reverse: true
          })
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

          Text(`${this.pageIndex + 1}/${this.pageCount}`)
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
              .alignRules({
                top: { anchor: "__container__", align: VerticalAlign.Top },
                left: { anchor: "__container__", align: HorizontalAlign.Start },
              })
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

        }.height('100%').hitTestBehavior(HitTestMode.Transparent)
      }
      .hitTestBehavior(HitTestMode.Transparent)
      .alignRules(
        {
          'top': { 'anchor': '__container__', 'align': VerticalAlign.Top },
          'bottom': { 'anchor': '__container__', 'align': VerticalAlign.Bottom },
          'left': { 'anchor': '__container__', 'align': HorizontalAlign.Start },
          'right': { 'anchor': '__container__', 'align': HorizontalAlign.End },
        }
      )
      .margin(
        {
          left: StandardOffset,
          right: StandardOffset,
          top: StandardOffset,
          bottom: StandardOffset,
        }
      )

    }
    .width('100%')
    .height('100%')
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