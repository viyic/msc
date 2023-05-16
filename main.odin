package msc

import "core:fmt"
import "core:runtime"
import "core:strings"
import "core:mem"
import win32 "core:sys/windows"
import ma "vendor:miniaudio"

app: App
theme: Theme

font_default: win32.HFONT
FONT_HEIGHT :: 11

cursor_arrow: win32.HCURSOR
cursor_hand: win32.HCURSOR

speed_steps := [?]f32{ 0.5, 0.6, 0.7, 0.75, 0.8, 0.9, 1, 1.1, 1.2, 1.25, 1.3, 1.4, 1.5, 1.6, 1.7, 1.75, 1.8, 1.9, 2 }
// speed_steps := [?]f32{ 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2 }

when USE_TRACKING_ALLOCATOR
{
    track: mem.Tracking_Allocator
    track_allocator: mem.Allocator
}

main :: proc()
{
    using win32

    when USE_TRACKING_ALLOCATOR
    {
        mem.tracking_allocator_init(&track, context.allocator)
        track_allocator = mem.tracking_allocator(&track)
        context.allocator = track_allocator
    }

    instance := HINSTANCE(GetModuleHandleW(nil))
    class_name := win32.L("msc") // issue #2007

    win_class: WNDCLASSEXW
    win_class.cbSize = size_of(win_class)
    win_class.lpfnWndProc = win_proc
    win_class.hInstance = instance
    win_class.lpszClassName = class_name
    win_class.style = CS_HREDRAW | CS_VREDRAW
    if !b32(RegisterClassExW(&win_class))
    {
        return
    }

    win_handle := CreateWindowExW(
        0,
        class_name,
        win32.L("msc"),
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT,
        750, 550,
        nil,
        nil,
        instance,
        nil,
    )

    DWMWA_USE_IMMERSIVE_DARK_MODE :: 20
    dark_mode := true
    DwmSetWindowAttribute(win_handle, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark_mode, size_of(dark_mode))

    if win_handle == nil
    {
        return
    }

    font_init()

    if result := app_init(&app, win_handle); result != ma.result.SUCCESS
    {
        return // result
    }

    ShowWindow(win_handle, SW_SHOWNORMAL)
    UpdateWindow(win_handle)

    cursor_arrow = LoadCursorA(nil, IDC_ARROW) // LoadCursorW?
    cursor_hand = LoadCursorA(nil, IDC_HAND)
    SetTimer(win_handle, TRACK_TIMER, 1000, nil)

    msg: MSG
    for GetMessageW(&msg, nil, 0, 0)
    {
        TranslateMessage(&msg)
        DispatchMessageW(&msg)
    }
}

