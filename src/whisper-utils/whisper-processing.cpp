#include <whisper.h>

#include <obs-module.h>

#include "plugin-support.h"
#include "transcription-filter-data.h"
#include "whisper-processing.h"
#include "whisper-utils.h"
#include "transcription-utils.h"

#ifdef _WIN32
#include <fstream>
#define NOMINMAX
#include <Windows.h>
#endif

#include "model-utils/model-find-utils.h"

#include <algorithm>
#include <chrono>

struct vad_state {
	bool vad_on;
	uint64_t start_timestamp;
	uint64_t end_timestamp;
};

// Taken from https://github.com/ggerganov/whisper.cpp/blob/master/examples/stream/stream.cpp
std::string to_timestamp(uint64_t t)
{
	uint64_t sec = t / 1000;
	uint64_t msec = t - sec * 1000;
	uint64_t min = sec / 60;
	sec = sec - min * 60;

	char buf[32];
	snprintf(buf, sizeof(buf), "%02d:%02d.%03d", (int)min, (int)sec, (int)msec);

	return std::string(buf);
}

struct whisper_context *init_whisper_context(const std::string &model_path_in,
					     struct transcription_filter_data *gf)
{
	std::string model_path = model_path_in;

	obs_log(LOG_INFO, "Loading whisper model from %s", model_path.c_str());

	if (std::filesystem::is_directory(model_path)) {
		obs_log(LOG_INFO,
			"Model path is a directory, not a file, looking for .bin file in folder");
		// look for .bin file
		const std::string model_bin_file = find_bin_file_in_folder(model_path);
		if (model_bin_file.empty()) {
			obs_log(LOG_ERROR, "Model bin file not found in folder: %s",
				model_path.c_str());
			return nullptr;
		}
		model_path = model_bin_file;
	}

	whisper_log_set(
		[](enum ggml_log_level level, const char *text, void *user_data) {
			UNUSED_PARAMETER(level);
			struct transcription_filter_data *ctx =
				static_cast<struct transcription_filter_data *>(user_data);
			// remove trailing newline
			char *text_copy = bstrdup(text);
			text_copy[strcspn(text_copy, "\n")] = 0;
			obs_log(ctx->log_level, "Whisper: %s", text_copy);
			bfree(text_copy);
		},
		gf);

	struct whisper_context_params cparams = whisper_context_default_params();
#ifdef LOCALVOCAL_WITH_CUDA
	cparams.use_gpu = true;
	obs_log(LOG_INFO, "Using CUDA GPU for inference, device %d", cparams.gpu_device);
#elif defined(LOCALVOCAL_WITH_CLBLAST)
	cparams.use_gpu = true;
	obs_log(LOG_INFO, "Using OpenCL for inference");
#else
	cparams.use_gpu = false;
	obs_log(LOG_INFO, "Using CPU for inference");
#endif

	cparams.dtw_token_timestamps = gf->enable_token_ts_dtw;
	if (gf->enable_token_ts_dtw) {
		obs_log(LOG_INFO, "DTW token timestamps enabled");
		cparams.dtw_aheads_preset = WHISPER_AHEADS_TINY_EN;
		// cparams.dtw_n_top = 4;
	} else {
		obs_log(LOG_INFO, "DTW token timestamps disabled");
		cparams.dtw_aheads_preset = WHISPER_AHEADS_NONE;
	}

	struct whisper_context *ctx = nullptr;
	try {
#ifdef _WIN32
		// convert model path UTF8 to wstring (wchar_t) for whisper
		int count = MultiByteToWideChar(CP_UTF8, 0, model_path.c_str(),
						(int)model_path.length(), NULL, 0);
		std::wstring model_path_ws(count, 0);
		MultiByteToWideChar(CP_UTF8, 0, model_path.c_str(), (int)model_path.length(),
				    &model_path_ws[0], count);

		// Read model into buffer
		std::ifstream modelFile(model_path_ws, std::ios::binary);
		if (!modelFile.is_open()) {
			obs_log(LOG_ERROR, "Failed to open whisper model file %s",
				model_path.c_str());
			return nullptr;
		}
		modelFile.seekg(0, std::ios::end);
		const size_t modelFileSize = modelFile.tellg();
		modelFile.seekg(0, std::ios::beg);
		std::vector<char> modelBuffer(modelFileSize);
		modelFile.read(modelBuffer.data(), modelFileSize);
		modelFile.close();

		// Initialize whisper
		ctx = whisper_init_from_buffer_with_params(modelBuffer.data(), modelFileSize,
							   cparams);
#else
		ctx = whisper_init_from_file_with_params(model_path.c_str(), cparams);
#endif
	} catch (const std::exception &e) {
		obs_log(LOG_ERROR, "Exception while loading whisper model: %s", e.what());
		return nullptr;
	}
	if (ctx == nullptr) {
		obs_log(LOG_ERROR, "Failed to load whisper model");
		return nullptr;
	}

