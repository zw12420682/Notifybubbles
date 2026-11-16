ARCHS = arm64e
TARGET := iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = MilkyWayReborn
MilkyWayReborn_FILES = Tweak.x MWBackgrounderManager.m MWSceneHelper.m MWPassthroughWindow.m MWWindowView.m MWThemeManager.m
MilkyWayReborn_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
MilkyWayReborn_FRAMEWORKS = UIKit CoreGraphics QuartzCore
include $(THEOS_MAKE_PATH)/tweak.mk
