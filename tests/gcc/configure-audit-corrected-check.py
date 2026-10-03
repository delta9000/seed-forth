#!/usr/bin/env python3
"""Check repaired original probes and original gencheck without accepting a full GCC build."""
from pathlib import Path
import argparse
import json
import re
import runpy
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
helpers = runpy.run_path(str(ROOT / "tests/gcc/configure-audit-check.py"))
sha, verify, json_write = (helpers[key] for key in ("sha", "verify", "json_write"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work", type=Path)
    args = parser.parse_args()
    work = args.work.resolve()
    out = Path(tempfile.mkdtemp(prefix="configure-audit-corrected-", dir=ROOT / "build-out"))
    reports = {}
    for key, script in (("configure", "configure-audit-check.py"), ("gencheck", "configure-audit-gencheck.py")):
        result = subprocess.run([sys.executable, ROOT / "tests/gcc" / script, work],
                                capture_output=True, text=True, timeout=120)
        (out / (key + "-audit.stdout")).write_text(result.stdout)
        (out / (key + "-audit.stderr")).write_text(result.stderr)
        if result.returncode:
            raise RuntimeError(f"{key} audit failed: {result.stderr}")
        path = Path(result.stdout.splitlines()[0])
        reports[key] = {"path": str(path), "sha256": sha(path), "data": json.loads(path.read_text())}
    inventory = json.loads((work / "probe-inventory.json").read_text())
    probes = json.loads((Path(reports["configure"]["path"]).parent / "verified-probes.json").read_text())
    config = (work / "build/gcc/auto-host.h").read_text()
    config_log = (work / "build/gcc/config.log").read_text()
    macros = dict(re.findall(r"^#define (\w+)(?:[ \t]+([^\n]*))?$", config, re.M))
    if macros.get("BYTEORDER") != "1234" or any(name in macros for name in
            ("WORDS_BIGENDIAN", "HOST_WORDS_BIG_ENDIAN", "MKDIR_TAKES_ONE_ARG")):
        raise RuntimeError("known unsafe endian/mkdir configuration remains")
    ansi_state = re.findall(r"^ac_cv_prog_cc_stdc=(.*)$", config_log, re.M)
    if ansi_state not in ([""], ["''"]):
        raise RuntimeError(f"original ANSI probe still did not select empty successful option: {ansi_state}")

    observed = {}
    selectors = {"endian": "From Harbison&Steele", "mkdir": 'mkdir ("foo", 0)',
                 "ansi": "int pairnames (int, char **, FILE *(*)(struct buf *, struct stat *, int), int, int);"}
    for name, needle in selectors.items():
        matches = [p for p in probes if needle in p["body"]]
        if len(matches) != 1 or matches[0]["returncode"] != 0:
            raise RuntimeError(f"original {name} probe not uniquely successful: {matches}")
        probe = matches[0]
        observed[name] = {"trace": probe["trace"], "returncode": probe["returncode"],
                          "arguments": probe["arguments"], "input_sha256": probe["input_sha256"],
                          "output_sha256": probe["output_sha256"]}
        if name == "endian":
            original = inventory[probe["number"]]
            binary = work / original["trace"] / original["outputs"][0]["copy"]
            result = subprocess.run([binary], cwd=out, capture_output=True, timeout=30)
            observed[name]["execution_returncode"] = result.returncode
            observed[name]["execution_stdout"] = result.stdout.decode(errors="replace")
            observed[name]["execution_stderr"] = result.stderr.decode(errors="replace")
            if result.returncode or result.stdout or result.stderr:
                raise RuntimeError("original native endian executable did not run faithfully")

    source_root = Path(json.loads((work / "configure-command.json").read_text())["command"][1]).parent
    system = (source_root / "system.h").read_text()
    headers = work / "toolchain/runtime/gcc-seed/include"
    actual_headers = {name: (headers / name).read_text() for name in ("stdlib.h", "string.h", "stdio.h")}
    declarations = {
        "MALLOC": ("stdlib.h", "void *malloc(size_t size);", "extern void *malloc (size_t);"),
        "REALLOC": ("stdlib.h", "void *realloc(void *pointer, size_t size);", "extern void *realloc (void *, size_t);"),
        "CALLOC": ("stdlib.h", "void *calloc(size_t count, size_t size);", "extern void *calloc (size_t, size_t);"),
        "FREE": ("stdlib.h", "void free(void *pointer);", "extern void free (void *);"),
        "STRSTR": ("string.h", "char *strstr(const char *haystack, const char *needle);", "extern char *strstr (const char *, const char *);"),
        "SNPRINTF": ("stdio.h", "int snprintf(char *buffer, size_t size, const char *format, ...);", "extern int snprintf (char *, size_t, const char *, ...);")}
    declaration_evidence = {}
    for name, (header, provided, fallback) in declarations.items():
        if provided not in actual_headers[header] or fallback not in system:
            raise RuntimeError(f"fallback signature needs fresh review: {name}")
        matches = [p for p in probes if f"#undef HAVE_DECL_{name}\n" in p["body"]]
        if len(matches) != 1:
            raise RuntimeError(f"declaration probe missing: {name}")
        p = matches[0]
        declaration_evidence[name] = {"configured": macros.get("HAVE_DECL_" + name),
            "trace": p["trace"], "probe_returncode": p["returncode"],
            "runtime_header": header, "provided_declaration": provided, "fallback_declaration": fallback,
            "equivalence": "identical return and parameter types; only parameter names/whitespace differ"}

    known_unavailable = {}
    exports = {name for obj in reports["configure"]["data"]["runtime_object_symbols"].values()
               for name in obj["defined_global_symbols"]}
    for name, needle in (("getgroups", "n = getgroups ("), ("sscanf", 'sscanf(buf, "%p", &q)')):
        matches = [p for p in probes if needle in p["body"]]
        if len(matches) != 1 or name in exports:
            raise RuntimeError(f"{name} result needs fresh review")
        p = matches[0]
        known_unavailable[name] = {"trace": p["trace"], "returncode": p["returncode"],
                                   "symbol_present_in_runtime": False, "diagnostic": p["diagnostic"]}

    report = {"status": "original endian/ANSI/mkdir probes and exact original gencheck independently verified",
              "scope": "bounded native C-only generator evidence; no full configuration/libiberty/archive/GCC build claim",
              "original_work": str(work), "source_location_review": "separate review; no result inferred by this audit",
              "gcc_archive_sha256": reports["configure"]["data"]["gcc_archive_sha256"],
              "toolchain_manifest_sha256": sha(work / "toolchain-inputs.json"),
              "configure_report_sha256": sha(work / "report.json"),
              "auto_host_sha256": sha(work / "build/gcc/auto-host.h"),
              "configure_invocation_count": len(inventory),
              "configure_returncodes": reports["configure"]["data"]["returncodes"],
              "audit_script_sha256": sha(Path(__file__)), "reports": reports,
              "repaired_original_probes": observed, "ansi_cache_state": ansi_state,
              "declaration_fallbacks": declaration_evidence, "unavailable_runtime_interfaces": known_unavailable,
              "sizeof_and_layout": reports["configure"]["data"]["layout_stdout"]}
    json_write(out / "report.json", report)
    print(out / "report.json")


if __name__ == "__main__":
    main()
