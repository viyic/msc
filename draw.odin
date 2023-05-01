package msc

import "core:fmt"
import "core:os"
import "core:slice"
import "core:path/filepath"
import win32 "core:sys/windows"
import ma "vendor:miniaudio"

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
    draw_rect_default,
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

button :: proc(ctx: ^Ui_Context, x: int, y: int, w: int, h: int, str: string) -> bool
{
    font_height := FONT_HEIGHT
    result := false
    hover := false

    // @todo: tweak this
    hover_area := 50

    if between_equal_left(x, ctx.cx, x + w) &&
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
        label(ctx, x + w / 2, y + (h - font_height) / 2, str)
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

    return result && ctx.msg == .MOUSE_CLICK
}

label :: proc(ctx: ^Ui_Context, x: int, y: int, text: string)
{
    if ctx.msg != .PAINT
    {
        return
    }

    draw_text(ctx, x, y, text);
}

set_text_align :: proc(ctx: ^Ui_Context, text_align: u32)
{
    win32.SetTextAlign(ctx.hdc, text_align);
}

draw_text :: proc(ctx: ^Ui_Context, x: int, y: int, str: string)
{
    win32.TextOutW(ctx.hdc, i32(x), i32(y), win32.utf8_to_wstring(str), i32(len(str)));
}

ui_panel_left :: proc(app: ^App, ctx: ^Ui_Context)
{
    // app->file_arena.used = 0;
    x := 0
    y := 0
    width := ctx.width - ctx.width / 3
    height := ctx.height - 55 //app.bottom.height

    // ---------- QUEUE
    ui_music_list(app, ctx);
    // ui_music_grid(app, ctx);

    set_color(ctx, theme.background);
    // draw_rect(ctx, 0, 0, width, 5);
}

ui_music_list :: proc(app: ^App, ctx: ^Ui_Context)
{
    width := ctx.width - ctx.width / 3
    height := ctx.height - 55
    x := 5
    padding := 5
    item_height := FONT_HEIGHT + padding

    if (ctx.scroll != 0)
    {
        app.left.scroll = max(0, min(app.left.scroll - ctx.scroll / 100, 1))
        ctx.redraw = true
    }

    at_y := 5

    index := 0
    handle, err_open := os.open("D:\\msc\\")
    if err_open != os.ERROR_NONE {
        return
    }
    defer os.close(handle)

    // file_list := [?]os.File_Info{
    //     { fullpath = `D:\msc\shirenvasea - nuestro.mp3`, name = `shirenvasea - nuestro.mp3`},
    // }
    // file_list, err_read_dir := os.read_dir(handle, 0)
    // if err_read_dir != os.ERROR_NONE {
    //     return
    // }
    file_list := read_dir()

    // using win32
    // file_data: WIN32_FIND_DATAW
    // file := FindFirstFileW(win32.L(`D:\msc\*`), &file_data)
    // assert(file != INVALID_HANDLE_VALUE)
    // defer FindClose(file)

    // file_list := make([dynamic]string, 0, 256)

    // found := false
    // found_prev_dir := false
    // for {
    //     // if (file_data.cFileName == "." == 0 ||
    //     //     file_data.cFileName == "..") == 0 ||
    //     //     file_data.cFileName == "System Volume Information")) continue

    //     if file_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY != 0
    //     {
    //     }
    //     else
    //     {
    //     }
    //     // file_name, err := utf16_to_utf8(file_data.cFileName[:])
    //     append(&file_list, `hai`) //file_name)
    //     // delete(file_name)
    //     if !FindNextFileW(file, &file_data)
    //     {
    //         break
    //     }
    // }
    defer {
        for file in file_list
        {
            delete(file)
        }
        delete(file_list)
    }

    filter_proc :: proc(item: os.File_Info) -> bool
    {
        ext := filepath.ext(item.name)
        return item.is_dir ||
            (ext == ".mp3" ||
             ext == ".flac" ||
             ext == ".wav" ||
             ext == ".ogg")
    }
    // file_list_ := slice.filter(file_list, filter_proc)
    // defer {
    //     for item, _ in file_list_
    //     {
    //         delete(item.fullpath)
    //     }
    //     delete(file_list_)
    // }

    // @todo: figure out how resizing with scrolled panel work, anchor on top left?
    list_height := item_height * (len(file_list) + 1)
    list_scroll := int(f32(list_height - height) * app.left.scroll)

    set_text_align(ctx, TA_CENTER)
    for index in 0..<len(file_list)
    {
        if at_y + item_height >= list_scroll &&
           at_y < list_scroll + height
        {
            cursor := file_list[index]

            rect := get_text_size(ctx, cursor)
            if button(ctx, x, at_y - list_scroll, int(rect.w) + padding, int(rect.h) + padding, cursor)
            {
                ext := filepath.ext(cursor)
                if 
                   (ext == ".mp3" ||
                    ext == ".flac" ||
                    ext == ".wav" ||
                    ext == ".ogg")
                {
                    add_music_to_queue(app, cursor)
                    // request_redraw(ctx, { app.left.x, app.left.y, app.left.width, app.left.height })
                }
                else
                {
                    fmt.println("waaa", cursor, ext)
                    // wcscpy_s(app.current_path, cursor.filename.length, cursor.filename.data)
                    // app.file_list = platform_list_file(app, app.current_path)
                    // app.left.scroll = 0
                }
                ctx.redraw = true
            }
        }

        at_y += item_height
    }
}

