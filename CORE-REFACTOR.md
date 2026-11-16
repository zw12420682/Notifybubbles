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

## Future independent engine
Implement NFBSplitBackend first; extend it with typed scene handles, capabilities (multi-scene, orientation, keyboard hosting), exact-window close and async completion outcomes before switching away from Open.
The current backend protocol is an initial seam, not yet a complete native scene-hosting engine API.
Native engine must independently validate real scene rendering/input, keyboard focus, app lifecycle/audio, lock safety, fullscreen restoration and failure rollback on iOS 16.0.3.
No live hot-swap: backend replacement only while disabled and without desktop or movie session.

## Verification
Run scripts/validate.py and all portable test scripts. CI builds both packaging schemes and runs the desktop UIKit fixture with SplitCoordinatorFixture.h.
Simulator tests do not prove SpringBoard/Open private API compatibility. Device validation required before merging to main.
