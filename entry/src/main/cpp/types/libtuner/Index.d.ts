export interface TunerNativeAnalysisResult {
  spectrumMagnitudes: number[];
  pitchHz: number;
  rawEnvelope: number;
}

export const tunerStartMic: () => number;
export const tunerStopMic: () => number;
export const tunerSetConfig: (
  pitchMinHz: number,
  pitchMaxHz: number,
  highPassHz: number,
  lowPassHz: number,
  rmsGateThreshold: number,
  windowSize: number
) => number;
export const tunerSetResultCallback: (callback: (result: TunerNativeAnalysisResult) => void) => number;
export const tunerClearResultCallback: () => number;
