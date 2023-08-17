package msc

import "core:fmt"
import "core:strings"
import "core:runtime"
import win32 "core:sys/windows"
import ma "vendor:miniaudio"

platform_window_handle :: win32.HWND
platform_font_handle :: win32.HFONT
platform_cursor_handle :: win32.HCURSOR

platform_ui_context_create :: proc(app: ^App, hdc: win32.HDC = nil) -> Platform_Ui_Context
{
    using win32

    ctx: Platform_Ui_Context
    ctx.win_handle = app.win_handle
    ctx.hdc = hdc
    ctx.last_click_cx = app.last_click_cx
    ctx.last_click_cy = app.last_click_cy
    ctx.mouse_down = app.mouse_down
    ctx.font_height = app.font_height

    set_text_align(&ctx, TA_CENTER)

    win: RECT
    if GetClientRect(ctx.win_handle, &win)
    {
        ctx.width = int(win.right - win.left)
        ctx.height = int(win.bottom - win.top)
    }

    cursor: POINT
    if GetCursorPos(&cursor)
    {
        ScreenToClient(ctx.win_handle, &cursor)
        ctx.cx = int(cursor.x)
        ctx.cy = int(cursor.y)
    }

    return ctx
}

platform_get_text_size :: proc(ctx: ^Platform_Ui_Context, str: string) -> Rect
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
    str_ := utf8_to_utf16(str)
    GetTextExtentPoint32W(hdc, &str_[0], i32(len(str_)), &length_size)
    if ctx.msg != .PAINT
    {
        SelectObject(hdc, HGDIOBJ(font_old))
        ReleaseDC(ctx.win_handle, hdc)
    }

    return { 0, 0, int(length_size.cx), int(length_size.cy) }
}

platform_rect_to_rect :: proc(r0: win32.RECT) -> Rect
{
    return {
        int(r0.left),
        int(r0.top),
        int(r0.right - r0.left),
        int(r0.bottom - r0.top)
    }
}

platform_open_file_dialog :: proc(filter: string, allocator := context.allocator) -> (path: string, ok: bool)
{
    using win32

    context.allocator = allocator

    max_length := u32(MAX_PATH_WIDE)
    file_buf := make([]u16, max_length)
    defer delete(file_buf)
    // @note: use normal allocator to prevent overwrite
    filter_ := utf8_to_wstring(filter, allocator)
    defer free(filter_)

    ofn := OPENFILENAMEW{
        lStructSize = size_of(OPENFILENAMEW),
        hwndOwner = GetActiveWindow(),
        lpstrFile = wstring(&file_buf[0]),
        nMaxFile = max_length,
        lpstrFilter = filter_,
        Flags = OFN_FILEMUSTEXIST,
    }

    ok = bool(win32.GetOpenFileNameW(&ofn))

    if !ok do return

    file_name, _ := utf16_to_utf8(file_buf[:], allocator)
    path = strings.trim_right_null(file_name)

    return
}

platform_miniaudio_sound_init :: proc(app: ^App, path: string) -> bool
{
    return ma.sound_init_from_file_w(&app.engine, win32.utf8_to_wstring(path), u32(ma.sound_flags.STREAM | ma.sound_flags.NO_SPATIALIZATION), nil, nil, &app.sound) == .SUCCESS
}

platform_window_set_text :: proc(app: ^App, text: string)
{
    text_ := win32.utf8_to_wstring(text, context.allocator)
    defer free(text_)
    win32.SetWindowTextW(app.win_handle, text_)
}

platform_get_shift_key :: proc() -> bool
{
    return win32.GetKeyState(win32.VK_SHIFT) >= 0
}

platform_redraw :: proc(app: ^App)
{
    win32.InvalidateRect(app.win_handle, nil, win32.TRUE)
}

platform_get_executable_path :: proc() -> (string, bool)
{
    executable_path := make([]u16, win32.MAX_PATH_WIDE)
    defer delete(executable_path)
    win32.GetModuleFileNameW(nil, &executable_path[0], u32(len(executable_path)))
    result, err := win32.utf16_to_utf8(executable_path[:], context.allocator)

    return result, err == .None
}

platform_timer_start :: proc(app: ^App, timer: Timer, time: u32)
{
    win32.SetTimer(app.win_handle, uintptr(timer), time, nil)
}

platform_timer_stop :: proc(app: ^App, timer: Timer)
{
    win32.KillTimer(app.win_handle, uintptr(timer))
}


platform_window_create :: proc() -> win32.HWND
{
    using win32

    instance := HINSTANCE(GetModuleHandleW(nil))
    class_name := win32.L("msc") // issue #2007

    win_class: WNDCLASSEXW
    win_class.cbSize = size_of(win_class)
    win_class.lpfnWndProc = win_proc
    win_class.hInstance = instance
    win_class.lpszClassName = class_name
    win_class.style = CS_HREDRAW | CS_VREDRAW
    win_class.hIcon = HICON(LoadImageW(instance, win32.L("MSC_ICON"), IMAGE_ICON, LR_DEFAULTSIZE, LR_DEFAULTSIZE, 0))
    win_class.hIconSm = HICON(LoadImageW(instance, win32.L("MSC_ICON"), IMAGE_ICON, LR_DEFAULTSIZE, LR_DEFAULTSIZE, 0))
    if !b32(RegisterClassExW(&win_class)) do return nil

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
    if win_handle == nil do return nil

    // windows dark titlebar
    DWMWA_USE_IMMERSIVE_DARK_MODE :: 20
    dark_mode: BOOL = TRUE
    DwmSetWindowAttribute(win_handle, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark_mode, size_of(dark_mode))

    cursor_arrow = LoadCursorA(nil, IDC_ARROW) // LoadCursorW?
    cursor_hand = LoadCursorA(nil, IDC_HAND)

    return win_handle
}

Platform_Ui_Context :: struct
{
    cx, cy: int,
    width, height: int,
    scroll: f32,
    msg: Ui_Message,
    text_align: u32,

    font_height: int,
    last_click_cx, last_click_cy: int,
    mouse_down: b32,

    redraw: b32,
    redraw_rect: win32.RECT,
    next_cursor: Cursor,

    hold: runtime.Source_Code_Location, // @analyze: add z and compare the z?

    hdc: win32.HDC,
    win_handle: platform_window_handle,
}
