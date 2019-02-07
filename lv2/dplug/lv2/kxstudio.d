/*
  LV2 External UI extension
  This work is in public domain.

  This file is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  If you have questions, contact Filipe Coelho (aka falkTX) <falktx@falktx.com>
  or ask in #lad channel, FreeNode IRC network.
*/

/**
   @file lv2_external_ui.h
   C header for the LV2 External UI extension <http://kxstudio.sf.net/ns/lv2ext/external-ui>.
*/
module dplug.lv2.kxstudio;

import dplug.lv2.ui;

enum LV2_EXTERNAL_UI_URI     = "http://kxstudio.sf.net/ns/lv2ext/external-ui";
enum LV2_EXTERNAL_UI_PREFIX  = LV2_EXTERNAL_UI_URI ~ "#";

enum LV2_EXTERNAL_UI__Host   = LV2_EXTERNAL_UI_PREFIX ~ "Host";
enum LV2_EXTERNAL_UI__Widget = LV2_EXTERNAL_UI_PREFIX ~ "Widget";

/** This extension used to be defined by a lv2plug.in URI */
enum LV2_EXTERNAL_UI_DEPRECATED_URI = "http://lv2plug.in/ns/extensions/ui#external";

extern (C) {

	/**
	* When LV2_EXTERNAL_UI__Widget UI is instantiated, the returned
	* LV2UI_Widget handle must be cast to pointer to LV2_External_UI_Widget.
	* UI is created in invisible state.
	*/
	struct _LV2_External_UI_Widget {
	/**
	* Host calls this function regulary. UI library implementing the
	* callback may do IPC or redraw the UI.
	*
	* @param _this_ the UI context
	*/
	void function(_LV2_External_UI_Widget * _this_) run;

	/**
	* Host calls this function to make the plugin UI visible.
	*
	* @param _this_ the UI context
	*/
	void function(_LV2_External_UI_Widget * _this_) show;

	/**
	* Host calls this function to make the plugin UI invisible again.
	*
	* @param _this_ the UI context
	*/
	void function(_LV2_External_UI_Widget * _this_) hide;

	}
	alias LV2_External_UI_Widget = _LV2_External_UI_Widget;

	// enum LV2_EXTERNAL_UI_RUN(ptr)  (ptr)->run(ptr)
	// enum LV2_EXTERNAL_UI_SHOW(ptr) (ptr)->show(ptr)
	// enum LV2_EXTERNAL_UI_HIDE(ptr) (ptr)->hide(ptr)

	/**
	* On UI instantiation, host must supply LV2_EXTERNAL_UI__Host feature.
	* LV2_Feature::data must be pointer to LV2_External_UI_Host.
	*/
	struct _LV2_External_UI_Host {
	/**
	* Callback that plugin UI will call when UI (GUI window) is closed by user.
	* This callback will be called during execution of LV2_External_UI_Widget::run()
	* (i.e. not from background thread).
	*
	* After this callback is called, UI is defunct. Host must call LV2UI_Descriptor::cleanup().
	* If host wants to make the UI visible again, the UI must be reinstantiated.
	*
	* @note When using the depreated URI LV2_EXTERNAL_UI_DEPRECATED_URI,
	*       some hosts will not call LV2UI_Descriptor::cleanup() as they should,
	*       and may call show() again without re-initialization.
	*
	* @param controller Host context associated with plugin UI, as
	*                   supplied to LV2UI_Descriptor::instantiate().
	*/
	void function(LV2UI_Controller controller) ui_closed;

	/**
	* Optional (may be NULL) "user friendly" identifier which the UI
	* may display to allow a user to easily associate this particular
	* UI instance with the correct plugin instance as it is represented
	* by the host (e.g. "track 1" or "channel 4").
	*
	* If supplied by host, the string will be referenced only during
	* LV2UI_Descriptor::instantiate()
	*/
	const char * plugin_human_id;

	}
	alias LV2_External_UI_Host = _LV2_External_UI_Host;

}