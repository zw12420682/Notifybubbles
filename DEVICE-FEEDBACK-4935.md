# 0.49.35 device-feedback trial

Independent fix/device-feedback-4935 worktree based on 0.49.34/cd0e8d3. Official release stays 0.49.24.

Evidence: supplied shared-50FD78AD_nfb-debug.log, pid57611. Rejected began samples (15,-5), (-6,-5.6667), (5,-5), (10.333,-6) had positive native upward edge velocity but failed the old vertical-majority/near-zero gates. At 09:23:59 lower app closed through orange tap; fallback consumed a 26.832x47.6784 offscreen closing frame, failed preflight, and remained black.

Changes:
- On the already-verified bottom tongue/recognizer and capable exact Open target, accept small diagonal began samples with up displacement >1pt, upward speed >20pt/s, positive native distance/velocity, lateral displacement <=24pt and <=8x upward displacement. Pure horizontal, downward and larger lateral quick switches remain original. No late takeover of forwarded began. Completion stays vertical and cancellation never invokes native close. A diagonal stream captured at began cannot send underlying A a system-home tail.
- Split X skips closeDesktop only for the currently active movie-owned matching desktop session. Lower pane uses existing native orange close and parked desktop resumes. Closing the last landscape still tears down through existing movie reconciliation. Non-movie/manual desktop behavior unchanged.
- Single portable lower-geometry validator gates reference cache writes/reads and fallback reference selection. Reject nonfinite, undersized, offscreen or top-band frames. Invalid historical reference falls back to the normal portrait footprint.
- Validate lower geometry BEFORE assigning movie anchor. Validate anchor BEFORE consuming first fallback attempt. No periodic forced reopening, new timers or hidden retry loop. Non-geometry desktop failures remain one-shot and reported rather than being automatically masked.

Regression: production-header C tests replay device began samples; UIKit hook fixture replays diagonal starts and requires no system callback while closing saved B; geometry C tests include exact black-screen dimensions; source guards check X ownership and validation-before-write/attempt ordering. Existing desktop parking cycle fixture retained.

Device acceptance still required: full-screen A+Open B natural diagonal start must close B without returning A home; pure horizontal and downward gestures unchanged; cancelled pull leaves B; movie X lower app close repeatedly restores desktop with no new session/entry refresh; first movie fallback after lower close must not consume shrinking frame. Test upper-video close, keyboard, manual desktop and lock/disable restoration too. Local/CI success is not real-device acceptance.
