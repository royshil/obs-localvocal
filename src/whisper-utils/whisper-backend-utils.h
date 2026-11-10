#ifndef WHISPER_BACKEND_UTILS_H
#define WHISPER_BACKEND_UTILS_H

#include <string>

inline bool is_whisper_backend_changed(int current_backend_device, int new_backend_device,
				       bool current_enable_flash_attn, bool new_enable_flash_attn)
{
	return current_backend_device != new_backend_device ||
	       current_enable_flash_attn != new_enable_flash_attn;
}

// True when an external model is selected and its file isn't the one loaded.
// The model selection itself doesn't change when only the file does.
inline bool is_external_whisper_model_changed(const std::string &model_path,
					      const std::string &external_model_file_path,
					      const std::string &loaded_model_file_path)
{
	return model_path.find("!!!external!!!") != std::string::npos &&
	       !external_model_file_path.empty() &&
	       external_model_file_path != loaded_model_file_path;
}

#endif // WHISPER_BACKEND_UTILS_H
