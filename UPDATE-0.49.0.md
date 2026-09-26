# NotifyBubbles 0.49.0

- 为 TrollOpen 1.5.2 的边缘列表和导播台 App 图标增加红色角标。
- 读取 SpringBoard 桌面图标的 badgeNumberOrString，不使用 NotifyBubbles 自己的通知条数。
- 每约 0.5 秒刷新；桌面角标清零后隐藏。角标位于图标右上角内部，避免被原容器裁剪。
- 不替换 TrollOpen 图标的手势，不改变原来的点击、长按操作。跟随 NotifyBubbles 总开关。
- 优先识别按钮自身 App 标识；没有明确标识时，使用 TrollOpen 同一控制器的等长按钮与 App 列表对应。这个对应关系仍需真机验证。

上传时覆盖完整项目内容，必须包含新的 Sources 文件和根目录 Makefile。
安装后重新启动桌面，再打开 TrollOpen 边缘列表/导播台。

本地配置与压缩包检查通过；新增角标文本测试由 GitHub 构建运行。本机未编译 iOS 插件，尚未验证手机上的接口调用和显示效果。若图标没有角标或对应不正确，请提供截图及 /var/tmp/nfb-debug.log。
