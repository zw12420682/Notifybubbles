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
if "NFBRowCenter(rowCount, rowIndex, step, side) + railFrame" in manager:
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

# 10. Collapsed column with a fullscreen app: the whole visible column half hides
#     (rail + every row + the control shift together), screen-space truth lives in
#     one helper, and the collapse control is tappable without a desktop target.
geometry = read("Sources/NFBGeometry.h")
for helper in ["NFBExpandedAppHalfHidden", "NFBHalfHiddenShift", "NFBHalfHiddenBubbleOriginX"]:
    if helper not in geometry:
        problems.append("missing geometry helper: " + helper)
if "return collapsed && !split && frontAppPresent;" not in geometry:
    problems.append("the half-hidden state must require collapsed && !split && a fullscreen app")
if "return 4 + (diameter + 14) / 2;" not in geometry:
    problems.append("the half-hidden shift must put the image centre on the screen edge "
                    "(margin + half bubble, independent of the unread count)")
if "static inline double NFBHalfHiddenBubbleOriginX(" not in geometry:
    problems.append("the half-hidden column x must come from one helper")
if "return screenWidth - NFBHalfHiddenShift(diameter) + margin;" not in geometry:
    problems.append("the half-hidden column x must be screenWidth - (margin + side/2)")
if "NFBHalfHiddenBubbleX" in geometry or "NFBCollapsedEdgeRailFrameX" in geometry:
    problems.append("the old local-x half-hide helpers must be gone")
if "NFBExpandedAppHalfHidden(collapsed, split, fullscreenApp.length > 0)" not in manager:
    problems.append("the manager must track the fullscreen app of the column")
if "if (exceptionApp && ![columnApps containsObject:fullscreenApp]) [columnApps addObject:fullscreenApp];" not in manager:
    problems.append("the fullscreen app must join the same column and never duplicate a notified app")
if "windowState.fullscreen" not in manager or "NFBCurrentWindowState()" not in manager:
    problems.append("the front app must come from the shared NFBWindowState, not a new tree scan")
# The manager must pass the half-hidden state to the plan (not a local x guess).
if "self.splitRailMeasured, exceptionApp);" not in manager:
    problems.append("the plan must receive the half-hidden state")
# The move is applied exactly once: no row carries an offset, and the control
# takes the rail's x instead of adding the shift a second time.
if "CGFloat rowX = side / 2;" not in manager:
    problems.append("rows must keep the plain side/2 offset (the column moves once)")
for stale in ["rowInset", "clearInset", "+ plan.halfHiddenShift", "NFBHalfHiddenBubbleX"]:
    if stale in manager:
        problems.append("the half-hidden offset is applied twice: " + stale)
if "toggleFrame.origin.x = CGRectGetMinX(railFrame);" not in manager:
    problems.append("the control shares the rail's half-hidden x")
# Whole-column fade: no per-row exception alpha, the column dims as one.
if "CGFloat columnAlpha = exceptionApp ? 0.5 : 1;" not in manager:
    problems.append("the collapsed fullscreen column must fade as a whole")
if "if (exceptionRow) alpha = 0.5;" in manager:
    problems.append("only the fullscreen row must not be dimmed individually")
if "transform.origin.x" in manager or "self.rail.transform = CGAffineTransform" in manager:
    problems.append("the column must move by its frame, never by a transform")
if "exceptionSlot" in manager:
    problems.append("no separate exception slot may be created")
if "CGSizeMake(railFrameWidth, contentHeight)" not in manager:
    problems.append("the rail content size must follow its frame")

# 11. Interaction of the half-hidden control and rows.
hit = read("Sources/NFBHitPolicy.h")
if "NFBHalfHiddenAcceptsTouch" not in hit or "NFBMinimumTouchRadius" not in hit:
    problems.append("a shared touch helper is required for half-hidden views")
if "NFBToggleIsInteractive" not in hit:
    problems.append("toggle interactivity must not depend on a desktop target")
if "requireGestureRecognizerToFail:self.desktopActionHold" not in manager:
    problems.append("the collapse control keeps its own tap/long-press pairing")
if "if (self.desktopActionToggle) {" not in manager or "return self.desktopActionTouchTarget != nil;" not in manager:
    problems.append("toggle mode must be accepted before the desktop target gate")
# The half-hidden hit fix must stay local: no circle test that would change the
# square bubble everywhere, and no manual descent from the window.
if "- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event" in manager:
    problems.append("a bubble-wide pointInside would change every icon's hit area")
if "hit = [root hitTest:" in manager:
    problems.append("the window must not hand touches to a narrower root by hand")
if "NFBVisibleMinX(" not in hit:
    problems.append("the on-screen part of a half-hidden view must be computed once")
if "- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event" not in manager:
    problems.append("the rail must offer the on-screen half of a row that hangs past it")
if "self.rail.clipsToBounds = NO;" not in manager:
    problems.append("the rail must not clip a half-hidden row before the screen edge")
if "[self.window addSubview:button];" not in manager:
    problems.append("the collapse control must not be disabled by HideInScreenshots")

# 12. Transitions: interruption-safe, no restart of identical animations, badge
#     only on content change, programmatic scrolling never resets the idle timer.
policy = read("Sources/NFBTransitionPolicy.h")
motion = read("Sources/NFBMotionPolicy.h")
for helper in ["NFBMotionNeedsAnimation", "NFBMotionCompletionIsCurrent", "NFBBadgeNeedsAnimation"]:
    if helper not in motion:
        problems.append("missing transition helper: " + helper)
if "columnSlideToken" not in manager:
    problems.append("column slides need a token so a stale completion cannot hide them")
if "beginFromCurrentState" in manager and "BeginFromCurrentState" not in manager:
    problems.append("animations must use UIViewAnimationOptionBeginFromCurrentState")
if "badgeContentVersion" not in manager:
    problems.append("the badge may only animate when its content changed")
if "if (!isClearAll) [self layoutBadge:button diameter:diameter];" not in manager:
    problems.append("the badge must be laid out after the icon geometry")
if "NFBBadgeFrame(" not in manager:
    problems.append("the badge rect must come from the shared inside-the-icon helper")
if "self.lastInteractionAt = CACurrentMediaTime();" in manager and "if (self.edgeExpanded) self.lastInteractionAt" in manager:
    problems.append("touch stamps must not be gated on edgeExpanded")

# 13. Tests must assert screen coordinates, not only local values.
if "rowImageCenterX" not in tests or "toggleImageCenterX" not in tests:
    problems.append("RailLayoutTests must assert image centres in screen coordinates")
if "NFBHalfHiddenAcceptsTouch" not in tests:
    problems.append("RailLayoutTests must cover the half-hidden hit test")
if "NFBBadgeInsideImage" not in tests:
    problems.append("RailLayoutTests must assert the badge stays inside the icon")
if "NFBHalfHiddenBubbleX" in tests:
    problems.append("RailLayoutTests still asserts the old local-x formula")

if problems:
    print("FAIL: rail layout checks\n - " + "\n - ".join(problems))
    sys.exit(1)
print("PASS: rail layout wiring (single geometry source, half-hidden whole column, screen-space assertions)")
