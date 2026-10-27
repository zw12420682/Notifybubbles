"""Static guards for Objective-C constructs the portable tests cannot compile.

The plain-C tests and validate.py run on every host, but the tweak's Objective-C
only builds in macOS CI. These rules catch the mistakes that broke a build (and
that no C test can see):

  1. a property whose type is a C struct, *unless* it is only ever assigned as a
     whole (the getter returns a temporary, so `self.x.field = ...` is
     "expression is not assignable" and `&self.x` is the address of a temporary);
  2. an Objective-C object passed to a `const void *` parameter without the
     __bridge cast ARC requires;
  3. the same selector defined twice inside one class (a redefinition, or -
     worse - one definition silently replacing the other);
  4. new state that is written but never read (dead state that reads like a
     working guard). "New" means: added since 0.48.88. CI checks out shallow, so
     without git history the rule only watches Sources/NFBManager.m (the one file
     this change adds state to); everything older is left alone.

A source scan on purpose: no clang, no SDK, no network, and it can never weaken
a behavioural assertion.
"""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
BASE_REF = "b499be9"
NEW_STATE_SCOPE = {"NFBManager.m"}

sources = sorted((root / "Sources").glob("*.[mh]"))
assert sources, "no sources found"

# Baseline: writes that already existed in BASE_REF, per file.
base_written_by_file = {}
for base_source in sorted((root / "Sources").glob("*.m")):
    try:
        base_text = subprocess.run(
            ["git", "-C", str(root), "show", BASE_REF + ":Sources/" + base_source.name],
            capture_output=True, text=True, check=True).stdout
    except Exception:
        continue
    per_file = set(re.findall(r"\bself\.(\w+)\s*=[^=]", base_text))
    per_file |= set(re.findall(r"^\s*_(\w+)\s*=[^=]", base_text, re.M))
    base_written_by_file[base_source.name] = per_file
base_available = bool(base_written_by_file)

typedefs = set()
for path in sources:
    typedefs.update(re.findall(r"\}\s*([A-Za-z_]\w*)\s*;", path.read_text()))

class_blocks = {}
for path in sources:
    text = path.read_text()
    for match in re.finditer(r"@implementation\s+(\w+)(.*?)@end", text, re.S):
        class_blocks.setdefault(path.name, []).append((match.group(1), match.group(2)))

problems = []
for path in sources:
    text = path.read_text()
    for index, line in enumerate(text.split("\n"), 1):
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
            if re.search(r"\(\s*const void \*\s*\)\s*self\.", call.group(0)):
                problems.append("%s:%d: const void * without __bridge" % (path.name, index))

    # 3. Duplicate selectors inside one class.
    seen = {}
    for class_name, body in class_blocks.get(path.name, []):
        for match in re.finditer(r"^[-+]\s*\([^)]*\)\s*(.+?)\{", body, re.M):
            signature = match.group(1)
            keywords = re.findall(r"([A-Za-z_]\w*)\s*:\s*\([^)]*\)", signature)
            name = ":".join(keywords) + ":" if keywords else signature.strip()
            if (class_name, name) in seen:
                problems.append("%s: -[%s %s] defined twice" % (path.name, class_name, name))
            seen[(class_name, name)] = True

    # 4. New state written but never read. UIKit's accessibility state is set to
    #    make the view usable, not read back by us; it is not our state.
    written = set(re.findall(r"\bself\.(\w+)\s*=[^=]", text))
    written |= set(re.findall(r"^\s*_(\w+)\s*=[^=]", text, re.M))
    if base_available:
        known = base_written_by_file.get(path.name, set())
    else:
        if path.name not in NEW_STATE_SCOPE:
            continue
        known = set()
    for name in written - known - {"accessibilityTraits", "isAccessibilityElement"}:
        reads = re.findall(r"\bself\.%s\b(?!\s*=[^=])" % re.escape(name), text)
        reads += re.findall(r"(?<!\w)_%s\b(?!\s*=[^=])" % re.escape(name), text)
        if not reads:
            problems.append("%s: self.%s is written but never read" % (path.name, name))

if problems:
    for problem in problems:
        print("FAIL:", problem)
    raise SystemExit(1)
if not base_available:
    print("NOTE: %s not in this clone; rule 4 scans %s only"
          % (BASE_REF, ", ".join(sorted(NEW_STATE_SCOPE))))
print("PASS: no struct lvalues, unbridged probes, duplicate selectors or write-only state")
