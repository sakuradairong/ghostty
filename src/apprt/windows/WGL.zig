const WGL = @This();

const std = @import("std");
const log = std.log.scoped(.apprt_windows_wgl);

/// A per-window WGL device and rendering context.
///
/// The window must have been created with CS_OWNDC. A window's pixel format can
/// only be set once, so create exactly one WGL value for each HWND.
pub const HWND = *opaque {};
pub const HDC = *opaque {};
pub const HGLRC = *opaque {};

pub const ContextInfo = struct {
    major: i32,
    minor: i32,
    profile_mask: i32,
    flags: i32,
};

pub const InitError = error{
    GetDeviceContextFailed,
    ChoosePixelFormatFailed,
    SetPixelFormatFailed,
    CreateLegacyContextFailed,
    MakeLegacyContextCurrentFailed,
    CreateContextAttribsUnavailable,
    CreateCoreContextFailed,
    DetachLegacyContextFailed,
    MakeCoreContextCurrentFailed,
    DeleteLegacyContextFailed,
    QueryContextInfoFailed,
    OpenGLVersionTooOld,
    OpenGLCoreProfileRequired,
};

pub const RuntimeError = error{
    MakeCurrentFailed,
    SwapBuffersFailed,
};

pub fn isInitError(err: anyerror) bool {
    return switch (err) {
        error.GetDeviceContextFailed,
        error.ChoosePixelFormatFailed,
        error.SetPixelFormatFailed,
        error.CreateLegacyContextFailed,
        error.MakeLegacyContextCurrentFailed,
        error.CreateContextAttribsUnavailable,
        error.CreateCoreContextFailed,
        error.DetachLegacyContextFailed,
        error.MakeCoreContextCurrentFailed,
        error.DeleteLegacyContextFailed,
        error.QueryContextInfoFailed,
        error.OpenGLVersionTooOld,
        error.OpenGLCoreProfileRequired,
        => true,
        else => false,
    };
}

hwnd: HWND,
hdc: HDC,
hglrc: HGLRC,
context_info: ContextInfo,

/// Installs a double-buffered RGBA pixel format and creates a context.
/// Ghostty requires OpenGL 4.3 core. The legacy context only exists long
/// enough to load WGL_ARB_create_context.
pub fn init(hwnd: HWND) InitError!WGL {
    const hdc = GetDC(hwnd) orelse
        return initFailure(error.GetDeviceContextFailed, "GetDC");
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
    if (format == 0)
        return initFailure(error.ChoosePixelFormatFailed, "ChoosePixelFormat");
    if (SetPixelFormat(hdc, format, &pfd) == 0)
        return initFailure(error.SetPixelFormatFailed, "SetPixelFormat");

    const legacy = wglCreateContext(hdc) orelse
        return initFailure(error.CreateLegacyContextFailed, "wglCreateContext");
    errdefer _ = wglDeleteContext(legacy);

    if (wglMakeCurrent(hdc, legacy) == 0)
        return initFailure(error.MakeLegacyContextCurrentFailed, "wglMakeCurrent(legacy)");
    errdefer _ = wglMakeCurrent(null, null);

    const create_context_attribs = loadWglCreateContextAttribs() orelse
        return extensionUnavailable();
    const context = createCoreContext(create_context_attribs, hdc, 4, 3) orelse
        return initFailure(error.CreateCoreContextFailed, "wglCreateContextAttribsARB(4.3 core)");
    errdefer _ = wglDeleteContext(context);

    // Detach the bootstrap context before binding the final core context.
    if (wglMakeCurrent(null, null) == 0)
        return initFailure(error.DetachLegacyContextFailed, "wglMakeCurrent(null, null)");
    if (wglMakeCurrent(hdc, context) == 0)
        return initFailure(error.MakeCoreContextCurrentFailed, "wglMakeCurrent(4.3 core)");
    // This must be registered after the final context becomes current so it
    // runs before the context deletion errdefer above.
    errdefer _ = wglMakeCurrent(null, null);

    const context_info = try queryContextInfo();
    validateContext(
        context_info.major,
        context_info.minor,
        context_info.profile_mask,
    ) catch |err| {
        log.err(
            "OpenGL context rejected error={s} version={}.{} profile_mask=0x{x}; " ++
                "Ghostty requires an OpenGL 4.3 Core Profile context.",
            .{
                @errorName(err),
                context_info.major,
                context_info.minor,
                context_info.profile_mask,
            },
        );
        return err;
    };
    log.info("OpenGL GL_CONTEXT_CORE_PROFILE_BIT confirmed", .{});

    if (wglDeleteContext(legacy) == 0)
        return initFailure(error.DeleteLegacyContextFailed, "wglDeleteContext(legacy)");

    return .{
        .hwnd = hwnd,
        .hdc = hdc,
        .hglrc = context,
        .context_info = context_info,
    };
}

