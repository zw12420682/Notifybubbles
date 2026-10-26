#!/usr/bin/env python3
"""Static consistency checks for the rail layout changes.

Mac-free safety net: CI compiles the real sources, this catches the class of
mistakes that made the previous batch ship broken (a control sized from the
wrong rectangle, favorites counted while hidden, or a leftover fullscreen
override). Pure text checks, no toolchain.
"""
import pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent


def read(relative):
    return (root / relative).read_text(encoding="utf-8")


def strip_comments(source):
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return re.sub(r"//[^\n]*", "", source)


manager = strip_comments(read("Sources/NFBManager.m"))
plan = strip_comments(read("Sources/NFBRailLayout.h"))
tests = read("Tests/RailLayoutTests.m")
workflow = read(".github/workflows/build.yml")

problems = []

# 1. The fullscreen first row must come from the remembered split row, never
#    from the rail frame that the fullscreen position slider recomputed.
if "railFrame.origin.y" in manager:
    problems.append("NFBManager still derives a row from the fullscreen rail frame")
if "NFBSplitRailTop(CGRectGetMinY(splitFrame)" not in plan:
    problems.append("split row top must still be derived from the split window")

# 2. Favorites must not be counted while the favorites rail is hidden.
if re.search(r"NFBFitContainers\([^;]*self\.favoriteApps\.count", manager):
    problems.append("favorites count still passed to NFBFitContainers while hidden")
if "hideFavorites ? 0 : self.favoriteApps.count" not in manager:
    problems.append("favorites must be zero while the favorites rail is hidden")

# 3. The remembered split metric must be validated (rotation/resize) and reused.
for token in ["splitRailTop", "splitRailDiameter", "splitRailScreenWidth", "splitRailMeasured"]:
    if token not in manager:
        problems.append("missing split metric cache: " + token)
if "NFBSplitMetricsValid" not in read("Sources/NFBGeometry.h"):
    problems.append("split metric validity helper missing")

# 3b. The cache must store the button-slot top, never the content top one row
#     below it (that shifted the next fullscreen top down by a row), and the
#     geometry must survive a SpringBoard relaunch through its own state domain.
state = strip_comments(read("Sources/NFBRailLayout.h"))
if "self.splitRailTop = plan.toggleTop;" not in manager:
    problems.append("split metric must cache plan.toggleTop (button slot), not the content top")
if "self.splitRailTop = plan.rowsTop;" in manager:
    problems.append("split metric still caches the content top")
if "plan.toggleTop" not in state:
    problems.append("plan must expose the button slot top")
store = read("Sources/NFBRailStateStore.m")
if 'return @"local.notifybubbles.railstate";' not in store:
    problems.append("rail geometry must persist in its own state domain")
if 'CFStringRef)NFBDomain' in store or "NFBDomain" in store:
    problems.append("rail geometry must not write the user settings domain")
if "scheduleMetric" not in manager or "restoreRailMetric" not in manager:
    problems.append("rail geometry must be restored once and written debounced")
if "NFBRailStateStore.m" not in read("Makefile"):
    problems.append("NFBRailStateStore.m must be part of the tweak sources")
if "invalidateRestoredRailMetricForSize" not in manager:
    problems.append("a restored metric must be dropped when the screen width changes")

# 4. The top slot exists in both modes; in a split it is the desktop action.
if "CGRect desktopActionFrame = (splitNow && actionTarget) ? plan.toggle : CGRectNull;" not in manager:
    problems.append("split desktop action must use the plan's top slot")
if "if (toggleSlot)" in plan or "bool toggleSlot = !split" in plan:
    problems.append("the top slot must be allocated in split mode too")

# 4b. Toggle mode must follow the explicit split state, not the desktop target.
toggle = re.search(r"BOOL toggleMode\s*=\s*([^;]+);", manager)
if not toggle or "splitNow" not in toggle.group(1):
    problems.append("toggle mode must be derived from the explicit split state")
if "toggleFrame" not in manager:
    problems.append("toggle frame must be passed explicitly from the layout plan")

# 5. Parking rules.
if "NFBShouldParkToggle" not in plan or "collapsed && !split && notifiedCount == 0" not in read("Sources/NFBGeometry.h"):
    problems.append("parking must require collapsed && !split && no notifications")
