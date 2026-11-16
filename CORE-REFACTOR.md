# Unified split core — development branch

Baseline: 0.48.154 (6711f7d). Main/stable worktree is unchanged.

## First increment (0.49.0, not a completed rewrite)
- NFBSplitCoordinator owns enabled/locked/movie/keyboard state, phase and scene generation.
- NFBSplitBackend hides the current Open lifecycle entry points. Fake backend tested in UIKit simulator.
- Manager layout and desktop dismissal enter the coordinator. Keyboard settling is gated there.
- Auto movie desktop ownership binds to actual desktop session identifier.
- Geometry lease is updated only when a destination was actually applied.
- Host level lease yields after an external change until the host presentation ends.
- Portrait selection uses the same attachment resolver as the rail.

## Remaining migration before recommending daily use
- Move keyboard retry scheduling and cleanup retry scheduling into coordinator; bind both scene and session generation.
- Replace polling-derived booleans with explicit scene snapshots including known/temporarily unknown/closed.
- Move movie geometry calculation into platform-neutral planner and host hit-test/level lease into scoped components.
- Desktop mutation ledger needs apply/rollback phases and failure injection coverage.
- Preserve current public gesture behavior and ordinary split geometry.
- Never add automatic movie unlock recovery or ordinary-home page recovery.

## Scope update — Open only
The user paused independent split-engine development. This branch integrates the existing Open-backed movie, desktop, level, touch and keyboard logic. The backend boundary is kept for isolation and testing, not as a commitment to build another engine.

## Second increment (0.49.1)
- Movie keyboard retry scheduling is in the coordinator and validates scene identity and generation.
- Movie geometry uses NFBSplitLayout.h, with compiled numerical tests.
- Cleanup desktop fallback scheduling now belongs to the coordinator, binds exact desktop session plus user-operation epoch, and retains the manager's foreground/notification cancellation guard.
- Desktop identity can legitimately change when cleanup removes an old pane. Do not bind cleanup to that disappearing Open scene; backend validates any new lower app before fallback.
- Added UIKit fixture checks for successful cleanup fallback, cancelling pending fallback by user close, and denying fallback after a superseding app guard.

Pending: desktop mutation phases/rollback failure tests, explicit known/unknown/closed snapshots, full extraction of level and hit-test leases. No merge to stable until reviewed and device tested.

## Verification
Run scripts/validate.py and all portable test scripts. CI builds both packaging schemes and runs the desktop UIKit fixture with SplitCoordinatorFixture.h.
Simulator tests do not prove SpringBoard/Open private API compatibility. Device validation required before merging to main.
