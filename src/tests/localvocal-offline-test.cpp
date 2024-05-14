#include <iostream>
#include <string>
#include <codecvt>
#include <vector>
#include <fstream>
#include <thread>
#include <mutex>
#include <chrono>
#include <iomanip>
#include <regex>
#include <algorithm>

#include "transcription-filter-data.h"
#include "transcription-filter.h"
#include "transcription-utils.h"
#include "whisper-utils/whisper-utils.h"

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>

#ifdef _WIN32
#include <Windows.h>
#endif

void obs_log(int log_level, const char *format, ...)
{
	if (log_level == LOG_DEBUG) {
		return;
	}
	// print timestamp in format [HH:MM:SS.mmm], use std::chrono::system_clock
	auto now = std::chrono::system_clock::now();
	auto now_ms = std::chrono::time_point_cast<std::chrono::milliseconds>(now);
	auto epoch = now_ms.time_since_epoch();

	// convert to std::time_t in order to convert to std::tm
	std::time_t now_time_t = std::chrono::system_clock::to_time_t(now);
	std::tm now_tm = *std::localtime(&now_time_t);

	// print timestamp
	printf("[%02d:%02d:%02d.%03d] ", now_tm.tm_hour, now_tm.tm_min, now_tm.tm_sec,
	       (int)(epoch.count() % 1000));

	// print log level
	switch (log_level) {
	case LOG_DEBUG:
		printf("[DEBUG] ");
		break;
	case LOG_INFO:
		printf("[INFO] ");
		break;
	case LOG_WARNING:
		printf("[WARNING] ");
		break;
	case LOG_ERROR:
		printf("[ERROR] ");
		break;
	default:
		printf("[UNKNOWN] ");
		break;
	}
	// print format with arguments with utf-8 support
	va_list args;
	va_start(args, format);
	vprintf(format, args);
	va_end(args);

	printf("\n");
}

#if defined(_WIN32) || defined(__APPLE__)

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/frame.h>
#include <libavutil/mem.h>
#include <libavutil/opt.h>
#include <libswresample/swresample.h>
}

std::vector<std::vector<uint8_t>>
read_audio_file(const char *filename, std::function<void(int, int)> initialization_callback)
{
	obs_log(LOG_INFO, "Reading audio file %s", filename);

	AVFormatContext *formatContext = nullptr;
	int ret = avformat_open_input(&formatContext, filename, nullptr, nullptr);
	if (ret != 0) {
		char errbuf[AV_ERROR_MAX_STRING_SIZE];
		av_make_error_string(errbuf, AV_ERROR_MAX_STRING_SIZE, ret);
		obs_log(LOG_ERROR, "Error opening file: %s", errbuf);
		return {};
	}

	if (avformat_find_stream_info(formatContext, nullptr) < 0) {
		obs_log(LOG_ERROR, "Error finding stream information");
		return {};
	}

	int audioStreamIndex = -1;
	for (unsigned int i = 0; i < formatContext->nb_streams; i++) {
		if (formatContext->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
			audioStreamIndex = i;
			break;
		}
	}

	if (audioStreamIndex == -1) {
		obs_log(LOG_ERROR, "No audio stream found");
		return {};
	}

	// print information about the file
	av_dump_format(formatContext, 0, filename, 0);

	// if the sample format is not float, return
	if (formatContext->streams[audioStreamIndex]->codecpar->format != AV_SAMPLE_FMT_FLTP) {
		obs_log(LOG_ERROR,
			"Sample format is not float (it is %s). Encode the audio file with float planar sample format."
			" For example, use the command 'ffmpeg -i input.mp3 -f f32le -acodec pcm_f32le output.f32le'",
			"convert the audio file to float format.",
			av_get_sample_fmt_name(
				(AVSampleFormat)formatContext->streams[audioStreamIndex]
					->codecpar->format));
		return {};
	}

	initialization_callback(formatContext->streams[audioStreamIndex]->codecpar->sample_rate,
				formatContext->streams[audioStreamIndex]->codecpar->channels);

	AVCodecParameters *codecParams = formatContext->streams[audioStreamIndex]->codecpar;
	const AVCodec *codec = avcodec_find_decoder(codecParams->codec_id);
	if (!codec) {
		obs_log(LOG_ERROR, "Decoder not found");
		return {};
	}

	AVCodecContext *codecContext = avcodec_alloc_context3(codec);
	if (!codecContext) {
		obs_log(LOG_ERROR, "Failed to allocate codec context");
		return {};
	}

	if (avcodec_parameters_to_context(codecContext, codecParams) < 0) {
		obs_log(LOG_ERROR, "Failed to copy codec parameters to codec context");
		return {};
	}

	if (avcodec_open2(codecContext, codec, nullptr) < 0) {
		obs_log(LOG_ERROR, "Failed to open codec");
		return {};
	}

	AVFrame *frame = av_frame_alloc();
	AVPacket packet;

	std::vector<std::vector<uint8_t>> buffer(
		formatContext->streams[audioStreamIndex]->codecpar->channels);

	while (av_read_frame(formatContext, &packet) >= 0) {
		if (packet.stream_index == audioStreamIndex) {
			if (avcodec_send_packet(codecContext, &packet) == 0) {
				while (avcodec_receive_frame(codecContext, frame) == 0) {
					// push data to the buffer
					for (int j = 0; j < codecContext->channels; j++) {
						buffer[j].insert(buffer[j].end(), frame->data[j],
								 frame->data[j] +
									 frame->linesize[0]);
					}
				}
			}
		}
		av_packet_unref(&packet);
	}

	av_frame_free(&frame);
	avcodec_free_context(&codecContext);
	avformat_close_input(&formatContext);

	return buffer;
}

