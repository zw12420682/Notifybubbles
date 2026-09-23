# NotifyBubbles 0.46.3

- 当前窗口缩成角落小窗后，气泡容器优先吸附到仍展开的最前方竖屏窗口。
- 没有符合条件的竖屏窗口时，返回屏幕右边缘。
- 跳过隐藏、屏幕外、小窗、横屏以及正在关闭的窗口，保留现有布局过渡动画。
- 吸附回退只调整气泡布局，不激活窗口、不触发自动关闭或重新设置窗口大小。
- 保留 0.46.2 横屏转回竖屏后关闭前一个分屏的规则。

上传：解压后，将 NotifyBubbles 内部文件及目录上传到仓库根目录覆盖。
验证：本地配置检查和压缩包检查；GitHub 编译及真机测试待完成。

---

# NotifyBubbles 0.46.2

- A 切换到横屏 B 时保留 A 的分屏窗口。
- 当前 B 变回竖屏并稳定 0.35 秒后，关闭保存的前一个 A 分屏窗口，不清除后台。
- 自动关闭开关关闭时取消待关闭记录。当前窗口收起、关闭或切换到第三个 App 时不再沿用旧记录。
- 保留原有的旧横屏窗口和角落小窗保护。
- 保留 0.46.1 的整体下移 10% 与 4pt 间距。

本地配置检查通过；尚需 GitHub 编译和真机验证 TrollOpen 窗口方向状态。

---

# NotifyBubbles 0.46.1

- 分屏时，一键清理按钮和图标容器整体下移屏幕高度的 10%。
- 容器与竖向分屏窗口的间距从 8pt 减少到 4pt。
- 保留过渡动画、最多七个图标的滚动容器，以及键盘弹出时的底部避让。
- 可用高度不足时缩短容器，通过上下滑动查看其余图标。

解压后，将 NotifyBubbles 文件夹里面的文件及目录上传到仓库根目录覆盖。完整上传可包含 .github，本次未修改编译流程。

已完成本地配置检查；需要 GitHub 编译和手机实测确认效果。

---

# 0.46.0

See UPDATE-0.46.0.md for badge, gap, half-retraction and keyboard changes.

# 0.45.2

See UPDATE-0.45.2.md for container sizing and opacity.

# 0.45.1

Fix the rail property type to NFBRail so the containerMode property compiles. No behavior changes from 0.45.0. Native compilation must be confirmed by GitHub Actions.

# 0.45.0

See UPDATE-0.45.0.md for the frosted scrolling container and keyboard avoidance.

# 0.44.3

See UPDATE-0.44.3.md for mini-window preservation.

# 0.44.2

See UPDATE-0.44.2.md for transition changes and remaining device checks.

# 0.44.1

See UPDATE-0.44.1.md for the desktop/split ordering fix.

# 0.44.0

See UPDATE-0.44.0.md for current behavior.

# 0.43.0

See UPDATE-0.43.0.md for edge alignment and the portrait-window replacement switch.

# 0.42.0

See UPDATE-0.42.0.md for the window-attached scrolling icon rail.

# 0.41.0

See UPDATE-0.41.0.md for rotation and initial split placement.

# 0.40.1

See UPDATE-0.40.1.md for the dark keyboard fix and installation checks.

# 0.40.0

See UPDATE-0.40.0.md for the new keyboard toggle, storage long-press cleanup, upload steps and device checks.

# 0.40.0 收纳按钮与抖动角标裁切修正

- 紧凑排列的行距比按钮高度少 6 点，旧滚动区域按行距计算高度导致底部内容越界。本版在顶部、底部及左侧增加 12 点绘制留白，保持实际图标排列间距不变。
- 抖动最大幅度由 8 点调整为 6 点，不超过展开图标距屏幕右边缘 7 点的余量。左侧留白用于防止角标左移时被滚动区域裁切。
- 同步修改内容高度、滚动偏移和中心点，保留右侧收纳位置与点击穿透；列表被限制在屏幕安全区域内。
- 保留 0.39.1 的 EDGE2 手势诊断，尚未接入未知回调。

