#include "piano_engine.h"

#include <cmath>
#include <cstring>
#include <mutex>

#include <hilog/log.h>
#include <ohaudio/native_audiorenderer.h>
#include <ohaudio/native_audiostreambuilder.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0000
#define LOG_TAG "PDFPianoNative"

namespace {
constexpr int32_t kSampleRateHz = 48000;
constexpr int32_t kChannelCount = 2;
constexpr int32_t kCallbackFrames = 240;
constexpr int32_t kMaxVoices = 12;
constexpr int32_t kMaxPartials = 12;
constexpr int32_t kSineTableSize = 2048;
constexpr int32_t kSineTableMask = 2047;
constexpr int32_t kOrganAttackFrames = 288;
constexpr int32_t kPianoAttackFrames = 384;
constexpr int32_t kMaxModes = 16;
constexpr int32_t kTwinModes = 3;
constexpr int32_t kProgramPiano = 0;
constexpr int32_t kProgramOrgan = 1;
constexpr int32_t kProgramSquare = 2;
constexpr float kPi = 3.141592653589793f;
constexpr float kTwoPi = 6.283185307179586f;
constexpr float kNyquistLimitHz = 18000.0f;
constexpr float kPeakLimitStart = 0.92f;
constexpr float kOutputScale = 0.97f;
constexpr float kVoicePeakTarget = 0.78f;
constexpr float kCompThreshold = 0.64f;
constexpr float kCompAttack = 0.0069f;
constexpr float kCompRelease = 0.00030f;
constexpr float kNormLoudness = 0.30f;
constexpr float kNormAttack = 0.0012f;
constexpr float kNormRelease = 0.0028f;
constexpr float kMakeup = 1.18f;
constexpr float kTunerFade = 0.0024f;
constexpr int16_t kMaxAmplitude = 32767;

enum VoiceState {
    VOICE_ATTACK = 0,
    VOICE_SUSTAIN = 1,
    VOICE_RELEASE = 2
};

// 稳幅相位器模态：Bank 分音衰减，不用高 Q 双二阶（避免低音自激失真）。
struct ModalPartial {
    uint32_t phaseU = 0;
    uint32_t incrementU = 0;
    float amp = 0.0f;
    float level = 0.0f;
    float decay = 1.0f;
};

struct PianoVoice {
    int32_t midi = 60;
    float frequencyHz = 261.63f;
    uint32_t phaseU[kMaxPartials] = {};
    uint32_t incrementU[kMaxPartials] = {};
    float partialAmp[kMaxPartials] = {};
    float partialLevel[kMaxPartials] = {};
    float partialDecay[kMaxPartials] = {};
    int32_t partialCount = 0;
    float envLevel = 0.0f;
    float releaseDecay = 1.0f;
    float loudness = 1.0f;
    float hammerLevel = 0.0f;
    float hammerDecay = 0.0f;
    float voiceGain = 0.22f;
    ModalPartial modes[kMaxModes];
    ModalPartial twins[kTwinModes];
    int32_t modeCount = 0;
    int32_t twinCount = 0;
    float hammerLp = 0.0f;
    int32_t state = VOICE_ATTACK;
    int32_t framesInState = 0;
    int32_t framesSinceOn = 0;
    bool modal = false;
    bool inUse = false;
};

struct TunerTone {
    uint32_t phaseU = 0;
    uint32_t incrementU = 0;
    float amplitude = 0.0f;
    float targetAmplitude = 0.0f;
    float frequencyHz = 440.0f;
    float targetFrequencyHz = 440.0f;
};

struct PianoEngineState {
    std::mutex mutex;
    OH_AudioRenderer* renderer = nullptr;
    PianoVoice voices[kMaxVoices];
    TunerTone tuner;
    float sineTable[kSineTableSize];
    uint32_t noiseState = 0xA5A5C3C3u;
    float dynPeak = 0.0f;
    float dynRms2 = 0.0f;
    float dynNorm = 1.0f;
    float mixScaleSmooth = 1.0f;
    int32_t program = kProgramPiano;
    bool pianoClientActive = false;
    bool running = false;
    bool tableReady = false;
};

PianoEngineState g_engine;

float FastSineU(uint32_t phaseU)
{
    return g_engine.sineTable[phaseU >> 21];
}

uint32_t FrequencyToIncrement(float frequencyHz)
{
    if (frequencyHz <= 0.0f) {
        return 0;
    }
    const double ratio = static_cast<double>(frequencyHz) / static_cast<double>(kSampleRateHz);
    if (ratio >= 1.0) {
        return 0;
    }
    return static_cast<uint32_t>(ratio * 4294967296.0);
}

float NextNoise()
{
    g_engine.noiseState = g_engine.noiseState * 1664525u + 1013904223u;
    const float unit = static_cast<float>(g_engine.noiseState) * (1.0f / 4294967296.0f);
    return unit * 2.0f - 1.0f;
}

float LoudnessCompensation(float frequencyHz)
{
    if (frequencyHz <= 0.0f) {
        return 1.0f;
    }
    if (frequencyHz < 440.0f) {
        const float boosted = powf(440.0f / frequencyHz, 0.18f);
        return boosted > 1.28f ? 1.28f : boosted;
    }
    const float attenuated = powf(440.0f / frequencyHz, 0.10f);
    return attenuated < 0.88f ? 0.88f : attenuated;
}

void SetupPartial(ModalPartial& partial, float frequencyHz, float tauSeconds, float amp, bool resetState)
{
    float safeTau = tauSeconds;
    if (safeTau < 0.04f) {
        safeTau = 0.04f;
    }
    if (safeTau > 8.0f) {
        safeTau = 8.0f;
    }
    partial.incrementU = FrequencyToIncrement(frequencyHz);
    partial.amp = amp;
    partial.decay = expf(-1.0f / (safeTau * static_cast<float>(kSampleRateHz)));
    if (resetState) {
        partial.level = 1.0f;
        const float unit = NextNoise() * 0.5f + 0.5f;
        partial.phaseU = static_cast<uint32_t>(unit * 4294967296.0);
    }
}

float TickPartial(ModalPartial& partial)
{
    if (partial.level < 0.00001f) {
        return 0.0f;
    }
    const float sample = FastSineU(partial.phaseU) * partial.amp * partial.level;
    partial.phaseU += partial.incrementU;
    partial.level *= partial.decay;
    return sample;
}

float RaisedCosine(float t)
{
    if (t <= 0.0f) {
        return 0.0f;
    }
    if (t >= 1.0f) {
        return 1.0f;
    }
    return 0.5f * (1.0f - cosf(kPi * t));
}

void ApplyVoicePeakNormalize(PianoVoice& voice, float ampSum)
{
    if (ampSum < 0.001f) {
        ampSum = 0.001f;
    }
    voice.voiceGain = kVoicePeakTarget / ampSum;
}

float ProcessDynamics(float sample)
{
    const float absx = sample < 0.0f ? -sample : sample;
    const float peakCoeff = absx > g_engine.dynPeak ? kCompAttack : kCompRelease;
    g_engine.dynPeak += peakCoeff * (absx - g_engine.dynPeak);
    float comp = 1.0f;
    if (g_engine.dynPeak > kCompThreshold) {
        const float over = g_engine.dynPeak / kCompThreshold;
        comp = 1.0f / sqrtf(over);
    }
    g_engine.dynRms2 += 0.0018f * (sample * sample - g_engine.dynRms2);
    if (g_engine.dynRms2 < 0.0f) {
        g_engine.dynRms2 = 0.0f;
    }
    const float rms = sqrtf(g_engine.dynRms2);
    float normTarget = 1.0f;
    if (rms > 0.0030f) {
        normTarget = kNormLoudness / rms;
        if (normTarget > 3.20f) {
            normTarget = 3.20f;
        }
        if (normTarget < 0.70f) {
            normTarget = 0.70f;
        }
    }
    const float normCoeff = rms > 0.0030f ? kNormAttack : kNormRelease;
    g_engine.dynNorm += normCoeff * (normTarget - g_engine.dynNorm);
    return sample * comp * g_engine.dynNorm * kMakeup;
}

void ResetDynamics()
{
    g_engine.dynPeak = 0.0f;
    g_engine.dynRms2 = 0.0f;
    g_engine.dynNorm = 1.0f;
    g_engine.mixScaleSmooth = 1.0f;
}

void EnsureSineTable()
{
    if (g_engine.tableReady) {
        return;
    }
    for (int32_t index = 0; index < kSineTableSize; ++index) {
        g_engine.sineTable[index] = sinf(kTwoPi * static_cast<float>(index) / static_cast<float>(kSineTableSize));
    }
    g_engine.tableReady = true;
}

int32_t FindActiveVoiceLocked(int32_t midi)
{
    for (int32_t index = 0; index < kMaxVoices; ++index) {
        if (g_engine.voices[index].inUse && g_engine.voices[index].midi == midi &&
            g_engine.voices[index].state != VOICE_RELEASE) {
            return index;
        }
    }
    return -1;
}

int32_t FindFreeOrStealVoiceLocked()
{
    for (int32_t index = 0; index < kMaxVoices; ++index) {
        if (!g_engine.voices[index].inUse) {
            return index;
        }
    }
    for (int32_t index = 0; index < kMaxVoices; ++index) {
        if (g_engine.voices[index].inUse && g_engine.voices[index].state == VOICE_RELEASE) {
            return index;
        }
    }
    return 0;
}

void ConfigureVoiceLocked(PianoVoice& voice, int32_t midi, float frequencyHz, bool resetEnvelope)
{
    const float safeHz = frequencyHz < 20.0f ? 20.0f : frequencyHz;
    voice.midi = midi;
    voice.frequencyHz = safeHz;
    voice.loudness = LoudnessCompensation(safeHz);
    const int32_t program = g_engine.program;
    if (program == kProgramOrgan) {
        voice.partialCount = 2;
        voice.incrementU[0] = FrequencyToIncrement(safeHz);
        voice.incrementU[1] = FrequencyToIncrement(safeHz * 2.003f);
        voice.partialAmp[0] = 0.70f;
        voice.partialAmp[1] = 0.22f;
        voice.partialDecay[0] = 1.0f;
        voice.partialDecay[1] = 1.0f;
        voice.partialLevel[0] = 1.0f;
        voice.partialLevel[1] = 1.0f;
        ApplyVoicePeakNormalize(voice, 0.92f);
        voice.hammerLevel = resetEnvelope ? 0.06f : voice.hammerLevel;
        voice.hammerDecay = expf(-1.0f / (0.0060f * static_cast<float>(kSampleRateHz)));
        voice.modal = false;
    } else if (program == kProgramSquare) {
        int32_t count = 0;
        for (int32_t harmonic = 1; harmonic <= 11 && count < kMaxPartials; harmonic += 2) {
            if (safeHz * static_cast<float>(harmonic) >= kNyquistLimitHz) {
                break;
            }
            voice.incrementU[count] = FrequencyToIncrement(safeHz * static_cast<float>(harmonic));
            voice.partialAmp[count] = (1.0f / static_cast<float>(harmonic)) * 0.52f;
            voice.partialDecay[count] = 1.0f;
            voice.partialLevel[count] = 1.0f;
            ++count;
        }
        voice.partialCount = count;
        float squareAmp = 0.0f;
        for (int32_t index = 0; index < count; ++index) {
            squareAmp += voice.partialAmp[index];
        }
        ApplyVoicePeakNormalize(voice, squareAmp * 1.15f);
        voice.hammerLevel = 0.0f;
        voice.hammerDecay = 0.0f;
        voice.modal = false;
    } else {
        // 稳幅模态：分音从设定振幅衰减，槌头只做很轻的毡噪，不再驱动高 Q 滤波。
        voice.partialCount = 0;
        voice.modal = true;
        float inharmonicity = 0.00008f * powf(110.0f / safeHz, 0.40f);
        if (inharmonicity > 0.00028f) {
            inharmonicity = 0.00028f;
        }
        if (inharmonicity < 0.000025f) {
            inharmonicity = 0.000025f;
        }
        float baseTau = 3.6f * powf(220.0f / safeHz, 0.36f);
        if (baseTau > 5.8f) {
            baseTau = 5.8f;
        }
        if (baseTau < 0.85f) {
            baseTau = 0.85f;
        }
        int32_t count = 0;
        for (int32_t partial = 1; partial <= kMaxModes; ++partial) {
            const float stretch = sqrtf(1.0f + inharmonicity * static_cast<float>(partial * partial));
            const float partialHz = static_cast<float>(partial) * safeHz * stretch;
            if (partialHz >= kNyquistLimitHz) {
                break;
            }
            const float tilt = partial <= 2 ? 1.12f : 1.75f;
            const float amp = 1.0f / powf(static_cast<float>(partial), tilt);
            const float tauSeconds = baseTau / (1.0f + 0.34f * powf(static_cast<float>(partial), 1.65f));
            SetupPartial(voice.modes[count], partialHz, tauSeconds, amp, resetEnvelope);
            ++count;
        }
        voice.modeCount = count;
        int32_t twins = 0;
        const int32_t twinLimit = count < kTwinModes ? count : kTwinModes;
        for (int32_t index = 0; index < twinLimit; ++index) {
            const int32_t partial = index + 1;
            const float stretch = sqrtf(1.0f + inharmonicity * static_cast<float>(partial * partial));
            const float beatHz = safeHz < 180.0f ? 0.18f : 0.10f;
            const float twinHz = static_cast<float>(partial) * safeHz * stretch + beatHz;
            const float tilt = partial <= 2 ? 1.12f : 1.75f;
            const float amp = (1.0f / powf(static_cast<float>(partial), tilt)) * 0.32f;
            const float tauSeconds = (baseTau * 0.52f) / (1.0f + 0.34f * powf(static_cast<float>(partial), 1.65f));
            SetupPartial(voice.twins[twins], twinHz, tauSeconds, amp, resetEnvelope);
            ++twins;
        }
        voice.twinCount = twins;
        float pianoAmp = 0.0f;
        for (int32_t index = 0; index < count; ++index) {
            pianoAmp += voice.modes[index].amp;
        }
        for (int32_t index = 0; index < twins; ++index) {
            pianoAmp += voice.twins[index].amp;
        }
        ApplyVoicePeakNormalize(voice, pianoAmp);
        voice.hammerDecay = expf(-1.0f / (0.0080f * static_cast<float>(kSampleRateHz)));
        if (resetEnvelope) {
            voice.hammerLevel = 0.018f;
            voice.hammerLp = 0.0f;
        }
    }
    if (resetEnvelope) {
        for (int32_t index = 0; index < kMaxPartials; ++index) {
            voice.phaseU[index] = 0;
        }
        voice.releaseDecay = 1.0f;
        voice.framesInState = 0;
        voice.framesSinceOn = 0;
        if (program == kProgramSquare) {
            voice.envLevel = 1.0f;
            voice.state = VOICE_SUSTAIN;
        } else {
            voice.envLevel = 0.0f;
            voice.state = VOICE_ATTACK;
        }
    } else if (program == kProgramSquare && voice.state == VOICE_ATTACK) {
        voice.envLevel = 1.0f;
        voice.state = VOICE_SUSTAIN;
    }
    voice.inUse = true;
}

void BeginReleaseLocked(PianoVoice& voice)
{
    if (voice.state == VOICE_RELEASE) {
        return;
    }
    voice.envLevel = voice.envLevel > 0.0001f ? voice.envLevel : 0.0001f;
    const float damperTau = voice.modal ? 0.13f : 0.04f;
    voice.releaseDecay = expf(-1.0f / (damperTau * static_cast<float>(kSampleRateHz)));
    voice.state = VOICE_RELEASE;
    voice.framesInState = 0;
}

float AdvanceEnvelopeLocked(PianoVoice& voice)
{
    if (voice.state == VOICE_ATTACK) {
        const int32_t attackFrames = voice.modal ? kPianoAttackFrames : kOrganAttackFrames;
        const float t = static_cast<float>(voice.framesInState + 1) / static_cast<float>(attackFrames);
        voice.envLevel = voice.modal ? RaisedCosine(t) : (t > 1.0f ? 1.0f : t);
        ++voice.framesInState;
        ++voice.framesSinceOn;
        if (voice.framesInState >= attackFrames) {
            voice.state = VOICE_SUSTAIN;
            voice.framesInState = 0;
            voice.envLevel = 1.0f;
        }
        return voice.envLevel;
    }
    if (voice.state == VOICE_SUSTAIN) {
        voice.envLevel = 1.0f;
        ++voice.framesInState;
        ++voice.framesSinceOn;
        return 1.0f;
    }
    ++voice.framesInState;
    ++voice.framesSinceOn;
    voice.envLevel *= voice.releaseDecay;
    if (voice.envLevel < 0.0004f) {
        voice.envLevel = 0.0f;
    }
    return voice.envLevel;
}

float RenderModalSampleLocked(PianoVoice& voice)
{
    float mixed = 0.0f;
    float energy = 0.0f;
    for (int32_t index = 0; index < voice.modeCount; ++index) {
        mixed += TickPartial(voice.modes[index]);
        energy += voice.modes[index].level * voice.modes[index].amp;
    }
    for (int32_t index = 0; index < voice.twinCount; ++index) {
        mixed += TickPartial(voice.twins[index]);
        energy += voice.twins[index].level * voice.twins[index].amp;
    }
    if (voice.hammerLevel > 0.0002f) {
        voice.hammerLp += 0.045f * (NextNoise() - voice.hammerLp);
        mixed += voice.hammerLp * voice.hammerLevel;
        voice.hammerLevel *= voice.hammerDecay;
    }
    if (voice.framesSinceOn > 240 && energy < 0.0005f) {
        voice.inUse = false;
        return 0.0f;
    }
    return mixed * voice.loudness * voice.voiceGain;
}

float RenderVoiceSampleLocked(PianoVoice& voice, float envelope)
{
    if (voice.modal) {
        return RenderModalSampleLocked(voice) * envelope;
    }
    float mixed = 0.0f;
    for (int32_t index = 0; index < voice.partialCount; ++index) {
        mixed += FastSineU(voice.phaseU[index]) * voice.partialAmp[index] * voice.partialLevel[index];
        voice.phaseU[index] += voice.incrementU[index];
        voice.partialLevel[index] *= voice.partialDecay[index];
    }
    float hammer = 0.0f;
    if (voice.hammerLevel > 0.0001f) {
        hammer = voice.hammerLevel * NextNoise() * 0.22f;
        voice.hammerLevel *= voice.hammerDecay;
    }
    return (mixed + hammer) * envelope * voice.loudness * voice.voiceGain;
}

float RenderBandLimitedSquare(uint32_t phaseU, uint32_t fundIncrementU)
{
    float mixed = 0.0f;
    const uint32_t nyquistIncrement = FrequencyToIncrement(kNyquistLimitHz);
    for (int32_t harmonic = 1; harmonic <= 11; harmonic += 2) {
        if (fundIncrementU > 0 && fundIncrementU * static_cast<uint32_t>(harmonic) >= nyquistIncrement) {
            break;
        }
        mixed += FastSineU(phaseU * static_cast<uint32_t>(harmonic)) / static_cast<float>(harmonic);
    }
    return mixed * 0.62f;
}

float PeakLimit(float sample)
{
    const float magnitude = sample < 0.0f ? -sample : sample;
    if (magnitude <= kPeakLimitStart) {
        return sample;
    }
    const float limited = kPeakLimitStart + (magnitude - kPeakLimitStart) / (1.0f + (magnitude - kPeakLimitStart) * 12.0f);
    return sample < 0.0f ? -limited : limited;
}

int16_t ClampPcm(float sample)
{
    if (sample > static_cast<float>(kMaxAmplitude)) {
        return kMaxAmplitude;
    }
    if (sample < static_cast<float>(-kMaxAmplitude)) {
        return static_cast<int16_t>(-kMaxAmplitude);
    }
    return static_cast<int16_t>(sample);
}

void MixIntoBufferLocked(int16_t* output, int32_t frames)
{
    const float outputAmplitude = static_cast<float>(kMaxAmplitude) * kOutputScale;
    for (int32_t frame = 0; frame < frames; ++frame) {
        float dry = 0.0f;
        int32_t liveCount = 0;
        for (int32_t voiceIndex = 0; voiceIndex < kMaxVoices; ++voiceIndex) {
            PianoVoice& voice = g_engine.voices[voiceIndex];
            if (!voice.inUse) {
                continue;
            }
            const float envelope = AdvanceEnvelopeLocked(voice);
            if ((envelope <= 0.0f && voice.state == VOICE_RELEASE) || !voice.inUse) {
                voice.inUse = false;
                continue;
            }
            dry += RenderVoiceSampleLocked(voice, envelope);
            ++liveCount;
        }
        const float mixTarget = 1.0f / sqrtf(static_cast<float>(liveCount > 0 ? liveCount : 1));
        g_engine.mixScaleSmooth += 0.0020f * (mixTarget - g_engine.mixScaleSmooth);
        dry *= g_engine.mixScaleSmooth;
        const bool tunerLive = g_engine.tuner.amplitude > 0.00005f || g_engine.tuner.targetAmplitude > 0.00005f;
        if (tunerLive) {
            g_engine.tuner.amplitude += (g_engine.tuner.targetAmplitude - g_engine.tuner.amplitude) * kTunerFade;
            g_engine.tuner.frequencyHz +=
                (g_engine.tuner.targetFrequencyHz - g_engine.tuner.frequencyHz) * kTunerFade;
            if (g_engine.tuner.frequencyHz < 20.0f) {
                g_engine.tuner.frequencyHz = 20.0f;
            }
            g_engine.tuner.incrementU = FrequencyToIncrement(g_engine.tuner.frequencyHz);
            if (g_engine.tuner.amplitude > 0.00005f) {
                dry += RenderBandLimitedSquare(g_engine.tuner.phaseU, g_engine.tuner.incrementU) *
                    g_engine.tuner.amplitude * LoudnessCompensation(g_engine.tuner.frequencyHz);
                g_engine.tuner.phaseU += g_engine.tuner.incrementU;
            }
        }
        const float limited = PeakLimit(ProcessDynamics(dry));
        const int16_t pcm = ClampPcm(limited * outputAmplitude);
        output[frame * kChannelCount] = pcm;
        output[frame * kChannelCount + 1] = pcm;
    }
}

OH_AudioData_Callback_Result OnWriteData(OH_AudioRenderer* renderer, void* userData, void* audioData,
    int32_t audioDataSize)
{
    (void)renderer;
    (void)userData;
    if (audioData == nullptr || audioDataSize <= 0) {
        return AUDIO_DATA_CALLBACK_RESULT_INVALID;
    }
    std::memset(audioData, 0, static_cast<size_t>(audioDataSize));
    const int32_t frames = audioDataSize / static_cast<int32_t>(sizeof(int16_t) * kChannelCount);
    if (frames <= 0) {
        return AUDIO_DATA_CALLBACK_RESULT_VALID;
    }
    {
        std::lock_guard<std::mutex> lock(g_engine.mutex);
        MixIntoBufferLocked(static_cast<int16_t*>(audioData), frames);
    }
    return AUDIO_DATA_CALLBACK_RESULT_VALID;
}

void OnInterrupt(OH_AudioRenderer* renderer, void* userData, OH_AudioInterrupt_ForceType type,
    OH_AudioInterrupt_Hint hint)
{
    (void)renderer;
    (void)userData;
    OH_LOG_INFO(LOG_APP, "键盘音频中断 type=%{public}d hint=%{public}d", static_cast<int>(type),
        static_cast<int>(hint));
}

void OnError(OH_AudioRenderer* renderer, void* userData, OH_AudioStream_Result error)
{
    (void)renderer;
    (void)userData;
    OH_LOG_ERROR(LOG_APP, "键盘音频异常 error=%{public}d", static_cast<int>(error));
}

OH_AudioStream_Result GenerateRenderer(bool useFast, bool setFrameSize)
{
    OH_AudioStreamBuilder* builder = nullptr;
    OH_AudioStream_Result result = OH_AudioStreamBuilder_Create(&builder, AUDIOSTREAM_TYPE_RENDERER);
    if (result != AUDIOSTREAM_SUCCESS || builder == nullptr) {
        return result == AUDIOSTREAM_SUCCESS ? AUDIOSTREAM_ERROR_SYSTEM : result;
    }
    OH_AudioStreamBuilder_SetSamplingRate(builder, kSampleRateHz);
    OH_AudioStreamBuilder_SetChannelCount(builder, kChannelCount);
    OH_AudioStreamBuilder_SetSampleFormat(builder, AUDIOSTREAM_SAMPLE_S16LE);
    OH_AudioStreamBuilder_SetEncodingType(builder, AUDIOSTREAM_ENCODING_TYPE_RAW);
    OH_AudioStreamBuilder_SetRendererInfo(builder, AUDIOSTREAM_USAGE_GAME);
    OH_AudioStreamBuilder_SetLatencyMode(builder,
        useFast ? AUDIOSTREAM_LATENCY_MODE_FAST : AUDIOSTREAM_LATENCY_MODE_NORMAL);
    if (setFrameSize) {
        OH_AudioStreamBuilder_SetFrameSizeInCallback(builder, kCallbackFrames);
    }
    OH_AudioStreamBuilder_SetRendererWriteDataCallback(builder, OnWriteData, nullptr);
    OH_AudioStreamBuilder_SetRendererInterruptCallback(builder, OnInterrupt, nullptr);
    OH_AudioStreamBuilder_SetRendererErrorCallback(builder, OnError, nullptr);
    result = OH_AudioStreamBuilder_GenerateRenderer(builder, &g_engine.renderer);
    OH_AudioStreamBuilder_Destroy(builder);
    return result;
}

bool CreateRendererWithFallback()
{
    const bool attemptsFast[] = { true, true, false };
    const bool attemptsFrame[] = { true, false, false };
    for (int32_t attempt = 0; attempt < 3; ++attempt) {
        g_engine.renderer = nullptr;
        const OH_AudioStream_Result result = GenerateRenderer(attemptsFast[attempt], attemptsFrame[attempt]);
        if (result == AUDIOSTREAM_SUCCESS && g_engine.renderer != nullptr) {
            OH_LOG_INFO(LOG_APP, "键盘引擎已创建 fast=%{public}d frameSize=%{public}d",
                attemptsFast[attempt] ? 1 : 0, attemptsFrame[attempt] ? 1 : 0);
            return true;
        }
        OH_LOG_WARN(LOG_APP, "键盘引擎创建失败 fast=%{public}d frameSize=%{public}d result=%{public}d",
            attemptsFast[attempt] ? 1 : 0, attemptsFrame[attempt] ? 1 : 0, static_cast<int>(result));
        g_engine.renderer = nullptr;
    }
    return false;
}

int32_t StartRendererIfNeeded()
{
    OH_AudioRenderer* renderer = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_engine.mutex);
        if (g_engine.running) {
            return 0;
        }
        if (g_engine.renderer == nullptr && !CreateRendererWithFallback()) {
            return -1;
        }
        renderer = g_engine.renderer;
    }
    if (renderer == nullptr) {
        return -1;
    }
    const OH_AudioStream_Result startResult = OH_AudioRenderer_Start(renderer);
    if (startResult != AUDIOSTREAM_SUCCESS) {
        OH_LOG_ERROR(LOG_APP, "键盘引擎 Start 失败 result=%{public}d", static_cast<int>(startResult));
        return static_cast<int32_t>(startResult);
    }
    std::lock_guard<std::mutex> lock(g_engine.mutex);
    if (g_engine.renderer == renderer) {
        g_engine.running = true;
        OH_AudioStream_FastStatus fastStatus = AUDIOSTREAM_FASTSTATUS_NORMAL;
        if (OH_AudioRenderer_GetFastStatus(g_engine.renderer, &fastStatus) == AUDIOSTREAM_SUCCESS) {
            OH_LOG_INFO(LOG_APP, "键盘低时延状态 fastStatus=%{public}d", static_cast<int>(fastStatus));
        }
    }
    return 0;
}

