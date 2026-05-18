/** PDF 内链跳转的双栈历史（后退 / 前进）。 */
export class PDFLinkJumpHistory {
  private backStack: number[] = [];
  private forwardStack: number[] = [];

  clear(): void {
    this.backStack = [];
    this.forwardStack = [];
  }

  /** 用户主动跳转到新页时调用；会清空前进栈。 */
  recordJump(fromPageIndex: number, toPageIndex: number): void {
    if (fromPageIndex === toPageIndex) {
      return;
    }
    this.backStack.push(fromPageIndex);
    this.forwardStack = [];
  }

  canGoBack(): boolean {
    return this.backStack.length > 0;
  }

  canGoForward(): boolean {
    return this.forwardStack.length > 0;
  }

  /** 后退：弹出后退栈顶页，并将当前页压入前进栈。 */
  popBack(currentPageIndex: number): number | undefined {
    const backLen = this.backStack.length;
    if (backLen === 0) {
      return undefined;
    }
    const target = this.backStack[backLen - 1];
    this.backStack = this.backStack.slice(0, backLen - 1);
    this.forwardStack = [...this.forwardStack, currentPageIndex];
    return target;
  }

  /** 前进：弹出前进栈顶页，并将当前页压入后退栈。 */
  popForward(currentPageIndex: number): number | undefined {
    const forwardLen = this.forwardStack.length;
    if (forwardLen === 0) {
      return undefined;
    }
    const target = this.forwardStack[forwardLen - 1];
    this.forwardStack = this.forwardStack.slice(0, forwardLen - 1);
    this.backStack = [...this.backStack, currentPageIndex];
    return target;
  }
}
