#include <iostream>

#include "whisper-utils/whisper-backend-utils.h"

struct backend_change_test_case {
	const char *name;
	int current_backend_device;
	int new_backend_device;
	bool current_enable_flash_attn;
	bool new_enable_flash_attn;
	bool expected;
};

struct external_model_change_test_case {
	const char *name;
	const char *model_path;
	const char *external_model_file_path;
	const char *loaded_model_file_path;
	bool expected;
};

int main()
{
	const backend_change_test_case test_cases[] = {
		{"same backend and Flash Attention", -1, -1, false, false, false},
		{"different backend", -1, 0, false, false, true},
		{"changed Flash Attention", -1, -1, false, true, true},
		{"different backend and changed Flash Attention", -1, 0, false, true, true},
	};

	for (const auto &test_case : test_cases) {
		const bool actual = is_whisper_backend_changed(test_case.current_backend_device,
							       test_case.new_backend_device,
							       test_case.current_enable_flash_attn,
							       test_case.new_enable_flash_attn);
		if (actual != test_case.expected) {
			std::cerr << "Failed: " << test_case.name << " (expected "
				  << test_case.expected << ", got " << actual << ")\n";
			return 1;
		}
	}

	const external_model_change_test_case external_test_cases[] = {
		{"built-in model selected", "Whisper Tiny English (74Mb)", "b.bin", "a.bin", false},
		{"same external file", "!!!external!!!", "a.bin", "a.bin", false},
		{"different external file", "!!!external!!!", "b.bin", "a.bin", true},
		{"external file not chosen yet", "!!!external!!!", "", "a.bin", false},
	};

	for (const auto &test_case : external_test_cases) {
		const bool actual = is_external_whisper_model_changed(
			test_case.model_path, test_case.external_model_file_path,
			test_case.loaded_model_file_path);
		if (actual != test_case.expected) {
			std::cerr << "Failed: " << test_case.name << " (expected "
				  << test_case.expected << ", got " << actual << ")\n";
			return 1;
		}
	}

	return 0;
}
