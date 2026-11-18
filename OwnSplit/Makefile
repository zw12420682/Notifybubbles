export TARGET = iphone:clang:16.5:16.0.3
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = OwnSplit
OwnSplit_FILES = Sources/Tweak.x Sources/OSSettings.m Sources/OSFloatingWindow.m Sources/OSWindowManager.m Sources/OSGestureController.m Sources/OSAppPicker.m Sources/OSSceneHost.m Sources/OSPassthroughWindow.m Sources/OSSplitView.m
OwnSplit_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-deprecated-declarations
OwnSplit_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
include $(THEOS_MAKE_PATH)/tweak.mk
