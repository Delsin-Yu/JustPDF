#include "napi/native_api.h"
#include "tuner_engine.h"

#include <mutex>

namespace {
std::mutex g_tsfnMutex;
napi_threadsafe_function g_tsfn = nullptr;

struct JsTunerResult {
    float spectrumMagnitudes[TUNER_ENGINE_SPECTRUM_BAND_COUNT];
    float pitchHz;
    float rawEnvelope;
};

napi_value NapiCreateInt32(napi_env env, int32_t value)
{
    napi_value result = nullptr;
    napi_create_int32(env, value, &result);
    return result;
}

bool ReadDoubleArg(napi_env env, napi_value value, double* outValue)
{
    return napi_get_value_double(env, value, outValue) == napi_ok;
}

bool ReadInt32Arg(napi_env env, napi_value value, int32_t* outValue)
{
    return napi_get_value_int32(env, value, outValue) == napi_ok;
}

void ReleaseTsfnLocked()
{
    if (g_tsfn == nullptr) {
        return;
    }
    napi_release_threadsafe_function(g_tsfn, napi_tsfn_release);
    g_tsfn = nullptr;
}

void CallJsResult(napi_env env, napi_value jsCallback, void* context, void* data)
{
    (void)context;
    JsTunerResult* result = static_cast<JsTunerResult*>(data);
    if (result == nullptr) {
        return;
    }
    if (env == nullptr || jsCallback == nullptr) {
        delete result;
        return;
    }

    napi_value undefinedValue = nullptr;
    napi_get_undefined(env, &undefinedValue);
    napi_value object = nullptr;
    napi_create_object(env, &object);
    napi_value pitchValue = nullptr;
    napi_value envelopeValue = nullptr;
    napi_value spectrumArray = nullptr;
    napi_create_double(env, result->pitchHz, &pitchValue);
    napi_create_double(env, result->rawEnvelope, &envelopeValue);
    napi_create_array_with_length(env, TUNER_ENGINE_SPECTRUM_BAND_COUNT, &spectrumArray);
    for (uint32_t index = 0; index < TUNER_ENGINE_SPECTRUM_BAND_COUNT; ++index) {
        napi_value item = nullptr;
        napi_create_double(env, result->spectrumMagnitudes[index], &item);
        napi_set_element(env, spectrumArray, index, item);
    }
    napi_set_named_property(env, object, "pitchHz", pitchValue);
    napi_set_named_property(env, object, "rawEnvelope", envelopeValue);
    napi_set_named_property(env, object, "spectrumMagnitudes", spectrumArray);

    napi_value argv[1] = { object };
    napi_value callResult = nullptr;
    napi_call_function(env, undefinedValue, jsCallback, 1, argv, &callResult);
    delete result;
}

void OnEngineResult(const TunerEngineResult* result, void* userData)
{
    (void)userData;
    if (result == nullptr) {
        return;
    }
    napi_threadsafe_function tsfn = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_tsfnMutex);
        tsfn = g_tsfn;
    }
    if (tsfn == nullptr) {
        return;
    }
    JsTunerResult* jsResult = new JsTunerResult();
    jsResult->pitchHz = result->pitchHz;
    jsResult->rawEnvelope = result->rawEnvelope;
    for (int index = 0; index < TUNER_ENGINE_SPECTRUM_BAND_COUNT; ++index) {
        jsResult->spectrumMagnitudes[index] = result->spectrumMagnitudes[index];
    }
    const napi_status status = napi_call_threadsafe_function(tsfn, jsResult, napi_tsfn_nonblocking);
    if (status != napi_ok) {
        delete jsResult;
    }
}

napi_value TunerStartMic(napi_env env, napi_callback_info info)
{
    (void)info;
    return NapiCreateInt32(env, TunerEngine_StartMic());
}

napi_value TunerStopMic(napi_env env, napi_callback_info info)
{
    (void)info;
    TunerEngine_StopMic();
    return NapiCreateInt32(env, 0);
}

napi_value TunerSetConfig(napi_env env, napi_callback_info info)
{
    size_t argc = 6;
    napi_value args[6] = { nullptr, nullptr, nullptr, nullptr, nullptr, nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    TunerEngineConfig config{};
    config.pitchMinHz = 27.5f;
    config.pitchMaxHz = 1760.0f;
    config.highPassHz = 22.0f;
    config.lowPassHz = 5200.0f;
    config.rmsGateThreshold = 0.008f;
    config.windowSize = 4096;
    double numberValue = 0.0;
    if (argc > 0 && ReadDoubleArg(env, args[0], &numberValue)) {
        config.pitchMinHz = static_cast<float>(numberValue);
    }
    if (argc > 1 && ReadDoubleArg(env, args[1], &numberValue)) {
        config.pitchMaxHz = static_cast<float>(numberValue);
    }
    if (argc > 2 && ReadDoubleArg(env, args[2], &numberValue)) {
        config.highPassHz = static_cast<float>(numberValue);
    }
    if (argc > 3 && ReadDoubleArg(env, args[3], &numberValue)) {
        config.lowPassHz = static_cast<float>(numberValue);
    }
    if (argc > 4 && ReadDoubleArg(env, args[4], &numberValue)) {
        config.rmsGateThreshold = static_cast<float>(numberValue);
    }
    int32_t windowSize = 4096;
    if (argc > 5 && ReadInt32Arg(env, args[5], &windowSize)) {
        config.windowSize = windowSize;
    }
    return NapiCreateInt32(env, TunerEngine_SetConfig(&config));
}

napi_value TunerSetResultCallback(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return NapiCreateInt32(env, -1);
    }
    napi_valuetype valueType = napi_undefined;
    napi_typeof(env, args[0], &valueType);
    if (valueType != napi_function) {
        return NapiCreateInt32(env, -1);
    }

    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "JustPdfTunerResult", NAPI_AUTO_LENGTH, &resourceName);
    napi_threadsafe_function tsfn = nullptr;
    const napi_status createStatus = napi_create_threadsafe_function(
        env, args[0], nullptr, resourceName, 1, 1, nullptr, nullptr, nullptr, CallJsResult, &tsfn);
    if (createStatus != napi_ok || tsfn == nullptr) {
        return NapiCreateInt32(env, -1);
    }

    {
        std::lock_guard<std::mutex> lock(g_tsfnMutex);
        ReleaseTsfnLocked();
        g_tsfn = tsfn;
    }
    TunerEngine_SetResultCallback(OnEngineResult, nullptr);
    return NapiCreateInt32(env, 0);
}

napi_value TunerClearResultCallback(napi_env env, napi_callback_info info)
{
    (void)info;
    TunerEngine_SetResultCallback(nullptr, nullptr);
    std::lock_guard<std::mutex> lock(g_tsfnMutex);
    ReleaseTsfnLocked();
    return NapiCreateInt32(env, 0);
}
} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "tunerStartMic", nullptr, TunerStartMic, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "tunerStopMic", nullptr, TunerStopMic, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "tunerSetConfig", nullptr, TunerSetConfig, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "tunerSetResultCallback", nullptr, TunerSetResultCallback, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "tunerClearResultCallback", nullptr, TunerClearResultCallback, nullptr, nullptr, nullptr, napi_default,
            nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module tunerModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "tuner",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterTunerModule(void)
{
    napi_module_register(&tunerModule);
}
