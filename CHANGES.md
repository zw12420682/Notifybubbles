# 0.48.72 — CI 几何回归测试修复（RailLayoutTests 编译 + 断言）

## 失败来源（CI run 40336888237 / job 121620748255 真实日志）

失败步骤 `Test column geometry (split, fullscreen, collapsed, empty)`，报错：

```
In file included from Tests/RailLayoutTests.m:18:
Sources/NFBRailLayout.h:36:9: error: unknown type name 'UIEdgeInsets'
```

日志不是网络问题，是测试源文件本身写坏了：

1. **语言/框架混用**。0.48.71 把测试改成「纯 C 端口 + 条件块」的形态，但文件顶部
   `#include "CoreGraphics/CoreGraphics.h"`，并在函数体里调 `UIEdgeInsetsMake(...)`、
   把结果赋给 `UIEdgeInsets`。该步骤只链接 `-framework Foundation`，Foundation 不导出
   `UIEdgeInsets`（那是 UIKit 的类型），所以 `NFBRailLayout.h` 的签名无法编译。
   同时 `.m` 被当作 Objective-C 编译时，C 端口代码并非条件编译，纯 C 端也走不到。
2. **一条断言本身写错了**（即使编译通过也会失败）：`close_(split.rail.origin.y, 422 + 422*0.05)`
   —— 分屏时首行由收藏夹 rail 占用，主轨在收藏夹之后才开始（119 + 9），
   正确值是 571.1 而不是 443.1。同理 `split.rail` 右沿不是 `windowMaxX + 4`，而是
   经 `NFBContainedRailX` 收紧后的位置（390 屏宽、195 宽分屏时为 261）。
   `toggle.y < H/2` 也是错的：测试里的分屏窗口本身在下半屏（y=422），继承来的行
   本来就在 443.1；这条断言把「不落到右下」写成了「必须在上半屏」。

## 修复

- `Tests/RailLayoutTests.m` 重写为**单一、纯 C 可编译**文件，不再混入 UIKit 类型：
  - 自定义 `NSBRailSafe { top, left, bottom, right }`（与 `UIEdgeInsets` 同字段同序），
    用 `NSBBuildSafeArea()` 转换成 `UIEdgeInsets`。链接 UIKit 时（tweak 本体）走
    `UIEdgeInsetsMake`，UIKit-less 编译（CI 的 `-framework Foundation`、本容器）走
    逐字段赋值，两条路径产物完全一致。
  - 保留 `-DNFB_RAIL_PORT=1` 的纯 C 形态（`NFBRailLayoutPort` 抑制 Foundation 导入），
    CI 与本容器都能直接编译执行。
- 断言改为与 `NFBPlanRail` 的真实语义一致，并**按需求覆盖每个确认点**，而不是删测试：
  - 分屏：行顶 = 窗口顶 + 5%，主轨在收藏夹块之后，水平用 `NFBContainedRailX` 收紧且不出屏，
    diameter = 设置值，分屏不显示桌面/收纳按钮，分屏永不 park（分屏样式不动）。
  - 非分屏展开：diameter 复用分屏实测值，**行顶 = 分屏行顶**（不再由全屏滑块从底部重算），
    控件 x = 屏宽 − 62 − 4（贴右沿），主轨在控件下方、宽 > 48（不是一条横线），
    收藏夹可见，永不半隐。
  - 窄分屏（340 宽窗口）收紧后的 diameter 被展开态完整复用。
  - 收纳（折叠）：diameter 与行顶同分屏，控件停在 `W − 7 − diameter/2`（图心落在右缘，
    即露左半），列本身贴右沿、宽 < 80 且高 > 宽（竖列非横条），收藏夹高度为 0
    （隐藏的收藏夹不吃高度），且带未读数时正确 park。
  - 空通知：尺寸/位置与折叠一致，`NFBToggleShouldFade` 为真（只露左半、alpha 0.5）。
  - 折叠下收藏夹数量 5 与 0 的主轨高度一致（收藏夹不偷高度）。
  - 有未读通知时折叠列不 park、不淡化（收起仅未读）。
  - 无缓存（首次布局）：行顶取设置值 90，不再落到屏底。
  - 旋转到 657 宽后缓存失效，diameter 回落到设置值 52。
  - NaN / ∞ / 0 屏宽输入：rail / toggle 全部有限且非负。
  - 长列表保留真实视口；`NFBSplitMetricsValid` 正负例。

