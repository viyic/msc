package msc

import "core:fmt"
import win32 "core:sys/windows"

draw_rect_default :: proc(ctx: ^Platform_Ui_Context, x: int, y: int, w: int, h: int) {
	using win32
	rect := win32.RECT{i32(x), i32(y), i32(x + w), i32(y + h)}
	FillRect(ctx.hdc, &rect, HBRUSH(GetStockObject(DC_BRUSH)))
}

draw_rect_rect :: #force_inline proc(ctx: ^Platform_Ui_Context, rect: Rect) {
	draw_rect_default(ctx, rect.x, rect.y, rect.w, rect.h)
}

draw_rect :: proc {
	draw_rect_default,
	draw_rect_rect,
}

set_color :: proc(ctx: ^Platform_Ui_Context, col: [3]f32) {
	r := u8(col.r * 255)
	g := u8(col.g * 255)
	b := u8(col.b * 255)
	win32.SetDCBrushColor(ctx.hdc, win32.RGB(r, g, b))
}

set_text_color :: proc(ctx: ^Platform_Ui_Context, col: [3]f32) {
	r := u8(col.r * 255)
	g := u8(col.g * 255)
	b := u8(col.b * 255)
	SetTextColor(ctx.hdc, win32.RGB(r, g, b))
}

button :: proc(
	ctx: ^Platform_Ui_Context,
	x, y, w, h: int,
	str: string,
	clip := Rect{},
	config := button_config_default,
) -> bool {
	result := false
	hover := false

	// @todo: tweak this
	hover_area := 50

	clip_exists := clip.w != 0 && clip.h != 0

	in_clip := !clip_exists || point_in_rect(ctx.cx, ctx.cy, clip)

	if in_clip && between_equal_left(x, ctx.cx, x + w) && between_equal_left(y, ctx.cy, y + h) {
		hover = true
		ctx.next_cursor = .HAND
	}

	result = hover && ctx.mouse_down

	if ctx.msg == .PAINT {
		if result {
			set_color(ctx, theme.button.click)
		} else {
			if hover {
				set_color(ctx, theme.button.hover)
			} else {
				set_color(ctx, theme.button.normal)
			}
		}

		rect := Rect{x, y, w, h}
		if clip_exists {
			if rect.x < clip.x {
				rect.w -= clip.x - rect.x
				rect.x = clip.x
			}
			if rect.y < clip.y {
				rect.h -= clip.y - rect.y
				rect.y = clip.y
			}
			rect.w = min(rect.w, clip.w)
			rect.h = min(rect.h, clip.h)
		}

		// @todo: use a workaround since we don't have this
		// region_handle: win32.HRGN = win32.CreateRectRgn(rect.x, rect.y, x1(rect), y1(rect))
		// win32.SelectClipRgn(ctx.hdc, region_handle)

		draw_rect(ctx, rect)
		set_text_color(ctx, theme.text)
		set_text_align(ctx, config.text_align.x)
		x_ := x
		if config.text_align.x == TA_CENTER do x_ += w / 2
		else if config.text_align.x == TA_RIGHT do x_ += w - config.inset.x
		else do x_ += config.inset.x / 2
		label(ctx, x_, y + (h - ctx.font_height) / 2, str)
		set_text_color(ctx, 0)
	} else {
		if hover ||
		   (between_equal_left(x - hover_area, ctx.cx, x + w + hover_area) &&
				   between_equal_left(y - hover_area, ctx.cy, y + h + hover_area)) {
			ctx.redraw = true
		}
	}

	clicked := false
	if config.double_click {
		if ctx.msg == .MOUSE_DOUBLE_CLICK &&
		   between_equal_left(x, ctx.last_click_cx, x + w) &&
		   between_equal_left(y, ctx.last_click_cy, y + h) {
			clicked = true
		}
	} else if ctx.msg == .MOUSE_LEFT_RELEASED {
		clicked = true
	}

	return result && clicked
}

label :: proc(ctx: ^Platform_Ui_Context, x: int, y: int, text: string) {
	if ctx.msg != .PAINT {
		return
	}

	draw_text(ctx, x, y, text)
}

/*
slider :: proc(ctx: ^Platform_Ui_Context, x: int, y: int, w: int, h: int, str: string, clip := Rect{}, loc := #caller_location) -> f32
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
        label(ctx, x_, y + (h - app.font_height) / 2, str)
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

set_text_align :: proc(ctx: ^Platform_Ui_Context, text_align: u32) {
	if ctx.text_align == text_align do return

	ctx.text_align = text_align
	SetTextAlign(ctx.hdc, text_align)
}

draw_text :: proc(ctx: ^Platform_Ui_Context, x: int, y: int, str: string) {
	// @warning: utf8_to_wstring might crash because there's no check for len(res) > 0
	// D:/Odin/core/sys/windows/util.odin(57:15) Index 0 is out of range 0..<0
	if len(str) <= 0 do return
	win32.TextOutW(ctx.hdc, i32(x), i32(y), win32.utf8_to_wstring(str), i32(len(str)))
}
