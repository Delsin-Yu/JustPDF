import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'ViewerKeepAwake';

/**
 * 阅读页在前台时保持常亮；离开或进后台后恢复系统超时灭屏。
 */
export function setViewerKeepAwake(targetWindow: window.Window, keepOn: boolean): void {
  targetWindow.setWindowKeepScreenOn(keepOn).then(() => {
    hilog.info(0, TAG, keepOn ? '阅读页常亮已打开' : '阅读页常亮已关闭');
  }).catch((error: Error) => {
    hilog.warn(0, TAG, `设置阅读页常亮失败 keepOn=${keepOn}: ${error}`);
  });
}
