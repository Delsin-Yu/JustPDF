#include "tuner_engine.h"

#include "tuner_yin.h"

#include <condition_variable>
#include <mutex>
#include <thread>
#include <vector>

#include <hilog/log.h>
#include <ohaudio/native_audiocapturer.h>
#include <ohaudio/native_audiostreambuilder.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0000
#define LOG_TAG "PDFTunerNative"

namespace {
constexpr int32_t kSampleRateHz = 48000;
constexpr int32_t kChannelCount = 1;
constexpr int32_t kRingSize = 32768;
constexpr int32_t kRingMask = kRingSize - 1;
constexpr int32_t kDefaultWindowSize = 4096;
constexpr int32_t kLowWindowSize = 8192;
constexpr int32_t kHopSize = 1024;
constexpr float kTwoPi = 6.283185307179586f;

struct TunerEngineState {
    std::mutex mutex;
    std::mutex ringMutex;
    std::condition_variable ringCv;
    std::thread analysisThread;
    OH_AudioCapturer* capturer = nullptr;
    TunerEngineConfig config{};
    TunerEngineResultCallback resultCallback = nullptr;
    void* resultUserData = nullptr;
    std::vector<int16_t> captureRing;
    std::vector<float> processedRing;
    uint32_t captureWrite = 0;
    uint32_t captureRead = 0;
    uint32_t processedWrite = 0;
    uint32_t processedCount = 0;
    uint32_t hopAccumulated = 0;
    float highPassPrevInput = 0.0f;
    float highPassPrevOutput = 0.0f;
    float lowPassPrevOutput = 0.0f;
    bool running = false;
    bool threadStarted = false;
};

TunerEngineState g_engine;

int32_t ClampWindowSize(int32_t windowSize)
{
    if (windowSize >= kLowWindowSize) {
        return kLowWindowSize;
    }
    return kDefaultWindowSize;
}

float HighPassAlpha(float cutoffHz)
{
    if (cutoffHz <= 0.0f) {
        return 0.0f;
    }
    const float dt = 1.0f / static_cast<float>(kSampleRateHz);
    const float rc = 1.0f / (kTwoPi * cutoffHz);
    return rc / (rc + dt);
}

float LowPassAlpha(float cutoffHz)
{
    if (cutoffHz <= 0.0f) {
        return 1.0f;
    }
    const float dt = 1.0f / static_cast<float>(kSampleRateHz);
    const float rc = 1.0f / (kTwoPi * cutoffHz);
    return dt / (rc + dt);
}

void ResetFilterLocked()
{
    g_engine.highPassPrevInput = 0.0f;
    g_engine.highPassPrevOutput = 0.0f;
    g_engine.lowPassPrevOutput = 0.0f;
}

void InitDefaultConfigLocked()
{
    g_engine.config.pitchMinHz = 27.5f;
    g_engine.config.pitchMaxHz = 1760.0f;
    g_engine.config.highPassHz = 22.0f;
    g_engine.config.lowPassHz = 5200.0f;
    g_engine.config.rmsGateThreshold = 0.008f;
    g_engine.config.windowSize = kDefaultWindowSize;
}

float FilterSample(float sample, const TunerEngineConfig& config)
{
    float next = sample;
    if (config.highPassHz > 0.0f) {
        const float alpha = HighPassAlpha(config.highPassHz);
        const float highPass = alpha * (g_engine.highPassPrevOutput + next - g_engine.highPassPrevInput);
        g_engine.highPassPrevInput = next;
        g_engine.highPassPrevOutput = highPass;
        next = highPass;
    }
    if (config.lowPassHz > 0.0f) {
        const float alpha = LowPassAlpha(config.lowPassHz);
        g_engine.lowPassPrevOutput += alpha * (next - g_engine.lowPassPrevOutput);
        next = g_engine.lowPassPrevOutput;
    }
    return next;
}

void PublishResult(const TunerYinResult& yinResult)
{
    TunerEngineResultCallback callback = nullptr;
    void* userData = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_engine.mutex);
        callback = g_engine.resultCallback;
        userData = g_engine.resultUserData;
    }
    if (callback == nullptr) {
        return;
    }
    TunerEngineResult result{};
    result.pitchHz = yinResult.pitchHz;
    result.rawEnvelope = yinResult.rawEnvelope;
    for (int i = 0; i < TUNER_ENGINE_SPECTRUM_BAND_COUNT; ++i) {
        result.spectrumMagnitudes[i] = yinResult.spectrumMagnitudes[i];
    }
    callback(&result, userData);
}

