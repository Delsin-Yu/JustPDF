import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { PageStore } from '../../common/page/PageStore';
import { PdfLinkAnnotation, PdfLinkRectangle } from '../../common/page/PdfLinks';
import { Vec2, Vector2 } from '../../common/ui/Numbers';
import { PDFLinkJumpHistory } from './PDFLinkJumpHistory';
import { PDFLinkDisplayHitArea } from './PDFPageSlot';
import { PDFViewerViewModel } from './PDFViewerViewModel';
import { PageViewSlot } from './PageViewSlot';
import { PDFPageTurnController } from './PDFPageTurnController';

const PdfLinkDebugLogEnabled: boolean = true;
const PdfLinkFadeVisibleMs: number = 500;
const PdfLinkFadeOutMs: number = 1300;

interface PDFLinkSlotRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface PDFLinkControllerDependencies {
  viewerViewModel: PDFViewerViewModel;
  pageDataSource: PageStore;
  pageTurnController: PDFPageTurnController;
  getUIContext: () => UIContext;
  getMainSlots: () => PageViewSlot[];
  getMainSlotAt: (index: number) => PageViewSlot | undefined;
  isDocumentLoading: () => boolean;
  isDocumentReadOnly: () => boolean;
  isAnnotateModePreparing: () => boolean;
  isPanelGestureActive: () => boolean;
  isDualFingerActive: () => boolean;
  cancelLongPress: () => void;
  setSuppressSidePageFlipFromGesture: (value: boolean) => void;
  gotoPage: (targetIndex: number, deferSlideVisualReset?: boolean, recordJumpHistory?: boolean) => Promise<void>;
}

@ObservedV2
export class PDFLinkController {
  private readonly dependencies: PDFLinkControllerDependencies;
  private readonly linkJumpHistory: PDFLinkJumpHistory = new PDFLinkJumpHistory();
  private pdfLinkPressCandidateResetToken: number = 0;
  private pdfLinkDebugState: Map<string, string> = new Map();
  private pdfLinkFadeTimeoutId: number | undefined = undefined;

  /** 当前触摸序列是否始于 PDF 链接热区；用于避免父级长按/侧翻与链接点击交叉触发。 */
  @Trace pdfLinkPressCandidateActive: boolean = false;
  @Trace linkJumpCanGoBack: boolean = false;
  @Trace linkJumpCanGoForward: boolean = false;
  @Trace showLinkJumpHistory: boolean = false;
  @Trace linkJumpNavRevision: number = 0;
  @Trace pdfLinkVisualOpacity: number = 0;

  constructor(dependencies: PDFLinkControllerDependencies) {
    this.dependencies = dependencies;
  }

  clearPdfLinkFadeTimeout(): void {
    if (this.pdfLinkFadeTimeoutId !== undefined) {
      clearTimeout(this.pdfLinkFadeTimeoutId);
      this.pdfLinkFadeTimeoutId = undefined;
    }
  }

