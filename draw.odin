package msc

import "core:fmt"
import win32 "core:sys/windows"

draw_rect_default :: proc(ctx: ^Ui_Context, x: int, y: int, w: int, h: int)
{
    using win32
    rect := win32.RECT{
        i32(x),
        i32(y),
        i32(x + w),
        i32(y + h),
    }
    FillRect(ctx.hdc, &rect, HBRUSH(GetStockObject(DC_BRUSH)))
}

draw_rect_rect :: #force_inline proc(ctx: ^Ui_Context, rect: Rect)
{
    draw_rect_default(ctx, rect.x, rect.y, rect.w, rect.h)
}

draw_rect :: proc
{
    draw_rect_default
    draw_rect_rect
}

set_color :: proc(ctx: ^Ui_Context, col: [3]f32)
{
    r := u8(col.r * 255)
    g := u8(col.g * 255)
    b := u8(col.b * 255)
    win32.SetDCBrushColor(ctx.hdc, win32.RGB(r, g, b))
}

set_text_color :: proc(ctx: ^Ui_Context, col: [3]f32)
{
    r := u8(col.r * 255)
    g := u8(col.g * 255)
    b := u8(col.b * 255)
    win32.SetTextColor(ctx.hdc, win32.RGB(r, g, b))
}

button :: proc(ctx: ^Ui_Context, x: int, y: int, w: int, h: int, str: string, clip := Rect{}) -> bool
{
    result := false
    hover := false

    // @todo: tweak this
    hover_area := 50

    in_clip := (clip.w == 0 && clip.h == 0) || point_in_rect(ctx.cx, ctx.cy, clip)

    if in_clip &&
       between_equal_left(x, ctx.cx, x + w) &&
       between_equal_left(y, ctx.cy, y + h)
    {
        hover = true
        ctx.next_cursor = .HAND
    }

    result = hover && app.mouse_down

    if ctx.msg == .PAINT
    {
        if result
        {
            set_color(ctx, theme.button.click)
        }
        else
        {
            if hover
            {
                set_color(ctx, theme.button.hover)
            }
            else
            {
                set_color(ctx, theme.button.normal)
            }
        }
        draw_rect(ctx, x, y, w, h)
        set_text_color(ctx, theme.text)
        label(ctx, x + w / 2, y + (h - FONT_HEIGHT) / 2, str)
        set_text_color(ctx, { 0, 0, 0 })
    }
    else
    {
        if hover ||
           (between_equal_left(x - hover_area, ctx.cx, x + w + hover_area) &&
            between_equal_left(y - hover_area, ctx.cy, y + h + hover_area))
        {
            // refresh_draw()
            // request_redraw(ctx, { x - hover_area, y - hover_area, w + hover_area, h + hover_area })
            ctx.redraw = true
            // win32.InvalidateRect(ctx.win_handle, nil, win32.TRUE)
        }
    }

    return result && ctx.msg == .MOUSE_LEFT_RELEASED
}

label :: proc(ctx: ^Ui_Context, x: int, y: int, text: string)
{
    if ctx.msg != .PAINT
    {
        return
    }

    draw_text(ctx, x, y, text);
}

/*
slider :: proc(ctx: ^Ui_Context, x: int, y: int, w: int, h: int, str: string, clip := Rect{}, loc := #caller_location) -> f32
{
    result := 0.0
    hover := false

    // @todo: tweak this
    hover_area := 50

    in_clip := (clip.w == 0 && clip.h == 0) || point_in_rect(ctx.cx, ctx.cy, clip)

    if in_clip &&
       between_equal_left(x, ctx.cx, x + w) &&
       between_equal_left(y, ctx.cy, y + h)
    {
        hover = true
        ctx.next_cursor = .HAND
    }

    result = hover && app.mouse_down

    if ctx.msg == .PAINT
    {
        if result
        {
            set_color(ctx, theme.button.click)
        }
        else
        {
            if hover
            {
                set_color(ctx, theme.button.hover)
            }
            else
            {
                set_color(ctx, theme.button.normal)
            }
        }
        draw_rect(ctx, x, y, w, h)
        set_text_color(ctx, theme.text)
        label(ctx, x + w / 2, y + (h - FONT_HEIGHT) / 2, str)
        set_text_color(ctx, { 0, 0, 0 })
    }
    else
    {
        if hover ||
           (between_equal_left(x - hover_area, ctx.cx, x + w + hover_area) &&
            between_equal_left(y - hover_area, ctx.cy, y + h + hover_area))
        {
            // refresh_draw()
            // request_redraw(ctx, { x - hover_area, y - hover_area, w + hover_area, h + hover_area })
            ctx.redraw = true
            // win32.InvalidateRect(ctx.win_handle, nil, win32.TRUE)
        }
    }

    return result && ctx.msg == .MOUSE_LEFT_RELEASED
}
*/

set_text_align :: proc(ctx: ^Ui_Context, text_align: u32)
{
    win32.SetTextAlign(ctx.hdc, text_align);
}

draw_text :: proc(ctx: ^Ui_Context, x: int, y: int, str: string)
{
    win32.TextOutW(ctx.hdc, i32(x), i32(y), win32.utf8_to_wstring(str), i32(len(str)));
}

/* Text Alignment Options */
TA_NOUPDATECP :: 0
TA_UPDATECP   :: 1

TA_LEFT   :: 0
TA_RIGHT  :: 2
TA_CENTER :: 6

TA_TOP        :: 0
TA_BOTTOM     :: 8
TA_BASELINE   :: 24
TA_RTLREADING :: 256
TA_MASK       :: TA_BASELINE + TA_CENTER + TA_UPDATECP + TA_RTLREADING

VTA_BASELINE :: TA_BASELINE
VTA_LEFT     :: TA_BOTTOM
VTA_RIGHT    :: TA_TOP
VTA_CENTER   :: TA_CENTER
VTA_BOTTOM   :: TA_RIGHT
VTA_TOP      :: TA_LEFT
