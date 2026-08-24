# macbook-display-toggle

English | [简体中文](#简体中文)

A tiny native command-line tool that manually enables or disables a MacBook's built-in display while an external display remains active.

## Requirements

- Apple Silicon MacBook
- macOS 13 or later
- Xcode Command Line Tools
- At least one active external display when turning the built-in display off

## Build and use

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

Before every off operation, including `doff`, the tool verifies that at least one non-built-in display is active. It refuses to disable the built-in display if that check fails, preventing a no-display state through normal use.

The change lasts only for the current login session, so logging out or rebooting provides a recovery path. If an `on` operation fails, close and reopen the lid, reconnect the external display, log out, or reboot. Disabling a display may cause macOS to rearrange its windows; this tool does not preserve window positions.

## How it works

The tool dynamically resolves the private `CGSConfigureDisplayEnabled` or `SLSConfigureDisplayEnabled` API and calls it inside a `CGBeginDisplayConfiguration` / `CGCompleteDisplayConfiguration` transaction. It uses `CGSGetDisplayList` or `SLSGetDisplayList` to rediscover the built-in display after the public online-display list no longer contains it, and `CGDisplayIsBuiltin` to identify the panel.

These APIs are private and undocumented. A macOS update may change or remove them, and software using them is not eligible for the Mac App Store. Sleep, lid changes, and display hot-plugging may cause macOS to restore the built-in display; run the command again when needed.

---

## 简体中文

一个极简的原生命令行工具：在外接显示器保持活动时，手动开启或关闭 MacBook 内建屏幕。

## 系统要求

- Apple Silicon MacBook
- macOS 13 或更高版本
- Xcode Command Line Tools
- 关闭内建屏幕时，至少有一台处于活动状态的外接显示器

## 构建与使用

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

每次执行关闭操作时，包括通过 `doff` 调用，工具都会确认至少存在一台处于活动状态的非内建显示器。如果检测失败，工具会拒绝关闭内建屏幕，防止正常操作导致无屏幕可用。

显示配置仅对当前登录会话有效，因此注销或重启可以作为恢复手段。如果执行 `on` 失败，请依次尝试合上再打开上盖、重新插拔外接显示器、注销或重启。关闭显示器可能导致 macOS 重新排列窗口；本工具不保存窗口位置。

## 工作原理

工具通过动态符号解析加载私有的 `CGSConfigureDisplayEnabled` 或 `SLSConfigureDisplayEnabled` API，并在 `CGBeginDisplayConfiguration` / `CGCompleteDisplayConfiguration` 事务中调用。内建屏幕关闭并从公共在线显示器列表消失后，工具使用 `CGSGetDisplayList` 或 `SLSGetDisplayList` 重新定位它，并通过 `CGDisplayIsBuiltin` 识别内建面板。

这些 API 未公开且没有稳定性保证；macOS 更新可能改变或移除它们，使用这些 API 的软件也不能上架 Mac App Store。睡眠、开合上盖或插拔显示器可能让 macOS 恢复内建屏幕，届时重新运行命令即可。
