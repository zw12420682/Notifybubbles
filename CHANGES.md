# 0.48.69 — 非分屏列：收纳键贴右沿、复用分屏列几何

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
