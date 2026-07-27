const Surface = @This();

const std = @import("std");
const apprt = @import("../../apprt.zig");
const global = @import("../../global.zig");
const CoreSurface = @import("../../Surface.zig");
const App = @import("App.zig");

core_surface: *CoreSurface,
app: *App,
size: apprt.SurfaceSize = .{ .width = 1, .height = 1 },
content_scale: apprt.ContentScale = .{ .x = 1, .y = 1 },
cursor_pos: apprt.CursorPos = .{ .x = 0, .y = 0 },

pub fn init(core_surface: *CoreSurface, app: *App) Surface {
    return .{
        .core_surface = core_surface,
        .app = app,
    };
}

pub fn deinit(self: *Surface) void {
    _ = self;
}

pub fn core(self: *Surface) *CoreSurface {
    return self.core_surface;
}

pub fn rtApp(self: *Surface) *App {
    return self.app;
}

pub fn close(self: *Surface, process_active: bool) void {
    _ = self;
    _ = process_active;
}

pub fn getContentScale(self: *const Surface) !apprt.ContentScale {
    return self.content_scale;
}

pub fn getSize(self: *const Surface) !apprt.SurfaceSize {
    return self.size;
}

pub fn getCursorPos(self: *const Surface) !apprt.CursorPos {
    return self.cursor_pos;
}

pub fn getTitle(self: *const Surface) ?[:0]const u8 {
    _ = self;
    return null;
}

pub fn supportsClipboard(
    self: *const Surface,
    clipboard_type: apprt.Clipboard,
) bool {
    _ = self;
    _ = clipboard_type;
    return false;
}

pub fn clipboardRequest(
    self: *Surface,
    clipboard_type: apprt.Clipboard,
    state: apprt.ClipboardRequest,
) !bool {
    _ = self;
    _ = clipboard_type;
    _ = state;
    return false;
}

pub fn setClipboard(
    self: *Surface,
    clipboard_type: apprt.Clipboard,
    contents: []const apprt.ClipboardContent,
    confirm: bool,
) !void {
    _ = self;
    _ = clipboard_type;
    _ = contents;
    _ = confirm;
    return error.Unsupported;
}

pub fn defaultTermioEnv(self: *const Surface) !std.process.Environ.Map {
    _ = self;
    return try global.environMap();
}
