# MenuFold · 折叠菜单栏

一个使用 Swift、AppKit 和 Objective-C 构建的原生 macOS 菜单栏收纳工具。

## 功能

- 点击顶部“收纳”箭头，展开或收起菜单栏图标。
- 鼠标悬停约半秒自动展开，可在设置中关闭。
- 按应用图标和名称选择需要收纳的应用，支持整行勾选。
- 调整第三方应用图标间距，提供紧凑、适中、系统默认、宽松四档，支持恢复调整前配置。
- 可选 10 秒、30 秒或 1 分钟后自动收起。
- 支持启动后收起和登录 Mac 时启动。
- 右键或 Option 点击菜单栏入口打开设置菜单。
- 提供 Control + Option + Command + B 快捷键，以及设置中的“恢复顶部按钮”。

## 系统要求与验证范围

构建目标为 Apple Silicon Mac、macOS 14 及以上，需要 Apple Command Line Tools 或 Xcode 提供的 Swift 和 Clang 编译器。当前构建脚本生成 arm64 应用。

0.1.6 已在 macOS 27.2 上验证安装、应用选择、收起后菜单栏入口保留、点击展开和实际鼠标悬停展开。

0.1.7 已验证四档间距偏好的写入与读回、连续调整后保留首次备份，以及恢复原始值和数据类型。独立 AppKit 测试应用的间距变化已通过实际视觉对照确认。

macOS 14–26 的分隔线收纳路径、多显示器、全屏模式、重新登录后的自动启动，以及其他应用前台时的全局快捷键，仍需进一步实测。快捷键在应用设置窗口内已验证。

macOS 27 的实现依赖系统非公开接口 `MenuBarClientCore`，在运行时检测其可用性。后续 macOS 更新可能影响兼容性。应用使用本机构建的临时签名，尚未经过 Apple 公证或 App Store 审核。

## 构建和安装

```sh
xcode-select --install
git clone https://github.com/EnterBoom/menufold.git
cd menufold
zsh build.sh --install
open "/Applications/折叠菜单栏.app"
```

已安装 Command Line Tools 或 Xcode 时，可以跳过第一条命令。

构建脚本会生成 `build/折叠菜单栏.app`，`--install` 参数将应用复制到 `/Applications`，并注册到 LaunchServices。安装需要当前账户具有该目录的写入权限。只运行 `zsh build.sh` 可完成本地构建。

**macOS 27 请从 `/Applications/折叠菜单栏.app` 启动。** 相同收纳机制在应用程序目录以外运行时，存在隐藏自身菜单栏入口的已知问题。安装到“应用程序”后，菜单栏入口的保留、点击和悬停展开已通过实测。[兼容性问题说明](https://github.com/dwarvesf/hidden/issues/360#issuecomment-5729243602)

## 使用

### macOS 27 及以上

1. 打开应用，点击“选择收纳应用”。
2. 通过应用图标和名称勾选需要收纳的应用，再保存。
3. 点击顶部“收纳”箭头收起或展开图标。
4. 开启悬停展开后，收起时先移开鼠标，再移回入口停留约半秒。

同一应用的多个图标会一起收纳，系统图标保持可见。列表来自运行中的应用，其中部分应用可能没有菜单栏图标。选择列表显示应用自身的图标，部分软件的菜单栏符号可能不同。

### macOS 14–26

按住 Command，将需要收纳的图标拖到分隔线左侧，将常用图标和箭头留在右侧，再点击箭头收起或展开。这条兼容路径尚未完成实际设备验收。

### 设置与恢复

右键或 Option 点击菜单栏入口打开设置菜单。再次双击应用可重新打开设置。入口异常时，可以在设置中点击“恢复顶部按钮”。退出应用会释放收纳限制，恢复图标显示。

设置窗口打开或整理图标时暂停自动收起。登录启动使用 macOS 登录项服务，系统可能要求在“系统设置 → 通用 → 登录项与扩展”中确认。

### 第三方图标间距

打开设置中的“第三方图标间距”，选择档位，再点击“应用间距”。

| 档位 | 间距参数 |
| --- | --- |
| 紧凑 | 4 |
| 适中 | 8 |
| 系统默认 | 清除本机覆盖值，沿用系统或已有全局配置 |
| 宽松 | 24 |

这些数值是系统间距参数，实际图标占位宽度还取决于应用的实现。偏好写入当前用户在本机的 `NSStatusItemSpacing` 与 `NSStatusItemSelectionPadding`。相关应用在下次启动时采用新间距，重新登录可统一应用到当次启动的菜单栏应用。

在 macOS 27 上，这项调整的范围为第三方应用图标。Wi-Fi、电池、时钟、控制中心和系统输入菜单的图标间距由 macOS 自身管理。[同类实现的范围说明](https://github.com/nlink-jp/menubar-spacer#limits)

首次点击“应用间距”时自动保存调整前配置。点击“恢复调整前”可恢复当时的原值，包括原始数据类型和未设置的状态。备份保存在 `~/Library/Application Support/MenuFold/spacing-original.plist`。恢复后，相关应用在下次启动时采用恢复后的间距。

## 本地数据

应用通过 `UserDefaults` 在本机保存收纳名单和设置，使用 `NSWorkspace` 获取运行中的应用及其图标。当前实现无需辅助功能或屏幕录制权限。

间距设置保存于 macOS 的当前用户、本机全局偏好中，首次调整的备份独立保存在上述应用支持目录。

## 项目结构

```text
Sources/
  App.swift                 菜单栏入口、收纳状态、自动收起与悬停
  ApplicationPicker.swift   应用图标与勾选列表
  MenuBarSpacing.swift      本机间距偏好、原始备份与恢复
  SettingsController.swift  原生设置窗口
  NativeVisibility.h        macOS 27 兼容桥接声明
  NativeVisibility.m        运行时加载菜单栏可见性接口
  RecoveryShortcut.swift    系统快捷键注册
  main.swift                应用入口
scripts/
  make-icon.swift           应用图标生成
Info.plist
build.sh
```

## 许可证与致谢

项目采用 MIT 许可证。[LICENSE](LICENSE)

macOS 27 兼容机制参考并适配了 Hidden Bar 的原生可见性桥接实现，安装位置相关问题也参考了该项目的排查记录。相关版权和 MIT 许可证见第三方声明。[Hidden Bar](https://github.com/dwarvesf/hidden) · [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
