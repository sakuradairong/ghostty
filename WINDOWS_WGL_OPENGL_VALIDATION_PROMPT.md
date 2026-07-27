# Windows WGL/OpenGL 4.3 Core Validation Agent Prompt

你正在真实 Windows 10/11 x64 环境中完善 Ghostty 原生 Windows 应用的 WGL/OpenGL 初始化。请直接检查代码、构建、运行、诊断和修复，不要只给建议或分析报告。

## 仓库

- 仓库：<https://github.com/sakuradairong/ghostty.git>
- 分支：`feature/windows-native-app`
- 预期最低 HEAD：`0e8150875`
- 对照项目：<https://github.com/amanthanvi/winghostty.git>
- winghostty 对照版本：`v1.3.120`，提交 `0fa9af9e0`

不得创建 issue 或 PR。发现问题后直接修复、测试、提交并推送到 fork 的 `feature/windows-native-app` 分支。

## 目标

确认当前 Ghostty Windows runtime 使用真正的 OpenGL 4.3 Core Profile，而不是仅通过传统 `wglCreateContext` 接受驱动默认提供的 compatibility context。

需要保证：

1. 使用临时 legacy WGL context 加载 `wglCreateContextAttribsARB`。
2. 最终上下文显式请求 OpenGL 4.3。
3. 最终上下文显式请求 Core Profile。
4. 不支持 OpenGL 4.3 Core 时立即、明确且可诊断地失败。
5. 临时 context、最终 context、HDC 和 HWND 的资源生命周期正确。
6. Ghostty renderer 能在最终 context 上成功初始化和绘制。
7. 不引入 context 泄漏、DC 泄漏、线程绑定错误或重复设置 pixel format。
8. 保留 Win32/WGL 原生实现，不引入 GLFW、ANGLE、Qt、GTK 或其他 GUI/runtime 依赖。

## 先检查现状

执行：

```powershell
git clone -b feature/windows-native-app https://github.com/sakuradairong/ghostty.git
cd ghostty
git pull --ff-only
git rev-parse HEAD
git status --short
```

重点阅读：

```text
src/apprt/windows/WGL.zig
src/apprt/windows/Surface.zig
src/apprt/windows/App.zig
src/apprt/windows/win32.zig
src/renderer/
src/build/
```

另行克隆 winghostty，只作为实现对照：

```powershell
git clone https://github.com/amanthanvi/winghostty.git ..\winghostty
cd ..\winghostty
git checkout v1.3.120
```

检查其 `src/apprt/win32.zig`，特别关注：

- `createGLContext`
- `wglCreateContext`
- `wglMakeCurrent`
- `SwapBuffers`
- OpenGL capability diagnostics

不要直接复制 winghostty 的传统 `wglCreateContext` 方案。它由驱动决定上下文版本和 profile，不等同于显式的 OpenGL 4.3 Core Profile。

## 正确的 WGL 初始化流程

确认或实现以下流程：

1. 对目标 HWND 调用 `GetDC`。
2. HWND 的窗口类必须包含 `CS_OWNDC`。
3. 选择支持以下能力的 pixel format：
   - `PFD_DRAW_TO_WINDOW`
   - `PFD_SUPPORT_OPENGL`
   - `PFD_DOUBLEBUFFER`
   - RGBA
   - 合理的 color、alpha、depth 和 stencil bits
4. 对每个 HWND 只调用一次 `SetPixelFormat`。
5. 调用 `wglCreateContext` 创建临时 legacy context。
6. 将临时 context 设为当前 context。
7. 使用 `wglGetProcAddress` 加载 `wglCreateContextAttribsARB`。
8. 拒绝 `wglGetProcAddress` 返回的无效哨兵值：
   - `null`
   - `1`
   - `2`
   - `3`
   - `-1`
9. 通过 `wglCreateContextAttribsARB` 创建最终 context，至少包含：

```text
WGL_CONTEXT_MAJOR_VERSION_ARB = 4
WGL_CONTEXT_MINOR_VERSION_ARB = 3
WGL_CONTEXT_PROFILE_MASK_ARB = WGL_CONTEXT_CORE_PROFILE_BIT_ARB
```