	obs_log(LOG_INFO, "Whisper model loaded: %s", whisper_print_system_info());
	return ctx;
}

struct DetectionResultWithText run_whisper_inference(struct transcription_filter_data *gf,
						     const float *pcm32f_data_,
						     size_t pcm32f_num_samples,
						     uint64_t start_offset_ms = 0,
						     uint64_t end_offset_ms = 0)
{
	if (gf == nullptr) {
		obs_log(LOG_ERROR, "run_whisper_inference: gf is null");
		return {DETECTION_RESULT_UNKNOWN, "", start_offset_ms, end_offset_ms, {}};
	}

	if (pcm32f_data_ == nullptr || pcm32f_num_samples == 0) {
		obs_log(LOG_ERROR, "run_whisper_inference: pcm32f_data is null or size is 0");
		return {DETECTION_RESULT_UNKNOWN, "", start_offset_ms, end_offset_ms, {}};
	}

	obs_log(gf->log_level, "%s: processing %d samples, %.3f sec, %d threads", __func__,
		int(pcm32f_num_samples), float(pcm32f_num_samples) / WHISPER_SAMPLE_RATE,
		gf->whisper_params.n_threads);

	bool should_free_buffer = false;
	float *pcm32f_data = (float *)pcm32f_data_;
	size_t pcm32f_size = pcm32f_num_samples;

	if (pcm32f_num_samples < WHISPER_SAMPLE_RATE) {
		obs_log(gf->log_level,
			"Speech segment is less than 1 second, padding with zeros to 1 second");
		const size_t new_size = (size_t)(1.01f * (float)(WHISPER_SAMPLE_RATE));
		// create a new buffer and copy the data to it
		pcm32f_data = (float *)bzalloc(new_size * sizeof(float));
		memset(pcm32f_data, 0, new_size * sizeof(float));
		memcpy(pcm32f_data, pcm32f_data_, pcm32f_num_samples * sizeof(float));
		pcm32f_size = new_size;
		should_free_buffer = true;
	}

	// duration in ms
	const uint64_t duration_ms = (uint64_t)(pcm32f_size * 1000 / WHISPER_SAMPLE_RATE);
	const uint64_t t0 = start_offset_ms;
	const uint64_t t1 = end_offset_ms;

	std::lock_guard<std::mutex> lock(gf->whisper_ctx_mutex);
	if (gf->whisper_context == nullptr) {
		obs_log(LOG_WARNING, "whisper context is null");
		return {DETECTION_RESULT_UNKNOWN, "", t0, t1, {}};
	}

	// run the inference
	int whisper_full_result = -1;
	gf->whisper_params.duration_ms = (int)(duration_ms);
	try {
		whisper_full_result = whisper_full(gf->whisper_context, gf->whisper_params,
						   pcm32f_data, (int)pcm32f_size);
	} catch (const std::exception &e) {
		obs_log(LOG_ERROR, "Whisper exception: %s. Filter restart is required", e.what());
		whisper_free(gf->whisper_context);
		gf->whisper_context = nullptr;
		if (should_free_buffer) {
			bfree(pcm32f_data);
		}
		return {DETECTION_RESULT_UNKNOWN, "", t0, t1, {}};
	}
	if (should_free_buffer) {
		bfree(pcm32f_data);
	}

	if (whisper_full_result != 0) {
		obs_log(LOG_WARNING, "failed to process audio, error %d", whisper_full_result);
		return {DETECTION_RESULT_UNKNOWN, "", t0, t1, {}};
	} else {
		float sentence_p = 0.0f;
		std::string text = "";
		std::string tokenIds = "";
		std::vector<whisper_token_data> tokens;
		for (int n_segment = 0; n_segment < whisper_full_n_segments(gf->whisper_context);
		     ++n_segment) {
			const int n_tokens = whisper_full_n_tokens(gf->whisper_context, n_segment);
			for (int j = 0; j < n_tokens; ++j) {
				// get token
				whisper_token_data token = whisper_full_get_token_data(
					gf->whisper_context, n_segment, j);
				const char *token_str =
					whisper_token_to_str(gf->whisper_context, token.id);
				bool keep = true;
				// if the token starts with '[' and ends with ']', don't keep it
				if (token_str[0] == '[' &&
				    token_str[strlen(token_str) - 1] == ']') {
					keep = false;
				}
				// if this is a special token, don't keep it
				if (token.id >= 50256) {
					keep = false;
				}
				// if (j == n_tokens - 2 && token.p < 0.5) {
				// 	keep = false;
				// }
				// if (j == n_tokens - 3 && token.p < 0.4) {
				// 	keep = false;
				// }
				// if the second to last token is .id == 13 ('.'), don't keep it
				if (j == n_tokens - 2 && token.id == 13) {
					keep = false;
				}
				// token ids https://huggingface.co/openai/whisper-large-v3/raw/main/tokenizer.json
				// if (token.id > 50566 && token.id <= 51865) {
				// 	obs_log(gf->log_level,
				// 		"Large time token found (%d), this shouldn't happen",
				// 		token.id);
				// 	return {DETECTION_RESULT_UNKNOWN, "", 0, 0, {}};
				// }

				if (keep) {
					sentence_p += token.p;
					text += token_str;
					tokens.push_back(token);
				}
				obs_log(gf->log_level, "S %d, Token %d: %d\t%s\tp: %.3f [keep: %d]",
					n_segment, j, token.id, token_str, token.p, keep);
			}
		}
		sentence_p /= (float)tokens.size();
		if (sentence_p < gf->sentence_psum_accept_thresh) {
			obs_log(gf->log_level, "Sentence psum %.3f below threshold %.3f, skipping",
				sentence_p, gf->sentence_psum_accept_thresh);
			return {DETECTION_RESULT_SILENCE, "", t0, t1, {}};
		}

		obs_log(gf->log_level, "Decoded sentence: '%s'", text.c_str());

		if (gf->log_words) {
			obs_log(LOG_INFO, "[%s --> %s] (%.3f) %s", to_timestamp(t0).c_str(),
				to_timestamp(t1).c_str(), sentence_p, text.c_str());
		}

		if (text.empty() || text == "." || text == " " || text == "\n") {
			return {DETECTION_RESULT_SILENCE, "", t0, t1, {}};
		}

		return {DETECTION_RESULT_SPEECH, text, t0, t1, tokens};
	}
}

