package msc

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import ma "vendor:miniaudio"

app_init :: proc(app: ^App, win_handle: platform_window_handle) -> bool {
	ok: bool
	app.executable_path, ok = platform_get_executable_path()
	if !ok {
		fmt.eprintln("get executable path failed")
		return false
	}

	app.win_handle = win_handle

	app.font_name = FONT_DEFAULT_NAME
	app.font_height = FONT_DEFAULT_HEIGHT

	change_current_path(app, START_PATH)
	update_file_list(app)
	change_volume(app, 0.5)
	app.paused = true
	app.speed = 1
	app.playing_index = -1
	app.delay_time = 5

	result := ma.engine_init(nil, &app.engine)
	if result != ma.result.SUCCESS {
		fmt.eprintln("engine init failed")
		return false
	}
	// @hack: too lazy to make config
	app.engine.pDevice.onData = ma_engine_data_callback

	theme_init_default(&theme)

	return true
}

config_init :: proc(app: ^App) {
	dir := filepath.dir(app.executable_path, context.temp_allocator)

	config, ok := os.read_entire_file(
		filepath.join([]string{dir, "msc.cfg"}, context.temp_allocator),
	)
	if !ok do return
	defer delete(config)

	lines := strings.split_lines(string(config[:]))
	defer delete(lines)
	for line, line_number in lines {
		words := strings.split_n(line, " ", 3)
		defer delete(words)
		if len(words) != 3 || words[0] == "#" || words[1] != "=" do continue

		switch words[0] {
		case "start_path":
			if os.is_dir(words[2]) {
				change_current_path(app, words[2])
			} else {
				fmt.eprintln(
					"[msc.cfg] invalid path for 'start_path' value in line ",
					line_number,
					": ",
					words[2],
					"\nexample: start_path = E:\\music",
				)
			}
		case "volume":
			value, ok := strconv.parse_int(words[2])
			if ok {
				change_volume(app, f32(value) / 100)
			} else {
				fmt.eprintln(
					"[msc.cfg] invalid 'volume' value in line ",
					line_number,
					": ",
					words[2],
					"\nexample: volume = 50",
				)
			}
		case "font_name":
			app.font_name = strings.clone(words[2])
		case "font_height":
			value, ok := strconv.parse_int(words[2])
			if ok {
				app.font_height = value
			} else {
				fmt.eprintln(
					"[msc.cfg] invalid 'font_height' value in line ",
					line_number,
					": ",
					words[2],
					"\nexample: font_height = 11",
				)
			}
		case "delay_time":
			value, ok := strconv.parse_f32(words[2])
			if ok {
				app.delay_time = value
			} else {
				fmt.eprintln(
					"[msc.cfg] invalid 'delay_time' value in line ",
					line_number,
					": ",
					words[2],
					"\nexample: delay_time = 5",
				)
			}
		case:
			fmt.eprintln("[msc.cfg] unknown config name '", words[0], "' in line ", line_number)
		}
	}
}

load_prev_session :: proc(app: ^App) {
	dir := filepath.dir(app.executable_path, context.temp_allocator)

	prev, ok := os.read_entire_file(
		filepath.join([]string{dir, "msc.prev"}, context.temp_allocator),
	)
	if !ok do return
	defer delete(prev)

	lines := strings.split_lines(string(prev[:]))
	defer delete(lines)
	for line, line_number in lines {
		// words := strings.split(line, " ")
		// defer delete(words)
		// if len(words) != 3 || words[0] == "#" || words[1] != "=" do continue
		if line == "" do continue

		music_info, ok := get_music_info_from_path(line)
		if ok {
			add_music_to_queue(app, music_info)
		}
	}
}

save_prev_session :: proc(app: ^App) {
	dir := filepath.dir(app.executable_path, context.temp_allocator)
	path := filepath.join([]string{dir, "msc.prev"}, context.temp_allocator)
	if len(app.queue) == 0 {
		os.remove(path)
		return
	}

	prev_file, err := os.open(path, os.O_CREATE)
	if err != os.ERROR_NONE {
		fmt.print(err)
		return
	}
	defer os.close(prev_file)

	for index in app.queue {
		music_info := app.music_infos[index]

		os.write_string(prev_file, music_info.full_path)
		os.write_string(prev_file, "\n")
	}
}

