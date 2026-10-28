import { StylusFrameBoost } from '@kit.Penkit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'StylusFrameBoost';

let boost: StylusFrameBoost | undefined = undefined;

function touchTypeToBoostAction(type: TouchType): number {
  if (type === TouchType.Down) {
    return 0;
  }
  if (type === TouchType.Up) {
    return 1;
  }
  if (type === TouchType.Move) {
    return 2;
  }
  return 3;
}

/** 仅由 StylusFrameBoostHelper 在 API 26 动态导入。 */
export function notifyStylusFrameBoostImpl(event: TouchEvent): void {
  if (deviceInfo.apiAvailable('26.0.0')) {
    try {
      if (boost === undefined) {
        boost = new StylusFrameBoost();
      }
      boost.forceRefreshOneFrame(touchTypeToBoostAction(event.type));
    } catch (error) {
      hilog.warn(0, TAG, `跟手性加速失败: ${error}`);
    }
  }
}
