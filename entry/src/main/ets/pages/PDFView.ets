import { pdfService, pdfViewManager, PdfView } from '@kit.PDFKit';
import { router } from '@kit.ArkUI';
import { KeyCode } from '@kit.InputKit';

const ButtonColor: ResourceColor = 'rgba(85, 85, 85, 1)';
const ButtonColorHighlight: ResourceColor = 'rgba(180, 180, 180, 1)';
const TrackColor: ResourceColor = 'rgba(85, 85, 85, 0.4)';
const StandardOffset: LPX = '5lpx';
const ButtonFontSize: number = 20;
const ButtonSize: SizeOptions = { height: '30lpx', width: '60lpx' };

const PdfViewId = 'pdfview_control';


@Entry
@Component
struct PDFView {
  private controller: pdfViewManager.PdfController = new pdfViewManager.PdfController();
  @State pageCount: number = 0;
  @State pageIndex: number = 0;
  isInDualPageMode: boolean = false;

  setPageIndexAndGotoPage(newIndex: number) {
    if (this.pageIndex == newIndex) {
      return;
    }
    this.pageIndex = newIndex;
    this.controller.goToPage(this.pageIndex);
  }

  aboutToAppear() {
    this.controller.registerPageChangedListener(newPageIndex => this.pageIndex = newPageIndex);
    this.controller.loadDocument((router.getParams() as Record<string, string>)['src']).then(() => {
      this.pageCount = this.controller.getPageCount();
    });
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

      Column({ space: StandardOffset }) {
        Toggle({ type: ToggleType.Button }) {
          Text("双页")
            .fontSize(ButtonFontSize)
            .fontWeight(FontWeight.Bold)
        }
        .onChange(isOn => {
          this.isInDualPageMode = isOn;
          this.controller.setPageLayout(isOn ? pdfService.PageLayout.LAYOUT_DOUBLE :
          pdfService.PageLayout.LAYOUT_SINGLE)
          if (!isOn) {
            return;
          }
          let currentPageIndex = this.pageIndex;
          if (currentPageIndex % 2 == 0) {
            return;
          }
          this.setPageIndexAndGotoPage(currentPageIndex - 1);
        })
        .size(ButtonSize)
        .backgroundColor(ButtonColor)
        .selectedColor(ButtonColorHighlight)

        Button("视口")
          .onClick(() => this.controller.setPageFit(pdfService.PageFit.FIT_PAGE))
          .fontSize(ButtonFontSize)
          .fontWeight(FontWeight.Bold)
          .size(ButtonSize)
          .backgroundColor(ButtonColor)
        Button("首页")
          .onClick(() => this.gotoFirstPage())
          .fontSize(ButtonFontSize)
          .fontWeight(FontWeight.Bold)
          .size(ButtonSize)
          .backgroundColor(ButtonColor)
        Button("尾页")
          .onClick(() => this.gotoLastPage())
          .fontSize(ButtonFontSize)
          .fontWeight(FontWeight.Bold)
          .size(ButtonSize)
          .backgroundColor(ButtonColor)
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
          .trackThickness('30lpx')
          .height('60%')
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
          .fontSize(ButtonFontSize)
          .fontWeight(FontWeight.Bold)
          .textShadow({
            type: ShadowType.BLUR,
            radius: 8,
            offsetX: 2,
            offsetY: 5
          })
          .size(ButtonSize)
          .textAlign(TextAlign.Center)
      }
      .alignRules({
        bottom: { anchor: '__container__', align: VerticalAlign.Bottom },
        right: { anchor: '__container__', align: HorizontalAlign.End }
      })
      .offset({ right: StandardOffset, bottom: StandardOffset })
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