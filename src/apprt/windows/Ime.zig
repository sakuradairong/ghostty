const Ime = @This();

const std = @import("std");
const Surface = @import("Surface.zig");
const win32 = @import("win32.zig");

composing: bool = false,

/// Handles IME messages completely. Returning a result tells the window proc
/// not to call DefWindowProcW. In particular, handling GCS_RESULTSTR here and
/// returning zero prevents the default procedure from generating WM_CHAR for
/// the same committed text.
pub fn handle(self: *Ime, surface: *Surface, message: u32, l_param: win32.LPARAM) ?win32.LRESULT {
    switch (message) {
        win32.WM_IME_STARTCOMPOSITION => {
            self.composing = true;
            self.setCandidatePosition(surface);
            self.setPreedit(surface, null);
            return 0;
        },
        win32.WM_IME_COMPOSITION => {
            self.composing = true;
            self.setCandidatePosition(surface);

            const flags: usize = @bitCast(l_param);
            if ((flags & win32.GCS_RESULTSTR) != 0) {
                self.commit(surface);
                self.setPreedit(surface, null);
            } else if ((flags & win32.GCS_COMPSTR) != 0) {
                self.updatePreedit(surface);
            }
            return 0;
        },
        win32.WM_IME_ENDCOMPOSITION => {
            self.composing = false;
            self.setPreedit(surface, null);
            return 0;
        },
        else => return null,
    }
}

pub fn reset(self: *Ime, surface: *Surface) void {
    self.composing = false;
    self.setPreedit(surface, null);
}

fn updatePreedit(self: *Ime, surface: *Surface) void {
    const text = getString(surface, win32.GCS_COMPSTR) orelse return;
    defer surface.app.core_app.alloc.free(text);
    self.setPreedit(surface, if (text.len == 0) null else text);
}

fn commit(_: *Ime, surface: *Surface) void {
    const text = getString(surface, win32.GCS_RESULTSTR) orelse return;
    defer surface.app.core_app.alloc.free(text);
    if (text.len != 0 and surface.core_initialized)
        surface.core_surface.textCallback(text) catch {};
}

fn setPreedit(_: *Ime, surface: *Surface, text: ?[]const u8) void {
    if (surface.core_initialized) surface.core_surface.preeditCallback(text) catch {};
}

fn getString(surface: *Surface, index: u32) ?[]u8 {
    const hwnd = surface.hwnd orelse return null;
    const context = win32.ImmGetContext(hwnd) orelse return null;
    defer _ = win32.ImmReleaseContext(hwnd, context);

    const byte_len = win32.ImmGetCompositionStringW(context, index, null, 0);
    if (byte_len < 0 or @mod(byte_len, @sizeOf(u16)) != 0) return null;
    if (byte_len == 0) return surface.app.core_app.alloc.alloc(u8, 0) catch null;

    const alloc = surface.app.core_app.alloc;
    const utf16 = alloc.alloc(u16, @intCast(@divExact(byte_len, @sizeOf(u16)))) catch return null;
    defer alloc.free(utf16);
    const copied = win32.ImmGetCompositionStringW(context, index, utf16.ptr, @intCast(byte_len));
    if (copied != byte_len) return null;

    // utf16LeToUtf8Alloc rejects malformed surrogate sequences rather than
    // allowing invalid UTF-8 into CoreSurface.
    return std.unicode.utf16LeToUtf8Alloc(alloc, utf16) catch null;
}

fn setCandidatePosition(_: *Ime, surface: *Surface) void {
    const hwnd = surface.hwnd orelse return;
    if (!surface.core_initialized) return;
    const context = win32.ImmGetContext(hwnd) orelse return;
    defer _ = win32.ImmReleaseContext(hwnd, context);

    const point = surface.core_surface.imePoint();
    var form: win32.COMPOSITIONFORM = .{
        .style = win32.CFS_POINT,
        .current_pos = .{ .x = @intFromFloat(point.x), .y = @intFromFloat(point.y) },
        .area = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    };
    _ = win32.ImmSetCompositionWindow(context, &form);
}
