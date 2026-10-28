#include "tuner_yin.h"

#include <cmath>
#include <cstring>
#include <vector>

namespace {
constexpr float kPi = 3.14159265358979323846f;
constexpr float kSpectrumFreqMinHz = 90.0f;
constexpr float kSpectrumFreqMaxHz = 6000.0f;
constexpr float kDefaultYinThreshold = 0.10f;
constexpr float kFallbackYinClarity = 0.20f;
constexpr int kMinFftLog2 = 8;
constexpr int kMaxFftLog2 = 16;

int NextPow2Log2(int value)
{
    int log2n = kMinFftLog2;
    int size = 1 << log2n;
    while (size < value && log2n < kMaxFftLog2) {
        log2n += 1;
        size <<= 1;
    }
    return log2n;
}

void BitReverse(std::vector<float>& re, std::vector<float>& im, int n)
{
    int j = 0;
    for (int i = 1; i < n; ++i) {
        int bit = n >> 1;
        while (j & bit) {
            j ^= bit;
            bit >>= 1;
        }
        j ^= bit;
        if (i < j) {
            const float tmpRe = re[static_cast<size_t>(i)];
            re[static_cast<size_t>(i)] = re[static_cast<size_t>(j)];
            re[static_cast<size_t>(j)] = tmpRe;
            const float tmpIm = im[static_cast<size_t>(i)];
            im[static_cast<size_t>(i)] = im[static_cast<size_t>(j)];
            im[static_cast<size_t>(j)] = tmpIm;
        }
    }
}

void FftRadix2(std::vector<float>& re, std::vector<float>& im, int n, bool inverse)
{
    BitReverse(re, im, n);
    for (int len = 2; len <= n; len <<= 1) {
        const float angle = (inverse ? kPi : -kPi) * 2.0f / static_cast<float>(len);
        const float wLenRe = cosf(angle);
        const float wLenIm = sinf(angle);
        for (int i = 0; i < n; i += len) {
            float wRe = 1.0f;
            float wIm = 0.0f;
            const int half = len >> 1;
            for (int k = 0; k < half; ++k) {
                const int even = i + k;
                const int odd = even + half;
                const float oddRe = re[static_cast<size_t>(odd)] * wRe - im[static_cast<size_t>(odd)] * wIm;
                const float oddIm = re[static_cast<size_t>(odd)] * wIm + im[static_cast<size_t>(odd)] * wRe;
                re[static_cast<size_t>(odd)] = re[static_cast<size_t>(even)] - oddRe;
                im[static_cast<size_t>(odd)] = im[static_cast<size_t>(even)] - oddIm;
                re[static_cast<size_t>(even)] += oddRe;
                im[static_cast<size_t>(even)] += oddIm;
                const float nextWRe = wRe * wLenRe - wIm * wLenIm;
                wIm = wRe * wLenIm + wIm * wLenRe;
                wRe = nextWRe;
            }
        }
    }
    if (inverse) {
        const float scale = 1.0f / static_cast<float>(n);
        for (int i = 0; i < n; ++i) {
            re[static_cast<size_t>(i)] *= scale;
            im[static_cast<size_t>(i)] *= scale;
        }
    }
}

float ClampPositive(float value, float fallback)
{
    return value > 0.0f ? value : fallback;
}

float BandCenterHz(int bandIndex)
{
    const float t = static_cast<float>(bandIndex) / static_cast<float>(TUNER_SPECTRUM_BAND_COUNT - 1);
    return kSpectrumFreqMinHz * powf(kSpectrumFreqMaxHz / kSpectrumFreqMinHz, t);
}

void FillSpectrum(const std::vector<float>& re, const std::vector<float>& im, int fftSize, float sampleRateHz,
    float* magnitudes)
{
    for (int band = 0; band < TUNER_SPECTRUM_BAND_COUNT; ++band) {
        const float center = BandCenterHz(band);
        const float prev = band == 0 ? (center * center / BandCenterHz(1)) : BandCenterHz(band - 1);
        const float next = band == TUNER_SPECTRUM_BAND_COUNT - 1
            ? (center * center / BandCenterHz(TUNER_SPECTRUM_BAND_COUNT - 2))
            : BandCenterHz(band + 1);
        const float lo = sqrtf(prev * center);
        const float hi = sqrtf(center * next);
        float sum = 0.0f;
        int count = 0;
        const int maxBin = fftSize / 2;
        for (int bin = 1; bin <= maxBin; ++bin) {
            const float freqHz = static_cast<float>(bin) * sampleRateHz / static_cast<float>(fftSize);
            if (freqHz < lo || freqHz > hi) {
                continue;
            }
            const float mag = sqrtf(re[static_cast<size_t>(bin)] * re[static_cast<size_t>(bin)] +
                im[static_cast<size_t>(bin)] * im[static_cast<size_t>(bin)]);
            sum += mag;
            count += 1;
        }
        magnitudes[band] = count > 0 ? (sum / (static_cast<float>(count) * static_cast<float>(fftSize))) : 0.0f;
    }
}

float ParabolicRefine(float y0, float y1, float y2)
{
    const float denom = y0 - 2.0f * y1 + y2;
    if (fabsf(denom) <= 1e-12f) {
        return 0.0f;
    }
    return (y0 - y2) / (2.0f * denom);
}

float DetectPitchYin(const float* samples, int windowSize, const TunerYinConfig* config, float envelope)
{
    if (envelope < config->rmsGateThreshold) {
        return 0.0f;
    }

    const int fftLog2 = NextPow2Log2(windowSize * 2);
    const int fftSize = 1 << fftLog2;
    std::vector<float> re(static_cast<size_t>(fftSize), 0.0f);
    std::vector<float> im(static_cast<size_t>(fftSize), 0.0f);
    for (int i = 0; i < windowSize; ++i) {
        re[static_cast<size_t>(i)] = samples[i];
    }
    FftRadix2(re, im, fftSize, false);
    for (int i = 0; i < fftSize; ++i) {
        const float power = re[static_cast<size_t>(i)] * re[static_cast<size_t>(i)] +
            im[static_cast<size_t>(i)] * im[static_cast<size_t>(i)];
        re[static_cast<size_t>(i)] = power;
        im[static_cast<size_t>(i)] = 0.0f;
    }
    FftRadix2(re, im, fftSize, true);

    std::vector<float> runningSq(static_cast<size_t>(windowSize + 1), 0.0f);
    for (int i = 0; i < windowSize; ++i) {
        runningSq[static_cast<size_t>(i + 1)] = runningSq[static_cast<size_t>(i)] + samples[i] * samples[i];
    }

    const float safeMinHz = ClampPositive(config->pitchMinHz, 27.5f);
    const float safeMaxHz = ClampPositive(config->pitchMaxHz, 1760.0f);
    int minLag = static_cast<int>(floorf(config->sampleRateHz / safeMaxHz));
    int maxLag = static_cast<int>(floorf(config->sampleRateHz / safeMinHz));
    if (minLag < 2) {
        minLag = 2;
    }
    if (maxLag > windowSize / 2) {
        maxLag = windowSize / 2;
    }
    if (maxLag <= minLag) {
        return 0.0f;
    }

    std::vector<float> cmndf(static_cast<size_t>(maxLag + 1), 1.0f);
    float runningDiff = 0.0f;
    int bestTau = 0;
    float bestValue = 1.0f;
    const float threshold = config->yinThreshold > 0.0f ? config->yinThreshold : kDefaultYinThreshold;

    for (int tau = 1; tau <= maxLag; ++tau) {
        const float energyA = runningSq[static_cast<size_t>(windowSize - tau)];
        const float energyB = runningSq[static_cast<size_t>(windowSize)] - runningSq[static_cast<size_t>(tau)];
        float diff = energyA + energyB - 2.0f * re[static_cast<size_t>(tau)];
        if (diff < 0.0f) {
            diff = 0.0f;
        }
        runningDiff += diff;
        const float value = runningDiff > 0.0f ? (diff * static_cast<float>(tau) / runningDiff) : 1.0f;
        cmndf[static_cast<size_t>(tau)] = value;
        if (tau >= minLag && value < bestValue) {
            bestValue = value;
            bestTau = tau;
        }
    }

    int firstTau = 0;
    for (int tau = minLag + 1; tau < maxLag; ++tau) {
        const float value = cmndf[static_cast<size_t>(tau)];
        if (value >= threshold) {
            continue;
        }
        if (value <= cmndf[static_cast<size_t>(tau - 1)] && value <= cmndf[static_cast<size_t>(tau + 1)]) {
            firstTau = tau;
            break;
        }
    }

    int chosenTau = firstTau;
    float chosenValue = firstTau > 0 ? cmndf[static_cast<size_t>(firstTau)] : 1.0f;
    if (chosenTau <= 0) {
        if (bestTau < minLag || bestValue > kFallbackYinClarity) {
            return 0.0f;
        }
        chosenTau = bestTau;
        chosenValue = bestValue;
    }

    float refinedTau = static_cast<float>(chosenTau);
    if (chosenTau > 1 && chosenTau < maxLag) {
        refinedTau += ParabolicRefine(
            cmndf[static_cast<size_t>(chosenTau - 1)],
            chosenValue,
            cmndf[static_cast<size_t>(chosenTau + 1)]);
    }
    if (refinedTau < 2.0f) {
        return 0.0f;
    }
    return config->sampleRateHz / refinedTau;
}
} // namespace

