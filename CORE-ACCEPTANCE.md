# Open unified core: tenth increment (0.49.11)

Stable worktree remains 0.48.154 / 6711f7d. This development branch still relies on Open.

## Entry audit
- Manager house: coordinator replaceWindowWithDesktop -> Open adapter -> exact portrait close / independent desktop anchor.
- Manager close button: coordinator closeDesktop / closeCurrentWindow. Both invalidate old cleanup and keyboard jobs.
- Manager current floating fullscreen (ordinary mode): coordinator fullscreenCurrentWindow. Movie current-app ignore rule unchanged.
- Manager other-app click: existing coordinator closeDesktop before app dispatch already invalidates pending tasks. The existing notification-authentication path remains unchanged.
- Hosted desktop icon launch: now calls beginUserWindowOperation before pendingApp and Open dispatch. Does not close desktop before confirmed app presentation.
- beginUserWindowOperation invalidates generation, operation and cleanup epochs, clears stored snapshot and cancels disposable desktop-return cover. It does NOT release live geometry or touch leases.
- Keyboard restoration and cleanup fallback remain bounded and backend/session guarded.
- Desktop periodic checks and rollback remain in DesktopHost and operate on its own session. Not all UIKit lifecycle work has moved into Coordinator.
- Open scene placement retries and notification/process cleanup still use existing specialized cancellation rules. No claim that all delayed callbacks are now one mechanism.
- ARC has its own verified TOJBW0/WatchMenuView ownership guard; it does not share the movie-host lease. It is intentionally unchanged, not rewritten merely for naming consistency.
- Native hitTest remains event-time UIKit hit testing within roots published from the movie observation; no synthetic or cross-window event forwarding.

## Behavioral scope retained
Normal portrait geometry, 4pt movie gap, desktop radius 0-100, two icon lists, current movie-app tap no-op, cleanup target scope, widget bounded page visit, ARC behavior, no automatic lock/unlock recovery.

## Device acceptance before stable merge
1. Open portrait app -> house replaces app with desktop (app stays in background) -> open another app from desktop -> desktop returns cleanly.
2. Repeat App/Desktop/App rapidly; repeat while an Open scene is rebuilding. No stale keyboard callback or desktop fallback can replace new app.
3. Movie + lower app: first keyboard show/hide, switch app while keyboard is up. Video aspect fit and final 4pt gap; rail does not cover keyboard.
4. Movie + automatic desktop: both areas touchable, blank area passes through; ARC display/buttons and dismissal keep native interaction.
5. Close upper movie: real desktop restored immediately; visual return lasts 0.28s. Rapid app reopen cancels cover. Check widget snapshots visually, including protected/remote widget surfaces.
6. New explicit window command during pending cleanup fallback cancels old fallback.
7. Lock/disable during any transition: no cover or input lease remains on lock screen. Do not reopen movie windows on unlock.
8. Two repeated lock/unlock cycles: inspect widgets; if blank, gather home-lock logs. The underlying intermittent widget issue is NOT claimed fixed by this refactor.

## Release gate
CI plus simulator tests are not proof of Open/SpringBoard private API compatibility. New transition visuals and actual ARC event delivery require device validation. Stop structural changes if acceptance finds no concrete defect; do not call this branch stable before user confirmation.
