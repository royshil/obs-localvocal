#include "transcription-filter-utils.h"

#include <obs-module.h>
#include <obs.h>
#include <obs-frontend-api.h>
#include <plugin-support.h>

void add_text_source_to_scenes_callback(obs_frontend_event event, __attribute__((unused)) void* private_data) {
	if (event == OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGED) {
		// check if a source called "LocalVocal Subtitles" exists
		obs_source_t *source = obs_get_source_by_name("LocalVocal Subtitles");
		if (source) {
			obs_log(LOG_INFO, "(add_text_source_callback) Text source exists");
			// source already exists, release it
			obs_source_release(source);
			return;
		}

		obs_log(LOG_INFO, "(add_text_source_callback) Creating text source 'LocalVocal Subtitles'");
		// create a new OBS text source called "LocalVocal Subtitles"
#ifdef _WIN32
		source = obs_source_create("text_gdiplus_v3", "LocalVocal Subtitles", nullptr, nullptr);
#else
		source = obs_source_create("text_ft2_source_v2", "LocalVocal Subtitles", nullptr, nullptr);
#endif
		if (source) {
			// set source settings
			obs_data_t *source_settings = obs_source_get_settings(source);
			obs_data_set_bool(source_settings, "word_wrap", true);
			obs_data_set_bool(source_settings, "extents", true);
			obs_data_set_bool(source_settings, "outline", true);
			obs_data_set_int(source_settings, "outline_color", 4278190080);
			obs_data_set_int(source_settings, "outline_size", 7);
			obs_data_set_int(source_settings, "extents_cx", 1500);
			obs_data_set_int(source_settings, "extents_cy", 230);
			obs_data_t *font_data = obs_data_create();
			obs_data_set_string(font_data, "face", "Arial");
			obs_data_set_string(font_data, "style", "Regular");
			obs_data_set_int(font_data, "size", 72);
			obs_data_set_int(font_data, "flags", 0);
			obs_data_set_obj(source_settings, "font", font_data);
			obs_data_release(font_data);
			obs_source_update(source, source_settings);
			obs_data_release(source_settings);

			obs_source_t *scene_as_source = obs_frontend_get_current_scene();
			if (!scene_as_source) {
				obs_log(LOG_WARNING, "Failed to get current scene");
			}
			obs_scene_t *scene = obs_scene_from_source(scene_as_source);

			uint32_t scene_width = obs_source_get_width(scene_as_source);
			uint32_t scene_height = obs_source_get_height(scene_as_source);

			// set transform settings
			obs_transform_info transform_info;
			transform_info.pos.x = ((float) scene_width) / 2.0f;
			transform_info.pos.y = (((float) scene_height) - ((transform_info.bounds.y / 2.0f) + 20.0f));
			transform_info.bounds.x = ((float) scene_width) - 40.0f;
			transform_info.bounds.y = 145.0;
			transform_info.bounds_type = obs_bounds_type::OBS_BOUNDS_SCALE_INNER;
			transform_info.bounds_alignment = OBS_ALIGN_CENTER;
			transform_info.alignment = OBS_ALIGN_CENTER;
			transform_info.scale.x = 1.0;
			transform_info.scale.y = 1.0;
			transform_info.rot = 0.0;
			transform_info.crop_to_bounds = false;

			// add source to the scene
			obs_sceneitem_t *source_sceneitem = obs_scene_add(scene, source);

			// apply settings to source for the scene and set visible
			obs_sceneitem_set_info2(source_sceneitem, &transform_info);
			obs_sceneitem_set_visible(source_sceneitem, true);

			obs_source_release(scene_as_source);
		}
		else {
			obs_log(LOG_DEBUG, "Failed to create text source");
		}

		obs_source_release(source);
		obs_frontend_remove_event_callback(add_text_source_to_scenes_callback, nullptr);
	}
};

void create_obs_text_source_if_needed()
{
	// Add event callback to add source to scenes once they've been loaded
	obs_frontend_add_event_callback(add_text_source_to_scenes_callback, nullptr);
}

bool add_sources_to_list(void *list_property, obs_source_t *source)
{
	const char *source_id = obs_source_get_id(source);
	if (strcmp(source_id, "text_ft2_source_v2") != 0 &&
	    strcmp(source_id, "text_gdiplus_v3") != 0 &&
	    strcmp(source_id, "text_gdiplus_v2") != 0) {
		return true;
	}

	obs_property_t *sources = (obs_property_t *)list_property;
	const char *name = obs_source_get_name(source);
	obs_property_list_add_string(sources, name, name);
	return true;
}
