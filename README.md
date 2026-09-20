# 通知悬浮气泡 · 0.18.0 测试工程

目标：iPhone 14、iOS 16.0.3、Dopamine RootHide，搭配 TrollOpenJB 1.5.2 隐根版。

本地仅通过文件和打包检查；Apple 编译、原生测试与真机验证尚未执行。

## 更新 GitHub 仓库

解压后进入 NotifyBubbles，将下列内容上传至仓库根目录覆盖，不要再套一层文件夹：

- Sources、Preferences、Tests、scripts 文件夹。
- Makefile、control、README.md。
- `NotifyBubbles.plist`（注入过滤器）。`NotifyBubblesBack.plist` 已随返回组件一起停用，不再需要上传。

另外将 `.github/workflows/build.yml` 替换为新版。提交后在 Actions 查看最新构建，成功后下载 Artifacts 中 NotifyBubbles-RootHide，解压安装 0.18.0 的 deb 并重启桌面。

**本版只注入 SpringBoard。** 单击关闭分屏窗口、长按退出 App 都在桌面进程内完成，不再需要目标 App 注入，因此无需在 App 内允许插件，也不用为了生效而重启目标 App。

## 交互规则

- 图标从下往上排列，最下方为第一位。当前 App（优先取 TrollOpen 当前展开浮窗，其次全屏前台 App）放在第一位，其余图标保留消息顺序；换位有动画。
- 设置新增“整组图标上下位置”：0 靠顶部，1 靠底部，默认 0.7。滑块移动整组图标，不改变排序；列表占满可用高度时没有剩余移动空间。
- 收到新通知的 App 在非当前 App 中优先排列。切到另一个 App 后，新当前 App 自动成为第一位。
- 当前展开浮窗对应图标保持伸出。其它图标伸出与缩回均约 0.6 秒，完整伸出后**停留 1 秒**。
- 点击有待处理通知的图标：按通知时间从新到旧提交系统通知默认动作；不消费其他 App 的通知。
- 点击当前浮窗图标且没有待处理通知：**关闭该分屏窗口**。
- 没有待处理通知且目标不是当前浮窗：通过 TrollOpen 打开浮窗；目标为全屏当前 App 时使用其专用前台转分屏入口。
- 点击边缘图标时，伸出动画与点击处理同时开始。
- 长按当前分屏浮窗对应的图标约 0.45 秒：**退出该 App**（等同 App 切换器上划卡片，终止进程）。其余图标长按仍关闭图标，保留破裂动画。
- 双击不绑定任何操作：系统不再安装双击手势，单击因此在抬手时立即响应，不再等待第二次点击判定。
- 切换器逐张上划：对应图标破裂消失。一键清空：从当前最下方第一位开始依次破裂。
- 图标大小、不透明度、锁屏/桌面/App 内独立显示开关保留。桌面角标仍由系统提供。

## 系统通知开关

已移除“各 App 新消息图标”页面，旧版本保存的 NotifyApp 开关不再读取。

只读查询系统通知授权状态，“允许通知”被关闭（Denied）时隐藏该 App 的通知来源图标；如果它仍有切换器卡片，图标继续正常显示。不会修改系统通知权限，不删除通知队列。设置约每 5 秒刷新一次。

跨 App 查询使用 SpringBoard 内的 `UNUserNotificationCenter initWithBundleIdentifier:`；接口缺失、异常或无回调时保留上次已知状态，首次未知时暂时保留图标，避免把切换器图标误关。这部分仍需 iOS 16.0.3 真机验证。

接口参考：[运行时头文件](https://github.com/nst/iOS-Runtime-Headers/blob/master/Frameworks/UserNotifications.framework/UNUserNotificationCenter.h)、[Apple 通知中心文档](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)。

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
2. 浮窗中无通知时点击气泡关闭该分屏窗口；有通知时优先跳转通知。
3. 分屏状态下长按气泡退出该 App（进程结束，等同切换器上划）；非分屏图标长按仍破裂关闭。
3b. 收到未读消息时图标伸出约 1 秒后自动收回。
4. 系统关闭 App 通知后，无切换器卡片时图标隐藏；有卡片时继续显示。
5. 系统重新开启通知后重新显示对应已有图标；旧的独立开关没有影响。
6. 长按、逐张清理和一键清理保留破裂效果，批量清理从下方开始。
7. 前台全屏转浮窗后背景仍是桌面；锁屏、横屏、键盘与点击穿透正常。