void StopRendererIfIdle()
{
    OH_AudioRenderer* renderer = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_engine.mutex);
        const bool tunerActive = g_engine.tuner.targetAmplitude > 0.0001f || g_engine.tuner.amplitude > 0.0001f;
        if (g_engine.pianoClientActive || tunerActive || g_engine.renderer == nullptr) {
            return;
        }
        renderer = g_engine.renderer;
        g_engine.running = false;
    }
    if (renderer == nullptr) {
        return;
    }
    OH_AudioRenderer_Stop(renderer);
    OH_AudioRenderer_Flush(renderer);
}
} // namespace

int32_t PianoEngine_Prepare(void)
{
    EnsureSineTable();
    std::lock_guard<std::mutex> lock(g_engine.mutex);
    if (g_engine.renderer != nullptr) {
        return 0;
    }
    return CreateRendererWithFallback() ? 0 : -1;
}

int32_t PianoEngine_Start(void)
{
    if (PianoEngine_Prepare() != 0) {
        return -1;
    }
    {
        std::lock_guard<std::mutex> lock(g_engine.mutex);
        g_engine.pianoClientActive = true;
    }
    return StartRendererIfNeeded();
}

void PianoEngine_Stop(void)
{
    {
        std::lock_guard<std::mutex> lock(g_engine.mutex);
        g_engine.pianoClientActive = false;
    }
    StopRendererIfIdle();
}

