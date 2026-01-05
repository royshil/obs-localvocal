#include "transcription-filter-utils.h"

#include <obs-module.h>
#include <obs.h>
#include <obs-frontend-api.h>
#include <plugin-support.h>

static void ensure_localvocal_text_source_in_current_scene()
{
	const char *kSourceName = "LocalVocal Subtitles";
	obs_source_t *source = obs_get_source_by_name(kSourceName);
	const bool created = (source == nullptr);

	if (!source) {
		obs_log(LOG_INFO, "(LocalVocal) Creating text source '%s'", kSourceName);
#ifdef _WIN32
		source = obs_source_create("text_gdiplus_v3", kSourceName, nullptr, nullptr);
#else
		source = obs_source_create("text_ft2_source_v2", kSourceName, nullptr, nullptr);
#endif
	}

	if (!source) {
		obs_log(LOG_WARNING, "(LocalVocal) Failed to create/find text source '%s'",
			kSourceName);
		return;
	}

	if (created) {
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
	}

	obs_source_t *scene_as_source = obs_frontend_get_current_scene();
	if (!scene_as_source) {
		obs_log(LOG_WARNING, "(LocalVocal) Failed to get current scene");
		obs_source_release(source);
		return;
	}

	obs_scene_t *scene = obs_scene_from_source(scene_as_source);
	if (!scene) {
		obs_log(LOG_WARNING, "(LocalVocal) Failed to get scene from current scene source");
		obs_source_release(scene_as_source);
		obs_source_release(source);
		return;
	}

	obs_sceneitem_t *item = obs_scene_find_source(scene, kSourceName);
	if (!item) {
		uint32_t scene_width = obs_source_get_width(scene_as_source);
		uint32_t scene_height = obs_source_get_height(scene_as_source);

		obs_transform_info transform_info;
		transform_info.bounds.x = ((float)scene_width) - 40.0f;
		transform_info.bounds.y = 145.0;
		transform_info.pos.x = ((float)scene_width) / 2.0f;
		transform_info.pos.y =
			(((float)scene_height) - ((transform_info.bounds.y / 2.0f) + 20.0f));
		transform_info.bounds_type = obs_bounds_type::OBS_BOUNDS_SCALE_INNER;
		transform_info.bounds_alignment = OBS_ALIGN_CENTER;
		transform_info.alignment = OBS_ALIGN_CENTER;
		transform_info.scale.x = 1.0;
		transform_info.scale.y = 1.0;
		transform_info.rot = 0.0;
		transform_info.crop_to_bounds = false;

		item = obs_scene_add(scene, source);
		obs_sceneitem_set_info2(item, &transform_info);
	}

	obs_sceneitem_set_visible(item, true);

	obs_source_release(scene_as_source);
	obs_source_release(source);
}

void add_text_source_to_scenes_callback(obs_frontend_event event, void *)
{
	if (event == OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGED ||
	    event == OBS_FRONTEND_EVENT_SCENE_CHANGED ||
	    event == OBS_FRONTEND_EVENT_FINISHED_LOADING) {
		ensure_localvocal_text_source_in_current_scene();
	}
};

void create_obs_text_source_if_needed()
{
	// Ensure now, and keep ensuring when scene/collection changes.
	ensure_localvocal_text_source_in_current_scene();
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
