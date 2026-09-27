# NotifyBubbles 0.48.8

- 分屏常用容器与原容器分别检查当前 App 的排序：前四个不动，只高亮；第五个及以后置顶，并滚回各自的前四个。未选择的 App 不会自动加入常用列表，重复刷新也不会反复抢回滚动位置。
- 返回按钮单击改为在目标 App 内模拟左边缘向右滑动，约 0.4 秒；分屏使用 App 本身窗口坐标，全屏同理。不再调用导航栈 pop 或网页 goBack。首页同样执行右划，可能打开侧栏，按用户确认保留这一行为。
- 长按返回按钮仍执行清理后台，其它已确认功能保留。

上传 NotifyBubbles 文件夹内全部内容覆盖仓库。编译安装后重新载入桌面，并退出后重新打开需要使用返回功能的 App，以加载新返回组件。RootHide 必须允许目标 App 注入 NotifyBubblesBack。

验证状态：本地配置、文件及压缩包检查通过。新增前四个/第五个/未选中/重复刷新测试由 GitHub 原生测试步骤运行。本地 Windows 环境没有 iOS 编译和手机验证，模拟触摸使用私有接口，是否被目标 App 接收需要实测。状态“已发送”只代表事件序列已送出，不代表页面一定返回。

请重点测试：在两个容器分别选第四、第五个 App；置顶后滚动不被持续拉回；全屏与分屏内分别点击返回；首页右划；确认长按仍清理而不额外右划。

接口核对参考：
- https://github.com/kif-framework/KIF/blob/master/Sources/KIF/Additions/UITouch-KIFAdditions.m
- https://github.com/WebKit/WebKit/blob/main/Tools/WebKitTestRunner/ios/HIDEventGenerator.mm
实现使用运行时接口检测、目标 App 内的事件序列，以及窗口改变或超时取消。