app_run :: proc(app: ^App, ctx: ^Platform_Ui_Context) {
	app.bottom.rect = {0, ctx.height - 55, ctx.width, 55}

	right_width := ctx.width / 3
	if right_width > 400 do right_width = 400
	app.top_left.rect = {0, 0, ctx.width - right_width, app.font_height + 20}
	app.left.rect =  {
		0,
		app.top_left.h,
		ctx.width - right_width,
		ctx.height - app.bottom.h - app.top_left.h,
	}
	app.right.rect = {app.left.w, 0, right_width, ctx.height - app.bottom.h}

	set_color(ctx, theme.background)
	draw_rect(ctx, 0, 0, ctx.width, ctx.height)

	ui_panel_left(app, ctx)
	ui_panel_right(app, ctx)
	ui_panel_bottom(app, ctx)

	set_color(ctx, theme.background)
	draw_rect(ctx, app.top_left.rect)
	ui_panel_top_left(app, ctx)

	if ctx.next_cursor == .NONE {
		ctx.next_cursor = .ARROW
	}

	if ctx.msg != .PAINT && ctx.redraw {
		platform_redraw(app)
	}
}

update_file_list :: proc(app: ^App) {
	handle, err_open := os.open(app.current_path)
	if err_open != os.ERROR_NONE do return
	defer os.close(handle)

	file_list, err_read_dir := os.read_dir(handle, 0)
	if err_read_dir != os.ERROR_NONE do return

	app.file_list = file_list
}

change_current_path :: proc(app: ^App, new_path: string) {
	new_path_ := strings.clone(new_path)

	if len(app.file_list) > 0 {
		os.file_info_slice_delete(app.file_list)
	}
	app.file_list = []os.File_Info{}

	if app.current_path != "" {
		delete(app.current_path)
	}
	app.current_path = new_path_
	update_file_list(app)
}

theme_init_default :: proc(theme: ^Theme) {
	theme.background = {0.1, 0.1, 0.1}
	theme.text = {1, 1, 1}
	theme.button.normal = {0.15, 0.15, 0.15}
	theme.button.hover = {0.4, 0.4, 0.4}
	theme.button.click = {0.35, 0.35, 0.35}
}

ui_panel_top_left :: proc(app: ^App, ctx: ^Platform_Ui_Context) {
	margin := 5
	padding := 5
	// set_color(ctx, 0.15)
	// draw_rect(ctx, app.top_left.x + margin, app.top_left.y + margin, app.top_left.w - 2 * margin, app.top_left.h - margin)

	y := app.top_left.y + margin
	at_x := app.top_left.x + margin

	if app.music_view == .GRID {
		name := "File"
		rect := platform_get_text_size(ctx, name)
		if button(ctx, at_x, y, rect.w + padding, rect.h + padding, name) {
			app.music_view = .FILE
			ctx.redraw = true
		}
		at_x += rect.w + padding + margin
	} else if app.music_view == .FILE {
		name := "Grid"
		rect := platform_get_text_size(ctx, name)
		if button(ctx, at_x, y, rect.w + padding, rect.h + padding, name) {
			app.music_view = .GRID
			ctx.redraw = true
		}
		at_x += rect.w + padding + margin
	}
}

ui_panel_left :: proc(app: ^App, ctx: ^Platform_Ui_Context) {
	// ---------- QUEUE
	if app.music_view == .FILE {
		ui_music_list(app, ctx)
	} else {
		// ui_music_grid(app, ctx)
	}
}