void process_audio_from_buffer(struct transcription_filter_data *gf)
{
	uint32_t num_new_frames_from_infos = 0;
	uint64_t start_timestamp = 0;
	bool save_overlap_region = true;

	{
		// scoped lock the buffer mutex
		std::lock_guard<std::mutex> lock(gf->whisper_buf_mutex);

		// We need (gf->frames - gf->last_num_frames) new frames for a full segment,
		const size_t remaining_frames_to_full_segment = gf->frames - gf->last_num_frames;

		obs_log(gf->log_level,
			"processing audio from buffer, %lu existing frames, %lu frames needed to full segment (%d frames)",
			gf->last_num_frames, remaining_frames_to_full_segment, gf->frames);

		// pop infos from the info buffer and mark the beginning timestamp from the first
		// info as the beginning timestamp of the segment
		struct transcription_filter_audio_info info_from_buf = {0};
		const size_t size_of_audio_info = sizeof(struct transcription_filter_audio_info);
		while (gf->info_buffer.size >= size_of_audio_info) {
			circlebuf_pop_front(&gf->info_buffer, &info_from_buf, size_of_audio_info);
			num_new_frames_from_infos += info_from_buf.frames;
			if (start_timestamp == 0) {
				start_timestamp = info_from_buf.timestamp;
			}
			// Check if we're within the needed segment length
			if (num_new_frames_from_infos > remaining_frames_to_full_segment) {
				// too big, push the last info into the buffer's front where it was
				num_new_frames_from_infos -= info_from_buf.frames;
				circlebuf_push_front(&gf->info_buffer, &info_from_buf,
						     size_of_audio_info);
				break;
			}
		}

		obs_log(gf->log_level,
			"with %lu remaining to full segment, popped %d frames from info buffer, pushed at %lu (overlap)",
			remaining_frames_to_full_segment, num_new_frames_from_infos,
			gf->last_num_frames);

		/* Pop from input circlebuf */
		for (size_t c = 0; c < gf->channels; c++) {
			// Push the new data to the end of the existing buffer copy_buffers[c]
			circlebuf_pop_front(&gf->input_buffers[c],
					    gf->copy_buffers[c] + gf->last_num_frames,
					    num_new_frames_from_infos * sizeof(float));
		}
	}

	if (gf->last_num_frames > 0) {
		obs_log(gf->log_level, "full segment, %lu frames overlap, %lu frames to process",
			gf->last_num_frames, gf->last_num_frames + num_new_frames_from_infos);
		gf->last_num_frames += num_new_frames_from_infos;
	} else {
		gf->last_num_frames = num_new_frames_from_infos;
		obs_log(gf->log_level, "first segment, no overlap exists, %lu frames to process",
			gf->last_num_frames);
	}

	obs_log(gf->log_level, "processing %lu frames (%d ms), start timestamp %llu",
		gf->last_num_frames,
		(int)((float)gf->last_num_frames * 1000.0f / (float)gf->sample_rate),
		start_timestamp);

	// time the audio processing
	auto start = std::chrono::high_resolution_clock::now();

	// resample to 16kHz
	float *resampled_16khz[MAX_PREPROC_CHANNELS];
	uint32_t resampled_16khz_frames;
	uint64_t ts_offset;
	audio_resampler_resample(gf->resampler_to_whisper, (uint8_t **)resampled_16khz,
				 &resampled_16khz_frames, &ts_offset,
				 (const uint8_t **)gf->copy_buffers, (uint32_t)gf->last_num_frames);

	obs_log(gf->log_level, "%d channels, %d frames, %f ms", (int)gf->channels,
		(int)resampled_16khz_frames,
		(float)resampled_16khz_frames / WHISPER_SAMPLE_RATE * 1000.0f);

	bool skipped_inference = false;
	uint32_t speech_start_frame = 0;
	uint32_t speech_end_frame = resampled_16khz_frames;

	if (gf->vad_enabled) {
		std::vector<float> vad_input(resampled_16khz[0],
					     resampled_16khz[0] + resampled_16khz_frames);
		gf->vad->process(vad_input, false);

		std::vector<timestamp_t> stamps = gf->vad->get_speech_timestamps();
		if (stamps.size() == 0) {
			obs_log(gf->log_level, "VAD detected no speech in %d frames",
				resampled_16khz_frames);
			skipped_inference = true;
			// prevent copying the buffer to the beginning (overlap)
			save_overlap_region = false;
		} else {
			// if the vad finds that start within the first 10% of the buffer, set the start to 0
			speech_start_frame = (stamps[0].start < (int)(resampled_16khz_frames / 10))
						     ? 0
						     : stamps[0].start;
			speech_end_frame = stamps.back().end;
			uint32_t number_of_frames = speech_end_frame - speech_start_frame;

			// if the speech is pressed up against the end of the buffer
			// apply the overlapped region, else don't
			save_overlap_region = (speech_end_frame == resampled_16khz_frames);

			obs_log(gf->log_level,
				"VAD detected speech from %d to %d (%d frames, %d ms)",
				speech_start_frame, speech_end_frame, number_of_frames,
				number_of_frames * 1000 / WHISPER_SAMPLE_RATE);

			// if the speech is less than 1 second - pad with zeros and send for inference
			if (number_of_frames > 0 && number_of_frames < WHISPER_SAMPLE_RATE) {
				obs_log(gf->log_level,
					"Speech segment is less than 1 second, padding with zeros to 1 second");
				// copy the speech segment to the beginning of the resampled buffer
				// use memmove to copy the speech segment to the beginning of the buffer
				memmove(resampled_16khz[0], resampled_16khz[0] + speech_start_frame,
					number_of_frames * sizeof(float));
				// zero out the rest of the buffer
				memset(resampled_16khz[0] + number_of_frames, 0,
				       (WHISPER_SAMPLE_RATE - number_of_frames) * sizeof(float));

				speech_start_frame = 0;
				speech_end_frame = WHISPER_SAMPLE_RATE;
			}
		}
	}

	if (!skipped_inference) {
		// run inference
		const struct DetectionResultWithText inference_result =
			run_whisper_inference(gf, resampled_16khz[0] + speech_start_frame,
					      speech_end_frame - speech_start_frame);

		if (inference_result.result == DETECTION_RESULT_SPEECH) {
			// output inference result to a text source
			set_text_callback(gf, inference_result);
		} else if (inference_result.result == DETECTION_RESULT_SILENCE) {
			// output inference result to a text source
			set_text_callback(gf, {inference_result.result, "[silence]", 0, 0, {}});
		}
	} else {
		if (gf->log_words) {
			obs_log(LOG_INFO, "skipping inference");
		}
		set_text_callback(gf, {DETECTION_RESULT_UNKNOWN, "[skip]", 0, 0, {}});
	}

	// end of timer
	auto end = std::chrono::high_resolution_clock::now();
	auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();
	const uint64_t last_num_frames_ms = gf->last_num_frames * 1000 / gf->sample_rate;
	obs_log(gf->log_level, "audio processing of %lu ms data took %d ms", last_num_frames_ms,
		(int)duration);

	if (save_overlap_region) {
		const uint64_t overlap_size_ms =
			(uint64_t)(gf->overlap_frames * 1000 / gf->sample_rate);
		obs_log(gf->log_level,
			"copying %lu overlap frames (%lu ms) from the end of the buffer (pos %lu) to the beginning",
			gf->overlap_frames, overlap_size_ms,
			gf->last_num_frames - gf->overlap_frames);
		for (size_t c = 0; c < gf->channels; c++) {
			// zero out the copy buffer, just in case
			memset(gf->copy_buffers[c], 0, gf->frames * sizeof(float));
			// move overlap frames from the end of the last copy_buffers to the beginning
			memmove(gf->copy_buffers[c],
				gf->copy_buffers[c] + gf->last_num_frames - gf->overlap_frames,
				gf->overlap_frames * sizeof(float));
		}
		gf->last_num_frames = gf->overlap_frames;
	} else {
		obs_log(gf->log_level, "no overlap needed. zeroing out the copy buffer");
		// zero out the copy buffer, just in case
		for (size_t c = 0; c < gf->channels; c++) {
			memset(gf->copy_buffers[c], 0, gf->frames * sizeof(float));
		}
		gf->last_num_frames = 0;
	}
}

