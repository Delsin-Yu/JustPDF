import { ContainerSpacing, getCheckIcon } from '../../common/ui/UIComponents';
import { mul, pxToVp, Vec2, Vector2 } from '../../common/ui/Numbers';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { preferences } from '@kit.ArkData';

/** 阅读档 / 高清档；阅读档下限 6 以保留密谱细线 */
export const ViewerRenderScaleLevels: number[] = [6, 8];
export const ViewerMinRenderScale: number = 6;
const ViewerScaleThresholds: number[] = [2.0];

export type PDFPageDisplayMode =
  'single' | 'dual' | 'dualContinuous' | 'tri' | 'triContinuous' | 'halfVertical' | 'halfHorizontal';
export type PDFPageFlipMode = 'side' | 'button' | 'extern' | 'horizontalSlide';
export type PDFLinkVisualMode = 'hidden' | 'fadeOnPageEnter' | 'always';

/** 半页模式一次下一页/上一页的落点（整数页 + 是否露出下一页前一半） */
export class HalfPageNavStep {
  pageIndex: number;
  previewActive: boolean;
  needsGoto: boolean;

  constructor(pageIndex: number, previewActive: boolean, needsGoto: boolean) {
    this.pageIndex = pageIndex;
    this.previewActive = previewActive;
    this.needsGoto = needsGoto;
  }
}

function parsePageDisplayMode(raw: string): PDFPageDisplayMode {
  if (raw === 'single' || raw === 'dual' || raw === 'dualContinuous' || raw === 'tri' ||
    raw === 'triContinuous' || raw === 'halfVertical' || raw === 'halfHorizontal') {
    return raw;
  }
  return 'single';
}

/** 与 clampViewPan 一致的视口与内容边界（单位 vp，与 viewPan 一致） */
export interface PanClampBounds {
  minX: number;
  maxX: number;
  minY: number;
  maxY: number;
  relaxX: number;
  relaxY: number;
  scaledViewSizeVp: Vector2;
  viewportSizeVp: Vector2;
}
export type PDFAnnotateMode = 'drag' | 'draw' | 'erase';

// 批注浮窗记住的「绘制 / 擦除」工具（不含 drag）。
export type PalettePersistedTool = 'draw' | 'erase';

const PaletteToolModePreferenceKey: string = 'paletteToolMode';
const HorizontalSlideSensitivityPreferenceKey: string = 'horizontalSlideSensitivity';
const LinkVisualModePreferenceKey: string = 'linkVisualMode';
/** 贴合视口时的溢出容差（vp）。略大于 0 即可吸收 px/vp/scale 浮点误差，避免误开 25% 松弛平移 */
const PAN_FIT_OVERFLOW_EPSILON_VP: number = 3;

@ObservedV2
export class PDFViewerViewModel {
  private preferences?: preferences.Preferences;
  private readonly minScale: number;
  private readonly maxScale: number;

