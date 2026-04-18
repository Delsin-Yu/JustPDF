import { SymbolGlyphModifier } from '@kit.ArkUI';
import { Stack } from '@kit.ArkTS';
import { pdfService } from '@kit.PDFKit';

const HalfButtonFontSize: Length = '10vp';
const ButtonFontSize: Length = '20vp';
const ButtonHeight: Length = '40vp';
const ButtonSize: SizeOptions = { height: ButtonHeight, width: 80 };
const ButtonSizeWide: SizeOptions = { height: ButtonHeight, width: 90 };

export const ButtonColor: ResourceColor = `rgba(0, 0, 0, 0.4)`;

const ButtonColorHighlight: ResourceColor = 'rgba(160, 160, 160, 0.9)';

export const ButtonColorSemiTransparent: ResourceColor = 'rgba(50, 50, 50, 0.2)';

const BaseColor: ResourceColor = `rgba(0, 0, 0, 1)`;
const TrackColor: ResourceColor = 'rgba(0, 0, 0, 0.2)';
const ScrollBarWidth: Length = '40vp';
const squareSymbol = $r('sys.symbol.square');
const squareCheckedSymbol = $r('sys.symbol.checkmark_square_fill');
const boxUnchecked: SymbolGlyphModifier = new SymbolGlyphModifier(squareSymbol)
  .fontColor([Color.White])
  .fontSize(ButtonFontSize)
  .fontWeight(FontWeight.Medium);
const boxChecked: SymbolGlyphModifier = new SymbolGlyphModifier(squareCheckedSymbol)
  .fontColor([Color.White])
  .fontSize(ButtonFontSize)
  .fontWeight(FontWeight.Medium);

export const ContainerSpacing: number = 8;

export const ContainerCfg: RowOptions | ColumnOptions = { space: `${ContainerSpacing}px` };

export const ContainerPadding: Padding = {
  left: '16px',
  right: '16px',
  top: '16px',
  bottom: '16px'
}


export const ContainerWideSpacing: number = 16;

export const ContainerWideCfg: RowOptions | ColumnOptions = { space: `${ContainerWideSpacing}px` };

export const ContainerWidePadding: Padding = {
  left: `${ContainerWideSpacing}px`,
  right: `${ContainerWideSpacing}px`,
  top: `${ContainerWideSpacing}px`,
  bottom: `${ContainerWideSpacing}px`
}

export const TopLeft: AlignRuleOption = {
  top: { anchor: '__container__', align: VerticalAlign.Top },
  left: { anchor: '__container__', align: HorizontalAlign.Start },
};

export const TopRight: AlignRuleOption = {
  top: { anchor: '__container__', align: VerticalAlign.Top },
  right: { anchor: '__container__', align: HorizontalAlign.End }
}

export const FullRect: AlignRuleOption = {
  'top': { 'anchor': '__container__', 'align': VerticalAlign.Top },
  'bottom': { 'anchor': '__container__', 'align': VerticalAlign.Bottom },
  'left': { 'anchor': '__container__', 'align': HorizontalAlign.Start },
  'right': { 'anchor': '__container__', 'align': HorizontalAlign.End },
}

export function toVisibility(value: boolean): Visibility {
  return value ? Visibility.Visible : Visibility.None;
}

export function getCheckIcon(checked: boolean): SymbolGlyphModifier {
  if (checked) {
    return boxChecked;
  }
  return boxUnchecked;
}

export function getCheckIconName(checked: boolean): string {
  if (checked) {
    return 'sys.symbol.checkmark_square_fill';
  }
  return 'sys.symbol.square';
}

