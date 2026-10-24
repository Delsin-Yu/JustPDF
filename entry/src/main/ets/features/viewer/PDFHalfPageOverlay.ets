import { LengthMetricsUnit } from '@kit.ArkUI';
import { toSizePx, Vector2 } from '../../common/ui/Numbers';
import { PDFLinkDisplayHitArea, PDFPageSlot } from './PDFPageSlot';

@ComponentV2
export struct PDFHalfPageOverlay {
  @Param pixelMap: PixelMap | undefined = undefined;
  @Param loading: boolean = false;
  @Param pageViewSize: Vector2 = { x: 0, y: 0 };
  @Param clipSize: Vector2 = { x: 0, y: 0 };
  @Param canvasSize: Vector2 = { x: 0, y: 0 };
  @Param canvasScale: ScaleOptions = { x: 1, y: 1, centerX: 0, centerY: 0 };
  @Param overlayShown: boolean = false;
  @Param coverOpacity: number = 1;
  @Param dropShadow: ShadowOptions = { radius: 18, color: 'rgba(0, 0, 0, 0.32)', offsetX: 8, offsetY: 0 };
  @Param drawCanvasVisible: boolean = false;
  @Param annotateCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true), LengthMetricsUnit.PX);
  @Param drawCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true), LengthMetricsUnit.PX);
  @Param onDrawTouch: (event: TouchEvent) => void = () => {};
  @Param onDrawMouse: (event: MouseEvent) => void = () => {};
  @Param linkHitAreas: PDFLinkDisplayHitArea[] = [];
  @Param linkOverlayEnabled: boolean = false;
  @Param linkVisualOpacity: number = 0;
  @Param onLinkPressStart: (hitArea: PDFLinkDisplayHitArea) => void = () => {};
  @Param onLinkPressCancel: (hitArea: PDFLinkDisplayHitArea) => void = () => {};
  @Param onLinkActivated: (hitArea: PDFLinkDisplayHitArea) => void = () => {};

  build() {
    Stack() {
      PDFPageSlot({
        pixelMap: this.pixelMap,
        loading: this.loading,
        viewSize: this.pageViewSize,
        canvasSize: this.canvasSize,
        canvasScale: this.canvasScale,
        visible: true,
        drawCanvasVisible: this.drawCanvasVisible,
        annotateCtx: this.annotateCtx,
        drawCtx: this.drawCtx,
        onDrawTouch: (event: TouchEvent) => this.onDrawTouch(event),
        onDrawMouse: (event: MouseEvent) => this.onDrawMouse(event),
        linkHitAreas: this.linkHitAreas,
        linkOverlayEnabled: this.linkOverlayEnabled,
        linkVisualOpacity: this.linkVisualOpacity,
        onLinkPressStart: (hitArea: PDFLinkDisplayHitArea) => this.onLinkPressStart(hitArea),
        onLinkPressCancel: (hitArea: PDFLinkDisplayHitArea) => this.onLinkPressCancel(hitArea),
        onLinkActivated: (hitArea: PDFLinkDisplayHitArea) => this.onLinkActivated(hitArea)
      })
    }
    .alignContent(Alignment.TopStart)
    .size(toSizePx(this.clipSize))
    .clip(true)
    .shadow(this.dropShadow)
    .opacity(this.overlayShown ? this.coverOpacity : 0)
    .visibility(this.pixelMap !== undefined ? Visibility.Visible : Visibility.Hidden)
  }
}