#endif

transcription_filter_data *
create_context(int sample_rate, int channels, const std::string &whisper_model_path,
	       const std::string &silero_vad_model_file, const std::string &ct2ModelFolder,
	       const whisper_sampling_strategy whisper_sampling_method = WHISPER_SAMPLING_GREEDY)
{
	struct transcription_filter_data *gf = new transcription_filter_data();

	gf->log_level = LOG_DEBUG;
	gf->channels = channels;
	gf->sample_rate = sample_rate;
	gf->frames = (size_t)((float)gf->sample_rate * 10.0f);
	gf->last_num_frames = 0;
	gf->step_size_msec = 3000;
	gf->min_sub_duration = 3000;
	gf->last_sub_render_time = 0;
	gf->save_srt = false;
	gf->truncate_output_file = false;
	gf->save_only_while_recording = false;
	gf->rename_file_to_match_recording = false;
	gf->process_while_muted = false;
	gf->buffered_output = false;
	gf->fix_utf8 = true;

	for (size_t i = 0; i < gf->channels; i++) {
		circlebuf_init(&gf->input_buffers[i]);
	}
	circlebuf_init(&gf->info_buffer);
	circlebuf_init(&gf->whisper_buffer);

	// allocate copy buffers
	gf->copy_buffers[0] =
		static_cast<float *>(malloc(gf->channels * gf->frames * sizeof(float)));
	for (size_t c = 1; c < gf->channels; c++) { // set the channel pointers
		gf->copy_buffers[c] = gf->copy_buffers[0] + c * gf->frames;
	}
	obs_log(LOG_INFO, " allocated %llu bytes ", gf->channels * gf->frames * sizeof(float));

	gf->overlap_ms = 150;
	gf->overlap_frames = (size_t)((float)gf->sample_rate / (1000.0f / (float)gf->overlap_ms));
	obs_log(gf->log_level, "channels %d, frames %d, sample_rate %d", (int)gf->channels,
		(int)gf->frames, gf->sample_rate);

	obs_log(gf->log_level, "setup audio resampler");
	struct resample_info src, dst;
	src.samples_per_sec = gf->sample_rate;
	src.format = AUDIO_FORMAT_FLOAT_PLANAR;
	src.speakers = convert_speaker_layout((uint8_t)gf->channels);

	dst.samples_per_sec = WHISPER_SAMPLE_RATE;
	dst.format = AUDIO_FORMAT_FLOAT_PLANAR;
	dst.speakers = convert_speaker_layout((uint8_t)1);

	gf->resampler_to_whisper = audio_resampler_create(&dst, &src);

	gf->whisper_model_file_currently_loaded = "";
	gf->output_file_path = std::string("output.txt");
	gf->whisper_model_path = std::string(""); // The update function will set the model path
	gf->whisper_context = nullptr;

	// gf->captions_monitor.initialize(
	// 	gf,
	// 	[gf](const std::string &text) {
	// 		obs_log(LOG_INFO, "Captions: %s", text.c_str());
	// 	},
	// 	30, std::chrono::seconds(10));

	gf->vad_enabled = true;
	gf->log_words = true;
	gf->caption_to_stream = false;
	gf->start_timestamp_ms = now_ms();
	gf->sentence_number = 1;
	gf->last_sub_render_time = 0;
	gf->buffered_output = false;

	gf->source_lang = "";
	gf->target_lang = "";
	gf->translation_ctx.add_context = true;
	gf->translation_output = "";
	gf->suppress_sentences = "";
	gf->translate = false;
	gf->sentence_psum_accept_thresh = 0.4;

	gf->whisper_params = whisper_full_default_params(whisper_sampling_method);
	gf->whisper_params.duration_ms = 3000;
	gf->whisper_params.language = "en";
	gf->whisper_params.initial_prompt = "";
	gf->whisper_params.n_threads = 4;
	gf->whisper_params.n_max_text_ctx = 16384;
	gf->whisper_params.translate = false;
	gf->whisper_params.no_context = false;
	gf->whisper_params.single_segment = true;
	gf->whisper_params.print_special = false;
	gf->whisper_params.print_progress = false;
	gf->whisper_params.print_realtime = false;
	gf->whisper_params.print_timestamps = false;
	gf->whisper_params.token_timestamps = false;
	gf->whisper_params.thold_pt = 0.01;
	gf->whisper_params.thold_ptsum = 0.01;
	gf->whisper_params.max_len = 0;
	gf->whisper_params.split_on_word = false;
	gf->whisper_params.max_tokens = 0;
	gf->whisper_params.speed_up = false;
	gf->whisper_params.suppress_blank = true;
	gf->whisper_params.suppress_non_speech_tokens = true;
	gf->whisper_params.temperature = 0.1;
	gf->whisper_params.max_initial_ts = 1.0;
	gf->whisper_params.length_penalty = -1;
	gf->active = true;

	start_whisper_thread_with_path(gf, whisper_model_path, silero_vad_model_file.c_str());

	obs_log(gf->log_level, "context created");

	return gf;
}