pub fn makeCurrent(self: *const WGL) RuntimeError!void {
    if (wglMakeCurrent(self.hdc, self.hglrc) == 0) {
        log.err("wglMakeCurrent failed win32_error={}", .{GetLastError()});
        return error.MakeCurrentFailed;
    }
}

pub fn swapBuffers(self: *const WGL) RuntimeError!void {
    if (SwapBuffers(self.hdc) == 0) {
        log.err("SwapBuffers failed win32_error={}", .{GetLastError()});
        return error.SwapBuffersFailed;
    }
}

/// Releases the rendering context and the HWND's device context. The caller
/// must ensure no other thread has this HGLRC current.
pub fn deinit(self: *WGL) void {
    var detached = true;
    if (wglGetCurrentContext() == self.hglrc and wglMakeCurrent(null, null) == 0) {
        log.err("failed to detach WGL context during shutdown win32_error={}", .{GetLastError()});
        detached = false;
    }
    if (detached and wglDeleteContext(self.hglrc) == 0)
        log.err("wglDeleteContext failed during shutdown win32_error={}", .{GetLastError()});
    if (ReleaseDC(self.hwnd, self.hdc) == 0)
        log.err("ReleaseDC failed during shutdown win32_error={}", .{GetLastError()});
    self.* = undefined;
}

fn initFailure(err: InitError, stage: []const u8) InitError {
    const win32_error = GetLastError();
    log.err(
        "WGL initialization failed stage={s} error={s} win32_error={}; " ++
            "Ghostty requires an OpenGL 4.3 Core Profile context.",
        .{ stage, @errorName(err), win32_error },
    );
    return err;
}

fn extensionUnavailable() InitError {
    log.err(
        "WGL initialization failed stage=wglGetProcAddress " ++
            "error=CreateContextAttribsUnavailable; " ++
            "Ghostty requires an OpenGL 4.3 Core Profile context.",
        .{},
    );
    return error.CreateContextAttribsUnavailable;
}

fn createCoreContext(
    create: PFNWGLCREATECONTEXTATTRIBSARBPROC,
    hdc: HDC,
    major: i32,
    minor: i32,
) ?HGLRC {
    const attributes = contextAttributes(major, minor);
    return create(hdc, null, &attributes);
}

fn contextAttributes(major: i32, minor: i32) [7]i32 {
    return .{
        WGL_CONTEXT_MAJOR_VERSION_ARB, major,
        WGL_CONTEXT_MINOR_VERSION_ARB, minor,
        WGL_CONTEXT_PROFILE_MASK_ARB,  WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
        0,
    };
}

fn loadWglCreateContextAttribs() ?PFNWGLCREATECONTEXTATTRIBSARBPROC {
    const address = wglGetProcAddress("wglCreateContextAttribsARB") orelse return null;
    if (!isValidWglProcAddress(@intFromPtr(address))) return null;
    return @ptrCast(address);
}

fn isValidWglProcAddress(value: usize) bool {
    // wglGetProcAddress uses these sentinel values for unsupported functions.
    return value != 0 and value != 1 and value != 2 and value != 3 and
        value != @as(usize, @bitCast(@as(isize, -1)));
}

fn queryContextInfo() InitError!ContextInfo {
    // Ignore errors left by driver context creation before checking our own
    // diagnostic queries.
    var clear_count: usize = 0;
    while (clear_count < 16 and glGetError() != GL_NO_ERROR) : (clear_count += 1) {}

    const vendor = glGetString(GL_VENDOR) orelse return contextQueryFailure(GL_INVALID_VALUE);
    const renderer = glGetString(GL_RENDERER) orelse return contextQueryFailure(GL_INVALID_VALUE);
    const version = glGetString(GL_VERSION) orelse return contextQueryFailure(GL_INVALID_VALUE);
    const shading_language_version = glGetString(GL_SHADING_LANGUAGE_VERSION) orelse
        return contextQueryFailure(GL_INVALID_VALUE);

    var result: ContextInfo = .{
        .major = 0,
        .minor = 0,
        .profile_mask = 0,
        .flags = 0,
    };
    glGetIntegerv(GL_MAJOR_VERSION, &result.major);
    glGetIntegerv(GL_MINOR_VERSION, &result.minor);
    glGetIntegerv(GL_CONTEXT_PROFILE_MASK, &result.profile_mask);
    glGetIntegerv(GL_CONTEXT_FLAGS, &result.flags);

    const gl_error = glGetError();
    if (gl_error != GL_NO_ERROR) return contextQueryFailure(gl_error);

    log.info("OpenGL GL_VENDOR={s}", .{std.mem.span(vendor)});
    log.info("OpenGL GL_RENDERER={s}", .{std.mem.span(renderer)});
    log.info("OpenGL GL_VERSION={s}", .{std.mem.span(version)});
    log.info(
        "OpenGL GL_SHADING_LANGUAGE_VERSION={s}",
        .{std.mem.span(shading_language_version)},
    );
    log.info("OpenGL GL_MAJOR_VERSION={}", .{result.major});
    log.info("OpenGL GL_MINOR_VERSION={}", .{result.minor});
    log.info("OpenGL GL_CONTEXT_PROFILE_MASK=0x{x}", .{result.profile_mask});
    log.info("OpenGL GL_CONTEXT_FLAGS=0x{x}", .{result.flags});

    return result;
}

