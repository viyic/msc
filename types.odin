package msc

import win32 "core:sys/windows"
import ma "vendor:miniaudio"
import "core:runtime"
import "core:os"

App :: struct
{
    win_handle: win32.HWND
    mouse_down: b32

    speed: f32

    engine: ma.engine
    sound: ma.sound

    paused: b32
    volume: f32
    cursor: f32
    length: f32
    loop: Loop_State

    left: Panel
    right: Panel
    bottom: Panel

    current_path: string
    file_list: []os.File_Info

    queue: [dynamic]Music_File
    queue_max_count: u32
    playing_index: u32
    queue_first: ^Music_File

    last_click_cx, last_click_cy: int
    last_click_time: u64

    last_cursor: Cursor
}

Ui_Context :: struct
{
    cx, cy: int
    width, height: int
    scroll: f32
    msg: Ui_Message

    redraw: b32
    redraw_rect: win32.RECT
    next_cursor: Cursor

    hold: runtime.Source_Code_Location // @analyze: add z and compare the z?

    hdc: win32.HDC
    win_handle: win32.HWND
}

Ui_Message :: enum
{
    NONE
    PAINT
    MOUSE_MOVE
    MOUSE_LEFT_PRESSED
    MOUSE_LEFT_RELEASED
    MOUSE_DOUBLE_CLICK
    MOUSE_WHEEL
}

Theme :: struct
{
    background: [3]f32
    text: [3]f32
    button: struct {
        normal: [3]f32
        hover: [3]f32
        click: [3]f32
    }
}

Cursor :: enum
{
    NONE
    ARROW
    HAND
}

USE_TRACKING_ALLOCATOR :: false

REFRESH_TIMER :: 1
TRACK_TIMER :: 2

Loop_State :: enum
{
    NONE,
    SINGLE,
    PLAYLIST,
}

Rect :: struct
{
    x, y, w, h: int
}

Panel :: struct
{
    using rect: Rect
    scroll: f32
}

Music_File :: struct
{

}
