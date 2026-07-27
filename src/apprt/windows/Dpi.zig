const apprt = @import("../../apprt.zig");
const win32 = @import("win32.zig");

pub const default: u32 = 96;

pub fn forWindow(hwnd: win32.HWND) u32 {
    const dpi = win32.GetDpiForWindow(hwnd);
    return if (dpi == 0) default else dpi;
}

pub fn contentScale(dpi: u32) apprt.ContentScale {
    const scale: f32 = @as(f32, @floatFromInt(dpi)) / default;
    return .{ .x = scale, .y = scale };
}

pub fn windowRectForClient(width: u32, height: u32, dpi: u32) win32.RECT {
    var rect: win32.RECT = .{
        .left = 0,
        .top = 0,
        .right = @intCast(width),
        .bottom = @intCast(height),
    };
    _ = win32.AdjustWindowRectExForDpi(&rect, win32.WS_OVERLAPPEDWINDOW, 0, 0, dpi);
    return rect;
}

pub fn resizeClient(hwnd: win32.HWND, width: u32, height: u32, dpi: u32) void {
    const rect = windowRectForClient(width, height, dpi);
    var outer_width = rect.right - rect.left;
    var outer_height = rect.bottom - rect.top;
    if (workArea(hwnd)) |work| {
        outer_width = @min(outer_width, work.right - work.left);
        outer_height = @min(outer_height, work.bottom - work.top);
    }
    _ = win32.SetWindowPos(
        hwnd,
        null,
        0,
        0,
        outer_width,
        outer_height,
        win32.SWP_NOMOVE | win32.SWP_NOZORDER | win32.SWP_NOACTIVATE,
    );
}

pub fn workArea(hwnd: win32.HWND) ?win32.RECT {
    const monitor = win32.MonitorFromWindow(hwnd, win32.MONITOR_DEFAULTTONEAREST) orelse return null;
    var info: win32.MONITORINFO = .{ .size = @sizeOf(win32.MONITORINFO) };
    if (win32.GetMonitorInfoW(monitor, &info) == 0) return null;
    return info.work;
}
