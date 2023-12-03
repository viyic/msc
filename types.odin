package msc

import "core:os"
import "core:runtime"
import ma "vendor:miniaudio"

App :: struct {
	executable_path:              string,
	win_handle:                   platform_window_handle,
	font_name:                    string,
	font_height:                  int,
	mouse_down:                   b32,
	speed:                        f32,
	engine:                       ma.engine,
	sound:                        ma.sound,
	paused:                       b32,
	volume:                       f32,
	cursor:                       f32,
	length:                       f32,
	loop:                         Loop_State,
	delay_time:                   f32, // in seconds
	music_view:                   Music_View,
	left:                         Panel,
	right:                        Panel,
	bottom:                       Panel,
	top_left:                     Panel,
	current_path:                 string,
	file_list:                    []os.File_Info,
	music_infos:                  [dynamic]Music_Info,
	queue:                        [dynamic]int,
	playing_index:                int,
	last_click_cx, last_click_cy: int,
	last_click_time:              u64,
	last_cursor:                  Cursor,
}

Music_View :: enum {
	FILE,
	GRID,
}

Ui_Message :: enum {
	NONE,
	PAINT,
	MOUSE_MOVE,
	MOUSE_LEFT_PRESSED,
	MOUSE_LEFT_RELEASED,
	MOUSE_DOUBLE_CLICK,
	MOUSE_WHEEL,
}

Theme :: struct {
	background: [3]f32,
	text:       [3]f32,
	button:     struct {
		normal: [3]f32,
		hover:  [3]f32,
		click:  [3]f32,
	},
}

Cursor :: enum {
	NONE,
	ARROW,
	HAND,
}

USE_TRACKING_ALLOCATOR :: false

Timer :: enum {
	REFRESH = 1,
	DELAY,
	TRACK,
}

Loop_State :: enum {
	NONE,
	SINGLE,
	PLAYLIST,
	DELAY, // @analyze: only for SINGLE, should we add one for playlist?
}

Rect :: struct {
	x, y, w, h: int,
}

Panel :: struct {
	using rect: Rect,
	scroll:     f32,
}

Music_Info :: struct {
	artist:       string,
	title:        string,
	album:        string,
	release_time: string,
	full_path:    string,
}

Button_Config :: struct {
	text_align:   [2]u32,
	inset:        [2]int,
	double_click: bool,
}

button_config_default :: Button_Config {
	text_align   = TA_CENTER,
	inset        = 5,
	double_click = false,
}

Music_Info_Serialize :: enum {
	FULL_PATH,
	ARTIST,
	ALBUM,
	TITLE,
	RELEASE_TIME,
}

MUSIC_INFO_SERIALIZE :: [Music_Info_Serialize]string{} // .FULL_PATH = "full_path"


serialize :: proc(music_info: Music_Info) {
	for name, index in Music_Info_Serialize {

	}
}
