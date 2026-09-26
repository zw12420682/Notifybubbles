# NotifyBubbles 0.48.2

修复打包错误：postinst 权限为 644。

根目录 Makefile 现在在正式打包前，以 755 权限将清理脚本复制到最终 DEBIAN 目录。不依赖网页上传保留执行权限，也不只依赖工作流提前 chmod。打包后的检查要求 postinst 权限必须为 755。

插件功能与 0.48.1 完全相同，仍基于 0.48 系列，不包含 0.49 功能。

上传方式：解压后上传 NotifyBubbles 文件夹内的全部内容覆盖，尤其是根目录 Makefile。然后运行 GitHub Actions。

本地配置及压缩包检查通过；需要重新运行 GitHub 编译确认最终 DEB。
