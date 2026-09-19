ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NotifyBubbles NotifyBubblesBack
NotifyBubbles_FILES = Sources/Tweak.m Sources/NFBStore.m Sources/NFBManager.m Sources/NFBSwitcher.m Sources/NFBTrollOpen.m Sources/NFBNotificationPolicy.m Sources/NFBBackRequest.m
NotifyBubbles_CFLAGS = -fobjc-arc -Wall -Wextra
NotifyBubbles_FRAMEWORKS = UIKit Foundation QuartzCore UserNotifications
NotifyBubbles_LIBRARIES = substrate

NotifyBubblesBack_FILES = Sources/NFBAppBack.m
NotifyBubblesBack_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-error=deprecated-declarations
NotifyBubblesBack_FRAMEWORKS = UIKit Foundation WebKit
NotifyBubblesBack_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
