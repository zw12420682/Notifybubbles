#pragma once
#include <stdbool.h>

// Which of the collapse control's three gestures may act in a given state.
// The slot is a house button inside a split and a collapse control outside one:
//   split      tap = toggle the desktop split, hold = Open console (unchanged)
//   expanded   tap = fold, hold = clear unread records and keep it expanded
//   collapsed  tap = unfold, a left swipe on the visible control = unfold too,
//              hold = nothing
// One table keeps the manager, the delegate and the tests on the same rules.

typedef enum {
    NFBActionModeSplit = 0,
    NFBActionModeExpanded = 1,
    NFBActionModeCollapsed = 2,
} NFBActionMode;

typedef enum {
    NFBActionTap = 0,
    NFBActionHold = 1,
    NFBActionSwipeLeft = 2,
} NFBActionGesture;

// Only split mode owns a bottom close button. Expanded/collapsed edge columns
// clear unread through the top control's hold gesture, not a second bottom key.
static inline bool NFBBottomCloseVisible(bool split) { return split; }

static inline NFBActionMode NFBActionModeFor(bool split, bool expanded) {
    if (split) return NFBActionModeSplit;
    return expanded ? NFBActionModeExpanded : NFBActionModeCollapsed;
}

// A locked device or a disabled tweak never acts, in any mode.
static inline bool NFBActionGestureAllowed(NFBActionMode mode, NFBActionGesture gesture, bool enabled, bool locked) {
    if (!enabled || locked) return false;
    switch (mode) {
        case NFBActionModeSplit:
            return gesture == NFBActionTap || gesture == NFBActionHold;
        case NFBActionModeExpanded:
            return gesture == NFBActionTap || gesture == NFBActionHold;
        case NFBActionModeCollapsed:
            // A tap or a left swipe unfolds; a hold has no job here, so it is
            // refused before it can act or turn itself into a tap.
            return gesture == NFBActionTap || gesture == NFBActionSwipeLeft;
    }
    return false;
}

// What the handlers do. Split keeps its two original jobs; outside a split the
// gestures are one-way (a left swipe never folds again) and holding only clears
// unread records while the column is already expanded.
typedef enum {
    NFBActionNone = 0,
    NFBActionToggleSplit = 1,   // split: tap shows/closes the desktop
    NFBActionOpenConsole = 2,   // split: hold opens the Open console
    NFBActionFoldColumn = 3,    // expanded: tap folds
    NFBActionUnfoldColumn = 4,  // collapsed: tap or left swipe unfolds
    NFBActionClearUnread = 5,   // expanded: hold clears unread, stays expanded
} NFBActionEffect;

static inline NFBActionEffect NFBActionEffectFor(NFBActionMode mode, NFBActionGesture gesture, bool enabled, bool locked) {
    if (!NFBActionGestureAllowed(mode, gesture, enabled, locked)) return NFBActionNone;
    // Written out per cell instead of a chain of ternaries: the effect table is
    // what the handlers read, and each row has to be readable on its own.
    if (mode == NFBActionModeSplit)
        return (gesture == NFBActionTap) ? NFBActionToggleSplit : NFBActionOpenConsole;
    if (mode == NFBActionModeExpanded)
        return (gesture == NFBActionTap) ? NFBActionFoldColumn : NFBActionClearUnread;
    if (gesture == NFBActionSwipeLeft) return NFBActionUnfoldColumn;
    if (gesture == NFBActionTap) return NFBActionUnfoldColumn;
    return NFBActionNone;
}

// Swipe direction as recognised by UISwipeGestureRecognizerDirectionLeft.
#define NFBActionSwipeDirectionLeft (1u << 3)

// The swipe is registered on the control for the left direction only, so a
// right swipe can never fold (or toggle) the column.
static inline bool NFBActionSwipeMatches(unsigned long directions) {
    return (directions & NFBActionSwipeDirectionLeft) != 0 && (directions & ~(unsigned long)NFBActionSwipeDirectionLeft) == 0;
}
