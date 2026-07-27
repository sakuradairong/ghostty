const std = @import("std");

pub const HWND = ?*anyopaque;
pub const HINSTANCE = ?*anyopaque;
pub const HCURSOR = ?*anyopaque;
pub const HICON = ?*anyopaque;
pub const HBRUSH = ?*anyopaque;
pub const HDC = ?*anyopaque;
pub const HMENU = ?*anyopaque;
pub const HIMC = ?*anyopaque;
pub const HMONITOR = ?*anyopaque;
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;
pub const ATOM = u16;
pub const BOOL = i32;

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
pub const MINMAXINFO = extern struct {
    reserved: POINT,
    max_size: POINT,
    max_position: POINT,
    min_track_size: POINT,
    max_track_size: POINT,
};
pub const MONITORINFO = extern struct {
    size: u32,
    monitor: RECT = undefined,
    work: RECT = undefined,
    flags: u32 = 0,
};
pub const TRACKMOUSEEVENT = extern struct {
    size: u32,
    flags: u32,
    hwnd_track: HWND,
    hover_time: u32,
};
pub const FLASHWINFO = extern struct {
    size: u32,
    hwnd: HWND,
    flags: u32,
    count: u32,
    timeout_ms: u32,
};
pub const COMPOSITIONFORM = extern struct {
    style: u32,
    current_pos: POINT,
    area: RECT,
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
pub const WM_ACTIVATE: u32 = 0x0006;
pub const WM_CANCELMODE: u32 = 0x001F;
pub const WM_SETFOCUS: u32 = 0x0007;
pub const WM_KILLFOCUS: u32 = 0x0008;
pub const WM_PAINT: u32 = 0x000F;
pub const WM_SIZE: u32 = 0x0005;
pub const WM_CLOSE: u32 = 0x0010;
pub const WM_NCCREATE: u32 = 0x0081;
pub const WM_GETMINMAXINFO: u32 = 0x0024;
pub const WM_DPICHANGED: u32 = 0x02E0;
pub const WM_MOUSEMOVE: u32 = 0x0200;
pub const WM_LBUTTONDOWN: u32 = 0x0201;
pub const WM_LBUTTONUP: u32 = 0x0202;
pub const WM_RBUTTONDOWN: u32 = 0x0204;
pub const WM_RBUTTONUP: u32 = 0x0205;
pub const WM_MBUTTONDOWN: u32 = 0x0207;
pub const WM_MBUTTONUP: u32 = 0x0208;
pub const WM_MOUSEWHEEL: u32 = 0x020A;
pub const WM_XBUTTONDOWN: u32 = 0x020B;
pub const WM_XBUTTONUP: u32 = 0x020C;
pub const WM_MOUSEHWHEEL: u32 = 0x020E;
pub const WM_CAPTURECHANGED: u32 = 0x0215;
pub const WM_MOUSELEAVE: u32 = 0x02A3;
pub const WM_KEYDOWN: u32 = 0x0100;
pub const WM_KEYUP: u32 = 0x0101;
pub const WM_CHAR: u32 = 0x0102;
pub const WM_SYSKEYDOWN: u32 = 0x0104;
pub const WM_SYSKEYUP: u32 = 0x0105;
pub const WM_UNICHAR: u32 = 0x0109;
pub const WM_IME_STARTCOMPOSITION: u32 = 0x010D;
pub const WM_IME_ENDCOMPOSITION: u32 = 0x010E;
pub const WM_IME_COMPOSITION: u32 = 0x010F;
pub const UNICODE_NOCHAR: WPARAM = 0xFFFF;
pub const GCS_COMPSTR: u32 = 0x0008;
pub const GCS_RESULTSTR: u32 = 0x0800;
pub const CFS_POINT: u32 = 0x0002;
pub const WM_APP: u32 = 0x8000;
pub const GWLP_USERDATA: i32 = -21;
pub const GWL_STYLE: i32 = -16;
pub const GWL_EXSTYLE: i32 = -20;
pub const CS_OWNDC: u32 = 0x0020;
pub const CS_HREDRAW: u32 = 0x0002;
pub const CS_VREDRAW: u32 = 0x0001;
pub const WS_OVERLAPPEDWINDOW: u32 = 0x00CF0000;
pub const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));
pub const SW_SHOW: i32 = 5;
pub const SW_MINIMIZE: i32 = 6;
pub const SW_MAXIMIZE: i32 = 3;
pub const SW_RESTORE: i32 = 9;
pub const SWP_FRAMECHANGED: u32 = 0x0020;
pub const HWND_TOP: HWND = @ptrFromInt(0);
pub const SWP_NOMOVE: u32 = 0x0002;
pub const SWP_NOZORDER: u32 = 0x0004;
pub const SWP_NOACTIVATE: u32 = 0x0010;
pub const MONITOR_DEFAULTTONEAREST: u32 = 0x00000002;
pub const IDC_ARROW: [*:0]const u16 = @ptrFromInt(32512);
pub const TME_LEAVE: u32 = 0x00000002;
pub const FLASHW_ALL: u32 = 0x00000003;
pub const FLASHW_TIMERNOFG: u32 = 0x0000000C;
pub const MB_OK: u32 = 0x00000000;
pub const MB_ICONERROR: u32 = 0x00000010;
pub const MB_TASKMODAL: u32 = 0x00002000;
pub const XBUTTON1: u16 = 0x0001;
pub const WHEEL_DELTA: i32 = 120;
pub const VK_CAPITAL: i32 = 0x14;
pub const VK_LSHIFT: i32 = 0xA0;
pub const VK_RSHIFT: i32 = 0xA1;
pub const VK_LCONTROL: i32 = 0xA2;
pub const VK_RCONTROL: i32 = 0xA3;
pub const VK_LMENU: i32 = 0xA4;
pub const VK_RMENU: i32 = 0xA5;
pub const VK_LWIN: i32 = 0x5B;
pub const VK_RWIN: i32 = 0x5C;
pub const VK_NUMLOCK: i32 = 0x90;

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
pub extern "user32" fn SetWindowTextW(HWND, [*:0]const u16) callconv(.winapi) i32;
pub extern "user32" fn AdjustWindowRectExForDpi(*RECT, u32, i32, u32, u32) callconv(.winapi) i32;
pub extern "user32" fn IsZoomed(HWND) callconv(.winapi) i32;
pub extern "user32" fn IsIconic(HWND) callconv(.winapi) i32;
pub extern "user32" fn SetForegroundWindow(HWND) callconv(.winapi) i32;
pub extern "user32" fn GetWindowRect(HWND, *RECT) callconv(.winapi) i32;
pub extern "user32" fn MonitorFromWindow(HWND, u32) callconv(.winapi) HMONITOR;
pub extern "user32" fn GetMonitorInfoW(HMONITOR, *MONITORINFO) callconv(.winapi) i32;
pub extern "user32" fn LoadCursorW(HINSTANCE, [*:0]const u16) callconv(.winapi) HCURSOR;
pub extern "user32" fn GetDpiForWindow(HWND) callconv(.winapi) u32;
pub extern "user32" fn TrackMouseEvent(*TRACKMOUSEEVENT) callconv(.winapi) i32;
pub extern "user32" fn SetCapture(HWND) callconv(.winapi) HWND;
pub extern "user32" fn GetCapture() callconv(.winapi) HWND;
pub extern "user32" fn ReleaseCapture() callconv(.winapi) i32;
pub extern "user32" fn ScreenToClient(HWND, *POINT) callconv(.winapi) i32;
pub extern "user32" fn GetKeyState(i32) callconv(.winapi) i16;
pub extern "user32" fn MapVirtualKeyW(u32, u32) callconv(.winapi) u32;
pub extern "user32" fn FlashWindowEx(*FLASHWINFO) callconv(.winapi) i32;
pub extern "user32" fn GetForegroundWindow() callconv(.winapi) HWND;
pub extern "user32" fn MessageBoxW(HWND, [*:0]const u16, [*:0]const u16, u32) callconv(.winapi) i32;
pub extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) u32;
pub extern "kernel32" fn GetModuleHandleW(?[*:0]const u16) callconv(.winapi) HINSTANCE;
pub extern "imm32" fn ImmGetContext(HWND) callconv(.winapi) HIMC;
pub extern "imm32" fn ImmReleaseContext(HWND, HIMC) callconv(.winapi) i32;
pub extern "imm32" fn ImmGetCompositionStringW(HIMC, u32, ?*anyopaque, u32) callconv(.winapi) i32;
pub extern "imm32" fn ImmSetCompositionWindow(HIMC, *const COMPOSITIONFORM) callconv(.winapi) i32;

pub fn lowWord(value: usize) u16 {
    return @truncate(value);
}
pub fn highWord(value: usize) u16 {
    return @truncate(value >> 16);
}

comptime {
    _ = std;
}
