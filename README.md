# 0.48.46 文件夹处理修正

修正启动拦截未区分文件夹和应用的问题。识别 iconView/icon 的 isFolderIcon（先检查实际方法签名），以及原生 SBFolderIcon 类。文件夹返回原生处理，不提交 Open 分屏启动、不关闭桌面；实际应用仍维持分屏启动和成功后关闭桌面的规则。识别文件夹放在 pendingApp 判断前，避免等待 APP 启动时吞掉文件夹动作。

新增 UIKit fixture 测试覆盖文件夹 view 标记、model 标记、原生类后备、无 APP 请求以及等待启动时放行文件夹。已通过本地结构校验和 13 项校验器回归测试；UIKit 测试、iOS 编译及真实文件夹打开行为仍需 macOS CI 和设备验证。

更新包按原路径覆盖四个文件：Sources/NFBDesktopHost.m、Tests/DesktopHostTests.m、control、Preferences/Resources/Info.plist。现有工程须已同步上一版的共享模块和最新工作流。若不确定，使用完整 GitHub 上传包。

安装后重启 SpringBoard，测试：点击文件夹 → 点击空白关闭文件夹 → 再打开并点击文件夹内 APP。若仍打不开，请开启调试日志后发来新日志，查看 desktop folder icon: native folder handling 是否出现。

接口核对参考：https://github.com/Tweaker177/iOS-14-16-Private-System-API-headers/blob/master/SBFolderIcon.h 。实际调用仍以设备运行时签名检查为准。
