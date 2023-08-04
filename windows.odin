package msc

import win32 "core:sys/windows"
foreign import gdi32 "system:Gdi32.lib"
foreign import uxtheme "system:UxTheme.lib"

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

// Character Sets
ANSI_CHARSET        :: 0
DEFAULT_CHARSET     :: 1
SYMBOL_CHARSET      :: 2
SHIFTJIS_CHARSET    :: 128
HANGEUL_CHARSET     :: 129
HANGUL_CHARSET      :: 129
GB2312_CHARSET      :: 134
CHINESEBIG5_CHARSET :: 136
OEM_CHARSET         :: 255
JOHAB_CHARSET       :: 130
HEBREW_CHARSET      :: 177
ARABIC_CHARSET      :: 178
GREEK_CHARSET       :: 161
TURKISH_CHARSET     :: 162
VIETNAMESE_CHARSET  :: 163
THAI_CHARSET        :: 222
EASTEUROPE_CHARSET  :: 238
RUSSIAN_CHARSET     :: 204
MAC_CHARSET         :: 77
BALTIC_CHARSET      :: 186

// Font Signature Bitmaps
FS_LATIN1      :: 0x00000001
FS_LATIN2      :: 0x00000002
FS_CYRILLIC    :: 0x00000004
FS_GREEK       :: 0x00000008
FS_TURKISH     :: 0x00000010
FS_HEBREW      :: 0x00000020
FS_ARABIC      :: 0x00000040
FS_BALTIC      :: 0x00000080
FS_VIETNAMESE  :: 0x00000100
FS_THAI        :: 0x00010000
FS_JISJAPAN    :: 0x00020000
FS_CHINESESIMP :: 0x00040000
FS_WANSUNG     :: 0x00080000
FS_CHINESETRAD :: 0x00100000
FS_JOHAB       :: 0x00200000
FS_SYMBOL      :: 0x80000000

// Output Precisions
OUT_DEFAULT_PRECIS        :: 0
OUT_STRING_PRECIS         :: 1
OUT_CHARACTER_PRECIS      :: 2
OUT_STROKE_PRECIS         :: 3
OUT_TT_PRECIS             :: 4
OUT_DEVICE_PRECIS         :: 5
OUT_RASTER_PRECIS         :: 6
OUT_TT_ONLY_PRECIS        :: 7
OUT_OUTLINE_PRECIS        :: 8
OUT_SCREEN_OUTLINE_PRECIS :: 9
OUT_PS_ONLY_PRECIS        :: 10

// Clipping Precisions
CLIP_DEFAULT_PRECIS   :: 0
CLIP_CHARACTER_PRECIS :: 1
CLIP_STROKE_PRECIS    :: 2
CLIP_MASK             :: 0xf
CLIP_LH_ANGLES        :: 1 << 4
CLIP_TT_ALWAYS        :: 2 << 4
CLIP_DFA_DISABLE      :: 4 << 4
CLIP_EMBEDDED         :: 8 << 4

// Output Qualities
DEFAULT_QUALITY           :: 0
DRAFT_QUALITY             :: 1
PROOF_QUALITY             :: 2
NONANTIALIASED_QUALITY    :: 3
ANTIALIASED_QUALITY       :: 4
CLEARTYPE_QUALITY         :: 5
CLEARTYPE_NATURAL_QUALITY :: 6

// Font Pitches
DEFAULT_PITCH  :: 0
FIXED_PITCH    :: 1
VARIABLE_PITCH :: 2
MONO_FONT      :: 8

// Font Families
FF_DONTCARE   :: 0 << 4
FF_ROMAN      :: 1 << 4
FF_SWISS      :: 2 << 4
FF_MODERN     :: 3 << 4
FF_SCRIPT     :: 4 << 4
FF_DECORATIVE :: 5 << 4

@(default_calling_convention="stdcall")
foreign gdi32 {
    SetBkMode :: proc(hdc: win32.HDC, mode: win32.c_int) -> win32.c_int ---
    SetTextAlign :: proc(hdc: win32.HDC, align: win32.UINT) -> win32.UINT ---
    SetTextColor :: proc(hdc: win32.HDC, color: win32.COLORREF) -> win32.COLORREF ---
    GetCursor :: proc() -> win32.HCURSOR ---
}

@(default_calling_convention="stdcall")
foreign uxtheme {
    BeginBufferedPaint :: proc(
        hdcTarget: win32.HDC,
        prcTarget: ^win32.RECT,
        dwFormat: BP_BUFFERFORMAT,
        pPaintParams: ^BP_PAINTPARAMS,
        phdc: ^win32.HDC,
    ) -> HPAINTBUFFER ---
    EndBufferedPaint :: proc(hBufferedPaint: HPAINTBUFFER, fUpdateTarget: win32.BOOL) ---
}

HPAINTBUFFER :: distinct win32.HANDLE


CSIDL_PROFILE :: 0x0028
BLENDFUNCTION :: struct {
    BlendOp: win32.BYTE,
    BlendFlags: win32.BYTE,
    SourceConstantAlpha: win32.BYTE,
    AlphaFormat: win32.BYTE,
}

BP_BUFFERFORMAT :: enum {
    COMPATIBLEBITMAP,
    DIB,
    TOPDOWNDIB,
    TOPDOWNMONODIB,
}

BP_PAINTPARAMS :: struct {
    cbSize: win32.DWORD,
    dwFlags: win32.DWORD,
    prcExclude: ^win32.RECT,
    pBlendFunction: ^BLENDFUNCTION,
}

// Background Modes
TRANSPARENT :: 1
OPAQUE :: 2
BKMODE_LAST :: 2
