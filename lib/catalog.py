"""The Arch package names an Omarchy tree can hand its package helpers.

    python3 lib/catalog.py [--calls] <tree>

Prints one line per reference, `name<TAB>context<TAB>file:line`, where context
is `base` (install/omarchy-base.packages, what a fresh install has), the helper
called (add, aur-add, install, aur-install, present, missing, drop, remove),
the install helper that forwards the name (install-app, install-and-launch,
install-font, install-terminal) or setup-input (the input method presets).
--calls leaves the base list out. A name computed at run time that no literal
array in the same file explains is printed with the context `unresolved`.

Only what the port can reach: Omarchy's installer (install/) and the
migrations are left out (omarchy-upstream-check reads each new migration), and
so are the update helpers the port's updater replaces.
"""

import json
import re
import shlex
import sys
from pathlib import Path

HELPERS = "add|aur-add|install|aur-install|present|missing|drop|remove"
CALL = re.compile(r"(?<![\w-])omarchy-pkg-(" + HELPERS + r")(?![\w-])")
# Install helpers that take the package list as one positional argument.
FORWARDERS = {
    "omarchy-install-app": 1,
    "omarchy-install-and-launch": 1,
    "omarchy-install-font": 1,
    "omarchy-install-terminal": 0,
}
FORWARD = re.compile(r"(?<![\w-])(" + "|".join(map(re.escape, FORWARDERS)) + r")(?![\w-])")
NAME = re.compile(r"^[a-z0-9@][a-z0-9+._@-]*$")
ARRAY_REF = re.compile(r'^"?\$\{([A-Za-z_][A-Za-z0-9_]*)\[@\]\}"?$')
ARRAY_START = re.compile(r"^\s*(?:local\s+|declare\s+-a\s+)?([A-Za-z_][A-Za-z0-9_]*)\+?=\(")
SCAN_DIRS = ["bin", "default", "config", "shell"]
# The package helpers themselves, and what upstream's omarchy-update runs that
# omarchy-update-ubuntu does in its own way.
SKIP = {
    "bin/omarchy-pkg-ubuntu",
    "bin/omarchy-update-keyring",
    "bin/omarchy-update-orphan-pkgs",
}
# Names a command reads at run time from a file this script also reads.
READ_ELSEWHERE = {"bin/omarchy-setup-input"}
SUFFIXES = {"", ".sh", ".jsonc", ".json", ".js", ".qml", ".lua"}
STRING_SUFFIXES = {".jsonc", ".json", ".js", ".qml"}


def logical_lines(text):
    """Lines with backslash continuations joined, numbered by their first line."""
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        start, buf = i, lines[i]
        while buf.endswith("\\") and i + 1 < len(lines):
            i += 1
            buf = buf[:-1] + " " + lines[i]
        yield start + 1, buf
        i += 1


def words(rest, in_string):
    """The shell words of a command's arguments, up to the end of the command."""
    if in_string:
        # In a JSON or JS string the command ends where the string does.
        rest = re.split(r'(?<!\\)"', rest, maxsplit=1)[0].replace('\\"', '"')
    lex = shlex.shlex(rest, posix=True, punctuation_chars=";&|()")
    lex.whitespace_split = True
    lex.commenters = "#"
    out = []
    try:
        for tok in lex:
            if tok and all(c in ";&|()" for c in tok):
                break
            out.append(tok)
    except ValueError:
        # A command quoted inside another ('omarchy-install-terminal foot'):
        # the quote that closes it ends the command.
        out = []
        for tok in rest.split():
            end = re.search(r"['\";&|()]", tok)
            if end:
                if end.start():
                    out.append(tok[: end.start()])
                break
            out.append(tok)
    return out


def arrays_in(text):
    """The literal entries of every array a file assigns, by array name."""
    found = {}
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        m = ARRAY_START.match(lines[i])
        if not m:
            i += 1
            continue
        body = lines[i][m.end():]
        while ")" not in re.sub(r"\$\([^)]*\)", "", body) and i + 1 < len(lines):
            i += 1
            body += " " + lines[i]
        for tok in body.split(")")[0].split():
            tok = tok.strip("\"'")
            if NAME.match(tok):
                found.setdefault(m.group(1), []).append(tok)
        i += 1
    return found


def names_in(arg):
    for name in arg.split():
        name = re.split(r"[<>=]", name)[0]
        if NAME.match(name):
            yield name


def calls(tree):
    for d in SCAN_DIRS:
        for path in sorted((tree / d).rglob("*")):
            rel = path.relative_to(tree).as_posix()
            if not path.is_file() or rel in SKIP or path.suffix not in SUFFIXES:
                continue
            try:
                text = path.read_text()
            except UnicodeDecodeError:
                continue
            in_string = path.suffix in STRING_SUFFIXES
            own_args = (
                rel.startswith("bin/omarchy-pkg-")
                or rel.removeprefix("bin/") in FORWARDERS
                or rel in READ_ELSEWHERE
            )
            arrays = None
            for n, line in logical_lines(text):
                if line.lstrip().startswith(("#", "//")):
                    continue
                where = f"{rel}:{n}"
                for m in CALL.finditer(line):
                    if line[m.end():].lstrip().startswith("()"):
                        continue
                    for w in words(line[m.end():], in_string):
                        if w.startswith("-"):
                            continue
                        ref = ARRAY_REF.match(w)
                        if ref:
                            if arrays is None:
                                arrays = arrays_in(text)
                            entries = arrays.get(ref.group(1), [])
                            for name in entries:
                                yield name, m.group(1), where
                            if not entries and not own_args:
                                yield w, "unresolved", where
                        elif "$" in w:
                            # The helpers and forwarders pass their own
                            # arguments on; their callers are read instead.
                            if not own_args:
                                yield w, "unresolved", where
                        else:
                            for name in names_in(w):
                                yield name, m.group(1), where
                for m in FORWARD.finditer(line):
                    if rel == f"bin/{m.group(1)}":
                        continue
                    args = words(line[m.end():], in_string)
                    idx = FORWARDERS[m.group(1)]
                    if len(args) > idx and "$" not in args[idx]:
                        for name in names_in(args[idx]):
                            yield name, m.group(1).removeprefix("omarchy-"), where


def main():
    args = sys.argv[1:]
    with_base = "--calls" not in args
    args = [a for a in args if a != "--calls"]
    if len(args) != 1:
        sys.exit("usage: catalog.py [--calls] <tree>")
    tree = Path(args[0])
    rows = []
    base = tree / "install/omarchy-base.packages"
    if with_base and base.exists():
        for n, line in enumerate(base.read_text().split("\n"), 1):
            line = line.split("#")[0].strip()
            if line:
                rows.append((line.split()[0], "base", f"install/omarchy-base.packages:{n}"))
    presets = tree / "default/input-methods/presets.json"
    if presets.exists():
        for method, spec in json.loads(presets.read_text()).items():
            for name in spec.get("packages", []):
                rows.append((name, "setup-input", f"default/input-methods/presets.json:{method}"))
    rows.extend(calls(tree))
    for row in rows:
        print("\t".join(row))


if __name__ == "__main__":
    main()
