#include "napi/native_api.h"
#include "piano_engine.h"

static napi_value NapiCreateInt32(napi_env env, int32_t value)
{
    napi_value result = nullptr;
    napi_create_int32(env, value, &result);
    return result;
}

static bool ReadInt32Arg(napi_env env, napi_value value, int32_t* outValue)
{
    return napi_get_value_int32(env, value, outValue) == napi_ok;
}

static bool ReadDoubleArg(napi_env env, napi_value value, double* outValue)
{
    return napi_get_value_double(env, value, outValue) == napi_ok;
}

static napi_value PianoPrepare(napi_env env, napi_callback_info info)
{
    (void)info;
    return NapiCreateInt32(env, PianoEngine_Prepare());
}

static napi_value PianoStart(napi_env env, napi_callback_info info)
{
    (void)info;
    return NapiCreateInt32(env, PianoEngine_Start());
}

static napi_value PianoStop(napi_env env, napi_callback_info info)
{
    (void)info;
    PianoEngine_Stop();
    return NapiCreateInt32(env, 0);
}

static napi_value PianoRelease(napi_env env, napi_callback_info info)
{
    (void)info;
    PianoEngine_Release();
    return NapiCreateInt32(env, 0);
}

static napi_value PianoNoteOn(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr, nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t midi = 60;
    double frequencyHz = 261.63;
    if (argc > 0) {
        ReadInt32Arg(env, args[0], &midi);
    }
    if (argc > 1) {
        ReadDoubleArg(env, args[1], &frequencyHz);
    }
    PianoEngine_NoteOn(midi, static_cast<float>(frequencyHz));
    return NapiCreateInt32(env, 0);
}

static napi_value PianoNoteOff(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t midi = 60;
    if (argc > 0) {
        ReadInt32Arg(env, args[0], &midi);
    }
    PianoEngine_NoteOff(midi);
    return NapiCreateInt32(env, 0);
}

static napi_value PianoAllNotesOff(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool immediate = false;
    if (argc > 0) {
        napi_get_value_bool(env, args[0], &immediate);
    }
    PianoEngine_AllNotesOff(immediate ? 1 : 0);
    return NapiCreateInt32(env, 0);
}

static napi_value PianoRetune(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr, nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t midi = 60;
    double frequencyHz = 261.63;
    if (argc > 0) {
        ReadInt32Arg(env, args[0], &midi);
    }
    if (argc > 1) {
        ReadDoubleArg(env, args[1], &frequencyHz);
    }
    PianoEngine_Retune(midi, static_cast<float>(frequencyHz));
    return NapiCreateInt32(env, 0);
}

static napi_value PianoSetProgram(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t program = 0;
    if (argc > 0) {
        ReadInt32Arg(env, args[0], &program);
    }
    PianoEngine_SetProgram(program);
    return NapiCreateInt32(env, 0);
}

static napi_value PianoSetTunerTone(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr, nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    double frequencyHz = 440.0;
    double amplitude = 0.0;
    if (argc > 0) {
        ReadDoubleArg(env, args[0], &frequencyHz);
    }
    if (argc > 1) {
        ReadDoubleArg(env, args[1], &amplitude);
    }
    PianoEngine_SetTunerTone(static_cast<float>(frequencyHz), static_cast<float>(amplitude));
    return NapiCreateInt32(env, 0);
}

static napi_value PianoIsRunning(napi_env env, napi_callback_info info)
{
    (void)info;
    return NapiCreateInt32(env, PianoEngine_IsRunning());
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "pianoPrepare", nullptr, PianoPrepare, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "pianoStart", nullptr, PianoStart, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "pianoStop", nullptr, PianoStop, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "pianoRelease", nullptr, PianoRelease, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "pianoNoteOn", nullptr, PianoNoteOn, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "pianoNoteOff", nullptr, PianoNoteOff, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "pianoAllNotesOff", nullptr, PianoAllNotesOff, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "pianoRetune", nullptr, PianoRetune, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "pianoSetProgram", nullptr, PianoSetProgram, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "pianoSetTunerTone", nullptr, PianoSetTunerTone, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "pianoIsRunning", nullptr, PianoIsRunning, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module pianoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "piano",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterPianoModule(void)
{
    napi_module_register(&pianoModule);
}
