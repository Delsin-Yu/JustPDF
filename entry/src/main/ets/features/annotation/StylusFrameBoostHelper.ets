import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'StylusFrameBoost';

type BoostFn = (event: TouchEvent) => void;

let impl: BoostFn | undefined = undefined;
let loading: boolean = false;

/**
 * 批注 Canvas 触摸时提示系统提前刷一帧。API 26+ 且已接笔时才有效。
 * StylusFrameBoost 在 API 24 上不存在，必须动态导入，不能出现在 PDFView 静态加载链。
 */
export function notifyStylusFrameBoost(event: TouchEvent): void {
  if (event.sourceTool !== SourceTool.Pen && event.sourceTool !== SourceTool.MOUSE &&
    event.sourceTool !== SourceTool.Finger) {
    return;
  }
  if (deviceInfo.apiAvailable('26.0.0')) {
    if (impl !== undefined) {
      impl(event);
      return;
    }
    if (loading) {
      return;
    }
    loading = true;
    import('./StylusFrameBoostApi26').then((ns: ESObject) => {
      const loaded: BoostFn = ns.notifyStylusFrameBoostImpl as BoostFn;
      impl = loaded;
      loading = false;
      loaded(event);
    }).catch((error: Error) => {
      loading = false;
      hilog.warn(0, TAG, `加载跟手性加速失败: ${error}`);
    });
  }
}
