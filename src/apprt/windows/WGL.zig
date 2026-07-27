const WGL = @This();

/// A per-window WGL device and rendering context.
///
/// The window must have been created with CS_OWNDC. A window's pixel format can
/// only be set once, so create exactly one WGL value for each HWND.
pub const HWND = *opaque {};
pub const HDC = *opaque {};
pub const HGLRC = *opaque {};

pub const ContextKind = enum {
    core_4_3,
    core_3_3,
    legacy,
};

pub const InitError = error{
    GetDeviceContextFailed,
    ChoosePixelFormatFailed,
    SetPixelFormatFailed,
    CreateLegacyContextFailed,
    MakeLegacyContextCurrentFailed,
    MakeContextCurrentFailed,
    OpenGL43Unavailable,
};

pub const RuntimeError = error{
    MakeCurrentFailed,
    SwapBuffersFailed,
};

hwnd: HWND,
hdc: HDC,
hglrc: HGLRC,
context_kind: ContextKind,

/// Installs a double-buffered RGBA pixel format and creates a context.
/// Ghostty requires OpenGL 4.3 core. The legacy context only exists long
/// enough to load WGL_ARB_create_context.
pub fn init(hwnd: HWND) InitError!WGL {
    const hdc = GetDC(hwnd) orelse return error.GetDeviceContextFailed;
    errdefer _ = ReleaseDC(hwnd, hdc);

    var pfd: PIXELFORMATDESCRIPTOR = .{
        .nSize = @sizeOf(PIXELFORMATDESCRIPTOR),
        .nVersion = 1,
        .dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER,
        .iPixelType = PFD_TYPE_RGBA,
        .cColorBits = 32,
        .cRedBits = 0,
        .cRedShift = 0,
        .cGreenBits = 0,
        .cGreenShift = 0,
        .cBlueBits = 0,
        .cBlueShift = 0,
        .cAlphaBits = 8,
        .cAlphaShift = 0,
        .cAccumBits = 0,
        .cAccumRedBits = 0,
        .cAccumGreenBits = 0,
        .cAccumBlueBits = 0,
        .cAccumAlphaBits = 0,
        .cDepthBits = 24,
        .cStencilBits = 8,
        .cAuxBuffers = 0,
        .iLayerType = PFD_MAIN_PLANE,
        .bReserved = 0,
        .dwLayerMask = 0,
        .dwVisibleMask = 0,
        .dwDamageMask = 0,
    };

    const format = ChoosePixelFormat(hdc, &pfd);
    if (format == 0) return error.ChoosePixelFormatFailed;
    if (SetPixelFormat(hdc, format, &pfd) == 0)
        return error.SetPixelFormatFailed;

    const legacy = wglCreateContext(hdc) orelse
        return error.CreateLegacyContextFailed;
    errdefer _ = wglDeleteContext(legacy);

    if (wglMakeCurrent(hdc, legacy) == 0)
        return error.MakeLegacyContextCurrentFailed;
    errdefer _ = wglMakeCurrent(null, null);

    const create_context_attribs = loadWglCreateContextAttribs() orelse
        return error.OpenGL43Unavailable;
    const context = createCoreContext(create_context_attribs, hdc, 4, 3) orelse
        return error.OpenGL43Unavailable;
    errdefer _ = wglDeleteContext(context);

    // Detach the bootstrap context before binding the final core context.
    if (wglMakeCurrent(null, null) == 0)
        return error.MakeContextCurrentFailed;
    if (wglMakeCurrent(hdc, context) == 0)
        return error.MakeContextCurrentFailed;

    _ = wglDeleteContext(legacy);

    return .{
        .hwnd = hwnd,
        .hdc = hdc,
        .hglrc = context,
        .context_kind = .core_4_3,
    };
}

pub fn makeCurrent(self: *const WGL) RuntimeError!void {
    if (wglMakeCurrent(self.hdc, self.hglrc) == 0)
        return error.MakeCurrentFailed;
}

pub fn swapBuffers(self: *const WGL) RuntimeError!void {
    if (SwapBuffers(self.hdc) == 0)
        return error.SwapBuffersFailed;
}

/// Releases the rendering context and the HWND's device context. The caller
/// must ensure no other thread has this HGLRC current.
pub fn deinit(self: *WGL) void {
    if (wglGetCurrentContext() == self.hglrc) _ = wglMakeCurrent(null, null);
    _ = wglDeleteContext(self.hglrc);
    _ = ReleaseDC(self.hwnd, self.hdc);
    self.* = undefined;
}

/// Returns the calling thread's Win32 last-error code. Call immediately after
/// catching an error to supplement the stage-specific Zig error.
pub fn lastError() u32 {
    return GetLastError();
}

