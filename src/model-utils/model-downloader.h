#ifndef MODEL_DOWNLOADER_H
#define MODEL_DOWNLOADER_H

#include <filesystem>
#include <string>
#include <optional>

#include <whisper.h>

#include "model-downloader-types.h"

std::optional<std::filesystem::path> find_model_folder(const ModelInfo &model_info);
std::string find_model_bin_file(const ModelInfo &model_info);
void download_coreml_encoder_model_if_available(
	const ModelInfo &model_info,
	coreml_model_download_finished_callback_t download_finished_callback);

// Start the model downloader UI dialog with a callback for when the download is finished
void download_model_with_ui_dialog(const ModelInfo &model_info,
				   download_finished_callback_t download_finished_callback);

#endif // MODEL_DOWNLOADER_H
