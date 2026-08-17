/**
 * 沉浸式窗口下交互控件的避让边距（px）。
 * 合并状态栏 / 导航指示条。
 * 2in1 标题栏按钮只作为角落尺寸返回，不并入四边 inset。
 */

import { window } from '@kit.ArkUI';

export interface WindowSafeInsetsPx {
  top: number;
  bottom: number;
  left: number;
  right: number;
  /** 2in1 标题栏按钮区（vp），只避让角落，不并入四边 inset */
  titleWidthVp: number;
  titleHeightVp: number;
}

export function createEmptyWindowSafeInsetsPx(): WindowSafeInsetsPx {
  const insets: WindowSafeInsetsPx = {
    top: 0,
    bottom: 0,
    left: 0,
    right: 0,
    titleWidthVp: 0,
    titleHeightVp: 0
  };
  return insets;
}

function foldRectSize(insets: WindowSafeInsetsPx, area: window.AvoidArea): void {
  insets.top = Math.max(insets.top, area.topRect.height);
  insets.bottom = Math.max(insets.bottom, area.bottomRect.height);
  insets.left = Math.max(insets.left, area.leftRect.width);
  insets.right = Math.max(insets.right, area.rightRect.width);
}

function readTitleButtonSize(insets: WindowSafeInsetsPx, win: window.Window): void {
  try {
    const titleRect: window.TitleButtonRect = win.getTitleButtonRect();
    if (titleRect.width <= 0 || titleRect.height <= 0) {
      return;
    }
    insets.titleWidthVp = titleRect.width;
    insets.titleHeightVp = titleRect.height;
  } catch (_error) {
  }
}

export function readWindowSafeInsetsPx(win: window.Window): WindowSafeInsetsPx {
  const insets: WindowSafeInsetsPx = createEmptyWindowSafeInsetsPx();
  try {
    const systemArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    foldRectSize(insets, systemArea);
  } catch (_error) {
  }
  try {
    const navArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    insets.bottom = Math.max(insets.bottom, navArea.bottomRect.height);
  } catch (_error) {
  }
  readTitleButtonSize(insets, win);
  return insets;
}
