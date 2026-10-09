# 0.48.31：按参考图展开 Open 右侧面板

用户参考图右侧是包含删除、收起箭头及 APP 图标的 Open 原生托盘。此前 0.48.28–0.48.30 将“伸出”理解为单个边缘按钮的位置，未打开该面板。

本版规则：
- NotifyBubbles 分屏图标显示：关闭 Open 托盘并隐藏边缘图标。
- APP 全屏且无可见浮窗：关闭托盘，原生边缘按钮收起。
- 其他符合 Open 原生显示条件的状态：调用原生 showTray 展开参考图中的面板。

删除和 APP 图标操作仍由 Open 原生方法处理。原生关闭动作允许执行；等待关闭动画结束后重新检查当前状态。若仍属于展开状态，恢复面板。上下滑动选择应用期间不抢占该手势。增加重入保护，避免原生托盘显示/关闭触发 Hook 的递归。移除此前单个按钮的坐标、getter 和 setter 拦截。

核对提供的 Open 1.3.7 二进制 Objective-C 元数据：showTray 为 v16@0:8，hideTrayAnimated: 为 v20@0:8B16，trayBackdrop 为 @16@0:8，swipeGestureActive 为 B16@0:8。也检查了 showTray/hideTrayAnimated: 的 arm64 反汇编，关闭方法在退出动画前清空托盘属性，因此自动恢复需等待动画结束。安装 Hook 前校验相关方法签名。

scripts/validate.py 静态校验及 ZIP 完整性检查通过。Windows 环境未执行 iOS 编译或真机验证。请重新运行已有 GitHub Actions 构建，并检查：桌面右侧自动出现参考图面板；全屏时面板收起；分屏图标显示时 Open 消失；分屏图标消失且非全屏时面板恢复；删除/APP 图标点击及滑动动作正常。
