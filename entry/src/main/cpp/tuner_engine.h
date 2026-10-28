#ifndef JUSTPDF_TUNER_ENGINE_H
#define JUSTPDF_TUNER_ENGINE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    TUNER_ENGINE_SPECTRUM_BAND_COUNT = 20
};

typedef struct TunerEngineConfig {
    float pitchMinHz;
    float pitchMaxHz;
    float highPassHz;
    float lowPassHz;
    float rmsGateThreshold;
    int32_t windowSize;
} TunerEngineConfig;

typedef struct TunerEngineResult {
    float spectrumMagnitudes[TUNER_ENGINE_SPECTRUM_BAND_COUNT];
    float pitchHz;
    float rawEnvelope;
} TunerEngineResult;

typedef void (*TunerEngineResultCallback)(const TunerEngineResult* result, void* userData);

int32_t TunerEngine_SetConfig(const TunerEngineConfig* config);
int32_t TunerEngine_SetResultCallback(TunerEngineResultCallback callback, void* userData);
int32_t TunerEngine_StartMic(void);
void TunerEngine_StopMic(void);

#ifdef __cplusplus
}
#endif

#endif
