#!/usr/bin/env python3
"""Independent bounded computed-include review; host CPP is an oracle only."""
from pathlib import Path
import ast
import hashlib
import importlib.util
import json
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / "tools/gcc-direct-cc.py"
spec = importlib.util.spec_from_file_location("review_direct_driver", DRIVER)
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def tokens(data):
    pattern = rb'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|/\*.*?\*/|//[^\n]*|[A-Za-z_][A-Za-z_0-9]*|[0-9]+|[^\s]'
    result = []
    for token in re.findall(pattern, data, re.S):
        if token.startswith((b"/*", b"//")):
            continue
        result.append(("string", ast.literal_eval(token.decode())) if token.startswith(b'"') else token)
    return result


def main():
    review_source = Path(__file__).read_bytes()
    work = Path(tempfile.mkdtemp(prefix="review-computed-", dir=ROOT / "build-out"))
    (work / "toolchain").mkdir()
    toolchain = driver.Toolchain(work / "toolchain")
    source = work / "root.c"
    includes = [work / "first", work / "second"]
    fixtures = {
        "a.h": "root_a __FILE__ __LINE__\n",
        "first/a.h": "first_a __FILE__ __LINE__\n",
        "second/a.h": "second_a __FILE__ __LINE__\n",
        "first/only.h": "only_header\n",
        "first/3": "line_three __FILE__ __LINE__\n",
        "first/space name.h": "space_header\n",
        "first/escaped\\n.h": "backslash_n_header\n",
        "first/double\\\\name.h": "double_backslash_header\n",
        'first/quoted\\"name.h': "escaped_quote_header\n",
        "first/ angle.h": "leading_space_header\n",
        "first/angle.h": "angle_header\n",
        "first/angle name.h": "internal_space_header\n",
        "first/dir/*x.h": "literal_block_comment_marker_header\n",
        "sub/entry.h": '#define CHILD "../peer.h"\nentry_before __FILE__ __LINE__\n#include CHILD\nentry_after __FILE__ __LINE__\n#define AFTER_CHILD(x) x __FILE__ __LINE__\n',
        "peer.h": '#define LEAF "sub/deep/leaf.h"\npeer_before __FILE__ __LINE__\n#include LEAF\npeer_after __FILE__ __LINE__\n',
        "sub/deep/leaf.h": '#define STR0(x) #x\n#define STR(x) STR0(x)\nleaf_before __FILE__ __LINE__\n#include STR(local.h)\nleaf_after __FILE__ __LINE__\n',
        "sub/deep/local.h": "actual_relative_leaf __FILE__ __LINE__\n",
        "first/local.h": "wrong_search_root\n",
        "no-final-newline.h": "header_without_newline __FILE__ __LINE__",
    }
    for name, contents in fixtures.items():
        path = work / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)

    good = {
        "nested_relative_and_return_location": '#define ENTRY "sub/entry.h"\nmain_before __FILE__ __LINE__\n#include ENTRY\nmain_after __FILE__ __LINE__\nAFTER_CHILD(done)\n',
        "quote_prefers_includer": '#define H "a.h"\n#include H\n',
        "angle_uses_include_order": '#define H <a.h>\n#include H\n',
        "quote_include_fallback": '#define H "only.h"\n#include H\n',
        "absolute_quote": '#define H "' + str(work / "first/only.h") + '"\n#include H\n',
        "absolute_angle": '#define H <' + str(work / "first/only.h") + '>\n#include H\n',
        "alias_chain": '#define H1 H2\n#define H2 H3\n#define H3 "a.h"\n#include H1\n',
        "function_argument_string": '#define ID(x) x\n#define NAME "only.h"\n#include ID(NAME)\n',
        "empty_macro_after_header": '#define H "only.h"\n#define EMPTY\n#include H EMPTY\n',
        "function_alias": '#define ID(x) x\n#define ALIAS ID\n#include ALIAS("only.h")\n',
        "function_returns_function": '#define ID(x) x\n#define OUTER() ID\n#include OUTER()("only.h")\n',
        "stringize_raw": '#define Q(x) #x\n#include Q(only.h)\n',
        "stringize_prescan": '#define Q0(x) #x\n#define Q(x) Q0(x)\n#define NAME only.h\n#include Q(NAME)\n',
        "stringize_line": '#define Q0(x) #x\n#define Q(x) Q0(x)\n#include Q(__LINE__)\n__FILE__ __LINE__\n',
        "pasted_macro_name": '#define HEADER "only.h"\n#define JOIN(a,b) a ## b\n#include JOIN(HEAD,ER)\n',
        "comments_around_operand": '#define H "only.h"\n#include /* before */ H /* after */\n__LINE__ __FILE__\n',
        "quoted_block_comment_marker": '#define ID(x) x\n#include ID("dir/*x.h")\nafter_include __LINE__ __FILE__\n',
        "line_comment_block_marker": '#define H "only.h"\n#include H // /* this is a line comment\nafter_include __LINE__ __FILE__\n',
        "multiline_comment": '#define H "only.h"\n#include H /* first\nsecond */\n__LINE__ __FILE__\n',
        "continued_operand": '#define H "only.h"\n#include \\\nH\n__LINE__ __FILE__\n',
        "inactive_nested": '#if 0\n#include UNDEFINED\n#if 1\n#include BAD(\n#endif\n#else\n#define H "only.h"\n#include H\n#endif\n__LINE__ __FILE__\n',
        "quoted_space": '#define H "space name.h"\n#include H\n',
        "quoted_backslash_n": '#define H "escaped\\n.h"\n#include H\n',
        "quoted_double_backslash": '#define H "double\\\\name.h"\n#include H\n',
        "quoted_escaped_quote": '#define H "quoted\\"name.h"\n#include H\n',
        "end_of_file_operand": '#define H "only.h"\n#include H',
        "header_without_final_newline": '#define H "no-final-newline.h"\n#include H\nroot_after __FILE__ __LINE__\n',
        "dynamic_file_guarded_self": '#ifndef SELF\n#define SELF\n#include __FILE__\n#endif\nself_after __FILE__ __LINE__\n',
        "macro_redefinition_after_return": '#define H "sub/entry.h"\n#include H\n#undef H\n#define H "only.h"\n#include H\n#define CALL(x) x + x\nCALL(7) __FILE__ __LINE__\n',
        "repeated_computed_includes": '#define H "only.h"\n' + '#include H\n' * 400 + '__LINE__ __FILE__\n',
    }
    records = []
    failures = []

    def positive(name, text, policy_reject=False):
        source.write_text(text)
        output = work / (name + ".i")
        host = subprocess.run(["cc", "-E", "-P", *["-I" + str(p) for p in includes], source], capture_output=True, timeout=60)
        if host.returncode:
            failures.append({"case": name, "issue": "oracle rejected", "stderr": host.stderr.decode(errors="replace")})
            return
        actual = subprocess.run([DRIVER, "-E", *["-I" + str(p) for p in includes], source, "-o", output], capture_output=True, timeout=60)
        record = {"case": name, "host_status": host.returncode, "forth_status": actual.returncode}
        if policy_reject:
            record["expected_explicit_angle_policy_rejection"] = actual.returncode == 30 and b"error 30" in actual.stderr and not output.exists()
            if not record["expected_explicit_angle_policy_rejection"]:
                failures.append(record)
        elif actual.returncode:
            record["stderr"] = actual.stderr.decode(errors="replace")
            failures.append(record)
        else:
            data = output.read_bytes()
            record["tokens_equal_host"] = tokens(data) == tokens(host.stdout)
            record["output_sha256"] = digest(data)
            if not record["tokens_equal_host"]:
                record["actual"] = data.decode(errors="replace")
                record["expected"] = host.stdout.decode(errors="replace")
                failures.append(record)
        records.append(record)

    for name, text in good.items():
        positive(name, text)
    # The shared macro engine already does not join a function macro name to
    # its '(' across a comment. Record this honestly, without widening the
    # computed-include fix into a claim of complete macro token handling.
    source.write_text('#define ID(x) x\n#include ID/**/("only.h")\nafter_include\n')
    shared_gap_actual = subprocess.run([DRIVER, "-E", *["-I" + str(p) for p in includes], source], capture_output=True, timeout=60)
    shared_gap_host = subprocess.run(["cc", "-E", "-P", *["-I" + str(p) for p in includes], source], capture_output=True, timeout=60)
    shared_gap = {"case": "function_call_separated_by_comment", "forth_status": shared_gap_actual.returncode, "host_status": shared_gap_host.returncode, "status": "known shared macro-engine gap" if shared_gap_actual.returncode == 30 and shared_gap_host.returncode == 0 else "changed behavior; inspect"}
    for name, text in {
        "angle_leading_space": '#define H < angle.h>\n#include H\n',
        "angle_trailing_space": '#define H <angle.h >\n#include H\n',
        "angle_internal_space": '#define H <angle name.h>\n#include H\n',
        "angle_function_substitution": '#define H(x) <x>\n#include H(angle.h)\n',
    }.items():
        positive(name, text, True)

    rejected = {
        "unknown": '#include MISSING\n',
        "integer": '#define H 42\n#include H\n',
        "character": "#define H 'a'\n#include H\n",
        "empty_macro": '#define H\n#include H\n',
        "empty_string": '#define H ""\n#include H\n',
        "empty_angle": '#define H <>\n#include H\n',
        "object_self_cycle": '#define H H\n#include H\n',
        "mutual_cycle": '#define H J\n#define J H\n#include H\n',
        "function_self_cycle": '#define H(x) H(x)\n#include H("only.h")\n',
        "two_strings": '#define H "only.h" "a.h"\n#include H\n',
        "trailing_identifier": '#define H "only.h" leftover\n#include H\n',
        "trailing_punctuation": '#define H "only.h";\n#include H\n',
        "angle_trailing_token": '#define H <only.h> extra\n#include H\n',
        "angle_unclosed": '#define H <only.h\n#include H\n',
        "angle_double_close": '#define H <only.h>>\n#include H\n',
        "parenthesized_string": '#define H ("only.h")\n#include H\n',
        "wide_string": '#define H L"only.h"\n#include H\n',
        "missing_quote_file": '#define H "absent.h"\n#include H\n',
        "missing_angle_file": '#define H <absent.h>\n#include H\n',
        "missing_nested_target": '#define H "missing-nested.h"\n#include H\n',
        "missing_extra_modes_target": '#define EXTRA_MODES_FILE "config/i386/i386-modes.def"\n#include EXTRA_MODES_FILE\n',
    }
    (work / "missing-nested.h").write_text('#define TARGET "missing-mode.def"\n#include TARGET\n')
    rejection_records = []
    for name, text in rejected.items():
        source.write_text(text)
        output = work / (name + ".o")
        original = b"previous exact output\x00\xff\n"
        output.write_bytes(original)
        actual = subprocess.run([DRIVER, "-c", *["-I" + str(p) for p in includes], source, "-o", output], capture_output=True, timeout=60)
        okay = actual.returncode == 30 and b"error 30" in actual.stderr and output.read_bytes() == original
        record = {"case": name, "forth_status": actual.returncode, "error_30_and_output_preserved": okay}
        rejection_records.append(record)
        if not okay:
            record["stderr"] = actual.stderr.decode(errors="replace")
            failures.append(record)

    # The original pinned target input is used verbatim, without reconstruction
    # or substitutions. The configured lookup root is the GCC source tree.
    gcc_root = ROOT / "build-out/direct-gcc-inputs/gcc-source/gcc"
    target = gcc_root / "config/i386/i386-modes.def"
    expected_target_hash = "0141dec67f7141c1f2bb4096ad18fb2a7628f4a7ea5258acd9dc736491c6330d"
    if target.is_file():
        target_hash = digest(target.read_bytes())
        includes.append(gcc_root)
        positive("original_pinned_i386_modes", '#define EXTRA_MODES_FILE "config/i386/i386-modes.def"\n#include EXTRA_MODES_FILE\n')
        includes.pop()
        original_output = work / "original_pinned_i386_modes.i"
        markers = ["ieee_extended_intel_96_format", "ieee_quad_format", "CCGC", "CCFPU", "TARGET_128BIT_LONG_DOUBLE"]
        content = original_output.read_bytes() if original_output.exists() else b""
        target_proof = {"input_sha256": target_hash, "pinned_input_unchanged": target_hash == expected_target_hash == digest(target.read_bytes()), "markers_present": {marker: marker.encode() in content for marker in markers}, "tokens_equal_host": records[-1].get("tokens_equal_host", False)}
        if not target_proof["pinned_input_unchanged"] or not all(target_proof["markers_present"].values()):
            failures.append(target_proof)
    else:
        target_proof = {"status": "NOT RUN", "reason": "pinned original target absent"}

    # Direct state assertions complement token tests: every computed include
    # must restore its scratch allocation, outer source region and sink.
    source.write_text(good["nested_relative_and_return_location"] + good["repeated_computed_includes"])
    forth = "cc-sysv-object-enable\n[lit] 8388608 cc-arena-map\n"
    forth += driver.path_word("review-source", source)
    forth += f"review-source [lit] {len(str(source).encode())} cc-prep-source-name\n"
    for index, path in enumerate(includes):
        forth += driver.path_word(f"review-inc-{index}", path)
        forth += f"review-inc-{index} [lit] {len(str(path).encode())} cc-prep-add-include\n"
    forth += ": review-assert 0= if, [lit] 99 cc-die then, ;\n"
    forth += ": review-main cc-load-stdin cc-preprocess\n"
    checks = [
        "cc-pp-scratch-top @ cc-pp-scratch =",
        "cc-prep-src-addr @ cc-in-buf =",
        "cc-prep-src-len @ cc-in-len @ =",
        "cc-prep-src-pos @ cc-in-len @ =",
        "cc-prep-in-file @",
        "cc-prep-inc-depth @ 0=",
        "cc-prep-inc-top @ 0=",
        "cc-pp-sink-depth @ 0=",
        "cc-pp-location-depth @ 0=",
        "cc-pp-out @ cc-src-buf =",
        "cc-pp-pending-nl @ 0=",
    ]
    forth += "\n".join(check + " review-assert" for check in checks)
    forth += "\nbye ;\nreview-main\n"
    try:
        toolchain.forth(toolchain.compiler, forth, source.read_bytes())
        state = {"status": "PASS", "assertions": checks}
    except driver.Failure as exc:
        state = {"status": "FAIL", "detail": str(exc)}
        failures.append(state)

    changed = [name for name, data in toolchain.inputs.items() if (ROOT / name).read_bytes() != data]
    if changed:
        failures.append({"source_changed_during_review": changed})
    if Path(__file__).read_bytes() != review_source:
        failures.append({"review_script_changed_during_review": str(Path(__file__))})
    report = {
        "status": "PASS" if not failures else "FAIL",
        "reference": "https://gcc.gnu.org/onlinedocs/cpp/Computed-Includes.html",
        "scope": "Quoted computed headers and angle results with no internal whitespace. GNU accepts the documented space-sensitive angle cases; this implementation deliberately rejects them with 30.",
        "oracle": "Host cc -E -P output token comparison only; all target preprocessing and state checks executed by the Forth seed.",
        "production_source_sha256": toolchain.hashes,
        "review_script_sha256": digest(review_source),
        "positive_and_policy_cases": records,
        "rejections": rejection_records,
        "state_restoration": state,
        "shared_macro_engine_limitation": shared_gap,
        "original_i386_target": target_proof,
        "failures": failures,
        "work_directory": str(work),
    }
    destination = ROOT / "tests/gcc/review-computed-include-results.json"
    destination.write_text(json.dumps(report, indent=2) + "\n")
    print(report["status"], len(good), "host-equal cases; 4 explicit angle limits;", len(rejected), "preserved-output rejections; state assertions", state["status"])
    print(destination)
    if failures:
        print(json.dumps(failures, indent=2))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
