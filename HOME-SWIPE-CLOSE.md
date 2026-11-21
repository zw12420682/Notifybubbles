# 0.49.33 home-swipe close trial

Based on 0.49.32 / 699e560; independent feat/home-swipe-close branch. Does not change the official 0.49.24 release.

## Contract

- With a proven, expanded Open 1.3.7 native orange single-tap target, an upward bottom-edge pull is owned from began through terminal callbacks.
- Bind the exact window, orange region, parent/host, app identity, foreground scene snapshot, coordinator generation and master-switch epoch at began.
- A completed upward pull invokes the saved window's native orange single-tap action once. No system home transaction is started through the owned callback quartet. No process killing, global close-current, direct close fallback, relaunch of the underlying app, or custom two-window exit.
- Cancellation/short pull or a changed target/foreground/lock/switch/session consumes the owned tail without closing or sending an unmatched end to the system. A subsequent new gesture can use the new state.
- No proven target, incompatible runtime ABI, disabled plugin, lock screen, side tongue, horizontal/downward gesture: original behavior. No new full-screen overlay, recognizer, timer or preference.
- While a split upward gesture is owned, it is a split-close gesture, not an app-switcher gesture. Native system handling resumes on the next gesture without an expanded target.
- Existing arrow stow gestures, long-press background clearing, floating-window controls, layout, keyboard rules and notification handling are unchanged.

## Interface evidence and limits

Public declarations: lechium/iPhone_OS_15.5/System/Library/PrivateFrameworks/SpringBoard/SBFluidSwitcherGestureManager.h and MTACS/iOS-17-Runtime-Headers/PrivateFrameworks/SpringBoard.framework/{SBFluidSwitcherGestureManager,SBGrabberTongue,SBPanSystemGestureRecognizer}.h.

Call-chain cross-check: SuperChaoM/iPhone15-3_17.6.1_21G101_Restore/System/Library/PrivateFrameworks/SpringBoard.framework/SBFluidSwitcherGestureManager.m. Deck tongue callbacks directly enter the switcher pan began/changed/ended path. These are NOT an iOS 16.0.3 binary or evidence of a device test. Before installing ANY hook, all four actual callbacks must have void(id,double,double,id) ABI and all three object getters must exist with compatible ABI. Otherwise install nothing. The runtime ABI check does not prove callback invocation on the user's device.

Orange action and ABI are from the user's Open 1.3.7 binary and the existing NFBRightEdgeTap adapter. The new path intentionally does not use the older button's Open 2.x or direct-close fallback.

## Device acceptance (not yet performed)

1. Full-screen A, open expanded B: swipe up -> B closes through orange action; A stays visible, no home flash. Next swipe -> ordinary system behavior.
2. Same operation with rail fully stowed and half-exposed restore arrow.
3. On home, open B, swipe up: native B close only, launcher remains usable.
4. Cancel/short pull: B remains, A does not go home.
5. Start pull, then change/close/minimize target, lock, disable, or change foreground: no retarget, no duplicate close, no unmatched system end.
6. No split, mini-only, disabled: home and switcher gestures unchanged. Horizontal quick switch and downward reachability unchanged.
7. Existing portrait/landscape/desktop-host/mini combinations: verify native orange semantics, no invented double-close or extra desktop action.
8. Confirm debug install/captured/orange-close messages. If no capture, inspect live iOS 16 callbacks; do not guess a second hook or cover the bottom with an overlay.

Portable C/source tests and UIKit fixtures are separate from SpringBoard/Open device acceptance. CI compilation and fixture success must not be reported as real-device validation.
