// Gesture policy for the top-column control (the collapse control outside a
// split, the house button inside one).
//
// The three gestures are a table, not scattered booleans: the manager, its
// gesture delegate and this file must agree on when a gesture acts and when it
// is refused, otherwise a hold that has no job either fires or turns itself into
// a tap. Plain C on purpose; CI compiles it with
//   clang -fobjc-arc -framework Foundation -I Sources Tests/ActionGestureTests.c
// and the file also builds without any Apple framework
//   clang -std=c11 -I Sources Tests/ActionGestureTests.c
// because the policy header only needs <stdbool.h>.
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include "NFBActionGesturePolicy.h"

static void check(bool condition, const char *message) {
    if (condition) return;
    fprintf(stderr, "FAIL: %s\n", message);
    exit(1);
}

int main(void) {
    // --- outside a split the control is the collapse control
    check(NFBActionModeFor(false, false) == NFBActionModeCollapsed, "collapsed outside a split");
    check(NFBActionModeFor(false, true) == NFBActionModeExpanded, "expanded outside a split");
    check(NFBActionModeFor(true, false) == NFBActionModeSplit, "a split wins even while folded");
    check(NFBActionModeFor(true, true) == NFBActionModeSplit, "a split wins while expanded");

    // --- split house button: its original tap and long press, nothing else
    check(NFBActionEffectFor(NFBActionModeSplit, NFBActionTap, true, false) == NFBActionToggleSplit,
          "split tap still toggles the desktop");
    check(NFBActionEffectFor(NFBActionModeSplit, NFBActionHold, true, false) == NFBActionOpenConsole,
          "split hold still opens the console");
    check(NFBActionEffectFor(NFBActionModeSplit, NFBActionSwipeLeft, true, false) == NFBActionNone,
          "split ignores the swipe");
    check(NFBActionGestureAllowed(NFBActionModeSplit, NFBActionSwipeLeft, true, false) == false,
          "split refuses the swipe before it can claim the touch");

    // --- collapsed: a tap or a left swipe unfolds, a hold does nothing
    check(NFBActionEffectFor(NFBActionModeCollapsed, NFBActionTap, true, false) == NFBActionUnfoldColumn,
          "collapsed tap unfolds");
    check(NFBActionEffectFor(NFBActionModeCollapsed, NFBActionSwipeLeft, true, false) == NFBActionUnfoldColumn,
          "collapsed left swipe unfolds");
    check(NFBActionEffectFor(NFBActionModeCollapsed, NFBActionHold, true, false) == NFBActionNone,
          "collapsed hold is a no-op");
    check(NFBActionGestureAllowed(NFBActionModeCollapsed, NFBActionHold, true, false) == false,
          "collapsed refuses the hold so it cannot turn into a tap");
    check(NFBActionGestureAllowed(NFBActionModeCollapsed, NFBActionTap, true, false) == true,
          "collapsed keeps its tap");

    // --- expanded: the tap folds, the hold clears unread, the swipe is a no-op
    check(NFBActionEffectFor(NFBActionModeExpanded, NFBActionTap, true, false) == NFBActionFoldColumn,
          "expanded tap folds");
    check(NFBActionEffectFor(NFBActionModeExpanded, NFBActionHold, true, false) == NFBActionClearUnread,
          "expanded hold clears unread");
    check(NFBActionEffectFor(NFBActionModeExpanded, NFBActionSwipeLeft, true, false) == NFBActionNone,
          "expanded left swipe is a no-op, never a fold");
    check(NFBActionGestureAllowed(NFBActionModeExpanded, NFBActionSwipeLeft, true, false) == false,
          "expanded refuses the swipe");
    check(NFBActionEffectFor(NFBActionModeExpanded, NFBActionTap, true, false) != NFBActionClearUnread,
          "an expanded tap never clears unread");

    // --- enabled / locked: nothing acts, in any mode, and nothing is claimed
    NFBActionMode modes[] = {NFBActionModeSplit, NFBActionModeExpanded, NFBActionModeCollapsed};
    NFBActionGesture gestures[] = {NFBActionTap, NFBActionHold, NFBActionSwipeLeft};
    for (unsigned m = 0; m < sizeof modes / sizeof modes[0]; m++) {
        for (unsigned g = 0; g < sizeof gestures / sizeof gestures[0]; g++) {
            check(NFBActionGestureAllowed(modes[m], gestures[g], false, false) == false,
                  "a disabled tweak refuses every gesture");
            check(NFBActionGestureAllowed(modes[m], gestures[g], true, true) == false,
                  "a locked device refuses every gesture");
            check(NFBActionEffectFor(modes[m], gestures[g], false, false) == NFBActionNone,
                  "a disabled tweak has no effect");
            check(NFBActionEffectFor(modes[m], gestures[g], true, true) == NFBActionNone,
                  "a locked device has no effect");
        }
    }

    // --- the swipe is registered for the left direction only
    check(NFBActionSwipeDirectionLeft == (1u << 3), "left is UISwipeGestureRecognizerDirectionLeft");
    check(NFBActionSwipeMatches(NFBActionSwipeDirectionLeft), "a left swipe matches");
    check(!NFBActionSwipeMatches(1u << 1), "a right swipe never matches");
    check(!NFBActionSwipeMatches(0), "no direction never matches");
    check(!NFBActionSwipeMatches(NFBActionSwipeDirectionLeft | (1u << 2)),
          "a mixed direction mask never matches");

    printf("PASS: control gestures (split unchanged, collapsed swipe-only unfold, expanded hold-only clear, disabled/locked inert)\n");
    return 0;
}
