const Surface = @This();

const std = @import("std");
const apprt = @import("../../apprt.zig");
const global = @import("../../global.zig");
const CoreSurface = @import("../../Surface.zig");
const App = @import("App.zig");
const win32 = @import("win32.zig");
const WGL = @import("WGL.zig");

core_surface: CoreSurface = undefined,
core_initialized: bool = false,
registered: bool = false,
app: *App,
hwnd: win32.HWND = null,
wgl: ?WGL = null,
size: apprt.SurfaceSize = .{ .width = 800, .height = 600 },
content_scale: apprt.ContentScale = .{ .x = 1, .y = 1 },
cursor_pos: apprt.CursorPos = .{ .x = 0, .y = 0 },

pub fn create(app: *App) !*Surface {
    const self = try app.core_app.alloc.create(Surface);
    errdefer app.core_app.alloc.destroy(self);
    self.* = .{ .app = app };
    try app.createNativeWindow(self);
    errdefer {
        if (self.hwnd != null) _ = win32.DestroyWindow(self.hwnd);
    }

    self.wgl = try WGL.init(@ptrCast(self.hwnd.?));
    errdefer {
        if (self.wgl) |*wgl| wgl.deinit();
    }

    var config = try apprt.surface.newConfig(app.core_app, &app.config, .window);
    defer config.deinit();

    try app.core_app.addSurface(self);
    self.registered = true;
    errdefer {
        app.core_app.deleteSurface(self);
        self.registered = false;
    }

    try self.core_surface.init(
        app.core_app.alloc,
        &config,
        app.core_app,
        app,
        self,
    );
    self.core_initialized = true;
    app.showNativeWindow(self);
    return self;
}

pub fn deinit(self: *Surface) void {
    if (self.registered) {
        self.app.core_app.deleteSurface(self);
        self.registered = false;
    }
    if (self.core_initialized) {
        self.core_surface.deinit();
        self.core_initialized = false;
    }
    if (self.wgl) |*wgl| wgl.deinit();
    self.app.core_app.alloc.destroy(self);
}

pub fn draw(self: *Surface) !void {
    if (!self.core_initialized) return;
    const wgl = &(self.wgl orelse return);
    try wgl.makeCurrent();
    try self.core_surface.draw();
    try wgl.swapBuffers();
}

pub fn core(self: *Surface) *CoreSurface {
    return &self.core_surface;
}
pub fn rtApp(self: *Surface) *App {
    return self.app;
}
pub fn close(self: *Surface, process_active: bool) void {
    _ = process_active;
    if (self.hwnd != null) _ = win32.DestroyWindow(self.hwnd);
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
pub fn supportsClipboard(self: *const Surface, clipboard_type: apprt.Clipboard) bool {
    _ = self;
    _ = clipboard_type;
    return false;
}
pub fn clipboardRequest(self: *Surface, clipboard_type: apprt.Clipboard, state: apprt.ClipboardRequest) !bool {
    _ = self;
    _ = clipboard_type;
    _ = state;
    return false;
}
pub fn setClipboard(self: *Surface, clipboard_type: apprt.Clipboard, contents: []const apprt.ClipboardContent, confirm: bool) !void {
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