## 验证（本容器，Alpine aarch64 / clang 19）

- 以 CI 同形命令（`-x objective-c -Wall -Wextra -Werror` + 桩 Foundation/CoreGraphics 头）
  编译并运行：`PASS: column geometry (split -> fullscreen expanded -> collapsed -> empty)`。
  （本容器没有 Apple SDK，桩头只提供 CG/UIEdgeInsets 几何类型，足以验证真实
  `NFBRailLayout.h` / `NFBGeometry.h` / `NFBContainerLayout.h` 的编译与断言。）
- `scripts/test_rail_layout.py`、`validate.py`、`test_validator.py`、`test_cleanup.py`、
  `test_scheme.py`、`test_package_parser.py` 全部 PASS。
- **未做**：iOS/UIKit 真编译、模拟器、真机行为。测试只覆盖纯几何函数，
  不覆盖动画时序、真实 safeArea、Open 分屏窗口实测值与真机渲染观感。

# 0.48.71 — 非分屏列：收纳键贴右沿、复用分屏列几何

## 根因（已在源码中确认，不是推测）

1. **收纳键跑到右下角**
   `NFBManager.m` 旧 1180 行 `desiredTop` 在非分屏时取 `railFrame.origin.y`，而这个
   `railFrame` 是先前用**全屏 position 滑块（默认 0.7）从底部重算**出来的普通轨。
   于是非分屏列顶部=滑块算出的底部位置，房子/收纳键自然出现在右下。
   `desktopActionFrame` 为空时还有一条 `slotY = railFrame.origin.y` 的兜底，同样落到底部。

2. **主轨被压成一条横线**
   旧 1213 行 `NFBFitContainers(room, side, step, self.favoriteApps.count, rowCount)`
   无论收藏夹 rail 是否被 `collapsed` 隐藏，都把 `favoriteApps.count` 当高度预算分走，
   主轨只剩几像素；同时收藏夹还拿走首行预算。

3. **分屏/非分屏图标大小不一致**
   分屏时 `diameter` 会被右侧实际空间收紧（`MIN(iconSize, room - 14)`），非分屏每帧
   直接重置成 `self.iconSize`，两态永远不同尺寸。

4. **收纳键判定用 `!target` 推断分屏**
   `layoutDesktopAction` 里 `toggleMode = !target`，而 TrollOpen 重建窗口期间分屏是
   `target == nil`，于是分屏中把桌面按钮当成收纳键（图标/透明度/长按都会错）。

## 修复

- 新增 `Sources/NFBRailLayout.h` 纯几何函数 `NFBPlanRail(...)`，`refresh` 只从它取
  rail / favorites / 收纳键 frame、diameter、parked。分屏与非分屏共用同一套几何。
- 分屏顶行仍用 `NFBSplitRailTop(splitWindow.y, h)`（原功能不动）；**非分屏改为复用
  缓存的分屏行 top**（`splitRailTop/rowsTop`）与 **实测分屏 diameter**，仅在水平方向
  贴右沿（`screenWidth - railWidth - 4`）。不再用全屏滑块另算 y。
- 缓存带有效性：`NFBSplitMetricsValid` 要求 diameter ≥16、屏宽与记录时的屏宽相差 ≤1
  （旋转/尺寸变化即失效），并跳过过渡态的 0 尺寸测量。无历史分屏时默认 `top`
  （`MAX(safeTop,48)+30`）与设置里的 iconSize。
- 收藏夹：`collapsed && !split` 时 favorites 计数按 0 传给 `NFBFitContainers`，
  favorites rail 不可见、不占高度；同时把**未读的收藏 app 放进主轨**（先 notified，
  再按原背景成员逻辑补最近三个），所以收纳态仍能看到未读收藏 app。