  @Trace public currentPageIndex: number = 0;
  @Trace public totalPageCount: number = 0;
  @Trace public pageDisplayMode: PDFPageDisplayMode = 'single';
  @Trace public pageFlipMode: PDFPageFlipMode = 'horizontalSlide';
  @Trace public annotateMode: PDFAnnotateMode = 'drag';
  @Trace public paletteToolMode: PalettePersistedTool = 'draw';
  @Trace public viewPan: Vector2 = Vec2(0, 0);
  @Trace public viewScale: number = 1.0;
  @Trace public viewportSize: Vector2 = Vec2(0, 0);
  @Trace public viewSize: Vector2 = Vec2(0, 0);
  @Trace public showControls: boolean = true;
  @Trace public showSlider: boolean = true;
  /** 水平滑动翻页灵敏度档位 0～10（设置滑块），5 为默认手感 */
  @Trace public horizontalSlideSensitivity: number = 5;
  @Trace public linkVisualMode: PDFLinkVisualMode = 'fadeOnPageEnter';
  @Trace public controlsTransparency: number = 0.5;
  @Trace public displayedPageIndices: number[] = [];
  /** 半页模式：true 表示当前整页 A 上叠着 A+1 的前一半（页码为 A.5） */
  @Trace public halfPagePreviewActive: boolean = false;
  @Trace public isAnnotatePaletteVisible: boolean = false;
  @Trace public isAnnotationLayerPanelVisible: boolean = false;
  @Trace public isBookmarkPanelVisible: boolean = false;
  private savedPageFlipMode: PDFPageFlipMode = 'horizontalSlide';
  public onPageFlipModeChanged: ((mode: PDFPageFlipMode) => void) | undefined = undefined;
  public onPageDisplayModeChanged: ((mode: PDFPageDisplayMode) => void) | undefined = undefined;
  /**
   * 水平滑动已提交、目标页尚未完成 load 时，作为 peek / navigate 的「逻辑当前首页」，
   * 避免连滑第二次仍从旧 currentPageIndex 计算到同一套。
   */
  private slideNavEffectiveStartIndex: number | undefined = undefined;

  constructor(minScale: number = 0.5, maxScale: number = 9.0) {
    this.minScale = minScale;
    this.maxScale = maxScale;
  }

  loadPreferences(preferencesValue: preferences.Preferences): void {
    this.preferences = preferencesValue;
    try {
      this.showControls = preferencesValue.getSync('showControls', true) as boolean;
      this.showSlider = preferencesValue.getSync('showSlider', true) as boolean;
      const rawSens: preferences.ValueType = preferencesValue.getSync(HorizontalSlideSensitivityPreferenceKey, 5);
      if (typeof rawSens === 'number') {
        this.horizontalSlideSensitivity = Math.max(0, Math.min(10, Math.round(rawSens)));
      } else {
        this.horizontalSlideSensitivity = 5;
      }
      const linkVisualRaw: string = preferencesValue.getSync(LinkVisualModePreferenceKey, 'fadeOnPageEnter') as string;
      if (linkVisualRaw === 'hidden' || linkVisualRaw === 'fadeOnPageEnter' || linkVisualRaw === 'always') {
        this.linkVisualMode = linkVisualRaw as PDFLinkVisualMode;
      } else {
        this.linkVisualMode = 'fadeOnPageEnter';
      }
      const displayRaw: string = preferencesValue.getSync('pageDisplayMode', 'single') as string;
      this.pageDisplayMode = parsePageDisplayMode(displayRaw);
      this.halfPagePreviewActive = false;
      const flipRaw: string = preferencesValue.getSync('pageFlipMode', 'horizontalSlide') as string;
      if (flipRaw === 'side' || flipRaw === 'button' || flipRaw === 'extern' || flipRaw === 'horizontalSlide') {
        this.pageFlipMode = flipRaw as PDFPageFlipMode;
      } else {
        this.pageFlipMode = 'horizontalSlide';
      }
      this.annotateMode = 'drag';
      let tool: PalettePersistedTool = 'draw';
      if (preferencesValue.hasSync(PaletteToolModePreferenceKey)) {
        const v: string = preferencesValue.getSync(PaletteToolModePreferenceKey, 'draw') as string;
        if (v === 'draw' || v === 'erase') {
          tool = v;
        }
      } else {
        // 迁移：旧版曾把 annotateMode 写入偏好，关闭浮窗后多为 'drag'；若仍为 draw/erase 则沿用。
        const legacy: string = preferencesValue.getSync('annotateMode', 'drag') as string;
        if (legacy === 'draw' || legacy === 'erase') {
          tool = legacy;
          preferencesValue.putSync(PaletteToolModePreferenceKey, legacy);
          preferencesValue.flushSync();
        }
      }
      this.paletteToolMode = tool;
    } catch (error) {
      hilog.error(0, 'PDFViewerViewModel', `加载阅读器偏好出错: ${error}.`);
    }
  }

