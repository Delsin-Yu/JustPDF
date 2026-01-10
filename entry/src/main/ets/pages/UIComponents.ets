import { SymbolGlyphModifier } from "@kit.ArkUI";

const HalfButtonFontSize: Length = '10vp';
const ButtonFontSize: Length = '20vp';
const ButtonSize: SizeOptions = { height: 40, width: 80 };
const ButtonSizeWide: SizeOptions = { height: 40, width: 90 };
export const ButtonColor: ResourceColor = `rgba(50, 50, 50, 0.7)`;
const ButtonColorHighlight: ResourceColor = 'rgba(160, 160, 160, 0.9)';
export const ButtonColorSemiTransparent: ResourceColor = 'rgba(50, 50, 50, 0.2)';
const BaseColor: ResourceColor = `rgba(50, 50, 50, 1)`;
const TrackColor: ResourceColor = 'rgba(50, 50, 50, 0.4)';
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

@ComponentV2
export struct StyleText {
  @Param text: string = '';

  build() {
    Text(this.text)
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
  }
}

@ComponentV2
export struct StyleToggle {
  @Param text: string = '';
  @Param style: 'normal' | 'wide' = 'normal';
  @Param onChangeCallback: (checked: boolean) => void = () => {
  };

  build() {
    Toggle({ type: ToggleType.Button }) {
      Text(this.text)
        .fontSize(ButtonFontSize)
        .fontWeight(FontWeight.Bold)
    }
    .size(this.style == 'normal' ? ButtonSize : ButtonSizeWide)
    .hitTestBehavior(HitTestMode.Block)
    .monopolizeEvents(true)
    .backgroundColor(ButtonColor)
    .selectedColor(ButtonColorHighlight)
    .onChange(value => this.onChangeCallback(value))
  }
}

@ComponentV2
export struct StyleButton {

  @Param text: string = '';
  @Param style: 'normal' | 'wide' = 'normal';
  @Param symbol: string | undefined = undefined;
  @Param menuElement: MenuElement[] | undefined = undefined;
  @Param onClickCallback: () => void = () => {
  };
  @Param alternateColor: ResourceColor | undefined = undefined;
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
    .size(this.style == 'normal' ? ButtonSize : ButtonSizeWide)
    .hitTestBehavior(HitTestMode.Block)
    .monopolizeEvents(true)
    .backgroundColor(this.alternateColor != undefined ? this.alternateColor : ButtonColor)
    .bindMenu(this.menuElement == undefined ? [] : this.menuElement, {
      backgroundColor: ButtonColor,
      outlineColor: Color.Transparent
    })
    .onClick(() => this.onClickCallback())
  }
}

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
      style: {
        badgeColor: BaseColor,
        borderColor: Color.Transparent,
        fontSize: HalfButtonFontSize
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
        badgeColor: BaseColor,
        borderColor: Color.Transparent,
        fontSize: HalfButtonFontSize,
        fontWeight: FontWeight.Bold,
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
      .selectedColor(ButtonColor)
      .onChange((value, _) => this.onChangeCallback(value))
  }
}