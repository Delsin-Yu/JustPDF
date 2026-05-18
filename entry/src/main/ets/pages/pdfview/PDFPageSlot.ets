import { FullRect, toVisibility } from '../../components/UIComponents';
import { toSizePx, Vector2 } from '../../components/Numbers';
import { PdfLinkTarget } from '../../components/PageInfo';
import { LengthMetricsUnit } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const LINK_TAP_MOVE_THRESHOLD_PX: number = 10;
const LINK_HIT_AREA_PADDING_PX: number = 4;
const LINK_HIT_AREA_RADIUS_PX: number = 5;

export interface PDFLinkDisplayHitArea {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
  target: PdfLinkTarget;
}

@ComponentV2
export struct PDFPageSlot {
  @Param pixelMap: PixelMap | undefined = undefined;
  @Param loading: boolean = false;
  @Param viewSize: Vector2 = { x: 0, y: 0 };
  @Param canvasSize: Vector2 = { x: 0, y: 0 };
  @Param canvasScale: ScaleOptions = { x: 1, y: 1, centerX: 0, centerY: 0 };
  @Param visible: boolean = true;
  /** true 且 visible=false 时使用 Hidden 占位（仍参与布局）；用于双/三页主行「无该页」时避免 None 拆掉槽宽或透明层叠残影 */
  @Param occupyLayoutWhenHidden: boolean = false;
  @Param drawCanvasVisible: boolean = false;
  @Param annotateCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true), LengthMetricsUnit.PX);
  @Param drawCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true), LengthMetricsUnit.PX);
  @Param onDrawTouch: (event: TouchEvent) => void = () => {};
  @Param onDrawMouse: (event: MouseEvent) => void = () => {};
  @Param linkHitAreas: PDFLinkDisplayHitArea[] = [];
  @Param linkOverlayEnabled: boolean = false;
  @Param linkVisualOpacity: number = 0;
  @Param onLinkPressStart: (hitArea: PDFLinkDisplayHitArea) => void = () => {};
  @Param onLinkPressCancel: (hitArea: PDFLinkDisplayHitArea) => void = () => {};
  @Param onLinkActivated: (hitArea: PDFLinkDisplayHitArea) => void = () => {};

  private activeLinkHitAreaId: string = '';
  private activeLinkStartX: number = 0;
  private activeLinkStartY: number = 0;
  private activeLinkCanceled: boolean = false;

  private shouldRenderLinkOverlay(): boolean {
    return this.linkOverlayEnabled && !this.drawCanvasVisible && this.linkHitAreas.length > 0;
  }

  private getClampedLinkVisualOpacity(): number {
    return Math.max(0, Math.min(1, this.linkVisualOpacity));
  }

  private getLinkVisualFillColor(): ResourceColor {
    const alpha = this.getClampedLinkVisualOpacity() * 0.18;
    return alpha > 0.001 ? `rgba(0, 128, 255, ${alpha})` : Color.Transparent;
  }

  private getLinkVisualBorderColor(): ResourceColor {
    const alpha = this.getClampedLinkVisualOpacity() * 0.75;
    return alpha > 0.001 ? `rgba(0, 128, 255, ${alpha})` : Color.Transparent;
  }

  @Builder
  private buildLinkHitArea(hitArea: PDFLinkDisplayHitArea) {
    Stack() {
    }
      .width(`${hitArea.width + LINK_HIT_AREA_PADDING_PX * 2}px`)
      .height(`${hitArea.height + LINK_HIT_AREA_PADDING_PX * 2}px`)
      .padding(`${LINK_HIT_AREA_PADDING_PX}px`)
      .position({ x: `${hitArea.x - LINK_HIT_AREA_PADDING_PX}px`, y: `${hitArea.y - LINK_HIT_AREA_PADDING_PX}px` })
      .backgroundColor(this.getLinkVisualFillColor())
      .borderRadius(`${LINK_HIT_AREA_RADIUS_PX}px`)
      .border({
        width: this.getClampedLinkVisualOpacity() > 0.001 ? 1 : 0,
        color: this.getLinkVisualBorderColor()
      })
      // Keep link rectangles touchable without preventing the full-page transparent input layer from
      // receiving the same drag stream for pan/zoom or horizontal-slide handling.
      .hitTestBehavior(HitTestMode.Transparent)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.activeLinkHitAreaId = hitArea.id;
          this.activeLinkStartX = event.touches[0].x;
          this.activeLinkStartY = event.touches[0].y;
          this.activeLinkCanceled = false;
          hilog.info(0, 'PDFView', `PDF 链接热区 Down: id=${hitArea.id}, target=${hitArea.target.kind}, local=(${event.touches[0].x},${event.touches[0].y}), rect=(${hitArea.x},${hitArea.y},${hitArea.width},${hitArea.height})`);
          this.onLinkPressStart(hitArea);
          return;
        }

        if (this.activeLinkHitAreaId !== hitArea.id) {
          return;
        }

        if (event.type === TouchType.Move && event.touches.length > 0) {
          const dx = event.touches[0].x - this.activeLinkStartX;
          const dy = event.touches[0].y - this.activeLinkStartY;
          if (!this.activeLinkCanceled && dx * dx + dy * dy > LINK_TAP_MOVE_THRESHOLD_PX * LINK_TAP_MOVE_THRESHOLD_PX) {
            this.activeLinkCanceled = true;
            hilog.info(0, 'PDFView', `PDF 链接热区 Move 取消: id=${hitArea.id}, dx=${dx}, dy=${dy}`);
            this.onLinkPressCancel(hitArea);
          }
          return;
        }

        if (event.type === TouchType.Up) {
          const shouldActivate = !this.activeLinkCanceled;
          this.activeLinkHitAreaId = '';
          this.activeLinkCanceled = false;
          hilog.info(0, 'PDFView', `PDF 链接热区 Up: id=${hitArea.id}, shouldActivate=${shouldActivate}`);
          if (shouldActivate) {
            this.onLinkActivated(hitArea);
          }
          return;
        }

        if (event.type === TouchType.Cancel) {
          this.activeLinkHitAreaId = '';
          this.activeLinkCanceled = false;
          hilog.info(0, 'PDFView', `PDF 链接热区 Cancel: id=${hitArea.id}`);
          this.onLinkPressCancel(hitArea);
        }
      })
  }

  build() {
    RelativeContainer() {
      Image(this.pixelMap).alignRules(FullRect).draggable(false)
      Canvas(this.annotateCtx)
        .size(toSizePx(this.canvasSize))
        .scale(this.canvasScale)
        .hitTestBehavior(HitTestMode.None)
      Canvas(this.drawCtx)
        .size(toSizePx(this.canvasSize))
        .scale(this.canvasScale)
        .visibility(toVisibility(this.drawCanvasVisible))
        .onTouch((event: TouchEvent) => this.onDrawTouch(event))
        .onMouse((event: MouseEvent) => this.onDrawMouse(event))
      if (this.shouldRenderLinkOverlay()) {
        ForEach(this.linkHitAreas, (hitArea: PDFLinkDisplayHitArea) => {
          this.buildLinkHitArea(hitArea)
        }, (hitArea: PDFLinkDisplayHitArea) => hitArea.id)
      }
      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
        }
        .width('100%')
        .height(120)
        .justifyContent(FlexAlign.End)
        .padding({ bottom: 12 })
        .linearGradient({ direction: GradientDirection.Bottom, colors: [['#00000000', 0.0], ['#33000000', 1.0]] })
        .alignRules({ bottom: { anchor: '__container__', align: VerticalAlign.Bottom } })
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .size(toSizePx(this.viewSize))
    .visibility(
      this.visible
        ? Visibility.Visible
        : (this.occupyLayoutWhenHidden ? Visibility.Hidden : Visibility.None)
    )
  }
}
