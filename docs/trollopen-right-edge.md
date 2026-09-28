# TrollOpen 1.5.2 right-edge adapter

Evidence from the user-supplied binary (thin arm64 image, offsets here are build-specific):
- TOJBClass012 exposes rightTouchRegion (object return).
- At 0xc9a390..0xc9a3cc, rightTouchRegion and bottomTouchRegion are placed in bottomLikeTouchRegions.
- Gesture setup at 0xc9f730 / 0xc9f738 selects TOJBMETHOD063: for initWithTarget:action:.
- TOJBMETHOD063: (0xe175a8, v24@0:8@16) reads gesture state and calls TOJBMETHOD256 (0xe17d9c / 0xe181b4).
- TOJBMETHOD064: is a different action and is not called by this adapter.

The source does NOT invoke an offset or guess a binding. At runtime it checks the current window's rightTouchRegion, finds its enabled one-touch single-tap recognizer and verifies the target is that same window and selector is TOJBMETHOD063:. It then passes an ended UITapGestureRecognizer proxy to this original handler once. No synthetic screen touches, no termination override, no fallback to the old direct-close method. Unsupported bindings produce a notice and debug log. Actual on-device gesture binding and visible behavior still need confirmation.
