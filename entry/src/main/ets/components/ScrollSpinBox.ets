@Component
export struct ScrollSpinBox {
  @Prop value: number = 0;
  @Prop itemHeight: number | undefined = 0;
  @Prop gradientHeight: Dimension | undefined = 0;
  @Prop values: number[] = [];
  @Prop labels: string[] = [];
  canLoop: boolean = false;
  min: number = 0;
  max: number = 100;
  step: number = 1;
  valueFontSize: number = 24;
  debounceMs: number = 160;
  onValueChange: (value: number) => void = () => {};
  onInteractionStart: () => void = () => {};
  onInteractionEnd: () => void = () => {};
  onLongPress: () => void = () => {};
  private isInteracting: boolean = false;
  private isTouching: boolean = false;
  private pendingValue: number | undefined = undefined;
  private isScrollSettled: boolean = true;

  private getPickerRange(): string[] {
    if (this.values.length > 0) {
      if (this.labels.length === this.values.length) {
        return this.labels;
      }
      return this.values.map((item: number) => `${item}`);
    }

    const range: string[] = [];
    const safeStep = this.step > 0 ? this.step : 1;
    for (let current = this.min; current <= this.max; current += safeStep) {
      range.push(`${current}`);
    }
    return range;
  }

  private getSelectedIndex(): number {
    if (this.values.length > 0) {
      const idx = this.values.indexOf(this.value);
      return idx >= 0 ? idx : 0;
    }

    const safeStep = this.step > 0 ? this.step : 1;
    const rawIndex = Math.round((this.value - this.min) / safeStep);
    const maxIndex = Math.max(0, Math.floor((this.max - this.min) / safeStep));
    return Math.max(0, Math.min(maxIndex, rawIndex));
  }

  private getValueFromIndex(index: number): number {
    if (this.values.length > 0) {
      return this.values[index] ?? this.value;
    }

    const safeStep = this.step > 0 ? this.step : 1;
    const nextValue = this.min + index * safeStep;
    return Math.max(this.min, Math.min(this.max, nextValue));
  }

  private ensureInteractionStarted(): void {
    if (this.isInteracting) {
      return;
    }

    this.isInteracting = true;
    this.isScrollSettled = true;
    this.pendingValue = undefined;
    this.onInteractionStart();
  }

  private flushPendingValueAndMaybeEndInteraction(): void {
    if (!this.isInteracting || this.isTouching) {
      return;
    }

    if (!this.isScrollSettled && this.pendingValue !== undefined) {
      return;
    }

    if (this.pendingValue !== undefined) {
      const nextValue = this.pendingValue;
      this.pendingValue = undefined;
      this.onValueChange(nextValue);
    }

    if (!this.isTouching && this.isInteracting) {
      this.isInteracting = false;
      this.onInteractionEnd();
    }
  }

  private updatePendingValue(nextValue: number): void {
    this.pendingValue = nextValue;
  }

  build() {
    TextPicker({
      range: this.getPickerRange(),
      selected: this.getSelectedIndex()
    })
      .canLoop(this.canLoop)
      .gradientHeight(this.gradientHeight)
      .defaultPickerItemHeight(this.itemHeight)
      .divider(null)
      .selectedTextStyle({
        color: Color.White,
        font: {
          size: this.valueFontSize,
          weight: FontWeight.Bold
        }
      })
      .textStyle({
        color: 'rgba(255, 255, 255, 0.45)',
        font: {
          size: Math.max(14, Math.round(this.valueFontSize * 0.6)),
          weight: FontWeight.Medium
        }
      })
      .disappearTextStyle({
        color: 'rgba(255, 255, 255, 0.24)',
        font: {
          size: Math.max(12, Math.round(this.valueFontSize * 0.45)),
          weight: FontWeight.Regular
        }
      })
      .onChange((_value: string | string[], index: number | number[]) => {
        if (typeof index !== 'number') {
          return;
        }
        this.ensureInteractionStarted();
        this.isScrollSettled = false;
        this.updatePendingValue(this.getValueFromIndex(index));
      })
      .onScrollStop((_value: string | string[], index: number | number[]) => {
        if (typeof index === 'number') {
          this.updatePendingValue(this.getValueFromIndex(index));
        }
        this.isScrollSettled = true;
        this.flushPendingValueAndMaybeEndInteraction();
      })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.isTouching = true;
          this.ensureInteractionStarted();
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.isTouching = false;
          this.flushPendingValueAndMaybeEndInteraction();
        }
      })
      .priorityGesture(LongPressGesture({ repeat: false })
        .onAction(() => {
          this.onLongPress();
        }))
      .width('100%')
      .height('100%')
  }
}
