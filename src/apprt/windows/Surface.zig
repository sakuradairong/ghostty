const Surface = @This();

const std = @import("std");
const apprt = @import("../../apprt.zig");
const global = @import("../../global.zig");
const CoreSurface = @import("../../Surface.zig");
const App = @import("App.zig");
const Mouse = @import("Mouse.zig");
const Clipboard = @import("Clipboard.zig");
const Ime = @import("Ime.zig");
const Window = @import("Window.zig");
const Dpi = @import("Dpi.zig");
const win32 = @import("win32.zig");
const WGL = @import("WGL.zig");

const log = std.log.scoped(.apprt_windows);
const Keyboard = @import("Keyboard.zig");

core_surface: CoreSurface = undefined,
core_initialized: bool = false,
registered: bool = false,
app: *App,
hwnd: win32.HWND = null,
wgl: ?WGL = null,
size: apprt.SurfaceSize = .{ .width = 800, .height = 600 },
content_scale: apprt.ContentScale = .{ .x = 1, .y = 1 },
cursor_pos: apprt.CursorPos = .{ .x = 0, .y = 0 },
mouse: Mouse = .{},
keyboard: Keyboard = .{},
ime: Ime = .{},
window: Window,
focused: bool = false,
active: bool = false,

pub fn create(app: *App) !*Surface {
    const self = try app.core_app.alloc.create(Surface);
    errdefer app.core_app.alloc.destroy(self);
    self.* = .{ .app = app, .window = try Window.init(app.core_app.alloc, "Ghostty") };
    errdefer self.window.deinit();
    try app.createNativeWindow(self);
    errdefer {
        if (self.hwnd != null) _ = win32.DestroyWindow(self.hwnd);
    }

    self.content_scale = Dpi.contentScale(Dpi.forWindow(self.hwnd));

    self.wgl = WGL.init(@ptrCast(self.hwnd.?)) catch |err| {
        log.err("WGL initialization failed error={s}", .{@errorName(err)});
        return err;
    };
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

    self.core_surface.init(
        app.core_app.alloc,
        &config,
        app.core_app,
        app,
        self,
    ) catch |err| {
        log.err("Ghostty renderer initialization failed error={s}", .{@errorName(err)});
        return err;
    };
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
        // Renderer teardown deletes OpenGL objects, so it must run against
        // this surface's context rather than whichever window drew last.
        if (self.wgl) |*wgl| wgl.makeCurrent() catch |err| {
            log.err("failed to make WGL context current for renderer shutdown error={s}", .{@errorName(err)});
        };
        self.core_surface.deinit();
        self.core_initialized = false;
    }
    if (self.wgl) |*wgl| wgl.deinit();
    self.window.deinit();
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
    return self.window.getTitle();
}
pub fn supportsClipboard(self: *const Surface, clipboard_type: apprt.Clipboard) bool {
    _ = self;
    return clipboard_type == .standard;
}
pub fn clipboardRequest(self: *Surface, clipboard_type: apprt.Clipboard, state: apprt.ClipboardRequest) !bool {
    if (clipboard_type != .standard) return false;

    const alloc = self.app.core_app.alloc;
    const text = Clipboard.read(alloc, self.hwnd) catch |err| switch (err) {
        error.ClipboardEmpty, error.ClipboardFormatUnavailable => return false,
        else => return err,
    };
    defer alloc.free(text);

    self.core_surface.completeClipboardRequest(state, text, false) catch |err| switch (err) {
        // The native Windows runtime does not have confirmation UI yet. Never
        // bypass CoreSurface's paste/read protections in its absence.
        error.UnsafePaste, error.UnauthorizedPaste => {
            log.warn("clipboard request requires confirmation; denying request", .{});
            return true;
        },
        else => return err,
    };
    return true;
}
pub fn setClipboard(self: *Surface, clipboard_type: apprt.Clipboard, contents: []const apprt.ClipboardContent, confirm: bool) !void {
    if (clipboard_type != .standard) return error.Unsupported;

    // Until Windows has confirmation UI, a confirmation-required write must
    // be denied rather than silently granting an OSC 52 clipboard write.
    if (confirm) {
        log.warn("clipboard write requires confirmation; denying request", .{});
        return;
    }

    const text = for (contents) |content| {
        if (std.mem.eql(u8, content.mime, "text/plain")) break content.data;
    } else return error.Unsupported;

    try Clipboard.write(self.app.core_app.alloc, self.hwnd, text);
}
pub fn defaultTermioEnv(self: *const Surface) !std.process.Environ.Map {
    _ = self;
    return try global.environMap();
}
