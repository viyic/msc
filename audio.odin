package msc

import "core:fmt"
import "core:runtime"
import win32 "core:sys/windows"
import ma "vendor:miniaudio"

ma_engine_data_callback :: proc "cdecl" (pDevice: ^ma.device, pFramesOut, pFramesIn: rawptr, frameCount: u32)
{
    context = runtime.default_context()
    when USE_TRACKING_ALLOCATOR
    {
        context.allocator = track_allocator
    }
    pEngine := (^ma.engine)(pDevice.pUserData)

    // pFramesIn

    ma.engine_read_pcm_frames(pEngine, pFramesOut, u64(frameCount), nil)

    if (ma.sound_at_end(&app.sound))
    {
        handle_end_of_music(&app)
        win32.InvalidateRect(app.win_handle, nil, win32.TRUE)
    }
}

reset_queue :: proc(app: ^App)
{
    for i: u32 = 0; i < app.queue_max_count; i += 1
    {
        // music: ^Music_File = &app->queue[i]
        // music.active = false
        // music.next = nil
    }
    app.queue_first = nil
}

add_music_to_queue :: proc(app: ^App, filename: string)
{
    /*
    if !is_file_valid(filename) ||
       !is_file_music(filename)
    {
        return
    }

    Music_File *empty_music = NULL
    for (u32 i = 0; i < app->queue_max_count; i++)
    {
        Music_File *music = app->queue + i
        if (music->active)
        {
            continue
        }
        else
        {
            empty_music = music
            break
        }
    }
    if (empty_music)
    {
        assert(app->main_arena.temp_count == 0)

        empty_music->active = true
        empty_music->filename.length = wcslen(filename) + 1
        empty_music->filename.data = cast(wchar *) push_size(&app->main_arena, sizeof(wchar) * empty_music->filename.length)
        strcpy_len(empty_music->filename.data, empty_music->filename.length, filename)

        empty_music->info = get_id3_frames(app, filename)
        if (empty_music->info.title.length == 0)
        {
            String name = get_filename(empty_music->filename)
            empty_music->info.title = name
            // empty_music->title.data = cast(wchar *) push_size(&app->main_arena, sizeof(wchar) * empty_music->title.length)
            // strcpy_len(empty_music->title.data, empty_music->title.length, name.data)
        }

        empty_music->next = NULL

        if (app->queue_first)
        {
            Music_File *last = app->queue_first
            for (Music_File *cursor = app->queue_first; cursor; cursor = cursor->next)
            {
                last = cursor
            }
            if (last)
            {
                last->next = empty_music
            }
            else
            {
                assert(!"no!!!")
            }

            ma_resource_manager_data_source data_source
            ma_resource_manager_data_source_config resourceManagerDataSourceConfig = ma_resource_manager_data_source_config_init()
            resourceManagerDataSourceConfig.pFilePathW = filename

            ma_result result = ma_resource_manager_data_source_init_ex(app->engine.pResourceManager, &resourceManagerDataSourceConfig, &data_source)
            if (result == MA_SUCCESS) {
                ma_data_source_get_length_in_seconds(&data_source, &empty_music->length)
            }
            ma_resource_manager_data_source_uninit(&data_source)
        }
        else
        {
            */
            // app->queue_first = empty_music
            play_music(app, filename)
            // ma.sound_get_length_in_seconds(&app.sound, &empty_music.length)
            // app.length = empty_music.length
            /*
        }
    }
    else
    {
        assert(!"no!!!")
    }
    */
}

play_music :: proc(app: ^App, path: string)
{
    fmt.println(path)

    // if is_file_valid(path)
    // {
        if (ma.device_get_state(app.engine.pDevice) == ma.device_state.stopped)
        {
            ma.device_start(app.engine.pDevice)
        }
        if app.sound.pDataSource != nil
        {
            ma.sound_uninit(&app.sound)
        }
        result := ma.sound_init_from_file_w(&app.engine, win32.utf8_to_wstring(path), u32(ma.sound_flags.STREAM | ma.sound_flags.NO_SPATIALIZATION), nil, nil, &app.sound)
        if (result == ma.result.SUCCESS)
        {
            ma.sound_set_pitch(&app.sound, app.speed)
            ma.sound_start(&app.sound)
            // start_refresh_timer()
            win32.SetTimer(app.win_handle, REFRESH_TIMER, 200, nil)
            app.paused = false

            // @todo: implement this for better seamless transition
            // ma.data_source_set_next(app.sound.pDataSource, test.pDataSource)
        }
        // else
        // {
        //     print_error("sound init failed\n")
        // }
    // }
    // else
    // {
    //     print_error("can't find file\n")
    // }
}

toggle_pause_music :: proc(app: ^App)
{
    if ma.device_get_state(app.engine.pDevice) == ma.device_state.stopped
    {
        ma.device_start(app.engine.pDevice)
    }
    // if (app.queue_first)
    // {
        if (ma.sound_at_end(&app.sound))
        {
            ma.sound_seek_to_pcm_frame(&app.sound, 0)
            ma.sound_start(&app.sound)
            app.paused = false
        }
        else
        {
            if (app.paused)
            {
                ma.sound_start(&app.sound)
                app.paused = false
            }
            else
            {
                ma.sound_stop(&app.sound)
                app.paused = true
            }
        }
    // }
}

handle_end_of_music :: proc(app: ^App)
{
    if (app.loop == .SINGLE)
    {
        ma.sound_start(&app.sound)
    }
    else
    {
        // jump_queue(app, app.playing_index + 1)
        // end of queue
        if (ma.sound_at_end(&app.sound))
        {
            // jump_queue(app, 0)
            if (app.loop == .PLAYLIST)
            {
            }
            else
            {
                ma.sound_stop(&app.sound)
                app.paused = true
            }
        }
        // refresh_draw()
    }
}

change_speed :: proc(app: ^App, amount: int)
{
    for speed, index in speed_steps
    {
        if app.speed == speed
        {
            index_ := max(min(index + amount, len(speed_steps) - 1), 0)
            app.speed = speed_steps[index_]
            fmt.println(index_, " ", speed_steps[index_])
            break
        }
    }

    if app.sound.pDataSource != nil
    {
        ma.sound_set_pitch(&app.sound, app.speed)
    }
}
