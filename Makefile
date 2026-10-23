ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

# Main features stay SpringBoard-only. The isolated keyboard module targets UIKit.
TWEAK_NAME = NotifyBubbles NFBKeyboardDock
NotifyBubbles_FILES = Sources/Tweak.m Sources/NFBStore.m Sources/NFBManager.m Sources/NFBSwitcher.m Sources/NFBTrollOpen.m Sources/NFBWindowControls.m Sources/NFBNotificationPolicy.m Sources/NFBAppExit.m Sources/NFBKeyboard.m Sources/NFBPrivacy.m Sources/NFBOpenEdge.m Sources/NFBDebugLog.m Sources/NFBWindowState.m Sources/NFBOpenConsole.m Sources/NFBHotspot.m Sources/NFBDesktopHost.m Sources/NFBStateLedger.m Sources/NFBInterfaces.m
NFB_PACKAGE_VERSION = $(shell sed -n 's/^Version: //p' control)
NotifyBubbles_CFLAGS = -fobjc-arc -Wall -Wextra -DNFB_VERSION='@"$(NFB_PACKAGE_VERSION)"'
NotifyBubbles_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics UserNotifications
NotifyBubbles_LIBRARIES = substrate


NFBKeyboardDock_FILES = Sources/NFBKeyboardDock.m
NFBKeyboardDock_CFLAGS = -fobjc-arc -Wall -Wextra
NFBKeyboardDock_FRAMEWORKS = UIKit Foundation
NFBKeyboardDock_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk

# Browser uploads do not preserve executable bits. Set the final staged script
# mode after Theos prepares DEBIAN/control, immediately before DEB packaging.
before-package:: $(THEOS_STAGING_DIR)/DEBIAN/control
	install -m 755 "$(THEOS_LAYOUT_DIR)/DEBIAN/postinst" "$(THEOS_STAGING_DIR)/DEBIAN/postinst"
