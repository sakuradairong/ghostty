const Mouse = @This();

const apprt = @import("../../apprt.zig");
const input = @import("../../input.zig");
const win32 = @import("win32.zig");

tracking_leave: bool = false,
pressed_buttons: u5 = 0,

/// Handles a mouse message, returning null when the message is not ours.
pub fn handle(self: *Mouse, surface: anytype, message: u32, w_param: win32.WPARAM, l_param: win32.LPARAM) ?win32.LRESULT {
    if (!surface.core_initialized) return null;

    switch (message) {
        win32.WM_MOUSEMOVE => {
            if (!self.tracking_leave) {
                var event: win32.TRACKMOUSEEVENT = .{
                    .size = @sizeOf(win32.TRACKMOUSEEVENT),
                    .flags = win32.TME_LEAVE,
                    .hwnd_track = surface.hwnd,
                    .hover_time = 0,
                };
                if (win32.TrackMouseEvent(&event) != 0) self.tracking_leave = true;
            }

            self.updatePosition(surface, pointFromLParam(l_param), mods()) catch {};
            return 0;
        },
        win32.WM_MOUSELEAVE => {
            self.tracking_leave = false;
            surface.cursor_pos = .{ .x = -1, .y = -1 };
            surface.core_surface.cursorPosCallback(surface.cursor_pos, mods()) catch {};
            return 0;
        },
        win32.WM_CAPTURECHANGED => {
            // ReleaseCapture also sends this message. The normal button-up path
            // clears the state first, so this is a no-op in that case.
            self.cancel(surface);
            return 0;
        },
        win32.WM_CANCELMODE => {
            self.cancel(surface);
            // DefWindowProc performs the actual capture cancellation. Returning
            // null avoids calling ReleaseCapture here and re-entering this path.
            return null;
        },
        win32.WM_LBUTTONDOWN => return self.button(surface, l_param, .press, .left, 0),
        win32.WM_LBUTTONUP => return self.button(surface, l_param, .release, .left, 0),
        win32.WM_RBUTTONDOWN => return self.button(surface, l_param, .press, .right, 1),
        win32.WM_RBUTTONUP => return self.button(surface, l_param, .release, .right, 1),
        win32.WM_MBUTTONDOWN => return self.button(surface, l_param, .press, .middle, 2),
        win32.WM_MBUTTONUP => return self.button(surface, l_param, .release, .middle, 2),
        win32.WM_XBUTTONDOWN, win32.WM_XBUTTONUP => {
            const xbutton = win32.highWord(w_param);
            const mouse_button: input.MouseButton = if (xbutton == win32.XBUTTON1) .four else .five;
            const bit: u3 = if (xbutton == win32.XBUTTON1) 3 else 4;
            _ = self.button(
                surface,
                l_param,
                if (message == win32.WM_XBUTTONDOWN) .press else .release,
                mouse_button,
                bit,
            );
            // Windows requires TRUE for handled XBUTTON messages.
            return 1;
        },
        win32.WM_MOUSEWHEEL, win32.WM_MOUSEHWHEEL => {
            var point = pointFromLParam(l_param);
            _ = win32.ScreenToClient(surface.hwnd, &point);
            self.updatePosition(surface, point, mods()) catch {};

            const raw: i16 = @bitCast(win32.highWord(w_param));
            const ticks = @as(f64, @floatFromInt(raw)) / @as(f64, win32.WHEEL_DELTA);
            // Win32 wheel messages are discrete and don't expose momentum.
            // Keyboard modifiers are delivered through cursorPosCallback above,
            // matching the GTK backend; ScrollMods only describes scroll shape.
            const scroll_mods: input.ScrollMods = .{};
            if (message == win32.WM_MOUSEWHEEL) {
                surface.core_surface.scrollCallback(0, ticks, scroll_mods) catch {};
            } else {
                surface.core_surface.scrollCallback(ticks, 0, scroll_mods) catch {};
            }
            return 0;
        },
        else => return null,
    }
}

/// Forget all locally pressed buttons and keep Core's button state in sync.
/// This intentionally doesn't manipulate capture: the caller or Windows owns
/// capture teardown, and ReleaseCapture would synchronously send another
/// WM_CAPTURECHANGED.
pub fn cancel(self: *Mouse, surface: anytype) void {
    const pressed = self.pressed_buttons;
    self.pressed_buttons = 0;

    const buttons = [_]input.MouseButton{ .left, .right, .middle, .four, .five };
    for (buttons, 0..) |button_, bit| {
        if (pressed & (@as(u5, 1) << @intCast(bit)) == 0) continue;
        _ = surface.core_surface.mouseButtonCallback(.release, button_, mods()) catch false;
    }
}

fn button(
    self: *Mouse,
    surface: anytype,
    l_param: win32.LPARAM,
    action: input.MouseButtonState,
    button_: input.MouseButton,
    bit: u3,
) win32.LRESULT {
    self.updatePosition(surface, pointFromLParam(l_param), mods()) catch {};

    const mask = @as(u5, 1) << bit;
    if (action == .press) {
        self.pressed_buttons |= mask;
        _ = win32.SetCapture(surface.hwnd);
    } else {
        self.pressed_buttons &= ~mask;
    }

    _ = surface.core_surface.mouseButtonCallback(action, button_, mods()) catch false;

    // Keep capture until every button pressed through this surface is released.
    if (action == .release and self.pressed_buttons == 0 and
        win32.GetCapture() == surface.hwnd)
    {
        _ = win32.ReleaseCapture();
    }
    return 0;
}

fn updatePosition(self: *Mouse, surface: anytype, point: win32.POINT, event_mods: input.Mods) !void {
    _ = self;
    const pos: apprt.CursorPos = .{
        .x = @floatFromInt(point.x),
        .y = @floatFromInt(point.y),
    };
    surface.cursor_pos = pos;
    try surface.core_surface.cursorPosCallback(pos, event_mods);
}

fn pointFromLParam(l_param: win32.LPARAM) win32.POINT {
    const value: usize = @bitCast(l_param);
    return .{
        .x = @as(i16, @bitCast(win32.lowWord(value))),
        .y = @as(i16, @bitCast(win32.highWord(value))),
    };
}

fn keyDown(key: i32) bool {
    return win32.GetKeyState(key) < 0;
}

fn toggled(key: i32) bool {
    return (win32.GetKeyState(key) & 1) != 0;
}

fn mods() input.Mods {
    const lshift = keyDown(win32.VK_LSHIFT);
    const rshift = keyDown(win32.VK_RSHIFT);
    const lctrl = keyDown(win32.VK_LCONTROL);
    const rctrl = keyDown(win32.VK_RCONTROL);
    const lalt = keyDown(win32.VK_LMENU);
    const ralt = keyDown(win32.VK_RMENU);
    const lsuper = keyDown(win32.VK_LWIN);
    const rsuper = keyDown(win32.VK_RWIN);
    return .{
        .shift = lshift or rshift,
        .ctrl = lctrl or rctrl,
        .alt = lalt or ralt,
        .super = lsuper or rsuper,
        .caps_lock = toggled(win32.VK_CAPITAL),
        .num_lock = toggled(win32.VK_NUMLOCK),
        .sides = .{
            .shift = if (rshift and !lshift) .right else .left,
            .ctrl = if (rctrl and !lctrl) .right else .left,
            .alt = if (ralt and !lalt) .right else .left,
            .super = if (rsuper and !lsuper) .right else .left,
        },
    };
}
