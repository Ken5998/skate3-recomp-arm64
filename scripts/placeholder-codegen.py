#!/usr/bin/env python3
"""Writes a stand-in for the code `rexglue codegen` generates from the game,
so the port can be compiled and linked without the game (in CI).

    scripts/placeholder-codegen.py SKATE3

SKATE3 is the Skate 3 Recomp tree prepare.sh made. It writes
SKATE3/generated (the game, project skate3) and SKATE3/generated/eawebkit
(the EAWebkit module, project eawebkit) the way codegen lays them out, from
the SDK's own codegen templates.

Every project declares and defines (with empty bodies) only the recompiled
functions Skate 3 Recomp's own sources name, with made-up image addresses.
The result builds and links like the real thing but does nothing: it holds no
code or data of the game, and nothing built from it may be run.

Needs jinja2 (the codegen templates are inja, which jinja2 reads).
"""
import re
import sys
from pathlib import Path

import jinja2

root = Path(sys.argv[1])
sdk = root / "third_party" / "rexglue-sdk"


class CBool:
    """A flag that tests like a bool and prints as C++ (false/true)."""

    def __init__(self, value: bool):
        self.value = value

    def __bool__(self):
        return self.value

    def __str__(self):
        return "true" if self.value else "false"


env = jinja2.Environment(
    loader=jinja2.FileSystemLoader(str(sdk / "resources" / "templates")),
    keep_trailing_newline=True)
env.globals["cmake_var"] = lambda name: "${" + name + "}"


def render(name: str, values: dict) -> str:
    return env.get_template(f"codegen/{name}.inja").render(**values)


sources = sorted(p for p in (root / "src").rglob("*") if p.suffix in (".cpp", ".h", ".inc", ".mm"))
named = set()
helpers = set()
for path in sources:
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    text = re.sub(r"//[^\n]*|/\*.*?\*/", "", text, flags=re.S)
    named.update(re.findall(r"(?<![0-9A-Za-z])sub_[0-9A-F]{8}(?!\w)", text))
    # The register save/restore helpers codegen names __savegprlr_N and so on.
    helpers.update(re.findall(r"(?<!\w)__(?:save|rest)[a-z]+_[0-9]+(?!\w)", text))

projects = [
    # (project, output folder, image base, function names)
    ("skate3", root / "generated", 0x82000000, sorted(named) + sorted(helpers)),
    ("eawebkit", root / "generated" / "eawebkit", 0x8A000000, []),
]
for project, out, image_base, names in projects:
    out.mkdir(parents=True, exist_ok=True)
    values = {
        "project": project,
        "is_dll": CBool(False),
        "has_dll_modules": False,
        "image_base": f"0x{image_base:08X}", "image_size": "0x4000000",
        "code_base": f"0x{image_base + 0x100000:08X}", "code_size": "0x2000000",
        "thunk_reserve_size": "0x10000",
        "rexcrt_heap": CBool(False),
        "config_flags": {k: CBool(False) for k in (
            "skip_lr", "ctr_as_local", "xer_as_local", "reserved_as_local",
            "skip_msr", "cr_as_local", "non_argument_as_local", "non_volatile_as_local")},
        "functions": [{"name": n, "address": f"0x{n[4:]}" if n.startswith("sub_")
                       else f"0x{image_base + 0x80000 + 0x10 * i:08X}",
                       "below_code_base": False, "is_import": False}
                      for i, n in enumerate(names)],
        "recomp_files": [f"{project}_recomp.0.cpp"],
        "dll_modules": [],
    }
    files = {
        f"{project}_init.h": render("init_h", values),
        f"{project}_init.cpp": "// Placeholder (scripts/placeholder-codegen.py): not the game.\n"
                               + render("init_cpp", values),
        f"{project}_register.cpp": render("register_cpp", values),
        f"{project}_recomp.0.cpp": f'#include "{project}_init.h"\n\n'
                                   + "".join(f"DEFINE_REX_FUNC({n}) {{ (void)ctx; (void)base; }}\n"
                                             for n in names),
        "sources.cmake": render("sources_cmake", values),
    }
    for name, text in files.items():
        (out / name).write_text(text)
    print(f"Placeholder {project}: {len(names)} functions in {out}")
