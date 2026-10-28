import { hilog } from '@kit.PerformanceAnalysisKit';
import tunerNative from 'libtuner.so';

export interface TunerNativeAnalysisResult {
  spectrumMagnitudes: number[];
  pitchHz: number;
  rawEnvelope: number;
}

export type TunerNativeResultCallback = (result: TunerNativeAnalysisResult) => void;

export function nativeTunerStartMic(): boolean {
  try {
    return tunerNative.tunerStartMic() === 0;
  } catch (error) {
    hilog.warn(0, 'PDFTunerNative', `启动原生调音器采集失败: ${error}`);
    return false;
  }
}

export function nativeTunerStopMic(): void {
  try {
    tunerNative.tunerStopMic();
  } catch (error) {
    hilog.warn(0, 'PDFTunerNative', `停止原生调音器采集失败: ${error}`);
  }
}

export function nativeTunerSetConfig(
  pitchMinHz: number,
  pitchMaxHz: number,
  highPassHz: number,
  lowPassHz: number,
  rmsGateThreshold: number,
  windowSize: number,
): boolean {
  try {
    return tunerNative.tunerSetConfig(
      pitchMinHz,
      pitchMaxHz,
      highPassHz,
      lowPassHz,
      rmsGateThreshold,
      windowSize,
    ) === 0;
  } catch (error) {
    hilog.warn(0, 'PDFTunerNative', `设置原生调音器参数失败: ${error}`);
    return false;
  }
}

export function nativeTunerSetResultCallback(callback: TunerNativeResultCallback): boolean {
  try {
    return tunerNative.tunerSetResultCallback(callback) === 0;
  } catch (error) {
    hilog.warn(0, 'PDFTunerNative', `注册原生调音器回调失败: ${error}`);
    return false;
  }
}

export function nativeTunerClearResultCallback(): void {
  try {
    tunerNative.tunerClearResultCallback();
  } catch (error) {
    hilog.warn(0, 'PDFTunerNative', `清除原生调音器回调失败: ${error}`);
  }
}