  private pdfRectToSlotRect(rect: PdfLinkRectangle, rawPageSize: Vector2, viewSize: Vector2): PDFLinkSlotRect | undefined {
    if (rawPageSize.x <= 0 || rawPageSize.y <= 0 || viewSize.x <= 0 || viewSize.y <= 0) {
      return undefined;
    }
    if (!Number.isFinite(rect.left) || !Number.isFinite(rect.right) ||
      !Number.isFinite(rect.bottom) || !Number.isFinite(rect.top)) {
      return undefined;
    }

    const left = Math.min(rect.left, rect.right);
    const right = Math.max(rect.left, rect.right);
    const bottom = Math.min(rect.bottom, rect.top);
    const top = Math.max(rect.bottom, rect.top);
    const x = left / rawPageSize.x * viewSize.x;
    const y = (1 - top / rawPageSize.y) * viewSize.y;
    const width = (right - left) / rawPageSize.x * viewSize.x;
    const height = (top - bottom) / rawPageSize.y * viewSize.y;

    if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(width) || !Number.isFinite(height) ||
      width <= 0 || height <= 0) {
      return undefined;
    }
    const slotRect: PDFLinkSlotRect = { x: x, y: y, width: width, height: height };
    return slotRect;
  }

  private logPdfLinkDebug(key: string, message: string): void {
    if (!PdfLinkDebugLogEnabled) {
      return;
    }
    const previous = this.pdfLinkDebugState.get(key);
    if (previous === message) {
      return;
    }
    this.pdfLinkDebugState.set(key, message);
    hilog.info(0, 'PDFView', 'PDFLinkDebug[' + key + '] ' + message);
  }

  applyPdfLinkVisualMode(showForCurrentPage: boolean): void {
    this.clearPdfLinkFadeTimeout();
    if (this.dependencies.viewerViewModel.linkVisualMode === 'hidden') {
      this.pdfLinkVisualOpacity = 0;
      return;
    }
    if (this.dependencies.viewerViewModel.linkVisualMode === 'always') {
      this.pdfLinkVisualOpacity = 1;
      return;
    }
    if (showForCurrentPage) {
      this.triggerPdfLinkVisualPageEnter();
    } else {
      this.pdfLinkVisualOpacity = 0;
    }
  }

  triggerPdfLinkVisualPageEnter(): void {
    this.clearPdfLinkFadeTimeout();
    if (this.dependencies.viewerViewModel.linkVisualMode === 'hidden') {
      this.pdfLinkVisualOpacity = 0;
      return;
    }
    if (this.dependencies.viewerViewModel.linkVisualMode === 'always') {
      this.pdfLinkVisualOpacity = 1;
      return;
    }

    this.pdfLinkVisualOpacity = 1;
    this.pdfLinkFadeTimeoutId = setTimeout(() => {
      this.pdfLinkFadeTimeoutId = undefined;
      this.dependencies.getUIContext().animateTo({
        duration: PdfLinkFadeOutMs,
        curve: Curve.EaseOut
      }, () => {
        this.pdfLinkVisualOpacity = 0;
      });
    }, PdfLinkFadeVisibleMs);
  }

  private getLinkOverlayRenderDisabledReason(): string {
    if (this.dependencies.viewerViewModel.annotateMode !== 'drag') {
      return 'annotateMode=' + this.dependencies.viewerViewModel.annotateMode;
    }
    if (this.dependencies.isDocumentLoading()) {
      return 'documentLoading';
    }
    if (this.dependencies.isDocumentReadOnly()) {
      return 'documentReadOnly';
    }
    if (this.dependencies.isAnnotateModePreparing()) {
      return 'annotatePreparing';
    }
    if (this.dependencies.isPanelGestureActive()) {
      return 'panelGestureActive';
    }
    return '';
  }

  private getLinkOverlayDisabledReason(): string {
    const renderReason = this.getLinkOverlayRenderDisabledReason();
    if (renderReason.length > 0) {
      return renderReason;
    }
    return this.dependencies.pageTurnController.getBusyDisabledReason();
  }

  private getPdfLinkActivationDisabledReason(): string {
    const overlayReason = this.getLinkOverlayDisabledReason();
    if (overlayReason.length > 0) {
      return overlayReason;
    }
    const slots = this.dependencies.getMainSlots();
    if (slots[0].loading || slots[1].loading || slots[2].loading) {
      return 'slotLoading=' + slots[0].loading.toString() + '/' +
        slots[1].loading.toString() + '/' + slots[2].loading.toString();
    }
    if (this.dependencies.isDualFingerActive()) {
      return 'dualFingerActive';
    }
    return '';
  }

  private isMainSlotCommittedVisible(viewIndex: number): boolean {
    if (viewIndex < 0 || viewIndex >= this.dependencies.viewerViewModel.displayedPageIndices.length) {
      return false;
    }
    if (viewIndex === 1) {
      return this.dependencies.viewerViewModel.shouldShowSecondSlot();
    }
    if (viewIndex === 2) {
      return this.dependencies.viewerViewModel.shouldShowThirdSlot();
    }
    return viewIndex === 0;
  }

  private getMainSlotViewSize(viewIndex: number): Vector2 {
    const slot = this.dependencies.getMainSlotAt(viewIndex);
    if (slot === undefined) {
      return Vec2(0, 0);
    }
    return slot.viewSize;
  }

  getLinkHitAreasForSlot(viewIndex: number): PDFLinkDisplayHitArea[] {
    if (!this.isMainSlotCommittedVisible(viewIndex)) {
      return [];
    }

    const pageIndex = this.dependencies.viewerViewModel.displayedPageIndices[viewIndex];
    if (pageIndex === undefined || pageIndex < 0 || pageIndex >= this.dependencies.pageDataSource.totalPageCount()) {
      return [];
    }

    const viewSize = this.getMainSlotViewSize(viewIndex);
    const rawPageSize = this.dependencies.pageDataSource.getPageRawSize(pageIndex);
    const links = this.dependencies.pageDataSource.getPageLinks(pageIndex);
    const hitAreas: PDFLinkDisplayHitArea[] = [];
    for (let i = 0; i < links.length; i++) {
      const link: PdfLinkAnnotation = links[i];
      const slotRect = this.pdfRectToSlotRect(link.rect, rawPageSize, viewSize);
      if (slotRect === undefined) {
        this.logPdfLinkDebug(
          'slot-' + viewIndex.toString() + '-link-' + i.toString(),
          'skip invalid display rect: page=' + pageIndex.toString() +
            ', raw=(' + rawPageSize.x.toString() + ',' + rawPageSize.y.toString() +
            '), view=(' + viewSize.x.toString() + ',' + viewSize.y.toString() +
            '), pdfRect=(' + link.rect.left.toString() + ',' + link.rect.bottom.toString() +
            ',' + link.rect.right.toString() + ',' + link.rect.top.toString() + ')'
        );
        continue;
      }
      const hitArea: PDFLinkDisplayHitArea = {
        id: pageIndex.toString() + '-' + (link.uniqueId ?? i).toString() + '-' +
          slotRect.x.toString() + '-' + slotRect.y.toString() + '-' +
          slotRect.width.toString() + '-' + slotRect.height.toString(),
        x: slotRect.x,
        y: slotRect.y,
        width: slotRect.width,
        height: slotRect.height,
        target: link.target
      };
      hitAreas.push(hitArea);
    }
    const overlayReason = this.getLinkOverlayRenderDisabledReason();
    this.logPdfLinkDebug(
      'slot-' + viewIndex.toString(),
      'page=' + pageIndex.toString() +
        ', raw=(' + rawPageSize.x.toString() + ',' + rawPageSize.y.toString() +
        '), view=(' + viewSize.x.toString() + ',' + viewSize.y.toString() +
        '), links=' + links.length.toString() +
        ', hitAreas=' + hitAreas.length.toString() +
        ', overlay=' + (overlayReason.length === 0 ? 'enabled' : ('disabled:' + overlayReason))
    );
    return hitAreas;
  }

  isLinkOverlayEnabled(): boolean {
    return this.getLinkOverlayRenderDisabledReason().length === 0;
  }

  isPdfLinkActivationAllowed(): boolean {
    return this.getPdfLinkActivationDisabledReason().length === 0;
  }

  handlePdfLinkPressStart(hitArea: PDFLinkDisplayHitArea): void {
    const disabledReason = this.getPdfLinkActivationDisabledReason();
    if (disabledReason.length > 0) {
      hilog.info(0, 'PDFView', 'PDF 链接按下被忽略: id=' + hitArea.id + ', reason=' + disabledReason);
      return;
    }
    this.pdfLinkPressCandidateResetToken++;
    this.pdfLinkPressCandidateActive = true;
    this.dependencies.cancelLongPress();
    this.dependencies.setSuppressSidePageFlipFromGesture(true);
    hilog.info(0, 'PDFView', 'PDF 链接按下候选开始: id=' + hitArea.id + ', target=' + hitArea.target.kind);
  }

  handlePdfLinkPressCancel(hitArea: PDFLinkDisplayHitArea): void {
    this.pdfLinkPressCandidateResetToken++;
    this.pdfLinkPressCandidateActive = false;
    this.dependencies.cancelLongPress();
    hilog.info(0, 'PDFView', 'PDF 链接按下候选取消: id=' + hitArea.id);
  }

  cancelPdfLinkPressCandidateForDrag(dx: number, dy: number): void {
    if (!this.pdfLinkPressCandidateActive) {
      return;
    }
    this.pdfLinkPressCandidateResetToken++;
    this.pdfLinkPressCandidateActive = false;
    this.dependencies.cancelLongPress();
    // Keep side-flip suppressed for this sequence: a drag that began on a link should not flip on release.
    this.dependencies.setSuppressSidePageFlipFromGesture(true);
    hilog.info(0, 'PDFView', 'PDF 链接按下候选因拖动取消: dx=' + dx.toString() + ', dy=' + dy.toString());
  }

  schedulePdfLinkPressCandidateReset(): void {
    const token = ++this.pdfLinkPressCandidateResetToken;
    setTimeout(() => {
      if (this.pdfLinkPressCandidateResetToken === token) {
        this.pdfLinkPressCandidateActive = false;
      }
    }, 0);
  }

  private canActivatePdfLinkFromCurrentGesture(): boolean {
    return this.pdfLinkPressCandidateActive && this.isPdfLinkActivationAllowed();
  }

  private openExternalPdfLinkUri(uri: string): void {
    const targetUri = uri.trim();
    const lowerUri = targetUri.toLowerCase();
    if (!lowerUri.startsWith('http://') && !lowerUri.startsWith('https://')) {
      hilog.warn(0, 'PDFView', '忽略不支持的 PDF 链接 URI: ' + uri);
      return;
    }

    try {
      const abilityContext = this.dependencies.getUIContext().getHostContext() as common.UIAbilityContext;
      abilityContext.openLink(targetUri)
        .catch((error: BusinessError) => {
          hilog.error(0, 'PDFView', '打开 PDF 外部链接失败: ' + error.code.toString() + ' ' + error.message);
        });
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0, 'PDFView', '打开 PDF 外部链接异常: ' + err.code.toString() + ' ' + err.message);
    }
  }

  activatePdfLink(hitArea: PDFLinkDisplayHitArea): void {
    if (!this.canActivatePdfLinkFromCurrentGesture()) {
      hilog.info(
        0,
        'PDFView',
        'PDF 链接激活被忽略: id=' + hitArea.id +
          ', candidate=' + this.pdfLinkPressCandidateActive.toString() +
          ', reason=' + this.getPdfLinkActivationDisabledReason()
      );
      this.pdfLinkPressCandidateResetToken++;
      this.pdfLinkPressCandidateActive = false;
      return;
    }
    this.pdfLinkPressCandidateResetToken++;
    this.pdfLinkPressCandidateActive = false;
    this.dependencies.cancelLongPress();
    this.dependencies.setSuppressSidePageFlipFromGesture(true);

    const target = hitArea.target;
    if (target.kind === 'gotoPage') {
      hilog.info(0, 'PDFView', 'PDF 链接激活: gotoPage=' + target.pageIndex.toString() + ', id=' + hitArea.id);
      void this.dependencies.gotoPage(target.pageIndex);
      return;
    }
    if (target.kind === 'uri') {
      hilog.info(0, 'PDFView', 'PDF 链接激活: uri=' + target.uri + ', id=' + hitArea.id);
      this.openExternalPdfLinkUri(target.uri);
      return;
    }
    hilog.warn(0, 'PDFView', '忽略未知 PDF 链接目标。');
  }

  syncLinkJumpNavState(): void {
    this.linkJumpCanGoBack = this.linkJumpHistory.canGoBack();
    this.linkJumpCanGoForward = this.linkJumpHistory.canGoForward();
    this.showLinkJumpHistory = this.linkJumpCanGoBack || this.linkJumpCanGoForward;
    this.linkJumpNavRevision++;
  }

  clearLinkJumpHistory(): void {
    this.linkJumpHistory.clear();
    this.syncLinkJumpNavState();
  }

  recordLinkJumpHistory(fromPageIndex: number, toPageIndex: number): void {
    this.linkJumpHistory.recordJump(fromPageIndex, toPageIndex);
    this.syncLinkJumpNavState();
  }

  navigatePdfLinkBack(): void {
    const target = this.linkJumpHistory.popBack(this.dependencies.viewerViewModel.currentPageIndex);
    if (target === undefined) {
      return;
    }
    this.syncLinkJumpNavState();
    void this.dependencies.gotoPage(target, false, false).then(() => this.syncLinkJumpNavState());
  }

  navigatePdfLinkForward(): void {
    const target = this.linkJumpHistory.popForward(this.dependencies.viewerViewModel.currentPageIndex);
    if (target === undefined) {
      return;
    }
    this.syncLinkJumpNavState();
    void this.dependencies.gotoPage(target, false, false).then(() => this.syncLinkJumpNavState());
  }
}
