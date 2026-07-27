const std = @import("std");
const win32 = @import("win32.zig");

const Clipboard = @This();

const HGLOBAL = ?*anyopaque;

const CF_UNICODETEXT: u32 = 13;
const GMEM_MOVEABLE: u32 = 0x0002;
const open_attempts = 10;
const retry_delay_ms = 5;

pub const Error = error{
    ClipboardBusy,
    ClipboardEmpty,
    ClipboardFormatUnavailable,
    ClipboardDataInvalid,
    OutOfMemory,
    WindowsError,
};

/// Open the process-global clipboard, retrying briefly because another process
/// may have it open while handling a clipboard notification.
fn open(owner: win32.HWND) Error!void {
    for (0..open_attempts) |attempt| {
        if (OpenClipboard(owner) != 0) return;
        if (attempt + 1 < open_attempts) Sleep(retry_delay_ms);
    }
    return error.ClipboardBusy;
}

/// Read CF_UNICODETEXT and return an allocator-owned, sentinel-terminated UTF-8
/// copy. The clipboard is closed and its global memory unlocked before return.
pub fn read(allocator: std.mem.Allocator, owner: win32.HWND) Error![:0]u8 {
    if (IsClipboardFormatAvailable(CF_UNICODETEXT) == 0)
        return error.ClipboardFormatUnavailable;

    try open(owner);
    defer _ = CloseClipboard();

    const handle = GetClipboardData(CF_UNICODETEXT) orelse
        return error.ClipboardEmpty;
    const byte_len = GlobalSize(handle);
    if (byte_len < @sizeOf(u16)) return error.ClipboardDataInvalid;

    const raw = GlobalLock(handle) orelse return error.WindowsError;
    defer _ = GlobalUnlock(handle);

    const units: [*]const u16 = @ptrCast(@alignCast(raw));
    const max_units = byte_len / @sizeOf(u16);
    const len = std.mem.indexOfScalar(u16, units[0..max_units], 0) orelse
        return error.ClipboardDataInvalid;

    const utf8 = std.unicode.utf16LeToUtf8Alloc(allocator, units[0..len]) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.ClipboardDataInvalid,
    };
    defer allocator.free(utf8);
    return allocator.dupeZ(u8, utf8) catch error.OutOfMemory;
}

/// Replace the clipboard with CF_UNICODETEXT. Ownership of the HGLOBAL is
/// transferred to Windows only after SetClipboardData succeeds.
pub fn write(allocator: std.mem.Allocator, owner: win32.HWND, text: []const u8) Error!void {
    const utf16 = std.unicode.utf8ToUtf16LeAllocZ(allocator, text) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.ClipboardDataInvalid,
    };
    defer allocator.free(utf16);

    const byte_len = (utf16.len + 1) * @sizeOf(u16);
    const handle = GlobalAlloc(GMEM_MOVEABLE, byte_len) orelse
        return error.OutOfMemory;
    var owned = true;
    defer {
        if (owned) {
            _ = GlobalFree(handle);
        }
    }

    const raw = GlobalLock(handle) orelse return error.WindowsError;
    const utf16_with_sentinel = utf16.ptr[0 .. utf16.len + 1];
    @memcpy(
        @as([*]u8, @ptrCast(raw))[0..byte_len],
        std.mem.sliceAsBytes(utf16_with_sentinel),
    );
    _ = GlobalUnlock(handle);

    try open(owner);
    defer _ = CloseClipboard();
    if (EmptyClipboard() == 0) return error.WindowsError;
    if (SetClipboardData(CF_UNICODETEXT, handle) == null)
        return error.WindowsError;

    owned = false;
}

extern "user32" fn OpenClipboard(win32.HWND) callconv(.winapi) i32;
extern "user32" fn CloseClipboard() callconv(.winapi) i32;
extern "user32" fn EmptyClipboard() callconv(.winapi) i32;
extern "user32" fn IsClipboardFormatAvailable(u32) callconv(.winapi) i32;
extern "user32" fn GetClipboardData(u32) callconv(.winapi) HGLOBAL;
extern "user32" fn SetClipboardData(u32, HGLOBAL) callconv(.winapi) HGLOBAL;
extern "kernel32" fn GlobalAlloc(u32, usize) callconv(.winapi) HGLOBAL;
extern "kernel32" fn GlobalFree(HGLOBAL) callconv(.winapi) HGLOBAL;
extern "kernel32" fn GlobalLock(HGLOBAL) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GlobalUnlock(HGLOBAL) callconv(.winapi) i32;
extern "kernel32" fn GlobalSize(HGLOBAL) callconv(.winapi) usize;
extern "kernel32" fn Sleep(u32) callconv(.winapi) void;
