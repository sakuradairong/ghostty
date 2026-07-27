const App = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const apprt = @import("../../apprt.zig");
const Config = @import("../../config.zig").Config;
const CoreApp = @import("../../App.zig");
const Surface = @import("Surface.zig");
const ShellIntegration = @import("ShellIntegration.zig");
const Dpi = @import("Dpi.zig");
const win32 = @import("win32.zig");
const WGL = @import("WGL.zig");

const log = std.log.scoped(.apprt_windows);

const wake_message: u32 = win32.WM_APP;
const class_name = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyWindow");
const window_title = std.unicode.utf8ToUtf16LeStringLiteral("Ghostty");

pub const must_draw_from_app_thread = true;

core_app: *CoreApp,
config: Config,
thread_id: u32,
instance: win32.HINSTANCE,
shell: ShellIntegration,
window_count: usize = 0,
/// Set by the window procedure while dispatching a key message. Key
/// messages are dispatched before translation so Core can prevent the
/// complete WM_CHAR/WM_DEADCHAR sequence for a consumed shortcut.
translate_key_message: bool = true,

pub fn init(self: *App, core_app: *CoreApp, opts: struct {}) !void {
    _ = opts;
    var config = try Config.load(core_app.alloc);
    errdefer config.deinit();
    const instance = win32.GetModuleHandleW(null) orelse return error.GetModuleHandleFailed;
    self.* = .{
        .core_app = core_app,
        .config = config,
        .thread_id = win32.GetCurrentThreadId(),
        .instance = instance,
        .shell = .init(),
    };
    errdefer self.shell.deinit();

    const class: win32.WNDCLASSEXW = .{
        .size = @sizeOf(win32.WNDCLASSEXW),
        .style = win32.CS_OWNDC | win32.CS_HREDRAW | win32.CS_VREDRAW,
        .wnd_proc = windowProc,
        .cls_extra = 0,
        .wnd_extra = 0,
        .instance = instance,
        .icon = null,
        .cursor = win32.LoadCursorW(null, win32.IDC_ARROW),
        .background = null,
        .menu_name = null,
        .class_name = class_name,
        .icon_small = null,
    };
    if (win32.RegisterClassExW(&class) == 0) return error.RegisterClassFailed;
}

pub fn createNativeWindow(self: *App, surface: *Surface) !void {
    const hwnd = win32.CreateWindowExW(0, class_name, window_title, win32.WS_OVERLAPPEDWINDOW, win32.CW_USEDEFAULT, win32.CW_USEDEFAULT, 800, 600, null, null, self.instance, surface) orelse return error.CreateWindowFailed;
    surface.hwnd = hwnd;
    self.window_count += 1;
}

pub fn showNativeWindow(_: *App, surface: *Surface) void {
    const hwnd = surface.hwnd orelse return;
    _ = win32.ShowWindow(hwnd, win32.SW_SHOW);
    _ = win32.UpdateWindow(hwnd);
}

pub fn run(self: *App) !void {
    _ = Surface.create(self) catch |err| {
        log.err("initial Windows surface creation failed error={s}", .{@errorName(err)});
        showStartupError(err);
        return err;
    };
    var message: win32.MSG = undefined;
    while (true) {
        const result = win32.GetMessageW(&message, null, 0, 0);
        if (result == 0) break;
        if (result == -1) return error.GetMessageFailed;
        if (message.message == wake_message) {
            try self.core_app.tick(self);
            continue;
        }
        if (isKeyMessage(message.message)) {
            // TranslateMessage posts zero or more character messages. Doing it
            // after dispatch lets Core consume the physical key before any of
            // those messages exist. This avoids stateful "drop the next char"
            // logic, which cannot safely distinguish dead-key output,
            // surrogate pairs, and a later unrelated character.
            self.translate_key_message = true;
            _ = win32.DispatchMessageW(&message);
            if (self.translate_key_message) _ = win32.TranslateMessage(&message);
        } else {
            _ = win32.TranslateMessage(&message);
            _ = win32.DispatchMessageW(&message);
        }
    }
}

pub fn terminate(self: *App) void {
    self.shell.deinit();
    self.config.deinit();
}
pub fn wakeup(self: *App) void {
    _ = win32.PostThreadMessageW(self.thread_id, wake_message, 0, 0);
}

