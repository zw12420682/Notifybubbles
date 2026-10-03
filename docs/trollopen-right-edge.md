# TrollOpen 1.3.7 right-edge adapter

Evidence from the user-supplied binary (thin arm64 image, offsets here are build-specific):
- FloatingAppWindow exposes rightTouchRegion (object return).
- At 0xc9a390..0xc9a3cc, rightTouchRegion and bottomTouchRegion are placed in bottomLikeTouchRegions.
- Gesture setup at 0xc9f730 / 0xc9f738 selects handleBottomSingleTap: for initWithTarget:action:.
- handleBottomSingleTap: (0xe175a8, v24@0:8@16) reads gesture state and calls TOJBMETHOD256 (0xe17d9c / 0xe181b4).
- TOJBMETHOD064: is a different action and is not called by this adapter.

Version 0.48.11 removes all direct reads of UIGestureRecognizerTarget action storage from the close adapter and edge diagnostics. The supplied SpringBoard crash (2026-09-28 20:08:32) shows NotifyBubbles -> NSStringFromSelector -> strlen with EXC_BAD_ACCESS and a possible pointer-authentication failure. The failure occurred while inspecting the private action pointer, before dispatching the TrollOpen close handler.

The adapter now registers the known handleBottomSingleTap: name with NSSelectorFromString, checks its object-argument/void-return signature, and invokes it using objc_msgSend with an ended tap proxy. It still validates that rightTouchRegion belongs to the selected visible expanded window. No private target/action reads, PAC stripping, raw function addresses or generic-close fallback are used. On-device behavior of the original handler still needs testing; local validation cannot establish device compatibility.
