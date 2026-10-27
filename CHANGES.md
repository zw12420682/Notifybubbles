# 0.48.83 — 收纳态整列半露、左半个可点、5 秒真实无操作收纳（修正 0.48.82）

0.48.82 只在列的右缘（屏幕右缘 - 4）露出全屏 App 和收纳键的左半，其余未读图标仍完整；
半露又只靠“列内单行偏移”实现，屏幕坐标（`rowImageCenterX` / `toggleImageCenterX`）
在 `Tests/RailLayoutTests.m` 里是 413 / 417，而目标 390。本版按屏幕坐标重做：

1. **整列半露**：收纳且非分屏时，行内的未读 App、无通知的全屏 App、收纳键**全部**只露左半，
   `alpha 0.5`（`self.rail.alpha` / 收纳键 alpha 同一值，rail 的毛玻璃底也按 0.55 × 0.5）。
   没有通知、没有全屏 App 时仍是原来的 parked 收纳键；展开后恢复完整列与 1.0 alpha。
2. **屏幕坐标推导（唯一公式，只作用一次）**
   - 普通列：`NFBPlainRailFrameX(W, side, 4) = W - side - 4 - 7`（气泡内的 7pt 图标内缩），
     所以图标中心在 `W - 4 - 7 - d/2`，图标右缘在 `W - 4 - 7`。
   - 半露列：整条 rail 的 frame 原点改为 `NFBHalfHiddenBubbleOriginX(W, d, 4) = W - (4 + side/2) + 4`，
     收纳键（root/window 的直接子视图，与 rail 同一原点）用同一个 x。
     行仍在列内 `side/2`，故屏幕坐标 = `railX + 7 + d/2 = W`，左右任何直径、任何未读数量都一样。
   - 列宽不变、不做 transform、不给单行加第二次偏移；列右缘随之外移，
     `rail.clipsToBounds = NO`，屏幕（窗口宽 = 屏宽）才是唯一的裁切边界。
3. **左半个可点**：半露列的行有一半在 rail 的 bounds 之外，UIKit 在 gesture 之前就按 bounds 拒绝，
   所以 rail 的 `-hitTest:withEvent:` 对“点在 rail bounds 之外、且该行确实有屏幕内部分”的行
   返回它（`NFBVisibleMinX` + `NFBHalfHiddenAcceptsTouch`：只接受屏幕内的那半，半径不少于 22pt，
   圆外方角不接管）；rail 内的点仍走原 hitTest，窗口的命中逻辑不变。
   收纳键仍由自己的 tap/长按手势处理，半露/parked 时用同一策略只接受屏幕内那半。
   没有新增边缘控件，没有全屏透明接管。
4. **收纳键不再被 HideInScreenshots 吞掉点击**：该开关只禁用窗口根视图的交互（不改 alpha），
   而收纳键原先是根视图的子视图，于是外观正常但所有点击都丢失。现改为窗口的直接子视图
   （`initWithFrame` + `window addSubview:`），并去掉“开启时把根视图交互重新打开”的做法。
5. **过渡**：rail 只在 frame/alpha 真正变化时才起动画（20Hz 刷新不再每帧重置曲线），
   未变化时直接赋值（首帧也能落位）；所有动画保留 `BeginFromCurrentState` 且在
   ReduceMotion 下时长为 0；角标只在数量变化时弹一次，位置按图标几何计算（在图标左上角、
   不越出图标），图标/角标/透明度随同一次布局过渡。
6. **5 秒收纳只认真实操作**：`touchColumn` / `resetAutoCollapseTimer` 不再以 `edgeExpanded` 为前提，
   展开当帧的触摸也会盖章；`tickBody` 自动收纳后重新盖章，下次展开不会立刻被收；
   `scrollViewDidScroll` 只在 `tracking / dragging / decelerating` 时算操作，
   程序化 `contentOffset`（布局动画、`NFBSettleRailOffset`）不重置计时。

# 0.48.82 — 收纳态显示当前全屏 App（同列半露）

只改这一项需求，其余美化、分屏、点击/长按、行距字号、收纳键原规则未动。