  setTotalPageCount(totalPageCount: number): void {
    this.totalPageCount = Math.max(0, totalPageCount);
    if (this.totalPageCount === 0) {
      this.currentPageIndex = 0;
      this.displayedPageIndices = [];
      this.halfPagePreviewActive = false;
      return;
    }
    this.commitPageTarget(Math.min(this.currentPageIndex, this.totalPageCount - 1));
  }

  getPageDisplayModeText(): string {
    switch (this.pageDisplayMode) {
      case 'single':
        return '单页';
      case 'dual':
        return '双页';
      case 'dualContinuous':
        return '双页连续';
      case 'tri':
        return '三页';
      case 'triContinuous':
        return '三页连续';
      case 'halfVertical':
        return '半页(纵向)';
      case 'halfHorizontal':
        return '半页(横向)';
      default:
        return '单页';
    }
  }

  isHalfPageMode(): boolean {
    return this.pageDisplayMode === 'halfVertical' || this.pageDisplayMode === 'halfHorizontal';
  }

  setHalfPagePreviewActive(active: boolean): void {
    if (!this.isHalfPageMode()) {
      this.halfPagePreviewActive = false;
      return;
    }
    this.halfPagePreviewActive = active;
  }

  canHalfPageStepNext(): boolean {
    if (!this.isHalfPageMode() || this.totalPageCount <= 0) {
      return false;
    }
    return this.getSlideNavBaseIndex() < this.getLastNavigableIndex();
  }

  canHalfPageStepPrev(): boolean {
    if (!this.isHalfPageMode() || this.totalPageCount <= 0) {
      return false;
    }
    if (this.halfPagePreviewActive) {
      return true;
    }
    return this.getSlideNavBaseIndex() > 0;
  }

  stepHalfPageNext(): HalfPageNavStep {
    const base: number = this.getSlideNavBaseIndex();
    const last: number = this.getLastNavigableIndex();
    if (!this.isHalfPageMode() || this.totalPageCount <= 0) {
      return new HalfPageNavStep(this.currentPageIndex, false, false);
    }
    if (this.halfPagePreviewActive) {
      const nextIndex: number = Math.min(base + 1, last);
      if (nextIndex === base) {
        return new HalfPageNavStep(base, true, false);
      }
      return new HalfPageNavStep(nextIndex, false, true);
    }
    if (base >= last) {
      return new HalfPageNavStep(base, false, false);
    }
    return new HalfPageNavStep(base, true, false);
  }

  stepHalfPagePrev(): HalfPageNavStep {
    const base: number = this.getSlideNavBaseIndex();
    if (!this.isHalfPageMode() || this.totalPageCount <= 0) {
      return new HalfPageNavStep(this.currentPageIndex, false, false);
    }
    if (this.halfPagePreviewActive) {
      return new HalfPageNavStep(base, false, false);
    }
    if (base <= 0) {
      return new HalfPageNavStep(0, false, false);
    }
    return new HalfPageNavStep(base - 1, true, true);
  }

  getPageFlipModeText(): string {
    switch (this.pageFlipMode) {
      case 'side':
        return '屏侧翻页';
      case 'button':
        return '按钮翻页';
      case 'extern':
        return '外设翻页';
      case 'horizontalSlide':
        return '水平滑动';
    }
  }

  getExpectedSlotCount(): number {
    if (this.pageDisplayMode === 'dual' || this.pageDisplayMode === 'dualContinuous') {
      return 2;
    }
    if (this.pageDisplayMode === 'tri' || this.pageDisplayMode === 'triContinuous') {
      return 3;
    }
    return 1;
  }

  shouldShowSecondSlot(): boolean {
    return this.getExpectedSlotCount() >= 2;
  }

  shouldShowThirdSlot(): boolean {
    return this.getExpectedSlotCount() >= 3;
  }

