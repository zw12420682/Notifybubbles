# Open 定制版 1.3.7 接口核对

分析对象 SHA256：`260ca20e59b376b490c2b47791dbd6a44b28696384d073284820b16537aaa45e`。包标识 com.charlieleung.trollopenjb；架构 iphoneos-arm64e。
原 DEB 未修改、未包含在本源码包中。根据随包二进制方法信息与关键处理函数反汇编核对。

|功能|新包接口|
|---|---|
|窗口类|FloatingAppWindow|
|按应用打开|+[FloatingAppWindow showWithBundleID:]|
|当前窗口|+[TOJBBarGestureBridge currentVisibleFloatingWindow]|
|前台分屏|+[TOJBBarGestureBridge splitFrontmostApplication]|
|全屏/缩小|桥接类 fullscreenCurrentFloatingWindow / minimizeCurrentFloatingWindow，返回 BOOL|
|关闭区域单击|handleBottomSingleTap:；state=Ended，关闭窗口但不终止进程|
|顶部区域长按|handleTopTouchLongPress:；state=Began，调用 rotateButtonTapped|
|方向请求|requestSceneOrientationOnce:，NSInteger|
|宿主布局|updateHostViewLayoutForCurrentBounds|
|大小|setVisualScale:，double；syncContainerFrameToVisualScalePreservingCenter:，BOOL|
|状态|bundleID、sceneOrientation、containerOrientation、miniWindowModeEnabled、isTransitioningFromMiniMode、isClosingWithKeepAliveAnimation|

打开应用使用普通包装方法，其内部 skipOnlineLimitClose 参数为 NO，保留原包行为。
手势使用明确方法名和参数签名校验，不读取私有 action 指针。
源码接口映射可静态验证；手机窗口动画、键盘、横竖屏旋转及布局仍需要真机测试。
