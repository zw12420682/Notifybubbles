# NotifyBubbles 0.48.45

适用于 iOS 16、RootHide 与 Open 定制版 1.3.7。

## 上传到 GitHub

1. 解压 ZIP，把里面的全部文件和文件夹上传到仓库根目录；不要把 ZIP 文件本身作为源码上传，也不要再套一层项目文件夹。
2. 仓库根目录应直接看到 Makefile、control、Sources、Tests、scripts、Preferences、layout 和 .github。
3. 务必更新 `.github/workflows/build.yml`。若文件选择器未显示点号开头目录，请单独核对这个文件已上传。
4. 使用本包配套的测试和脚本，不要只替换 validate.py。
5. 提交后运行仓库的构建工作流，全部检查通过后下载生成的 DEB。

旧版本遗留、但未写入 Makefile 的源码只会提示，不会阻断校验。本包省略不参与构建的 Legacy 归档以及临时文件。

## 验证状态

交付前完成结构校验、校验脚本回归测试及包解析器测试。本地为 Windows 环境，未执行 iOS 编译和 UIKit 模拟器测试；它们由配套 macOS 工作流运行。