if "NFBToggleShouldFade" not in manager:
    problems.append("parked opacity must come from the shared helper")
if "screenWidth - 7 - diameter / 2" not in read("Sources/NFBGeometry.h"):
    problems.append("parked toggle must center its image on the screen edge")

# 6. A split must never auto-fold and programmatic scrolling must not count.
if "self.edgeExpanded && !self.splitLayout" not in manager:
    problems.append("auto-collapse tick must skip split mode")
if "isTracking" not in manager or "isDragging" not in manager:
    problems.append("scroll callbacks must only reset on real user scrolling")
if "if (!NFBTrollVisibleApp().length) self.edgeExpanded = NO;" in manager:
    problems.append("tapping an app must not fold the expanded column")

# 7. The clear action is hidden when there is nothing to clear.
if "split || (self.edgeExpanded && notified.count > 0)" not in manager:
    problems.append("clear button must be hidden without notifications outside a split")

# 8. No new independent edge control: only the one desktop-action button.
if manager.count("desktopActionButton = button;") != 1:
    problems.append("exactly one desktop/toggle control may exist")
for forbidden in ["NFBEdgeButton", "collapseButton", "toggleButton"]:
    if forbidden in manager:
        problems.append("unexpected extra control: " + forbidden)

# 9. Tests and CI wiring.
for call in ["split -> fullscreen expanded", "collapsed", "empty"]:
    pass
if "NFBPlanRail" not in tests:
    problems.append("RailLayoutTests must exercise the layout plan")
if "RailLayoutTests.m" not in workflow:
    problems.append("CI must run RailLayoutTests.m")

# 10. Collapsed column with a fullscreen app: one exception row inside the same
#     column, half-hidden by x (never by a whole-column transform or clipping).
geometry = read("Sources/NFBGeometry.h")
for helper in ["NFBExpandedAppHalfHidden", "NFBHalfHiddenBubbleX", "NFBCollapsedEdgeRailFrameX"]:
    if helper not in geometry:
        problems.append("missing geometry helper: " + helper)
if "return collapsed && !split && frontAppPresent;" not in geometry:
    problems.append("the half-hidden exception must require collapsed && !split && a fullscreen app")
if "return isfinite(diameter) ? diameter / 2 - 7 : 0;" not in geometry:
    problems.append("half-hidden x must be diameter/2 - 7 (image centre on the edge)")
if "self.railExceptionApp" not in manager:
    problems.append("the manager must track the exception row")
if "if (exceptionApp && ![columnApps containsObject:fullscreenApp]) [columnApps addObject:fullscreenApp];" not in manager:
    problems.append("the exception app must join the same column and never duplicate a notified app")
if "windowState.fullscreen" not in manager or "NFBCurrentWindowState()" not in manager:
    problems.append("the front app must come from the shared NFBWindowState, not a new tree scan")
if "self.railExceptionApp.length > 0" not in manager or "toggleFrame.origin.x += NFBHalfHiddenBubbleX(diameter);" not in manager:
    problems.append("the collapse control must take the same half-hidden x")
# The exception row moves through its centre; the column itself is never shifted.
if "CGFloat rowX = side / 2 + (exceptionRow ? NFBHalfHiddenBubbleX(diameter) : 0);" not in manager:
    problems.append("the exception row must be offset through its own centre")
if "transform.origin.x" in manager or "self.rail.transform = CGAffineTransform" in manager:
    problems.append("the exception must move by row x, never by a column transform")
    problems.append("the exception must move by row x, never by a column transform")
if "railViewportWidth" not in plan:
    problems.append("the plan must expose the icon column width inside the widened frame")
if "CGSizeMake(railFrameWidth, contentHeight)" not in manager:
    problems.append("the rail content size must follow the widened frame")
if "exceptionSlot" in manager:
    problems.append("no separate exception slot may be created")
if "NFBExpandedAppHalfHidden(" not in tests:
    problems.append("RailLayoutTests must cover the half-hidden policy")

if problems:
    print("FAIL: rail layout checks\n - " + "\n - ".join(problems))
    sys.exit(1)
print("PASS: rail layout wiring (single geometry source, no hidden favorites, explicit split state, half-hidden exception row)")