ui_music_list :: proc(app: ^App, ctx: ^Platform_Ui_Context) {
	width := ctx.width - ctx.width / 3
	height := ctx.height - 55
	x := 5
	margin := 5 // inset
	padding := 5 // for items
	item_height := app.font_height + padding

	clip := app.left
	clip.x += margin
	clip.y += margin
	clip.w -= margin * 2
	clip.h -= margin * 2

	at_y := app.left.y + margin

	filter_proc :: proc(item: os.File_Info) -> bool {
		ext := filepath.ext(item.name)

		return item.is_dir || is_supported_audio_file(ext)
	}
	file_list_ := slice.filter(app.file_list, filter_proc)
	file_list := slice.concatenate(
	[][]os.File_Info{[]os.File_Info{os.File_Info{name = "..", is_dir = true}}, file_list_}, // @warning: dangerous!
	)
	delete(file_list_)
	defer delete(file_list)

	sort_proc :: proc(a: os.File_Info, b: os.File_Info) -> bool {
		return a.is_dir && !b.is_dir
	}
	slice.stable_sort_by(file_list, sort_proc)

	list_height := item_height * (len(file_list) + 1)
	if ctx.scroll != 0 {
		app.left.scroll = clamp(app.left.scroll - ctx.scroll, 0, f32(list_height - height))
		ctx.redraw = true
	}
	if list_height <= height do app.left.scroll = 0
	// @todo: figure out how resizing with scrolled panel work, anchor on top left?
	list_scroll := int(app.left.scroll)

	new_path := app.current_path

	button_config := button_config_default
	button_config.text_align = {TA_LEFT, TA_CENTER}
	button_config.double_click = true

	set_text_align(ctx, TA_CENTER)
	for cursor in file_list {
		if at_y + item_height >= list_scroll && at_y < list_scroll + height {
			name: string
			if cursor.is_dir && cursor.name != ".." {
				name = strings.concatenate([]string{": ", cursor.name}, context.temp_allocator)
			} else {
				name = cursor.name
			}

			rect := platform_get_text_size(ctx, name)
			if button(
				   ctx,
				   x,
				   at_y - list_scroll,
				   rect.w + padding,
				   rect.h + padding,
				   name,
				   clip,
				   button_config,
			   ) {
				if !cursor.is_dir {
					music_info, ok := get_music_info_from_path(cursor.fullpath)

					if ok {
						add_music_to_queue(app, music_info)
						if platform_get_shift_key() do jump_queue(app, len(app.queue) - 1)
						fmt.println(music_info)
					}
				} else {
					if cursor.name == ".." {
						clean := filepath.clean(app.current_path, context.temp_allocator)
						up, _ := filepath.split(clean)
						new_path = up
					} else {
						new_path = cursor.fullpath
					}
				}

				ctx.redraw = true
			}
		}

		at_y += item_height
	}

	if new_path != app.current_path {
		fmt.println(new_path)
		change_current_path(app, new_path)
		app.left.scroll = 0
	}

	set_color(ctx, theme.background)
	draw_rect(ctx, Rect{app.left.x, app.left.y, app.left.w, margin})
	draw_rect(ctx, Rect{app.left.x, app.left.y, margin, app.left.h})
	draw_rect(
		ctx,
		Rect{x1(app.left) - margin, app.left.y, ctx.width - (x1(app.left) - margin), app.left.h},
	)
	draw_rect(
		ctx,
		Rect{app.left.x, y1(app.left) - margin, app.left.w, ctx.height - (y1(app.left) - margin)},
	)
}

