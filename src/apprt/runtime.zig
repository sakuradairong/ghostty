const std = @import("std");

/// Runtime is the runtime to use for Ghostty. All runtimes do not provide
/// equivalent feature sets.
pub const Runtime = enum {
    /// Will not produce an executable at all when `zig build` is called.
    /// This is only useful if you're only interested in the lib only (macOS).
    none,

    /// GTK4. Rich windowed application. This uses a full GObject-based
    /// approach to building the application.
    gtk,

    /// Native Windows application runtime.
    windows,

    pub fn default(target: std.Target) Runtime {
        return switch (target.os.tag) {
            // The Linux and FreeBSD default is GTK because it is a full
            // featured application.
            .linux, .freebsd => .gtk,
            .windows => .windows,
            // Otherwise, we do NONE so we don't create an exe and we create
            // libghostty. On macOS, Xcode is used to build the app that links
            // to libghostty.
            else => .none,
        };
    }
};

test {
    _ = Runtime;
}

test "default runtime" {
    var target = @import("builtin").target;

    target.os.tag = .linux;
    try std.testing.expectEqual(.gtk, Runtime.default(target));

    target.os.tag = .windows;
    try std.testing.expectEqual(.windows, Runtime.default(target));

    target.os.tag = .macos;
    try std.testing.expectEqual(.none, Runtime.default(target));
}