上传 Sources、Preferences、scripts 文件夹和 control、README.md 覆盖原仓库即可；Makefile、.github 不变。若从 0.38.0 升级，还需上传 Tests。

本地完成几何范围与文件/压缩包检查，仍需 GitHub 编译及真机验证。

# 0.39.1 边缘手势诊断补充

用户日志确认边缘区域同时绑定 UITapGestureRecognizer 和 UILongPressGestureRecognizer，但 1800 条 EDGE 记录中没有 target/action 输出。不能据此认定接口不存在，也不能确认具体回调。

本版仅增加 EDGE2 日志：手势描述、目标容器类型、条目描述及实际字段名称/类型；不调用这些动作，不改变 0.39.0 的收纳布局或交互。安装重启桌面后打开一次分屏即可记录，不要求反复点击或长按。

从 0.39.0 升级可只上传 Sources/NFBEdgeInspection.h、control、Preferences/Resources/Info.plist、Preferences/Resources/Root.plist。也可覆盖整个 Sources 和 Preferences 文件夹以及 control、README.md。编译工作流不变。

本地仅检查文件与压缩包，尚未运行 Apple 编译及真机测试。

# 0.39.0 收纳外观与间距更新

本版以用户提供的 0.38.0 为基础，保留原有分屏手势、键盘规则和退出逻辑，返回组件仍不构建。

- 非分屏收起时，无未读应用合并为一个半透明圆角收纳按钮，带叠层图案与应用数量，不再显示一摞相互遮挡的 App 图标。
- 未读图标紧贴收纳按钮向上排列，图像边缘间距固定约 8 点；收纳应用再多也不增加空位。
- 点击收纳按钮展开，保留 20 秒无操作自动收起。收纳按钮没有长按退出 App 的动作。
- 分屏时继续展示原有图标排列与清理按钮；键盘出现时保留原来的缩回规则。

## 上传

上传新版 Sources、Tests、Preferences、scripts 文件夹及 control、README.md 覆盖原仓库。Makefile 和 .github/workflows/build.yml 与所提供的 0.38.0 相同，无需改。不要套外层 NotifyBubbles 文件夹。

## TrollOpen 边缘区域接口检查

从此前提供的 TrollOpenJB 1.5.2 隐根安装包中确认 TOJBClass012 有对象返回、无参数的实例方法：leftTouchRegion、rightTouchRegion、bottomTouchRegion、topLikeTouchRegions、bottomLikeTouchRegions、allEdgeTouchRegions。这些是区域获取接口，不等于点击/长按动作入口。

点击与长按目标方法有混淆，尚未确认绿色区域的准确动作回调。新版首次遇到浮窗时只读检查上述区域的 UIGestureRecognizer 目标与 selector，记录 EDGE 行；不调用、不替换手势，也不猜测执行混淆方法。

安装后打开一次分屏，用 Filza 查找 /var/tmp/nfb-debug.log；若不存在则查 /var/mobile/Library/Logs/nfb-debug.log。把包含 EDGE 的日志发来，可据实际绑定确定单击、长按的 target、selector 和方法参数。若私有手势结构不可读取，日志会显示不可用，仍需进一步适配。

## 验证状态

文件、LF 换行、plist 和压缩包完整性本地检查；未执行 Apple 编译或真机测试。GitHub 原生测试新增：全部已读只占一行、未读紧邻收纳、全部未读不留空收纳按钮。

真机重点：1/10/30 个已读应用加一条新通知，间距应相同；展开与 20 秒收起不误打开或退出应用；所有消息读完只剩收纳按钮；分屏、键盘与一键清理保持原行为。

---

以下保留 0.38.0 原说明与历史记录；其中旧收纳样式由本页上述规则替代。

# 通知悬浮气泡 · 0.38.0 测试工程

目标：iPhone 14、iOS 16.0.3、Dopamine RootHide，搭配 TrollOpenJB 1.5.2 隐根版。