ui_panel_bottom :: proc(app: ^App, ctx: ^Platform_Ui_Context) {
	ui_focus := app.ui_focus // @todo: find a better way to do this
	playing := app.paused ? "|>" : "||"

	set_color(ctx, theme.background)
	draw_rect(ctx, app.bottom.x, app.bottom.y, app.bottom.w, app.bottom.h)

	button_play: Rect
	button_play.w = 30
	button_play.h = 30
	button_play.x = (ctx.width - button_play.w) / 2
	button_play.y = ctx.height - button_play.h - 5

	set_text_color(ctx, {1, 1, 1})

	// ---------- PLAY INFORMATION
	play_bar := Rect{5, button_play.y - 15, ctx.width - 10, 10}
	set_color(ctx, {0.2, 0.2, 0.2})
	draw_rect(ctx, play_bar)

	if sound_exists(app) {
		ma.sound_get_cursor_in_seconds(&app.sound, &app.cursor)
		ma.sound_get_length_in_seconds(&app.sound, &app.length)
	}

	right_of_play_x := 5
	if sound_exists(app) {
		// ---------- PLAY BAR
		set_color(ctx, theme.button.hover)
		play_bar_hover := point_in_rect(ctx.cx, ctx.cy, play_bar)

		play_bar_drag := false
		if ctx.msg == .MOUSE_LEFT_PRESSED && play_bar_hover {
			app.ui_focus = "play"
			ui_focus = "play"
			play_bar_drag = true
		}
		if app.mouse_down && ui_focus == "play" {
			play_bar_drag = true
		}

		if ctx.msg == .MOUSE_LEFT_RELEASED && app.mouse_down && ui_focus == "play" {
			app.ui_focus = ""
			play_bar_drag = true
			pcm_length: u64
			sample_rate: u32
			result := ma.data_source_get_length_in_pcm_frames(app.sound.pDataSource, &pcm_length)
			result = ma.data_source_get_data_format(
				app.sound.pDataSource,
				nil,
				nil,
				&sample_rate,
				nil,
				0,
			)
			if result == .SUCCESS {
				normalized := clamp(f32(ctx.cx - play_bar.x) / f32(play_bar.w), 0, 1)
				new_length := u64(f32(pcm_length) * normalized)
				// @analyze: less popping?
				new_length = new_length - (new_length % u64(sample_rate))
				ma.sound_seek_to_pcm_frame(&app.sound, new_length)
				ctx.redraw = true
			}
		}

		draw_rect(
			ctx,
			{play_bar.x, play_bar.y, int(app.cursor / app.length * f32(play_bar.w)), play_bar.h},
		)

		set_color(ctx, {1, 1, 1})
		if play_bar_drag {
			x :=
				int(clamp(f32(ctx.cx - play_bar.x) / f32(play_bar.w), 0, 1) * f32(play_bar.w)) +
				play_bar.x
			draw_rect(ctx, {x - 3, play_bar.y, 6, play_bar.h})

		}
	}

	// ---------- VOLUME BAR
	vol_bar := Rect {
		button_play.x + button_play.w + right_of_play_x,
		button_play.y + button_play.h / 2 - 5,
		int(app.volume * 80),
		10,
	}
	set_color(ctx, 0.2)
	draw_rect(ctx, {vol_bar.x, vol_bar.y, 80, vol_bar.h})
	set_color(ctx, theme.button.normal)
	draw_rect(ctx, vol_bar)
	vol_bar.w = 80

	change := false
	vol_bar_hover := point_in_rect(ctx.cx, ctx.cy, vol_bar)
	if ctx.msg == .MOUSE_LEFT_PRESSED && vol_bar_hover {
		app.ui_focus = "volume"
		ui_focus = "volume"
		change = true
	}
	if ui_focus == "volume" && app.mouse_down {
		ctx.redraw = true
		change = true
	}
	if ctx.msg == .MOUSE_LEFT_RELEASED && app.mouse_down && ui_focus == "volume" {
		app.ui_focus = "" // @warning: might cause bug
		ctx.redraw = true
		change = true
	}

	if change {
		new_vol := clamp(f32(ctx.cx - vol_bar.x) / f32(vol_bar.w), 0, 1)
		change_volume(app, new_vol)
	}
	right_of_play_x += vol_bar.w + 5

	if sound_exists(app) {
		set_text_align(ctx, TA_LEFT)
		cursor_min := int(app.cursor / 60)
		cursor_sec := int(app.cursor) % 60
		length_min := int(app.length / 60)
		length_sec := int(app.length) % 60
		str := fmt.tprintf("%d:%02d/%d:%02d", cursor_min, cursor_sec, length_min, length_sec)
		rect := platform_get_text_size(ctx, str)
		label(
			ctx,
			button_play.x + button_play.w + right_of_play_x,
			button_play.y + (button_play.h - app.font_height) / 2,
			str,
		)
		right_of_play_x += rect.w + 5
	}

	// ---------- LOOP
	loop_text := "loop: x"
	if app.loop == .SINGLE do loop_text = "loop: s"
	else if app.loop == .PLAYLIST do loop_text = "loop: p"
	else if app.loop == .DELAY do loop_text = "loop: d"

	padding := 10
	loop_size := platform_get_text_size(ctx, loop_text)
	loop_size.w += padding
	loop_size.h += padding

	if button(
		   ctx,
		   int(button_play.x - loop_size.w - 5),
		   int(button_play.y + (button_play.h - app.font_height) / 2 - padding / 2),
		   int(loop_size.w),
		   int(loop_size.h),
		   loop_text,
	   ) {
		app.loop = Loop_State((int(app.loop) + 1) % len(Loop_State))
	}

	// ---------- SPEED
	set_text_align(ctx, TA_RIGHT)
	set_text_color(ctx, 1)
	str := fmt.tprintf(int(app.speed * 100) % 10 == 0 ? "%.1fx" : "%.2fx", app.speed)
	label(
		ctx,
		button_play.x - loop_size.w - 10,
		button_play.y + (button_play.h - app.font_height) / 2,
		str,
	)

	// ---------- PLAY BUTTON
	if button(ctx, button_play.x, button_play.y, button_play.w, button_play.h, playing) &&
	   ui_focus == "" {
		toggle_pause_music(app)
		ctx.redraw = true
	}
}

