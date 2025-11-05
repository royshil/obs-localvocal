#include "model-downloader.h"
#include "plugin-support.h"
#include "model-downloader-ui.h"
#include "model-find-utils.h"

#include <obs-module.h>
#include <obs-frontend-api.h>

#include <whisper.h>

#include <cstdlib>
#include <filesystem>
#include <optional>

std::filesystem::path obs_config_stdfs_path(char *config_folder)
{
#ifdef _WIN32
	// convert mbstring to wstring
	int count = MultiByteToWideChar(CP_UTF8, 0, config_folder, strlen(config_folder), NULL, 0);
	std::wstring config_folder_str(count, 0);
	MultiByteToWideChar(CP_UTF8, 0, config_folder, strlen(config_folder), &config_folder_str[0],
			    count);
	obs_log(LOG_INFO, "Config models folder: %S", config_folder_str.c_str());
#else
	std::string config_folder_str = config_folder;
	obs_log(LOG_INFO, "Config models folder: %s", config_folder_str.c_str());
#endif

	const std::filesystem::path config_folder_path =
		std::filesystem::absolute(config_folder_str);
	bfree(config_folder);
	return config_folder_path;
}

std::optional<std::filesystem::path> model_path(const ModelInfo &model_info,
						std::filesystem::path models_folder)
{
	const auto model_local_data_path = models_folder / model_info.local_folder_name;

	if (!std::filesystem::exists(model_local_data_path)) {
		obs_log(LOG_INFO, "Model not found in path: %s", model_local_data_path.c_str());
		return std::nullopt;
	} else {
		obs_log(LOG_INFO, "Model folder found in path: %s", model_local_data_path.c_str());
		return std::optional<std::filesystem::path>{model_local_data_path};
	}
}

std::optional<std::filesystem::path> model_data_path(const ModelInfo &model_info)
{
	char *data_folder = obs_module_file("models");

	obs_log(LOG_INFO, "Checking if model '%s' exists in data...",
		model_info.friendly_name.c_str());
	return model_path(model_info, obs_config_stdfs_path(data_folder));
}

std::optional<std::filesystem::path> model_config_path(const ModelInfo &model_info)
{
	char *config_folder = obs_module_config_path("models");
	if (!config_folder) {
		obs_log(LOG_INFO, "Config folder not set.");
		return std::nullopt;
	}
	obs_log(LOG_INFO, "Checking if model '%s' exists in config...",
		model_info.friendly_name.c_str());
	return model_path(model_info, obs_config_stdfs_path(config_folder));
}

std::optional<std::filesystem::path> find_model_folder(const ModelInfo &model_info)
{
	if (model_info.friendly_name.empty()) {
		obs_log(LOG_ERROR, "Model info is invalid. Friendly name is empty.");
		return std::nullopt;
	}
	if (model_info.local_folder_name.empty()) {
		obs_log(LOG_ERROR, "Model info is invalid. Local folder name is empty.");
		return std::nullopt;
	}
	if (model_info.files.empty()) {
		obs_log(LOG_ERROR, "Model info is invalid. Files list is empty.");
		return std::nullopt;
	}

	auto model_path = model_data_path(model_info);
	if (!model_path.has_value()) {
		model_path = model_config_path(model_info);
	}

	if (!model_path.has_value()) {
		obs_log(LOG_INFO, "Model '%s' not found.", model_info.friendly_name.c_str());
	}
	return model_path;
}

std::string find_model_bin_file(const ModelInfo &model_info)
{
	const auto model_local_folder_path = find_model_folder(model_info);
	if (!model_local_folder_path.has_value()) {
		return "";
	}

	return find_model_file_in_folder(model_local_folder_path.value().string());
}

void download_model_with_ui_dialog(const ModelInfo &model_info,
				   download_finished_callback_t download_finished_callback)
{
	// Start the model downloader UI
	ModelDownloader *model_downloader = new ModelDownloader(
		model_info, download_finished_callback, (QWidget *)obs_frontend_get_main_window());
	model_downloader->show();
}

void symlink_coreml_model(std::filesystem::path bin_model_folder,
			  std::filesystem::path coreml_model_folder, std::string coreml_model_name)
{
	auto source = coreml_model_folder / coreml_model_name;
	auto target = bin_model_folder / coreml_model_name;
	if (!std::filesystem::exists(target)) {
		obs_log(LOG_DEBUG, "Symlinking CoreML model from %s to %s", source.c_str(),
			target.c_str());
		std::filesystem::create_directory_symlink(source, target);
	} else {
		obs_log(LOG_DEBUG, "CoreML symlink already exists at %s", target.c_str());
	}
}