  getLastNavigableIndex(): number {
    if (this.pageDisplayMode === 'dualContinuous') {
      return Math.max(0, this.totalPageCount - 2);
    }
    if (this.pageDisplayMode === 'triContinuous') {
      return Math.max(0, this.totalPageCount - 3);
    }
    return Math.max(0, this.totalPageCount - 1);
  }

  /** 水平滑动提交瞬间设置，goto 完成或普通导航时清除 */
  setSlideNavEffectiveStartIndex(index: number): void {
    this.slideNavEffectiveStartIndex = index;
  }

  clearSlideNavEffectiveStartIndex(): void {
    this.slideNavEffectiveStartIndex = undefined;
  }

  private getSlideNavBaseIndex(): number {
    return this.slideNavEffectiveStartIndex !== undefined
      ? this.slideNavEffectiveStartIndex
      : this.currentPageIndex;
  }

  commitPageTarget(targetIndex: number): number[] {
    if (this.totalPageCount <= 0) {
      this.currentPageIndex = 0;
      this.displayedPageIndices = [];
      return this.displayedPageIndices;
    }
    const clampedTarget = Math.max(0, Math.min(targetIndex, this.totalPageCount - 1));
    this.currentPageIndex = clampedTarget;
    this.displayedPageIndices = this.calculateDisplayIndices(clampedTarget);
    return this.displayedPageIndices;
  }

  /** 在未 commit 前解析某「首页」索引对应的各槽页面索引（与 commitPageTarget 后一致），供先 load 再提交导航 */
  getDisplayedIndicesForTargetPage(targetPageIndex: number): number[] {
    if (this.totalPageCount <= 0) {
      return [];
    }
    const c = Math.max(0, Math.min(targetPageIndex, this.totalPageCount - 1));
    return this.calculateDisplayIndices(c);
  }

  navigateToPreviousPage(): number {
    const base = this.getSlideNavBaseIndex();
    if (this.pageDisplayMode === 'single' || this.pageDisplayMode === 'dualContinuous' ||
      this.pageDisplayMode === 'triContinuous' || this.isHalfPageMode()) {
      return base - 1;
    }
    if (this.pageDisplayMode === 'dual') {
      const currentPair = Math.floor(base / 2);
      return Math.max(0, (currentPair - 1) * 2);
    }
    const currentGroup = Math.floor(base / 3);
    return Math.max(0, (currentGroup - 1) * 3);
  }

  navigateToNextPage(): number {
    const base = this.getSlideNavBaseIndex();
    if (this.pageDisplayMode === 'single' || this.pageDisplayMode === 'dualContinuous' ||
      this.pageDisplayMode === 'triContinuous' || this.isHalfPageMode()) {
      return Math.min(base + 1, this.getLastNavigableIndex());
    }
    if (this.pageDisplayMode === 'dual') {
      const currentPair = Math.floor(base / 2);
      return (currentPair + 1) * 2;
    }
    const currentGroup = Math.floor(base / 3);
    return (currentGroup + 1) * 3;
  }

  setPageDisplayMode(value: PDFPageDisplayMode): void {
    if (this.pageDisplayMode !== value) {
      this.halfPagePreviewActive = false;
    }
    this.pageDisplayMode = value;
    this.persistPreference('pageDisplayMode', value, '保存页面显示模式出错');
    this.onPageDisplayModeChanged?.(value);
  }

  setPageFlipMode(value: PDFPageFlipMode): void {
    this.pageFlipMode = value;
    this.persistPreference('pageFlipMode', value, '保存翻页模式出错');
    this.onPageFlipModeChanged?.(value);
  }

  setAnnotateMode(value: PDFAnnotateMode): void {
    this.annotateMode = value;
    if (value === 'draw' || value === 'erase') {
      this.paletteToolMode = value;
      this.persistPreference(PaletteToolModePreferenceKey, value, '保存批注工具模式出错');
    }
  }