pub fn performAction(self: *App, target: apprt.Target, comptime action: apprt.Action.Key, value: apprt.Action.Value(action)) !bool {
    switch (action) {
        .quit => {
            win32.PostQuitMessage(0);
            return true;
        },
        .new_window => {
            _ = try Surface.create(self);
            return true;
        },
        .render => {
            const core = switch (target) {
                .surface => |surface| surface,
                else => return false,
            };
            _ = win32.InvalidateRect(core.rt_surface.hwnd, null, 0);
            return true;
        },
        .initial_size => {
            const core = switch (target) {
                .surface => |surface| surface,
                else => return false,
            };
            Dpi.resizeClient(core.rt_surface.hwnd, value.width, value.height, Dpi.forWindow(core.rt_surface.hwnd));
            return true;
        },
        .size_limit => {
            const core = switch (target) {
                .surface => |surface| surface,
                else => return false,
            };
            core.rt_surface.window.setSizeLimit(value);
            return true;
        },
        .set_title => {
            const core = switch (target) {
                .surface => |surface| surface,
                else => return false,
            };
            try core.rt_surface.window.setTitle(core.rt_surface.hwnd, value.title);
            return true;
        },
        .toggle_maximize => {
            const core = switch (target) {
                .surface => |surface| surface,
                else => return false,
            };
            core.rt_surface.window.toggleMaximize(core.rt_surface.hwnd);
            return true;
        },
        .toggle_fullscreen => {
            const core = switch (target) {
                .surface => |surface| surface,
                else => return false,
            };
            core.rt_surface.window.toggleFullscreen(core.rt_surface.hwnd);
            return true;
        },
        .present_terminal => {
            const core = switch (target) {
                .surface => |surface| surface,
                else => return false,
            };
            core.rt_surface.window.present(core.rt_surface.hwnd);
            return true;
        },
        .ring_bell => {
            const core = switch (target) {
                .surface => |surface| surface,
                else => return false,
            };
            if (self.config.@"bell-features".attention) {
                self.shell.requestAttention(core.rt_surface.hwnd);
            }
            return true;
        },
        .progress_report => {
            const core = switch (target) {
                .surface => |surface| surface,
                else => return false,
            };
            return self.shell.setProgress(core.rt_surface.hwnd, value);
        },
        // Windows toast notifications require an installer-provided AUMID and
        // activation registration. Do not claim this action until those exist.
        .desktop_notification => return false,
        else => return false,
    }
}

pub fn performIpc(alloc: Allocator, target: apprt.ipc.Target, comptime action: apprt.ipc.Action.Key, value: apprt.ipc.Action.Value(action)) !bool {
    _ = alloc;
    _ = target;
    _ = value;
    return false;
}

