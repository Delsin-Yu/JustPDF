import { pdfService } from '@kit.PDFKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export interface PdfLinkRectangle {
  left: number;
  right: number;
  bottom: number;
  top: number;
}

export interface PdfLinkDestination {
  pageIndex: number;
  fitMode: pdfService.FitMode;
  left?: number;
  top?: number;
  right?: number;
  bottom?: number;
  zoom?: number;
}

export interface PdfGotoPageLinkTarget {
  kind: 'gotoPage';
  pageIndex: number;
  destination?: PdfLinkDestination;
}

export interface PdfUriLinkTarget {
  kind: 'uri';
  uri: string;
}

export interface PdfUnknownLinkTarget {
  kind: 'unknown';
  actionType?: pdfService.PdfActionType;
}

export type PdfLinkTarget = PdfGotoPageLinkTarget | PdfUriLinkTarget | PdfUnknownLinkTarget;

export interface PdfLinkAnnotation {
  rect: PdfLinkRectangle;
  target: PdfLinkTarget;
  uniqueId?: string;
  highlightMode?: pdfService.HighlightMode;
  color?: number;
}

export function normalizeLinkRectangle(annotationInfo: pdfService.LinkAnnotationInfo): PdfLinkRectangle | undefined {
  if (!Number.isFinite(annotationInfo.left) || !Number.isFinite(annotationInfo.right) ||
    !Number.isFinite(annotationInfo.bottom) || !Number.isFinite(annotationInfo.top)) {
    return undefined;
  }

  return {
    left: Math.min(annotationInfo.left, annotationInfo.right),
    right: Math.max(annotationInfo.left, annotationInfo.right),
    bottom: Math.min(annotationInfo.bottom, annotationInfo.top),
    top: Math.max(annotationInfo.bottom, annotationInfo.top)
  };
}

export function cloneDestInfo(destInfo: pdfService.DestInfo): PdfLinkDestination {
  const destination: PdfLinkDestination = {
    pageIndex: destInfo.pageIndex,
    fitMode: destInfo.fitMode
  };

  if (destInfo.left !== undefined && Number.isFinite(destInfo.left)) {
    destination.left = destInfo.left;
  }
  if (destInfo.top !== undefined && Number.isFinite(destInfo.top)) {
    destination.top = destInfo.top;
  }
  if (destInfo.right !== undefined && Number.isFinite(destInfo.right)) {
    destination.right = destInfo.right;
  }
  if (destInfo.bottom !== undefined && Number.isFinite(destInfo.bottom)) {
    destination.bottom = destInfo.bottom;
  }
  if (destInfo.zoom !== undefined && Number.isFinite(destInfo.zoom)) {
    destination.zoom = destInfo.zoom;
  }

  return destination;
}

export function normalizeGoToLinkTarget(action: pdfService.PdfActionGoTo): PdfLinkTarget {
  const destInfo = action.destInfo;
  if (destInfo === undefined || !Number.isFinite(destInfo.pageIndex)) {
    return { kind: 'unknown', actionType: action.type };
  }

  return {
    kind: 'gotoPage',
    pageIndex: destInfo.pageIndex,
    destination: cloneDestInfo(destInfo)
  };
}

export function normalizeLinkTarget(action: pdfService.PdfAction | undefined): PdfLinkTarget {
  if (action === undefined) {
    return { kind: 'unknown' };
  }

  if (action.type === pdfService.PdfActionType.GOTO) {
    return normalizeGoToLinkTarget(action as pdfService.PdfActionGoTo);
  }

  if (action.type === pdfService.PdfActionType.HYPERLINK) {
    const hyperlinkAction = action as pdfService.PdfActionHyperlink;
    if (hyperlinkAction.hyperlink === undefined || hyperlinkAction.hyperlink.length === 0) {
      return { kind: 'unknown', actionType: action.type };
    }
    return {
      kind: 'uri',
      uri: hyperlinkAction.hyperlink
    };
  }

  return { kind: 'unknown', actionType: action.type };
}

/** 从 PdfPage 批注列表提取可用链接（供 PageInfo 调用）。 */
export function extractPageLinksFromAnnotations(
  annotations: pdfService.PdfAnnotation[],
  localPageIndex: number
): PdfLinkAnnotation[] {
  const links: PdfLinkAnnotation[] = [];
  let linkAnnotationCount = 0;

  for (const annotation of annotations) {
    if (annotation.type !== pdfService.AnnotationType.LINK) {
      continue;
    }
    linkAnnotationCount++;

    try {
      const annotationInfo = annotation.getAnnotationInfo() as pdfService.LinkAnnotationInfo;
      const rect = normalizeLinkRectangle(annotationInfo);
      if (rect === undefined) {
        hilog.warn(0, 'PageInfo', `PDF 链接批注矩形无效: page=${localPageIndex}, uniqueId=${annotation.uniqueId}`);
        continue;
      }

      const target = normalizeLinkTarget(annotationInfo.action);
      const link: PdfLinkAnnotation = {
        rect: rect,
        target: target,
        uniqueId: annotationInfo.uniqueId && annotationInfo.uniqueId.length > 0 ? annotationInfo.uniqueId : annotation.uniqueId,
        highlightMode: annotationInfo.highlightMode,
        color: annotationInfo.color
      };
      links.push(link);
      hilog.info(0, 'PageInfo', `PDF 链接批注: page=${localPageIndex}, uniqueId=${link.uniqueId ?? ''}, rect=(${rect.left},${rect.bottom},${rect.right},${rect.top}), target=${target.kind}`);
    } catch (error) {
      hilog.warn(0, 'PageInfo', `读取页面 ${localPageIndex} 链接批注失败: ${error}`);
    }
  }

  hilog.info(0, 'PageInfo', `PDF 链接扫描完成: page=${localPageIndex}, annotations=${annotations.length}, linkAnnotations=${linkAnnotationCount}, usableLinks=${links.length}`);
  return links;
}
