package msc

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:path/filepath"
import win32 "core:sys/windows"
import ma "vendor:miniaudio"

app_init :: proc(app: ^App, win_handle: win32.HWND) -> ma.result
{
    app.win_handle = win_handle
    app.current_path = strings.clone(`D:\msc`)
    update_file_list(app)
    app.volume = 0.5
    app.paused = true
    app.speed = 1
    app.playing_index = -1

    result := ma.engine_init(nil, &app.engine)
    if result != ma.result.SUCCESS
    {
        fmt.eprintln("engine init failed")
        return result
    }
    ma.engine_set_volume(&app.engine, app.volume)
    // @hack: too lazy to make config
    app.engine.pDevice.onData = ma_engine_data_callback

    theme_init_default(&theme)

    return result
}

app_run :: proc(app: ^App, ctx: ^Ui_Context)
{
    app.bottom.rect = { 0, ctx.height - 55, ctx.width, 55 }

    right_width := ctx.width / 3
    app.left.rect = { 0, 0, ctx.width - right_width, ctx.height - app.bottom.h }
    app.right.rect = { app.left.w, 0, right_width, ctx.height - app.bottom.h }

    set_color(ctx, theme.background)
    draw_rect(ctx, 0, 0, ctx.width, ctx.height)

    ui_panel_left(app, ctx)
    ui_panel_right(app, ctx)
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

update_file_list :: proc(app: ^App)
{
    handle, err_open := os.open(app.current_path)
    if err_open != os.ERROR_NONE do return
    defer os.close(handle)

    file_list, err_read_dir := os.read_dir(handle, 0)
    if err_read_dir != os.ERROR_NONE do return

    app.file_list = file_list
}

change_current_path :: proc(app: ^App, new_path: string)
{
    if len(app.file_list) > 0
    {
        os.file_info_slice_delete(app.file_list)
    }
    app.file_list = []os.File_Info{}
    delete(app.current_path)
    app.current_path = new_path
    update_file_list(app)
}

theme_init_default :: proc(theme: ^Theme)
{
    theme.background = { 0.1, 0.1, 0.1 }
    theme.text = { 1, 1, 1 }
    theme.button.normal = { 0.3, 0.3, 0.3 }
    theme.button.hover = { 0.4, 0.4, 0.4 }
    theme.button.click = { 0.35, 0.35, 0.35 }
}

ui_panel_left :: proc(app: ^App, ctx: ^Ui_Context)
{
    // ---------- QUEUE
    ui_music_list(app, ctx)
    // ui_music_grid(app, ctx)
}

ui_music_list :: proc(app: ^App, ctx: ^Ui_Context)
{
    width := ctx.width - ctx.width / 3
    height := ctx.height - 55
    x := 5
    margin := 5 // inset
    padding := 5 // for items
    item_height := FONT_HEIGHT + padding

    clip := app.left
    clip.x += margin
    clip.y += margin
    clip.w -= margin * 2
    clip.h -= margin * 2

    if ctx.scroll != 0
    {
        app.left.scroll = max(0, min(app.left.scroll - ctx.scroll / 100, 1))
        ctx.redraw = true
    }

    at_y := margin

    filter_proc :: proc(item: os.File_Info) -> bool
    {
        ext := filepath.ext(item.name)
        return item.is_dir ||
            (ext == ".mp3" ||
             ext == ".flac" ||
             ext == ".wav" ||
             ext == ".ogg")
    }
    file_list_ := slice.filter(app.file_list, filter_proc)
    file_list := slice.concatenate([][]os.File_Info{
        []os.File_Info{
            os.File_Info{
                name = "..",
                is_dir = true
            }
        },
        file_list_
    })
    delete(file_list_)

    // @todo: figure out how resizing with scrolled panel work, anchor on top left?
    list_height := item_height * (len(file_list) + 1)
    list_scroll := int(f32(list_height - height) * app.left.scroll)

    new_path := app.current_path

    set_text_align(ctx, TA_CENTER)
    for cursor in file_list
    {
        if at_y + item_height >= list_scroll &&
           at_y < list_scroll + height
        {
            rect := get_text_size(ctx, cursor.name)
            if button(ctx, x, at_y - list_scroll, rect.w + padding, rect.h + padding, cursor.name, clip, { text_align = {TA_LEFT, TA_CENTER}, inset = 5})
            {
                if !cursor.is_dir
                {
                    music_info, ok := get_music_info_from_path(cursor.fullpath)
                    // request_redraw(ctx, { app.left.x, app.left.y, app.left.width, app.left.height })

                    if ok
                    {
                        add_music_to_queue(app, music_info)
                        if win32.GetKeyState(win32.VK_SHIFT) >= 0 do jump_queue(app, len(app.queue) - 1)
                        fmt.println(music_info)
                    }
                }
                else
                {
                    if cursor.name == ".."
                    {
                        clean := filepath.clean(app.current_path, context.temp_allocator)
                        up, _ := filepath.split(clean)
                        new_path = strings.clone(up)
                    }
                    else
                    {
                        new_path = strings.clone(cursor.fullpath)
                    }
                }
                ctx.redraw = true
            }
        }

        at_y += item_height
    }

    if new_path != app.current_path
    {
        fmt.println(new_path)
        change_current_path(app, new_path)
        app.left.scroll = 0
    }

    set_color(ctx, theme.background)
    draw_rect(ctx, Rect{app.left.x, app.left.y, app.left.w, margin})
    draw_rect(ctx, Rect{app.left.x, app.left.y, margin, app.left.h})
    draw_rect(ctx, Rect{x1(app.left) - margin, app.left.y, ctx.width - (x1(app.left) - margin), app.left.h})
    draw_rect(ctx, Rect{app.left.x, y1(app.left) - margin, app.left.w, ctx.height - (y1(app.left) - margin)})
}

ui_panel_bottom :: proc(app: ^App, ctx: ^Ui_Context)
{
    playing := app.paused ? "|>" : "||"

    set_color(ctx, theme.background)
    // draw_rect(ctx, 0, ctx.height - 55, ctx.width, 55)
    draw_rect(ctx, app.bottom.x, app.bottom.y, app.bottom.w, app.bottom.h)

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

        if ctx.msg == .MOUSE_LEFT_RELEASED &&
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
    set_color(ctx, 0.2)
    draw_rect(ctx, {
        vol_bar.x,
        vol_bar.y,
        80,
        vol_bar.h
    })
    set_color(ctx, theme.button.normal)
    draw_rect(ctx, vol_bar)
    vol_bar.w = 80
    if ctx.msg == .MOUSE_LEFT_RELEASED &&
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

    if button(ctx,
              int(button_play.x - loop_size.w - 5),
              int(button_play.y + (button_play.h - FONT_HEIGHT) / 2 - padding / 2),
              int(loop_size.w),
              int(loop_size.h),
              loop_text)
    {
        app.loop = Loop_State((int(app.loop) + 1) % len(Loop_State))
    }

    // ---------- SPEED
    set_text_align(ctx, TA_RIGHT)
    set_text_color(ctx, 1)
    str := fmt.tprintf(int(app.speed * 100) % 10 == 0 ? "%.1fx" : "%.2fx", app.speed)
    label(ctx, button_play.x - loop_size.w - 10, button_play.y + (button_play.h - FONT_HEIGHT) / 2, str)

    // ---------- PLAY BUTTON
    if button(ctx, button_play.x, button_play.y, button_play.w, button_play.h, playing)
    {
        toggle_pause_music(app)
        // refresh_draw()
        // request_redraw(ctx, { app->bottom.x, app->bottom.y, app->bottom.width, app->bottom.height })
        ctx.redraw = true
    }
    // draw_ellipse(ctx, button_play.x, button_play.y, button_play.x + button_play.w, button_play.y + button_play.h)
}

ui_panel_right :: proc(app: ^App, ctx: ^Ui_Context)
{
    width := app.right.w
    x := app.right.x
    margin := 5
    padding := 5
    item_height := FONT_HEIGHT + padding

    if ctx.scroll != 0
    {

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
    label(ctx, x + width / 2, at_y + (title_height - item_height) / 2, "List")

    at_y += title_height + margin

    // ---------- QUEUE
    list_width := width - 3 * margin
    clip := Rect{x + margin, at_y, list_width, app.right.h - at_y}
    for music_info_index, queue_index in app.queue
    {
        music_info := app.music_infos[music_info_index]

        str := fmt.tprintf("%v%v%v%v",
            app.playing_index == music_info_index ? "> " : "  ",
            len(music_info.title) > 0 ? music_info.title : filepath.stem(music_info.full_path),
            len(music_info.artist) > 0 ? " : " : "",
            music_info.artist)

        if button(ctx, x + margin, at_y, list_width, item_height, str, clip, { text_align = {TA_LEFT, TA_CENTER}, inset = 5 })
        {
            jump_queue(app, queue_index)
            // request_redraw(ctx, { app.right.x, app.right.y, app.right.width, app.right.height })
        }

        // i32 length_min = cast(i32) (cursor.length / 60)
        // i32 length_sec = cast(i32) cursor.length % 60
        // String_Null length = push_printf_null(&app.temp_arena, L"%d.%.2d", length_min, length_sec)
        // set_text_align(ctx, TA_RIGHT)
        // label(ctx, x + width - 15, at_y, length)

        // set_text_color(ctx, 0)

        at_y += item_height
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
    draw_rect(ctx, x + width - 2 * margin, margin + title_height, margin, app.right.h - margin - title_height)
    set_color(ctx, theme.background)
    draw_rect(ctx, x + width - margin, app.right.y, margin, app.right.h)
}