fn windowProc(hwnd: win32.HWND, message: u32, w_param: win32.WPARAM, l_param: win32.LPARAM) callconv(.winapi) win32.LRESULT {
    var surface: ?*Surface = if (win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA) == 0) null else @ptrFromInt(@as(usize, @bitCast(win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA))));
    if (message == win32.WM_NCCREATE) {
        const create: *const win32.CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(l_param)));
        surface = @ptrCast(@alignCast(create.create_params.?));
        _ = win32.SetWindowLongPtrW(hwnd, win32.GWLP_USERDATA, @bitCast(@intFromPtr(surface.?)));
        surface.?.hwnd = hwnd;
    }
    const self = surface orelse return win32.DefWindowProcW(hwnd, message, w_param, l_param);
    if (self.mouse.handle(self, message, w_param, l_param)) |result| return result;
    if (self.ime.handle(self, message, l_param)) |result| return result;
    switch (message) {
        win32.WM_CLOSE => {
            _ = win32.DestroyWindow(hwnd);
            return 0;
        },
        win32.WM_DESTROY => {
            _ = win32.SetWindowLongPtrW(hwnd, win32.GWLP_USERDATA, 0);
            self.hwnd = null;
            const app = self.app;
            app.window_count -= 1;
            // During Surface.create failure handling the allocator still owns
            // the object. A fully initialized surface is window-owned.
            if (self.core_initialized) {
                self.deinit();
                if (app.window_count == 0) win32.PostQuitMessage(0);
            }
            return 0;
        },
        win32.WM_SIZE => {
            const dimensions: usize = @bitCast(l_param);
            self.size = .{ .width = win32.lowWord(dimensions), .height = win32.highWord(dimensions) };
            if (self.core_initialized) self.core_surface.sizeCallback(self.size) catch {};
            return 0;
        },
        win32.WM_GETMINMAXINFO => {
            const info: *win32.MINMAXINFO = @ptrFromInt(@as(usize, @bitCast(l_param)));
            self.window.applyMinMaxInfo(hwnd, info);
            return 0;
        },
        win32.WM_ACTIVATE => {
            self.active = win32.lowWord(w_param) != 0;
            return 0;
        },
        win32.WM_PAINT => {
            var paint: win32.PAINTSTRUCT = undefined;
            _ = win32.BeginPaint(hwnd, &paint);
            defer _ = win32.EndPaint(hwnd, &paint);
            self.draw() catch |err| {
                log.err("Windows surface draw failed error={s}", .{@errorName(err)});
            };
            return 0;
        },
        win32.WM_DPICHANGED => {
            const dpi = win32.lowWord(w_param);
            self.content_scale = Dpi.contentScale(dpi);
            if (self.core_initialized) self.core_surface.contentScaleCallback(self.content_scale) catch {};
            const rect: *const win32.RECT = @ptrFromInt(@as(usize, @bitCast(l_param)));
            _ = win32.SetWindowPos(hwnd, null, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top, win32.SWP_NOZORDER | win32.SWP_NOACTIVATE);
            return 0;
        },
        win32.WM_SETFOCUS, win32.WM_KILLFOCUS => {
            self.focused = message == win32.WM_SETFOCUS;
            if (message == win32.WM_KILLFOCUS) {
                self.mouse.cancel(self);
                self.ime.reset(self);
            }
            self.keyboard.focus(self, message == win32.WM_SETFOCUS);
            return 0;
        },
        win32.WM_KEYDOWN, win32.WM_KEYUP, win32.WM_SYSKEYDOWN, win32.WM_SYSKEYUP => {
            if (self.keyboard.key(self, message, w_param, l_param)) {
                self.app.translate_key_message = false;
                return 0;
            }
            return win32.DefWindowProcW(hwnd, message, w_param, l_param);
        },
        win32.WM_CHAR => {
            self.keyboard.char(self, @truncate(w_param));
            return 0;
        },
        win32.WM_UNICHAR => {
            if (w_param == win32.UNICODE_NOCHAR) return 1;
            self.keyboard.char(self, @truncate(w_param));
            return 0;
        },
        else => return win32.DefWindowProcW(hwnd, message, w_param, l_param),
    }
}

fn showStartupError(err: anyerror) void {
    const requirement = if (WGL.isInitError(err) or err == error.OpenGLOutdated)
        "\n\nGhostty requires an OpenGL 4.3 Core Profile context."
    else
        "";
    var utf8_buffer: [512]u8 = undefined;
    const message = std.fmt.bufPrint(
        &utf8_buffer,
        "Ghostty failed to initialize its Windows surface.\n\n" ++
            "Failure stage: {s}{s}",
        .{ @errorName(err), requirement },
    ) catch "Ghostty failed to initialize its Windows surface.";

    var utf16_buffer: [512]u16 = undefined;
    const len = std.unicode.utf8ToUtf16Le(utf16_buffer[0 .. utf16_buffer.len - 1], message) catch 0;
    utf16_buffer[len] = 0;
    const title = std.unicode.utf8ToUtf16LeStringLiteral("Ghostty startup error");
    _ = win32.MessageBoxW(
        null,
        utf16_buffer[0..len :0].ptr,
        title,
        win32.MB_OK | win32.MB_ICONERROR | win32.MB_TASKMODAL,
    );
}

fn isKeyMessage(message: u32) bool {
    return message == win32.WM_KEYDOWN or message == win32.WM_KEYUP or
        message == win32.WM_SYSKEYDOWN or message == win32.WM_SYSKEYUP;
}