void run_inference_and_callbacks(transcription_filter_data *gf, uint64_t start_offset_ms,
				 uint64_t end_offset_ms, int vad_state)
{
	// get the data from the entire whisper buffer
	const size_t pcm32f_size = gf->whisper_buffer.size / sizeof(float);
	// allocate a new buffer and copy the data to it
	float *pcm32f_data = (float *)bzalloc(pcm32f_size * sizeof(float));
	circlebuf_pop_back(&gf->whisper_buffer, pcm32f_data, pcm32f_size * sizeof(float));

	struct DetectionResultWithText inference_result =
		run_whisper_inference(gf, pcm32f_data, pcm32f_size, start_offset_ms, end_offset_ms);
	// output inference result to a text source
	set_text_callback(gf, inference_result);

	if (gf->enable_audio_chunks_callback) {
		audio_chunk_callback(gf, pcm32f_data, pcm32f_size, vad_state, inference_result);
	}

	// free the buffer
	bfree(pcm32f_data);
}

vad_state vad_based_segmentation(transcription_filter_data *gf, vad_state last_vad_state)
{
	uint32_t num_frames_from_infos = 0;
	uint64_t start_timestamp = 0;
	uint64_t end_timestamp = 0;
	size_t overlap_size = 0; //gf->sample_rate / 10;

	for (size_t c = 0; c < gf->channels; c++) {
		// if (!current_vad_on && gf->last_num_frames > overlap_size) {
		//     if (c == 0) {
		//         // print only once
		//         obs_log(gf->log_level, "VAD overlap: %lu frames", overlap_size);
		//     }
		//     // move 100ms from the end of copy_buffers to the beginning
		//     memmove(gf->copy_buffers[c], gf->copy_buffers[c] + gf->last_num_frames - overlap_size,
		//             overlap_size * sizeof(float));
		// } else {
		//     overlap_size = 0;
		// }
		// zero the rest of copy_buffers
		memset(gf->copy_buffers[c] + overlap_size, 0,
		       (gf->frames - overlap_size) * sizeof(float));
	}

	{
		// scoped lock the buffer mutex
		std::lock_guard<std::mutex> lock(gf->whisper_buf_mutex);

		obs_log(gf->log_level,
			"vad based segmentation. currently %lu bytes in the audio input buffer",
			gf->input_buffers[0].size);

		// max number of frames is 10 seconds worth of audio
		const size_t max_num_frames = gf->sample_rate * 10;

		// pop all infos from the info buffer and mark the beginning timestamp from the first
		// info as the beginning timestamp of the segment
		struct transcription_filter_audio_info info_from_buf = {0};
		const size_t size_of_audio_info = sizeof(transcription_filter_audio_info);
		while (gf->info_buffer.size >= size_of_audio_info) {
			circlebuf_pop_front(&gf->info_buffer, &info_from_buf, size_of_audio_info);
			num_frames_from_infos += info_from_buf.frames;
			if (start_timestamp == 0) {
				start_timestamp = info_from_buf.timestamp;
			}
			// Check if we're within the needed segment length
			if (num_frames_from_infos > max_num_frames) {
				// too big, push the last info into the buffer's front where it was
				num_frames_from_infos -= info_from_buf.frames;
				circlebuf_push_front(&gf->info_buffer, &info_from_buf,
						     size_of_audio_info);
				break;
			}
		}
		end_timestamp = info_from_buf.timestamp;

		/* Pop from input circlebuf */
		for (size_t c = 0; c < gf->channels; c++) {
			// Push the new data to copy_buffers[c]
			circlebuf_pop_front(&gf->input_buffers[c],
					    gf->copy_buffers[c] + overlap_size,
					    num_frames_from_infos * sizeof(float));
		}
	}

	obs_log(gf->log_level, "found %d frames from info buffer. %lu in overlap",
		num_frames_from_infos, overlap_size);
	gf->last_num_frames = num_frames_from_infos + overlap_size;

	// resample to 16kHz
	float *resampled_16khz[MAX_PREPROC_CHANNELS];
	uint32_t resampled_16khz_frames;
	uint64_t ts_offset;
	audio_resampler_resample(gf->resampler_to_whisper, (uint8_t **)resampled_16khz,
				 &resampled_16khz_frames, &ts_offset,
				 (const uint8_t **)gf->copy_buffers,
				 (uint32_t)num_frames_from_infos);

	obs_log(gf->log_level, "resampled: %d channels, %d frames, %f ms", (int)gf->channels,
		(int)resampled_16khz_frames,
		(float)resampled_16khz_frames / WHISPER_SAMPLE_RATE * 1000.0f);

	std::vector<float> vad_input(resampled_16khz[0],
				     resampled_16khz[0] + resampled_16khz_frames);
	gf->vad->process(vad_input, false);

	const uint64_t start_offset_ms = start_timestamp / 1000000 - gf->start_timestamp_ms;
	const uint64_t end_offset_ms = end_timestamp / 1000000 - gf->start_timestamp_ms;

	vad_state current_vad_state = {false, start_offset_ms, end_offset_ms};

	std::vector<timestamp_t> stamps = gf->vad->get_speech_timestamps();
	if (stamps.size() == 0) {
		obs_log(gf->log_level, "VAD detected no speech in %d frames",
			resampled_16khz_frames);
		if (last_vad_state.vad_on) {
			obs_log(gf->log_level, "Last VAD was ON: segment end -> send to inference");
			run_inference_and_callbacks(gf, last_vad_state.start_timestamp,
						    last_vad_state.end_timestamp, VAD_STATE_WAS_ON);
		}

		if (gf->enable_audio_chunks_callback) {
			audio_chunk_callback(gf, resampled_16khz[0], resampled_16khz_frames,
					     VAD_STATE_IS_OFF,
					     {DETECTION_RESULT_SILENCE,
					      "[silence]",
					      current_vad_state.start_timestamp,
					      current_vad_state.end_timestamp,
					      {}});
		}
	} else {
		// process vad segments
		for (size_t i = 0; i < stamps.size(); i++) {
			int start_frame = stamps[i].start;
			if (i > 0) {
				// if this is not the first segment, start from the end of the previous segment
				start_frame = stamps[i - 1].end;
			} else {
				// take at least 100ms of audio before the first speech segment, if available
				start_frame = std::max(0, start_frame - WHISPER_SAMPLE_RATE / 10);
			}

			int end_frame = stamps[i].end;
			if (i == stamps.size() - 1 && stamps[i].end < (int)resampled_16khz_frames) {
				// take at least 100ms of audio after the last speech segment, if available
				end_frame = std::min(end_frame + WHISPER_SAMPLE_RATE / 10,
						     (int)resampled_16khz_frames);
			}

			const int number_of_frames = end_frame - start_frame;
			// push the data into gf-whisper_buffer
			circlebuf_push_back(&gf->whisper_buffer, resampled_16khz[0] + start_frame,
					    number_of_frames * sizeof(float));
			obs_log(gf->log_level,
				"VAD segment %d. pushed %d to %d (%d frames / %lu ms). current size: %lu bytes / %lu frames / %lu ms",
				i, start_frame, end_frame, number_of_frames,
				number_of_frames * 1000 / WHISPER_SAMPLE_RATE,
				gf->whisper_buffer.size, gf->whisper_buffer.size / sizeof(float),
				gf->whisper_buffer.size / sizeof(float) * 1000 /
					WHISPER_SAMPLE_RATE);

			// if the segment is in the middle of the buffer, send it to inference
			if (stamps[i].end < (int)resampled_16khz_frames) {
				// new "ending" segment (not up to the end of the buffer)
				obs_log(gf->log_level, "VAD segment end -> send to inference");
				// find the end timestamp of the segment
				const uint64_t segment_end_ts =
					start_offset_ms + end_frame * 1000 / WHISPER_SAMPLE_RATE;
				run_inference_and_callbacks(gf, last_vad_state.start_timestamp,
							    segment_end_ts,
							    last_vad_state.vad_on
								    ? VAD_STATE_WAS_ON
								    : VAD_STATE_WAS_OFF);
				current_vad_state.vad_on = false;
				current_vad_state.start_timestamp = current_vad_state.end_timestamp;
				current_vad_state.end_timestamp = 0;
			} else {
				current_vad_state.vad_on = true;
				if (last_vad_state.vad_on) {
					current_vad_state.start_timestamp =
						last_vad_state.start_timestamp;
				} else {
					current_vad_state.start_timestamp =
						start_offset_ms +
						start_frame * 1000 / WHISPER_SAMPLE_RATE;
				}
				obs_log(gf->log_level,
					"end not reached. vad state: start ts: %llu, end ts: %llu",
					current_vad_state.start_timestamp,
					current_vad_state.end_timestamp);
			}
			last_vad_state = current_vad_state;
		}
	}

	return current_vad_state;
}

