# 0.48.29：修正其他显示状态仍收起

0.48.28 只控制 edgeButtonAutoHidden 标志，用户反馈其他显示状态仍收起。此版增加原生位置计算拦截，并在设置标志后重新执行原生布局，避免 setter 的状态未变化分支保留旧位置。

规则：NotifyBubbles 分屏图标显示时隐藏 Open；APP 全屏且无可见浮窗时收起；桌面和其他可见悬浮/迷你窗口情况下使用伸出位置。保留 Open 的原生图标显示资格及托盘行为。

新增拦截 edgeButtonAutoHidden getter 和 edgeCenterXForHostBounds:tucked:，横坐标仍由 Open 原生左右边缘几何计算。currentVisibleFloatingWindow 也参与状态判断，避免只查询 UIApplication.windows 漏掉浮窗。所有新增接口均在安装 Hook 前验证参数与返回类型。

直接读取用户提供 Open DEB 中两个架构的 Objective-C 方法元数据，接口类型一致：

- edgeCenterXForHostBounds:tucked:：d52@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16B48
- edgeButtonAutoHidden：B16@0:8
- updateEdgeButtonLayoutInHostView:animated:：v28@0:8@16B24

对应 arm64 方法地址：0x157614 / 0x15f318 / 0x1590d4；arm64e：0x163888 / 0x16bc80 / 0x1654f0。地址仅用于记录核对证据，代码通过 Objective-C 方法名访问，不硬编码地址。

验证：scripts/validate.py 通过；ZIP 内容及版本检查通过。当前 Windows 环境没有 Theos/iOS SDK，未编译 DEB，未完成真机验证。使用项目原有 GitHub Actions 构建，真机检查桌面、全屏、横屏/迷你窗口、分屏图标隐藏/恢复及边缘左滑。上一版 cleanup 测试因 Windows 临时目录权限未完成，本次未重复与该变更无关的清理测试。