void AnalyzeAvailableSamples()
{
    TunerEngineConfig config{};
    {
        std::lock_guard<std::mutex> lock(g_engine.mutex);
        config = g_engine.config;
        config.windowSize = ClampWindowSize(config.windowSize);
    }

    std::vector<int16_t> incoming;
    {
        std::unique_lock<std::mutex> lock(g_engine.ringMutex);
        g_engine.ringCv.wait(lock, []() {
            if (!g_engine.running) {
                return true;
            }
            return (g_engine.captureWrite - g_engine.captureRead) >= static_cast<uint32_t>(kHopSize);
        });
        if (!g_engine.running) {
            return;
        }
        const uint32_t available = g_engine.captureWrite - g_engine.captureRead;
        incoming.resize(static_cast<size_t>(available));
        for (uint32_t i = 0; i < available; ++i) {
            incoming[static_cast<size_t>(i)] =
                g_engine.captureRing[static_cast<size_t>((g_engine.captureRead + i) & kRingMask)];
        }
        g_engine.captureRead += available;
    }

    for (size_t i = 0; i < incoming.size(); ++i) {
        const float filtered = FilterSample(static_cast<float>(incoming[i]) / 32768.0f, config);
        g_engine.processedRing[static_cast<size_t>(g_engine.processedWrite & kRingMask)] = filtered;
        g_engine.processedWrite += 1;
        if (g_engine.processedCount < static_cast<uint32_t>(kRingSize)) {
            g_engine.processedCount += 1;
        }
        g_engine.hopAccumulated += 1;
    }

    if (g_engine.processedCount < static_cast<uint32_t>(config.windowSize) ||
        g_engine.hopAccumulated < static_cast<uint32_t>(kHopSize)) {
        return;
    }
    g_engine.hopAccumulated = 0;

    std::vector<float> window(static_cast<size_t>(config.windowSize), 0.0f);
    const uint32_t start = g_engine.processedWrite - static_cast<uint32_t>(config.windowSize);
    for (int32_t i = 0; i < config.windowSize; ++i) {
        window[static_cast<size_t>(i)] =
            g_engine.processedRing[static_cast<size_t>((start + static_cast<uint32_t>(i)) & kRingMask)];
    }

    TunerYinConfig yinConfig{};
    yinConfig.sampleRateHz = static_cast<float>(kSampleRateHz);
    yinConfig.pitchMinHz = config.pitchMinHz;
    yinConfig.pitchMaxHz = config.pitchMaxHz;
    yinConfig.rmsGateThreshold = config.rmsGateThreshold;
    yinConfig.yinThreshold = 0.10f;
    yinConfig.windowSize = config.windowSize;

    TunerYinResult yinResult{};
    TunerYin_Analyze(window.data(), static_cast<size_t>(config.windowSize), &yinConfig, &yinResult);
    PublishResult(yinResult);
}

void AnalysisLoop()
{
    while (true) {
        {
            std::lock_guard<std::mutex> lock(g_engine.mutex);
            if (!g_engine.running) {
                break;
            }
        }
        AnalyzeAvailableSamples();
    }
}

void OnReadData(OH_AudioCapturer* capturer, void* userData, void* audioData, int32_t audioDataSize)
{
    (void)capturer;
    (void)userData;
    if (audioData == nullptr || audioDataSize <= 0) {
        return;
    }
    const int32_t sampleCount = audioDataSize / static_cast<int32_t>(sizeof(int16_t));
    if (sampleCount <= 0) {
        return;
    }
    const int16_t* samples = static_cast<const int16_t*>(audioData);
    std::lock_guard<std::mutex> lock(g_engine.ringMutex);
    if (!g_engine.running) {
        return;
    }
    for (int32_t i = 0; i < sampleCount; ++i) {
        g_engine.captureRing[static_cast<size_t>(g_engine.captureWrite & kRingMask)] = samples[i];
        g_engine.captureWrite += 1;
    }
    if ((g_engine.captureWrite - g_engine.captureRead) > static_cast<uint32_t>(kRingSize)) {
        g_engine.captureRead = g_engine.captureWrite - static_cast<uint32_t>(kRingSize);
    }
    g_engine.ringCv.notify_one();
}

void OnCapturerError(OH_AudioCapturer* capturer, void* userData, OH_AudioStream_Result error)
{
    (void)capturer;
    (void)userData;
    OH_LOG_ERROR(LOG_APP, "调音器采集异常 error=%{public}d", static_cast<int>(error));
}

bool CreateCapturerLocked()
{
    if (g_engine.capturer != nullptr) {
        return true;
    }
    OH_AudioStreamBuilder* builder = nullptr;
    OH_AudioStream_Result result = OH_AudioStreamBuilder_Create(&builder, AUDIOSTREAM_TYPE_CAPTURER);
    if (result != AUDIOSTREAM_SUCCESS || builder == nullptr) {
        OH_LOG_ERROR(LOG_APP, "调音器构造器创建失败 result=%{public}d", static_cast<int>(result));
        return false;
    }
    OH_AudioStreamBuilder_SetSamplingRate(builder, kSampleRateHz);
    OH_AudioStreamBuilder_SetChannelCount(builder, kChannelCount);
    OH_AudioStreamBuilder_SetSampleFormat(builder, AUDIOSTREAM_SAMPLE_S16LE);
    OH_AudioStreamBuilder_SetEncodingType(builder, AUDIOSTREAM_ENCODING_TYPE_RAW);
    OH_AudioStreamBuilder_SetCapturerInfo(builder, AUDIOSTREAM_SOURCE_TYPE_MIC);
    OH_AudioStreamBuilder_SetLatencyMode(builder, AUDIOSTREAM_LATENCY_MODE_NORMAL);
    OH_AudioStreamBuilder_SetCapturerReadDataCallback(builder, OnReadData, nullptr);
    OH_AudioStreamBuilder_SetCapturerErrorCallback(builder, OnCapturerError, nullptr);
    result = OH_AudioStreamBuilder_GenerateCapturer(builder, &g_engine.capturer);
    OH_AudioStreamBuilder_Destroy(builder);
    if (result != AUDIOSTREAM_SUCCESS || g_engine.capturer == nullptr) {
        OH_LOG_ERROR(LOG_APP, "调音器采集器创建失败 result=%{public}d", static_cast<int>(result));
        g_engine.capturer = nullptr;
        return false;
    }
    return true;
}