void whisper_loop(void *data)
{
	if (data == nullptr) {
		obs_log(LOG_ERROR, "whisper_loop: data is null");
		return;
	}

	struct transcription_filter_data *gf =
		static_cast<struct transcription_filter_data *>(data);

	obs_log(LOG_INFO, "starting whisper thread");

	vad_state current_vad_state = {false, 0, 0};
	// 500 ms worth of audio is needed for VAD segmentation
	uint32_t min_num_bytes_for_vad = (gf->sample_rate / 2) * sizeof(float);

	// Thread main loop
	while (true) {
		{
			std::lock_guard<std::mutex> lock(gf->whisper_ctx_mutex);
			if (gf->whisper_context == nullptr) {
				obs_log(LOG_WARNING, "Whisper context is null, exiting thread");
				break;
			}
		}

		uint32_t num_bytes_on_input = 0;
		{
			// scoped lock the buffer mutex
			std::lock_guard<std::mutex> lock(gf->whisper_buf_mutex);
			num_bytes_on_input = (uint32_t)gf->input_buffers[0].size;
		}

		// only run vad segmentation if there are at least 500 ms of audio in the buffer
		if (num_bytes_on_input > min_num_bytes_for_vad) {
			current_vad_state = vad_based_segmentation(gf, current_vad_state);
		}

		// Sleep for 10 ms using the condition variable wshiper_thread_cv
		// This will wake up the thread if there is new data in the input buffer
		// or if the whisper context is null
		std::unique_lock<std::mutex> lock(gf->whisper_ctx_mutex);
		gf->wshiper_thread_cv.wait_for(lock, std::chrono::milliseconds(50));
	}

	obs_log(LOG_INFO, "exiting whisper thread");
}
