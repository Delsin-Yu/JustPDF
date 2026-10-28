#ifndef JUSTPDF_TUNER_YIN_H
#define JUSTPDF_TUNER_YIN_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    TUNER_SPECTRUM_BAND_COUNT = 20
};

typedef struct TunerYinConfig {
    float sampleRateHz;
    float pitchMinHz;
    float pitchMaxHz;
    float rmsGateThreshold;
    float yinThreshold;
    int windowSize;
} TunerYinConfig;

typedef struct TunerYinResult {
    float pitchHz;
    float rawEnvelope;
    float spectrumMagnitudes[TUNER_SPECTRUM_BAND_COUNT];
} TunerYinResult;

void TunerYin_Analyze(const float* samples, size_t sampleCount, const TunerYinConfig* config,
    TunerYinResult* result);

#ifdef __cplusplus
}
#endif

#endif
