#include "ssl-utils.h"
#include <obs-module.h>
#include <plugin-support.h>
#include <string>
#include <util/bmem.h>

std::string PEMrootCertsPath()
{
	char *root_cert_file_path = obs_module_file("roots.pem");
	if (root_cert_file_path == nullptr) {
		return "";
	}

	std::string path_str(root_cert_file_path);
	bfree(root_cert_file_path);
	return path_str;
}