  openAnnotatePalette(explicitTool?: PDFAnnotateMode): void {
    const resolvedTool: PDFAnnotateMode =
      explicitTool !== undefined && explicitTool !== 'drag'
        ? explicitTool
        : this.paletteToolMode;
    if (this.isAnnotatePaletteVisible) {
      this.setAnnotateMode(resolvedTool);
      return;
    }
    this.savedPageFlipMode = this.pageFlipMode;
    this.setAnnotateMode(resolvedTool);
    this.isAnnotatePaletteVisible = true;
    if (this.pageFlipMode === 'side' || this.pageFlipMode === 'horizontalSlide') {
      this.setPageFlipMode('button');
    }
  }

  toggleAnnotationLayerPanel(): void {
    this.isAnnotationLayerPanelVisible = !this.isAnnotationLayerPanelVisible;
  }

  closeAnnotationLayerPanel(): void {
    this.isAnnotationLayerPanelVisible = false;
  }

  closeAnnotatePalette(): void {
    if (!this.isAnnotatePaletteVisible) {
      return;
    }
    this.isAnnotatePaletteVisible = false;
    this.isAnnotationLayerPanelVisible = false;
    this.setAnnotateMode('drag');
    if (this.pageFlipMode !== this.savedPageFlipMode) {
      this.setPageFlipMode(this.savedPageFlipMode);
    }
  }

  toggleBookmarkPanel(): void {
    this.isBookmarkPanelVisible = !this.isBookmarkPanelVisible;
  }

  openBookmarkPanel(): void {
    this.isBookmarkPanelVisible = true;
  }

  closeBookmarkPanel(): void {
    this.isBookmarkPanelVisible = false;
  }

  setShowControls(value: boolean): void {
    this.showControls = value;
    this.persistPreference('showControls', value, '保存显示控件出错');
  }

  setShowSlider(value: boolean): void {
    this.showSlider = value;
    this.persistPreference('showSlider', value, '保存滑块偏好出错');
  }

  setHorizontalSlideSensitivity(level: number): void {
    const clamped = Math.max(0, Math.min(10, Math.round(level)));
    if (clamped === this.horizontalSlideSensitivity) {
      return;
    }
    this.horizontalSlideSensitivity = clamped;
    this.persistPreference(HorizontalSlideSensitivityPreferenceKey, clamped, '保存水平滑动灵敏度出错');
  }

  setLinkVisualMode(mode: PDFLinkVisualMode): void {
    if (mode === this.linkVisualMode) {
      return;
    }
    this.linkVisualMode = mode;
    this.persistPreference(LinkVisualModePreferenceKey, mode, '保存 PDF 链接显示模式出错');
  }

  updateViewSize(view1Size: Vector2, view2Size: Vector2, view3Size: Vector2): void {
    let next: Vector2 = view1Size;
    if (this.getExpectedSlotCount() === 1) {
      next = view1Size;
    } else if (this.getExpectedSlotCount() === 2) {
      next = Vec2(
        view1Size.x + ContainerSpacing + view2Size.x,
        Math.max(view1Size.y, view2Size.y)
      );
    } else {
      next = Vec2(
        view1Size.x + ContainerSpacing + view2Size.x + ContainerSpacing + view3Size.x,
        Math.max(view1Size.y, view2Size.y, view3Size.y)
      );
    }
    // 连滑期间 animateTo 仍在跑时，重复写入相同 viewSize 也会被隐式插值，看起来像整页被缩小
    if (this.viewSize.x === next.x && this.viewSize.y === next.y) {
      return;
    }
    this.viewSize = next;
  }

  setViewportSize(viewportSize: Vector2): void {
    this.viewportSize = viewportSize;
  }

  resetViewToFit(uiContext: UIContext): void {
    this.viewScale = this.calculateFitScale(uiContext);
    this.viewPan = Vec2(0, 0);
    this.clampViewPan(uiContext);
  }

