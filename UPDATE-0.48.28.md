# 0.48.28 边缘图标状态

- NotifyBubbles 分屏图标显示：隐藏 Open 边缘图标。
- APP 全屏且没有可见悬浮窗口：使用 Open 的 edgeButtonAutoHidden 收起位置。
- 桌面、可见分屏/横屏/迷你窗口等其余状态：使用原生左滑后伸出位置。
- 拦截原生收起 setter，防止原生自动收起覆盖上述规则；保留 Open 的原生显示资格和托盘行为。
- 新接口安装前校验方法签名；不修改 Open 原始 DEB。

已通过 scripts/validate.py 静态校验。Windows 环境没有 Theos/iOS SDK，未编译 DEB，未进行真机验证。scripts/test_cleanup.py 在本环境因临时目录权限失败，未完成。可使用项目原有 GitHub Actions 构建流程编译，再在设备验证全屏、桌面、分屏图标显示/消失和迷你窗口切换。