1. **收纳态且非分屏时，当前全屏 App 即使没有通知也显示在同一条图标列里**
   - 成员：`refresh` 里从**已有的** `NFBCurrentWindowState()` 取 `frontApp/home/fullscreen`
     （按主队列回合共享的快照，不增加每帧全树扫描），满足
     `!split && !home && fullscreen && frontApp` 才成立；不靠 target 是否为 nil 推断分屏。
     `NFBExpandedAppHalfHidden(collapsed, split, hasFrontApp)` 即“收纳 && 非分屏 && 有全屏 App”。
   - 位置：该 App 追加在 `columnApps` **末尾**再加入同一条 `railApps`（不新增独立悬浮视图、
     不改原有未读顺序）；`displayApps` 只过滤按钮，不会重复。
   - 去重：若该 App 本身有通知，`[columnApps containsObject:]` 已为真，不再追加，
     于是完全走原“有通知完整显示”规则，同 App 只有一个图标（预期内的合理去重）。
   - 切前台：新 App 成为 `frontApp` → 替换异常行；旧 App 无通知立即从列里移除（收起动画），
     有通知则按原规则保留在未读里。
   - 回桌面：`state.home` 为真 → 无异常行，原“空通知 parked 半露收纳键”规则不变。

2. **半露：只有当前 App 图标和收纳键，且都在同一条列的同一 y/间距上**
   - 新增 `NFBHalfHiddenBubbleX(diameter) = diameter/2 - 7`：气泡中心右移该值后，
     图像中心（7pt 内缩 + diameter/2）正好落在图标列右缘（行右缘 = 屏幕右缘 - 4）。
     `alpha = 0.5`。两者的 y、step、直径、点击/长按完全沿用原值。
   - **不是整列 transform**：偏移只作用在 `exceptionRow` 的 `targetCenter.x`，其它未读图标
     仍是原 x、原 alpha、完整显示。
   - 收纳键：`toggleFrame.origin.x += NFBHalfHiddenBubbleX(diameter)`，只在异常行存在且非分屏时；
     因此即使全屏 App 在、收纳键也半露 `alpha 0.5`（`NFBToggleShouldFade` 原逻辑，
     有未读/无未读都一样）。
   - **不靠父视图裁切制造半露**：`NFBPlanRail` 新增 `edgeRail`，收纳且非分屏时把列 frame
     右缘推到物理屏幕边缘（宽度 +11，x = 宽度 - 新宽 - margin，仍留 4pt margin，
     右缘 `W - 4` 不留黑边），`plan.railViewportWidth` 仍为原图标列宽，`contentSize` 用新 frame 宽。
     子视图按“视图左边”摆放，于是各行在列内的偏移不变；半露气泡整块都在 viewport 内
     （不会被 `rail.clipsToBounds` 提前裁掉），实际图像中心就在屏幕右缘。
   - 滚动：`viewportResized` 会走原有的短动画；用户 `dragging/decelerating` 时仍不抢 offset，
     `touchColumn` 计时不变，5 秒真实无操作收纳由原 `tickBody` 负责。
   - 展开（`edgeExpanded`）、分屏、旋转都按 `collapsed && !split` 关掉 edgeRail / 异常行，
     回到原几何。

测试：`Tests/RailLayoutTests.m` 新增 “hidden fullscreen exception” 段——收纳+全屏
列 frame 右缘 = 屏宽、宽 +11、`railViewportWidth` 不变、y/直径/clearCenter 与普通收纳列一致、
异常行 y 不变、半露 x = diameter/2-7 且图像中心落在列右缘、未读行右缘不变（完整）、
半露气泡不被 viewport 裁切、有未读时同样半露且收纳键 x 不额外右移、分屏/展开忽略 edgeRail、
横屏仍成立。本机 portable 编译运行通过：
`clang -std=c11 -I Sources -include /tmp/shim.h Tests/RailLayoutTests.m -lm -o t && ./t`。
`scripts/test_rail_layout.py` 增加策略/接线静态检查（只此一需求、无额外槽位/整列 transform、
contentSize 跟随）。validate / test_scheme / test_cleanup / test_validator 全部通过。

真机未验证。