void set_text_callback(struct transcription_filter_data *gf,
		       const DetectionResultWithText &resultIn)
{
	DetectionResultWithText result = resultIn;

	if (!result.text.empty() && result.result == DETECTION_RESULT_SPEECH) {
		std::string str_copy = result.text;
		if (gf->fix_utf8) {
			str_copy = fix_utf8(str_copy);
		}
		str_copy = remove_leading_trailing_nonalpha(str_copy);

		// if suppression is enabled, check if the text is in the suppression list
		if (!gf->suppress_sentences.empty()) {
			// split the suppression list by newline into individual sentences
			std::vector<std::string> suppress_sentences_list =
				split(gf->suppress_sentences, '\n');
			const std::string original_str_copy = str_copy;
			// check if the text is in the suppression list
			for (const std::string &suppress_sentence : suppress_sentences_list) {
				// if suppress_sentence exists within str_copy, remove it (replace with "")
				str_copy = std::regex_replace(str_copy,
							      std::regex(suppress_sentence), "");
			}
			if (original_str_copy != str_copy) {
				obs_log(LOG_INFO, "Suppression: '%s' -> '%s'",
					original_str_copy.c_str(), str_copy.c_str());
			}
		}

		if (gf->translate) {
			obs_log(gf->log_level, "Translating text. %s -> %s",
				gf->source_lang.c_str(), gf->target_lang.c_str());
			std::string translated_text;
			if (translate(gf->translation_ctx, str_copy, gf->source_lang,
				      gf->target_lang,
				      translated_text) == OBS_POLYGLOT_TRANSLATION_SUCCESS) {
				if (gf->log_words) {
					obs_log(LOG_INFO, "Translation: '%s' -> '%s'",
						str_copy.c_str(), translated_text.c_str());
				}
				// overwrite the original text with the translated text
				str_copy = str_copy + " -> " + translated_text;
			} else {
				obs_log(gf->log_level, "Failed to translate text");
			}
		}

		std::ofstream output_file(gf->output_file_path, std::ios::app);
		output_file << str_copy << std::endl;
		output_file.close();
	}

	/*


	if (gf->buffered_output) {
		gf->captions_monitor.addWords(result.tokens);
	}

	if (gf->output_file_path != "" && gf->text_source_name.empty()) {
		// Check if we should save the sentence
		// should the file be truncated?
		std::ios_base::openmode openmode = std::ios::out;
		if (gf->truncate_output_file) {
			openmode |= std::ios::trunc;
		} else {
			openmode |= std::ios::app;
		}
		if (!gf->save_srt) {
			// Write raw sentence to file
			std::ofstream output_file(gf->output_file_path, openmode);
			output_file << str_copy << std::endl;
			output_file.close();
		} else {
			obs_log(gf->log_level, "Saving sentence to file %s, sentence #%d",
				gf->output_file_path.c_str(), gf->sentence_number);
			// Append sentence to file in .srt format
			std::ofstream output_file(gf->output_file_path, openmode);
			output_file << gf->sentence_number << std::endl;
			// use the start and end timestamps to calculate the start and end time in srt format
			auto format_ts_for_srt = [&output_file](uint64_t ts) {
				uint64_t time_s = ts / 1000;
				uint64_t time_m = time_s / 60;
				uint64_t time_h = time_m / 60;
				uint64_t time_ms_rem = ts % 1000;
				uint64_t time_s_rem = time_s % 60;
				uint64_t time_m_rem = time_m % 60;
				uint64_t time_h_rem = time_h % 60;
				output_file << std::setfill('0') << std::setw(2) << time_h_rem
					    << ":" << std::setfill('0') << std::setw(2)
					    << time_m_rem << ":" << std::setfill('0')
					    << std::setw(2) << time_s_rem << ","
					    << std::setfill('0') << std::setw(3) << time_ms_rem;
			};
			format_ts_for_srt(result.start_timestamp_ms);
			output_file << " --> ";
			format_ts_for_srt(result.end_timestamp_ms);
			output_file << std::endl;

			output_file << str_copy << std::endl;
			output_file << std::endl;
			output_file.close();
			gf->sentence_number++;
		}
	}
    */
};

