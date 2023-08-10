package msc

import "core:strings"
import win32 "core:sys/windows"

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
    return between_equal_left(rect.x, px, rect.x + rect.w) &&
           between_equal_left(rect.y, py, rect.y + rect.h)
}

win32_rect_to_rect :: proc(r0: win32.RECT) -> Rect
{
    return {
        int(r0.left),
        int(r0.top),
        int(r0.right - r0.left),
        int(r0.bottom - r0.top)
    }
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
    str_ := utf8_to_utf16(str)
    GetTextExtentPoint32W(hdc, &str_[0], i32(len(str_)), &length_size)
    if ctx.msg != .PAINT
    {
        SelectObject(hdc, HGDIOBJ(font_old))
        ReleaseDC(ctx.win_handle, hdc)
    }

    return { 0, 0, int(length_size.cx), int(length_size.cy) }
}

win32_open_file_dialog :: proc(filter: string, allocator := context.allocator) -> (path: string, ok: bool)
{
    using win32

    context.allocator = allocator

    max_length: u32 = MAX_PATH_WIDE
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

    if !ok
    {
        return
    }

    file_name, _ := utf16_to_utf8(file_buf[:], allocator)
    path = strings.trim_right_null(file_name)

    return
}

x1 :: #force_inline proc(rect: Rect) -> int
{
    return rect.x + rect.w
}

y1 :: #force_inline proc(rect: Rect) -> int
{
    return rect.y + rect.h
}

u16_bytes_to_u16 :: proc(bytes: []u8, allocator := context.temp_allocator) -> ([]u16, bool)
{
    if len(bytes) % 2 != 0 do return {}, false

    result := make([]u16, len(bytes) / 2, allocator)
    for index := 0; index < len(result); index += 1
    {
        result[index] = u16(bytes[index * 2]) |
                        u16(bytes[index * 2 + 1]) << 8
    }

    return result, true
}

u16_bytes_to_u8 :: proc(bytes: []u8, allocator := context.temp_allocator) -> (string, bool)
{
    if len(bytes) % 2 != 0 do return {}, false

    result := make([]u8, len(bytes) / 2, allocator)

    return {}, true
}