export function toResultCode(parseResult: pdfService.ParseResult): string {
  switch (parseResult) {
    case pdfService.ParseResult.PARSE_SUCCESS:
      return '成功';
    case pdfService.ParseResult.PARSE_ERROR_FILE:
      return '文件错误';
    case pdfService.ParseResult.PARSE_ERROR_FORMAT:
      return '格式错误';
    case pdfService.ParseResult.PARSE_ERROR_PASSWORD:
      return '暂不支持加密的 PDF 文件';
    case pdfService.ParseResult.PARSE_ERROR_HANDLER:
      return '处理程序错误';
    case pdfService.ParseResult.PARSE_ERROR_CERT:
      return '证书错误';
    default:
      return '未知错误';
  }
}

export function showAlertDialog(title: string, message: string, uiContext: UIContext): Promise<void> {
  return new Promise<void>((resolve) => {
    uiContext.showAlertDialog({
    title: title,
    message: message,
    confirm: {
      defaultFocus: true,
      action: () => resolve(),
      value: $r('sys.string.general_confirm')
    }
  });
});
}

@ComponentV2
export struct StyleText {
  @Param text: string = '';

  build() {
    Text(this.text)
      .height(ButtonHeight)
      .constraintSize({ minWidth: 80 })
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
      .maxLines(1)
      .alignSelf(ItemAlign.End)
  }
}

@ComponentV2
export struct StyleButton {
  @Param text: string = '';
  @Param style: 'normal' | 'wide' | Length = 'normal';
  @Param symbol: string | undefined = undefined;
  @Param menuElement: MenuElement[] | undefined = undefined;
  @Param onClickCallback: () => void = () => {
  };
  @Param alternateColor: ResourceColor | undefined = undefined;
  @Param menuPlacement: Placement = Placement.Bottom;

  build() {
    Button() {
      Text() {
        Span(this.text).fontColor(Color.White)
        SymbolSpan(this.symbol == undefined ? undefined : $r(this.symbol)).fontColor([Color.White])
      }
      .fontSize(ButtonFontSize)
      .fontWeight(FontWeight.Bold)
    }
    .fontSize(ButtonFontSize)
    .fontWeight(FontWeight.Bold)
    .size(this.style == 'normal' ? ButtonSize : this.style == 'wide' ? ButtonSizeWide : { width: this.style, height: ButtonHeight })
    .hitTestBehavior(HitTestMode.Block)
    .monopolizeEvents(true)
    .backgroundColor(this.alternateColor != undefined ? this.alternateColor : ButtonColor)
    .bindMenu(this.menuElement == undefined ? [] : this.menuElement, {
      backgroundColor: ButtonColor,
      outlineColor: Color.Transparent,
      placement: this.menuPlacement
    })
    .onClick(() => this.onClickCallback())
  }
}

const IconButtonSize: number = 44;
const IconFontSize: number = 20;

@ComponentV2
export struct StyleIconButton {
  @Param icon: Resource = $r('sys.symbol.more');
  @Param iconSize: number = IconFontSize;
  @Param label: string = '';
  @Param onClickCallback: () => void = () => {
  };
  @Param alternateColor: ResourceColor | undefined = undefined;
  @Param backgroundAnimationDurationMs: number = 0;
  @Param menuElement: MenuElement[] | undefined = undefined;
  @Param menuPlacement: Placement = Placement.Bottom;

  @Builder
  iconButton() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(this.icon)
        .fontSize(this.iconSize)
        .fontColor([Color.White])
        .fontWeight(FontWeight.Bold)
    }
    .width(IconButtonSize)
    .height(IconButtonSize)
    .hitTestBehavior(HitTestMode.Block)
    .monopolizeEvents(true)
    .backgroundColor(this.alternateColor != undefined ? this.alternateColor : ButtonColor)
    .animation({ duration: this.backgroundAnimationDurationMs, curve: Curve.EaseOut })
    .bindMenu(this.menuElement == undefined ? [] : this.menuElement, {
      backgroundColor: ButtonColor,
      outlineColor: Color.Transparent,
      placement: this.menuPlacement
    })
    .onClick(() => this.onClickCallback())
  }

  build() {
    if (this.label != '') {
      Row({ space: 8 }) {
        this.iconButton()
        Text(this.label)
          .fontSize(13)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
          .textShadow({
            type: ShadowType.BLUR,
            radius: 3,
            offsetX: 0,
            offsetY: 1
          })
      }
      .alignItems(VerticalAlign.Center)
    } else {
      this.iconButton()
    }
  }
}