  calculateFitScale(uiContext: UIContext): number {
    const viewSizeVp = pxToVp(this.viewSize, uiContext);
    const viewportSizeVp = pxToVp(this.viewportSize, uiContext);
    if (viewSizeVp.x <= 0 || viewSizeVp.y <= 0 || viewportSizeVp.x <= 0 || viewportSizeVp.y <= 0) {
      return 1.0;
    }
    const scaleX = viewportSizeVp.x / viewSizeVp.x;
    const scaleY = viewportSizeVp.y / viewSizeVp.y;
    return Math.max(this.minScale, Math.min(this.maxScale, Math.min(scaleX, scaleY)));
  }

  /** 与 clampViewPan 使用同一套公式，供水平滑动翻页判断左右边界 */
  getPanClampBounds(uiContext: UIContext): PanClampBounds {
    const viewSizeVp = pxToVp(this.viewSize, uiContext);
    const viewportSizeVp = pxToVp(this.viewportSize, uiContext);
    const scaledViewSizeVp = mul(viewSizeVp, this.viewScale);
    const boundaryRelaxation = 0.25;
    const relaxX = viewportSizeVp.x * boundaryRelaxation;
    const relaxY = viewportSizeVp.y * boundaryRelaxation;

    let minX: number;
    let maxX: number;
    const overflowX = scaledViewSizeVp.x - viewportSizeVp.x;
    if (overflowX <= PAN_FIT_OVERFLOW_EPSILON_VP) {
      const centered = (viewportSizeVp.x - scaledViewSizeVp.x) / 2;
      minX = centered;
      maxX = centered;
    } else {
      minX = -overflowX - relaxX;
      maxX = relaxX;
    }

    let minY: number;
    let maxY: number;
    const overflowY = scaledViewSizeVp.y - viewportSizeVp.y;
    if (overflowY <= PAN_FIT_OVERFLOW_EPSILON_VP) {
      const centeredY = (viewportSizeVp.y - scaledViewSizeVp.y) / 2;
      minY = centeredY;
      maxY = centeredY;
    } else {
      minY = -overflowY - relaxY;
      maxY = relaxY;
    }

    return {
      minX,
      maxX,
      minY,
      maxY,
      relaxX,
      relaxY,
      scaledViewSizeVp,
      viewportSizeVp
    };
  }

  /** 横向可滚动且已贴右端（可向左拖出下一页预览） */
  isAtHorizontalScrollRightEnd(uiContext: UIContext, epsilonVp: number = 2): boolean {
    const b = this.getPanClampBounds(uiContext);
    if (!this.canPanHorizontally(uiContext)) {
      return false;
    }
    return this.viewPan.x <= b.minX + b.relaxX * 0.35 + epsilonVp;
  }

  /** 横向可滚动且已贴左端（可向右拖出上一页预览） */
  isAtHorizontalScrollLeftEnd(uiContext: UIContext, epsilonVp: number = 2): boolean {
    const b = this.getPanClampBounds(uiContext);
    if (!this.canPanHorizontally(uiContext)) {
      return false;
    }
    return this.viewPan.x >= b.maxX - b.relaxX * 0.35 - epsilonVp;
  }

  /** 内容明显宽于视口时需横向平移才能看全（贴合误差不计入） */
  canPanHorizontally(uiContext: UIContext): boolean {
    const b = this.getPanClampBounds(uiContext);
    return b.maxX > b.minX + 0.5;
  }

  clampViewPan(uiContext: UIContext): void {
    const b = this.getPanClampBounds(uiContext);
    const clampedX = Math.max(b.minX, Math.min(b.maxX, this.viewPan.x));
    const clampedY = Math.max(b.minY, Math.min(b.maxY, this.viewPan.y));
    this.viewPan = Vec2(clampedX, clampedY);
  }

