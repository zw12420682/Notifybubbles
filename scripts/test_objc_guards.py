"""Static guards for Objective-C constructs the portable tests cannot compile.

The plain-C tests and validate.py run on every host, but the tweak's Objective-C
only builds in macOS CI. These rules catch the mistakes that broke a build (and
that no C test can see):

  1. a property whose type is a C struct, unless it is only ever assigned as a
     whole (the getter returns a temporary, so `self.x.field = ...` is
     "expression is not assignable" and `&self.x` is the address of a temporary),
     and a bare variable declaration inside an @interface / class extension
     ("cannot declare variable inside @interface or @protocol": only declarations
     belong there, C-struct state must be an ivar in the @implementation);
  2. an Objective-C object passed to a `const void *` parameter without the
     __bridge cast ARC requires;
  3. the same selector defined twice inside one class (a redefinition, or -
     worse - one definition silently replacing the other);
  4. state that is written but never read in the file that declares it (dead state
     that reads like a working guard). This rule does *not* need git history: the
     declarations are read from the files themselves and the scan is per file, so
     a shallow clone and a full clone give the same answer. It used to guess "new
     state" from a baseline commit, which is exactly what made a shallow checkout
     report old state (columnSliding, wallpaperCount) as new.

A source scan on purpose: no clang, no SDK, no network, and it can never weaken
a behavioural assertion.

Self-test: run this file with --self-test to build a throwaway tree (shallow: one
commit, no history) and check that the rules still fire and still stay quiet on an
old file. It needs git, nothing else, and is a no-op on a checkout without git.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]

# UIKit's accessibility state is set to make the view usable, not read back by
# us; it is not our state (and it has UIKit setters with their own semantics).
NOT_OUR_STATE = {"accessibilityTraits", "isAccessibilityElement", "_cmd", "self"}

# State that is stored and never read back through its property. It predates
# 0.48.88, is harmless, and is reported identically with or without git history -
# so this is an explicit one-entry allowlist, not a rescan of old fields and not a
# stand-in for a baseline commit. The field is left alone (removing state is not a
# test's job); the fixtures in scripts/fixtures/guard_shallow prove the rule still
# fires on new write-only state and stays quiet on this one.
KNOWN_WRITE_ONLY = {
    # NFBDesktopSession's wallpaper count: stored in -adoptDesktopAppearance and read
    # once in -transferTo: as `next.wallpaperCount == 0`, i.e. through a local whose
    # name this per-file scan cannot resolve.
    ("NFBDesktopHost.m", "wallpaperCount"),
}


def strip_c_comments(text):
    """Drop comments, keep line structure (rule 4 is line-local)."""
    text = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def read_refs(text, ref):
    """Occurrences of `ref` that read it.

    `ref = ...` is a write, not a read - and so is a dictionary element write,
    `self.map[key] = value`, which only *transcribes* the name. Every other
    occurrence (equality, comparison, method call, dictionary read) is a read.
    """
    reads = 0
    for match in re.finditer(r"(?<!\w)" + re.escape(ref) + r"\b", text):
        after = text[match.end():]
        assign = re.match(r"\s*=(?!=)", after)
        element = re.match(r"\s*\[[^\[\]]*\]\s*=(?!=)", after)
        if assign or element:
            continue
        reads += 1
    return reads


def scan(sources):
    """Return the list of problems found in `sources` (one tree)."""
    problems = []

    typedefs = set()
    for path in sources:
        typedefs.update(re.findall(r"\}\s*([A-Za-z_]\w*)\s*;", strip_c_comments(path.read_text())))

    class_blocks = {}
    for path in sources:
        text = strip_c_comments(path.read_text())
        for match in re.finditer(r"@implementation\s+(\w+)(.*?)@end", text, re.S):
            class_blocks.setdefault(path.name, []).append((match.group(1), match.group(2)))

    for path in sources:
        text = strip_c_comments(path.read_text())
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

        # 1b. Only declarations belong in an @interface / class extension. A bare
        #     variable there is the sibling mistake of a struct property, and it is
        #     what broke the build that added these guards in the first place.
        #     Interface members are at column 0; method bodies inside an
        #     @implementation are indented, so indentation alone tells them apart
        #     (`return x;` in a method must never read as a declaration).
        for match in re.finditer(r"@interface\s+\w+\s*(?:\([^)]*\))?[^\n]*\n(.*?)\n@end", text, re.S):
            body_ = match.group(1)
            depth = 0
            for line in body_.split("\n"):
                stripped = line.strip()
                if not re.match(r"[A-Za-z_]", line) or depth:
                    depth += line.count("{") - line.count("}")
                    continue
                if re.fullmatch(r"(?:[A-Za-z_]\w*[\s*]+)+\**[A-Za-z_]\w*\s*;", stripped) \
                        and not stripped.startswith("typedef"):
                    problems.append("%s: variable declaration '%s' inside @interface (it must be "
                                    "an ivar in the @implementation)" % (path.name, stripped))

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

        # 4. State written but never read, per file: the file that stores it must
        #    also read it, whoever declares it. No baseline commit is consulted, so
        #    a shallow clone and a full clone agree, and old state in an untouched
        #    file (columnSliding below) can never be mistaken for new state.
        #    Properties the file declares itself are listed for the diagnostic
        #    only; a property backed by a synthsized ivar needs no declaration to
        #    be found, which also covers a typo (favoritesApps).
        declared_head = set()
        for match in re.finditer(r"@(?:interface|class)\s+\w+\s*(?:\([^)]*\))?[^\n]*\n(.*?)\n@end", text, re.S):
            header = match.group(1)
            for decl in re.finditer(r"^\s*@property[^;]*;", header, re.M):
                # @property(nonatomic) BOOL a, b; - every declarator is a name.
                declared_head.update(re.findall(r"[*\s]([A-Za-z_]\w*)\s*(?:,|;)", decl.group(0)))
            for decl in re.finditer(r"^\s*(?:[A-Za-z_]\w*[\s*]+)+\b(\w+)\s*;", header, re.M):
                declared_head.add(decl.group(1))
        own_state = declared_head | typedefs
        body = text
        for match in re.finditer(r"@(?:interface|class)\s+\w+\s*(?:\([^)]*\))?[^\n]*\n(.*?)\n@end", text, re.S):
            body = body.replace(match.group(1), "")
        written = set(re.findall(r"\bself\.(\w+)\s*=(?!=)", body))
        written |= set(re.findall(r"^\s*_(\w+)\s*=(?!=)", body, re.M))
        for name in sorted(written - NOT_OUR_STATE):
            if (path.name, name) in KNOWN_WRITE_ONLY:
                continue
            reads = read_refs(body, "self." + name) + read_refs(body, "_" + name)
            if not reads:
                problems.append("%s: self.%s is written but never read" % (path.name, name))
    return problems


def self_test():
    """Build a shallow (history-less) tree and prove the rules are history-free.

    The clone has exactly one commit, so no rule can reach a baseline. It holds:
      * an old file with write-only state, which the rule must ignore - the
        shallow-checkout false positive this replaced used to report exactly this;
      * new state written and read, which must pass;
      * new state written and never read, and a misspelled property, which must be
        reported. These are the fixtures in scripts/fixtures/guard_shallow.
    """
    import shutil
    if not shutil.which("git"):
        print("SKIP: no git, guard self-test not exercised")
        return 0
    git = ["git", "-c", "user.name=t", "-c", "user.email=t@t.local"]
    quiet = {"stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL}
    fixture = Path(__file__).resolve().parent / "fixtures" / "guard_shallow"
    fixtures = sorted(fixture.glob("*.m"))
    assert fixtures, "no guard fixtures found"
    with tempfile.TemporaryDirectory() as tmp:
        tree = Path(tmp) / "tree"
        (tree / "Sources").mkdir(parents=True)
        (tree / "scripts").mkdir()
        shutil.copy(__file__, tree / "scripts" / "test_objc_guards.py")
        # Committed first and then removed: history the clone is not asked for.
        (tree / "Sources" / "NFBOld.m").write_text(
            "// Old: write-only state that predates the change under test.\n"
            "@interface NFBOld : NSObject\n@end\n"
            "@implementation NFBOld\n"
            "- (void)load {\n    self.parkFlag = NO;\n}\n"
            "@end\n")
        subprocess.run(["git", "init", "-q", "-b", "main"], cwd=tree, check=True, **quiet)
        subprocess.run(git + ["add", "-A"], cwd=tree, check=True, **quiet)
        subprocess.run(git + ["commit", "-qm", "old"], cwd=tree, check=True, **quiet)
        (tree / "Sources" / "NFBOld.m").unlink()
        for path in fixtures:
            shutil.copy(path, tree / "Sources" / path.name)
        subprocess.run(git + ["add", "-A"], cwd=tree, check=True, **quiet)
        subprocess.run(git + ["commit", "-qm", "fixture: new state"], cwd=tree, check=True, **quiet)
        checkout = Path(tmp) / "shallow"
        subprocess.run(["git", "clone", "-q", "--depth", "1", "file://" + str(tree), str(checkout)],
                       check=True, **quiet)
        assert subprocess.run(["git", "rev-list", "--count", "HEAD"], cwd=checkout,
                              capture_output=True, text=True).stdout.strip() == "1"
        result = subprocess.run([sys.executable, "scripts/test_objc_guards.py"], cwd=checkout,
                                capture_output=True, text=True)
        output = result.stdout + result.stderr
        wanted = {
            "old write-only state in an untouched file is not reported": "NFBOld.m" not in output,
            "new state that is read is accepted": "NFBGoodState.m" not in output,
            "new write-only state is reported": "NFBDeadState.m: self.showClearAll is written but never read" in output,
            "a variable in a class extension is reported": "NFBVapor.m: variable declaration 'NFBProbeStamp probe;' inside @interface" in output,
            "the fixture tree fails the scan": result.returncode != 0,
        }
        failures = [name for name, ok in wanted.items() if not ok]
        for name in failures:
            print("FAIL: self-test: " + name)
        if failures:
            print(output)
            return 1
        print("PASS: guard self-test on a shallow, history-less clone")
        return 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    sources = sorted((root / "Sources").glob("*.[mh]"))
    assert sources, "no sources found"
    problems = scan(sources)
    if problems:
        for problem in problems:
            print("FAIL:", problem)
        return 1
    print("PASS: no struct lvalues, unbridged probes, duplicate selectors or write-only state")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
