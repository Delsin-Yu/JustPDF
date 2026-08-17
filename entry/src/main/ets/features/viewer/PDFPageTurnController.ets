import { LengthMetricsUnit } from '@kit.ArkUI';
import { ContainerSpacing } from '../../common/ui/UIComponents';
import { PageCache, selectDisplayPixelMap } from '../../common/page/PageRasterCache';
import { Vec2, Vector2 } from '../../common/ui/Numbers';
import { PDFViewerViewModel } from './PDFViewerViewModel';
import { createPageViewSlots, PageViewSlot } from './PageViewSlot';

// 横向滑动翻页：主导轴判定；慢拖需要更大比例位移才提交，快拖/甩动阈值更低；甩动最低进度门槛
const PAGE_TURN_DOMINANT_RATIO: number = 0.55;
const PAGE_TURN_COMMIT_RATIO_SLOW: number = 0.22;
const PAGE_TURN_COMMIT_RATIO_FAST: number = 0.065;
const PAGE_TURN_FLICK_VP_PER_MS: number = 0.42;
const PAGE_TURN_FLICK_MIN_PROGRESS: number = 0.038;
const PAGE_TURN_ELASTIC_EXTRA_RATIO: number = 0.38;
/** 手指位移换算为翻页偏移的增益，略大于 1 可减少「拖很远才够翻页」的感觉 */
const PAGE_TURN_DRAG_GAIN: number = 1.55;
/** 横向滑动：邻条取消 / defer 收尾淡出时长（毫秒），宜短以减轻连滑时的节奏感与「浮层」感 */
const SLIDE_NEIGHBOR_FADE_OUT_MS: number = 160;

export interface PDFPageTurnControllerDependencies {
  viewerViewModel: PDFViewerViewModel;
  getUIContext: () => UIContext;
  getPageCache: (targetIndex: number, renderScale: number, loadVersion: number) => Promise<PageCache>;
  peekPageCache: (targetIndex: number, renderScale: number) => PageCache | undefined;
  getCurrentRenderScale: () => number;
  getPageLoadVersion: () => number;
  bumpPageLoadVersion: () => void;
  getPlaceholderPixelMap: () => PixelMap | undefined;
  getPageDisplaySize: (pageIndex: number) => Vector2;
  setSuppressSidePageFlipFromGesture: (value: boolean) => void;
  ensureMainRowEmptySlotsMatchDisplayed: () => void;
  resetViewToFit: () => void;
  redrawStrokes: () => void;
  gotoPage: (targetIndex: number, deferSlideVisualReset: boolean, recordJumpHistory: boolean) => Promise<void>;
  getMainSlotAt: (index: number) => PageViewSlot | undefined;
}

@ObservedV2
export class PDFPageTurnController {
  private readonly dependencies: PDFPageTurnControllerDependencies;