void release_context(transcription_filter_data *gf)
{
	obs_log(LOG_INFO, "destroy");
	shutdown_whisper_thread(gf);

	if (gf->resampler_to_whisper) {
		audio_resampler_destroy(gf->resampler_to_whisper);
	}

	{
		std::lock_guard<std::mutex> lockbuf(gf->whisper_buf_mutex);
		free(gf->copy_buffers[0]);
		gf->copy_buffers[0] = nullptr;
		for (size_t i = 0; i < gf->channels; i++) {
			circlebuf_free(&gf->input_buffers[i]);
		}
	}
	circlebuf_free(&gf->info_buffer);
	circlebuf_free(&gf->whisper_buffer);

	delete gf;
}

int wmain(int argc, wchar_t *argv[])
{
	if (argc < 3) {
		std::cout << "Usage: localvocal-offline-test <audio-file> <config_json_file>"
			  << std::endl;
		return 1;
	}

#ifdef _WIN32
	// Set console output to UTF-8
	SetConsoleOutputCP(CP_UTF8);
#endif

	std::wstring file = argv[1];
	std::wstring configJsonFile = argv[2];

	std::wstring_convert<std::codecvt_utf8<wchar_t>> converter;
	std::string filenameStr = converter.to_bytes(file);

	// read the configuration json file
	std::ifstream config_stream(configJsonFile);
	if (!config_stream.is_open()) {
		std::cout << "Failed to open config file" << std::endl;
		return 1;
	}
	nlohmann::json config;
	config_stream >> config;
	config_stream.close();

	// get the configuration values
	std::string whisperModelPathStr = config["whisper_model_path"];
	std::string sileroVadModelFileStr = config["silero_vad_model_file"];
	std::string sourceLanguageStr = config["source_language"];
	std::string targetLanguageStr = config["target_language"];
	std::string whisperLanguageStr = config["whisper_language"];
	std::string ct2ModelFolderStr = config["ct2_model_folder"];
	std::string logLevelStr = config["log_level"];
	whisper_sampling_strategy whisper_sampling_method = config["whisper_sampling_method"];

	std::cout << "LocalVocal Offline Test" << std::endl;
	transcription_filter_data *gf = nullptr;

	std::vector<std::vector<uint8_t>> audio =
		read_audio_file(filenameStr.c_str(), [&](int sample_rate, int channels) {
			gf = create_context(sample_rate, channels, whisperModelPathStr,
					    sileroVadModelFileStr, ct2ModelFolderStr,
					    whisper_sampling_method);
			if (sourceLanguageStr.empty() || targetLanguageStr.empty() ||
			    sourceLanguageStr == "none" || targetLanguageStr == "none") {
				obs_log(LOG_INFO,
					"Source or target translation language are empty or disabled");
			} else {
				obs_log(LOG_INFO, "Setting translation languages");
				gf->source_lang = sourceLanguageStr;
				gf->target_lang = targetLanguageStr;
				build_and_enable_translation(gf, ct2ModelFolderStr.c_str());
			}
			gf->whisper_params.language = whisperLanguageStr.c_str();
			if (config.contains("fix_utf8")) {
				obs_log(LOG_INFO, "Setting fix_utf8 to %s",
					config["fix_utf8"] ? "true" : "false");
				gf->fix_utf8 = config["fix_utf8"];
			}
			if (config.contains("suppress_sentences")) {
				obs_log(LOG_INFO, "Setting suppress_sentences to %ls",
					config["suppress_sentences"].get<std::string>().c_str());
				gf->suppress_sentences =
					config["suppress_sentences"].get<std::string>();
			}
			if (config.contains("overlap_ms")) {
				obs_log(LOG_INFO, "Setting overlap_ms to %d",
					config["overlap_ms"].get<int>());
				gf->overlap_ms = config["overlap_ms"];
				gf->overlap_frames = (size_t)((float)gf->sample_rate /
							      (1000.0f / (float)gf->overlap_ms));
			}
			// set log level
			if (logLevelStr == "debug") {
				gf->log_level = LOG_DEBUG;
			} else if (logLevelStr == "info") {
				gf->log_level = LOG_INFO;
			} else if (logLevelStr == "warning") {
				gf->log_level = LOG_WARNING;
			} else if (logLevelStr == "error") {
				gf->log_level = LOG_ERROR;
			}
		});

	if (gf == nullptr) {
		std::cout << "Failed to create context" << std::endl;
		return 1;
	}
	if (audio.empty()) {
		std::cout << "Failed to read audio file" << std::endl;
		return 1;
	}

	// truncate the output file
	obs_log(LOG_INFO, "Truncating output file");
	std::ofstream output_file(gf->output_file_path, std::ios::trunc);
	output_file.close();

	// fill up the whisper buffer
	{
		obs_log(LOG_INFO, "Sending samples to whisper buffer");
		// 25 ms worth of frames
		int frames = gf->sample_rate * 25 / 1000;
		const int frame_size_bytes = sizeof(float);
		int frames_size_bytes = frames * frame_size_bytes;
		int frames_count = 0;
		while (true) {
			// check if there are enough frames left in the audio buffer
			if ((frames_count + frames) > (audio[0].size() / frame_size_bytes)) {
				// only take the remaining frames
				frames = audio[0].size() / frame_size_bytes - frames_count;
				frames_size_bytes = frames * frame_size_bytes;
			}
			{
				std::lock_guard<std::mutex> lock(gf->whisper_buf_mutex);

				// push back current audio data to input circlebuf
				for (size_t c = 0; c < gf->channels; c++) {
					circlebuf_push_back(&gf->input_buffers[c],
							    audio[c].data() +
								    frames_count * frame_size_bytes,
							    frames_size_bytes);
				}
				// push audio packet info (timestamp/frame count) to info circlebuf
				struct transcription_filter_audio_info info = {0};
				info.frames = frames; // number of frames in this packet
				// make a timestamp from the current clock time
				info.timestamp =
					std::chrono::duration_cast<std::chrono::nanoseconds>(
						std::chrono::system_clock::now().time_since_epoch())
						.count();
				circlebuf_push_back(&gf->info_buffer, &info, sizeof(info));
			}
			frames_count += frames;
			if (frames_count >= audio[0].size() / frame_size_bytes) {
				break;
			}
			// sleep for 25 ms
			std::this_thread::sleep_for(std::chrono::milliseconds(25));
		}
		// push a second of silence to the input circlebuf
		frames = 2 * gf->sample_rate;
		frames_size_bytes = frames * frame_size_bytes;
		for (size_t c = 0; c < gf->channels; c++) {
			circlebuf_push_back(&gf->input_buffers[c],
					    std::vector<uint8_t>(frames_size_bytes).data(),
					    frames_size_bytes);
		}
		// push audio packet info (timestamp/frame count) to info circlebuf
		struct transcription_filter_audio_info info = {0};
		info.frames = frames; // number of frames in this packet
		// make a timestamp from the current frame count
		info.timestamp = frames_count * 1000 / gf->sample_rate;
		circlebuf_push_back(&gf->info_buffer, &info, sizeof(info));
	}

	obs_log(LOG_INFO, "Buffer filled with %d frames",
		(int)gf->input_buffers[0].size / sizeof(float));

	// wait for processing to finish
	obs_log(LOG_INFO, "Waiting for processing to finish");
	while (true) {
		std::this_thread::sleep_for(std::chrono::milliseconds(100));
		// check the input circlebuf has more data
		size_t input_buf_size = 0;
		{
			std::lock_guard<std::mutex> lock(gf->whisper_buf_mutex);
			input_buf_size = gf->input_buffers[0].size;
		}

		if (input_buf_size == 0) {
			break;
		}
	}

	release_context(gf);

	obs_log(LOG_INFO, "LocalVocal Offline Test Done");
	return 0;
}