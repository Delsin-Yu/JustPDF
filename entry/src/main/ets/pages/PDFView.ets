import { pdfService, pdfViewManager, PdfView } from '@kit.PDFKit';
import { KeyCode } from '@kit.InputKit';
import { window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';

const ButtonColor: ResourceColor = 'rgba(85, 85, 85, 1)';
const ButtonColorSemiTransparent: ResourceColor = 'rgba(85, 85, 85, 0.2)';
const ButtonColorHighlight: ResourceColor = 'rgba(180, 180, 180, 1)';
const TrackColor: ResourceColor = 'rgba(85, 85, 85, 0.4)';
const StandardOffsetValue: number = 5;
const StandardOffset: LPX = `${StandardOffsetValue}lpx`;
const ButtonFontSize: number = 20;
const ButtonSize: SizeOptions = { height: '25lpx', width: '50lpx' };

const PdfViewId = 'pdfview_control';


@Entry
@Component
struct PDFView {
  private controller: pdfViewManager.PdfController = new pdfViewManager.PdfController();
  @State pageCount: number = 0;
  @State pageIndex: number = 0;
  @State showControls: Visibility = Visibility.Visible;
  @State isAlternateControlMode: boolean = false;
  @State isInDualPageMode: boolean = false;
  decorBarHeight: number = AppStorage.get("decorBarHeight") as number;
  @State isExclusiveFullScreen: boolean = false;
  preferences: preferences.Preferences = AppStorage.get('preferences') as preferences.Preferences;
  mainWindow: window.Window = (AppStorage.get('windowStage') as window.WindowStage).getMainWindowSync();

  setPageIndexAndGotoPage(newIndex: number) {
    if (this.pageIndex == newIndex) {
      return;
    }
    this.pageIndex = newIndex;
    this.controller.goToPage(this.pageIndex);
  }

  aboutToAppear() {
    this.controller.registerPageChangedListener(newPageIndex => this.pageIndex = newPageIndex);
    this.controller.loadDocument((this.getUIContext().getRouter().getParams() as Record<string, string>)['src'])
      .then(() => {
        this.pageCount = this.controller.getPageCount();
        this.applyDualPageMode();
      });
    this.showControls = this.preferences.getSync('showControls', Visibility.Visible) as Visibility;
    this.isAlternateControlMode = this.preferences.getSync('isAlternateControlMode', false) as boolean;
    this.isInDualPageMode = this.preferences.getSync('isInDualPageMode', false) as boolean;
    this.mainWindow.on('windowStatusChange', (statusType: window.WindowStatusType) => this.isExclusiveFullScreen =
      statusType == window.WindowStatusType.FULL_SCREEN);
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

  build() {
    RelativeContainer() {
      PdfView({
        controller: this.controller,
        pageFit: pdfService.PageFit.FIT_PAGE,
        isContinuous: false,
        pageLayout: pdfService.PageLayout.LAYOUT_SINGLE
      }).width('100%').height('100%').id(PdfViewId)

      Image('')
        .width('100%')
        .height(this.decorBarHeight)
        .alignSelf(ItemAlign.Center)
        .linearGradient({
          colors: [['rgba(0, 0, 0, 0.2)', 0.0], ['rgba(0, 0, 0, 0)', 1.0]]
        })
        .alignRules({
          top: { anchor: '__container__', align: VerticalAlign.Top },
          left: { anchor: '__container__', align: HorizontalAlign.Start }
        })
        .visibility(this.isExclusiveFullScreen ? Visibility.None : Visibility.Visible)

      Button({ type: ButtonType.Normal })
        .fontSize(ButtonFontSize)
        .fontWeight(FontWeight.Bold)
        .size({ width: '30%', height: '100%' })
        .backgroundColor(Color.Transparent)
        .onClick(() => this.gotoPreviousPage())
        .alignRules({
          top: { anchor: '__container__', align: VerticalAlign.Top },
          left: { anchor: '__container__', align: HorizontalAlign.Start }
        })
        .visibility(this.isAlternateControlMode ? Visibility.None : Visibility.Visible)


      Button({ type: ButtonType.Normal })
        .fontSize(ButtonFontSize)
        .fontWeight(FontWeight.Bold)
        .size({ width: '30%', height: '100%' })
        .backgroundColor(Color.Transparent)
        .onClick(() => this.gotoNextPage())
        .alignRules({
          top: { anchor: '__container__', align: VerticalAlign.Top },
          right: { anchor: '__container__', align: HorizontalAlign.End }
        })
        .visibility(this.isAlternateControlMode ? Visibility.None : Visibility.Visible)


      Column({ space: StandardOffset }) {
        Toggle({ type: ToggleType.Button, isOn: this.isInDualPageMode }) {
          Text("双页")
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
        }
        .onChange(isOn => {
          this.isInDualPageMode = isOn;
          this.preferences.putSync('isInDualPageMode', this.isInDualPageMode);
          this.preferences.flushSync();
          this.applyDualPageMode();
        })
        .size(ButtonSize)
        .backgroundColor(ButtonColor)
        .selectedColor(ButtonColorHighlight)
        .visibility(this.showControls)

        Toggle({ type: ToggleType.Button, isOn: this.isAlternateControlMode }) {
          Text("切换")
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
        }
        .onChange(isOn => {
          this.isAlternateControlMode = isOn
          this.preferences.putSync('isAlternateControlMode', this.isAlternateControlMode);
          this.preferences.flushSync();
        })
        .size(ButtonSize)
        .backgroundColor(ButtonColor)
        .selectedColor(ButtonColorHighlight)
        .visibility(this.showControls)

        Button("视口")
          .onClick(() => this.controller.setPageFit(pdfService.PageFit.FIT_PAGE))
          .fontSize(ButtonFontSize)
          .fontWeight(FontWeight.Bold)
          .size(ButtonSize)
          .backgroundColor(ButtonColor)
          .visibility(this.showControls)

        Button("首页")
          .onClick(() => this.gotoFirstPage())
          .fontSize(ButtonFontSize)
          .fontWeight(FontWeight.Bold)
          .size(ButtonSize)
          .backgroundColor(ButtonColor)
          .visibility(this.showControls)

        Button("尾页")
          .onClick(() => this.gotoLastPage())
          .fontSize(ButtonFontSize)
          .fontWeight(FontWeight.Bold)
          .size(ButtonSize)
          .backgroundColor(ButtonColor)
          .visibility(this.showControls)


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

      }.alignRules({
        bottom: { anchor: '__container__', align: VerticalAlign.Bottom },
        left: { anchor: '__container__', align: HorizontalAlign.Start }
      }).offset({ left: StandardOffset, bottom: StandardOffset })

      Column({ space: StandardOffset }) {
        Slider({
          value: this.pageIndex,
          min: 0,
          max: this.pageCount - 1,
          style: SliderStyle.InSet,
          direction: Axis.Vertical,
          reverse: true
        })
          .showSteps(true)
          .showTips(true)
          .trackThickness('20lpx')
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
          .visibility(this.showControls)

        Text(`${this.pageIndex + 1}/${this.pageCount}`)
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

        Row({ space: StandardOffset }) {
          Button("<")
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
            .size(ButtonSize)
            .backgroundColor(ButtonColor)
            .onClick(() => this.gotoPreviousPage())
          Button(">")
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
            .size(ButtonSize)
            .backgroundColor(ButtonColor)
            .onClick(() => this.gotoNextPage())
        }
        .visibility(this.isAlternateControlMode ? Visibility.Visible : Visibility.None)
      }
      .alignRules({
        bottom: { anchor: '__container__', align: VerticalAlign.Bottom },
        right: { anchor: '__container__', align: HorizontalAlign.End }
      })
      .offset({ right: StandardOffset, bottom: StandardOffset })
      .responseRegion({
        x: 0,
        y: 0,
        width: '0%',
        height: '0%'
      })

      Column({ space: StandardOffset }) {
        Toggle({ type: ToggleType.Button }) {
          Text(!this.isExclusiveFullScreen ? "全屏" : "窗口")
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
        }
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
      }
      .alignRules({
        top: { anchor: '__container__', align: VerticalAlign.Top },
        right: { anchor: '__container__', align: HorizontalAlign.End }
      })
      .offset({ right: StandardOffset, top: !this.isExclusiveFullScreen ? this.decorBarHeight : StandardOffset })
      .visibility(this.showControls)

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