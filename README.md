# macbook-display-toggle

English | [简体中文](#简体中文)

A tiny native menu bar app and command-line tool that manually enable or disable a MacBook's built-in display while an external display remains active.

## Download

Download the latest `MacBook-Display-Toggle-*.dmg` from [GitHub Releases](https://github.com/jinggqu/macbook-display-toggle/releases/latest), open it, and drag **MacBook Display Toggle** to the **Applications** shortcut.

The current test release is ad-hoc signed because it does not yet have a Developer ID certificate or Apple notarization. On first launch, Control-click the app, choose **Open**, and confirm; alternatively use **System Settings → Privacy & Security → Open Anyway** after macOS blocks the first attempt.

## Requirements

- Apple Silicon MacBook
- macOS 13 or later
- Xcode Command Line Tools
- At least one active external display when turning the built-in display off

Build artifacts target arm64 and macOS 13.0 or later. Compilation, bundle validation, and private-symbol discovery have been checked on an M1 Mac running macOS 15.8; runtime behavior on other Apple Silicon models and macOS versions still requires device testing.

## Menu bar app

Build both the app and CLI, then open the app:

```sh
make
open build/MacBookDisplayToggle.app
```

- Click the menu bar icon to open the status and controls menu.
- Choose **Turn Built-in Display On** or **Turn Built-in Display Off**. An action is disabled when the display is already in that state; **Off** is also disabled when no active external display exists.
- Quitting restores the built-in display.
- If the external display is disconnected while the built-in display is off, the running app automatically restores the built-in display.

The app has no Dock icon and uses an ad-hoc local signature for testing. `make` directly creates `build/MacBookDisplayToggle.app`; no archive is needed for local use. Create a distributable DMG and checksum with:

```sh
make release
```

The resulting files are `build/MacBook-Display-Toggle-v0.2.1-macOS-arm64.dmg` and its `.sha256` checksum. The DMG is only a transport and installation container for the directory-based `.app`. A future production release should be signed with a Developer ID and notarized to avoid Gatekeeper warnings.

After downloading both Release assets into the same directory, verify the DMG with:

```sh
shasum -a 256 -c MacBook-Display-Toggle-v0.2.1-macOS-arm64.dmg.sha256
```

## Command-line tool

```sh
make

./build/display-toggle status
./build/display-toggle          # toggle
./build/display-toggle off
./build/display-toggle on

./build/doff                    # short alias for off
./build/don                     # short alias for on
```

Optionally install the full command and both aliases into `/usr/local/bin`:

```sh
sudo make install

display-toggle status
display-toggle toggle
doff
don
```

`display-toggle` is the canonical interface. `don` and `doff` are intentionally limited to one action each, making them convenient for Terminal use, Shortcuts, or hotkey launchers without replacing the readable full command.

## Safety

Before every off operation, including the app's **Off** action and `doff`, the shared control core verifies that at least one non-built-in display is active. It refuses to disable the built-in display if that check fails. The menu also disables actions that are redundant or unsafe. While the app is running, it restores the built-in display if the last external display is disconnected.

The change lasts only for the current login session, so logging out or rebooting provides a recovery path. If an `on` operation fails, close and reopen the lid, reconnect the external display, log out, or reboot. Disabling a display may cause macOS to rearrange its windows; this tool does not preserve window positions.

## How it works

The tool dynamically resolves the private `CGSConfigureDisplayEnabled` or `SLSConfigureDisplayEnabled` API and calls it inside a `CGBeginDisplayConfiguration` / `CGCompleteDisplayConfiguration` transaction. It uses `CGSGetDisplayList` or `SLSGetDisplayList` to rediscover the built-in display after the public online-display list no longer contains it, and `CGDisplayIsBuiltin` to identify the panel.

These APIs are private and undocumented. A macOS update may change or remove them, and software using them is not eligible for the Mac App Store. Sleep, lid changes, and display hot-plugging may cause macOS to restore the built-in display; run the command again when needed.

---

## 简体中文

一个极简的原生状态栏应用和命令行工具：在外接显示器保持活动时，手动开启或关闭 MacBook 内建屏幕。

## 下载

从 [GitHub Releases](https://github.com/jinggqu/macbook-display-toggle/releases/latest) 下载最新的 `MacBook-Display-Toggle-*.dmg`，打开后将 **MacBook Display Toggle** 拖到 **Applications** 快捷入口。

当前测试版采用临时签名，尚未配置 Developer ID 和 Apple 公证。首次启动时，请按住 Control 单击应用、选择“打开”并确认；如果第一次已经被 macOS 拦截，也可以前往“系统设置 → 隐私与安全性 → 仍要打开”。

## 系统要求

- Apple Silicon MacBook
- macOS 13 或更高版本
- Xcode Command Line Tools
- 关闭内建屏幕时，至少有一台处于活动状态的外接显示器

构建产物面向 arm64，最低系统版本为 macOS 13.0。目前已在运行 macOS 15.8 的 M1 Mac 上验证编译、应用包结构和私有符号解析；其他 Apple Silicon 型号及 macOS 版本仍需实机测试。

## 状态栏应用

构建状态栏应用及 CLI，然后打开应用：

```sh
make
open build/MacBookDisplayToggle.app
```

- 单击状态栏图标打开状态和控制菜单。
- 选择“开启内建屏幕”或“关闭内建屏幕”。如果内建屏幕已经处于目标状态，对应操作会被禁用；没有活动外接显示器时，“关闭”也会被禁用。
- 退出应用时会恢复内建屏幕。
- 内建屏幕关闭期间，如果最后一台外接显示器被拔掉，运行中的应用会自动恢复内建屏幕。

应用不显示 Dock 图标，测试构建使用本机临时签名。`make` 会直接生成 `build/MacBookDisplayToggle.app`，本机使用无需打包。可以生成便于分发的 DMG 及校验值：

```sh
make release
```

输出文件为 `build/MacBook-Display-Toggle-v0.2.1-macOS-arm64.dmg` 及对应的 `.sha256` 校验文件。DMG 只是目录型 `.app` 的传输和安装容器；未来正式版应使用 Developer ID 签名并完成 Apple 公证，以免出现 Gatekeeper 警告。

将两个 Release 附件下载到同一目录后，可以验证 DMG：

```sh
shasum -a 256 -c MacBook-Display-Toggle-v0.2.1-macOS-arm64.dmg.sha256
```

## 命令行工具

```sh
make

./build/display-toggle status
./build/display-toggle          # 切换
./build/display-toggle off
./build/display-toggle on

./build/doff                    # 关闭的短命令
./build/don                     # 开启的短命令
```

也可以将完整命令及两个短命令安装到 `/usr/local/bin`：

```sh
sudo make install

display-toggle status
display-toggle toggle
doff
don
```

`display-toggle` 是规范、完整的命令接口；`don` 和 `doff` 分别只执行开启和关闭，适合在终端、快捷指令或热键启动器中使用，同时保留完整命令的可读性。

## 安全保护

每次执行关闭操作时，包括选择应用中的“关闭”或通过 `doff` 调用，共享控制核心都会确认至少存在一台处于活动状态的非内建显示器。如果检测失败，工具会拒绝关闭内建屏幕。菜单还会禁用重复或不安全的操作。应用运行期间，如果最后一台外接显示器被拔掉，还会自动恢复内建屏幕。

显示配置仅对当前登录会话有效，因此注销或重启可以作为恢复手段。如果执行 `on` 失败，请依次尝试合上再打开上盖、重新插拔外接显示器、注销或重启。关闭显示器可能导致 macOS 重新排列窗口；本工具不保存窗口位置。

## 工作原理

工具通过动态符号解析加载私有的 `CGSConfigureDisplayEnabled` 或 `SLSConfigureDisplayEnabled` API，并在 `CGBeginDisplayConfiguration` / `CGCompleteDisplayConfiguration` 事务中调用。内建屏幕关闭并从公共在线显示器列表消失后，工具使用 `CGSGetDisplayList` 或 `SLSGetDisplayList` 重新定位它，并通过 `CGDisplayIsBuiltin` 识别内建面板。

这些 API 未公开且没有稳定性保证；macOS 更新可能改变或移除它们，使用这些 API 的软件也不能上架 Mac App Store。睡眠、开合上盖或插拔显示器可能让 macOS 恢复内建屏幕，届时重新运行命令即可。
