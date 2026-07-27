const std = @import("std");

pub const HWND = ?*anyopaque;
pub const HINSTANCE = ?*anyopaque;
pub const HCURSOR = ?*anyopaque;
pub const HICON = ?*anyopaque;
pub const HBRUSH = ?*anyopaque;
pub const HDC = ?*anyopaque;
pub const HMENU = ?*anyopaque;
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;
pub const ATOM = u16;

pub const POINT = extern struct { x: i32, y: i32 };
pub const MSG = extern struct {
    hwnd: HWND,
    message: u32,
    w_param: WPARAM,
    l_param: LPARAM,
    time: u32,
    point: POINT,
    private: u32,
};
pub const RECT = extern struct { left: i32, top: i32, right: i32, bottom: i32 };
pub const PAINTSTRUCT = extern struct {
    hdc: HDC,
    erase: i32,
    paint: RECT,
    restore: i32,
    update: i32,
    reserved: [32]u8,
};
pub const CREATESTRUCTW = extern struct {
    create_params: ?*anyopaque,
    instance: HINSTANCE,
    menu: HMENU,
    parent: HWND,
    cy: i32,
    cx: i32,
    y: i32,
    x: i32,
    style: i32,
    name: ?[*:0]const u16,
    class: ?[*:0]const u16,
    ex_style: u32,
};
pub const WNDPROC = *const fn (HWND, u32, WPARAM, LPARAM) callconv(.winapi) LRESULT;
pub const WNDCLASSEXW = extern struct {
    size: u32,
    style: u32,
    wnd_proc: WNDPROC,
    cls_extra: i32,
    wnd_extra: i32,
    instance: HINSTANCE,
    icon: HICON,
    cursor: HCURSOR,
    background: HBRUSH,
    menu_name: ?[*:0]const u16,
    class_name: [*:0]const u16,
    icon_small: HICON,
};

pub const WM_DESTROY: u32 = 0x0002;
pub const WM_PAINT: u32 = 0x000F;
pub const WM_SIZE: u32 = 0x0005;
pub const WM_CLOSE: u32 = 0x0010;
pub const WM_NCCREATE: u32 = 0x0081;
pub const WM_DPICHANGED: u32 = 0x02E0;
pub const WM_APP: u32 = 0x8000;
pub const GWLP_USERDATA: i32 = -21;
pub const CS_OWNDC: u32 = 0x0020;
pub const CS_HREDRAW: u32 = 0x0002;
pub const CS_VREDRAW: u32 = 0x0001;
pub const WS_OVERLAPPEDWINDOW: u32 = 0x00CF0000;
pub const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));
pub const SW_SHOW: i32 = 5;
pub const IDC_ARROW: [*:0]const u16 = @ptrFromInt(32512);

pub extern "user32" fn RegisterClassExW(*const WNDCLASSEXW) callconv(.winapi) ATOM;
pub extern "user32" fn CreateWindowExW(u32, [*:0]const u16, [*:0]const u16, u32, i32, i32, i32, i32, HWND, HMENU, HINSTANCE, ?*anyopaque) callconv(.winapi) HWND;
pub extern "user32" fn DefWindowProcW(HWND, u32, WPARAM, LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn DestroyWindow(HWND) callconv(.winapi) i32;
pub extern "user32" fn ShowWindow(HWND, i32) callconv(.winapi) i32;
pub extern "user32" fn UpdateWindow(HWND) callconv(.winapi) i32;
pub extern "user32" fn GetMessageW(*MSG, HWND, u32, u32) callconv(.winapi) i32;
pub extern "user32" fn TranslateMessage(*const MSG) callconv(.winapi) i32;
pub extern "user32" fn DispatchMessageW(*const MSG) callconv(.winapi) LRESULT;
pub extern "user32" fn PostQuitMessage(i32) callconv(.winapi) void;
pub extern "user32" fn PostThreadMessageW(u32, u32, WPARAM, LPARAM) callconv(.winapi) i32;
pub extern "user32" fn SetWindowLongPtrW(HWND, i32, isize) callconv(.winapi) isize;
pub extern "user32" fn GetWindowLongPtrW(HWND, i32) callconv(.winapi) isize;
pub extern "user32" fn InvalidateRect(HWND, ?*const RECT, i32) callconv(.winapi) i32;
pub extern "user32" fn BeginPaint(HWND, *PAINTSTRUCT) callconv(.winapi) HDC;
pub extern "user32" fn EndPaint(HWND, *const PAINTSTRUCT) callconv(.winapi) i32;
pub extern "user32" fn SetWindowPos(HWND, HWND, i32, i32, i32, i32, u32) callconv(.winapi) i32;
pub extern "user32" fn LoadCursorW(HINSTANCE, [*:0]const u16) callconv(.winapi) HCURSOR;
pub extern "user32" fn GetDpiForWindow(HWND) callconv(.winapi) u32;
pub extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) u32;
pub extern "kernel32" fn GetModuleHandleW(?[*:0]const u16) callconv(.winapi) HINSTANCE;

pub fn lowWord(value: usize) u16 {
    return @truncate(value);
}
pub fn highWord(value: usize) u16 {
    return @truncate(value >> 16);
}

comptime {
    _ = std;
}