  panBy(delta: Vector2, uiContext: UIContext): void {
    this.viewPan = Vec2(this.viewPan.x + delta.x, this.viewPan.y + delta.y);
    this.clampViewPan(uiContext);
  }

  /** 使用 vp 增量平移（用于水平滑动翻页时与 pageTurnOffsetVp 单位一致） */
  panByDeltaVp(deltaVp: Vector2, uiContext: UIContext): void {
    this.viewPan = Vec2(this.viewPan.x + deltaVp.x, this.viewPan.y + deltaVp.y);
    this.clampViewPan(uiContext);
  }

  zoomAround(anchor: Vector2, scaleRatio: number, centerDelta: Vector2, uiContext: UIContext): void {
    const nextScale = Math.max(this.minScale, Math.min(this.maxScale, this.viewScale * scaleRatio));
    const actualScaleChange = nextScale / this.viewScale;
    const nextPanX = anchor.x - (anchor.x - this.viewPan.x) * actualScaleChange + centerDelta.x;
    const nextPanY = anchor.y - (anchor.y - this.viewPan.y) * actualScaleChange + centerDelta.y;
    this.viewScale = nextScale;
    this.viewPan = Vec2(nextPanX, nextPanY);
    this.clampViewPan(uiContext);
  }

  getRenderScaleForViewScale(): number {
    if (this.viewScale > ViewerScaleThresholds[0]) {
      return ViewerRenderScaleLevels[1];
    }
    return ViewerRenderScaleLevels[0];
  }

  buildPageDisplayModeMenu(onApply: () => void): MenuElement[] {
    return [
      {
        value: '单页',
        action: () => {
          this.setPageDisplayMode('single');
          onApply();
        },
        symbolIcon: getCheckIcon(this.pageDisplayMode == 'single')
      },
      {
        value: '双页',
        action: () => {
          this.setPageDisplayMode('dual');
          onApply();
        },
        symbolIcon: getCheckIcon(this.pageDisplayMode == 'dual')
      },
      {
        value: '双页连续',
        action: () => {
          this.setPageDisplayMode('dualContinuous');
          onApply();
        },
        symbolIcon: getCheckIcon(this.pageDisplayMode == 'dualContinuous')
      },
      {
        value: '三页',
        action: () => {
          this.setPageDisplayMode('tri');
          onApply();
        },
        symbolIcon: getCheckIcon(this.pageDisplayMode == 'tri')
      },
      {
        value: '三页连续',
        action: () => {
          this.setPageDisplayMode('triContinuous');
          onApply();
        },
        symbolIcon: getCheckIcon(this.pageDisplayMode == 'triContinuous')
      },
      {
        value: '半页(纵向)',
        action: () => {
          this.setPageDisplayMode('halfVertical');
          onApply();
        },
        symbolIcon: getCheckIcon(this.pageDisplayMode == 'halfVertical')
      },
      {
        value: '半页(横向)',
        action: () => {
          this.setPageDisplayMode('halfHorizontal');
          onApply();
        },
        symbolIcon: getCheckIcon(this.pageDisplayMode == 'halfHorizontal')
      }
    ];
  }

  buildPageFlipModeMenu(): MenuElement[] {
    return [
      {
        value: '水平滑动',
        action: () => this.setPageFlipMode('horizontalSlide'),
        symbolIcon: getCheckIcon(this.pageFlipMode == 'horizontalSlide')
      },
      {
        value: '屏侧翻页',
        action: () => this.setPageFlipMode('side'),
        symbolIcon: getCheckIcon(this.pageFlipMode == 'side')
      },
      {
        value: '按钮翻页',
        action: () => this.setPageFlipMode('button'),
        symbolIcon: getCheckIcon(this.pageFlipMode == 'button')
      },
      {
        value: '外设翻页',
        action: () => this.setPageFlipMode('extern'),
        symbolIcon: getCheckIcon(this.pageFlipMode == 'extern')
      }
    ];
  }

