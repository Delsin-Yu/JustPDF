import { FullRect, toVisibility } from '../../components/UIComponents';
import { toSizePx, Vector2 } from '../../components/Numbers';
import { LengthMetricsUnit } from '@kit.ArkUI';

@ComponentV2
export struct PDFPageSlot {
  @Param pixelMap: PixelMap | undefined = undefined;
  @Param loading: boolean = false;
  @Param viewSize: Vector2 = { x: 0, y: 0 };
  @Param canvasSize: Vector2 = { x: 0, y: 0 };
  @Param canvasScale: ScaleOptions = { x: 1, y: 1, centerX: 0, centerY: 0 };
  @Param visible: boolean = true;
  @Param drawCanvasVisible: boolean = false;
  @Param annotateCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true), LengthMetricsUnit.PX);
  @Param drawCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true), LengthMetricsUnit.PX);
  @Param onDrawTouch: (event: TouchEvent) => void = () => {};
  @Param onDrawMouse: (event: MouseEvent) => void = () => {};

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
    .visibility(toVisibility(this.visible))
  }
}
