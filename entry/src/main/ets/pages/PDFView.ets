import { deviceInfo } from '@kit.BasicServicesKit';
import { pdfService, PdfView, pdfViewManager } from '@kit.PDFKit';
import { KeyCode } from '@kit.InputKit';
import { LengthUnit, SymbolGlyphModifier, window } from '@kit.ArkUI';
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

const PdfViewId = 'pdfview_control';

enum OperationMode {
  SidePageTurn,
  ButtonPageTurn,
  ExternalPageTurn,
}

@Entry
@Component
struct PDFView {
  @State pageCount: number = 0;
  @State pageIndex: number = 0;
  @State showControls: Visibility = Visibility.Visible;
  @State currentOperationMode: OperationMode = OperationMode.SidePageTurn;
  @State enableAnnotation: boolean = false;
  @State isInDualPageMode: boolean = false;
  @State isExclusiveFullScreen: boolean = false;
  // @State leftPageCanvasPosition: Position = { x: 0, y: 0 };
  // @State rightPageCanvasPosition: Position = { x: 0, y: 0 };
  // @State leftPageCanvasSize: Size = { width: 0, height: 0 };
  // @State rightPageCanvasSize: Size = { width: 0, height: 0 };
  // @State leftPageCanvasScale: ScaleOptions = { x: 0, y: 0 };
  // @State rightPageCanvasScale: ScaleOptions = { x: 0, y: 0 };
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
  private controller: pdfViewManager.PdfController = new pdfViewManager.PdfController();
  private document: pdfService.PdfDocument = new pdfService.PdfDocument();

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

