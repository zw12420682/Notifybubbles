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

# 4. Toggle mode must follow the explicit split state, not the desktop target.
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

if problems:
    print("FAIL: rail layout checks\n - " + "\n - ".join(problems))
    sys.exit(1)
print("PASS: rail layout wiring (single geometry source, no hidden favorites, explicit split state)")