void ReleaseCapturer(OH_AudioCapturer* capturer)
{
    if (capturer == nullptr) {
        return;
    }
    OH_AudioCapturer_Stop(capturer);
    OH_AudioCapturer_Release(capturer);
}

void EnsureRings()
{
    if (g_engine.captureRing.size() != static_cast<size_t>(kRingSize)) {
        g_engine.captureRing.assign(static_cast<size_t>(kRingSize), 0);
    }
    if (g_engine.processedRing.size() != static_cast<size_t>(kRingSize)) {
        g_engine.processedRing.assign(static_cast<size_t>(kRingSize), 0.0f);
    }
}

void ResetRingsLocked()
{
    g_engine.captureWrite = 0;
    g_engine.captureRead = 0;
    g_engine.processedWrite = 0;
    g_engine.processedCount = 0;
    g_engine.hopAccumulated = 0;
    ResetFilterLocked();
}

void StopMicInternal()
{
    OH_AudioCapturer* capturer = nullptr;
    std::thread joining;
    {
        std::lock_guard<std::mutex> lock(g_engine.mutex);
        capturer = g_engine.capturer;
        g_engine.capturer = nullptr;
        g_engine.running = false;
        if (g_engine.threadStarted && g_engine.analysisThread.joinable()) {
            joining = std::move(g_engine.analysisThread);
        }
        g_engine.threadStarted = false;
        ResetRingsLocked();
    }
    {
        std::lock_guard<std::mutex> lock(g_engine.ringMutex);
        g_engine.ringCv.notify_all();
    }
    if (joining.joinable()) {
        joining.join();
    }
    ReleaseCapturer(capturer);
}
} // namespace

int32_t TunerEngine_SetConfig(const TunerEngineConfig* config)
{
    std::lock_guard<std::mutex> lock(g_engine.mutex);
    if (g_engine.config.pitchMinHz <= 0.0f) {
        InitDefaultConfigLocked();
    }
    if (config == nullptr) {
        return -1;
    }
    g_engine.config = *config;
    g_engine.config.windowSize = ClampWindowSize(config->windowSize);
    ResetFilterLocked();
    return 0;
}

int32_t TunerEngine_SetResultCallback(TunerEngineResultCallback callback, void* userData)
{
    std::lock_guard<std::mutex> lock(g_engine.mutex);
    g_engine.resultCallback = callback;
    g_engine.resultUserData = userData;
    return 0;
}

int32_t TunerEngine_StartMic(void)
{
    {
        std::lock_guard<std::mutex> lock(g_engine.mutex);
        if (g_engine.running && g_engine.capturer != nullptr) {
            return 0;
        }
    }
    StopMicInternal();

    OH_AudioCapturer* capturer = nullptr;
    bool threadStarted = false;
    {
        std::lock_guard<std::mutex> lock(g_engine.mutex);
        EnsureRings();
        if (g_engine.config.pitchMinHz <= 0.0f) {
            InitDefaultConfigLocked();
        }
        if (!CreateCapturerLocked()) {
            return -1;
        }
        ResetRingsLocked();
        g_engine.running = true;
        capturer = g_engine.capturer;
        try {
            g_engine.analysisThread = std::thread(AnalysisLoop);
            g_engine.threadStarted = true;
            threadStarted = true;
        } catch (...) {
            g_engine.running = false;
            g_engine.capturer = nullptr;
            g_engine.threadStarted = false;
            OH_LOG_ERROR(LOG_APP, "调音器分析线程启动失败");
        }
    }
    if (!threadStarted) {
        ReleaseCapturer(capturer);
        return -1;
    }

    const OH_AudioStream_Result startResult = OH_AudioCapturer_Start(capturer);
    if (startResult != AUDIOSTREAM_SUCCESS) {
        OH_LOG_ERROR(LOG_APP, "调音器采集启动失败 result=%{public}d", static_cast<int>(startResult));
        StopMicInternal();
        return static_cast<int32_t>(startResult);
    }
    OH_LOG_INFO(LOG_APP, "调音器原生采集已启动 window=%{public}d", g_engine.config.windowSize);
    return 0;
}

void TunerEngine_StopMic(void)
{
    StopMicInternal();
}
