# macbook-display-toggle

English | [简体中文](#简体中文)

A minimal macOS menu bar app and CLI for manually enabling or disabling a
MacBook's built-in display while an external display is active.

## Install and use

Requirements: Apple Silicon MacBook, macOS 13 or later. Download the latest
DMG from [GitHub Releases](https://github.com/jinggqu/macbook-display-toggle/releases/latest),
open it, and drag **MacBook Display Toggle** to **Applications**.

The test build is ad-hoc signed and not notarized. On first launch,
Control-click the app and choose **Open**.

- Click the menu bar icon to open the controls.
- **Turn Built-in Display Off** is available only when an active external
  display exists.
- Redundant On or Off actions are disabled.
- Quitting restores the built-in display.
- Disconnecting the last external display triggers automatic recovery.
- Reconnecting an external display reapplies the last manually selected state.

## CLI

```sh
make

./build/display-toggle status
./build/display-toggle on
./build/display-toggle off
./build/display-toggle toggle
./build/don
./build/doff
```

Install the commands into `/usr/local/bin` with `sudo make install`.
`display-toggle` is the canonical command; `don` and `doff` are short aliases.

## Build a DMG

Build requirement: Xcode Command Line Tools.

```sh
make clean
make release
```

This creates `build/MacBook-Display-Toggle-v0.3-macOS-arm64.dmg` and its
`.sha256` checksum. The app uses private, undocumented SkyLight/CoreGraphics
APIs and may break after a macOS update.

## Safety

The shared control core refuses to disable the built-in display unless a
hardware-backed external display is active. While the built-in display is off,
the app combines display-change events with a three-second fallback safety
check and ignores virtual transition placeholders. The check stops as soon as
the built-in display is on. The last manual On or Off choice is remembered; an
automatic safety restore does not overwrite it. If recovery fails, reconnect
the external display, close and reopen the lid, log out, or reboot.

---

## 简体中文

一个极简的 macOS 状态栏应用和命令行工具，用于在外接显示器保持活动时，
手动开启或关闭 MacBook 内建屏幕。

## 安装与使用

系统要求：Apple Silicon MacBook、macOS 13 或更高版本。从
[GitHub Releases](https://github.com/jinggqu/macbook-display-toggle/releases/latest)
下载最新 DMG，打开后将 **MacBook Display Toggle** 拖入 **Applications**。

测试版本采用临时签名且未经过 Apple 公证。首次启动时，请按住 Control 单击应用并
选择“打开”。

- 单击状态栏图标打开控制菜单。
- 只有存在活动外接显示器时，才允许关闭内建屏幕。
- 已经处于目标状态时，对应操作会被禁用。
- 退出应用时会恢复内建屏幕。
- 拔掉最后一台外接显示器时会触发自动恢复。
- 重新接入外接显示器后，会恢复用户最后一次手动选择的状态。

## 命令行工具

```sh
make

./build/display-toggle status
./build/display-toggle on
./build/display-toggle off
./build/display-toggle toggle
./build/don
./build/doff
```

运行 `sudo make install` 可安装到 `/usr/local/bin`。`display-toggle` 是完整命令，
`don` 和 `doff` 是短命令。

## 构建 DMG

构建依赖：Xcode Command Line Tools。

```sh
make clean
make release
```

输出为 `build/MacBook-Display-Toggle-v0.3-macOS-arm64.dmg` 及其 `.sha256`
校验文件。应用使用未公开的 SkyLight/CoreGraphics API，macOS 更新可能导致其失效。

## 安全保护

没有真实硬件外接显示器时，共享控制核心会拒绝关闭内建屏幕。内建屏关闭期间，应用会
结合显示器变化事件与每三秒一次的兜底安全检查，并忽略系统切换期间的虚拟占位显示器；
内建屏点亮后检查立即停止。应用会记住最后一次手动选择；安全恢复不会覆盖该选择。
如果恢复失败，请重新连接外接显示器、合盖后重新打开、注销或重启。