  buildJumpMenu(onResetViewport: () => void, onGotoPage: (pageIndex: number) => void): MenuElement[] {
    return [
      {
        value: '重置视口',
        action: () => onResetViewport()
      },
      {
        value: '跳转首页',
        action: () => onGotoPage(0)
      },
      {
        value: '跳转尾页',
        action: () => onGotoPage(this.getLastNavigableIndex())
      }
    ];
  }

  /** 水平滑动预览：下一页（跨页）索引；若无下一套则返回空数组 */
  peekNextSetIndices(): number[] {
    if (this.totalPageCount <= 0 || this.isHalfPageMode()) {
      return [];
    }
    const baseDisplayed: number[] = this.slideNavEffectiveStartIndex !== undefined
      ? this.calculateDisplayIndices(this.slideNavEffectiveStartIndex)
      : this.displayedPageIndices;
    const raw = this.navigateToNextPage();
    const t = Math.max(0, Math.min(raw, this.totalPageCount - 1));
    const nextSet = this.calculateDisplayIndices(t);
    if (PDFViewerViewModel.pageSetsEqual(nextSet, baseDisplayed)) {
      return [];
    }
    return nextSet;
  }

  /** 水平滑动预览：上一套页面索引；若无上一套则返回空数组 */
  peekPrevSetIndices(): number[] {
    if (this.totalPageCount <= 0 || this.isHalfPageMode()) {
      return [];
    }
    const baseDisplayed: number[] = this.slideNavEffectiveStartIndex !== undefined
      ? this.calculateDisplayIndices(this.slideNavEffectiveStartIndex)
      : this.displayedPageIndices;
    const raw = this.navigateToPreviousPage();
    const t = Math.max(0, raw);
    const prevSet = this.calculateDisplayIndices(t);
    if (PDFViewerViewModel.pageSetsEqual(prevSet, baseDisplayed)) {
      return [];
    }
    return prevSet;
  }

  private static pageSetsEqual(a: number[], b: number[]): boolean {
    if (a.length !== b.length) {
      return false;
    }
    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) {
        return false;
      }
    }
    return true;
  }

  private calculateDisplayIndices(targetIndex: number): number[] {
    switch (this.pageDisplayMode) {
      case 'single':
        return [targetIndex];
      case 'dual': {
        const leftIndex = targetIndex % 2 === 0 ? targetIndex : targetIndex - 1;
        const indices = [leftIndex];
        if (leftIndex + 1 < this.totalPageCount) {
          indices.push(leftIndex + 1);
        }
        return indices;
      }
      case 'dualContinuous': {
        const indices = [targetIndex];
        if (targetIndex + 1 < this.totalPageCount) {
          indices.push(targetIndex + 1);
        }
        return indices;
      }
      case 'tri': {
        const firstIndex = Math.floor(targetIndex / 3) * 3;
        const indices = [firstIndex];
        if (firstIndex + 1 < this.totalPageCount) {
          indices.push(firstIndex + 1);
        }
        if (firstIndex + 2 < this.totalPageCount) {
          indices.push(firstIndex + 2);
        }
        return indices;
      }
      case 'triContinuous': {
        const indices = [targetIndex];
        if (targetIndex + 1 < this.totalPageCount) {
          indices.push(targetIndex + 1);
        }
        if (targetIndex + 2 < this.totalPageCount) {
          indices.push(targetIndex + 2);
        }
        return indices;
      }
      case 'halfVertical':
      case 'halfHorizontal':
        return [targetIndex];
      default:
        return [targetIndex];
    }
  }

  private persistPreference<T>(key: string, value: T, logMessage: string): void {
    if (!this.preferences) {
      return;
    }
    try {
      this.preferences.putSync(key, value as Object);
      this.preferences.flushSync();
    } catch (error) {
      hilog.error(0, 'PDFViewerViewModel', `${logMessage}: ${error}.`);
    }
  }
}
