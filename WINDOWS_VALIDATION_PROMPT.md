# Windows Native Application Validation Agent Prompt

You are validating Ghostty's experimental native Windows desktop application on a real Windows 10/11 x64 machine. Keep executing, diagnosing, and fixing issues. Do not stop at recommendations or research.

## Repository

- Repository: `https://github.com/sakuradairong/ghostty.git`
- Branch: `feature/windows-native-app`
- Expected minimum HEAD: `21f1f9a4d`

## Goal

Complete native Windows end-to-end acceptance testing covering MSVC builds, Win32/WGL, ConPTY, input, IME, clipboard, multiple windows, DPI, taskbar integration, and portable packaging. Fix discovered problems directly, repeat validation, commit fixes to the current branch, and push them to the fork. Do not create an issue or pull request.

## Rules

1. Compilation success is not native runtime acceptance.
2. Do not rewrite or delete existing milestone commits.
3. Preserve commands, errors, logs, and reproduction steps for every failure.
4. Prefer fixing code over merely documenting defects.
5. Do not claim functionality that you did not personally observe.
6. Before committing fixes, run formatting, relevant tests, and a complete MSVC build.
7. Push fixes directly to `sakuradairong/ghostty`, branch `feature/windows-native-app`.
8. If the environment lacks an interactive desktop, OpenGL 4.3, an IME, or necessary hardware, mark that test blocked rather than passed.

## Phase 1: Environment and Source Verification

Run:

```powershell
git clone https://github.com/sakuradairong/ghostty.git
cd ghostty
git checkout feature/windows-native-app
git pull --ff-only
git rev-parse HEAD
git status --short
zig version
```

Confirm:

- HEAD includes at least `21f1f9a4d`.
- Zig satisfies `minimum_zig_version` in `build.zig.zon`, currently expected to be 0.16.0.
- Visual Studio 2022 C++ Build Tools and a Windows 10/11 SDK are installed.
- Commands run from Developer PowerShell or an environment containing MSVC and SDK paths.
- The initial worktree is clean.
- The system supports ConPTY.
- The graphics driver provides an OpenGL 4.3 core profile through WGL.

## Phase 2: MSVC Build and Tests

Run:

```powershell
zig fmt --check src/apprt/windows
zig build test -Dtarget=x86_64-windows-msvc -Dapp-runtime=none '-Dtest-filter=default runtime'
zig build test-lib-vt -Dtarget=x86_64-windows-msvc '-Dtest-filter=PageList Pin row movement clamps across mixed-width pages'
zig build -Dtarget=x86_64-windows-msvc -Doptimize=ReleaseSafe
```

Confirm:

- `zig-out\bin\ghostty.exe` exists.
- The EXE contains its icon and DPI manifest.
- There are no missing `user32`, `gdi32`, `opengl32`, `imm32`, or `ole32` symbols.
- It does not unexpectedly depend on MinGW runtime DLLs.
- Runtime resources exist under `zig-out\share`.
- Event Viewer, stderr, and Ghostty logs contain no startup errors.

If the MSVC build fails, diagnose and fix Zig, Win32 ABI, SDK, linker, or resource errors directly. Do not substitute a GNU build to hide an MSVC failure. Repeat every command above after fixing it.

## Phase 3: Startup and Basic Terminal Behavior

Start:

```powershell
.\zig-out\bin\ghostty.exe
```

Validate and record:

1. The process stays alive and does not immediately crash.
2. A visible Win32 top-level window appears.
3. WGL creates an OpenGL 4.3 core context.
4. The first frame renders correctly rather than remaining black or white.
5. ConPTY starts the default shell.
6. A shell prompt is visible.
7. `echo GHOSTTY_WINDOWS_OK` produces the correct result.
8. PowerShell and `cmd.exe` input and output work.
9. Large output continues rendering and can be scrolled.
10. Resizing updates the ConPTY rows, columns, and rendered grid.
11. Shell exit produces reasonable window behavior.
12. Closing the window terminates Ghostty and its ConPTY child process.

Record the Windows version/build, GPU and driver, OpenGL vendor/renderer/version, default shell, and Passed/Failed/Blocked for every observation. Preserve stack traces, Event Viewer entries, and logs for crashes.

## Phase 4: Keyboard and Unicode

Validate:

1. A-Z, 0-9, Space, Enter, Backspace, Tab, and Escape.
2. Arrows, Home, End, Insert, Delete, Page Up, and Page Down.
3. F1-F12.
4. Left and right Shift, Ctrl, Alt, and Windows keys.
5. Numpad digits, operators, and numpad Enter.
6. Holding a character produces repeat and releasing stops it.
7. Ctrl+C, Ctrl+V, Ctrl+Shift+C, Ctrl+Shift+V, and other bindings do not insert extra characters after being consumed.
8. System shortcuts such as Alt+F4 retain normal Windows behavior.
9. AltGr layout characters work without incorrectly triggering Ctrl+Alt shortcuts.
10. Dead-key layouts compose characters correctly.
11. BMP Unicode characters work.
12. Non-BMP text such as emoji is handled as a correct UTF-16 surrogate pair.
13. Focus changes do not leave stuck modifier or surrogate state.

Test at least one non-US layout with AltGr and dead keys. If unavailable, state precisely which layout could not be installed or tested.

## Phase 5: IME

Use Microsoft Pinyin or another installed IME:

1. Starting composition displays preedit text.
2. Updating composition updates the preedit text.
3. The candidate window appears near the terminal cursor.
4. Confirming a candidate commits text exactly once.
5. No duplicate `WM_CHAR` text appears.
6. Cancelling composition clears preedit.
7. Losing focus safely clears composition state.
8. Committed Chinese, Japanese, or Korean text reaches the shell as correct UTF-8.
9. Candidate placement remains reasonable at 100%, 125%, and 150% DPI and on mixed-DPI displays.