fn createCoreContext(
    create: PFNWGLCREATECONTEXTATTRIBSARBPROC,
    hdc: HDC,
    major: i32,
    minor: i32,
) ?HGLRC {
    const attributes = [_]i32{
        WGL_CONTEXT_MAJOR_VERSION_ARB, major,
        WGL_CONTEXT_MINOR_VERSION_ARB, minor,
        WGL_CONTEXT_PROFILE_MASK_ARB,  WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
        0,
    };
    return create(hdc, null, &attributes);
}

fn loadWglCreateContextAttribs() ?PFNWGLCREATECONTEXTATTRIBSARBPROC {
    const address = wglGetProcAddress("wglCreateContextAttribsARB") orelse return null;
    const value = @intFromPtr(address);
    // wglGetProcAddress uses these sentinel values for unsupported functions.
    if (value == 0 or value == 1 or value == 2 or value == 3 or value == @as(usize, @bitCast(@as(isize, -1))))
        return null;
    return @ptrCast(address);
}

const BOOL = i32;
const UINT = u32;
const DWORD = u32;
const BYTE = u8;
const WORD = u16;

const PIXELFORMATDESCRIPTOR = extern struct {
    nSize: WORD,
    nVersion: WORD,
    dwFlags: DWORD,
    iPixelType: BYTE,
    cColorBits: BYTE,
    cRedBits: BYTE,
    cRedShift: BYTE,
    cGreenBits: BYTE,
    cGreenShift: BYTE,
    cBlueBits: BYTE,
    cBlueShift: BYTE,
    cAlphaBits: BYTE,
    cAlphaShift: BYTE,
    cAccumBits: BYTE,
    cAccumRedBits: BYTE,
    cAccumGreenBits: BYTE,
    cAccumBlueBits: BYTE,
    cAccumAlphaBits: BYTE,
    cDepthBits: BYTE,
    cStencilBits: BYTE,
    cAuxBuffers: BYTE,
    iLayerType: BYTE,
    bReserved: BYTE,
    dwLayerMask: DWORD,
    dwVisibleMask: DWORD,
    dwDamageMask: DWORD,
};

const PFD_DOUBLEBUFFER: DWORD = 0x00000001;
const PFD_DRAW_TO_WINDOW: DWORD = 0x00000004;
const PFD_SUPPORT_OPENGL: DWORD = 0x00000020;
const PFD_TYPE_RGBA: BYTE = 0;
const PFD_MAIN_PLANE: BYTE = 0;

const WGL_CONTEXT_MAJOR_VERSION_ARB: i32 = 0x2091;
const WGL_CONTEXT_MINOR_VERSION_ARB: i32 = 0x2092;
const WGL_CONTEXT_PROFILE_MASK_ARB: i32 = 0x9126;
const WGL_CONTEXT_CORE_PROFILE_BIT_ARB: i32 = 0x00000001;

const PFNWGLCREATECONTEXTATTRIBSARBPROC = *const fn (
    hdc: HDC,
    share_context: ?HGLRC,
    attributes: [*]const i32,
) callconv(.winapi) ?HGLRC;

extern "user32" fn GetDC(hwnd: HWND) callconv(.winapi) ?HDC;
extern "user32" fn ReleaseDC(hwnd: HWND, hdc: HDC) callconv(.winapi) i32;
extern "kernel32" fn GetLastError() callconv(.winapi) DWORD;

extern "gdi32" fn ChoosePixelFormat(
    hdc: HDC,
    pfd: *const PIXELFORMATDESCRIPTOR,
) callconv(.winapi) i32;
extern "gdi32" fn SetPixelFormat(
    hdc: HDC,
    format: i32,
    pfd: *const PIXELFORMATDESCRIPTOR,
) callconv(.winapi) BOOL;
extern "gdi32" fn SwapBuffers(hdc: HDC) callconv(.winapi) BOOL;

extern "opengl32" fn wglCreateContext(hdc: HDC) callconv(.winapi) ?HGLRC;
extern "opengl32" fn wglDeleteContext(context: HGLRC) callconv(.winapi) BOOL;
extern "opengl32" fn wglGetCurrentContext() callconv(.winapi) ?HGLRC;
extern "opengl32" fn wglGetProcAddress(name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
extern "opengl32" fn wglMakeCurrent(hdc: ?HDC, context: ?HGLRC) callconv(.winapi) BOOL;

test "declarations are analyzable for a Windows cross target" {
    comptime {
        _ = WGL.init;
        _ = WGL.makeCurrent;
        _ = WGL.swapBuffers;
        _ = WGL.deinit;
        _ = WGL.lastError;
    }
}
