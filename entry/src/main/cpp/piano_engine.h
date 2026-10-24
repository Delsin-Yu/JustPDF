#ifndef JUSTPDF_PIANO_ENGINE_H
#define JUSTPDF_PIANO_ENGINE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t PianoEngine_Prepare(void);
int32_t PianoEngine_Start(void);
void PianoEngine_Stop(void);
void PianoEngine_Release(void);
void PianoEngine_NoteOn(int32_t midi, float frequencyHz);
void PianoEngine_NoteOff(int32_t midi);
void PianoEngine_AllNotesOff(int32_t immediate);
void PianoEngine_Retune(int32_t midi, float frequencyHz);
void PianoEngine_SetProgram(int32_t program);
void PianoEngine_SetTunerTone(float frequencyHz, float amplitude);
int32_t PianoEngine_IsRunning(void);

#ifdef __cplusplus
}
#endif

#endif