Rect :: struct
{
    x, y, w, h: int,
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

ui_panel_bottom :: proc(app: ^App, ctx: ^Ui_Context)
{
    playing := app.paused ? "|>" : "||"

    set_color(ctx, theme.background)
    draw_rect(ctx, 0, ctx.height - 55, ctx.width, 55)
    // draw_rect(ctx, app.bottom.x, app.bottom.y, app.bottom.width, app.bottom.height)

    button_play: Rect
    button_play.w = 30
    button_play.h = 30
    button_play.x = (ctx.width - button_play.w) / 2
    button_play.y = ctx.height - button_play.h - 5

    set_text_color(ctx, { 1, 1, 1 })

    // ---------- PLAY INFORMATION
    play_bar := Rect{
        5,
        button_play.y - 15,
        ctx.width - 10,
        10
    }
    set_color(ctx, { 0.2, 0.2, 0.2 })
    draw_rect(ctx, play_bar)

    if app.sound.pDataSource != nil
    {
        ma.sound_get_cursor_in_seconds(&app.sound, &app.cursor)
        ma.sound_get_length_in_seconds(&app.sound, &app.length)
    }

    right_of_play_x := 5
    if app.sound.pDataSource != nil
    {
        // ---------- PLAY BAR
        // set_color(ctx, { 0.2, 0.2, 0.2 })
        set_color(ctx, theme.button.hover)
        draw_rect(ctx, {
            play_bar.x,
            play_bar.y,
            int(app.cursor / app.length * f32(ctx.width - 10)),
            play_bar.h
        })

        if ctx.msg == .MOUSE_CLICK &&
           app.mouse_down &&
           point_in_rect(ctx.cx, ctx.cy, play_bar)
        {
            pcm_length: u64
            sample_rate: u32
            result := ma.data_source_get_length_in_pcm_frames(app.sound.pDataSource, &pcm_length)
            result = ma.data_source_get_data_format(app.sound.pDataSource, nil, nil, &sample_rate, nil, 0)
            if result == .SUCCESS {
                if app.paused
                {
                    toggle_pause_music(app)
                }
                new_length := u64(f32(pcm_length) * (f32(ctx.cx) / f32(ctx.width)))
                // @analyze: less popping?
                new_length = new_length - (new_length % u64(sample_rate))
                ma.sound_seek_to_pcm_frame(&app.sound, new_length)
            }
        }
    }

    // ---------- VOLUME BAR
    vol_bar := Rect{
        button_play.x + button_play.w + right_of_play_x,
        button_play.y + button_play.h / 2 - 5,
        int(app.volume * 80),
        10
    }
    set_color(ctx, { 0.2, 0.2, 0.2 })
    draw_rect(ctx, {
        vol_bar.x,
        vol_bar.y,
        80,
        vol_bar.h
    })
    set_color(ctx, theme.button.normal)
    draw_rect(ctx, vol_bar)
    vol_bar.w = 80
    if ctx.msg == .MOUSE_CLICK &&
       app.mouse_down &&
       point_in_rect(ctx.cx, ctx.cy, vol_bar)
    {
        new_vol := f32(ctx.cx - vol_bar.x) / f32(vol_bar.w)
        app.volume = max(min(new_vol, 1), 0)
        ma.engine_set_volume(&app.engine, app.volume)
    }
    right_of_play_x += vol_bar.w + 5

    if app.sound.pDataSource != nil
    {
        set_text_align(ctx, TA_LEFT)
        cursor_min := int(app.cursor / 60)
        cursor_sec := int(app.cursor) % 60
        length_min := int(app.length / 60)
        length_sec := int(app.length) % 60
        str := fmt.tprintf("%d:%02d/%d:%02d", cursor_min, cursor_sec, length_min, length_sec)
        rect := get_text_size(ctx, str)
        label(ctx, button_play.x + button_play.w + right_of_play_x, button_play.y + (button_play.h - FONT_HEIGHT) / 2, str)
        right_of_play_x += rect.w + 5
    }

    // ---------- LOOP
    set_text_align(ctx, TA_CENTER)
    loop_text := "loop: x"
    if (app.loop == .SINGLE)
    {
        loop_text = "loop: s"
    }
    else if (app.loop == Loop_State.PLAYLIST)
    {
        loop_text = "loop: p"
    }

    padding := 10
    loop_size := get_text_size(ctx, loop_text)
    loop_size.w += padding
    loop_size.h += padding

    if (button(ctx,
               int(button_play.x - loop_size.w - 5),
               int(button_play.y + (button_play.h - FONT_HEIGHT) / 2 - padding / 2),
               int(loop_size.w),
               int(loop_size.h),
               loop_text))
    {
        app.loop = Loop_State((int(app.loop) + 1) % len(Loop_State))
    }

    // ---------- SPEED
    set_text_align(ctx, TA_RIGHT)
    set_text_color(ctx, { 1, 1, 1 })
    str := fmt.tprintf("%.1fx", app.speed)
    label(ctx, button_play.x - loop_size.w - 10, button_play.y + (button_play.h - FONT_HEIGHT) / 2, str)

    // ---------- PLAY BUTTON
    set_text_align(ctx, TA_CENTER)
    if (button(ctx, button_play.x, button_play.y, button_play.w, button_play.h, ""))
    {
        toggle_pause_music(app)
        // refresh_draw()
        // request_redraw(ctx, { app->bottom.x, app->bottom.y, app->bottom.width, app->bottom.height })
        ctx.redraw = true
    }
    // draw_ellipse(ctx, button_play.x, button_play.y, button_play.x + button_play.w, button_play.y + button_play.h)

    set_text_color(ctx, theme.text)
    label(ctx, button_play.x + button_play.w / 2, button_play.y + (button_play.h - FONT_HEIGHT) / 2, playing)

}

Loop_State :: enum
{
    NONE,
    SINGLE,
    PLAYLIST,
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
