import { ContainerSpacing, getCheckIcon } from '../../components/UIComponents';
import { mul, pxToVp, Vec2, Vector2 } from '../../components/Numbers';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { preferences } from '@kit.ArkData';

export const ViewerRenderScaleLevels: number[] = [4, 8];
export const ViewerMinRenderScale: number = 4;
const ViewerScaleThresholds: number[] = [2.0];

export type PDFPageDisplayMode = 'single' | 'dual' | 'dualContinuous' | 'tri' | 'triContinuous';
export type PDFPageFlipMode = 'side' | 'button' | 'extern';
export type PDFAnnotateMode = 'drag' | 'draw' | 'erase';

@ObservedV2
export class PDFViewerViewModel {
  private preferences?: preferences.Preferences;
  private readonly minScale: number;
  private readonly maxScale: number;

  @Trace public currentPageIndex: number = 0;
  @Trace public totalPageCount: number = 0;
  @Trace public pageDisplayMode: PDFPageDisplayMode = 'single';
  @Trace public pageFlipMode: PDFPageFlipMode = 'side';
  @Trace public annotateMode: PDFAnnotateMode = 'drag';
  @Trace public viewPan: Vector2 = Vec2(0, 0);
  @Trace public viewScale: number = 1.0;
  @Trace public viewportSize: Vector2 = Vec2(0, 0);
  @Trace public viewSize: Vector2 = Vec2(0, 0);
  @Trace public showControls: boolean = true;
  @Trace public showSlider: boolean = true;
  @Trace public controlsTransparency: number = 0.5;
  @Trace public displayedPageIndices: number[] = [];
  @Trace public menuExpanded: boolean = false;

  constructor(minScale: number = 0.5, maxScale: number = 9.0) {
    this.minScale = minScale;
    this.maxScale = maxScale;
  }

  loadPreferences(preferencesValue: preferences.Preferences): void {
    this.preferences = preferencesValue;
    try {
      this.showControls = preferencesValue.getSync('showControls', true) as boolean;
      this.showSlider = preferencesValue.getSync('showSlider', true) as boolean;
      this.pageDisplayMode = preferencesValue.getSync('pageDisplayMode', 'single') as PDFPageDisplayMode;
      this.pageFlipMode = preferencesValue.getSync('pageFlipMode', 'side') as PDFPageFlipMode;
      this.annotateMode = preferencesValue.getSync('annotateMode', 'drag') as PDFAnnotateMode;
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

  getAnnotateModeText(): string {
    switch (this.annotateMode) {
      case 'drag':
        return '拖动';
      case 'draw':
        return '绘制';
      case 'erase':
        return '擦除';
    }
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

  navigateToPreviousPage(): number {
    if (this.pageDisplayMode === 'single' || this.pageDisplayMode === 'dualContinuous' ||
      this.pageDisplayMode === 'triContinuous') {
      return this.currentPageIndex - 1;
    }
    if (this.pageDisplayMode === 'dual') {
      const currentPair = Math.floor(this.currentPageIndex / 2);
      return Math.max(0, (currentPair - 1) * 2);
    }
    const currentGroup = Math.floor(this.currentPageIndex / 3);
    return Math.max(0, (currentGroup - 1) * 3);
  }

  navigateToNextPage(): number {
    if (this.pageDisplayMode === 'single' || this.pageDisplayMode === 'dualContinuous' ||
      this.pageDisplayMode === 'triContinuous') {
      return Math.min(this.currentPageIndex + 1, this.getLastNavigableIndex());
    }
    if (this.pageDisplayMode === 'dual') {
      const currentPair = Math.floor(this.currentPageIndex / 2);
      return (currentPair + 1) * 2;
    }
    const currentGroup = Math.floor(this.currentPageIndex / 3);
    return (currentGroup + 1) * 3;
  }

  setPageDisplayMode(value: PDFPageDisplayMode): void {
    this.pageDisplayMode = value;
    this.persistPreference('pageDisplayMode', value, '保存页面显示模式出错');
  }

  setPageFlipMode(value: PDFPageFlipMode): void {
    this.pageFlipMode = value;
    this.persistPreference('pageFlipMode', value, '保存翻页模式出错');
  }

  setAnnotateMode(value: PDFAnnotateMode): void {
    this.annotateMode = value;
    this.persistPreference('annotateMode', value, '保存注释模式出错');
  }

  setShowControls(value: boolean): void {
    this.showControls = value;
    this.persistPreference('showControls', value, '保存显示控件出错');
  }

  setShowSlider(value: boolean): void {
    this.showSlider = value;
    this.persistPreference('showSlider', value, '保存滑块偏好出错');
  }

  setMenuExpanded(value: boolean): void {
    this.menuExpanded = value;
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

  clampViewPan(uiContext: UIContext): void {
    const viewSizeVp = pxToVp(this.viewSize, uiContext);
    const viewportSizeVp = pxToVp(this.viewportSize, uiContext);
    const scaledViewSizeVp = mul(viewSizeVp, this.viewScale);
    const boundaryRelaxation = 0.25;
    const relaxX = viewportSizeVp.x * boundaryRelaxation;
    const relaxY = viewportSizeVp.y * boundaryRelaxation;

    let clampedX = this.viewPan.x;
    let clampedY = this.viewPan.y;

    if (scaledViewSizeVp.x <= viewportSizeVp.x) {
      clampedX = (viewportSizeVp.x - scaledViewSizeVp.x) / 2;
    } else {
      const minX = -(scaledViewSizeVp.x - viewportSizeVp.x) - relaxX;
      const maxX = relaxX;
      clampedX = Math.max(minX, Math.min(maxX, this.viewPan.x));
    }

    if (scaledViewSizeVp.y <= viewportSizeVp.y) {
      clampedY = (viewportSizeVp.y - scaledViewSizeVp.y) / 2;
    } else {
      const minY = -(scaledViewSizeVp.y - viewportSizeVp.y) - relaxY;
      const maxY = relaxY;
      clampedY = Math.max(minY, Math.min(maxY, this.viewPan.y));
    }

    this.viewPan = Vec2(clampedX, clampedY);
  }

  panBy(delta: Vector2, uiContext: UIContext): void {
    this.viewPan = Vec2(this.viewPan.x + delta.x, this.viewPan.y + delta.y);
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

  buildAnnotateModeMenu(): MenuElement[] {
    return [
      {
        value: '拖动',
        action: () => this.setAnnotateMode('drag'),
        symbolIcon: getCheckIcon(this.annotateMode == 'drag')
      },
      {
        value: '绘制',
        action: () => this.setAnnotateMode('draw'),
        symbolIcon: getCheckIcon(this.annotateMode == 'draw')
      },
      {
        value: '擦除',
        action: () => this.setAnnotateMode('erase'),
        symbolIcon: getCheckIcon(this.annotateMode == 'erase')
      }
    ];
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