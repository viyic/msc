package msc

import "core:fmt"
import "core:runtime"
import "core:os"
import "core:strings"
import "core:path/filepath"
import win32 "core:sys/windows"
import ma "vendor:miniaudio"

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

        if platform_miniaudio_sound_init(app, path)
        {
            ma.sound_set_pitch(&app.sound, app.speed)
            ma.sound_start(&app.sound)
            platform_timer_start(app, Timer.REFRESH, 100)
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

    platform_timer_start(app, .REFRESH, 100)
}

handle_end_of_music :: proc(app: ^App)
{
    if app.loop == .SINGLE
    {
        ma.sound_start(&app.sound)
    }
    else if app.loop == .DELAY
    {
        // ma.sound_stop(&app.sound)
        ma.sound_uninit(&app.sound)
        platform_timer_start(app, .DELAY, u32(app.delay_time * 1000))
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
                // ma.sound_stop(&app.sound)
                ma.sound_uninit(&app.sound)
                app.paused = true
                platform_window_set_text(app, "msc")
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
            result.title = parse_text(frame_body)
        }
        else if frame_id == "TALB"
        {
            result.album = parse_text(frame_body)
        }
        else if frame_id == "TDOR"
        {
            result.release_time = parse_text(frame_body)
        }
        else if result.artist == "" &&
            (frame_id == "TCOM" ||
             frame_id == "TPE2" ||
             frame_id == "TPE1")
        {
            result.artist = parse_text(frame_body)
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

    parse_text :: proc(frame_body: []u8, allocator := context.allocator) -> string
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
                str, ok := u16_bytes_to_u16(frame_body[3:])
                if ok do result, _ = win32.utf16_to_utf8(str) // @todo: remove this so no more win32
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

        was_allocation: bool
        result, was_allocation = strings.remove_all(result, "\x00", allocator)
        if !was_allocation
        {
            result = strings.clone(result)
        }

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
            tag_content := string(tag[4:][:tag_length])
            tag_content_len := len(tag_content)
            if tag_content_len > 5 && tag_content[:5] == "DATE="
            {
                result.release_time = strings.clone(tag_content[5:])
            }
            else if tag_content_len > 6 && tag_content[:6] == "TITLE="
            {
                result.title = strings.clone(tag_content[6:])
            }
            else if tag_content_len > 6 && tag_content[:6] == "ALBUM="
            {
                result.album = strings.clone(tag_content[6:])
            }
            else if result.artist == ""
            {
                if tag_content_len > 7 && tag_content[:7] == "ARTIST="
                {
                    result.artist = strings.clone(tag_content[7:])
                }
                else if tag_content_len > 12 && tag_content[:12] == "ALBUMARTIST="
                {
                    result.artist = strings.clone(tag_content[12:])
                }
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
    platform_timer_stop(app, .DELAY)
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
    // fmt.println(title)
    platform_window_set_text(app, title)
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
            fmt.eprintln("unimplemented file extension:", ext)
            ok = false
        case ".ogg":
            fmt.eprintln("unimplemented file extension:", ext)
            ok = false
        case:
            fmt.eprintln("unsupported file extension:", ext)
            ok = false
    }

    return music_info, ok
}

read_music_dir :: proc(app: ^App)
{
    err: os.Errno

    music_dir := app.current_path
    data_path := strings.concatenate([]string{filepath.dir(app.executable_path, context.temp_allocator), "\\msc.data"}, context.temp_allocator)

    data_handle: os.Handle
    data_handle, err = os.open(data_path, os.O_CREATE)
    if err != os.ERROR_NONE
    {
        fmt.eprintln("can't write msc data to:", data_path)
        return
    }
    defer os.close(data_handle)

    data := [dynamic]string{}

    // @note: we'll only check 2 folders deep
    folders_to_read: [dynamic]string
    folders_to_read_index := 0
    append(&folders_to_read, strings.clone(music_dir))

    music_infos: [dynamic]Music_Info
    for folders_to_read_index < len(folders_to_read)
    {
        folder_path := folders_to_read[folders_to_read_index]
        folders_to_read_index += 1
        fmt.println("reading:", folder_path)
        file_list_handle: os.Handle
        file_list_handle, err = os.open(folder_path)
        if err != os.ERROR_NONE
        {
            fmt.eprintln("can't open folder:", folder_path)
            continue
        }
        defer os.close(file_list_handle)
        file_list: []os.File_Info
        file_list, err = os.read_dir(file_list_handle, 0)
        if err != os.ERROR_NONE
        {
            fmt.eprintln("can't read folder:", folder_path)
            continue
        }
        defer os.file_info_slice_delete(file_list)

        for file in file_list
        {
            if file.is_dir
            {
                append(&folders_to_read, strings.clone(file.fullpath))
            }
            else
            {
                if !is_supported_audio_file(filepath.ext(file.fullpath)) do continue
                music_info, ok := get_music_info_from_path(file.fullpath)
                if !ok do continue
                defer music_info_delete(music_info)

                fmt.fprintln(data_handle, music_info.full_path, "|", music_info.artist, "|", music_info.album, "|", music_info.title, "|", music_info.release_time)
                // append(&music_infos, music_info)
            }
        }
    }

    for folder in folders_to_read do delete(folder)
}

music_info_delete :: proc(music_info: Music_Info)
{
    if music_info.full_path    != "" do delete(music_info.full_path)
    if music_info.artist       != "" do delete(music_info.artist)
    if music_info.title        != "" do delete(music_info.title)
    if music_info.album        != "" do delete(music_info.album)
    if music_info.release_time != "" do delete(music_info.release_time)
}

is_supported_audio_file :: proc(ext: string) -> bool
{
     return ext == ".mp3" ||
            ext == ".flac" ||
            ext == ".wav" ||
            ext == ".ogg"
}