void download_coreml_encoder_model_if_available(
	const ModelInfo &bin_model_info,
	coreml_model_download_finished_callback_t download_finished_callback)
{
#ifdef LOCALVOCAL_WITH_COREML
	obs_log(LOG_DEBUG, "CoreML available");

	try {
		obs_log(LOG_DEBUG, "Checking for CoreML encoder model for %s",
			bin_model_info.friendly_name.c_str());
		auto model_path = std::filesystem::path(find_model_bin_file(bin_model_info));
		auto bin_model_folder = model_path.parent_path();
		auto model_stem = model_path.stem().string();
		obs_log(LOG_DEBUG, "Model stem: %s", model_stem.c_str());

		// Normalise stem
		auto pos = model_stem.rfind('-');
		if (pos != std::string::npos) {
			auto sub = model_stem.substr(pos);
			if (sub.size() == 5 && sub[1] == 'q' && sub[3] == '_') {
				model_stem = model_stem.substr(0, pos);
			}
		}

		obs_log(LOG_DEBUG, "Normalised model stem: %s", model_stem.c_str());

		std::string coreml_model_folder = std::string("coreml/").append(model_stem);

		for (const auto &model_info : get_sorted_models_info(
			     std::optional<ModelType>{MODEL_TYPE_TRANSCRIPTION_COREML})) {
			if (model_info.local_folder_name == coreml_model_folder) {
				auto model_local_folder_path = find_model_folder(model_info);
				if (!model_local_folder_path.has_value() ||
				    (find_model_file_in_folder(model_local_folder_path.value(),
							       ".mlmodelc")
					     .empty())) {
					// Download model
					obs_log(LOG_DEBUG,
						"Attempting to download CoreML encoder model %s",
						model_info.friendly_name.c_str());
					download_model_with_ui_dialog(model_info, [model_info,
										   bin_model_folder,
										   download_finished_callback](
											  int download_status,
											  const std::string
												  &path) {
						if (download_status == 0) {
							try {
								obs_log(LOG_INFO,
									"Downloaded CoreML model %s",
									model_info.friendly_name
										.c_str());
								auto downloaded_model_folder =
									std::filesystem::path(path);

								std::filesystem::path
									downloaded_model_zip =
										std::filesystem::
											current_path();
								for (auto const &dir_entry :
								     std::filesystem::directory_iterator{
									     downloaded_model_folder}) {
									if (dir_entry.path()
										    .extension() ==
									    ".zip") {
										downloaded_model_zip =
											dir_entry
												.path();
										break;
									}
								}
								if (downloaded_model_zip ==
								    std::filesystem::current_path()) {
									obs_log(LOG_ERROR,
										"zipped model not found");
									download_finished_callback();
									return;
								}

								obs_log(LOG_DEBUG,
									"zipped model: %s",
									downloaded_model_zip
										.c_str());
								std::string cmd = "unzip \"";
								cmd.append(downloaded_model_zip)
									.append("\" -d \"")
									.append(downloaded_model_folder)
									.append("\"");
								system(cmd.c_str());

								auto coreml_model_name =
									downloaded_model_zip.stem();
								auto unzipped_model =
									downloaded_model_folder /
									coreml_model_name;
								obs_log(LOG_DEBUG,
									"unzipped model: %s",
									unzipped_model.c_str());
								obs_log(LOG_DEBUG,
									"bin model folder: %s, Downloaded model folder: %s, coreml model name: %s",
									bin_model_folder.c_str(),
									downloaded_model_folder
										.c_str(),
									coreml_model_name.c_str());
								if (std::filesystem::exists(
									    unzipped_model)) {
									std::filesystem::remove(
										downloaded_model_zip);
									symlink_coreml_model(
										bin_model_folder,
										downloaded_model_folder,
										coreml_model_name);
								} else {
									obs_log(LOG_ERROR,
										"Unzipping CoreML model failed");
								}
							} catch (const std::exception &e) {
								obs_log(LOG_ERROR,
									"Error unpacking downloaded CoreML model: %s",
									e.what());
							}
						} else {
							obs_log(LOG_ERROR,
								"CoreML model download failed");
						}
						download_finished_callback();
					});
					return;
				} else {
					obs_log(LOG_DEBUG, "CoreML encoder model %s already exists",
						model_info.friendly_name.c_str());
					symlink_coreml_model(
						bin_model_folder, model_local_folder_path.value(),
						model_stem.append("-encoder.mlmodelc"));
					download_finished_callback();
					return;
				}
			}
		}
		obs_log(LOG_DEBUG, "Unable to find appropriate CoreML model");
		download_finished_callback();
	} catch (const std::exception &e) {
		obs_log(LOG_ERROR, "Error downloading CoreML model: %s", e.what());
	}
#else
	obs_log(LOG_DEBUG, "CoreML not available, not downloading encoder model for %s",
		bin_model_info.friendly_name.c_str());
	download_finished_callback();
#endif
}
