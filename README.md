# NotifyBubbles 0.48.2

修复打包错误：postinst 权限为 644。

根目录 Makefile 现在在正式打包前，以 755 权限将清理脚本复制到最终 DEBIAN 目录。不依赖网页上传保留执行权限，也不只依赖工作流提前 chmod。打包后的检查要求 postinst 权限必须为 755。

插件功能与 0.48.1 完全相同，仍基于 0.48 系列，不包含 0.49 功能。

上传方式：解压后上传 NotifyBubbles 文件夹内的全部内容覆盖，尤其是根目录 Makefile。然后运行 GitHub Actions。

本地配置及压缩包检查通过；需要重新运行 GitHub 编译确认最终 DEB。

---

# NotifyBubbles 0.48.1

本版从 0.48.0 修改，未合并作废的 0.49.0。

- 取消所有边缘、分屏图标的双击识别，不再等待第二次点击。
- 边缘图标缩回时：单击只伸出，不执行打开操作；长按后上下拖动调整整组位置。
- 边缘图标伸出时及分屏图标：单击执行原操作，长按清除图标及对应 App，保留气泡破裂动画。
- 操作按手指按下时的状态判断，避免长按过程中自动缩回造成误判。
- 伸出停留 1 秒。保留位置记忆、窄背景及键盘避让，不包含深色键盘组件。
- 修复没有通知记录的 App 清除时，空版本标记可能阻止清除的问题。

## 旧键盘组件清理

安装时的 postinst 根据 dpkg 记录寻找当前 NotifyBubbles.dylib 所在目录，只清理该目录内 NotifyBubblesKeyboard.dylib、NotifyBubblesKeyboard.plist 及对应 .disabled 文件。其他安装包所有的文件、符号链接、其他插件和其他 bootstrap 目录都不会删除。安装日志会显示已删除或跳过的路径。

这不代表已经清理了手机：残留可能在不同目录，也可能只是管理工具缓存。安装新版并重新启动桌面后检查。若仍显示残留，请在文件管理器搜索 NotifyBubblesKeyboard，提供完整路径再处理；不要删除 TrollOpenKeyboard。

## 上传

把 NotifyBubbles 文件夹里的全部内容上传覆盖到仓库根目录。本版务必包含 .github、layout、scripts、Sources、Preferences、Makefile 和 control，清理脚本需要随安装包一起编译打包。

## 验证

本地配置检查、清理脚本语法和隔离模拟测试通过。模拟覆盖孤立文件、停用文件、其他包所有权、其他插件、其他安装目录及重复安装。未在本机执行 iOS 编译和真机手势测试，需通过 GitHub 构建及手机验证。