本地仅通过文件和打包检查；Apple 编译、原生测试与真机验证尚未执行。

## 更新 GitHub 仓库

解压后进入 NotifyBubbles，将下列内容上传至仓库根目录覆盖，不要再套一层文件夹：

- Sources、Preferences、Tests、scripts 文件夹。
- Makefile、control、README.md。
- `NotifyBubbles.plist`（注入过滤器）。`NotifyBubblesBack.plist` 已随返回组件一起停用，不再需要上传。

另外将 `.github/workflows/build.yml` 替换为新版。提交后在 Actions 查看最新构建，成功后下载 Artifacts 中 NotifyBubbles-RootHide，解压安装 0.38.0 的 deb 并重启桌面。

**本版只注入 SpringBoard。** 单击关闭分屏窗口、长按退出 App 都在桌面进程内完成，不再需要目标 App 注入，因此无需在 App 内允许插件，也不用为了生效而重启目标 App。

## 交互规则

- 图标从下往上排列，最下方为第一位。当前 App（优先取 TrollOpen 当前展开浮窗，其次全屏前台 App）放在第一位，其余图标保留消息顺序；换位有动画。
- 设置新增“整组图标上下位置”：0 靠顶部，1 靠底部，默认 0.7。滑块移动整组图标，不改变排序；列表占满可用高度时没有剩余移动空间。
- 收到新通知的 App 在非当前 App 中优先排列。切到另一个 App 后，新当前 App 自动成为第一位。
- 当前展开浮窗对应图标保持伸出。其它图标伸出与缩回均约 0.6 秒，完整伸出后**停留 1 秒**。
- 点击有待处理通知的图标：按通知时间从新到旧提交系统通知默认动作；不消费其他 App 的通知。
- 点击当前浮窗图标且没有待处理通知：**将该分屏窗口放大到全屏**（等同点击 TrollOpen 绿色交互条）。
- 没有待处理通知且目标不是当前浮窗：通过 TrollOpen 打开浮窗；目标为全屏当前 App 时使用其专用前台转分屏入口。
- 点击边缘图标时，伸出动画与点击处理同时开始。
- 长按**当前分屏浮窗**对应的图标：**将浮窗缩小为小窗**（等同 TrollOpen 缩小浮窗操作），气泡同步缩回。
- 长按**其余图标**：气泡破裂消失，同时该 App **退出后台**（进程终止，等同 App 切换器上划卡片）。
- 分屏状态下，整排最上面多出一个**一键清理后台**气泡（红色垃圾桶图标）：点击后终止除当前浮窗 App 外的所有后台应用，气泡依次破裂消失。
- 双击不绑定任何操作：系统不再安装双击手势，单击因此在抬手时立即响应，不再等待第二次点击判定。
- 切换器逐张上划：对应图标破裂消失。一键清空：从当前最下方第一位开始依次破裂。
- 气泡角标显示该 App 在插件内的**未读通知条数**（而非系统图标角标）：分屏时收到新消息，对应气泡也会正常显示角标；打开该 App 后（通知被消费）角标随之消失。
- 图标大小、不透明度、锁屏/桌面/App 内独立显示开关保留。桌面角标仍由系统提供。

## 系统通知开关

已移除“各 App 新消息图标”页面，旧版本保存的 NotifyApp 开关不再读取。

只读查询系统通知授权状态，“允许通知”被关闭（Denied）时隐藏该 App 的通知来源图标；如果它仍有切换器卡片，图标继续正常显示。不会修改系统通知权限，不删除通知队列。设置约每 5 秒刷新一次。

跨 App 查询使用 SpringBoard 内的 `UNUserNotificationCenter initWithBundleIdentifier:`；接口缺失、异常或无回调时保留上次已知状态，首次未知时暂时保留图标，避免把切换器图标误关。这部分仍需 iOS 16.0.3 真机验证。

