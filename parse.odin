package msc

import "core:fmt"
import "core:os"
import "core:strings"
import win32 "core:sys/windows"

parse_mp3 :: proc(file_name: string) -> Music_Info {
	result := Music_Info {
		full_path = strings.clone(file_name),
	}

	handle, err := os.open(file_name)
	if err != os.ERROR_NONE do return result
	defer os.close(handle)

	id3_header := [10]u8{}
	os.read(handle, id3_header[:])
	if string(id3_header[:3]) != "ID3" {
		return result
	}

	major_version := u16(id3_header[3])
	minor_version := u16(id3_header[4])
	flags := u16(id3_header[5])
	size :=
		u64(id3_header[9]) |
		u64(id3_header[8]) << (7 * 1) |
		u64(id3_header[7]) << (7 * 2) |
		u64(id3_header[6]) << (7 * 3)

	if flags != 0 {
		fmt.println("[parse_mp3] non-zero flag detected, unimplemented:", result.full_path)
	}

	// fmt.printf("flags: %b\nsize: %v\n", flags, size)

	id3_frames := make([]u8, size)
	defer delete(id3_frames)
	os.read(handle, id3_frames)

	FRAME_HEADER_SIZE :: 10

	cursor: u64 = 0 // id3_frames
	for cursor + FRAME_HEADER_SIZE <= size {
		frame := id3_frames[cursor:]

		frame_header := frame[:FRAME_HEADER_SIZE]
		frame_id := string(frame_header[:4])
		frame_size :=
			u64(frame_header[7]) |
			u64(frame_header[6]) << (8 * 1) |
			u64(frame_header[5]) << (8 * 2) |
			u64(frame_header[4]) << (8 * 3)
		// @todo: flags
		cursor += FRAME_HEADER_SIZE

		if cursor + frame_size > size {
			break
		}

		frame_body := frame[FRAME_HEADER_SIZE:][:frame_size]

		if frame_id == "TIT2" {
			result.title = parse_text(frame_body)
		} else if frame_id == "TALB" {
			result.album = parse_text(frame_body)
		} else if frame_id == "TDOR" {
			result.release_time = parse_text(frame_body)
		} else if result.artist == "" &&
		   (frame_id == "TCOM" || frame_id == "TPE2" || frame_id == "TPE1") {
			result.artist = parse_text(frame_body)
		} else if frame_id == "APIC" {
		} else {
		}

		cursor += u64(len(frame_body))
	}

	return result

	parse_text :: proc(frame_body: []u8, allocator := context.allocator) -> string {
		result := ""

		// source: https://stackoverflow.com/a/13373943
		encoding := frame_body[0]
		if encoding == '\x00' // ASCII
		{
			result = string(frame_body[1:])
		} else if encoding == '\x01' // UTF-16 w/ BOM
		{
			is_little_endian := frame_body[1] == 0xff && frame_body[2] == 0xfe // FF// FE
			if is_little_endian {
				str, ok := u16_bytes_to_u16(frame_body[3:])
				// @todo: remove this so no more win32
				if ok do result, _ = win32.utf16_to_utf8(str)
				else do fmt.println("[parse_mp3] unicode bytes not divisible by 2:", frame_body)
			} else {
				fmt.println("[parse_mp3] big endian detected:", frame_body)
			}
		} else if encoding == '\x02' // UTF-16 Big Endian w/o BOM
		{
			fmt.println("[parse_mp3] big endian detected:", frame_body)
		} else if encoding == '\x03' // UTF-8 w/ Null Terminator? @analyze
		{
			result = string(frame_body[1:])
			result = strings.to_valid_utf8(result, "", context.temp_allocator)
		}

		was_allocation: bool
		result, was_allocation = strings.remove_all(result, "\x00", allocator)
		if !was_allocation {
			result = strings.clone(result)
		}

		return result
	}
}

parse_flac :: proc(file_name: string) -> Music_Info {
	result := Music_Info {
		full_path = strings.clone(file_name),
	}

	handle, err := os.open(file_name)
	if err != os.ERROR_NONE do return result
	defer os.close(handle)

	flac_header := [4]u8{}
	os.read(handle, flac_header[:])
	if string(flac_header[:]) != "fLaC" {
		return result
	}

	run := true
	metadata_header := [4]u8{}
	for run {
		defer if metadata_header[0] & 0b1000_0000 != 0 do run = false
		os.read(handle, metadata_header[:])
		metadata_length :=
			u64(metadata_header[3]) | u64(metadata_header[2]) << 8 | u64(metadata_header[1]) << 16
		fmt.println(metadata_length)
		if metadata_header[0] & 0b0111_1111 != 4 {
			os.seek(handle, i64(metadata_length), os.SEEK_CUR)
			continue
		}
		metadata_comment := make([]u8, metadata_length)
		defer delete(metadata_comment)
		os.read(handle, metadata_comment)
		fmt.println(args = {'"', string(metadata_comment), '"'}, sep = "")

		cursor: u64 = 0
		metadata_comment_count := 0
		// reference
		{
			tag := metadata_comment[cursor:]
			tag_length := u64(tag[0]) | u64(tag[1]) << 8 | u64(tag[2]) << 16 | u64(tag[3]) << 24
			tag_content := tag[4:][:tag_length]

			cursor += 4 + tag_length
		}
		// comment count
		{
			tag := metadata_comment[cursor:]
			tag_length := u64(tag[0]) | u64(tag[1]) << 8 | u64(tag[2]) << 16 | u64(tag[3]) << 24
			metadata_comment_count = int(tag_length)

			cursor += 4
		}
		for cursor < metadata_length {
			tag := metadata_comment[cursor:]
			tag_length := u64(tag[0]) | u64(tag[1]) << 8 | u64(tag[2]) << 16 | u64(tag[3]) << 24
			tag_content := string(tag[4:][:tag_length])
			tag_content_len := len(tag_content)
			if tag_content_len > 5 && tag_content[:5] == "DATE=" {
				result.release_time = strings.clone(tag_content[5:])
			} else if tag_content_len > 6 && tag_content[:6] == "TITLE=" {
				result.title = strings.clone(tag_content[6:])
			} else if tag_content_len > 6 && tag_content[:6] == "ALBUM=" {
				result.album = strings.clone(tag_content[6:])
			} else if result.artist == "" {
				if tag_content_len > 7 && tag_content[:7] == "ARTIST=" {
					result.artist = strings.clone(tag_content[7:])
				} else if tag_content_len > 12 && tag_content[:12] == "ALBUMARTIST=" {
					result.artist = strings.clone(tag_content[12:])
				}
			}

			cursor += 4 + tag_length
		}

		break
	}

	return result
}
