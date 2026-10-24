import { hilog } from '@kit.PerformanceAnalysisKit';
import { PageCache } from '../../common/page/PageRasterCache';
import { Vec2, Vector2 } from '../../common/ui/Numbers';
import { PDFViewerViewModel } from './PDFViewerViewModel';
import { PageViewSlot } from './PageViewSlot';

const TAG: string = 'PDFHalfPage';
const HALF_REVEAL: number = 0.5;

export interface PDFHalfPageControllerDependencies {
  viewerViewModel: PDFViewerViewModel;
  getPageCache: (targetIndex: number, renderScale: number, loadVersion: number) => Promise<PageCache>;
  peekPageCache: (targetIndex: number, renderScale: number) => PageCache | undefined;
  getCurrentRenderScale: () => number;
  getPageLoadVersion: () => number;
  getPlaceholderPixelMap: () => PixelMap | undefined;
  getPageDisplaySize: (pageIndex: number) => Vector2;
  redrawOverlayStrokes: (pageIndex: number, slot: PageViewSlot) => void;
  getMainSlotAt: (index: number) => PageViewSlot | undefined;
}

@ObservedV2
export class PDFHalfPageController {
  private readonly dependencies: PDFHalfPageControllerDependencies;
  @Trace overlaySlot: PageViewSlot;
  @Trace overlayPageIndex: number = -1;
  @Trace overlayShown: boolean = false;
  /** 0=无叠层，0.5=半页，1=整页盖住 */
  @Trace overlayReveal: number = 0;
  /** 整页盖住后置 0，节点留着避免拆 Image */
  @Trace overlayCoverOpacity: number = 1;
  /** 下一次 gotoPage 铺占位时，把叠层图拷到主槽 0，避免 A.5→B 闪白 */
  seedMainOnNextGoto: boolean = false;
  slideStartedPreview: boolean = false;
  private loadGen: number = 0;

  constructor(dependencies: PDFHalfPageControllerDependencies, settings: RenderingContextSettings) {
    this.dependencies = dependencies;
    this.overlaySlot = new PageViewSlot(settings);
  }

  shouldShowOverlay(): boolean {
    return this.dependencies.viewerViewModel.isHalfPageMode() &&
      this.overlayShown &&
      this.overlayReveal > 0.001 &&
      this.overlayCoverOpacity > 0.01;
  }

  committedReveal(): number {
    return this.dependencies.viewerViewModel.halfPagePreviewActive ? HALF_REVEAL : 0;
  }

  isHalfHorizontal(): boolean {
    return this.dependencies.viewerViewModel.pageDisplayMode === 'halfHorizontal';
  }

  getOverlayDropShadow(): ShadowOptions {
    if (this.overlayReveal > 0.92 || this.overlayReveal < 0.08) {
      return { radius: 0, color: 'rgba(0, 0, 0, 0)', offsetX: 0, offsetY: 0 };
    }
    if (this.isHalfHorizontal()) {
      return { radius: 18, color: 'rgba(0, 0, 0, 0.32)', offsetX: 8, offsetY: 0 };
    }
    return { radius: 18, color: 'rgba(0, 0, 0, 0.32)', offsetX: 0, offsetY: 8 };
  }

  getOverlayClipSizePx(): Vector2 {
    let pageSize: Vector2 = this.overlaySlot.viewSize;
    if (pageSize.x <= 0 || pageSize.y <= 0) {
      const main: PageViewSlot | undefined = this.dependencies.getMainSlotAt(0);
      if (main !== undefined && main.viewSize.x > 0 && main.viewSize.y > 0) {
        pageSize = main.viewSize;
      } else {
        return Vec2(1, 1);
      }
    }
    const reveal: number = Math.max(0, Math.min(1, this.overlayReveal));
    if (this.isHalfHorizontal()) {
      return Vec2(Math.max(1, pageSize.x * reveal), pageSize.y);
    }
    return Vec2(pageSize.x, Math.max(1, pageSize.y * reveal));
  }

  clearPreview(): void {
    this.loadGen++;
    this.dependencies.viewerViewModel.setHalfPagePreviewActive(false);
    this.overlayShown = false;
    this.overlayPageIndex = -1;
    this.overlayReveal = 0;
    this.overlayCoverOpacity = 1;
  }

  /** 整页落地后把当前主槽停在叠层里，透明度 0，避免 Hidden 拆掉 Image */
  parkInvisibleCoverFromMain(): void {
    const main: PageViewSlot | undefined = this.dependencies.getMainSlotAt(0);
    if (main === undefined || main.pixelMap === undefined) {
      this.clearPreview();
      return;
    }
    this.overlaySlot.copyDisplayFrom(main);
    this.overlayPageIndex = this.dependencies.viewerViewModel.currentPageIndex;
    this.overlayShown = true;
    this.overlayReveal = 1;
    this.overlayCoverOpacity = 0;
    this.dependencies.viewerViewModel.setHalfPagePreviewActive(false);
    this.dependencies.redrawOverlayStrokes(this.overlayPageIndex, this.overlaySlot);
  }