fn contextQueryFailure(gl_error: u32) InitError {
    log.err(
        "WGL initialization failed stage=OpenGL context query " ++
            "error=QueryContextInfoFailed gl_error=0x{x}; " ++
            "Ghostty requires an OpenGL 4.3 Core Profile context.",
        .{gl_error},
    );
    return error.QueryContextInfoFailed;
}

fn validateContext(major: i32, minor: i32, profile_mask: i32) InitError!void {
    if (major < 4 or (major == 4 and minor < 3))
        return error.OpenGLVersionTooOld;
    if (profile_mask & GL_CONTEXT_CORE_PROFILE_BIT == 0)
        return error.OpenGLCoreProfileRequired;
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

const GL_NO_ERROR: u32 = 0;
const GL_INVALID_VALUE: u32 = 0x0501;
const GL_VENDOR: u32 = 0x1F00;
const GL_RENDERER: u32 = 0x1F01;
const GL_VERSION: u32 = 0x1F02;
const GL_SHADING_LANGUAGE_VERSION: u32 = 0x8B8C;
const GL_MAJOR_VERSION: u32 = 0x821B;
const GL_MINOR_VERSION: u32 = 0x821C;
const GL_CONTEXT_FLAGS: u32 = 0x821E;
const GL_CONTEXT_PROFILE_MASK: u32 = 0x9126;
const GL_CONTEXT_CORE_PROFILE_BIT: i32 = 0x00000001;

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
extern "opengl32" fn glGetError() callconv(.winapi) u32;
extern "opengl32" fn glGetIntegerv(name: u32, value: *i32) callconv(.winapi) void;
extern "opengl32" fn glGetString(name: u32) callconv(.winapi) ?[*:0]const u8;

test "declarations are analyzable for a Windows cross target" {
    comptime {
        _ = WGL.init;
        _ = WGL.makeCurrent;
        _ = WGL.swapBuffers;
        _ = WGL.deinit;
        _ = WGL.isInitError;
    }
}

test "WGL classifies initialization failures" {
    try std.testing.expect(isInitError(error.CreateCoreContextFailed));
    try std.testing.expect(isInitError(error.OpenGLCoreProfileRequired));
    try std.testing.expect(!isInitError(error.OutOfMemory));
}

test "WGL builds explicit core profile context attributes" {
    try std.testing.expectEqualSlices(i32, &.{
        WGL_CONTEXT_MAJOR_VERSION_ARB, 4,
        WGL_CONTEXT_MINOR_VERSION_ARB, 3,
        WGL_CONTEXT_PROFILE_MASK_ARB,  WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
        0,
    }, &contextAttributes(4, 3));

    const impossible = contextAttributes(99, 0);
    try std.testing.expectEqual(@as(i32, 99), impossible[1]);
    try std.testing.expectEqual(@as(i32, 0), impossible[3]);
}

test "WGL validates OpenGL version and core profile" {
    try std.testing.expectError(
        error.OpenGLVersionTooOld,
        validateContext(4, 2, GL_CONTEXT_CORE_PROFILE_BIT),
    );
    try validateContext(4, 3, GL_CONTEXT_CORE_PROFILE_BIT);
    try validateContext(4, 6, GL_CONTEXT_CORE_PROFILE_BIT);
    try std.testing.expectError(
        error.OpenGLCoreProfileRequired,
        validateContext(4, 3, 0x00000002),
    );
    try std.testing.expectError(
        error.OpenGLCoreProfileRequired,
        validateContext(4, 6, 0x00000002),
    );
    try std.testing.expectError(
        error.OpenGLCoreProfileRequired,
        validateContext(4, 3, 0),
    );
}

test "WGL rejects invalid procedure addresses" {
    try std.testing.expect(!isValidWglProcAddress(0));
    try std.testing.expect(!isValidWglProcAddress(1));
    try std.testing.expect(!isValidWglProcAddress(2));
    try std.testing.expect(!isValidWglProcAddress(3));
    try std.testing.expect(!isValidWglProcAddress(@as(
        usize,
        @bitCast(@as(isize, -1)),
    )));
    try std.testing.expect(isValidWglProcAddress(4));
}