void PianoEngine_Release(void)
{
    OH_AudioRenderer* renderer = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_engine.mutex);
        for (int32_t index = 0; index < kMaxVoices; ++index) {
            g_engine.voices[index].inUse = false;
        }
        g_engine.tuner.amplitude = 0.0f;
        g_engine.tuner.targetAmplitude = 0.0f;
        g_engine.pianoClientActive = false;
        renderer = g_engine.renderer;
        g_engine.renderer = nullptr;
        g_engine.running = false;
    }
    if (renderer == nullptr) {
        return;
    }
    OH_AudioRenderer_Stop(renderer);
    OH_AudioRenderer_Flush(renderer);
    OH_AudioRenderer_Release(renderer);
}

void PianoEngine_NoteOn(int32_t midi, float frequencyHz)
{
    std::lock_guard<std::mutex> lock(g_engine.mutex);
    int32_t voiceIndex = FindActiveVoiceLocked(midi);
    if (voiceIndex < 0) {
        voiceIndex = FindFreeOrStealVoiceLocked();
    }
    ConfigureVoiceLocked(g_engine.voices[voiceIndex], midi, frequencyHz, true);
}

void PianoEngine_NoteOff(int32_t midi)
{
    std::lock_guard<std::mutex> lock(g_engine.mutex);
    for (int32_t index = 0; index < kMaxVoices; ++index) {
        if (g_engine.voices[index].inUse && g_engine.voices[index].midi == midi &&
            g_engine.voices[index].state != VOICE_RELEASE) {
            BeginReleaseLocked(g_engine.voices[index]);
        }
    }
}