接口参考：[运行时头文件](https://github.com/nst/iOS-Runtime-Headers/blob/master/Frameworks/UserNotifications.framework/UNUserNotificationCenter.h)、[Apple 通知中心文档](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)。

## 版本要点

自 0.19.0 起（手势最终形态）：单击当前分屏浮窗的气泡 → **全屏**；长按该气泡 → **缩小浮窗**（0.28.0 起，此前为无动作）；长按其余气泡 → 破裂消失且该 App **退出后台**。

`fullscreenCurrentFloatingWindow` 的归属在不同证据间有冲突（0.7.0 时判定为浮窗实例方法，0.17.0 设备方法清单显示它在 `TOJBBarGestureBridge` 元类上），因此实现为**双路径探测**：先试桥接类方法，失败再试浮窗实例方法，两者都要求无参且返回 void/BOOL。

气泡收到未读后停留 `NFBHold = 1.0` 秒（另有 `NFBMotion = 0.6` 秒展开动画）。要改总时长，调整 `NFBManager.m` 顶部的常量即可。

自 0.20.0 起，**分屏窗口关闭/全屏时气泡同步缩回**。此前气泡的展开状态只在 0.5 秒一次的轮询里更新，加上 TrollOpen 自己的过渡动画，观感是「窗口先关完、气泡才开始缩」。现改为两层：

- **主动路径**（`beginRetracting:`）：调用 TrollOpen 接口**之前**先把该 App 标记为收回中并立刻刷新，缩回动画与窗口过渡在同一帧起步；同时清掉该 App 的 `expandedUntil`/`needsReveal`，否则点击自带的 1.6 秒伸出窗会在踏出的瞬间把它重新顶出去。0.8 秒后解除标记并按真实状态复核一次。
- **被动路径**（`floatingWatch`）：仅在**存在浮窗时**运行 0.05 秒的轻量轮询，发现 `NFBTrollVisibleApp()` 变化立即刷新。这样从 TrollOpen 交互条、App 退出或崩溃等外部途径关闭窗口也能同步收回，且平时不付任何额外开销。

自 0.21.0 起，气泡展开判定改为三级优先级：

1. **键盘弹出 → 全部缩回**（最高，覆盖下面两条）。
2. **有 App 处于 TrollOpen 分屏 → 整排气泡全部伸出且不收回**（此前只有占据浮窗的那个 App 的气泡伸出）。
3. 其余情况按各自的 `expandedUntil` 计时（未读到达后伸出 `NFBHold = 1.0` 秒）。

自 0.22.0 起补上键盘的**恢复**：键盘弹出时缩回的气泡会被记下，键盘收起后自动重新弹出——分屏那条靠 `floatingApp` 自然恢复，未读计时那条则把「键盘弹出瞬间仍在计时」的气泡暂存起来，键盘收起时用 `extendApp` 重新伸出，避免它们在打字期间悄悄过期。

键盘检测在 SpringBoard 进程内完成（`Sources/NFBKeyboard.m`）。第三方 App 的键盘窗口（`UIRemoteKeyboardWindow`）位于 App 自己的进程，SpringBoard 收不到 `UIKeyboardWillShowNotification`，因此同时取三个信号源，任一为真即判定键盘弹出：`UIKeyboardWillShow/DidShow` 通知、SpringBoard 自身窗口中可见的 `UIRemoteKeyboardWindow`/`UIKeyboardWindow` 键盘窗口（要求 `hidden == NO` 且 `alpha > 0.01` 且高度 ≥ 100）、以及直接探测 `SBUIController` 的 `isKeyboardVisible`/`keyboardVisible`/`isKeyboardOnScreen`。每次状态翻转会向调试日志写 `keyboard: up/down (notified=? window=? system=?)`，真机上一看即知哪个源生效。

自 0.23.0 起修掉一个致命误判：此前窗口源把 `UITextEffectsWindow`（文本放大镜/选区句柄窗口，SpringBoard 里**常驻且非隐藏**）也算作键盘，导致 `keyboardUp` 恒为真、气泡永远弹不出来。现改为只认真正的键盘窗口类名，并要求高度 ≥ 100 才判定为键盘。

自 0.24.0 起，分屏高亮方式从「跳到第一位」改为「透明度区分」：有 App 处于 TrollOpen 分屏时，该 App 的气泡**保持完全不透明（固定 1.0，不受设置里的图标不透明度滑杆影响）**，其余气泡变淡（0.29.0 起 `NFBFloatingDim` 由 0.5 下调为 0.3，即更透明），**位置不再变动**。只有普通前台 App（非分屏）才会被提升到列表首位。

自 0.25.0 起，**新消息也不再置顶**：收到新通知时，该 App 的气泡保持原有位置不动（新出现的 App 追加到列表末尾），不再跳到第一位。气泡顺序只由「前台 App 提升」决定。

0.26.0 同步更新了 `Tests/StoreTests.m` 的排序断言以匹配上述新行为（旧断言「Notification moves its app to first position」会使 Actions 构建失败）。

自 0.27.0 起，分屏时整排气泡的**纵向位置**自动调整到 0.80（`NFBFloatingPosition`，更靠屏幕底部），避免遮挡悬浮窗；分屏结束后恢复用户在设置里「整组图标上下位置」滑杆所设的原始位置。

自 0.28.0 起，长按当前分屏浮窗的气泡改为**缩小浮窗**（`NFBMinimizeCurrentFloatingWindow`，等同 TrollOpen 缩小浮窗操作），气泡同步缩回。该接口同样按「桥接类方法优先、浮窗实例方法兜底」双路径探测，并额外尝试 `shrinkFloatingWindows` 作为降级。

自 0.29.0 起，分屏高亮修正两点：分屏 App 的气泡**固定完全不透明**（alpha 1.0），不再受设置里「图标不透明度」滑杆影响（此前滑杆调低时高亮会跟着变淡、看不出来）；其余气泡的变淡系数 `NFBFloatingDim` 从 0.5 下调到 **0.3**，其余气泡更透明、对比更强。

自 0.30.0 起，改动四点：

1. **分屏时整排最上面新增「一键清理后台」气泡**（红色垃圾桶图标）。它只作为布局项存在，不进入 store、不参与排序；点击后终止除当前浮窗 App 外的所有后台应用，气泡依次破裂消失（`NFBClearAllID` 合成气泡 + `clearBackground`）。
2. **分屏时非高亮气泡改用固定变淡系数**（`NFBFloatingDim = 0.3`），不再乘以设置里的「图标不透明度」，避免滑杆调低时非高亮气泡几乎看不见。
3. **气泡角标改为显示插件内未读通知条数**（`store countForApp:`），而非系统图标角标：分屏时收到新消息，对应气泡也正常显示角标。
4. **打开 App 后角标消失**：记录被消费（或系统图标角标归零触发的兜底清理）后，`countForApp:` 归零，角标随之隐藏。

自 0.31.0 起，改动两点：

1. **键盘弹出时气泡整体下移到 0.54**（`NFBKeyboardPosition`）：键盘优先级最高，分屏还是全屏都生效，整排气泡避开键盘；键盘收起后恢复原位置（分屏的 0.80 或设置里的「整组图标上下位置」滑杆值）。
2. **分屏时收到新消息，对应气泡加入抖动动画作为提醒**（`shakeBubble:`，水平 CAKeyframeAnimation 抖动约 0.6 秒），抖动期间该气泡**保持完全不透明高亮**（`shakingApps` 集合临时强制 alpha 1.0），结束后恢复到分屏下的正常透明度（浮窗 App 1.0 / 其余 `NFBFloatingDim` 0.3）。

自 0.32.0 起，改动三点：

1. **键盘弹出时气泡下移位置由 0.54 改为 0.49**（`NFBKeyboardPosition`），分屏/全屏仍通用。
2. **分屏新消息抖动时长延长到 2 秒**：`shakeBubble:` 的水平关键帧动画 duration 由 0.6 秒改为 2.0 秒（衰减抖动，7 个来回），高亮时长同步延长到约 2.2 秒。
3. **气泡从下往上增**：新出现的 App 气泡改为插入列表首位（`NFBStore putApp` 的 `insertObject:atIndex:0`），配合 `NFBRowCenter`「第一个在最下面」的几何，新气泡从屏幕下方冒出、把已有气泡往上顶，不再是追加到最上面。

自 0.33.0 起，把「从下往上增」补全到**所有**新增气泡路径：

- 0.32.0 只改了「收到新通知的新 App」（`putApp`）；**switcher 同步出来的新 App（`pinApp`）仍是追加到最上面**。
- 现 `pinApp` 同样改为 `insertObject:atIndex:0`，并在 `tick` 里把 switcher 遍历改成**倒序**（`current.reverseObjectEnumerator`），这样一批 switcher 卡片同时出现时，最近使用的那个最后被 pin、落在最下面，保持 switcher 顺序且最下面为最新。

自 0.34.0 起，纠正「从下往上增」的语义（0.32.0/0.33.0 理解反了）：

- 正确语义是：**第一个（最早）气泡固定在屏幕下方不动，后续新气泡依次加在它上面（往上叠）**，即数据上「追加到末尾」。
- 0.32.0/0.33.0 把 `putApp`/`pinApp` 改成 `insertObject:atIndex:0`（新气泡抢最下面、把第一个顶上去），方向反了。
- 现 `putApp`、`pinApp` 都改回 `addObject`（追加），`tick` 的 switcher 遍历改回正序；新气泡加在已有气泡上方，第一个气泡位置不再变动。`promoteApp`（前台 App 提升贴底）保持不变。

自 0.35.0 起，真正实现「第一个气泡固定不动」：

- 0.34.0 只修正了数据顺序（新气泡往上加），但布局仍按「rail 顶部」定位（`top + (available-height)*position`），气泡增多时 rail 顶部往上、底部往下，表现为「中间向上下扩散」。
- 现改为**锚定 rail 底部**：`railFrame.y = anchor + (step - side/2) - height`，其中 `anchor = top + available*position`。第一个气泡（index 0）的中心恒等于 `anchor`（不随数量变化），新气泡依次往上叠，整排只向上生长、不再向下扩散。
- `position`（「整组图标上下位置」滑杆 / 分屏 0.80 / 键盘 0.49）语义从「整组位置」变为「第一个气泡中心在可用空间的 0=顶/1=底 位置」。

自 0.36.0 起，非分屏时**无未读的气泡折叠成一条细边**，尽量少遮挡屏幕：

- 非分屏时，只有**有未读**的气泡正常伸出显示；**无未读**的气泡缩回屏幕外、只留一条约 8pt 的细边（`NFBStackEdge`），且都堆叠到第一个气泡（最下面）的位置，重叠成一摞。
- **点击细边 → 散开**：无未读气泡展开，可正常点击操作；**20 秒无动作 → 自动收起**（`NFBStackHold`）。散开期间任何点击都会重新计时。
- 分屏时仍保持所有气泡伸出的原行为（`stacked` 仅在非分屏生效）。
- 实现：新增 `stackUntil` 计时（0 = 折叠）、常量 `NFBStackHold=20`/`NFBStackEdge=8`；布局循环按 `stacked` 决定缩回量和堆叠位置；`tapped:` 折叠态点击转散开，`acceptGesture` 散开期间重置计时。

自 0.37.0 起，修正两点：

1. **有未读的气泡不再被收纳**：0.36.0 用 `expandedUntil`（只持续约 1.6 秒的计时）判断「有未读」，计时一到气泡就被误判为无未读、折叠收纳。现改为用 store 里的未读计数 `countForApp: > 0` 判断——只要还有未读记录，气泡就一直正常伸出显示，直到打开 App 消费（或系统角标归零兜底清理）后才收纳。
2. **收纳后的气泡恢复「露出一半」**：0.36.0 收纳后只留约 8pt 细边（`NFBStackEdge`），太细不好看/不好点。现收纳的气泡改回用 `NFBRetraction(diameter)`（和以前缩回一样露出半个圆），仍然堆叠在最下面、重叠成一摞，只是露出程度恢复为一半。删除了不再使用的 `NFBStackEdge` 常量。

## 返回功能范围（0.18.0 起停用）

**自 0.18.0 起返回组件不再构建。** 单击改为关闭分屏，没有手势再驱动 App 内返回。该组件过滤 `com.apple.UIKit`，即会被加载进设备上**每一个 App**；停用后这份额外的启动开销消失，也不再需要在目标 App 内允许注入。源文件保留在 `Sources/`（`NFBAppBack.m`、`NFBBackRequest.*`、`NFBBackProtocol.h`、`NotifyBubblesBack.plist`），需要时在 Makefile 加回 `NotifyBubblesBack` 目标即可恢复。

以下为停用前的行为记录：

返回组件通过限时、有回复的进程间请求在目标 App 主线程处理，过期请求不执行。只操作当前可见页面，不模拟任意坐标点击。自 0.8.0 起由点击当前浮窗气泡触发。

自 0.9.0 起修复分屏下的窗口发现：TrollOpen 分屏时目标 App 场景可能处于后台（activationState 非 Foreground），且窗口可能被重新挂载到悬浮容器、level 抬高。返回组件不再按「前台场景 + 窗口层级」过滤，改为遍历本进程所有可见窗口、优先命中带导航栈或可返回 WebView 的窗口，并在找不到时降级到 keyWindow / 首个候选窗口逐一遍历。同时放宽 WebView 的 window 关系检查。

自 0.10.0 起：为 `NotifyBubblesBack` 补齐 `LIBRARIES = substrate`（缺失会导致 roothide/ellekit 不按 tweak 注入，constructor 不在目标 App 执行）；返回组件构造函数和每次请求处理都输出 `[NotifyBubblesBack]` 日志（注入确认、请求到达、窗口候选数、导航栈判定、pop 结果），便于真机用 `log stream` 定位断点；双击手势限定为「仅当前分屏浮窗对应的气泡」才切换横竖屏（此前任意气泡双击都会切换当前浮窗）。

自 0.11.0 起：确认 TrollOpen 分屏下「边缘右滑返回」可正常返回，而直接 `popViewControllerAnimated:` 找不到导航栈。诊断日志增强——打印每个 scene 的 activationState、每个候选窗口的 rootViewController 类名/windowLevel/isKeyWindow，并合并 `UIApplication.windows` 全局窗口列表（怀疑 TrollOpen 把 App 内容窗口挂到了 scene 之外），以及 `visible.parentViewController` 链。用于真机定位「分屏下窗口/导航栈到底在哪」。

自 0.17.0 起（真机日志驱动的三处修正）：
- **关闭分屏（双击）**：`closeCurrentFloatingWindow` 是 `TOJBBarGestureBridge` 的**类方法**（设备方法清单确认为元类上的 `B16@0:8`），此前误按浮窗实例查找 → 改为调用 `+[TOJBBarGestureBridge closeCurrentFloatingWindow]`，并保留浮窗实例的 `closeWindowWithoutTerminatingProcess*` 作为降级。
- **横竖屏切换（长按）**：`isLandscape` 在该 1.5.2 版本**不存在**（方法清单里只有 `containerOrientation` / `sceneOrientation`，均为 `q`），此前恒读到 NO 导致只能转横屏、转不回竖屏 → 改为读 `containerOrientation` 判断：竖屏(1)→转 3，否则→转 1。
- **返回（单击）**：返回协议改为携带**失败原因码**（`(request << 4) | status`），因为目标 App 自己的日志落在其沙盒内取不到。状态码：0 成功 / 1 未取到窗口 / 2 无返回动作 / 3 自定义导航按钮 / 4 转场或弹窗中 / 5 异常。据此给出精确的中文提示，无需再翻 App 沙盒日志。
- **TrollOpen 接口权威清单**（设备方法 dump）：桥接类 `TOJBBarGestureBridge` 只有 12 个类方法——`currentVisibleFloatingWindow`、`splitFrontmostApplication`、`closeCurrentFloatingWindow`、`fullscreenCurrentFloatingWindow`、`minimizeCurrentFloatingWindow`、`shrinkFloatingWindows`、`handleBarGestureCommand:`(B)、`isBarGestureCommandAvailable:`(B)、`queryBarGestureCommandState:completion:`。浮窗实例 `TOJBClass012` 共 317 个方法。
`/var/tmp/nfb-debug.log`（不可写时依次降级到 `/var/mobile/Library/Logs/nfb-debug.log` 与进程 NSTemporaryDirectory），用 Filza 打开即可。内容含：
- 主插件的单击/长按手势分发、关闭分屏与退出 App 的每一条候选路径及命中结果；
- 返回组件的 constructor、请求处理、scene 状态、每个窗口与控制器树、导航控制器深度搜索结果、返回结果；
- TrollOpen 浮窗对象与 `TOJBBarGestureBridge` 的真实方法名清单（按 close/float/rotate/orientation 等关键词过滤）——用于确定关闭/旋转的正确 selector（真机已证明 `closeCurrentFloatingWindow` 在该 1.5.2 版本不可调用）。
返回执行新增**深度搜索兜底**：当 `visible.navigationController` 关系被托管破坏时，改为向下遍历整个控制器树寻找带返回栈的 UINavigationController 并 pop。

支持标准 UINavigationController 的普通返回，以及 WKWebView 网页历史返回。已处于第一页、页面正在转场、出现警告对话框、导航栏有自定义左按钮或无法判断目标窗口时，不猜测操作并提示。Flutter、游戏、自定义导航等可能需要逐 App 适配；不保证所有 App 通用，也不把“退出桌面”当作返回。

TrollOpen 多浮窗模式仍依赖其 currentVisibleFloatingWindow 返回的当前窗口，未验证所有同时展开窗口。最小化为迷你窗口不再作为当前展开浮窗。

## 通知及运行边界

“待处理通知”指插件运行期间捕获且尚未通过气泡提交打开的通知，不等同于每个 App 内部真实未读数据库。系统撤回、清理和已观察到的桌面角标清零会更新本地队列。图标不跨重启桌面保存。

锁屏不显示只隐藏 UI，仍收集符合横幅条件的通知；解锁后在允许显示的位置恢复。无通知时的浮窗/返回要求先解锁；有通知时交给系统认证。TrollOpen 的 void 接口返回不代表浮窗已经成功呈现。

切换器每约 0.5 秒读取差异。第三方一键清理需实际移除卡片，仅结束进程并保留卡片不触发清理。状态无法读取时不按空列表处理。

## 编译与验收

GitHub 原生测试覆盖通知时间顺序、重复投递、已处理记录、前台排序不改变通知队列、底部第一位几何、位置范围、过期返回请求和 TrollOpen 接口契约。打包检查要求主插件与设置面板齐全，并确保停用的返回组件没有被重新打进 deb。

真机需要验证：

1. 图标第一位在最下方，切换全屏 App/浮窗时自动换位；上下位置滑块有效。
2. 浮窗中无通知时点击气泡将该分屏窗口放大到全屏；有通知时优先跳转通知。
3. 长按当前分屏浮窗的气泡不应有任何反应；长按非分屏图标应破裂消失且该 App 从后台退出。
3b. 收到未读消息时图标伸出约 1 秒后自动收回。
4. 系统关闭 App 通知后，无切换器卡片时图标隐藏；有卡片时继续显示。
5. 系统重新开启通知后重新显示对应已有图标；旧的独立开关没有影响。
6. 长按、逐张清理和一键清理保留破裂效果，批量清理从下方开始。
7. 前台全屏转浮窗后背景仍是桌面；锁屏、横屏、键盘与点击穿透正常。