win_proc :: proc "stdcall" (win_handle: win32.HWND, msg: win32.UINT, wparam: win32.WPARAM, lparam: win32.LPARAM) -> win32.LRESULT
{
    using win32

    context = runtime.default_context()
    when USE_TRACKING_ALLOCATOR
    {
        context.allocator = track_allocator
    }
    free_all(context.temp_allocator)

    result: LRESULT = 0

    ctx := ui_context_create(win_handle)

    switch msg
    {
        case WM_CLOSE:
            DestroyWindow(win_handle)

        case WM_DESTROY:
            PostQuitMessage(0)

        case WM_SETCURSOR:
            cursor := Cursor(wparam)
            // fmt.println(cursor)
            if cursor == .ARROW
            {
                SetCursor(cursor_arrow)
                result = 1 // TRUE
            }
            else if cursor == .HAND
            {
                SetCursor(cursor_hand)
                result = 1 // TRUE
            }
            else
            {
                result = DefWindowProcW(win_handle, msg, wparam, lparam)
            }

        case WM_TIMER:
            if wparam == REFRESH_TIMER
            {
                if (ma.sound_is_playing(&app.sound))
                {
                    invalidate := RECT{ 0, i32(ctx.height - 100), i32(ctx.width), i32(ctx.height) }
                    InvalidateRect(win_handle, &invalidate, TRUE)
                    SetTimer(win_handle, REFRESH_TIMER, 200, nil)
                }
            }
            else if wparam == TRACK_TIMER
            {
                when USE_TRACKING_ALLOCATOR
                {
                    for _, leak in track.allocation_map
                    {
                        fmt.printf("%v leaked %v bytes\n", leak.location, leak.size)
                    }
                }
            }

        case WM_CHAR:
            if (wparam == 'o')
            {
                path, ok := win32_open_file_dialog("Music Files (.mp3, .flac, .wav, .ogg)\u0000*.mp3;*.flac;*.wav;*.ogg\u0000")
                if ok
                {
                    // reset_queue(&app)
                    music_info, ok := get_music_info_from_path(path)
                    if ok do add_music_to_queue(&app, music_info)
                    else do delete(path)
                    fmt.println("playing \"", path, "\"")
                    // print_music_title(filename)
                    InvalidateRect(win_handle, nil, TRUE)
                }
            }
            /*
            else if (wparam == 'O')
            {
                wchar filename[MAX_PATH]
                if (open_file_dialog(filename, MAX_PATH, L"\0"))
                {
                    add_music_to_queue(&app, filename)
                    // print_music_title(filename)
                    InvalidateRect(win_handle, nil, TRUE)
                }
            }
            else */
            if wparam == 'p'
            {
                // toggle_pause_music(&app)
                InvalidateRect(win_handle, nil, TRUE)
            }
            else if wparam == ','
            {
                // jump_queue(&app, app.playing_index - 1)
                InvalidateRect(win_handle, nil, TRUE)
            }
            else if wparam == '.'
            {
                // jump_queue(&app, app.playing_index + 1)
                InvalidateRect(win_handle, nil, TRUE)
            }
            else if wparam == 'q'
            {
                change_speed(&app, -1)
                // app.speed = max(0.5, app.speed - 0.1)
                // if app.sound.pDataSource != nil
                // {
                //     ma.sound_set_pitch(&app.sound, app.speed)
                // }
                InvalidateRect(win_handle, nil, TRUE)
            }
            else if (wparam == 'w')
            {
                change_speed(&app, 1)
                // app.speed = min(2.0, app.speed + 0.1)
                // if app.sound.pDataSource != nil
                // {
                //     ma.sound_set_pitch(&app.sound, app.speed)
                // }
                InvalidateRect(win_handle, nil, TRUE)
            }
            else if (wparam == 'b')
            {
                app.left.scroll = min(app.left.scroll + 0.1, 1)
                InvalidateRect(win_handle, nil, TRUE)
            }
            else if (wparam == 'v')
            {
                app.left.scroll = max(app.left.scroll - 0.1, 0)
                InvalidateRect(win_handle, nil, TRUE)
            }
            // fmt.println(app.left.scroll)

        case WM_KEYDOWN, WM_SYSKEYDOWN:
            if wparam == VK_ESCAPE
            {
                PostQuitMessage(0)
            }
            else if wparam == VK_SPACE
            {
                toggle_pause_music(&app)
                InvalidateRect(win_handle, nil, TRUE)
            }
            else if wparam == VK_BACK
            {
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
            // @todo @analyze: does this affect performance a lot?
            // is there a better way to do this?
            ctx.msg = .MOUSE_MOVE
            app_run(&app, &ctx)

            if app.last_cursor != ctx.next_cursor
            {
                app.last_cursor = ctx.next_cursor
                // fmt.println("cursor 1")
                PostMessageW(win_handle, WM_SETCURSOR, WPARAM(ctx.next_cursor), 0)
            }

            track: TRACKMOUSEEVENT = {
                size_of(TRACKMOUSEEVENT),
                TME_LEAVE,
                win_handle,
                HOVER_DEFAULT,
            }
            TrackMouseEvent(&track)

        case WM_MOUSELEAVE:
            app.last_cursor = .NONE
            InvalidateRect(win_handle, nil, TRUE)

        case WM_LBUTTONDOWN:
            if wparam & MK_LBUTTON != 0
            {
                if !app.mouse_down
                {
                    time: FILETIME
                    GetSystemTimePreciseAsFileTime(&time)
                    time64 := u64(time.dwLowDateTime) + u64(time.dwHighDateTime << 32)

                    if time64 - app.last_click_time < 3000000
                    {
                        // printf("%lld\n", time64 - app.last_click_time)
                        ctx.msg = .MOUSE_DOUBLE_CLICK
                        app_run(&app, &ctx)
                    }

                    app.last_click_cx = ctx.cx
                    app.last_click_cy = ctx.cy
                    app.last_click_time = time64
                }

                app.mouse_down = true
                InvalidateRect(win_handle, nil, TRUE)
            }

        case WM_LBUTTONUP:
            if app.mouse_down
            {
                ctx.msg = .MOUSE_LEFT_RELEASED
                app_run(&app, &ctx)
            }

            app.mouse_down = false
            InvalidateRect(win_handle, nil, TRUE)

        case WM_MOUSEWHEEL:
            ctx.scroll = f32(GET_WHEEL_DELTA_WPARAM(wparam)) / WHEEL_DELTA
            ctx.msg = .MOUSE_WHEEL
            app_run(&app, &ctx)

        case WM_PAINT:
            ps: PAINTSTRUCT
            paint_hdc: HDC = BeginPaint(win_handle, &ps)
            hdc: HDC
            buffered: HPAINTBUFFER = BeginBufferedPaint(paint_hdc, &ps.rcPaint, .COMPATIBLEBITMAP, nil, &hdc)
            if buffered != nil
            {
                font_old := HFONT(SelectObject(hdc, HGDIOBJ(font_default)))
                SetBkMode(hdc, TRANSPARENT)
                prev_brush: HBRUSH = cast(HBRUSH) SelectObject(hdc, GetStockObject(DC_BRUSH))
                SelectObject(hdc, GetStockObject(NULL_PEN))

                ctx.hdc = hdc
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

font_init :: proc()
{
    using win32

    font_default = CreateFontW(FONT_HEIGHT, 0,
                               0, 0,
                               FW_DONTCARE,
                               0, 0, 0,
                               ANSI_CHARSET,
                               OUT_DEFAULT_PRECIS,
                               CLIP_DEFAULT_PRECIS,
                               DEFAULT_QUALITY,
                               DEFAULT_PITCH | FF_DONTCARE,
                               win32.L("ProggySquareTT"))
}

ui_context_create :: proc(win_handle: win32.HWND) -> Ui_Context
{
    using win32

    ctx: Ui_Context
    ctx.win_handle = win_handle
    ctx.text_align = TA_CENTER
    // ctx.next_cursor = .ARROW

    win: RECT
    if GetClientRect(win_handle, &win)
    {
        ctx.width = int(win.right - win.left)
        ctx.height = int(win.bottom - win.top)
    }

    cursor: POINT
    if GetCursorPos(&cursor)
    {
        ScreenToClient(win_handle, &cursor)
        ctx.cx = int(cursor.x)
        ctx.cy = int(cursor.y)
    }

    return ctx
}
/*
ideas:
- app_run() once in non-WM_PAINT event and queue required draws, then draw during WM_PAINT
*/
