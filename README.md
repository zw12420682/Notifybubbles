# NotifyBubbles 0.48.71 · 双方案源码工程（rootless + roothide）

iOS 16 越狱插件源码，一套代码同时出 **rootless** 和 **roothide** 两个包：

| 方案 | `THEOS_PACKAGE_SCHEME` | DEB Architecture | 安装位置 | 适用环境 |
| --- | --- | --- | --- | --- |
| rootless（默认） | `rootless` | `iphoneos-arm64` | `/var/jb/<...>` | Dopamine / palera1n 无根越狱等一切 `/var/jb` 引导器 |
| roothide | `roothide` | `iphoneos-arm64e` | 引导器根目录（无 `/var/jb` 前缀） | Dopamine RootHide |

依赖保持 `firmware (>= 16.0), firmware (<< 17.0), mobilesubstrate, preferenceloader`，
目标平台 `iphone:clang:16.5:16.0`（最低 16.0，覆盖 iOS 16.0.3）。

---

## 1. 本地构建

前置：macOS + Xcode Command Line Tools、[theos](https://github.com/roothide/theos)（推荐 roothide/theos，一套即可打两种包）、
`ldid`、`dpkg`、`xz`、`fakeroot`（`brew install ldid xz dpkg`）。

```sh
export THEOS=$HOME/theos
# SDK：把 theos/sdks 里的 iPhoneOS16.5.sdk 放好
```

### rootless（默认）

```sh
make clean
make package FINALPACKAGE=1
# 产物：packages/local.notifybubbles_0.48.71_iphoneos-arm64.deb
```

### roothide

```sh
make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
# 或者
THEOS_PACKAGE_SCHEME=roothide make package FINALPACKAGE=1
# 产物：packages/local.notifybubbles_0.48.71_iphoneos-arm64e.deb
```

要点：

* `THEOS_PACKAGE_SCHEME` 的默认值只在"未设置"时生效（`ifeq ($(strip ...),)`），命令行 / 环境变量始终优先。
* 传入 `rootless`、`roothide` 以外的值（如 `rootful`）会直接 `$(error ...)` 停止，避免打出色不对的包。
* `ARCHS = arm64 arm64e` 两种方案通用；Theos 会自动 `ldid -M` 签名。
* 打包前（`before-package`）会用 `control.<scheme>` 覆写 staging 里的 `Architecture:` 字段，
  并把 `layout/DEBIAN/postinst` 重新 `chmod 755`（ZIP/GitHub 网页上传会丢执行位）。
* 两个包**同一包名** `local.notifybubbles`，**不要同时安装**；换方案前先卸载旧包。

### 只跑静态校验（不需要 macOS）

```sh
python3 scripts/validate.py                 # 校验两种 scheme 的 control 片段
python3 scripts/validate.py --scheme roothide
python3 scripts/test_scheme.py              # 用 GNU make 模拟 scheme 切换 + 打包前 control 覆写
python3 scripts/test_cleanup.py             # postinst 清理逻辑
python3 scripts/test_package_parser.py
python3 scripts/test_validator.py
```

---

## 2. GitHub Actions

`.github/workflows/build.yml`：

1. `test` job（`macos-15-intel`）
   * `scripts/validate.py`、`test_validator.py`、`test_cleanup.py`、`test_scheme.py`
   * Objective-C 单测：`Tests/StoreTests.m`、`Tests/TrollOpenTests.m`、`Tests/TransitionTests.c`、
     `Tests/InterfaceTests.m`、`Tests/StateLedgerTests.m`
   * iOS 模拟器内的 UIKit 测试：`scripts/test_desktop_simulator.py`
2. `build` job，matrix 两个变体（`fail-fast: false`）

   | matrix.scheme | artifact | 检查 |
   | --- | --- | --- |
   | `rootless` | `NotifyBubbles-rootless` | `check_package.py --scheme rootless`（Architecture `iphoneos-arm64`、payload 必须在 `/var/jb` 下） |
   | `roothide` | `NotifyBubbles-roothide` | `check_package.py --scheme roothide`（Architecture `iphoneos-arm64e`、payload 不得带 `/var/jb`） |

   * 两个变体都使用同一份固定 commit 的 **roothide/theos**
     （`THEOS_REF=88506b2c…`）。roothide/theos 是 upstream theos 的超集，自带
     `rootless` 与 `roothide` 两套 scheme 与打包脚本，所以**不需要**条件安装官方 theos；
     若以后改用官方 theos，则只剩 rootless 可打。
   * SDK 来自 `theos/sdks` 固定 commit 的 `iPhoneOS16.5.sdk`，有 actions/cache 复用。
   * Actions 版本均为确实存在的稳定版本：`actions/checkout@v4`、`actions/upload-artifact@v4`、
     `actions/cache@v4`（原先写的 `@v7.0.1` 并不存在，会让 workflow 直接失败；`validate.py` 会拦住 `@vX.Y` 这类写法）。
   * 每个变体用 `check_package.py --scheme <scheme>` 钉死期望的 Architecture 与 payload 前缀。
   * `release-notes` job 把两个包的信息写进 Job Summary。

用法：`Actions → Build DEB (rootless + roothide) → Run workflow`，或 push 到 `main`/`master`。
构建完成后在对应 run 页面下载 `NotifyBubbles-rootless.zip` / `NotifyBubbles-roothide.zip`
（每个 artifact 内含 `.deb` 与 `SHA256SUMS-<scheme>.txt`）。

---

## 3. 安装

### 通用准备

* 需要先装好 **mobilesubstrate 兼容层**（libhooker / ElleKit / RootHide 自带的 substrate）与 **PreferenceLoader**。
* 插件只注入 `com.apple.springboard`（`NotifyBubbles.plist` → `Filter.Bundles = ["com.apple.springboard"]`）。
* 设置入口：设置 → 通知悬浮气泡 · Open 1.3.7 专用版。

### rootless（Dopamine 常规 / iOS 16.0.3）

1. 用 Sileo / Zebra 安装 `NotifyBubbles-rootless` 的 `.deb`，或命令行：
   ```sh
   /var/jb/usr/bin/dpkg -i local.notifybubbles_0.48.71_iphoneos-arm64.deb
   ```
2. 文件实际落在 `/var/jb/Library/MobileSubstrate/DynamicLibraries/NotifyBubbles.dylib`。
3. 注销（respring）SpringBoard。

### roothide（Dopamine RootHide）

1. 装 `NotifyBubbles-rootless` 以外的那个包：`local.notifybubbles_0.48.71_iphoneos-arm64e.deb`。
   RootHide 的包管理器（Sileo/Zebra）默认即可识别 `iphoneos-arm64e`。
2. 文件落在 RootHide 引导器自己的根（jitless 前缀），**不要**手动拷进 `/var/jb`。
3. RootHide 需要给 SpringBoard 放行：打开 **RootHide Manager → Apps → 找到「设置」/ SpringBoard**，
   确保 SpringBoard（以及需要注入的进程）处于已启用/已放行状态；
   若气泡不出现，在 RootHide Manager 里对 SpringBoard 执行一次
   「Re-Enable / 重新启用」再 respring。
4. 首次安装后 respring。

### 升级 / 卸载

```sh
dpkg -r local.notifybubbles        # 卸载（rootless 用 /var/jb/usr/bin/dpkg）
```
`layout/DEBIAN/postinst` 只清理本包旧版本遗留的已停用键盘文件，
不会跨引导器、跨包删除任何东西。

---

## 4. 目录结构

```
Makefile                    # ARCHS / TARGET / scheme 默认值与切换、before-package
control                     # 包身份 + Version + Depends（Architecture 为默认 rootless 值）
control.rootless            # Architecture: iphoneos-arm64
control.roothide            # Architecture: iphoneos-arm64e
NotifyBubbles.plist         # 只注入 SpringBoard 的过滤器
Sources/*.m *.h             # tweak 主体（18 个编译单元）
Preferences/                # 设置面板 bundle（NFBPreferences）
layout/                     # PreferenceLoader 入口 + DEBIAN/postinst
Tests/                      # macOS 上的 Objective-C/C 单测
scripts/                    # 静态校验、打包校验、模拟器测试、scheme 切换测试
.github/workflows/build.yml # 双方案 CI
```

---

## 5. 注意

* 本项目按 iOS 16.0.3（A16 / arm64e）校准，`Depends` 上限锁在 `< 17.0`。
* 扫描结论：源码中**没有**任何 iOS 17 独占 API 的直接调用（未使用 `-[UIWindowScene _sceneForApp]`、
  `UISheetPresentationController`、`UIWindowSceneGeometry` 等），所有私有类/选择子都通过
  `NSClassFromString` / `respondsToSelector:` / `NSMethodSignature` 运行时探测，
  缺失时静默降级，不会崩；详见 `CHANGES.md` 的「iOS 16.0.3 兼容性」一节。
* 若把 `THEOS_PACKAGE_SCHEME` 设为 `rootful`，会在解析 Makefile 阶段报错退出（本项目只出 rootless/roothide）。
