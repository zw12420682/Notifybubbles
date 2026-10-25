ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
INSTALL_TARGET_PROCESSES = SpringBoard

# ---------------------------------------------------------------------------
# Packaging scheme (rootless / roothide)
#
# This project ships two flavours from one source tree:
#   rootless  -> installed under /var/jb, DEB Architecture: iphoneos-arm64
#                (Dopamine / palera1n rootless and other /var/jb bootstraps)
#   roothide  -> installed under the RootHide bootstrap, DEB Architecture:
#                iphoneos-arm64e (Dopamine RootHide)
#
# The value comes from the command line or the environment, so both work:
#   make package FINALPACKAGE=1                              # rootless
#   make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
#   THEOS_PACKAGE_SCHEME=roothide make package FINALPACKAGE=1
#
# The default is applied only when the variable is empty, so anything passed on
# the make command line (or exported into the environment) always wins; an empty
# value never shadows a scheme handed down by the toolchain.
# ---------------------------------------------------------------------------
ifeq ($(strip $(THEOS_PACKAGE_SCHEME)),)
THEOS_PACKAGE_SCHEME := rootless
endif

ifeq ($(filter $(THEOS_PACKAGE_SCHEME),rootless roothide),)
$(error Unsupported THEOS_PACKAGE_SCHEME '$(THEOS_PACKAGE_SCHEME)'; use rootless or roothide)
endif

# The scheme also decides the DEB Architecture field (see before-package).
# control is the shared identity + Version, control.rootless /
# control.roothide carry the per-scheme Architecture field only.
NFB_SCHEME_CONTROL = control.$(THEOS_PACKAGE_SCHEME)

include $(THEOS)/makefiles/common.mk

# Only SpringBoard is injected; the app-side return helper is retired.
TWEAK_NAME = NotifyBubbles
NotifyBubbles_FILES = Sources/Tweak.m Sources/NFBStore.m Sources/NFBManager.m Sources/NFBSwitcher.m Sources/NFBTrollOpen.m Sources/NFBWindowControls.m Sources/NFBNotificationPolicy.m Sources/NFBAppExit.m Sources/NFBKeyboard.m Sources/NFBPrivacy.m Sources/NFBOpenEdge.m Sources/NFBDebugLog.m Sources/NFBWindowState.m Sources/NFBOpenConsole.m Sources/NFBHotspot.m Sources/NFBDesktopHost.m Sources/NFBStateLedger.m Sources/NFBInterfaces.m
NFB_PACKAGE_VERSION = $(shell sed -n 's/^Version: //p' control)
NotifyBubbles_CFLAGS = -fobjc-arc -Wall -Wextra -DNFB_VERSION='@"$(NFB_PACKAGE_VERSION)"'
NotifyBubbles_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics UserNotifications
NotifyBubbles_LIBRARIES = substrate


include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk

# Browser uploads/ZIP transfers do not preserve executable bits, and the scheme
# specific control file has to replace the staged one. Run this immediately
# before DEB packaging (after Theos prepared $(THEOS_STAGING_DIR)/DEBIAN/control).
before-package::
	@if [ ! -f "$(NFB_SCHEME_CONTROL)" ]; then \
		echo "error: missing $(NFB_SCHEME_CONTROL) for THEOS_PACKAGE_SCHEME=$(THEOS_PACKAGE_SCHEME)" >&2; exit 1; \
	fi
	@staged="$(THEOS_STAGING_DIR)/DEBIAN/control"; \
	 mkdir -p "$(THEOS_STAGING_DIR)/DEBIAN"; \
	 shared="$$(mktemp)"; \
	 if [ -f "$$staged" ]; then \
		grep -v -e '^Architecture: ' -e '^Installed-Size: ' "$$staged" > "$$shared"; \
	 else \
		grep -v -e '^Architecture: ' "control" > "$$shared"; \
	 fi; \
	 { sed '/^Architecture: /d' "$$shared"; cat "$(NFB_SCHEME_CONTROL)"; } > "$$staged.nfb"; \
	 rm -f "$$shared"; \
	 mv "$$staged.nfb" "$$staged"
	@echo "NotifyBubbles: THEOS_PACKAGE_SCHEME=$(THEOS_PACKAGE_SCHEME), Architecture=$$(sed -n 's/^Architecture: //p' "$(THEOS_STAGING_DIR)/DEBIAN/control")"
	install -m 755 "$(THEOS_LAYOUT_DIR)/DEBIAN/postinst" "$(THEOS_STAGING_DIR)/DEBIAN/postinst"

# Rebuild trigger for the 0.48.56 rollback.