  aboutToAppear() {
    let args = this.getUIContext().getRouter().getParams() as Record<string, string>;
    let systemPath = args['systemPath'];
    let sandboxPath = args['sandboxPath'];
    this.document.loadDocument(sandboxPath);
    this.controller.loadDocument(sandboxPath)
      .then(parseResult => {
        if (parseResult != pdfService.ParseResult.PARSE_SUCCESS) {
          hilog.error(0, 'PDFView', `Err on loading pdf file: ${parseResult}`)
          app.terminate();
          return;
        }
        this.controller.registerScaleChangedListener(scale => this.viewScale = scale);
        // this.controller.registerScrollListener(scrollParam => {
        //   //hilog.info(0, "PDFView", `s: ${this.viewScale.toFixed(2)} x: ${scrollParam.offsetX.toFixed(2)}, y: ${scrollParam.offsetY.toFixed(2)}, vw: ${scrollParam.viewWidth.toFixed(2)}, vh: ${scrollParam.viewHeight.toFixed(2)}, pw: ${scrollParam.pdfWidth.toFixed(2)}, ph: ${scrollParam.pdfHeight.toFixed(2)}`);
        //   let centerX = scrollParam.pdfWidth < scrollParam.viewWidth;
        //   let centerY = scrollParam.pdfHeight < scrollParam.viewHeight;
        //
        //   let extraX = Math.max(scrollParam.pdfWidth - scrollParam.viewWidth, 0);
        //   let extraY = Math.max(scrollParam.pdfHeight - scrollParam.viewHeight, 0);
        //
        //   let leftX = -scrollParam.offsetX * extraX;
        //   let leftY = -scrollParam.offsetY * extraY;
        //
        //   let isDualPage = this.isInDualPageMode;
        //
        //   let pageIndexIsLastPage = this.pageIndex == this.pageCount - 1;
        //
        //   if (pageIndexIsLastPage || this.pageIndex == this.pageCount - 2) {
        //     isDualPage = this.pageCount % 2 == 0;
        //   }
        //
        //   let space = this.controller.getPageHorizontalSpacing() * this.viewScale;
        //   if (isDualPage) {
        //
        //     let leftPageIndex = 0;
        //     let rightPageIndex = 0;
        //     if (pageIndexIsLastPage) {
        //       leftPageIndex = this.pageIndex - 1;
        //       rightPageIndex = this.pageIndex;
        //     } else {
        //       leftPageIndex = this.pageIndex;
        //       rightPageIndex = this.pageIndex + 1;
        //     }
        //
        //     let leftPage = this.document.getPage(leftPageIndex);
        //     let rightPage = this.document.getPage(rightPageIndex);
        //
        //     let rawLeftPageWidth = leftPage.getWidth();
        //     let rawLeftPageHeight = leftPage.getHeight();
        //     let rawRightPageWidth = rightPage.getWidth();
        //     let rawRightPageHeight = rightPage.getHeight();
        //     let rawPdfWidth = rawLeftPageWidth + rawRightPageWidth;
        //     let rawPdfHeight = Math.max(rawLeftPageHeight, rawRightPageHeight);
        //
        //     let scaledPdfWidth = scrollParam.pdfWidth - space;
        //     let scaledPdfHeight = scrollParam.pdfHeight;
        //
        //     let leftPageWidth = scaledPdfWidth * (rawLeftPageWidth / rawPdfWidth);
        //     let rightPageWidth = scaledPdfWidth * (rawRightPageWidth / rawPdfWidth);
        //
        //     let leftPageHeight = rawLeftPageHeight * scaledPdfHeight / rawPdfHeight;
        //     let rightPageHeight = rawRightPageHeight * scaledPdfHeight / rawPdfHeight;
        //
        //     // hilog.info(0, "PDFView",
        //     //   `s: ${this.viewScale.toFixed(2)} x: ${scrollParam.offsetX.toFixed(2)}, y: ${scrollParam.offsetY.toFixed(2)}, vw: ${scrollParam.viewWidth.toFixed(2)}, vh: ${scrollParam.viewHeight.toFixed(2)}, pw: ${scrollParam.pdfWidth.toFixed(2)}, ph: ${scrollParam.pdfHeight.toFixed(2)}, lpw: ${leftPageWidth}, lph: ${leftPageHeight}, rpw: ${rightPageWidth}, rph: ${rightPageHeight}`);
        //
        //     this.leftPageCanvasSize = { width: rawLeftPageWidth, height: rawLeftPageHeight };
        //     this.rightPageCanvasSize = { width: rawRightPageWidth, height: rawRightPageHeight };
        //     this.leftPageCanvasScale = {
        //       x: leftPageWidth / rawLeftPageWidth,
        //       y: leftPageHeight / rawLeftPageHeight,
        //       centerX: `0px`,
        //       centerY: `0px`
        //     };
        //     this.rightPageCanvasScale = {
        //       x: rightPageWidth / rawRightPageWidth,
        //       y: rightPageHeight / rawRightPageHeight,
        //       centerX: `0px`,
        //       centerY: `0px`
        //     };
        //
        //     if (centerX) {
        //       leftX = (scrollParam.viewWidth - scrollParam.pdfWidth) / 2;
        //     }
        //     let rightX = leftX + leftPageWidth + space;
        //     let rightY = leftY;
        //     if (centerY) {
        //       if (leftPageHeight > rightPageHeight) {
        //         leftY = (scrollParam.viewHeight - scrollParam.pdfHeight) / 2;
        //         rightY =
        //           (scrollParam.viewHeight - scrollParam.pdfHeight + Math.abs((leftPageHeight - rightPageHeight))) / 2;
        //       } else {
        //         leftY =
        //           (scrollParam.viewHeight - scrollParam.pdfHeight + Math.abs((leftPageHeight - rightPageHeight))) / 2;
        //         rightY = (scrollParam.viewHeight - scrollParam.pdfHeight) / 2;
        //       }
        //     } else {
        //       if (leftPageHeight > rightPageHeight) {
        //         rightY += Math.abs((leftPageHeight - rightPageHeight)) / 2;
        //       } else {
        //         leftY += Math.abs((leftPageHeight - rightPageHeight)) / 2;
        //       }
        //     }
        //
        //     this.leftPageCanvasPosition = { x: `${leftX}px`, y: `${leftY}px` };
        //     this.rightPageCanvasPosition = { x: `${rightX}px`, y: `${rightY}px` };
        //
        //     hilog.info(0, "PDFView",
        //       `(${rawLeftPageWidth.toFixed(2)},${rawLeftPageHeight.toFixed(2)}), (${rawRightPageWidth.toFixed(2)},${rawRightPageHeight.toFixed(2)})`);
        //
        //   } else {
        //     let leftPage = this.document.getPage(this.pageIndex);
        //
        //     if (centerX) {
        //       leftX = (scrollParam.viewWidth - scrollParam.pdfWidth) / 2;
        //     }
        //     if (centerY) {
        //       leftY = (scrollParam.viewHeight - scrollParam.pdfHeight) / 2;
        //     }
        //     this.leftPageCanvasPosition = { x: `${leftX}px`, y: `${leftY}px` };
        //     let rawLeftPageWidth = leftPage.getWidth();
        //     let rawLeftPageHeight = leftPage.getHeight();
        //     this.leftPageCanvasSize = { width: rawLeftPageWidth, height: rawLeftPageHeight };
        //     this.leftPageCanvasScale = {
        //       x: scrollParam.pdfWidth / rawLeftPageWidth,
        //       y: scrollParam.pdfHeight / rawLeftPageHeight,
        //       centerX: `0px`,
        //       centerY: `0px`
        //     };
        //
        //     // hilog.info(0, "PDFView", `(${this.leftPageCanvasPosition.x},${this.leftPageCanvasPosition.y},${this.leftPageCanvasSize.width},${this.leftPageCanvasSize.height})`);
        //   }
        // });
        this.pageCount = this.controller.getPageCount();
        this.applyDualPageMode();
      });
    this.showControls = this.preferences.getSync('showControls', Visibility.Visible) as Visibility;
    this.currentOperationMode =
      this.preferences.getSync('currentOperationMode', OperationMode.SidePageTurn) as OperationMode;
    this.enableAnnotation = this.preferences.getSync('enableAnnotation', false) as boolean;
    this.isInDualPageMode = this.preferences.getSync('isInDualPageMode', false) as boolean;
    this.mainWindow.on('windowStatusChange', (statusType: window.WindowStatusType) =>
    this.isExclusiveFullScreen = statusType == window.WindowStatusType.FULL_SCREEN);
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

      // Canvas(this.lCtx) {
      //   // Polyline({ width: '100%', height: '100%' })
      //   //   .hitTestBehavior(HitTestMode.Transparent)
      //   //   .points(this.leftPageStrokes)
      //   //   .fillOpacity(0)
      //   //   .stroke(Color.Red)
      //   //   .strokeWidth(`3px`)
      // }
      // .backgroundColor('rgba(255,0,0,0.2)')
      // .hitTestBehavior(HitTestMode.Transparent)
      // .offset(this.leftPageCanvasPosition)
      // .size({ width: `${this.leftPageCanvasSize.width}px`, height: `${this.leftPageCanvasSize.height}px` })
      // .scale(this.leftPageCanvasScale)
      // .visibility(this.enableAnnotation ? Visibility.Visible : Visibility.Hidden)
      //
      // Canvas(this.rCtx) {
      //   // Polyline({ width: '100%', height: '100%' })
      //   //   .hitTestBehavior(HitTestMode.Transparent)
      //   //   .points(this.rightPageStrokes)
      //   //   .fillOpacity(0)
      //   //   .stroke(Color.Red)
      //   //   .strokeWidth(`3px`)
      // }
      // .backgroundColor('rgba(0,255,0,0.2)')
      // .hitTestBehavior(HitTestMode.Transparent)
      // .offset(this.rightPageCanvasPosition)
      // .size({ width: `${this.rightPageCanvasSize.width}px`, height: `${this.rightPageCanvasSize.height}px` })
      // .scale(this.rightPageCanvasScale)
      // .visibility((this.enableAnnotation && this.isDualPageEnabled()) ? Visibility.Visible : Visibility.Hidden)


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

          Blank()

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

          Blank()

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