package msc

import "core:strings"

between :: proc(a: $T, x: T, b: T) -> b32 {
	return a < x && x < b
}

between_equal :: proc(a: $T, x: T, b: T) -> b32 {
	return a <= x && x <= b
}

between_equal_left :: proc(a: $T, x: T, b: T) -> b32 {
	return a <= x && x < b
}

between_equal_right :: proc(a: $T, x: T, b: T) -> b32 {
	return a < x && x <= b
}

point_in_rect :: #force_inline proc(px, py: int, rect: Rect) -> b32 {
	return(
		between_equal_left(rect.x, px, rect.x + rect.w) &&
		between_equal_left(rect.y, py, rect.y + rect.h) \
	)
}

x1 :: #force_inline proc(rect: Rect) -> int {
	return rect.x + rect.w
}

y1 :: #force_inline proc(rect: Rect) -> int {
	return rect.y + rect.h
}

u16_bytes_to_u16 :: proc(bytes: []u8, allocator := context.temp_allocator) -> ([]u16, bool) {
	if len(bytes) % 2 != 0 do return {}, false

	result := make([]u16, len(bytes) / 2, allocator)
	for index := 0; index < len(result); index += 1 {
		result[index] = u16(bytes[index * 2]) | u16(bytes[index * 2 + 1]) << 8
	}

	return result, true
}

u16_bytes_to_u8 :: proc(bytes: []u8, allocator := context.temp_allocator) -> (string, bool) {
	if len(bytes) % 2 != 0 do return {}, false

	result := make([]u8, len(bytes) / 2, allocator)

	return {}, true
}
