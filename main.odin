package msc

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:runtime"
import "core:strconv"
import "core:strings"
import win32 "core:sys/windows"
import ma "vendor:miniaudio"

@(private = "file")
app: App
theme: Theme

START_PATH :: `C:\`
FONT_DEFAULT_NAME :: "Segoe UI"
FONT_DEFAULT_HEIGHT :: 20

font_default: platform_font_handle

cursor_arrow: platform_cursor_handle
cursor_hand: platform_cursor_handle

speed_steps := [?]f32 {
	0.5,
	0.6,
	0.7,
	0.75,
	0.8,
	0.9,
	1,
	1.1,
	1.2,
	1.25,
	1.3,
	1.4,
	1.5,
	1.6,
	1.7,
	1.75,
	1.8,
	1.9,
	2,
}

when USE_TRACKING_ALLOCATOR 
{
	track: mem.Tracking_Allocator
	track_allocator: mem.Allocator
}

main :: proc() {
	using win32

	when USE_TRACKING_ALLOCATOR 
	{
		mem.tracking_allocator_init(&track, context.allocator)
		track_allocator = mem.tracking_allocator(&track)
		context.allocator = track_allocator
	}

	win_handle := platform_window_create()
	if win_handle == nil {
		fmt.eprintln("window creation failed")
		return
	}

	if !app_init(&app, win_handle) do return

	config_init(&app)
	font_init(&app)

	ShowWindow(win_handle, SW_SHOWNORMAL)
	UpdateWindow(win_handle)

	when USE_TRACKING_ALLOCATOR 
	{
		SetTimer(win_handle, TRACK_TIMER, 1000, nil)
	}

	when false 
	{
		read_music_dir(&app)
		data_path := strings.concatenate(
			[]string{filepath.dir(app.executable_path, context.temp_allocator), "\\msc.data"},
			context.temp_allocator,
		)
		data_file, ok := os.read_entire_file_from_filename(data_path)
		if !ok do return
		defer delete(data_file)
		lines := strings.split_lines(string(data_file))
		defer delete(lines)
		for line in lines {
			TOTAL_INFO :: 5
			word := strings.split_n(line, " | ", TOTAL_INFO)
			defer delete(word)
			if len(word) < TOTAL_INFO do continue

			fmt.println(word[1], word[3], word[0])
		}

		return
	} else {
		msg: MSG
		for GetMessageW(&msg, nil, 0, 0) {
			TranslateMessage(&msg)
			DispatchMessageW(&msg)
		}
	}
}

win_proc :: proc "stdcall" (
	win_handle: win32.HWND,
	msg: win32.UINT,
	wparam: win32.WPARAM,
	lparam: win32.LPARAM,
) -> win32.LRESULT {
	using win32

	context = runtime.default_context()
	when USE_TRACKING_ALLOCATOR 
	{
		context.allocator = track_allocator
	}
	free_all(context.temp_allocator)

	result: LRESULT = 0

	switch msg 
	{
	case WM_CLOSE:
		DestroyWindow(win_handle)

	case WM_DESTROY:
		PostQuitMessage(0)

	case WM_SETCURSOR:
		cursor := Cursor(wparam)

		if cursor == .ARROW {
			SetCursor(cursor_arrow)
			result = 1 // TRUE
		} else if cursor == .HAND {
			SetCursor(cursor_hand)
			result = 1 // TRUE
		} else {
			result = DefWindowProcW(win_handle, msg, wparam, lparam)
		}

	case WM_TIMER:
		timer := Timer(wparam)
		if timer == .REFRESH {
			if (ma.sound_is_playing(&app.sound)) {
				InvalidateRect(win_handle, nil, TRUE)
				// SetTimer(win_handle, REFRESH_TIMER, 200, nil)
			} else {
				KillTimer(app.win_handle, uintptr(timer))
			}
		} else if timer == .DELAY {
			if sound_exists(&app) {
				// assert(false)
				// ma.sound_start(&app.sound)
			} else {
				if app.loop == .DELAY && !app.paused {
					jump_queue(&app, app.playing_index)
				}
			}
			KillTimer(app.win_handle, uintptr(timer))
			fmt.println("DELAY_TIMER end")
		} else if timer == .TRACK {
			when USE_TRACKING_ALLOCATOR 
			{
				for _, leak in track.allocation_map {
					fmt.printf("%v leaked %v bytes\n", leak.location, leak.size)
				}
			}
		}

	case WM_CHAR:
		switch wparam {
		case 'o':
			path, ok := platform_open_file_dialog(
				"Music Files (.mp3, .flac, .wav, .ogg)\u0000*.mp3;*.flac;*.wav;*.ogg\u0000",
			)
			if ok {
				// reset_queue(&app)
				music_info, ok := get_music_info_from_path(path)
				if ok do add_music_to_queue(&app, music_info)
				delete(path)
				fmt.println("playing \"", path, "\"")
			}
		case 'p':
		// toggle_pause_music(&app)
		case ',':
			jump_queue(&app, app.playing_index - 1)
		case '.':
			jump_queue(&app, app.playing_index + 1)
		case 'q':
			change_speed(&app, -1)
		case 'w':
			change_speed(&app, 1)
		}

		InvalidateRect(win_handle, nil, TRUE)

	case WM_KEYDOWN, WM_SYSKEYDOWN:
		switch wparam 
		{
		case VK_ESCAPE:
			PostQuitMessage(0)
		case VK_SPACE:
			toggle_pause_music(&app)
			InvalidateRect(win_handle, nil, TRUE)
		case VK_BACK:
			index := 0
			// prev: ^Music_File = nil
			/*
                    for cursor: ^Music_File = app.queue_first
                        cursor != nil
                        cursor = cursor.next
                    {
                        if (index == app.playing_index)
                        {
                            if (prev)
                            {
                                prev->next = cursor->next
                            }
                            else
                            {
                                app.queue_first = cursor->next
                            }
                            cursor->active = false
                            cursor->next = nil
                            app.paused = true
                            if app.queue_first == nil
                            {
                                ma.sound_uninit(&app.sound)
                            }
                            else
                            {
                                jump_queue(&app, MIN(cast(int) queue_count(&app) - 1, index))
                                ma.sound_stop(&app.sound)
                            }
                            break
                        }
                        index += 1
                        prev = cursor
                    }
                    */
			InvalidateRect(win_handle, nil, TRUE)
		}

	case WM_MOUSEMOVE:
		ctx := platform_ui_context_create(&app)

		// @todo @analyze: does this affect performance a lot?
		// is there a better way to do this?
		ctx.msg = .MOUSE_MOVE
		app_run(&app, &ctx)

		if app.last_cursor != ctx.next_cursor {
			app.last_cursor = ctx.next_cursor
			PostMessageW(win_handle, WM_SETCURSOR, WPARAM(ctx.next_cursor), 0)
		}

		track: TRACKMOUSEEVENT = {size_of(TRACKMOUSEEVENT), TME_LEAVE, win_handle, HOVER_DEFAULT}
		TrackMouseEvent(&track)

	case WM_MOUSELEAVE:
		app.last_cursor = .NONE
		InvalidateRect(win_handle, nil, TRUE)

	case WM_LBUTTONDOWN:
		if wparam & MK_LBUTTON != 0 {
			prev_mouse_down := app.mouse_down
			app.mouse_down = true

			if !prev_mouse_down {
				ctx := platform_ui_context_create(&app)
				time: FILETIME
				GetSystemTimePreciseAsFileTime(&time)
				time64 := u64(time.dwLowDateTime) + u64(time.dwHighDateTime << 32)

				if time64 - app.last_click_time < 3000000 {
					ctx.msg = .MOUSE_DOUBLE_CLICK
					app_run(&app, &ctx)
				}

				app.last_click_cx = ctx.cx
				app.last_click_cy = ctx.cy
				app.last_click_time = time64
			}

			InvalidateRect(win_handle, nil, TRUE)
		}

	case WM_LBUTTONUP:
		if app.mouse_down {
			ctx := platform_ui_context_create(&app)
			ctx.msg = .MOUSE_LEFT_RELEASED
			app_run(&app, &ctx)
		}

		app.mouse_down = false
		InvalidateRect(win_handle, nil, TRUE)

	case WM_MOUSEWHEEL:
		ctx := platform_ui_context_create(&app)
		ctx.scroll = f32(GET_WHEEL_DELTA_WPARAM(wparam)) / WHEEL_DELTA * 4
		ctx.msg = .MOUSE_WHEEL
		app_run(&app, &ctx)

	case WM_PAINT:
		ps: PAINTSTRUCT
		paint_hdc: HDC = BeginPaint(win_handle, &ps)
		hdc: HDC
		buffered: HPAINTBUFFER = BeginBufferedPaint(
			paint_hdc,
			&ps.rcPaint,
			.COMPATIBLEBITMAP,
			nil,
			&hdc,
		)
		if buffered != nil {
			font_old := HFONT(SelectObject(hdc, HGDIOBJ(font_default)))
			SetBkMode(hdc, TRANSPARENT)
			prev_brush: HBRUSH = cast(HBRUSH)SelectObject(hdc, GetStockObject(DC_BRUSH))
			SelectObject(hdc, GetStockObject(NULL_PEN))

			ctx := platform_ui_context_create(&app, hdc)
			ctx.msg = .PAINT
			app_run(&app, &ctx)

			SelectObject(hdc, HGDIOBJ(font_old))

			EndBufferedPaint(buffered, TRUE)
		}
		EndPaint(win_handle, &ps)

	case:
		result = DefWindowProcW(win_handle, msg, wparam, lparam)
	}

	return result
}

font_init :: proc(app: ^App) {
	using win32

	font_name := win32.utf8_to_wstring(app.font_name, context.allocator)
	defer free(font_name)
	font_default = CreateFontW(
		i32(app.font_height),
		0,
		0,
		0,
		FW_DONTCARE,
		0,
		0,
		0,
		ANSI_CHARSET,
		OUT_DEFAULT_PRECIS,
		CLIP_DEFAULT_PRECIS,
		DEFAULT_QUALITY,
		DEFAULT_PITCH | FF_DONTCARE,
		font_name,
	)
}

ma_engine_data_callback :: proc "cdecl" (
	pDevice: ^ma.device,
	pFramesOut, pFramesIn: rawptr,
	frameCount: u32,
) {
	context = runtime.default_context()
	when USE_TRACKING_ALLOCATOR 
	{
		context.allocator = track_allocator
	}
	pEngine := (^ma.engine)(pDevice.pUserData)

	// pFramesIn

	ma.engine_read_pcm_frames(pEngine, pFramesOut, u64(frameCount), nil)

	if ma.sound_at_end(&app.sound) {
		handle_end_of_music(&app)
		platform_redraw(&app)
	}
}

/*
ideas:
- app_run() once in non-WM_PAINT event and queue required draws, then draw during WM_PAINT
*/
