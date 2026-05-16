import { pdfService } from '@kit.PDFKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

export interface PDFBookmarkListItem {
  id: string;
  title: string;
  pageIndex: number;
  depth: number;
}

interface PDFBookmarkControllerDependencies {
  getDocument: () => pdfService.PdfDocument;
  onTreeChanged?: () => void;
}

interface BookmarkInsertTarget {
  parent: pdfService.Bookmark | null;
  position: number;
  displayDepth: number;
}

@ObservedV2
export class PDFBookmarkController {
  private readonly dependencies: PDFBookmarkControllerDependencies;
  private readonly bookmarkById: Map<string, pdfService.Bookmark> = new Map();
  private readonly bookmarkStableIds: Map<pdfService.Bookmark, string> = new Map();

  @Trace entries: PDFBookmarkListItem[] = [];
  @Trace hasBookmarks: boolean = false;
  @Trace isDirty: boolean = false;
  @Trace selectedId: string = '';

  constructor(dependencies: PDFBookmarkControllerDependencies) {
    this.dependencies = dependencies;
  }

  refresh(): void {
    this.bookmarkById.clear();
    const nextEntries: PDFBookmarkListItem[] = [];
    const document = this.dependencies.getDocument();
    const roots = document.getRootBookmarks();
    for (const root of roots) {
      this.collectBookmarkTree(root, nextEntries, 0);
    }
    this.entries = [...nextEntries];
    this.hasBookmarks = nextEntries.length > 0;
    if (this.selectedId.length > 0 && !this.bookmarkById.has(this.selectedId)) {
      this.selectedId = '';
    }
    this.dependencies.onTreeChanged?.();
  }

  setSelectedId(id: string): void {
    this.selectedId = id;
  }

  getSelectedTitle(): string {
    const item = this.entries.find((entry: PDFBookmarkListItem) => entry.id === this.selectedId);
    return item?.title ?? '';
  }

  renameSelected(title: string): boolean {
    const trimmed = title.trim();
    if (trimmed.length === 0 || this.selectedId.length === 0) {
      return false;
    }
    const bookmark = this.bookmarkById.get(this.selectedId);
    if (bookmark === undefined || bookmark.isRootBookmark()) {
      return false;
    }
    const bookmarkInfo = bookmark.getBookmarkInfo();
    bookmarkInfo.title = trimmed;
    bookmark.setBookmarkInfo(bookmarkInfo);
    this.isDirty = true;
    this.refresh();
    return true;
  }

  addBookmarkAtPage(pageIndex: number, totalPageCount: number): boolean {
    if (pageIndex < 0 || pageIndex >= totalPageCount) {
      return false;
    }
    const document = this.dependencies.getDocument();
    const bookmark = document.createBookmark();
    const destInfo = bookmark.getDestInfo();
    destInfo.fitMode = pdfService.FitMode.FIT_MODE_XYZ;
    destInfo.pageIndex = pageIndex;
    bookmark.setDestInfo(destInfo);

    const defaultTitle = `第 ${pageIndex + 1} 页`;
    const bookmarkInfo = bookmark.getBookmarkInfo();
    bookmarkInfo.title = defaultTitle;
    bookmark.setBookmarkInfo(bookmarkInfo);

    const insertTarget = this.resolveInsertTarget(document);
    const inserted = document.insertBookmark(bookmark, insertTarget.parent, insertTarget.position);
    if (!inserted) {
      hilog.error(0, 'PDFView', '插入书签失败');
      return false;
    }

    const newId = util.generateRandomUUID(true);
    this.bookmarkStableIds.set(bookmark, newId);
    this.bookmarkById.set(newId, bookmark);
    this.selectedId = newId;
    this.entries = [...this.entries, {
      id: newId,
      title: defaultTitle,
      pageIndex,
      depth: insertTarget.displayDepth
    }];
    this.hasBookmarks = this.entries.length > 0;
    this.isDirty = true;
    this.dependencies.onTreeChanged?.();
    return true;
  }

  removeSelected(): boolean {
    if (this.selectedId.length === 0) {
      return false;
    }
    const bookmark = this.bookmarkById.get(this.selectedId);
    if (bookmark === undefined) {
      return false;
    }
    if (bookmark.isRootBookmark()) {
      hilog.warn(0, 'PDFView', '无法删除根书签节点');
      return false;
    }
    const document = this.dependencies.getDocument();
    const removed = document.removeBookmark(bookmark);
    if (!removed) {
      hilog.error(0, 'PDFView', '删除书签失败');
      return false;
    }
    this.bookmarkStableIds.delete(bookmark);
    this.isDirty = true;
    this.selectedId = '';
    this.refresh();
    return true;
  }

  markDocumentSaved(): void {
    this.isDirty = false;
    this.dependencies.onTreeChanged?.();
  }

  private collectBookmarkTree(bookmark: pdfService.Bookmark, items: PDFBookmarkListItem[], depth: number): void {
    if (!bookmark.isRootBookmark()) {
      const info = bookmark.getBookmarkInfo();
      const dest = bookmark.getDestInfo();
      const title = (info.title ?? '').trim();
      const pageIndex = this.normalizePageIndex(dest.pageIndex);
      const id = this.getStableBookmarkId(bookmark);
      this.bookmarkById.set(id, bookmark);
      items.push({
        id,
        title: title.length > 0 ? title : '未命名书签',
        pageIndex,
        depth
      });
    }
    if (bookmark.hasChild()) {
      const nextDepth = bookmark.isRootBookmark() ? depth : depth + 1;
      for (const child of bookmark.getChildren()) {
        this.collectBookmarkTree(child, items, nextDepth);
      }
    }
  }

  private getStableBookmarkId(bookmark: pdfService.Bookmark): string {
    const existing = this.bookmarkStableIds.get(bookmark);
    if (existing !== undefined) {
      return existing;
    }
    const id = util.generateRandomUUID(true);
    this.bookmarkStableIds.set(bookmark, id);
    return id;
  }

  private normalizePageIndex(rawIndex: number): number {
    if (!Number.isFinite(rawIndex)) {
      return 0;
    }
    return Math.max(0, Math.floor(rawIndex));
  }

  private resolveInsertTarget(document: pdfService.PdfDocument): BookmarkInsertTarget {
    const roots = document.getRootBookmarks();
    if (roots.length === 1 && roots[0].isRootBookmark()) {
      const root = roots[0];
      const childCount = root.hasChild() ? root.getChildren().length : 0;
      const target: BookmarkInsertTarget = {
        parent: root,
        position: childCount + 1,
        displayDepth: 0
      };
      return target;
    }
    const target: BookmarkInsertTarget = {
      parent: null,
      position: Math.max(1, roots.length + 1),
      displayDepth: 0
    };
    return target;
  }
}
