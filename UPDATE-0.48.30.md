# 0.48.30：修复 iOS 16.5 SDK 编译错误

NFBOpenEdge.m 使用 UIApplication.windows，触发 deprecated-declarations，并被构建的 -Werror 转为错误，导致 arm64 和 arm64e 构建失败。

改为枚举 UIApplication.connectedScenes，仅对 UIWindowScene 读取 windows；继续保留 Open 桥接方法对未附着 scene 的可见浮窗的检查。边缘图标的隐藏、全屏收起与其他状态伸出策略保持原有规则。

scripts/validate.py 静态检查通过；ZIP 完整性、版本和修改内容检查通过。当前 Windows 环境未执行 iOS 编译，需重新运行项目 GitHub Actions 构建确认。
