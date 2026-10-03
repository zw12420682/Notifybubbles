ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

# Only SpringBoard is injected; the app-side return helper is retired.
TWEAK_NAME = NotifyBubbles
NotifyBubbles_FILES = Sources/Tweak.m Sources/NFBStore.m Sources/NFBManager.m Sources/NFBSwitcher.m Sources/NFBTrollOpen.m Sources/NFBWindowControls.m Sources/NFBNotificationPolicy.m Sources/NFBAppExit.m Sources/NFBKeyboard.m Sources/NFBPrivacy.m Sources/NFBOpenEdge.m
NotifyBubbles_CFLAGS = -fobjc-arc -Wall -Wextra
NotifyBubbles_FRAMEWORKS = UIKit Foundation QuartzCore UserNotifications
NotifyBubbles_LIBRARIES = substrate


include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk

# Browser uploads do not preserve executable bits. Set the final staged script
# mode after Theos prepares DEBIAN/control, immediately before DEB packaging.
before-package:: $(THEOS_STAGING_DIR)/DEBIAN/control
	install -m 755 "$(THEOS_LAYOUT_DIR)/DEBIAN/postinst" "$(THEOS_STAGING_DIR)/DEBIAN/postinst"
