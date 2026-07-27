//! Windows taskbar and attention integration.
//!
//! Toast notifications intentionally do not live here. An unpackaged
//! executable needs a stable AUMID, Start Menu registration, and an activation
//! strategy before Windows notifications are reliable.

const std = @import("std");
const terminal = @import("../../terminal/main.zig");
const win32 = @import("win32.zig");

const ShellIntegration = @This();

const HRESULT = i32;
const ULONG = u32;
const ULONGLONG = u64;
const RPC_E_CHANGED_MODE: HRESULT = @bitCast(@as(u32, 0x80010106));
const CLSCTX_INPROC_SERVER: u32 = 0x1;
const COINIT_APARTMENTTHREADED: u32 = 0x2;

const IID = extern struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,
};

const clsid_taskbar_list: IID = .{
    .data1 = 0x56FDF344,
    .data2 = 0xFD6D,
    .data3 = 0x11D0,
    .data4 = .{ 0x95, 0x8A, 0x00, 0x60, 0x97, 0xC9, 0xA0, 0x90 },
};
const iid_taskbar_list_3: IID = .{
    .data1 = 0xEA1AFB91,
    .data2 = 0x9E28,
    .data3 = 0x4B86,
    .data4 = .{ 0x90, 0xE9, 0x9E, 0x9F, 0x8A, 0x5E, 0xEF, 0xAF },
};

const TaskbarProgressState = enum(u32) {
    no_progress = 0,
    indeterminate = 0x1,
    normal = 0x2,
    error_state = 0x4,
    paused = 0x8,
};

const ITaskbarList3 = extern struct {
    vtable: *const VTable,

    const VTable = extern struct {
        query_interface: *const fn (*ITaskbarList3, *const IID, *?*anyopaque) callconv(.winapi) HRESULT,
        add_ref: *const fn (*ITaskbarList3) callconv(.winapi) ULONG,
        release: *const fn (*ITaskbarList3) callconv(.winapi) ULONG,
        hr_init: *const fn (*ITaskbarList3) callconv(.winapi) HRESULT,
        add_tab: *const fn (*ITaskbarList3, win32.HWND) callconv(.winapi) HRESULT,
        delete_tab: *const fn (*ITaskbarList3, win32.HWND) callconv(.winapi) HRESULT,
        activate_tab: *const fn (*ITaskbarList3, win32.HWND) callconv(.winapi) HRESULT,
        set_active_alt: *const fn (*ITaskbarList3, win32.HWND) callconv(.winapi) HRESULT,
        mark_fullscreen_window: *const fn (*ITaskbarList3, win32.HWND, win32.BOOL) callconv(.winapi) HRESULT,
        set_progress_value: *const fn (*ITaskbarList3, win32.HWND, ULONGLONG, ULONGLONG) callconv(.winapi) HRESULT,
        set_progress_state: *const fn (*ITaskbarList3, win32.HWND, TaskbarProgressState) callconv(.winapi) HRESULT,
    };
};

com_initialized: bool = false,
taskbar: ?*ITaskbarList3 = null,

pub fn init() ShellIntegration {
    var self: ShellIntegration = .{};
    const result = CoInitializeEx(null, COINIT_APARTMENTTHREADED);
    self.com_initialized = succeeded(result);
    if (!self.com_initialized and result != RPC_E_CHANGED_MODE) return self;

    var object: ?*anyopaque = null;
    if (succeeded(CoCreateInstance(
        &clsid_taskbar_list,
        null,
        CLSCTX_INPROC_SERVER,
        &iid_taskbar_list_3,
        &object,
    ))) {
        self.taskbar = @ptrCast(@alignCast(object.?));
        if (!succeeded(self.taskbar.?.vtable.hr_init(self.taskbar.?))) {
            _ = self.taskbar.?.vtable.release(self.taskbar.?);
            self.taskbar = null;
        }
    }
    return self;
}

pub fn deinit(self: *ShellIntegration) void {
    if (self.taskbar) |taskbar| _ = taskbar.vtable.release(taskbar);
    if (self.com_initialized) CoUninitialize();
    self.* = .{};
}

pub fn requestAttention(_: *ShellIntegration, hwnd: win32.HWND) void {
    if (hwnd == null or win32.GetForegroundWindow() == hwnd) return;
    var info: win32.FLASHWINFO = .{
        .size = @sizeOf(win32.FLASHWINFO),
        .hwnd = hwnd,
        .flags = win32.FLASHW_ALL | win32.FLASHW_TIMERNOFG,
        .count = 0,
        .timeout_ms = 0,
    };
    _ = win32.FlashWindowEx(&info);
}

pub fn setProgress(
    self: *ShellIntegration,
    hwnd: win32.HWND,
    report: terminal.osc.Command.ProgressReport,
) bool {
    const taskbar = self.taskbar orelse return false;
    if (hwnd == null) return false;

    const state: TaskbarProgressState = switch (report.state) {
        .remove => .no_progress,
        .set => .normal,
        .@"error" => .error_state,
        .indeterminate => .indeterminate,
        .pause => .paused,
    };
    if (!succeeded(taskbar.vtable.set_progress_state(taskbar, hwnd, state))) return false;

    if (report.progress) |progress| {
        return succeeded(taskbar.vtable.set_progress_value(
            taskbar,
            hwnd,
            @min(progress, 100),
            100,
        ));
    }
    return true;
}

fn succeeded(result: HRESULT) bool {
    return result >= 0;
}

extern "ole32" fn CoInitializeEx(?*anyopaque, u32) callconv(.winapi) HRESULT;
extern "ole32" fn CoUninitialize() callconv(.winapi) void;
extern "ole32" fn CoCreateInstance(*const IID, ?*anyopaque, u32, *const IID, *?*anyopaque) callconv(.winapi) HRESULT;

comptime {
    _ = std;
}
