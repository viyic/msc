package msc

import "core:fmt"
import "core:runtime"
import "core:os"
import "core:strings"
import "core:path/filepath"
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
    // for i: u32 = 0; i < app.queue_max_count; i += 1
    // {
        // music: ^Music_File = &app->queue[i]
        // music.active = false
        // music.next = nil
    // }
    // app.queue_first = nil
}

add_music_to_queue :: proc(app: ^App, music_info: Music_Info)
{
    append(&app.music_infos, music_info)
    append(&app.queue, len(app.music_infos) - 1)
    /*
            ma_resource_manager_data_source data_source
            ma_resource_manager_data_source_config resourceManagerDataSourceConfig = ma_resource_manager_data_source_config_init()
            resourceManagerDataSourceConfig.pFilePathW = file_name

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
        if ma.sound_at_end(&app.sound) // @analyze: not needed?
        {
            ma.sound_seek_to_pcm_frame(&app.sound, 0)
            ma.sound_start(&app.sound)
            app.paused = false
        }
        else
        {
            if app.sound.pDataSource == nil
            {
                if len(app.queue) > 0 do jump_queue(app, 0)
            }
            else
            {
                if app.paused
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
        }
    // }
}

handle_end_of_music :: proc(app: ^App)
{
    if app.loop == .SINGLE
    {
        ma.sound_start(&app.sound)
        // win32.SetWindowTextW(app.win_handle, cursor.name)
    }
    else
    {
        // end of queue
        if app.playing_index < len(app.queue) - 1
        {
            jump_queue(app, app.playing_index + 1)
        }
        else
        {
            if app.loop == .PLAYLIST
            {
                jump_queue(app, 0)
            }
            else
            {
                jump_queue(app, -1)
                ma.sound_stop(&app.sound)
                app.paused = true
                win32.SetWindowTextW(app.win_handle, win32.L("msc"))
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
            // fmt.println(index_, " ", speed_steps[index_])
            break
        }
    }

    if app.sound.pDataSource != nil
    {
        ma.sound_set_pitch(&app.sound, app.speed)
    }
}

parse_mp3 :: proc(file_name: string) -> Music_Info
{
    result := Music_Info{
        full_path = file_name
    }

    handle, err := os.open(file_name)
    if err != os.ERROR_NONE do return result
    defer os.close(handle)

    id3_header := [10]u8{}
    os.read(handle, id3_header[:])
    if string(id3_header[:3]) != "ID3"
    {
        return result
    }

    major_version := u16(id3_header[3])
    minor_version := u16(id3_header[4])
    flags := u16(id3_header[5])
    size := u64(id3_header[9]) |
        u64(id3_header[8]) << (7 * 1) |
        u64(id3_header[7]) << (7 * 2) |
        u64(id3_header[6]) << (7 * 3)

    if flags != 0
    {
        fmt.println("[parse_mp3] non-zero flag detected, unimplemented:", result.full_path)
    }

    // fmt.printf("flags: %b\nsize: %v\n", flags, size)

    id3_frames := make([]u8, size)
    defer delete(id3_frames)
    os.read(handle, id3_frames)

    // fmt.println(string(id3_frames[:]))
    FRAME_HEADER_SIZE :: 10

    cursor: u64 = 0 // id3_frames
    for cursor + FRAME_HEADER_SIZE <= size
    {
        frame := id3_frames[cursor:]

        frame_header := frame[:FRAME_HEADER_SIZE]
        frame_id := string(frame_header[:4])
        frame_size := u64(frame_header[7]) |
            u64(frame_header[6]) << (8 * 1) |
            u64(frame_header[5]) << (8 * 2) |
            u64(frame_header[4]) << (8 * 3)
        // @todo: flags
        cursor += FRAME_HEADER_SIZE

        // fmt.println(cursor, frame_id, frame_size)

        if cursor + frame_size > size
        {
            break
        }

        frame_body := frame[FRAME_HEADER_SIZE:][:frame_size]

        if frame_id == "TIT2"
        {
            // @ntoe: + 1 for ^C, - 2 for ^C and null terminator
            title := string(frame_body)
            title = strings.to_valid_utf8(title, "", context.temp_allocator)
            title, _ = strings.remove_all(title, "\x00", context.temp_allocator)
            result.title = strings.clone(title)
            // fmt.println(result.title)
        }
        else if frame_id == "TALB"
        {
            album := string(frame_body)
            album = strings.to_valid_utf8(album, "", context.temp_allocator)
            album, _ = strings.remove_all(album, "\x00", context.temp_allocator)
            result.album = strings.clone(album)
            // fmt.println(result.album)
        }
        else if frame_id == "TDOR"
        {
            time := string(frame_body)
            time = strings.to_valid_utf8(time, "", context.temp_allocator)
            time, _ = strings.remove_all(time, "\x00", context.temp_allocator)
            result.release_time = strings.clone(time)
            // fmt.println(result.release_time)
        }
        else if result.artist == "" &&
            (frame_id == "TCOM" ||
             frame_id == "TPE2" ||
             frame_id == "TPE1")
        {
            artist := string(frame_body)
            artist = strings.to_valid_utf8(artist, "", context.temp_allocator)
            artist, _ = strings.remove_all(artist, "\x00", context.temp_allocator)
            result.artist = strings.clone(artist)
            // fmt.println(result.artist)
        }
        else if frame_id == "APIC"
        {
        }
        else
        {
        }

        cursor += u64(len(frame_body))
    }

    return result
}

parse_flac :: proc(file_name: string) -> Music_Info
{
    result := Music_Info{
        full_path = file_name
    }

    handle, err := os.open(file_name)
    if err != os.ERROR_NONE do return result
    defer os.close(handle)

    flac_header := [8]u8{}
    os.read(handle, flac_header[:])
    if string(flac_header[:4]) != "fLaC"
    {
        return result
    }

    /*
    major_version := u16(flac_header[4])
    minor_version := u16(flac_header[5])
    flags : u16 = flac_header[6];
    size := u64(0) |
        flac_header[6] << (7 * 3) |
        flac_header[7] << (7 * 2) |
        flac_header[8] << (7 * 1) |
        flac_header[9]

    char *flac_frames = cast(char *) push_size(&app->temp_arena, size);
    fread(flac_frames, size, sizeof(char), file);

    char *cursor = flac_frames;
    while (cast(u64) (cursor - flac_frames) < size)
    {
        if (strncmp(cursor, "TIT2", 4) == 0)
        {
            cursor += 4;
            u64 frame_size = cast(u64) 0 |
                cursor[0] << (8 * 3) |
                cursor[1] << (8 * 2) |
                cursor[2] << (8 * 1) |
                cursor[3];
            cursor += 6; // skip flags
            cursor += 1; // after header there's a null that's also counted by the size fsr
            frame_size -= 1;

            char *temp = cast(char *) push_size(&app->temp_arena, sizeof(char) * frame_size);
            strcpy_len(temp, frame_size, cursor);
            result.title.data = cast(wchar *) push_size(&app->main_arena, sizeof(wchar) * frame_size);
            char_to_wchar(result.title.data, temp, frame_size);
            result.title.length = frame_size;
            cursor += frame_size;
        }
        else if (strncmp(cursor, "TALB", 4) == 0)
        {
            cursor += 4;
            u64 frame_size = cast(u64) 0 |
                cursor[0] << (8 * 3) |
                cursor[1] << (8 * 2) |
                cursor[2] << (8 * 1) |
                cursor[3];
            cursor += 6; // skip flags
            cursor += 1; // after header there's a null that's also counted by the size fsr
            frame_size -= 1;

            char *temp = cast(char *) push_size(&app->temp_arena, sizeof(char) * frame_size);
            strcpy_len(temp, frame_size, cursor);
            result.album.data = cast(wchar *) push_size(&app->main_arena, sizeof(wchar) * frame_size);
            char_to_wchar(result.album.data, temp, frame_size);
            result.album.length = frame_size;
            cursor += frame_size;
        }
        else if (result.artist.length == 0 &&
                 (strncmp(cursor, "TCOM", 4) == 0 ||
                  strncmp(cursor, "TPE2", 4) == 0 ||
                  strncmp(cursor, "TPE1", 4) == 0))
        {
            cursor += 4;
            u64 frame_size = cast(u64) 0 |
                cursor[0] << (8 * 3) |
                cursor[1] << (8 * 2) |
                cursor[2] << (8 * 1) |
                cursor[3];
            cursor += 6; // skip flags
            cursor += 1; // after header there's a null that's also counted by the size fsr
            frame_size -= 1;

            char *temp = cast(char *) push_size(&app->temp_arena, sizeof(char) * frame_size);
            strcpy_len(temp, frame_size, cursor);
            result.artist.data = cast(wchar *) push_size(&app->main_arena, sizeof(wchar) * frame_size);
            char_to_wchar(result.artist.data, temp, frame_size);
            result.artist.length = frame_size;
            cursor += frame_size;
        }
        else
        {
            cursor += 4;
            u64 frame_size = cast(u64) 0 |
                cursor[0] << (8 * 3) |
                cursor[1] << (8 * 2) |
                cursor[2] << (8 * 1) |
                cursor[3];
            cursor += 6;
            // cursor += 1;
            cursor += frame_size;
        }
    }
    */
    return result;
}

