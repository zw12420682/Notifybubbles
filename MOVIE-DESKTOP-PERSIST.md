# 0.49.34 trial: home swipe + persistent movie desktop

Based on 0.49.33 (1b65512). Independent fix/home-swipe-movie-persist branch. No official release change.

## Home swipe

- Zero began translation may be accepted only with upward recognizer velocity or positive native edge distance/velocity evidence; horizontal/downward/unknown direction remains original system behavior.
- Gentle upward completion threshold 40pt (previously 64pt), with existing 24pt fast-pull threshold, cancellation/reversal/horizontal guards retained.
- Capture explicit coordinator operationEpoch instead of the broad generation. Keyboard/layout synchronization alone must not invalidate an unchanged target. Actual scene identity, parent/host/region, app identity, master switch, lock and explicit user operations remain guarded.
- No delayed takeover after forwarding began; no unmatched system terminal events; strict saved-window native orange action remains once only.

## Movie desktop

- Only movie-owned desktop sessions are marked persistent. Existing manual/ordinary desktop sessions retain their original launch-close behavior.
- When lower portrait app appears, preserve movie desktop anchor/session/subtree and park our panel: finish any in-flight covered page refresh, suppress future refresh, hide panel, disable its interaction, release movie host leases, and relinquish native desktop focus if still held.
- While parked, native home hit-test cannot return hidden desktop content; native Open roots in the same host remain eligible. Hidden desktop safety checks continue without re-enabling its interaction.
- When lower portrait disappears and landscape survives, unpark same session without view transplant, page roundtrip, open animation or key-window acquisition. Subsequent real desktop touches can activate it normally.
- Movie exit, lock/disable, external desktop-tree ownership changes or system-hidden native window still tear down and restore native state. This is not a permanent hidden desktop lease.
- A desktop is created on first needed fallback, not eagerly when lower app is already present. Once created it persists through subsequent lower app cycles in that movie session.
- Pause does not hide the shared system home window or set its global interaction off. Existing manual desktop, mini ordering, notification and stow rules remain unchanged.

## Validation boundaries

Portable source/C regression plus UIKit simulator hook and desktop fixtures; actual SpringBoard/Open 1.3.7 behavior is NOT validated by those fixtures.

Device acceptance: full-screen A + Open B first swipe; zero/short/fast/cancelled/switched-target gesture; keyboard appearance without target change; movie lower app open/close at least 5 cycles, same page/widgets/no entry flash, no transparent blocker, top video controls/mini and lower app touch/keyboard/rotation; exit movie/lock/disable always restores ordinary desktop. Preserve existing long press and stow behavior.