  /** 横向滑动翻页：vp 偏移（负值表示露出右侧下一套） */
  @Trace pageTurnOffsetVp: number = 0;
  /** 提交收尾时临时锁定预览层位置，使主层归零不牵动预览层。 */
  @Trace pageTurnPreviewOffsetLocked: boolean = false;
  @Trace pageTurnPreviewOffsetVp: number = 0;
  /** 一次滑动会话内使用固定几何量，避免 gotoPage 更新 viewSize 时牵动预览层。 */
  @Trace pageTurnMainAdvanceVp: number = 0;
  @Trace pageTurnPrevAdvanceVp: number = 0;
  /** 当前手势是否在横向翻页拖动中（松手前不 commitPage） */
  @Trace pageTurnDragActive: boolean = false;
  /** -1 下一套，+1 上一套，0 未定向 */
  @Trace pageTurnDirection: number = 0;
  /** 横向翻页手势的平滑水平速度（vp/ms），用于动态提交阈值与甩动判定 */
  slideVelocityVpPerMs: number = 0;
  lastSlideSampleTimeMs: number = 0;
  /** 松手后「收尾」动画期间为 true，用于交叉淡化与避免提前拆掉条带 */
  @Trace pageTurnCommitAnimating: boolean = false;
  /** 收尾动画：0=当前页不透明 / 目标页透明，1=当前淡出、目标淡入完成（与位移同一 animateTo 插值） */
  @Trace pageTurnCrossfadeT: number = 0;
  /** 横向滑动邻条预览：短促出现淡入（非跟手）；取消/提交/重置前须回到 1 以免与 offset 回弹打架 */
  @Trace pageTurnNeighborAppearOpacity: number = 1;
  private slideNeighborAppearFadeGen: number = 0;
  /** defer 的 gotoPage 正在 await load；与 slideGotoCompletionToken 配对避免被过期的异步 return 误清 */
  slideGotoInFlight: boolean = false;
  private slideGotoCompletionToken: number = 0;
  /** 提交位移动画与 onFinish 配对；递增即视为用户打断，可立即开始下一次滑动。 */
  private slideCommitAnimGen: number = 0;
  /** 已提交但尚未进入 gotoPage 的目标页（仅提交动画期间有效）。 */
  private pendingSlideGotoTarget: number | undefined = undefined;
  transitionNeighborGen: number = 0;
  @Trace transNextIndices: number[] = [];
  @Trace transPrevIndices: number[] = [];
  /** 横向滑动下一套 / 上一套预览条三槽 */
  @Trace transNextSlots: PageViewSlot[];
  @Trace transPrevSlots: PageViewSlot[];
  transPreviewAnnotateCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true), LengthMetricsUnit.PX);
  transPreviewDrawCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true), LengthMetricsUnit.PX);

  constructor(dependencies: PDFPageTurnControllerDependencies, settings: RenderingContextSettings) {
    this.dependencies = dependencies;
    this.transNextSlots = createPageViewSlots(settings);
    this.transPrevSlots = createPageViewSlots(settings);
  }

  getPendingSlideGotoTarget(): number | undefined {
    return this.pendingSlideGotoTarget;
  }

  clearPendingSlideGotoTarget(): void {
    this.pendingSlideGotoTarget = undefined;
  }

  markSlideGotoInFlight(navToken: number): void {
    this.slideGotoInFlight = true;
    this.slideGotoCompletionToken = navToken;
  }

  clearSlideGotoInFlightIfToken(navToken: number): void {
    if (this.slideGotoCompletionToken === navToken) {
      this.slideGotoInFlight = false;
    }
  }

  shouldDeferViewportFitReset(): boolean {
    return this.dependencies.viewerViewModel.pageFlipMode === 'horizontalSlide' &&
      (this.pageTurnDragActive || this.pageTurnCommitAnimating || this.slideGotoInFlight);
  }

  private transitionSlots(kind: 'next' | 'prev'): PageViewSlot[] {
    return kind === 'next' ? this.transNextSlots : this.transPrevSlots;
  }

  transitionSlotAt(kind: 'next' | 'prev', index: number): PageViewSlot | undefined {
    const slots = this.transitionSlots(kind);
    if (index < 0 || index >= slots.length) {
      return undefined;
    }
    return slots[index];
  }

  applyTransitionHighResIfNeeded(targetIndex: number, cache: PageCache): void {
    // 邻条只铺 layout 代理：滑动时若绑全幅 HQ，每帧 translate 会严重掉帧
    this.assignTransitionSlotByCache('next', this.transNextIndices.indexOf(targetIndex), cache);
    this.assignTransitionSlotByCache('prev', this.transPrevIndices.indexOf(targetIndex), cache);
  }

  /** 手势开始时把邻条从 HQ 降到 layout（若仍误绑了全幅） */
  demoteTransitionSlotsToLayout(): void {
    for (let i = 0; i < this.transNextIndices.length; i++) {
      const cache = this.dependencies.peekPageCache(
        this.transNextIndices[i], this.dependencies.getCurrentRenderScale());
      if (cache !== undefined) {
        this.assignTransitionSlotByCache('next', i, cache);
      }
    }
    for (let i = 0; i < this.transPrevIndices.length; i++) {
      const cache = this.dependencies.peekPageCache(
        this.transPrevIndices[i], this.dependencies.getCurrentRenderScale());
      if (cache !== undefined) {
        this.assignTransitionSlotByCache('prev', i, cache);
      }
    }
  }

  private clearTransitionPixelMaps(): void {
    for (let i = 0; i < this.transNextSlots.length; i++) {
      this.transNextSlots[i].clearPixelMap();
      this.transNextSlots[i].clearLoading();
    }
    for (let i = 0; i < this.transPrevSlots.length; i++) {
      this.transPrevSlots[i].clearPixelMap();
      this.transPrevSlots[i].clearLoading();
    }
  }

  resetHorizontalSlidePreview(): void {
    this.clearHorizontalSlidePreviewState();
  }

  /** 立即清除横向滑动预览条带（无淡出） */
  clearHorizontalSlidePreviewState(): void {
    this.pendingSlideGotoTarget = undefined;
    // 使尚未完成的 loadTransitionNeighbor 回调全部失效，避免收尾后仍 assign / 再触发淡入造成邻条 Next/Prev 闪跳
    this.transitionNeighborGen++;
    this.pageTurnDragActive = false;
    this.pageTurnDirection = 0;
    this.pageTurnOffsetVp = 0;
    this.pageTurnPreviewOffsetLocked = false;
    this.pageTurnPreviewOffsetVp = 0;
    this.pageTurnMainAdvanceVp = 0;
    this.pageTurnPrevAdvanceVp = 0;
    this.slideVelocityVpPerMs = 0;
    this.lastSlideSampleTimeMs = 0;
    this.pageTurnCommitAnimating = false;
    this.pageTurnCrossfadeT = 0;
    this.transNextIndices = [];
    this.transPrevIndices = [];
    this.clearTransitionPixelMaps();
    this.dependencies.viewerViewModel.clearSlideNavEffectiveStartIndex();
    this.slideNeighborAppearFadeGen++;
    this.pageTurnNeighborAppearOpacity = 1;
  }

  /**
   * 单指新按下时打断尚未结束的提交动画或 defer goto 收尾，便于连续快速滑动翻页。
   * 与 slideCommitAnimGen / pageLoadVersion 配合丢弃已过期的 animateTo 与 load 回调。
   */
  interruptHorizontalSlideForNewTouch(): void {
    if (this.dependencies.viewerViewModel.pageFlipMode !== 'horizontalSlide') {
      return;
    }
    this.slideCommitAnimGen++;
    if (this.pageTurnCommitAnimating && this.pendingSlideGotoTarget !== undefined) {
      const t = this.pendingSlideGotoTarget;
      this.pendingSlideGotoTarget = undefined;
      const dir = this.pageTurnDirection;
      this.pageTurnOffsetVp = this.computeCommitSlideEndOffsetVp(dir);
      this.pageTurnCrossfadeT = 1;
      this.pageTurnCommitAnimating = false;
      this.pageTurnNeighborAppearOpacity = 1;
      void this.dependencies.gotoPage(t, true, false);
      return;
    }
    this.pageTurnCommitAnimating = false;
    this.pageTurnCrossfadeT = 0;
    this.pendingSlideGotoTarget = undefined;
    if (this.slideGotoInFlight) {
      this.dependencies.bumpPageLoadVersion();
      this.slideGotoInFlight = false;
      this.slideGotoCompletionToken = 0;
      this.clearHorizontalSlidePreviewState();
    } else {
      this.resetHorizontalSlidePreview();
    }
  }

  /** defer goto 收尾：邻条淡出后再清条带并 resetViewToFit，避免视口与条带位移叠帧闪动 */
  fadeDeferSlideGotoTeardown(navToken: number): void {
    const hasStrip = this.transPrevIndices.length > 0 || this.transNextIndices.length > 0;
    if (!hasStrip) {
      this.dependencies.ensureMainRowEmptySlotsMatchDisplayed();
      this.clearHorizontalSlidePreviewState();
      this.dependencies.resetViewToFit();
      this.dependencies.redrawStrokes();
      if (this.slideGotoCompletionToken === navToken) {
        this.slideGotoInFlight = false;
      }
      return;
    }
    // 先于淡出再 bump：否则仍挂着的 loadTransitionNeighbor 会在 await 结束后误触发 startSlideNeighborPreviewFadeIn / assign
    this.transitionNeighborGen++;
    this.slideNeighborAppearFadeGen++;
    const g = this.slideNeighborAppearFadeGen;
    // 预览层先钉在中心盖住一帧级别的主层重绘窗口；主层再独立归零并恢复可见。
    this.lockCommittedPreviewAtCenter();
    // 邻条常窄于双页主行全宽，恢复主层可见前强制对齐空槽，避免右侧仍一帧旧位图。
    this.dependencies.ensureMainRowEmptySlotsMatchDisplayed();
    this.pageTurnCommitAnimating = false;
    this.pageTurnCrossfadeT = 0;
    this.pageTurnOffsetVp = 0;
    this.pageTurnNeighborAppearOpacity = 1;
    setTimeout(() => {
      if (g !== this.slideNeighborAppearFadeGen || this.slideGotoCompletionToken !== navToken) {
        return;
      }
      this.dependencies.getUIContext().animateTo({
        duration: SLIDE_NEIGHBOR_FADE_OUT_MS,
        curve: Curve.EaseIn,
        onFinish: () => {
          if (g !== this.slideNeighborAppearFadeGen) {
            return;
          }
          this.clearHorizontalSlidePreviewState();
          this.dependencies.resetViewToFit();
          this.dependencies.redrawStrokes();
          if (this.slideGotoCompletionToken === navToken) {
            this.slideGotoInFlight = false;
          }
        }
      }, () => {
        this.pageTurnNeighborAppearOpacity = 0;
      });
    }, 0);
  }

  /**
   * 邻条挂载（占位或真实图）时立即显示为不透明。
   * 不再做长淡入：连滑时反复 0→1 会与主条位移叠出「浮层脉冲」；与主条保持全不透明一起更接近连续拖动。
   */
  private startSlideNeighborPreviewFadeIn(): void {
    if (this.dependencies.viewerViewModel.pageFlipMode !== 'horizontalSlide') {
      return;
    }
    this.slideNeighborAppearFadeGen++;
    this.pageTurnNeighborAppearOpacity = 1;
  }

  /** 左侧邻条：预览透明度由 pageTurnNeighborAppearOpacity 控制 */
  getSlidePrevStripOpacity(): number {
    if (this.transPrevIndices.length > 0) {
      return this.pageTurnNeighborAppearOpacity;
    }
    return 1;
  }

  /**
   * 中间主条不透明度。
   * 提交动画期间不再淡出主条：否则邻条叠在上层、主条渐隐，连滑时像「手指上飘着一块页、底下还在翻」；
   * 仅靠位移与邻条即可衔接，观感更接近连续纸带。
   */
  getSlideCurrentStripOpacity(): number {
    return 1;
  }

  /** 右侧邻条：预览透明度由 pageTurnNeighborAppearOpacity 控制 */
  getSlideNextStripOpacity(): number {
    if (this.transNextIndices.length > 0) {
      return this.pageTurnNeighborAppearOpacity;
    }
    return 1;
  }

  private getStripAdvanceForCommitVp(): number {
    const ui = this.dependencies.getUIContext();
    const vvm = this.dependencies.viewerViewModel;
    return ui.px2vp((vvm.viewSize.x + ContainerSpacing) * vvm.viewScale);
  }

  private snapshotPageTurnGeometry(): void {
    const ui = this.dependencies.getUIContext();
    const scale = this.dependencies.viewerViewModel.viewScale;
    this.pageTurnMainAdvanceVp =
      ui.px2vp((this.dependencies.viewerViewModel.viewSize.x + ContainerSpacing) * scale);
    this.pageTurnPrevAdvanceVp = ui.px2vp((this.getPrevStripWidthPx() + ContainerSpacing) * scale);
  }

  /** 松手后动画应收尾的相对偏移（不含 baseline）：下一套为负、上一套为正 */
  private computeCommitSlideEndOffsetVp(direction: number): number {
    const adv = this.pageTurnMainAdvanceVp > 0 ? this.pageTurnMainAdvanceVp : this.getStripAdvanceForCommitVp();
    if (direction === -1) {
      return -adv;
    }
    if (direction === 1) {
      return adv;
    }
    return 0;
  }

  private clampSlideTuning(value: number, lo: number, hi: number): number {
    return Math.max(lo, Math.min(hi, value));
  }

  /** -1（钝）～+1（敏），由设置中 0～10 档映射 */
  private getHorizontalSlideSensK(): number {
    const level = this.clampSlideTuning(this.dependencies.viewerViewModel.horizontalSlideSensitivity, 0, 10);
    return (level - 5) / 5;
  }

  private getSlideDragGainEff(): number {
    const k = this.getHorizontalSlideSensK();
    return this.clampSlideTuning(PAGE_TURN_DRAG_GAIN * (1 + 0.28 * k), 1.12, 1.98);
  }

  private getSlideCommitRatioSlowEff(): number {
    const k = this.getHorizontalSlideSensK();
    return this.clampSlideTuning(PAGE_TURN_COMMIT_RATIO_SLOW * (1 - 0.35 * k), 0.13, 0.34);
  }

  private getSlideCommitRatioFastEff(): number {
    const k = this.getHorizontalSlideSensK();
    return this.clampSlideTuning(PAGE_TURN_COMMIT_RATIO_FAST * (1 - 0.45 * k), 0.034, 0.12);
  }

  private getSlideSpeedRefVpPerMsEff(): number {
    const k = this.getHorizontalSlideSensK();
    return this.clampSlideTuning(0.52 * (1 - 0.22 * k), 0.36, 0.64);
  }

  private getSlideFlickVpPerMsEff(): number {
    const k = this.getHorizontalSlideSensK();
    return this.clampSlideTuning(PAGE_TURN_FLICK_VP_PER_MS * (1 - 0.34 * k), 0.25, 0.58);
  }

  private getSlideFlickMinProgressEff(): number {
    const k = this.getHorizontalSlideSensK();
    return this.clampSlideTuning(PAGE_TURN_FLICK_MIN_PROGRESS * (1 - 0.34 * k), 0.022, 0.058);
  }

  /** 速度越快，所需 |offset|/viewport 比例越低；单位 vp/ms */
  private getDynamicCommitProgressThreshold(speedVpPerMs: number): number {
    const refV = this.getSlideSpeedRefVpPerMsEff();
    const fast = this.getSlideCommitRatioFastEff();
    const slow = this.getSlideCommitRatioSlowEff();
    const s = Math.min(1, Math.abs(speedVpPerMs) / refV);
    return fast + (slow - fast) * (1 - s);
  }

  private shouldFlickCommit(direction: number, progress: number): boolean {
    if (progress < this.getSlideFlickMinProgressEff()) {
      return false;
    }
    const v = this.slideVelocityVpPerMs;
    const flick = this.getSlideFlickVpPerMsEff();
    if (direction === -1) {
      return v <= -flick;
    }
    if (direction === 1) {
      return v >= flick;
    }
    return false;
  }

  private getStripWidthPx(slots: PageViewSlot[], pageCount: number): number {
    const g = ContainerSpacing;
    if (pageCount === 0) {
      return 0;
    }
    let w = 0;
    const n = Math.min(pageCount, slots.length);
    for (let i = 0; i < n; i++) {
      if (i > 0) {
        w += g;
      }
      w += slots[i].viewSize.x;
    }
    return w;
  }

  private getPrevStripWidthPx(): number {
    return this.getStripWidthPx(this.transPrevSlots, this.transPrevIndices.length);
  }

  private getNextStripWidthPx(): number {
    return this.getStripWidthPx(this.transNextSlots, this.transNextIndices.length);
  }

  private maxSlotsHeightPx(slots: PageViewSlot[]): number {
    let h = 0;
    for (let i = 0; i < slots.length; i++) {
      h = Math.max(h, slots[i].viewSize.y);
    }
    return h;
  }

  getTransitionStripSizePx(side: 'next' | 'prev'): Vector2 {
    if (side === 'next') {
      return Vec2(this.getNextStripWidthPx(), this.maxSlotsHeightPx(this.transNextSlots));
    }
    return Vec2(this.getPrevStripWidthPx(), this.maxSlotsHeightPx(this.transPrevSlots));
  }

  /** 预览层作为主文档层的兄弟节点，偏移只表达相对主层的位置，不参与 viewSize/fit 计算。 */
  getPreviewStripTranslateVp(side: 'next' | 'prev'): number {
    const ui = this.dependencies.getUIContext();
    const scale = this.dependencies.viewerViewModel.viewScale;
    const slideOffsetVp = this.pageTurnPreviewOffsetLocked ? this.pageTurnPreviewOffsetVp : this.pageTurnOffsetVp;
    if (side === 'next') {
      const usingSnapshot = this.pageTurnMainAdvanceVp > 0;
      const advanceVp = usingSnapshot
        ? this.pageTurnMainAdvanceVp
        : ui.px2vp((this.dependencies.viewerViewModel.viewSize.x + ContainerSpacing) * scale);
      const result = slideOffsetVp + advanceVp;
      return result;
    }
    const usingSnapshot = this.pageTurnPrevAdvanceVp > 0;
    const advanceVp = usingSnapshot
      ? this.pageTurnPrevAdvanceVp
      : ui.px2vp((this.getPrevStripWidthPx() + ContainerSpacing) * scale);
    const result = slideOffsetVp - advanceVp;
    return result;
  }

  /** 收尾时把目标预览层钉在主层位置，之后主层可独立归零并在其下方完成绘制。 */
  private lockCommittedPreviewAtCenter(): void {
    const ui = this.dependencies.getUIContext();
    const scale = this.dependencies.viewerViewModel.viewScale;
    if (this.pageTurnDirection === -1 && this.transNextIndices.length > 0) {
      const usingSnapshot = this.pageTurnMainAdvanceVp > 0;
      const advanceVp = usingSnapshot
        ? this.pageTurnMainAdvanceVp
        : ui.px2vp((this.dependencies.viewerViewModel.viewSize.x + ContainerSpacing) * scale);
      this.pageTurnPreviewOffsetVp = -advanceVp;
      this.pageTurnPreviewOffsetLocked = true;
      return;
    }
    if (this.pageTurnDirection === 1 && this.transPrevIndices.length > 0) {
      const usingSnapshot = this.pageTurnPrevAdvanceVp > 0;
      const advanceVp = usingSnapshot
        ? this.pageTurnPrevAdvanceVp
        : ui.px2vp((this.getPrevStripWidthPx() + ContainerSpacing) * scale);
      this.pageTurnPreviewOffsetVp = advanceVp;
      this.pageTurnPreviewOffsetLocked = true;
      return;
    }
    this.pageTurnPreviewOffsetLocked = false;
    this.pageTurnPreviewOffsetVp = 0;
  }

  private applyElasticPageTurnOffset(rawVp: number, viewportWvp: number): number {
    if (viewportWvp < 1) {
      return rawVp;
    }
    const soft = viewportWvp;
    const hard = viewportWvp * (1 + PAGE_TURN_ELASTIC_EXTRA_RATIO);
    const sign = rawVp >= 0 ? 1 : -1;
    const ax = Math.abs(rawVp);
    if (ax <= soft) {
      return rawVp;
    }
    const over = ax - soft;
    const damp = soft + Math.sqrt(over) * (10 + viewportWvp * 0.04);
    return sign * Math.min(damp, hard);
  }

  private beginPageTurnSession(direction: number, firstHorizDeltaVp: number, viewportWvp: number): void {
    this.slideNeighborAppearFadeGen++;
    this.pageTurnNeighborAppearOpacity = 1;
    this.pageTurnDragActive = true;
    this.pageTurnDirection = direction;
    this.pageTurnPreviewOffsetLocked = false;
    this.pageTurnPreviewOffsetVp = 0;
    this.dependencies.setSuppressSidePageFlipFromGesture(true);
    this.pageTurnOffsetVp =
      this.applyElasticPageTurnOffset(firstHorizDeltaVp * this.getSlideDragGainEff(), viewportWvp);
    this.transitionNeighborGen++;
    const gen = this.transitionNeighborGen;
    this.slideVelocityVpPerMs = 0;
    this.lastSlideSampleTimeMs = Date.now();
    if (direction < 0) {
      this.transPrevIndices = [];
      void this.loadTransitionNeighbor('next', gen);
    } else {
      this.transNextIndices = [];
      void this.loadTransitionNeighbor('prev', gen);
    }
  }

  private async loadTransitionNeighbor(kind: 'next' | 'prev', gen: number): Promise<void> {
    const indices = kind === 'next'
      ? this.dependencies.viewerViewModel.peekNextSetIndices()
      : this.dependencies.viewerViewModel.peekPrevSetIndices();
    if (indices.length === 0) {
      return;
    }
    if (kind === 'next') {
      this.transNextIndices = indices;
      this.applyTransitionPlaceholders('next', indices);
    } else {
      this.transPrevIndices = indices;
      this.applyTransitionPlaceholders('prev', indices);
    }
    this.startSlideNeighborPreviewFadeIn();
    const loadVersion = this.dependencies.getPageLoadVersion();
    const tasks: Array<Promise<void>> = [];
    for (let i = 0; i < indices.length; i++) {
      const pageIndex = indices[i];
      const slot = i;
      tasks.push(this.dependencies.getPageCache(pageIndex, this.dependencies.getCurrentRenderScale(), loadVersion)
        .then(cache => {
          if (gen !== this.transitionNeighborGen || loadVersion !== this.dependencies.getPageLoadVersion()) {
            return;
          }
          this.assignTransitionSlot(kind, slot, cache);
        })
        .catch((_e: Error) => {
        }));
    }
    await Promise.all(tasks);
    if (gen !== this.transitionNeighborGen) {
      return;
    }
  }

  private applyTransitionPlaceholders(kind: 'next' | 'prev', indices: number[]): void {
    for (let i = 0; i < indices.length; i++) {
      const slot = this.transitionSlotAt(kind, i);
      if (slot === undefined) {
        continue;
      }
      slot.applyDisplay(this.dependencies.getPlaceholderPixelMap(), this.dependencies.getPageDisplaySize(indices[i]), true);
    }
  }

  private assignTransitionSlot(kind: 'next' | 'prev', slot: number, cache: PageCache): void {
    this.assignTransitionSlotByCache(kind, slot, cache);
  }

  private assignTransitionSlotByCache(kind: 'next' | 'prev', slot: number, cache: PageCache): void {
    if (slot < 0) {
      return;
    }
    const target = this.transitionSlotAt(kind, slot);
    if (target === undefined) {
      return;
    }
    // 邻条始终 preferLayout：滑动合成只应使用 layout 级纹理
    const displayMap: PixelMap = selectDisplayPixelMap(cache, true);
    target.applyDisplay(displayMap, cache.displaySize, false);
  }

  handleHorizontalSlideDragMove(deltaPx: Vector2, dvp: Vector2): void {
    const ui = this.dependencies.getUIContext();
    const vvm = this.dependencies.viewerViewModel;
    const viewportWvp = vvm.getPanClampBounds(ui).viewportSizeVp.x;
    const dominantH = Math.abs(dvp.x) * PAGE_TURN_DOMINANT_RATIO >= Math.abs(dvp.y);

    if (this.pageTurnDragActive) {
      vvm.panByDeltaVp(Vec2(0, dvp.y), ui);
      this.pageTurnOffsetVp = this.applyElasticPageTurnOffset(
        this.pageTurnOffsetVp + dvp.x * this.getSlideDragGainEff(),
        viewportWvp
      );
      const now = Date.now();
      if (this.lastSlideSampleTimeMs > 0) {
        const dtMs = Math.max(1, now - this.lastSlideSampleTimeMs);
        const instVpPerMs = (dvp.x * this.getSlideDragGainEff()) / dtMs;
        this.slideVelocityVpPerMs = 0.42 * this.slideVelocityVpPerMs + 0.58 * instVpPerMs;
      }
      this.lastSlideSampleTimeMs = now;
      if (this.pageTurnDirection === -1 && this.transNextIndices.length === 0) {
        this.transitionNeighborGen++;
        void this.loadTransitionNeighbor('next', this.transitionNeighborGen);
      } else if (this.pageTurnDirection === 1 && this.transPrevIndices.length === 0) {
        this.transitionNeighborGen++;
        void this.loadTransitionNeighbor('prev', this.transitionNeighborGen);
      }
      return;
    }

    const canH = vvm.canPanHorizontally(ui);
    const nextIdx = vvm.peekNextSetIndices();
    const prevIdx = vvm.peekPrevSetIndices();
    const startNext = dominantH && dvp.x < 0 && nextIdx.length > 0 &&
      (!canH || vvm.isAtHorizontalScrollRightEnd(ui));
    const startPrev = dominantH && dvp.x > 0 && prevIdx.length > 0 &&
      (!canH || vvm.isAtHorizontalScrollLeftEnd(ui));

    if (startNext) {
      this.beginPageTurnSession(-1, dvp.x, viewportWvp);
      vvm.panByDeltaVp(Vec2(0, dvp.y), ui);
      return;
    }
    if (startPrev) {
      this.beginPageTurnSession(1, dvp.x, viewportWvp);
      vvm.panByDeltaVp(Vec2(0, dvp.y), ui);
      return;
    }

    vvm.panBy(deltaPx, ui);
  }

  finalizeHorizontalSlideOnUp(): void {
    const ui = this.dependencies.getUIContext();
    if (!this.pageTurnDragActive) {
      return;
    }
    const viewportWvp = this.dependencies.viewerViewModel.getPanClampBounds(ui).viewportSizeVp.x;
    const progress = Math.abs(this.pageTurnOffsetVp) / Math.max(1, viewportWvp);
    const ratioReq = this.getDynamicCommitProgressThreshold(this.slideVelocityVpPerMs);
    const dir = this.pageTurnDirection;
    const committed =
      (dir !== 0 && progress >= ratioReq) || this.shouldFlickCommit(dir, progress);
    this.pageTurnDragActive = false;

    if (!committed || dir === 0) {
      this.pendingSlideGotoTarget = undefined;
      this.pageTurnCommitAnimating = false;
      this.pageTurnCrossfadeT = 0;
      const hasPreviewStrip = this.transPrevIndices.length > 0 || this.transNextIndices.length > 0;
      this.slideNeighborAppearFadeGen++;
      const cancelAnimGen = this.slideNeighborAppearFadeGen;
      this.dependencies.getUIContext().animateTo({
        duration: 200,
        curve: Curve.EaseInOut,
        onFinish: () => {
          if (cancelAnimGen !== this.slideNeighborAppearFadeGen) {
            return;
          }
          if (!hasPreviewStrip) {
            this.clearHorizontalSlidePreviewState();
          }
        }
      }, () => {
        this.pageTurnOffsetVp = 0;
      });
      if (hasPreviewStrip) {
        this.dependencies.getUIContext().animateTo({
          duration: SLIDE_NEIGHBOR_FADE_OUT_MS,
          curve: Curve.EaseIn,
          onFinish: () => {
            if (cancelAnimGen !== this.slideNeighborAppearFadeGen) {
              return;
            }
            this.clearHorizontalSlidePreviewState();
          }
        }, () => {
          this.pageTurnNeighborAppearOpacity = 0;
        });
      }
      return;
    }

    const targetNext = this.dependencies.viewerViewModel.navigateToNextPage();
    const targetPrev = Math.max(0, this.dependencies.viewerViewModel.navigateToPreviousPage());
    const targetPage = dir === -1 ? targetNext : targetPrev;
    this.pendingSlideGotoTarget = targetPage;
    this.dependencies.viewerViewModel.setSlideNavEffectiveStartIndex(targetPage);
    this.snapshotPageTurnGeometry();

    const endOff = this.computeCommitSlideEndOffsetVp(dir);
    const startOff = this.pageTurnOffsetVp;
    const dist = Math.abs(endOff - startOff);
    if (dist < 0.75) {
      this.slideNeighborAppearFadeGen++;
      this.pageTurnNeighborAppearOpacity = 1;
      this.pageTurnCommitAnimating = true;
      this.pageTurnCrossfadeT = 1;
      void this.dependencies.gotoPage(targetPage, true, false);
      return;
    }
    const dur = Math.round(Math.min(520, Math.max(240, 220 + (dist / Math.max(1, viewportWvp)) * 320)));
    this.slideNeighborAppearFadeGen++;
    this.pageTurnNeighborAppearOpacity = 1;
    this.pageTurnCommitAnimating = true;
    this.pageTurnCrossfadeT = 0;
    const commitAnimGuard = this.slideCommitAnimGen;
    this.dependencies.getUIContext().animateTo({
      duration: dur,
      curve: Curve.EaseOut,
      onFinish: () => {
        if (commitAnimGuard !== this.slideCommitAnimGen) {
          return;
        }
        // 位移到位后再 goto：主条不再做淡出，由邻条与位移承担过渡，goto 后 reset 偏移。
        void this.dependencies.gotoPage(targetPage, true, false);
      }
    }, () => {
      this.pageTurnOffsetVp = endOff;
      this.pageTurnCrossfadeT = 1;
    });
  }

  private assignViewSlotFromTransition(kind: 'next' | 'prev', mainSlot: number, transSlot: number): boolean {
    const source = this.transitionSlotAt(kind, transSlot);
    const target = this.dependencies.getMainSlotAt(mainSlot);
    if (source === undefined || target === undefined || source.pixelMap === undefined) {
      return false;
    }
    target.copyDisplayFrom(source);
    return true;
  }

  private assignViewSlotFromTransNext(mainSlot: number, transSlot: number): boolean {
    return this.assignViewSlotFromTransition('next', mainSlot, transSlot);
  }

  private assignViewSlotFromTransPrev(mainSlot: number, transSlot: number): boolean {
    return this.assignViewSlotFromTransition('prev', mainSlot, transSlot);
  }

  /**
   * 从横向滑动邻条带拷贝已解码的 PixelMap 到主槽，避免 commit 后、占位替换前仍画上一套图（目标→旧页→目标）。
   */
  trySeedMainViewsFromTransition(indices: number[]): boolean[] {
    const seeded: boolean[] = [false, false, false];
    const preferPrevStrip = this.pageTurnDirection === 1;
    const nSlots = Math.min(3, indices.length);
    for (let mainSlot = 0; mainSlot < nSlots; mainSlot++) {
      const pageIndex = indices[mainSlot];
      let done = false;
      if (!preferPrevStrip) {
        const jn = this.transNextIndices.indexOf(pageIndex);
        if (jn >= 0) {
          done = this.assignViewSlotFromTransNext(mainSlot, jn);
        }
        if (!done) {
          const jp = this.transPrevIndices.indexOf(pageIndex);
          if (jp >= 0) {
            done = this.assignViewSlotFromTransPrev(mainSlot, jp);
          }
        }
      } else {
        const jp = this.transPrevIndices.indexOf(pageIndex);
        if (jp >= 0) {
          done = this.assignViewSlotFromTransPrev(mainSlot, jp);
        }
        if (!done) {
          const jn = this.transNextIndices.indexOf(pageIndex);
          if (jn >= 0) {
            done = this.assignViewSlotFromTransNext(mainSlot, jn);
          }
        }
      }
      seeded[mainSlot] = done;
    }
    return seeded;
  }

  /** 供链接层判断当前是否处于横向翻页忙碌态 */
  getBusyDisabledReason(): string {
    if (this.pageTurnDragActive) {
      return 'pageTurnDragActive';
    }
    if (this.pageTurnCommitAnimating) {
      return 'pageTurnCommitAnimating';
    }
    if (this.slideGotoInFlight) {
      return 'slideGotoInFlight';
    }
    if (this.pendingSlideGotoTarget !== undefined) {
      return 'pendingSlideGotoTarget=' + this.pendingSlideGotoTarget.toString();
    }
    if (Math.abs(this.pageTurnOffsetVp) >= 0.001) {
      return 'pageTurnOffsetVp=' + this.pageTurnOffsetVp.toString();
    }
    if (this.transPrevIndices.length > 0 || this.transNextIndices.length > 0) {
      return 'transitionStrips=prev' + this.transPrevIndices.length.toString() +
        '/next' + this.transNextIndices.length.toString();
    }
    return '';
  }
}