  keepFullCoverVisible(): void {
    this.dependencies.viewerViewModel.setHalfPagePreviewActive(false);
    this.overlayShown = true;
    this.overlayReveal = 1;
    this.overlayCoverOpacity = 1;
  }

  /** A.5→B 落地：主槽已是新页后再把叠层透明度置 0 */
  settleFullPageCover(): void {
    this.dependencies.viewerViewModel.setHalfPagePreviewActive(false);
    this.overlayShown = true;
    this.overlayReveal = 1;
    this.overlayCoverOpacity = 0;
  }

  hasFullCoverOf(pageIndex: number): boolean {
    return this.overlayPageIndex === pageIndex && this.overlaySlot.pixelMap !== undefined;
  }

  reviveFullCover(pageIndex: number): boolean {
    if (!this.hasFullCoverOf(pageIndex)) {
      return false;
    }
    this.overlayShown = true;
    this.overlayReveal = 1;
    this.overlayCoverOpacity = 1;
    this.dependencies.viewerViewModel.setHalfPagePreviewActive(true);
    return true;
  }

  /** 从当前主槽拷出整页 B，先整页盖住再收到半页 */
  preparePreviewFromMainSlot(pageIndex: number): void {
    const main: PageViewSlot | undefined = this.dependencies.getMainSlotAt(0);
    if (main !== undefined) {
      this.overlaySlot.copyDisplayFrom(main);
    }
    this.overlayPageIndex = pageIndex;
    this.overlayShown = true;
    this.overlayReveal = 1;
    this.overlayCoverOpacity = 1;
    this.dependencies.viewerViewModel.setHalfPagePreviewActive(true);
    this.dependencies.redrawOverlayStrokes(pageIndex, this.overlaySlot);
    hilog.info(0, TAG, `半页预览由主槽准备: page=${pageIndex}`);
  }

  seedMainFromOverlay(): boolean {
    const main: PageViewSlot | undefined = this.dependencies.getMainSlotAt(0);
    if (main === undefined || this.overlaySlot.pixelMap === undefined) {
      return false;
    }
    main.copyDisplayFrom(this.overlaySlot);
    return true;
  }

  consumeSeedMainOnNextGoto(): boolean {
    if (!this.seedMainOnNextGoto) {
      return false;
    }
    this.seedMainOnNextGoto = false;
    return this.seedMainFromOverlay();
  }

  async showPreviewOfPage(pageIndex: number): Promise<void> {
    if (pageIndex < 0) {
      this.clearPreview();
      return;
    }
    this.overlayPageIndex = pageIndex;
    this.overlayShown = true;
    this.overlayCoverOpacity = 1;
    if (this.overlayReveal < 0.001) {
      this.overlayReveal = 0;
    }
    this.dependencies.viewerViewModel.setHalfPagePreviewActive(true);
    await this.loadOverlayPage(pageIndex);
  }

  async armOverlayForSlide(pageIndex: number, reveal: number): Promise<void> {
    if (pageIndex < 0) {
      return;
    }
    this.overlayPageIndex = pageIndex;
    this.overlayShown = true;
    this.overlayCoverOpacity = 1;
    this.overlayReveal = reveal;
    await this.loadOverlayPage(pageIndex);
  }

  applySlideReveal(direction: number, progress: number): void {
    const p: number = Math.max(0, Math.min(1, progress));
    if (direction < 0) {
      if (this.slideStartedPreview) {
        this.overlayReveal = HALF_REVEAL + HALF_REVEAL * p;
      } else {
        this.overlayReveal = HALF_REVEAL * p;
      }
    } else if (this.slideStartedPreview) {
      this.overlayReveal = HALF_REVEAL * (1 - p);
    } else {
      this.overlayReveal = 1 - HALF_REVEAL * p;
    }
  }

  applyOverlayCache(cache: PageCache): void {
    if (this.overlayPageIndex < 0) {
      return;
    }
    this.overlaySlot.applyCache(cache);
    this.dependencies.redrawOverlayStrokes(this.overlayPageIndex, this.overlaySlot);
  }

  async loadOverlayPage(pageIndex: number): Promise<void> {
    this.loadGen++;
    const gen: number = this.loadGen;
    this.overlayPageIndex = pageIndex;
    const peeked: PageCache | undefined =
      this.dependencies.peekPageCache(pageIndex, this.dependencies.getCurrentRenderScale());
    if (peeked !== undefined) {
      this.overlaySlot.applyCache(peeked);
      this.dependencies.redrawOverlayStrokes(pageIndex, this.overlaySlot);
    } else {
      this.overlaySlot.applyDisplay(
        this.dependencies.getPlaceholderPixelMap(),
        this.dependencies.getPageDisplaySize(pageIndex),
        true
      );
    }
    try {
      const cache: PageCache = await this.dependencies.getPageCache(
        pageIndex,
        this.dependencies.getCurrentRenderScale(),
        this.dependencies.getPageLoadVersion()
      );
      if (gen !== this.loadGen) {
        return;
      }
      this.overlaySlot.applyCache(cache);
      this.dependencies.redrawOverlayStrokes(pageIndex, this.overlaySlot);
    } catch (error) {
      hilog.error(0, TAG, `加载半页预览失败: ${error}.`);
    }
  }
}