10. Debug 构建可以在驱动支持时申请 `WGL_CONTEXT_DEBUG_BIT_ARB`，但不得因为驱动不支持 debug context 而让正常 Release 构建失败。
11. 解除临时 context 的当前绑定。
12. 将最终 4.3 Core context 设为当前。
13. 删除临时 context。
14. 查询并记录：
    - `GL_VENDOR`
    - `GL_RENDERER`
    - `GL_VERSION`
    - `GL_SHADING_LANGUAGE_VERSION`
    - `GL_MAJOR_VERSION`
    - `GL_MINOR_VERSION`
    - `GL_CONTEXT_PROFILE_MASK`
    - `GL_CONTEXT_FLAGS`
15. 验证：
    - major > 4，或 major == 4 且 minor >= 3
    - `GL_CONTEXT_PROFILE_MASK` 包含 `GL_CONTEXT_CORE_PROFILE_BIT`
16. 验证失败时释放所有已创建资源并返回明确错误。
17. 只有验证成功后才初始化 Ghostty renderer。

## 错误和诊断要求

不要只返回笼统的 “OpenGL unavailable”。至少区分：

- `GetDC` 失败
- `ChoosePixelFormat` 失败
- `SetPixelFormat` 失败
- 临时 context 创建失败
- 临时 context 绑定失败
- `wglCreateContextAttribsARB` 不可用
- 4.3 Core context 创建失败
- 最终 context 绑定失败
- 查询到的 OpenGL 版本低于 4.3
- 查询到的 context 不是 Core Profile
- Ghostty renderer 初始化失败
- `SwapBuffers` 失败

记录 Win32 `GetLastError`，并在适用时记录 OpenGL 错误。

如果应用是 Windows GUI subsystem，不能依赖用户能看到 stderr。启动失败时应同时满足至少一种可观察方式：

- 写入明确日志文件
- 显示包含具体失败阶段的 `MessageBoxW`
- 现有 Ghostty 日志系统能保留错误

错误消息应包括显卡和驱动能提供的信息，并明确说明：

> Ghostty requires an OpenGL 4.3 Core Profile context.

## 资源生命周期检查

重点检查所有错误路径：

- `GetDC` 成功后，失败路径必须 `ReleaseDC`。
- 创建的临时 HGLRC 必须删除。
- 创建的最终 HGLRC 必须删除。
- 删除当前 context 前必须先调用 `wglMakeCurrent(null, null)`。
- 不得在仍被其他线程绑定时删除 context。
- 每个 Surface 只能拥有自己的 HWND、HDC 和 HGLRC。
- 窗口销毁顺序应为：
  1. 停止 renderer 使用 context
  2. 将 context 从线程解除绑定
  3. 删除 HGLRC
  4. `ReleaseDC`
  5. 销毁 HWND 或完成窗口销毁
- 多窗口关闭一个 Surface 时不得影响其他 Surface 的 context。
- 重绘时仅在需要时调用 `wglMakeCurrent`。
- `SwapBuffers` 必须使用与最终 context 对应的 HDC。

## 构建和静态验证

在 Visual Studio 2022 Developer PowerShell 中执行：

```powershell
zig fmt --check src/apprt/windows
zig build test -Dtarget=x86_64-windows-msvc -Dapp-runtime=none '-Dtest-filter=default runtime'
zig build test-lib-vt -Dtarget=x86_64-windows-msvc '-Dtest-filter=PageList Pin row movement clamps across mixed-width pages'
zig build -Dtarget=x86_64-windows-msvc -Doptimize=ReleaseSafe
```

确认：

```powershell
Test-Path .\zig-out\bin\ghostty.exe
```

检查最终 EXE：

- 是 x86-64 Windows GUI executable。
- 正确链接 `opengl32`、`gdi32` 和 `user32`。
- 不意外依赖 MinGW runtime DLL。
- 不存在未解析 WGL/OpenGL 符号。

## 原生运行验收

在真实交互式 Windows 桌面执行：

```powershell
.\zig-out\bin\ghostty.exe
```

必须通过日志或调试器观察并记录：

