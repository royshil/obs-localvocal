#pragma once

#include <obs-properties.h>
#include <obs-data.h>

// Forward declaration
struct transcription_filter_data;

#ifdef __cplusplus
extern "C" {
#endif

obs_properties_t *transcription_filter_properties(void *data);
void transcription_filter_defaults(obs_data_t *settings);

#ifdef __cplusplus
}
#endif

