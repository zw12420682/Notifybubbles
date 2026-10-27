"""Static guards for Objective-C constructs the portable tests cannot compile.

The plain-C tests and validate.py run on every host, but the tweak's Objective-C
only builds in macOS CI. These rules catch the mistakes that broke a build (and
that no C test can see):

  1. a property whose type is a C struct, *unless* it is only ever assigned as a
     whole (the getter returns a temporary, so `self.x.field = ...` is
     "expression is not assignable" and `&self.x` is the address of a temporary);
  2. an Objective-C object passed to a `const void *` parameter without the
     __bridge cast ARC requires;
  3. the same selector defined twice in one @implementation (a redefinition, or
     - worse - one definition silently replacing the other);
  4. a state property that this change added and that is written but never read
     (dead state added since BASE_REF that reads like a working guard). Older
     properties are left alone: this guard is for new code, not a history lesson.

It is a source scan on purpose: no clang, no SDK, no network, and it can never
weaken a behavioural assertion.
"""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
# Only state added by this change is judged; the pre-0.48.88 properties are
# untouched code and their cleanup is not this release's job.
BASE_REF = "b499be9"
import subprocess
base_written = set()
for base_source in sorted((root / "Sources").glob("*.m")):
    try:
        base_text = subprocess.run(
            ["git", "-C", str(root), "show", BASE_REF + ":Sources/" + base_source.name],
            capture_output=True, text=True, check=True).stdout
    except Exception:
        continue
    base_written |= set(re.findall(r"\bself\.(\w+)\s*=[^=]", base_text))
    base_written |= set(re.findall(r"^\s*_(\w+)\s*=[^=]", base_text, re.M))
sources = sorted((root / "Sources").glob("*.[mh]"))
assert sources, "no sources found"

typedefs = set()
for path in sources:
    typedefs.update(re.findall(r"\}\s*([A-Za-z_]\w*)\s*;", path.read_text()))

# Both owned implementation blocks that may declare methods.
class_blocks = {}
for path in sources:
    text = path.read_text()
    for match in re.finditer(r"@implementation\s+(\w+)(.*?)@end", text, re.S):
        class_blocks.setdefault(path.name, []).append((match.group(1), match.group(2)))

problems = []
for path in sources:
    text = path.read_text()
    lines = text.split("\n")
    for index, line in enumerate(lines, 1):
        match = re.match(r"\s*@property[^;]*?\)\s*([A-Za-z_]\w*)\s+(\w+)\s*;", line)
        if match and match.group(1) in typedefs:
            name = match.group(2)
            field_write = re.search(r"\bself\.%s\.\w+\s*=[^=]" % re.escape(name), text)
            address = re.search(r"&(?:self\.|_)%s\b" % re.escape(name), text)
            if field_write or address:
                problems.append("%s:%d: C struct property %s is used as an lvalue/address"
                                % (path.name, index, name))
        # ARC: an object handed to a C pointer parameter needs __bridge.
        for call in re.finditer(r"NFBProbe(?:Record|Reusable)\(.*", line):
            arguments = call.group(0)
            if re.search(r"\(\s*const void \*\s*\)\s*self\.", arguments):
                problems.append("%s:%d: const void * without __bridge" % (path.name, index))

    # 3. Duplicate selectors inside the same @implementation of the same class.
    #    A class may have several @implementation blocks (a second one is a
    #    category), so collect per class across the file.
    seen = {}
    for class_name, body in class_blocks.get(path.name, []):
        for match in re.finditer(r"^[-+]\s*\([^)]*\)\s*(.+?)\{", body, re.M):
            signature = match.group(1)
            keywords = re.findall(r"([A-Za-z_]\w*)\s*:\s*\([^)]*\)", signature)
            name = ":".join(keywords) + ":" if keywords else signature.strip()
            key = (class_name, name)
            if key in seen:
                problems.append("%s: -[%s %s] defined twice" % (path.name, class_name, name))
            seen[key] = True

    # 4. Written but never read: `self.x = ...` / `_x = ...` with no other use.
    # UIKit's own accessibility state is set to make the view usable, not read
    # back by us; it is not our state.
    written = set(re.findall(r"\bself\.(\w+)\s*=[^=]", text))
    written |= set(re.findall(r"^\s*_(\w+)\s*=[^=]", text, re.M))
    for name in written - base_written - {"accessibilityTraits", "isAccessibilityElement"}:
        reads = re.findall(r"\bself\.%s\b(?!\s*=[^=])" % re.escape(name), text)
        reads += re.findall(r"(?<!\w)_%s\b(?!\s*=[^=])" % re.escape(name), text)
        if not reads:
            problems.append("%s: self.%s is written but never read" % (path.name, name))

if problems:
    for problem in problems:
        print("FAIL:", problem)
    raise SystemExit(1)
print("PASS: no struct lvalues, unbridged probes, duplicate selectors or write-only state")
