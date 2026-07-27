const Window = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const apprt = @import("../../apprt.zig");
const win32 = @import("win32.zig");

alloc: Allocator,
title: [:0]u8,
min_size: apprt.SurfaceSize = .{ .width = 0, .height = 0 },
max_size: apprt.SurfaceSize = .{ .width = 0, .height = 0 },
fullscreen: bool = false,
restore_rect: win32.RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
restore_style: isize = 0,

pub fn init(alloc: Allocator, title: []const u8) !Window {
    return .{
        .alloc = alloc,
        .title = try alloc.dupeZ(u8, title),
    };
}

pub fn deinit(self: *Window) void {
    self.alloc.free(self.title);
}

/// The returned title is borrowed and remains valid until setTitle or deinit.
pub fn getTitle(self: *const Window) [:0]const u8 {
    return self.title;
}

pub fn setTitle(self: *Window, hwnd: win32.HWND, title: []const u8) !void {
    const owned = try self.alloc.dupeZ(u8, title);
    errdefer self.alloc.free(owned);
    const wide = try std.unicode.utf8ToUtf16LeAllocZ(self.alloc, title);
    defer self.alloc.free(wide);
    if (win32.SetWindowTextW(hwnd, wide) == 0) return error.SetWindowTextFailed;
    self.alloc.free(self.title);
    self.title = owned;
}

pub fn setSizeLimit(self: *Window, limit: apprt.action.SizeLimit) void {
    self.min_size = .{ .width = limit.min_width, .height = limit.min_height };
    self.max_size = .{ .width = limit.max_width, .height = limit.max_height };
}

pub fn applyMinMaxInfo(self: *const Window, hwnd: win32.HWND, info: *win32.MINMAXINFO) void {
    const style: u32 = @truncate(@as(usize, @bitCast(win32.GetWindowLongPtrW(hwnd, win32.GWL_STYLE))));
    const ex_style: u32 = @truncate(@as(usize, @bitCast(win32.GetWindowLongPtrW(hwnd, win32.GWL_EXSTYLE))));
    const dpi = win32.GetDpiForWindow(hwnd);
    if (self.min_size.width != 0 or self.min_size.height != 0) {
        var rect: win32.RECT = .{ .left = 0, .top = 0, .right = @intCast(self.min_size.width), .bottom = @intCast(self.min_size.height) };
        _ = win32.AdjustWindowRectExForDpi(&rect, style, 0, ex_style, dpi);
        info.min_track_size = .{ .x = rect.right - rect.left, .y = rect.bottom - rect.top };
    }
    if (self.max_size.width != 0 or self.max_size.height != 0) {
        var rect: win32.RECT = .{ .left = 0, .top = 0, .right = @intCast(self.max_size.width), .bottom = @intCast(self.max_size.height) };
        _ = win32.AdjustWindowRectExForDpi(&rect, style, 0, ex_style, dpi);
        info.max_track_size = .{ .x = rect.right - rect.left, .y = rect.bottom - rect.top };
    }
}

pub fn resize(self: *const Window, hwnd: win32.HWND, size: apprt.SurfaceSize) void {
    _ = self;
    var rect: win32.RECT = .{ .left = 0, .top = 0, .right = @intCast(size.width), .bottom = @intCast(size.height) };
    const style: u32 = @truncate(@as(usize, @bitCast(win32.GetWindowLongPtrW(hwnd, win32.GWL_STYLE))));
    const ex_style: u32 = @truncate(@as(usize, @bitCast(win32.GetWindowLongPtrW(hwnd, win32.GWL_EXSTYLE))));
    _ = win32.AdjustWindowRectExForDpi(&rect, style, 0, ex_style, win32.GetDpiForWindow(hwnd));
    _ = win32.SetWindowPos(hwnd, null, 0, 0, rect.right - rect.left, rect.bottom - rect.top, win32.SWP_NOMOVE | win32.SWP_NOZORDER);
}

pub fn toggleMaximize(_: *Window, hwnd: win32.HWND) void {
    _ = win32.ShowWindow(hwnd, if (win32.IsZoomed(hwnd) != 0) win32.SW_RESTORE else win32.SW_MAXIMIZE);
}

pub fn minimize(_: *Window, hwnd: win32.HWND) void {
    _ = win32.ShowWindow(hwnd, win32.SW_MINIMIZE);
}

pub fn present(_: *Window, hwnd: win32.HWND) void {
    if (win32.IsIconic(hwnd) != 0) _ = win32.ShowWindow(hwnd, win32.SW_RESTORE);
    _ = win32.SetForegroundWindow(hwnd);
}

pub fn toggleFullscreen(self: *Window, hwnd: win32.HWND) void {
    if (!self.fullscreen) {
        if (win32.GetWindowRect(hwnd, &self.restore_rect) == 0) return;
        self.restore_style = win32.GetWindowLongPtrW(hwnd, win32.GWL_STYLE);
        const monitor = win32.MonitorFromWindow(hwnd, win32.MONITOR_DEFAULTTONEAREST);
        var info: win32.MONITORINFO = .{ .size = @sizeOf(win32.MONITORINFO), .monitor = undefined, .work = undefined, .flags = 0 };
        if (win32.GetMonitorInfoW(monitor, &info) == 0) return;
        _ = win32.SetWindowLongPtrW(hwnd, win32.GWL_STYLE, self.restore_style & ~@as(isize, win32.WS_OVERLAPPEDWINDOW));
        _ = win32.SetWindowPos(hwnd, win32.HWND_TOP, info.monitor.left, info.monitor.top, info.monitor.right - info.monitor.left, info.monitor.bottom - info.monitor.top, win32.SWP_FRAMECHANGED);
        self.fullscreen = true;
    } else {
        _ = win32.SetWindowLongPtrW(hwnd, win32.GWL_STYLE, self.restore_style);
        _ = win32.SetWindowPos(hwnd, null, self.restore_rect.left, self.restore_rect.top, self.restore_rect.right - self.restore_rect.left, self.restore_rect.bottom - self.restore_rect.top, win32.SWP_NOZORDER | win32.SWP_FRAMECHANGED);
        self.fullscreen = false;
    }
}