jump_queue :: proc(app: ^App, queue_index: int)
{
    app.playing_index = queue_index
    if app.playing_index == -1 do return // allow -1

    music_info := get_music_info_from_queue(app, queue_index)
    play_music(app, music_info.full_path)

    title := ""
    if music_info.artist != "" && music_info.title != ""
    {
        title = fmt.tprint(music_info.artist, "-", music_info.title, "- msc")
    }
    else
    {
        title = fmt.tprint(filepath.base(music_info.full_path), "- msc")
    }
    fmt.println(title)
    title_ := win32.utf8_to_wstring(title, context.allocator)
    defer free(title_)
    win32.SetWindowTextW(app.win_handle, title_)
}

get_music_info_from_queue :: #force_inline proc(app: ^App, queue_index: int) -> Music_Info
{
    assert(0 <= queue_index && queue_index < len(app.queue))
    music_info_index := app.queue[queue_index]
    assert(0 <= music_info_index && music_info_index < len(app.music_infos))
    return app.music_infos[music_info_index]
}

get_music_info_from_path :: proc(path: string) -> (Music_Info, bool)
{
    music_info := Music_Info{}
    ok := true
    ext := filepath.ext(path)
    switch ext
    {
        case ".mp3":
            music_info = parse_mp3(path)
        case ".flac":
            music_info = parse_flac(path)
        case ".wav":
        case ".ogg":
        case:
            ok = false
    }

    return music_info, ok
}
