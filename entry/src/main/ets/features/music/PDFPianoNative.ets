import { hilog } from '@kit.PerformanceAnalysisKit';
import pianoNative from 'libpiano.so';

export function prepareNativePiano(): boolean {
  try {
    return pianoNative.pianoPrepare() === 0;
  } catch (error) {
    hilog.warn(0, 'PDFPianoNative', `准备原生键盘引擎失败: ${error}`);
    return false;
  }
}

export function startNativePiano(): boolean {
  try {
    return pianoNative.pianoStart() === 0;
  } catch (error) {
    hilog.warn(0, 'PDFPianoNative', `启动原生键盘引擎失败: ${error}`);
    return false;
  }
}

export function stopNativePiano(): void {
  try {
    pianoNative.pianoStop();
  } catch (error) {
    hilog.warn(0, 'PDFPianoNative', `停止原生键盘引擎失败: ${error}`);
  }
}

export function releaseNativePiano(): void {
  try {
    pianoNative.pianoRelease();
  } catch (error) {
    hilog.warn(0, 'PDFPianoNative', `释放原生键盘引擎失败: ${error}`);
  }
}

export function nativePianoNoteOn(midi: number, frequencyHz: number): void {
  try {
    pianoNative.pianoNoteOn(midi, frequencyHz);
  } catch (error) {
    hilog.warn(0, 'PDFPianoNative', `原生键盘 noteOn 失败: ${error}`);
  }
}

export function nativePianoNoteOff(midi: number): void {
  try {
    pianoNative.pianoNoteOff(midi);
  } catch (error) {
    hilog.warn(0, 'PDFPianoNative', `原生键盘 noteOff 失败: ${error}`);
  }
}

export function nativePianoAllNotesOff(immediate: boolean): void {
  try {
    pianoNative.pianoAllNotesOff(immediate);
  } catch (error) {
    hilog.warn(0, 'PDFPianoNative', `原生键盘 allNotesOff 失败: ${error}`);
  }
}

export function nativePianoRetune(midi: number, frequencyHz: number): void {
  try {
    pianoNative.pianoRetune(midi, frequencyHz);
  } catch (error) {
    hilog.warn(0, 'PDFPianoNative', `原生键盘 retune 失败: ${error}`);
  }
}

export function nativePianoSetProgram(program: number): void {
  try {
    pianoNative.pianoSetProgram(program);
  } catch (error) {
    hilog.warn(0, 'PDFPianoNative', `原生键盘 setProgram 失败: ${error}`);
  }
}

export function nativePianoSetTunerTone(frequencyHz: number, amplitude: number): void {
  try {
    pianoNative.pianoSetTunerTone(frequencyHz, amplitude);
  } catch (error) {
    hilog.warn(0, 'PDFPianoNative', `原生调音器参考音失败: ${error}`);
  }
}
