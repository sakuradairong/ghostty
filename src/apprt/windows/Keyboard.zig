const Keyboard = @This();

const std = @import("std");
const input = @import("../../input.zig");
const Surface = @import("Surface.zig");
const win32 = @import("win32.zig");

/// A pending high surrogate from WM_CHAR. This state intentionally lives in
/// one place so that a future WM_IME_* implementation can replace text input
/// without changing the physical-key path.
pending_high_surrogate: ?u16 = null,

pub fn focus(self: *Keyboard, surface: *Surface, focused: bool) void {
    self.pending_high_surrogate = null;
    if (surface.core_initialized) surface.core_surface.focusCallback(focused) catch {};
}

pub fn key(self: *Keyboard, surface: *Surface, message: u32, w_param: usize, l_param: isize) bool {
    _ = self;
    if (!surface.core_initialized) return false;

    const down = message == win32.WM_KEYDOWN or message == win32.WM_SYSKEYDOWN;
    const bits: usize = @bitCast(l_param);
    const action: input.Action = if (!down) .release else if ((bits & (@as(usize, 1) << 30)) != 0) .repeat else .press;
    const vk: u8 = @truncate(w_param);
    const mods = modifiers(vk, action);
    const event: input.KeyEvent = .{
        .action = action,
        .key = physicalKey(vk, bits),
        .mods = mods,
        .consumed_mods = if (isAltGr(mods)) .{ .ctrl = true, .alt = true } else .{},
        .unshifted_codepoint = unshiftedCodepoint(vk),
    };
    const effect = surface.core_surface.keyCallback(event) catch return false;
    return effect != .ignored;
}

/// Windows reports AltGr as a synthetic left-Control held together with
/// right-Alt. Marking both aggregate modifiers consumed keeps layout-produced
/// AltGr characters from matching Ctrl+Alt shortcuts while retaining the raw
/// modifier and side information in the event.
///
/// This deliberately avoids ToUnicodeEx: querying it here would mutate the
/// thread's dead-key state unless that state were separately tracked and
/// restored. The unavoidable ambiguity is a physically held left-Control plus
/// right-Alt, which Windows exposes with the same keyboard state as AltGr.
fn isAltGr(mods: input.Mods) bool {
    return mods.ctrl and mods.alt and keyDown(win32.VK_LCONTROL) and keyDown(win32.VK_RMENU);
}

pub fn char(self: *Keyboard, surface: *Surface, value: u32) void {
    if (!surface.core_initialized) return;

    if (value >= 0xD800 and value <= 0xDBFF) {
        // A second high surrogate makes the first malformed. Replace it rather
        // than carrying stale state into an unrelated character.
        if (self.pending_high_surrogate != null) self.emit(surface, 0xFFFD);
        self.pending_high_surrogate = @intCast(value);
        return;
    }

    if (value >= 0xDC00 and value <= 0xDFFF) {
        if (self.pending_high_surrogate) |high| {
            self.pending_high_surrogate = null;
            const cp = 0x10000 + ((@as(u32, high) - 0xD800) << 10) + (value - 0xDC00);
            self.emit(surface, cp);
        } else self.emit(surface, 0xFFFD);
        return;
    }

    if (self.pending_high_surrogate != null) {
        self.pending_high_surrogate = null;
        self.emit(surface, 0xFFFD);
    }
    if (value <= 0x10FFFF) self.emit(surface, value);
}

fn emit(_: *Keyboard, surface: *Surface, value: u32) void {
    const cp: u21 = @intCast(value);
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(cp, &buf) catch return;
    surface.core_surface.textCallback(buf[0..len]) catch {};
}

fn keyDown(vk: i32) bool {
    return win32.GetKeyState(vk) < 0;
}

fn toggled(vk: i32) bool {
    return (win32.GetKeyState(vk) & 1) != 0;
}

fn modifiers(_: u8, _: input.Action) input.Mods {
    var result: input.Mods = .{
        .shift = keyDown(0x10),
        .ctrl = keyDown(0x11),
        .alt = keyDown(0x12),
        .super = keyDown(0x5B) or keyDown(0x5C),
        .caps_lock = toggled(0x14),
        .num_lock = toggled(0x90),
    };

    // GetKeyState reflects the keyboard state for the message being
    // dispatched and preserves an aggregate modifier when its other side is
    // still held.
    result.sides.shift = if (keyDown(0xA1)) .right else .left;
    result.sides.ctrl = if (keyDown(0xA3)) .right else .left;
    result.sides.alt = if (keyDown(0xA5)) .right else .left;
    result.sides.super = if (keyDown(0x5C)) .right else .left;
    return result;
}

fn unshiftedCodepoint(vk: u8) u21 {
    // MAPVK_VK_TO_CHAR returns the layout's unshifted character. The high bit
    // marks a dead key and is not part of the codepoint.
    const cp = win32.MapVirtualKeyW(vk, 2) & 0x7FFF_FFFF;
    return if (cp <= 0x10FFFF) @intCast(cp) else 0;
}

fn physicalKey(vk: u8, bits: usize) input.Key {
    const extended = (bits & (@as(usize, 1) << 24)) != 0;
    return switch (vk) {
        0x08 => .backspace,
        0x09 => .tab,
        0x0D => if (extended) .numpad_enter else .enter,
        0x10 => if (((bits >> 16) & 0xFF) == 0x36) .shift_right else .shift_left,
        0x11 => if (extended) .control_right else .control_left,
        0x12 => if (extended) .alt_right else .alt_left,
        0x13 => .pause,
        0x14 => .caps_lock,
        0x1B => .escape,
        0x20 => .space,
        0x21 => .page_up,
        0x22 => .page_down,
        0x23 => .end,
        0x24 => .home,
        0x25 => .arrow_left,
        0x26 => .arrow_up,
        0x27 => .arrow_right,
        0x28 => .arrow_down,
        0x2C => .print_screen,
        0x2D => .insert,
        0x2E => .delete,
        0x30...0x39 => @enumFromInt(@intFromEnum(input.Key.digit_0) + vk - 0x30),
        0x41...0x5A => @enumFromInt(@intFromEnum(input.Key.key_a) + vk - 0x41),
        0x5B => .meta_left,
        0x5C => .meta_right,
        0x5D => .context_menu,
        0x60...0x69 => @enumFromInt(@intFromEnum(input.Key.numpad_0) + vk - 0x60),
        0x6A => .numpad_multiply,
        0x6B => .numpad_add,
        0x6C => .numpad_separator,
        0x6D => .numpad_subtract,
        0x6E => .numpad_decimal,
        0x6F => .numpad_divide,
        0x70...0x87 => @enumFromInt(@intFromEnum(input.Key.f1) + vk - 0x70),
        0x90 => .num_lock,
        0x91 => .scroll_lock,
        0xA0 => .shift_left,
        0xA1 => .shift_right,
        0xA2 => .control_left,
        0xA3 => .control_right,
        0xA4 => .alt_left,
        0xA5 => .alt_right,
        0xBA => .semicolon,
        0xBB => .equal,
        0xBC => .comma,
        0xBD => .minus,
        0xBE => .period,
        0xBF => .slash,
        0xC0 => .backquote,
        0xDB => .bracket_left,
        0xDC => .backslash,
        0xDD => .bracket_right,
        0xDE => .quote,
        else => .unidentified,
    };
}
