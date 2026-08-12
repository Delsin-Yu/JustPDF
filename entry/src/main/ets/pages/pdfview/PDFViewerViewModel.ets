import { ContainerSpacing, getCheckIcon } from '../../components/UIComponents';
import { mul, pxToVp, Vec2, Vector2 } from '../../components/Numbers';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { preferences } from '@kit.ArkData';

/** 阅读档 / 高清档；下限提高以减少密谱细线在小缩放下被光栅丢弃 */
export const ViewerRenderScaleLevels: number[] = [6, 8];
export const ViewerMinRenderScale: number = 6;
/** viewScale 超过此阈值时升到高清档（宜低于旧值 2.0，避免长时间卡在阅读档） */
const ViewerScaleThresholds: number[] = [1.3];

export type PDFPageDisplayMode = 'single' | 'dual' | 'dualContinuous' | 'tri' | 'triContinuous';
export type PDFPageFlipMode = 'side' | 'button' | 'extern' | 'horizontalSlide';
export type PDFLinkVisualMode = 'hidden' | 'fadeOnPageEnter' | 'always';

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
  @Trace public isAnnotatePaletteVisible: boolean = false;
  @Trace public isBookmarkPanelVisible: boolean = false;
  private savedPageFlipMode: PDFPageFlipMode = 'horizontalSlide';
  public onPageFlipModeChanged: ((mode: PDFPageFlipMode) => void) | undefined = undefined;
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
      this.pageDisplayMode = preferencesValue.getSync('pageDisplayMode', 'single') as PDFPageDisplayMode;
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
    }
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
      this.pageDisplayMode === 'triContinuous') {
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
      this.pageDisplayMode === 'triContinuous') {
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
    this.pageDisplayMode = value;
    this.persistPreference('pageDisplayMode', value, '保存页面显示模式出错');
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

  closeAnnotatePalette(): void {
    if (!this.isAnnotatePaletteVisible) {
      return;
    }
    this.isAnnotatePaletteVisible = false;
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
    if (this.getExpectedSlotCount() === 1) {
      this.viewSize = view1Size;
      return;
    }
    if (this.getExpectedSlotCount() === 2) {
      this.viewSize = Vec2(
        view1Size.x + ContainerSpacing + view2Size.x,
        Math.max(view1Size.y, view2Size.y)
      );
      return;
    }
    this.viewSize = Vec2(
      view1Size.x + ContainerSpacing + view2Size.x + ContainerSpacing + view3Size.x,
      Math.max(view1Size.y, view2Size.y, view3Size.y)
    );
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
    if (scaledViewSizeVp.x <= viewportSizeVp.x) {
      const centered = (viewportSizeVp.x - scaledViewSizeVp.x) / 2;
      minX = centered;
      maxX = centered;
    } else {
      minX = -(scaledViewSizeVp.x - viewportSizeVp.x) - relaxX;
      maxX = relaxX;
    }

    let minY: number;
    let maxY: number;
    if (scaledViewSizeVp.y <= viewportSizeVp.y) {
      const centeredY = (viewportSizeVp.y - scaledViewSizeVp.y) / 2;
      minY = centeredY;
      maxY = centeredY;
    } else {
      minY = -(scaledViewSizeVp.y - viewportSizeVp.y) - relaxY;
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
    if (b.scaledViewSizeVp.x <= b.viewportSizeVp.x) {
      return false;
    }
    return this.viewPan.x <= b.minX + b.relaxX * 0.35 + epsilonVp;
  }

  /** 横向可滚动且已贴左端（可向右拖出上一页预览） */
  isAtHorizontalScrollLeftEnd(uiContext: UIContext, epsilonVp: number = 2): boolean {
    const b = this.getPanClampBounds(uiContext);
    if (b.scaledViewSizeVp.x <= b.viewportSizeVp.x) {
      return false;
    }
    return this.viewPan.x >= b.maxX - b.relaxX * 0.35 - epsilonVp;
  }

  /** 内容宽于视口时需横向平移才能看全 */
  canPanHorizontally(uiContext: UIContext): boolean {
    const b = this.getPanClampBounds(uiContext);
    return b.scaledViewSizeVp.x > b.viewportSizeVp.x;
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
    if (this.totalPageCount <= 0) {
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
    if (this.totalPageCount <= 0) {
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
