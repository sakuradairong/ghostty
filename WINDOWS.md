# Native Windows Application

> [!WARNING]
>
> The native Windows application is experimental development work. It has not
> completed Windows acceptance testing and is not an officially supported or
> distributed Ghostty application. Build it to develop and test the port, not as
> evidence that a Windows release is ready.

This document describes the source tree that contains it. The implementation
and requirements can change between commits.

## Requirements

- **Zig 0.16.0.** The authoritative value is `minimum_zig_version` in
  [`build.zig.zon`](build.zig.zon).
- **Windows 10 version 1809 or later** for
  [ConPTY](https://learn.microsoft.com/windows/console/creating-a-pseudoconsole-session).
  Ghostty creates the pseudoconsole directly. There is no legacy console host
  fallback.
- A graphics driver that exposes an **OpenGL 4.3 core profile** through WGL.
  The application exits during window creation when that context is unavailable.

For a native MSVC build, install Visual Studio 2022 Build Tools or Visual Studio
2022 with the **Desktop development with C++** workload and a Windows 10 or 11
SDK. Run the commands below from a Developer PowerShell or Developer Command
Prompt so the MSVC and SDK libraries are discoverable. This source tree does not
pin a particular Visual Studio 2022 minor release or Windows SDK revision.

## Build and Run

The native Windows runtime and MSVC ABI are selected by default when the target
is Windows. An explicit target makes developer and CI commands reproducible:

```powershell
zig build -Dtarget=x86_64-windows-msvc
.\zig-out\bin\ghostty.exe
```

During development, build and run in one step:

```powershell
zig build run -Dtarget=x86_64-windows-msvc
```

Arguments after `--` are passed to Ghostty:

```powershell
zig build run -Dtarget=x86_64-windows-msvc -- +show-config
```

A GNU ABI executable can be cross-compiled from Linux without Visual Studio or
the Windows SDK:

```sh
zig build -Dtarget=x86_64-windows-gnu
```

The result is `zig-out/bin/ghostty.exe`. Copy the complete `zig-out` tree to a
Windows machine before testing so the installed resources under `zig-out/share`
remain available. A cross-compiled executable cannot be run by `zig build run`
on the non-Windows build host.

The MSVC build is the native development path. GNU cross-compilation confirms
that the source builds for the target, but is not a substitute for running the
application and manually testing it on Windows.

## Implemented Platform Integration

The current runtime provides one native Win32 window per terminal surface and
uses the shared Ghostty core. The Windows-specific integration currently
includes:

- ConPTY process creation and resize
- OpenGL rendering through a WGL OpenGL 4.3 core context
- physical key press, repeat, and release events, Unicode text, dead keys,
  AltGr, and left/right modifier information
- mouse movement, leave tracking, capture, five buttons, and vertical and
  horizontal wheel input
- IMM32 composition preedit, committed IME text, and candidate-window
  positioning at the terminal cursor
- standard Windows Unicode text clipboard reads and writes
- a Per-Monitor V2 DPI-aware manifest, initial DPI scaling, and live
  `WM_DPICHANGED` handling
- multiple top-level windows, title changes, size limits, maximize, and
  fullscreen
- taskbar progress states and values, plus taskbar/window flashing for bell
  attention

These are implementation statements, not a completed compatibility matrix.
Keyboard layouts, IMEs, mouse hardware, mixed-DPI monitor arrangements, graphics
drivers, shells, and Windows versions still require manual acceptance testing.

## Known Limitations

- There are no tabs, splits, settings UI, or other platform-native application
  chrome yet. Many application actions not handled by the small Win32 runtime
  return unsupported.
- Closing a window destroys it immediately. The Windows runtime does not yet
  provide a close or quit confirmation dialog for active processes.
- Clipboard support is limited to the standard `CF_UNICODETEXT` clipboard.
  There is no selection clipboard or styled clipboard data.
- There is no Windows clipboard confirmation UI. Operations that Ghostty core
  marks unsafe or unauthorized, and OSC 52 writes that require confirmation,
  are denied rather than silently approved.
- Desktop notifications are disabled. Reliable Windows toast notifications
  require an installer-provided Application User Model ID, Start Menu
  registration, and activation handling, none of which exists yet.
- IPC and other unimplemented application-runtime actions are unavailable.

## Packaging

`zig build` produces an unpackaged executable and resources. The resource script
[`dist/windows/ghostty.rc`](dist/windows/ghostty.rc) embeds
[`ghostty.ico`](dist/windows/ghostty.ico) and the Per-Monitor V2 DPI manifest
[`ghostty.manifest`](dist/windows/ghostty.manifest) in `ghostty.exe`.

After a native Windows build, PowerShell 7 or newer can create the reproducible
portable ZIP documented in [`dist/windows/README.md`](dist/windows/README.md):

```powershell
zig build -Dtarget=x86_64-windows-msvc -Doptimize=ReleaseFast
.\dist\windows\package.ps1
```

[`package.ps1`](dist/windows/package.ps1) consumes the installed `zig-out` tree
and writes `zig-out/dist/ghostty-<version>-windows-<architecture>.zip`. The ZIP
contains `bin/ghostty.exe`, the `share` resource tree, and `LICENSE`. It is a
portable development artifact, not an installer.

There is currently no Windows installer, MSIX, signing pipeline, Start Menu
registration, or release publication workflow. Do not redistribute the portable
ZIP or CI executable as an official Ghostty package. The generic `zig build dist`
command creates a source tarball, not a Windows binary package.

## CI and Testing

The Windows jobs in [`.github/workflows/test.yml`](.github/workflows/test.yml)
are build and regression checks, not release qualification:

- `test-windows` runs targeted Windows tests, builds the native MSVC
  application, launches it long enough to verify that a top-level window is
  created, then uploads the unpackaged `zig-out` output and smoke-test logs.
- `build-libghostty-vt-windows` tests and builds `libghostty-vt` and checks its
  static-linking example. It does not test the native application.
- `build-libghostty-windows-gnu` builds the internal library with the GNU ABI and
  no application runtime. It does not build or run the native application.

The smoke check does not exercise terminal I/O, rendering correctness, input,
IME, clipboard, DPI transitions, taskbar integration, or the limitations listed
above. Those areas must be validated manually on Windows before support or
release claims are made.