- 收纳键：位置=第一行（与分屏桌面按钮同一逻辑行），`collapsed && !split &&
  notifiedCount == 0` 时半藏：`origin.x = screenWidth - 7 - diameter/2`（图像中心正好
  在屏幕右缘），alpha 0.5。**展开态永不半隐**；无通知时 App 与清空按钮都不生成，
  只留收纳键。展开后仍露左半，点得到。
- 收纳键外观：非分屏=蓝左箭头（`chevron.left`，圆角方形=同一图像 0.23 圆角），展开后
  变右箭头；分屏保持原绿色房子 + 长按控制台，长按在收纳态禁用。
- 5 秒收纳：tick 只对 `edgeExpanded && !splitLayout` 生效；真实拖拽/减速/点击/长按才
  刷新 `lastInteractionAt`（`isTracking || isDragging || isDecelerating`），**程序滚动
  （reveal/settle offset）不再重置计时**。点 app 不再立即 `edgeExpanded = NO`，而是
  重置计时后按原逻辑打开 app。
- 清空 X：非分屏只清通知（长按行为与原代码一致，未改），VoiceOver 语义随 split 切换；
  分屏样式与文案完全不动。
- 所有 frame 经 `plan` 输出，NaN/∞ 输入都在入口清洗；`NFBPlanRail` 对 0 屏宽、零行、
  超长列表、宽分屏、旋转都给出有限的矩形。
- 未新增任何独立边缘控件：仍然只有原来的一个 `desktopActionButton`。

## 测试

- `Tests/RailLayoutTests.m`（CI 编译运行，macOS Foundation）：分屏基线 → 非分屏展开 →
  收纳 → 空通知，断言 top/diameter 复用、收藏夹隐藏不占高度、收纳半隐 x、空态尺寸与 y
  一致、旋转使缓存失效、NaN/∞ 不出 frame。
- `scripts/test_rail_layout.py`：静态守卫（不许再出现 `railFrame.origin.y` 计算行、
  不许把 favoriteApps.count 传进 FitContainers、toggleMode 必须来自显式 splitNow、
  停靠条件必须含 notifiedCount==0、只有一个收纳控件）。
- 本地（Alpine aarch64, clang 19）以 C 端口把同样的 `NFBRailLayout.h`/`NFBGeometry.h`/
  `NFBContainerLayout.h` 编译执行：`PASS: column geometry (split -> fullscreen expanded
  -> collapsed -> empty)`。iOS/UIKit 真编译与真机行为均**未验证**。

## 仍待真机确认

- 收纳键半隐位置在真机右缘的观感（尤其有 Home Indicator 时）。
- 展开自动收纳 5s 与点击 app 打开之间的实际节奏。
- 分屏中桌面按钮图标/间距未改动，需要截图对照确认「分屏原功能大小间距不动」。

## 版本说明

0.48.69 的 CI 在 test 作业的「iOS simulator desktop transfer」步骤失败
（`FAIL: automatic page roundtrip restores exact original page ... expected={402, 0}`）。
该步骤只编译 `Tests/DesktopHostTests.m` + `Sources/NFBDesktopHost.m`（sha256
fcadc159… 与 0.48.68 完全一致），与本次布局改动无关，属模拟器时序类偶发；但当前
GITHUB_TOKEN 无 actions:write 权限，无法重跑，因此以 0.48.70 重新触发 CI。

## 0.48.70 的 CI 修正

- 0.48.69 在模拟器桌面测试偶发失败（与本改动无关的 DesktopHost 未变），0.48.70 重跑时
  在新增的「Test column geometry」步骤失败：
  `NFBRailLayout.h:7: fatal error: 'UIKit/UIKit.h' file not found`
  —— 该测试用 `-framework Foundation` 编译，而头文件还导入了 UIKit。改为只导入
  Foundation（UIKit 类型经由 Foundation 转出，SpringBoard 端不受影响）。
- 验证：本容器用 clang 与桩头文件 `-fsyntax-only -Wall -Wextra -Werror` 通过；同一测试
  源文件以 `-DNFB_RAIL_PORT=1` 用纯 C 端口编译运行通过；故意改坏一条断言即失败（负向对照）。
