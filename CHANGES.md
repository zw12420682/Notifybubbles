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

