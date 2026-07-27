const App = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const apprt = @import("../../apprt.zig");
const Config = @import("../../config.zig").Config;
const CoreApp = @import("../../App.zig");

const WM_APP: u32 = 0x8000;
const wake_message: u32 = WM_APP;

/// WGL contexts are owned and used by the Win32 application thread.
pub const must_draw_from_app_thread = true;

const MSG = extern struct {
    hwnd: ?*anyopaque,
    message: u32,
    w_param: usize,
    l_param: isize,
    time: u32,
    point: extern struct { x: i32, y: i32 },
    private: u32,
};

extern "user32" fn GetMessageW(
    message: *MSG,
    window: ?*anyopaque,
    message_filter_min: u32,
    message_filter_max: u32,
) callconv(.winapi) i32;
extern "user32" fn TranslateMessage(message: *const MSG) callconv(.winapi) i32;
extern "user32" fn DispatchMessageW(message: *const MSG) callconv(.winapi) isize;
extern "user32" fn PostQuitMessage(exit_code: i32) callconv(.winapi) void;
extern "user32" fn PostThreadMessageW(
    thread_id: u32,
    message: u32,
    w_param: usize,
    l_param: isize,
) callconv(.winapi) i32;
extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) u32;

core_app: *CoreApp,
config: Config,
thread_id: u32,

pub fn init(self: *App, core_app: *CoreApp, opts: struct {}) !void {
    _ = opts;

    var config = try Config.load(core_app.alloc);
    errdefer config.deinit();

    self.* = .{
        .core_app = core_app,
        .config = config,
        .thread_id = GetCurrentThreadId(),
    };
}

pub fn run(self: *App) !void {
    // M1 does not create a window yet. Queue a quit message so starting the
    // native runtime cannot leave a permanently idle, windowless process.
    PostQuitMessage(0);

    var message: MSG = undefined;
    while (true) {
        const result = GetMessageW(&message, null, 0, 0);
        if (result == 0) break;
        if (result == -1) return error.GetMessageFailed;

        if (message.message == wake_message) {
            try self.core_app.tick(self);
            continue;
        }

        _ = TranslateMessage(&message);
        _ = DispatchMessageW(&message);
    }
}

pub fn terminate(self: *App) void {
    self.config.deinit();
}

pub fn wakeup(self: *App) void {
    _ = PostThreadMessageW(self.thread_id, wake_message, 0, 0);
}

pub fn performAction(
    self: *App,
    target: apprt.Target,
    comptime action: apprt.Action.Key,
    value: apprt.Action.Value(action),
) !bool {
    _ = self;
    _ = target;
    _ = value;

    if (action == .quit) {
        PostQuitMessage(0);
        return true;
    }

    return false;
}

pub fn performIpc(
    alloc: Allocator,
    target: apprt.ipc.Target,
    comptime action: apprt.ipc.Action.Key,
    value: apprt.ipc.Action.Value(action),
) !bool {
    _ = alloc;
    _ = target;
    _ = value;
    return false;
}