## Phase 6: Mouse

Validate:

1. Movement and hover.
2. Leaving the client area.
3. Left, middle, and right buttons.
4. XBUTTON1 and XBUTTON2.
5. Vertical wheel.
6. Horizontal wheel.
7. Drag selection.
8. Capture while dragging outside the window.
9. Alt+Tab, system menus, or another window stealing capture does not leave a button stuck.
10. Input remains correct after `WM_CANCELMODE`, `WM_CAPTURECHANGED`, and focus loss.
11. Shift/Ctrl modified scrolling behaves consistently with Ghostty core semantics.

## Phase 7: Clipboard

Validate:

1. Copy ASCII from another Windows application into Ghostty.
2. Copy Chinese, emoji, and multiline text into Ghostty.
3. Copy ASCII, Chinese, emoji, and multiline text from Ghostty into Notepad.
4. An empty clipboard or missing `CF_UNICODETEXT` does not crash.
5. Temporary clipboard contention retries and fails safely.
6. Large copy/paste operations.
7. Unsafe or unauthorized paste is denied without confirmation UI.
8. OSC 52 writes requiring confirmation are denied rather than silently accepted.
9. Unsupported primary/selection clipboard requests report unsupported.

## Phase 8: Windows, Multiple Windows, and DPI

Validate:

1. Dynamic terminal title updates the window title.
2. Multiple windows can be created.
3. Closing one window does not terminate other windows.
4. Closing the final window exits the main process.
5. Maximize and restore.
6. Minimize and restore.
7. Enter and leave fullscreen.
8. Fullscreen exit restores the original style and placement.
9. Present/foreground behavior is reasonable and does not continuously steal focus.
10. Minimum and maximum size constraints work.
11. Initial client size is correct.
12. 100%, 125%, 150%, and 200% DPI.
13. Moving a window between displays with different DPI.
14. After `WM_DPICHANGED`, fonts, grid, client area, and mouse coordinates remain consistent.
15. Initial sizing does not exceed the nearest monitor work area.
16. IME candidate placement remains near the cursor after DPI changes.

## Phase 9: Taskbar and System Integration

Validate:

1. Bell attention flashes the taskbar/window when it is not foreground.
2. A foreground window does not flash unnecessarily.
3. OSC progress states normal, error, paused, indeterminate, and remove display correctly.
4. Progress for multiple windows applies to the correct HWND.
5. Closing windows does not expose COM or taskbar lifetime errors.
6. Application exit is clean.
7. Explicitly record Windows toast notifications as unimplemented, not passed.

## Phase 10: Portable Package

Run:

```powershell
.\dist\windows\package.ps1 -Architecture x86_64
```

Validate:

1. `zig-out\dist\ghostty-*-windows-x86_64.zip` is created.
2. The ZIP is non-empty and extracts cleanly.
3. It contains:
   - `bin\ghostty.exe`
   - the `share` resource tree
   - `share\terminfo\ghostty.terminfo`
   - `LICENSE`
4. It excludes unnecessary PDBs, import libraries, headers, and development DLLs.
5. Extract it into a new path containing spaces and Unicode.
6. Start Ghostty from that extracted directory without relying on the source tree or original `zig-out`.
7. Generate the ZIP twice and compare SHA-256. Identical inputs must produce identical hashes.
8. An invalid version such as `..\escape` must be rejected without writing outside the destination.

## Phase 11: Stability and Diagnostics

Perform at least:

1. Twenty start/close cycles.
2. Five simultaneous windows running commands.
3. Thirty seconds of rapid resize.
4. Large terminal output and scrolling.
5. Repeated Alt+Tab, mixed-DPI moves, and fullscreen toggles.
6. Repeated Unicode clipboard operations.
7. Repeated IME compose, confirm, and cancel operations.
8. Check Task Manager for residual Ghostty or shell processes.
9. Check the Application Event Log for crashes.
10. If available, use WinDbg, Application Verifier, or PageHeap to detect use-after-free, double-free, handle leaks, and invalid Win32 parameters.

## Fix Workflow

For every issue:

1. Establish minimal reproduction steps.
2. Locate the relevant Windows runtime, Win32 ABI, WGL, ConPTY, build, or package code.
3. Implement the smallest maintainable fix.
4. Run `zig fmt`.
5. Repeat the relevant targeted test.
6. Repeat the complete MSVC ReleaseSafe build.
7. Repeat the failed native scenario.
8. Run `git diff --check`.
9. Create a clear commit.
10. Push it to `sakuradairong/ghostty`, branch `feature/windows-native-app`.
11. Continue to the next acceptance item rather than stopping after the first failure.

## Required Final Report

Include:

- Final HEAD and every new fix commit.
- Windows version, CPU, GPU, driver, OpenGL version, Zig version, and Visual Studio/SDK versions.
- Exact MSVC build and test commands with results.
- Passed/Failed/Blocked for every validation phase.
- Reproduction steps, logs, and fix commits for every failure.
- Separate conclusions for WGL, ConPTY, keyboard, AltGr/dead keys, IME, clipboard, multiple windows, DPI, taskbar, and ZIP packaging.
- Every untested item explicitly listed rather than implied to pass.
- Empty output from `git status --short`.
- The pushed fork branch URL.
- For remaining blockers, the minimum missing condition required to finish acceptance.

Do not create an issue or pull request. Commit and push fixes only to the fork branch.
