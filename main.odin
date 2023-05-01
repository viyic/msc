package msc

import "core:fmt"
import "core:runtime"
import "core:strings"
import "core:mem"
import win32 "core:sys/windows"
import ma "vendor:miniaudio"

app: App
theme: Theme
track: mem.Tracking_Allocator
track_allocator: mem.Allocator

cursor_arrow: win32.HCURSOR
cursor_hand: win32.HCURSOR

REFRESH_TIMER :: 1
TRACK_TIMER :: 2

main :: proc()
{
    using win32

    mem.tracking_allocator_init(&track, context.allocator)
    track_allocator = mem.tracking_allocator(&track)
    context.allocator = track_allocator

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

    if win_handle == nil {
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

Arena :: struct
{

}

Panel :: struct
{
    scroll: f32
}

Music_File :: struct
{

}

App :: struct
{
    win_handle: win32.HWND,
    mouse_down: b32,

    run: b32,
    speed: f32,

    main_arena: Arena,
    file_arena: Arena,
    temp_arena: Arena,

    engine: ma.engine,
    sound: ma.sound,

    paused: b32,
    volume: f32,
    cursor: f32,
    length: f32,
    loop: Loop_State,

    left: Panel,
    right: Panel,
    bottom: Panel,

    // wchar current_path[MAX_PATH];
    // Array<String_Null> file_list;
    // Array<Music_File> file_list;

    queue: ^Music_File,
    queue_max_count: u32,
    playing_index: u32,
    queue_first: ^Music_File,

    last_click_cx, last_click_cy: int,
    last_click_time: u64,

    last_cursor: Cursor,
}

font_default: win32.HFONT
FONT_HEIGHT :: 11

font_init :: proc()
{
    using win32

    // font_default = CreateFontW(16, 0,
    //                            0, 0,
    //                            FW_DONTCARE,
    //                            0, 0, 0,
    //                            ANSI_CHARSET,
    //                            OUT_DEFAULT_PRECIS,
    //                            CLIP_DEFAULT_PRECIS,
    //                            ANTIALIASED_QUALITY,
    //                            DEFAULT_PITCH | FF_DONTCARE,
    //                            win32.L("Segoe UI"))
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

win32_open_file_dialog :: proc(filter: string, allocator := context.allocator) -> (path: string, ok: bool)
{
    using win32

    context.allocator = allocator

    max_length: u32 = MAX_PATH_WIDE
    file_buf := make([]u16, max_length)

    ofn := OPENFILENAMEW{
        lStructSize = size_of(OPENFILENAMEW),
        hwndOwner = GetActiveWindow(),
        lpstrFile = wstring(&file_buf[0]),
        nMaxFile = max_length,
        lpstrFilter = utf8_to_wstring(filter),
        Flags = OFN_FILEMUSTEXIST,
    }

    ok = bool(win32.GetOpenFileNameW(&ofn))

    if !ok
    {
        delete(file_buf)
        return
    }

    file_name, _ := utf16_to_utf8(file_buf[:], allocator)
    path = strings.trim_right_null(file_name)

    return
}

ui_context_create :: proc(win_handle: win32.HWND) -> Ui_Context
{
    using win32

    ctx: Ui_Context
    ctx.win_handle = win_handle
    // ctx.next_cursor = .ARROW

    win: RECT;
    if GetClientRect(win_handle, &win)
    {
        ctx.width = int(win.right - win.left)
        ctx.height = int(win.bottom - win.top)
    }

    cursor: POINT
    if GetCursorPos(&cursor)
    {
        ScreenToClient(win_handle, &cursor);
        ctx.cx = int(cursor.x)
        ctx.cy = int(cursor.y)
    }
    // ctx.hdc = hdc

    return ctx
}

win_proc :: proc "stdcall" (win_handle: win32.HWND, msg: win32.UINT, wparam: win32.WPARAM, lparam: win32.LPARAM) -> win32.LRESULT
{
    using win32

    context = runtime.default_context()
    context.allocator = track_allocator

    result: LRESULT = 0

    ctx := ui_context_create(win_handle)

    switch msg
    {
        case WM_CLOSE:
            DestroyWindow(win_handle);

        case WM_DESTROY:
            PostQuitMessage(0);

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
                    invalidate := RECT{ 0, i32(ctx.height - 100), i32(ctx.width), i32(ctx.height) };
                    InvalidateRect(win_handle, &invalidate, TRUE);
                    SetTimer(win_handle, REFRESH_TIMER, 200, nil);
                }
            }
            else if wparam == TRACK_TIMER
            {
                // for _, leak in track.allocation_map
                // {
                //     fmt.printf("%v leaked %v bytes\n", leak.location, leak.size)
                // }
            }

        case WM_CHAR:
            if (wparam == 'o')
            {
                path, ok := win32_open_file_dialog("Music Files (.mp3, .flac, .wav, .ogg)\u0000*.mp3;*.flac;*.wav;*.ogg\u0000")
                if ok
                {
                    defer delete(path)
                    // reset_queue(&app);
                    add_music_to_queue(&app, path)
                    fmt.println("playing \"", path, "\"")
                    // print_music_title(filename);
                    InvalidateRect(win_handle, nil, TRUE)
                }
            }
            /*
            else if (wparam == 'O')
            {
                wchar filename[MAX_PATH];
                if (open_file_dialog(filename, MAX_PATH, L"\0"))
                {
                    add_music_to_queue(&app, filename);
                    // print_music_title(filename);
                    InvalidateRect(win_handle, nil, TRUE);
                }
            }
            else */
            if wparam == 'p'
            {
                // toggle_pause_music(&app);
                InvalidateRect(win_handle, nil, TRUE)
            }
            else if wparam == ','
            {
                // jump_queue(&app, app.playing_index - 1);
                InvalidateRect(win_handle, nil, TRUE)
            }
            else if wparam == '.'
            {
                // jump_queue(&app, app.playing_index + 1);
                InvalidateRect(win_handle, nil, TRUE)
            }
            else if wparam == 'q'
            {
                app.speed = max(0.5, app.speed - 0.1)
                if app.sound.pDataSource != nil
                {
                    ma.sound_set_pitch(&app.sound, app.speed)
                }
                InvalidateRect(win_handle, nil, TRUE)
            }
            else if (wparam == 'w')
            {
                app.speed = min(2.0, app.speed + 0.1)
                if app.sound.pDataSource != nil
                {
                    ma.sound_set_pitch(&app.sound, app.speed)
                }
                InvalidateRect(win_handle, nil, TRUE);
            }
            else if (wparam == 'b')
            {
                app.left.scroll = min(app.left.scroll + 0.1, 1);
                InvalidateRect(win_handle, nil, TRUE);
            }
            else if (wparam == 'v')
            {
                app.left.scroll = max(app.left.scroll - 0.1, 0);
                InvalidateRect(win_handle, nil, TRUE);
            }
            // fmt.println(app.left.scroll)

        case WM_KEYDOWN, WM_SYSKEYDOWN:
            if wparam == VK_ESCAPE
            {
                PostQuitMessage(0);
            }
            else if wparam == VK_SPACE
            {
                toggle_pause_music(&app)
                InvalidateRect(win_handle, nil, TRUE)
            }
            else if wparam == VK_BACK
            {
                index := 0;
                prev: ^Music_File = nil
                /*
                for cursor: ^Music_File = app.queue_first;
                    cursor != nil;
                    cursor = cursor.next
                {
                    if (index == app.playing_index)
                    {
                        if (prev)
                        {
                            prev->next = cursor->next;
                        }
                        else
                        {
                            app.queue_first = cursor->next;
                        }
                        cursor->active = false
                        cursor->next = nil
                        app.paused = true
                        if app.queue_first == nil
                        {
                            ma.sound_uninit(&app.sound);
                        }
                        else
                        {
                            jump_queue(&app, MIN(cast(int) queue_count(&app) - 1, index));
                            ma.sound_stop(&app.sound);
                        }
                        break
                    }
                    index += 1
                    prev = cursor
                }
                */
                InvalidateRect(win_handle, nil, TRUE);
            }

        case WM_MOUSEMOVE:
            // @todo @analyze: does this affect performance a lot?
            // is there a better way to do this?
            ctx.msg = .MOUSE_MOVE;
            app_run(&app, &ctx);

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
            TrackMouseEvent(&track);

        case WM_MOUSELEAVE:
            app.last_cursor = .NONE
            InvalidateRect(win_handle, nil, TRUE);

        case WM_LBUTTONDOWN:
            if wparam == MK_LBUTTON
            {
                if !app.mouse_down
                {
                    app.last_click_cx = ctx.cx
                    app.last_click_cy = ctx.cy
                    time: FILETIME
                    GetSystemTimePreciseAsFileTime(&time)
                    time64 := u64(time.dwLowDateTime) + u64(time.dwHighDateTime << 32)

                    if time64 - app.last_click_time < 3000000
                    {
                        // printf("%lld\n", time64 - app.last_click_time);
                        // ctx.font_height = playing_size.cy;
                        ctx.msg = .MOUSE_DOUBLE_CLICK;
                        // platform: Platform_Ui_Context
                        // ctx.platform = &platform;
                        // app_run(&app, &ctx);
                    }

                    app.last_click_time = time64
                }

                app.mouse_down = true
                InvalidateRect(win_handle, nil, TRUE)
            }

        case WM_LBUTTONUP:
            if app.mouse_down
            {
                ctx.msg = .MOUSE_CLICK
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
            // else if app.last_cursor == .NONE && GetCursor() != cursor_arrow
            // {
            //     PostMessageW(win_handle, WM_SETCURSOR, WPARAM(Cursor.ARROW), 0)
            // }

        case:
            result = DefWindowProcW(win_handle, msg, wparam, lparam)
    }

    return result
}

app_init :: proc(app: ^App, win_handle: win32.HWND) -> ma.result
{
    app.win_handle = win_handle
    app.run = true;
    app.volume = 0.5;
    app.speed = 1;
    app.queue_max_count = 128;

    result := ma.engine_init(nil, &app.engine)
    if result != ma.result.SUCCESS
    {
        fmt.eprintln("engine init failed\n");
        return result
    }
    ma.engine_set_volume(&app.engine, app.volume)
    // @hack: too lazy to make config
    app.engine.pDevice.onData = ma_engine_data_callback

    theme_init_default(&theme)

    return result
}

Theme :: struct
{
    background: [3]f32,
    text: [3]f32,
    button: struct {
        normal: [3]f32,
        hover: [3]f32,
        click: [3]f32,
    },
}

theme_init_default :: proc(theme: ^Theme)
{
    theme.background = { 0.1, 0.1, 0.1 }
    theme.text = { 1, 1, 1 }
    theme.button.normal = { 0.3, 0.3, 0.3 }
    theme.button.hover = { 0.4, 0.4, 0.4 }
    theme.button.click = { 0.35, 0.35, 0.35 }
}

app_run :: proc(app: ^App, ctx: ^Ui_Context)
{
    // app.temp_arena.used = 0

    // app.bottom.x = 0
    // app.bottom.y = ctx->height - 55
    // app.bottom.width = ctx->width
    // app.bottom.height = 55
    // app.left.x = 0
    // app.left.y = 0
    // app.left.width = ctx->width - ctx->width / 3
    // app.left.height = ctx->height - app->bottom.height
    // app.right.x = ctx->width - ctx->width / 3
    // app.right.y = 0
    // app.right.width = ctx->width / 3
    // app.right.height = ctx->height - app->bottom.height

    set_color(ctx, theme.background)
    draw_rect(ctx, 0, 0, ctx.width, ctx.height)
    // draw_text(ctx, 100, 100, "HEY")

    ui_panel_left(app, ctx)
    // ui_right_panel(app, ctx)
    ui_panel_bottom(app, ctx)

    if ctx.next_cursor == .NONE
    {
        ctx.next_cursor = .ARROW
    }

    if ctx.msg != .PAINT && ctx.redraw
    {
        win32.InvalidateRect(ctx.win_handle, nil, win32.TRUE)
        // refresh_draw()
    }
}

between :: proc(a: $T, x: T, b: T) -> b32
{
    return a < x && x < b
}

between_equal :: proc(a: $T, x: T, b: T) -> b32
{
    return a <= x && x <= b
}

between_equal_left :: proc(a: $T, x: T, b: T) -> b32
{
    return a <= x && x < b
}

between_equal_right :: proc(a: $T, x: T, b: T) -> b32
{
    return a < x && x <= b
}

point_in_rect :: #force_inline proc(px, py: int, rect: Rect) -> b32
{
    return between(rect.x, px, rect.x + rect.w) &&
           between(rect.y, py, rect.y + rect.h)
}

get_text_size :: proc(ctx: ^Ui_Context, str: string) -> Rect
{
    using win32

    hdc := ctx.hdc
    font_old: HFONT
    if ctx.msg != .PAINT
    {
        hdc = GetDC(ctx.win_handle)
        font_old = HFONT(SelectObject(hdc, HGDIOBJ(font_default)))
    }
    length_size: win32.SIZE
    GetTextExtentPoint32W(hdc, utf8_to_wstring(str), i32(len(str)), &length_size);
    if ctx.msg != .PAINT
    {
        SelectObject(hdc, HGDIOBJ(font_old))
        ReleaseDC(ctx.win_handle, hdc)
    }

    return { 0, 0, int(length_size.cx), int(length_size.cy) }
}

Ui_Context :: struct
{
    cx, cy: int
    width, height: int
    scroll: f32
    msg: Ui_Message

    redraw: b32
    redraw_rect: win32.RECT
    next_cursor: Cursor

    hdc: win32.HDC
    win_handle: win32.HWND
}

Ui_Message :: enum
{
    NONE
    PAINT
    MOUSE_MOVE
    MOUSE_CLICK
    MOUSE_DOUBLE_CLICK
    MOUSE_WHEEL
}

Cursor :: enum
{
    NONE
    ARROW
    HAND
}

// read_dir :: proc() -> [dynamic]string
// {
//     using win32

//     file_data: WIN32_FIND_DATAW
//     file := FindFirstFileW(win32.L(`D:\msc\*`), &file_data)
//     assert(file != INVALID_HANDLE_VALUE)
//     defer FindClose(file)

//     file_list := make([dynamic]string, 0, 256)

//     found := false
//     found_prev_dir := false
//     for {
//         // if (file_data.cFileName == "." == 0 ||
//         //     file_data.cFileName == "..") == 0 ||
//         //     file_data.cFileName == "System Volume Information")) continue

//         if file_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY != 0
//         {
//         }
//         else
//         {
//         }
//         // file_name, err := utf16_to_utf8(file_data.cFileName[:])
//         append(&file_list, `hai`) //file_name)
//         // delete(file_name)
//         if !FindNextFileW(file, &file_data)
//         {
//             break
//         }
//     }

//     fmt.println(file_list)

//     return file_list
// }

read_dir :: proc() -> [dynamic]string
{
    file_list := make([dynamic]string, 0, 256)

    for _ in 0..=218 {
        append(&file_list, `hai`)
    }

    return file_list
}