void TunerYin_Analyze(const float* samples, size_t sampleCount, const TunerYinConfig* config, TunerYinResult* result)
{
    if (result == nullptr) {
        return;
    }
    memset(result, 0, sizeof(TunerYinResult));
    if (samples == nullptr || config == nullptr || sampleCount == 0 || config->sampleRateHz <= 0.0f) {
        return;
    }

    const int windowSize = static_cast<int>(sampleCount);
    float sumSq = 0.0f;
    for (int i = 0; i < windowSize; ++i) {
        sumSq += samples[i] * samples[i];
    }
    result->rawEnvelope = sqrtf(sumSq / static_cast<float>(windowSize));

    const int specLog2 = NextPow2Log2(windowSize);
    const int specSize = 1 << specLog2;
    std::vector<float> specRe(static_cast<size_t>(specSize), 0.0f);
    std::vector<float> specIm(static_cast<size_t>(specSize), 0.0f);
    const float denom = static_cast<float>(windowSize > 1 ? windowSize - 1 : 1);
    for (int i = 0; i < windowSize; ++i) {
        const float hann = 0.5f * (1.0f - cosf(2.0f * kPi * static_cast<float>(i) / denom));
        specRe[static_cast<size_t>(i)] = samples[i] * hann;
    }
    FftRadix2(specRe, specIm, specSize, false);
    FillSpectrum(specRe, specIm, specSize, config->sampleRateHz, result->spectrumMagnitudes);

    result->pitchHz = DetectPitchYin(samples, windowSize, config, result->rawEnvelope);
}