void PianoEngine_AllNotesOff(int32_t immediate)
{
    std::lock_guard<std::mutex> lock(g_engine.mutex);
    for (int32_t index = 0; index < kMaxVoices; ++index) {
        if (!g_engine.voices[index].inUse) {
            continue;
        }
        if (immediate != 0) {
            g_engine.voices[index].inUse = false;
        } else {
            BeginReleaseLocked(g_engine.voices[index]);
        }
    }
}

void PianoEngine_Retune(int32_t midi, float frequencyHz)
{
    std::lock_guard<std::mutex> lock(g_engine.mutex);
    for (int32_t index = 0; index < kMaxVoices; ++index) {
        PianoVoice& voice = g_engine.voices[index];
        if (!voice.inUse || voice.midi != midi) {
            continue;
        }
        ConfigureVoiceLocked(voice, midi, frequencyHz, false);
    }
}

void PianoEngine_SetProgram(int32_t program)
{
    int32_t nextProgram = program;
    if (nextProgram < kProgramPiano) {
        nextProgram = kProgramPiano;
    }
    if (nextProgram > kProgramSquare) {
        nextProgram = kProgramSquare;
    }
    std::lock_guard<std::mutex> lock(g_engine.mutex);
    if (g_engine.program == nextProgram) {
        return;
    }
    g_engine.program = nextProgram;
    ResetDynamics();
    for (int32_t index = 0; index < kMaxVoices; ++index) {
        PianoVoice& voice = g_engine.voices[index];
        if (!voice.inUse) {
            continue;
        }
        ConfigureVoiceLocked(voice, voice.midi, voice.frequencyHz, false);
    }
}

void PianoEngine_SetTunerTone(float frequencyHz, float amplitude)
{
    if (PianoEngine_Prepare() != 0) {
        return;
    }
    const float safeHz = frequencyHz < 20.0f ? 20.0f : frequencyHz;
    const float safeAmp = amplitude < 0.0f ? 0.0f : amplitude;
    {
        std::lock_guard<std::mutex> lock(g_engine.mutex);
        g_engine.tuner.targetFrequencyHz = safeHz;
        g_engine.tuner.targetAmplitude = safeAmp;
        if (safeAmp <= 0.0001f) {
            g_engine.tuner.amplitude = 0.0f;
        }
    }
    if (safeAmp > 0.0001f) {
        StartRendererIfNeeded();
        return;
    }
    StopRendererIfIdle();
}

int32_t PianoEngine_IsRunning(void)
{
    std::lock_guard<std::mutex> lock(g_engine.mutex);
    return g_engine.running ? 1 : 0;
}