ui_panel_right :: proc(app: ^App, ctx: ^Platform_Ui_Context) {
	width := app.right.w
	x := app.right.x
	margin := 5
	padding := 5
	item_height := app.font_height + padding

	if ctx.scroll != 0 {

	}

	set_color(ctx, 0.2)
	draw_rect(ctx, x, margin, width - margin, app.right.h - margin)

	button_add := Rect{}
	button_add.w = 20
	button_add.h = 20
	button_add.x = x + (width - button_add.w) / 2
	button_add.y = item_height * (len(app.music_infos) + 1) + item_height / 2

	at_y := margin

	title_height := item_height + 2 * padding

	set_color(ctx, 0.15)
	draw_rect(ctx, x, at_y, width - margin, title_height)

	set_text_align(ctx, TA_CENTER)
	set_text_color(ctx, 1)
	label(ctx, x + width / 2, at_y + (title_height - item_height) / 2, "Playlist")

	at_y += title_height + margin

	// ---------- QUEUE
	button_config := button_config_default
	button_config.text_align = {TA_LEFT, TA_CENTER}
	button_config.double_click = true

	remove_index := -1
	list_width := width - 3 * margin
	clip := Rect{x + margin, at_y, list_width, app.right.h - at_y}
	for music_info_index, queue_index in app.queue {
		music_info := app.music_infos[music_info_index]

		str := fmt.tprintf(
			"%v%v%v%v",
			app.playing_index > -1 && app.queue[app.playing_index] == music_info_index \
			? "> " \
			: "  ",
			len(music_info.title) > 0 ? music_info.title : filepath.stem(music_info.full_path),
			len(music_info.artist) > 0 ? " : " : "",
			music_info.artist,
		)

		if button(ctx, x + margin, at_y, list_width, item_height, str, clip, button_config) {
			jump_queue(app, queue_index)
		}

		if ctx.msg == .MOUSE_MIDDLE_RELEASED &&
		   point_in_rect(ctx.cx, ctx.cy, Rect{x + margin, at_y, list_width, item_height}) {
			remove_index = queue_index
		}

		// i32 length_min = cast(i32) (cursor.length / 60)
		// i32 length_sec = cast(i32) cursor.length % 60
		// String_Null length = push_printf_null(&app.temp_arena, L"%d.%.2d", length_min, length_sec)
		// set_text_align(ctx, TA_RIGHT)
		// label(ctx, x + width - 15, at_y, length)

		// set_text_color(ctx, 0)

		at_y += item_height
	}

	if remove_index > -1 {
		remove_from_queue(app, remove_index)
	}

	// ---------- ADD TO QUEUE
	/*
    set_text_align(ctx, TEXT_ALIGN_CENTER)
    if button(ctx, button_add.x, button_add.y, button_add.w, button_add.h, L"+")
    {
        wchar filename[MAX_PATH]
        if (platform_open_music_dialog(filename, MAX_PATH))
        {
            add_music_to_queue(app, filename)
            request_redraw(ctx, { app.right.x, app.right.y, app.right.width, app.right.height })
        }
    }
    */

	set_color(ctx, 0.2)
	draw_rect(
		ctx,
		x + width - 2 * margin,
		margin + title_height,
		margin,
		app.right.h - margin - title_height,
	)
	set_color(ctx, theme.background)
	draw_rect(ctx, x + width - margin, app.right.y, margin, app.right.h)
}

change_volume :: proc(app: ^App, value: f32) {
	app.volume = max(min(value, 1), 0)
	ma.engine_set_volume(&app.engine, app.volume)
}