@ComponentV2
export struct StyleIconBadgeButton {
  @Param icon: Resource = $r('sys.symbol.more');
  @Param iconSize: number = IconFontSize;
  @Param count: number = 0;
  @Param maxCount: number = 99;
  @Param onClickCallback: () => void = () => {
  };

  build() {
    Badge({
      count: this.count,
      maxCount: this.maxCount,
      position: BadgePosition.RightTop,
      style: StyleBadgeStyle
    }) {
      StyleIconButton({
        icon: this.icon,
        iconSize: this.iconSize,
        onClickCallback: this.onClickCallback
      })
    }
    .width(IconButtonSize)
    .height(IconButtonSize)
  }
}

export const StyleBadgeStyle: BadgeStyle = {
  badgeColor: BaseColor,
  borderColor: Color.Transparent,
  fontSize: HalfButtonFontSize,
  fontWeight: FontWeight.Bold,
};

@ComponentV2
export struct StyleNumBadgeButton {
  @Param text: string = '';
  @Param count: number = 0;
  @Param maxCount: number = 99;
  @Param badgePosition: BadgePosition = BadgePosition.RightTop;
  @Param style: 'normal' | 'wide' = 'normal';
  @Param onClickCallback: () => void = () => {
  };
  @Param symbol: string | undefined = undefined;
  @Param menuElement: MenuElement[] | undefined = undefined;

  build() {
    Badge({
      count: this.count,
      maxCount: this.maxCount,
      position: this.badgePosition,
      style: StyleBadgeStyle
    }) {
      StyleButton({
        text: this.text,
        style: this.style,
        symbol: this.symbol,
        menuElement: this.menuElement,
        onClickCallback: this.onClickCallback
      })
    }
    .size(this.style == 'normal' ? ButtonSize : ButtonSizeWide)
  }
}

@ComponentV2
export struct StyleStrBadgeButton {
  @Param text: string = '';
  @Param badgeText: string = '';
  @Param badgeVisibility: boolean = true;
  @Param badgePosition: BadgePosition = BadgePosition.RightTop;
  @Param style: 'normal' | 'wide' = 'normal';
  @Param onClickCallback: () => void = () => {
  };
  @Param symbol: string | undefined = undefined;
  @Param menuElement: MenuElement[] | undefined = undefined;

  build() {
    Badge({
      value: this.badgeText,
      position: this.badgePosition,
      style: {
        badgeColor: StyleBadgeStyle.badgeColor,
        borderColor: StyleBadgeStyle.borderColor,
        fontSize: StyleBadgeStyle.fontSize,
        fontWeight: StyleBadgeStyle.fontWeight,
        badgeSize: this.badgeVisibility ? null : 0
      }
    }) {
      StyleButton({
        text: this.text,
        style: this.style,
        symbol: this.symbol,
        menuElement: this.menuElement,
        onClickCallback: this.onClickCallback
      })
    }
    .size(this.style == 'normal' ? ButtonSize : ButtonSizeWide)
  }
}

@ComponentV2
export struct MakeSlider {
  @Param value: number = 0;
  @Param min: number = 0;
  @Param max: number = 100;
  @Param onChangeCallback: (value: number) => void = () => {
  };

  build() {
    Slider({
      value: this.value,
      min: this.min,
      max: this.max,
      style: SliderStyle.InSet,
      direction: Axis.Vertical,
      reverse: true
    })
      .monopolizeEvents(true)
      .showSteps(true)
      .showTips(true)
      .trackThickness(ScrollBarWidth)
      .height('50%')
      .alignSelf(ItemAlign.End)
      .trackColor(TrackColor)
      .selectedColor(TrackColor)
      .onChange((value, _) => this.onChangeCallback(value))
  }
}