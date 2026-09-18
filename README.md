# 通知悬浮气泡 · 0.1.0 测试工程

开发目标：iPhone 14、iOS 16.0.3、Dopamine RootHide（隐根版）。
工程附带 GitHub Actions，生成 `iphoneos-arm64e` 架构的 RootHide `.deb`。

**交付状态：源码已编写，项目文件检查已通过；尚未在 GitHub 编译，尚未真机验证。不能把本工程视为已经验证兼容的成品。**

## 用 GitHub 编译

1. 解压源码包，新建自己的 GitHub 仓库。
2. 将 `NotifyBubbles` 文件夹里面的全部内容上传到仓库根目录。根目录应直接看到 `Makefile`、`control`、`Sources` 和 `.github`，不要再套一层 `NotifyBubbles`。
3. 必须包含 `.github/workflows/build.yml`。部分文件选择器会隐藏点开头的文件夹；若漏了，可在 GitHub 用 **Add file → Create new file** 创建这个路径，粘贴附带工作流内容。
4. 打开 **Actions → Build RootHide DEB → Run workflow → Run workflow**。若显示启用 Actions 的提示，先启用。
5. 等待构建显示绿色。进入该次构建，下方 **Artifacts** 下载 `NotifyBubbles-RootHide`。
6. 解压下载物，里面的 `.deb` 才是安装包；源码 ZIP 本身不能安装。
7. 将 `.deb` 传到手机，通过你现有的 RootHide 包管理器安装，按安装器提示重启桌面。
8. 打开系统“设置 → 通知悬浮气泡”。如果设置页没出现，确认 RootHide 环境已安装并启用 PreferenceLoader，然后重新打开设置。

不需要 Apple 开发者证书、不需要填写 SSH 密码或 GitHub Token。
工作流只构建并上传产物，不会自动发布 Release，也不会连接手机。
若构建失败，下载 `NotifyBubbles-build-log`，或复制第一个失败步骤的完整日志进行修复。

## 本版规则

| 项目 | 行为 |
| --- | --- |
| 通知来源 | 观察系统投递的横幅通知；锁屏分支要求通知目标中也包含横幅 |
| 位置与大小 | 屏幕右侧，48 点圆形 App 图标；纵向排列，过多时可滚动 |
| 动画 | 弹出与收起；遵循系统“减弱动态效果”设置 |
| 空闲 | 启动时不显示；没有待处理气泡时隐藏；重启桌面清空气泡 |
| 角标 | 左上角读取 SpringBoard 桌面图标的角标值，约 0.75 秒刷新 |
| 没有桌面角标 | 气泡可以表示新通知，但不伪造角标数字 |
| 点击 | 执行该 App 最新通知的系统默认动作，并清空所有 App 的全部气泡 |
| 锁屏点击 | 请求系统认证；用户取消认证后也已清空气泡，符合“点击即清除”规则 |
| 系统通知 | 保留原横幅和通知中心；清气泡不删除通知中心通知，不修改桌面角标或 App 未读数 |
| 显示开关 | 锁屏、主屏、App 内分别控制；总开关关闭时清空 |

本版没有压制原横幅，因此系统通知接口不匹配时，仍能从原通知打开消息。
“桌面角标一致”指系统图标提供的值；第三方美化插件自行绘制的角标样式或改写后的显示文本不保证一致。
图标优先使用通知内容中的 App 图标；系统未提供时显示铃铛占位。

## 真机验证（首次安装必须检查）

先用短信或另一个设备向当前手机发一条通知，再测试日常 App。

- [ ] 无新通知时不显示任何气泡。
- [ ] 两个 App 分别收到消息后出现两个气泡，同一个 App 的重复消息合并。
- [ ] 桌面角标为 3、10 或无角标时，气泡数字一致；在 App 中已读后及时更新。
- [ ] 点击任意气泡打开对应通知（如 App 支持则进入具体消息），并清空所有气泡。
- [ ] 清空后再次收到通知，气泡重新出现。
- [ ] 分别关闭锁屏、主屏和 App 内显示，其他位置不受影响。
- [ ] 锁屏收到新消息仍可产生气泡；点击后需要 Face ID 或密码；取消后行为与表格一致。
- [ ] 通知中心清除消息、App 撤回通知后，相关气泡正确移除。
- [ ] 勿扰/专注模式、通知摘要和禁用横幅时没有意外新增气泡。
- [ ] 键盘、横竖屏、应用切换、屏幕右侧点击和多气泡滚动没有触摸阻塞。

锁屏新通知捕获、窗口层级、场景旋转、默认动作回调以及撤回接口依赖 iOS 私有实现，是本次必须真机确认的部分。公开头文件用于选择候选接口，不能替代 iOS 16.0.3 的设备验证。
如果没有气泡，查看 SpringBoard 日志中 `[NotifyBubbles]` 开头的启动诊断；`feed=0` 表示所有通知入口候选接口都未匹配。不要先改系统通知权限来掩盖接口问题。

若出现桌面异常，通过 Dopamine 提供的不加载插件方式进入系统，卸载“通知悬浮气泡”，再恢复加载插件。不要删除任何系统文件。

## 工程与验证

- `Sources/NFBStore.m`：通知去重、最新动作、撤回和全量清除；最多保留最近 512 个通知对象，防止持续增长。
- `Sources/Tweak.m`：只向 SpringBoard 注入，检查方法签名后安装观察钩子。
- `Sources/NFBManager.m`：透传空白处触摸、气泡窗口、桌面角标读取与系统通知动作。
- `Preferences`：中文设置面板，无额外第三方偏好库。
- `Tests/StoreTests.m`：在 GitHub macOS 构建机上运行实际生产状态类的 13 项检查。
- `scripts/validate.py`：跨平台校验文件、plist、设置键和注入范围。
- `scripts/check_package.py`：构建后检查 `.deb` 架构与插件、设置面板是否真的打包。

工作流固定了 RootHide Theos 和 SDK 的提交，使用 macOS Xcode 的 arm64/arm64e 编译器。包架构 `iphoneos-arm64e` 和二进制架构 `arm64/arm64e` 是不同概念，不要仅修改 control 来转换成其他越狱环境的包。

本机可运行：`python scripts/validate.py`。
有 macOS + RootHide Theos 时可运行：`make package FINALPACKAGE=1`。
完整编译及 Objective-C 状态测试以你仓库的 Actions 运行结果为准。

## 参考资料

- [RootHide 官方开发说明](https://github.com/roothide/Developer)
- [RootHide Theos](https://github.com/roothide/theos)
- [Theos SDK](https://github.com/theos/sdks)
- [公开通知分发接口头文件](https://github.com/nst/iOS-Runtime-Headers/blob/master/PrivateFrameworks/UserNotificationsKit.framework/NCNotificationDispatcher.h)

通知内容只在 SpringBoard 内存中用于打开原通知；本插件没有联网代码，不记录消息正文，不把通知写入磁盘。
