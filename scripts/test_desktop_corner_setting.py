from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]
p=plistlib.loads((r/"Preferences/Resources/Root.plist").read_bytes())
assert not any(x.get("key")=="DesktopCornerRadius" for x in p["items"])
h=(r/"Sources/NFBDesktopHost.m").read_text()
assert "NFBConfiguredDesktopRadius" not in h
assert "CFSTR(\"DesktopCornerRadius\")" not in h
assert "CGFloat radius = 14.0;" in h
assert "panel.layer.cornerRadius = 14.0;" in h
print("PASS: appearance radius setting removed; fixed original 14pt hosted desktop corner")
