import { schedulingOptimization } from '@kit.FASTKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'PerfHintSession';

/** 仅由 PerfHintSession 在 API 26 动态导入，避免 API 24 加载 FASTKit。 */
export async function beginLocalFilePerfHintImpl(): Promise<void> {
  if (deviceInfo.apiAvailable('26.0.0')) {
    const config: schedulingOptimization.PerfHintConfig = {
      sceneType: schedulingOptimization.SceneType.LOCAL_FILE_PROCESSING,
      sceneState: schedulingOptimization.SceneState.BEGIN,
      durationType: schedulingOptimization.DurationType.MEDIUM,
      tids: []
    };
    try {
      await schedulingOptimization.perfHint(config);
    } catch (error) {
      hilog.warn(0, TAG, `perfHint BEGIN 失败: ${error}`);
    }
  }
}

export async function endLocalFilePerfHintImpl(): Promise<void> {
  if (deviceInfo.apiAvailable('26.0.0')) {
    const config: schedulingOptimization.PerfHintConfig = {
      sceneType: schedulingOptimization.SceneType.LOCAL_FILE_PROCESSING,
      sceneState: schedulingOptimization.SceneState.END,
      durationType: schedulingOptimization.DurationType.MEDIUM,
      tids: []
    };
    try {
      await schedulingOptimization.perfHint(config);
    } catch (error) {
      hilog.warn(0, TAG, `perfHint END 失败: ${error}`);
    }
  }
}
