import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'PerfHintSession';

type HintFn = () => Promise<void>;

let localFileHintActive: boolean = false;
let beginImpl: HintFn | undefined = undefined;
let endImpl: HintFn | undefined = undefined;

async function loadApi26Impl(): Promise<void> {
  if (beginImpl !== undefined && endImpl !== undefined) {
    return;
  }
  const ns: ESObject = await import('./PerfHintSessionApi26');
  beginImpl = ns.beginLocalFilePerfHintImpl as HintFn;
  endImpl = ns.endLocalFilePerfHintImpl as HintFn;
}

/** 打开文档前：提示系统进入本地文件处理加速。 */
export async function beginLocalFilePerfHint(): Promise<void> {
  if (localFileHintActive) {
    return;
  }
  if (deviceInfo.apiAvailable('26.0.0')) {
    localFileHintActive = true;
    try {
      await loadApi26Impl();
      const impl: HintFn | undefined = beginImpl;
      if (impl !== undefined) {
        await impl();
      }
    } catch (error) {
      hilog.warn(0, TAG, `perfHint BEGIN 失败: ${error}`);
    }
  }
}

/** 打开文档结束（成功、失败或取消密码）后结束提示。 */
export async function endLocalFilePerfHint(): Promise<void> {
  if (!localFileHintActive) {
    return;
  }
  localFileHintActive = false;
  if (deviceInfo.apiAvailable('26.0.0')) {
    try {
      await loadApi26Impl();
      const impl: HintFn | undefined = endImpl;
      if (impl !== undefined) {
        await impl();
      }
    } catch (error) {
      hilog.warn(0, TAG, `perfHint END 失败: ${error}`);
    }
  }
}