1. 最终 context 的 OpenGL 版本至少为 4.3。
2. `GL_CONTEXT_PROFILE_MASK` 包含 `GL_CONTEXT_CORE_PROFILE_BIT`。
3. Ghostty renderer 初始化成功。
4. 首帧正常显示，不是黑屏、白屏或未刷新窗口。
5. shell prompt 正常显示。
6. 执行 `echo GHOSTTY_WGL_CORE_OK` 有正确输出。
7. 调整窗口尺寸时终端正常重绘。
8. 快速调整尺寸 30 秒，无崩溃和花屏。
9. 最小化和恢复后正常重绘。
10. 最大化和恢复后正常重绘。
11. 全屏进入和退出后正常重绘。
12. 创建至少五个窗口，每个窗口拥有独立可用 context。
13. 关闭其中一个窗口不影响其他窗口。
14. 连续启动和关闭应用 20 次。
15. 退出后 Task Manager 中没有残留 Ghostty 进程。
16. Windows Event Viewer 中没有应用崩溃记录。

不得把 MSVC 编译通过当作上述原生运行测试通过。

## 负面路径验证

必须验证不支持条件下能够安全失败。优先采用不会破坏系统的方式，例如增加仅 Debug/测试构建可用的内部版本请求覆盖，不要修改用户显卡驱动。

建议把 context attributes 构造和版本/profile 验证拆成纯函数，并添加单元测试，覆盖：

- 4.2 Core：拒绝
- 4.3 Core：接受
- 4.6 Core：接受
- 4.3 Compatibility：拒绝
- 4.6 Compatibility：拒绝
- 缺失 profile mask：拒绝
- `wglCreateContextAttribsARB` 不可用：明确失败
- `wglGetProcAddress` 的 `null` 和 `1`、`2`、`3`、`-1` 哨兵值：明确拒绝

如果可以安全注入一个不可实现的版本，例如 99.0，验证应用：

- 不崩溃
- 不泄漏资源
- 显示或记录明确错误
- 不继续进入 renderer 初始化
- 不留下残余进程

不要永久保留面向用户的危险测试开关。测试注入必须限制在测试或 Debug 构建。

## 与 winghostty 的对比结论

在最终报告中明确说明：

1. winghostty `v1.3.120` 使用传统 `wglCreateContext`。
2. 传统接口通常返回由驱动决定的 compatibility context。
3. 它可能提供 OpenGL 4.3 功能，但没有在 context 创建时显式保证 4.3 Core Profile。
4. 当前分支使用 `wglCreateContextAttribsARB` 明确建立 4.3 Core Profile。
5. 两者使用的终端 renderer 都来自 Ghostty OpenGL pipeline。
6. 差异主要在 WGL context 契约和失败时机，不意味着 renderer 完全不同。
7. Core Profile 本身不必然提高性能，价值在于能力契约、可预测性和诊断清晰度。

## 修复流程

如发现问题：

1. 建立最小复现。
2. 实现最小且可维护的修复。
3. 保持 WGL 逻辑集中在 `WGL.zig`，不要把更多平台细节堆入 `App.zig`。
4. 为可纯函数化的版本/profile/函数指针验证增加测试。
5. 执行 `zig fmt`。
6. 运行相关测试。
7. 重新运行完整 MSVC ReleaseSafe 构建。
8. 重新执行真实 Windows 运行验收。
9. 执行：

```powershell
git diff --check
git status --short
```

10. 创建清晰提交，例如：

```text
windows: enforce OpenGL 4.3 core contexts
```

11. 推送到：

```text
https://github.com/sakuradairong/ghostty.git
feature/windows-native-app
```

不得创建 issue 或 PR。

## 最终报告

报告必须包含：

- Windows 版本和 build number
- CPU、GPU、显卡驱动版本
- Zig、Visual Studio 和 Windows SDK 版本
- 最终提交 SHA
- 所有修改文件
- 精确构建和测试命令
- 每项测试的 Passed、Failed 或 Blocked
- `GL_VENDOR`
- `GL_RENDERER`
- `GL_VERSION`
- `GL_SHADING_LANGUAGE_VERSION`
- `GL_MAJOR_VERSION` 和 `GL_MINOR_VERSION`
- `GL_CONTEXT_PROFILE_MASK`
- 是否确认 `GL_CONTEXT_CORE_PROFILE_BIT`
- 多窗口和资源生命周期测试结果
- 负面路径测试结果
- Windows Event Viewer 检查结果
- 所有未测试项目
- 推送后的分支 URL
- 最终 `git status --short` 必须为空

不要在没有观察真实运行结果时声称 OpenGL 4.3 Core、WGL 渲染或多窗口已经验收通过。
