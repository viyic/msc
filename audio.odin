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

    if ma.sound_at_end(&app.sound)
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
        if sound_exists(app)
        {
            ma.sound_uninit(&app.sound)
        }
        result := ma.sound_init_from_file_w(&app.engine, win32.utf8_to_wstring(path), u32(ma.sound_flags.STREAM | ma.sound_flags.NO_SPATIALIZATION), nil, nil, &app.sound)
        if result == ma.result.SUCCESS
        {
            ma.sound_set_pitch(&app.sound, app.speed)
            ma.sound_start(&app.sound)
            // start_refresh_timer()
            win32.SetTimer(app.win_handle, REFRESH_TIMER, 100, nil)
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

    if !sound_exists(app)
    {
        if app.loop == .DELAY && app.playing_index > -1
        {
            app.paused = !app.paused
        }
        else
        {
            if len(app.queue) > 0 do jump_queue(app, 0)
        }
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

    win32.SetTimer(app.win_handle, REFRESH_TIMER, 100, nil)
}

handle_end_of_music :: proc(app: ^App)
{
    if app.loop == .SINGLE
    {
        ma.sound_start(&app.sound)
    }
    else if app.loop == .DELAY
    {
        ma.sound_stop(&app.sound)
        ma.sound_uninit(&app.sound)
        win32.SetTimer(app.win_handle, DELAY_TIMER, u32(app.delay_time * 1000), nil)
        fmt.println("DELAY_TIMER start")
    }
    else
    {
        if -1 < app.playing_index && app.playing_index < len(app.queue) - 1
        {
            jump_queue(app, app.playing_index + 1)
        }
        else // end of playlist
        {
            if app.loop == .PLAYLIST
            {
                jump_queue(app, 0)
            }
            else
            {
                jump_queue(app, -1)
                ma.sound_stop(&app.sound)
                ma.sound_uninit(&app.sound)
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

    if sound_exists(app)
    {
        ma.sound_set_pitch(&app.sound, app.speed)
    }
}

sound_exists :: #force_inline proc(app: ^App) -> bool
{
    return app.sound.pDataSource != nil
}

parse_mp3 :: proc(file_name: string) -> Music_Info
{
    result := Music_Info{
        full_path = strings.clone(file_name)
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

        if cursor + frame_size > size
        {
            break
        }

        frame_body := frame[FRAME_HEADER_SIZE:][:frame_size]

        if frame_id == "TIT2"
        {
            title := parse_text(frame_body)
            result.title = strings.clone(title)
        }
        else if frame_id == "TALB"
        {
            album := parse_text(frame_body)
            result.album = strings.clone(album)
        }
        else if frame_id == "TDOR"
        {
            time := parse_text(frame_body)
            result.release_time = strings.clone(time)
        }
        else if result.artist == "" &&
            (frame_id == "TCOM" ||
             frame_id == "TPE2" ||
             frame_id == "TPE1")
        {
            artist := parse_text(frame_body)
            result.artist = strings.clone(artist)
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

    parse_text :: proc(frame_body: []u8) -> string
    {
        result := ""

        // source: https://stackoverflow.com/a/13373943
        encoding := frame_body[0]
        if encoding == '\x00' // ASCII
        {
            result = string(frame_body[1:])
        }
        else if encoding == '\x01' // UTF-16 w/ BOM
        {
            is_little_endian :=
                frame_body[1] == 0xff && // FF
                frame_body[2] == 0xfe // FE
            if is_little_endian
            {
                str, ok := u8_to_u16(frame_body[3:])
                if ok do result, _ = win32.utf16_to_utf8(str)
                else do fmt.println("[parse_mp3] unicode bytes not divisible by 2:", frame_body)
            }
            else
            {
                fmt.println("[parse_mp3] big endian detected:", frame_body)
            }
        }
        else if encoding == '\x02' // UTF-16 Big Endian w/o BOM
        {
            fmt.println("[parse_mp3] big endian detected:", frame_body)
        }
        else if encoding == '\x03' // UTF-8 w/ Null Terminator? @analyze
        {
            result = string(frame_body[1:])
            result = strings.to_valid_utf8(result, "", context.temp_allocator)
        }
        result, _ = strings.remove_all(result, "\x00", context.temp_allocator)

        return result
    }
}

parse_flac :: proc(file_name: string) -> Music_Info
{
    result := Music_Info{
        full_path = strings.clone(file_name)
    }

    handle, err := os.open(file_name)
    if err != os.ERROR_NONE do return result
    defer os.close(handle)

    flac_header := [4]u8{}
    os.read(handle, flac_header[:])
    if string(flac_header[:]) != "fLaC"
    {
        return result
    }

    run := true
    metadata_header := [4]u8{}
    for run
    {
        defer if metadata_header[0] & 0b1000_0000 != 0 do run = false
        os.read(handle, metadata_header[:])
        metadata_length := u64(metadata_header[3]) |
                           u64(metadata_header[2]) << 8 |
                           u64(metadata_header[1]) << 16
        fmt.println(metadata_length)
        if metadata_header[0] & 0b0111_1111 != 4
        {
            os.seek(handle, i64(metadata_length), os.SEEK_CUR)
            continue
        }
        metadata_comment := make([]u8, metadata_length)
        defer delete(metadata_comment)
        os.read(handle, metadata_comment)
        fmt.println(args = { '"', string(metadata_comment), '"' }, sep = "")

        cursor: u64 = 0
        metadata_comment_count := 0
        // reference
        {
            tag := metadata_comment[cursor:]
            tag_length := u64(tag[0]) |
                          u64(tag[1]) << 8 |
                          u64(tag[2]) << 16 |
                          u64(tag[3]) << 24
            tag_content := tag[4:][:tag_length]

            cursor += 4 + tag_length
        }
        // comment count
        {
            tag := metadata_comment[cursor:]
            tag_length := u64(tag[0]) |
                          u64(tag[1]) << 8 |
                          u64(tag[2]) << 16 |
                          u64(tag[3]) << 24
            metadata_comment_count = int(tag_length)

            cursor += 4
        }
        for cursor < metadata_length
        {
            tag := metadata_comment[cursor:]
            tag_length := u64(tag[0]) |
                          u64(tag[1]) << 8 |
                          u64(tag[2]) << 16 |
                          u64(tag[3]) << 24
            tag_content := tag[4:][:tag_length]
            if string(tag_content[:6]) == "TITLE="
            {
                result.title = strings.clone(string(tag_content[6:]))
            }
            else if string(tag_content[:6]) == "ALBUM="
            {
                result.album = strings.clone(string(tag_content[6:]))
            }
            else if result.artist == "" && string(tag_content[:7]) == "ARTIST="
            {
                result.artist = strings.clone(string(tag_content[7:]))
            }
            else if result.artist == "" && string(tag_content[:12]) == "ALBUMARTIST="
            {
                result.artist = strings.clone(string(tag_content[12:]))
            }
            else if string(tag_content[:5]) == "DATE="
            {
                result.release_time = strings.clone(string(tag_content[5:]))
            }

            cursor += 4 + tag_length
        }

        break
    }

    return result
}

jump_queue :: proc(app: ^App, queue_index: int, caller := #caller_location)
{
    fmt.println(caller)
    win32.KillTimer(app.win_handle, DELAY_TIMER)
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
        title = fmt.tprint(filepath.stem(music_info.full_path), "- msc")
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
