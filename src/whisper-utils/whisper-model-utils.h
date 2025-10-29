#ifndef WHISPER_MODEL_UTILS_H
#define WHISPER_MODEL_UTILS_H

#include <obs.h>

#include "transcription-filter-data.h"

void update_whisper_model(struct transcription_filter_data *gf, bool force_whisper_restart = false);

#endif // WHISPER_MODEL_UTILS_H
