#!/usr/bin/env python3
"""Stage C: the Forth-built GCC 4.0.4 builds libgcc and musl 1.1.24.

Usage:
    python3 gcc-direct/stage-c.py WORK --binutils BINUTILS_WORK \\
        --oyacc OYACC --flex FLEX [-j JOBS] [--resume]

BINUTILS_WORK is a finished gcc-direct/binutils.py run; its as-new, ld-new, ar,
nm-new, objdump and readelf are checked against its stage-B report and copied
into WORK/toolchain (ranlib there is a two-line `ar s` script).  OYACC and
FLEX are the Forth-built parser generators census.py needs.  Steps, in order:

1. inputs   musl's pinned tarball (gcc64/SOURCES) and every file of the
            unpacked source tree (build-out/stage-c-inputs) are verified.
2. headers  musl's original Makefile installs its headers into
            WORK/sysroot/usr/include (`install-headers`, no compiler).
3. configure  configure.py runs the original libiberty (--alloca-frame),
            libcpp and gcc configure scripts with the frozen Forth compiler.
            GCC additionally gets --with-binutils WORK/toolchain and
            --with-sysroot WORK/sysroot, so it is a native compiler whose
            target headers and libraries are WORK/sysroot/usr/{include,lib}
            (4.0.4 then sets SYSTEM_HEADER_DIR there, so limits.h is
            generated against musl's) and whose as/ld are ours.
4. cc1      census.py --link builds libiberty, every cc1 object, libcpp and cc1.
5. driver   GCC's Makefile builds xgcc, cpp, collect2 and specs.
6. libgcc   GCC's Makefile builds the target libraries with ./xgcc and
            ./cc1 (GCC_FOR_TARGET): `stmp-multilib` = libgcc.a, libgcov.a and
            crtbegin/crtend/crtbeginS/crtendS/crtbeginT.  STMP_FIXINC is
            empty (no fixincludes; gsyslimits.h is installed as
            include/syslimits.h, as gcc64/build-gcc4.sh does).
7. install  `make install` into WORK/gcc/install (bin/gcc, libexec cc1,
            lib/gcc/.../4.0.4/{include,libgcc.a,crt*.o}).
8. musl     musl's original configure and Makefile, out of tree in
            WORK/musl-build, with CC=WORK/gcc/install/bin/gcc and our ar;
            installed with DESTDIR=WORK/sysroot (prefix /usr).
9. hello    tests/gcc/stage-c-hello.c (printf, snprintf, malloc, qsort,
            strtol, string functions, long double output, a stdio file round
            trip and a 128-bit division) is compiled and statically linked by
            that gcc alone (`gcc -static -O2`: default startfiles and libraries
            from the sysroot and the installed libgcc), run under a minimal
            environment, and its output compared with
            tests/gcc/stage-c-hello.expected; nm must show libgcc's __divti3.

Every make/configure after step 3 runs with WORK/gcc/guard first in PATH, so
any host compiler, assembler or linker use is blocked and logged in
WORK/gcc/host-tool-attempts.jsonl.  The GCC that compiles libgcc, musl and
hello is xgcc + cc1 built in step 4-5 by the Forth compiler; it is never the
host's.  No GCC or musl source file is patched: GCC 4.0.4's
config/i386/linux-unwind.h names `struct ucontext`, which musl provides because
gcc/tsystem.h defines _GNU_SOURCE (musl's signal.h then maps __ucontext to
ucontext); its `struct siginfo` is only in the i386 branch, unused here.
Build-tree adjustments (all recorded in the step logs): the combined-tree
links ../libiberty, ../libcpp, ../build-TRIPLE/libiberty and ../binutils/{ar,
ranlib}; STMP_FIXINC emptied in the configured Makefile; gsyslimits.h as
include/syslimits.h; install-tools/include created before `make install`.

WORK/stage-c/report.json and report.md record each step (command, exit,
seconds, log), the input and output hashes and the hello result.  With
--resume, steps already recorded as successful in an existing WORK are skipped.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shlex
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "gcc-direct"))
import configure  # noqa: E402  (verify_source, PACKAGES)

TRIPLE = configure.TRIPLE
BINUTILS = {"gas/as-new": "as", "ld/ld-new": "ld", "binutils/ar": "ar",
            "binutils/nm-new": "nm", "binutils/objdump": "objdump", "binutils/readelf": "readelf"}
MUSL = {"archive": "musl-1.1.24.tar.gz", "top": "musl-1.1.24",
        "inputs": "build-out/stage-c-inputs", "source": "musl-source"}
COMPONENTS = {"libiberty": ["--forth-ar", "--alloca-frame"], "libcpp": ["--forth-ar"], "gcc": ["--forth-ar"]}
HELLO = ROOT / "tests/gcc/stage-c-hello.c"
HELLO_EXPECTED = ROOT / "tests/gcc/stage-c-hello.expected"
STEPS = ("inputs", "headers", "configure", "cc1", "driver", "libgcc", "install", "musl", "hello")


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


class Recipe:
    def __init__(self, work, args):
        self.work, self.args = work, args
        self.out = work / "stage-c"
        self.out.mkdir(parents=True, exist_ok=True)
        self.state = self.out / "steps.json"
        self.steps = json.loads(self.state.read_text()) if self.state.is_file() else {}
        self.toolchain = work / "toolchain"
        self.sysroot = work / "sysroot"
        self.gcc_build = work / "gcc/build/gcc"
        self.install = work / "gcc/install"
        self.gcc = self.install / "bin/gcc"

    def save(self):
        self.state.write_text(json.dumps(self.steps, indent=2) + "\n")

    def run(self, name, command, cwd, environment, log=None):
        """Run one command of a step, appending to the step's log."""
        log = log or self.out / f"{name}.log"
        started = time.time()
        with log.open("ab") as stream:
            stream.write(("\n$ (cd " + str(cwd) + ") " + shlex.join(map(str, command)) + "\n").encode())
            stream.flush()
            result = subprocess.run([str(c) for c in command], cwd=cwd, env=environment,
                                    stdout=stream, stderr=subprocess.STDOUT)
        record = {"command": [str(c) for c in command], "cwd": str(cwd), "returncode": result.returncode,
                  "seconds": round(time.time() - started, 1), "log": str(log)}
        self.steps.setdefault(name, {"commands": []})["commands"].append(record)
        self.save()
        if result.returncode:
            raise StepFailed(f"{name}: exit {result.returncode} from {command[0]}; see {log}")
        return record

    def target_environment(self):
        """GCC's recorded configure environment, guards first in PATH."""
        recorded = json.loads((self.work / "gcc/configure-command.json").read_text())
        environment = os.environ.copy()
        environment.update(recorded["environment"])
        environment["LC_ALL"] = "C"
        return environment

    def gcc_overrides(self):
        libiberty = self.work / "libiberty/build/libiberty/libiberty.a"
        return ["CFLAGS=", "LDFLAGS=", f"BISON={self.args.oyacc}", f"FLEX={self.args.flex}",
                f"LIBIBERTY={libiberty}", f"BUILD_LIBIBERTY={libiberty}",
                f"CPPLIB={self.work / 'libcpp/build/libcpp/libcpp.a'}"]

    # 1 -------------------------------------------------------------------
    def step_inputs(self):
        report = json.loads((self.args.binutils / "stage-b/report.json").read_text())
        recorded = {tool["path"]: tool for tool in report["tools"]}
        self.toolchain.mkdir(exist_ok=True)
        tools = {}
        for path, name in BINUTILS.items():
            source = self.args.binutils / "build/top" / path
            if not recorded.get(path, {}).get("built") or sha(source) != recorded[path]["sha256"]:
                raise StepFailed(f"{source} differs from its stage-B report")
            shutil.copy2(source, self.toolchain / name)
            tools[name] = {"from": str(source), "sha256": sha(self.toolchain / name)}
        ranlib = self.toolchain / "ranlib"
        ranlib.write_text(f"#!/bin/sh\nexec {shlex.quote(str(self.toolchain / 'ar'))} s \"$@\"\n")
        ranlib.chmod(0o755)
        configure.PACKAGES.setdefault("musl", MUSL)
        source = ROOT / MUSL["inputs"] / MUSL["source"]
        proof = configure.verify_source(source.resolve(), (ROOT / MUSL["inputs"] / MUSL["archive"]).resolve(), "musl")
        (self.out / "musl-source-inputs.json").write_text(json.dumps(proof, indent=2) + "\n")
        return {"binutils": tools, "musl_archive_sha256": proof["archive_sha256"],
                "musl_files": len(proof["files"])}

    # 2 -------------------------------------------------------------------
    def musl_source(self):
        return (ROOT / MUSL["inputs"] / MUSL["source"]).resolve()

    def step_headers(self):
        build = self.work / "musl-headers"
        build.mkdir(exist_ok=True)
        self.run("headers", ["make", "-f", self.musl_source() / "Makefile", f"srcdir={self.musl_source()}",
                             "ARCH=x86_64", "prefix=/usr", f"DESTDIR={self.sysroot}", "install-headers"],
                 build, dict(os.environ, LC_ALL="C"))
        headers = sorted(p for p in (self.sysroot / "usr/include").rglob("*") if p.is_file())
        return {"headers": len(headers)}

    # 3 -------------------------------------------------------------------
    def step_configure(self):
        for component, options in COMPONENTS.items():
            command = [sys.executable, ROOT / "gcc-direct/configure.py", "--component", component,
                       *options, "--work", self.work / component]
            if component == "gcc":
                command += ["--with-binutils", self.toolchain, "--with-sysroot", self.sysroot]
            self.run("configure", command, ROOT, os.environ.copy())
        return {"components": list(COMPONENTS)}

    # 4 -------------------------------------------------------------------
    def step_cc1(self):
        self.run("cc1", [sys.executable, ROOT / "gcc-direct/census.py", self.work, "--oyacc", self.args.oyacc,
                         "--flex", self.args.flex, "--link", "-j", str(self.args.jobs)], ROOT, os.environ.copy())
        return {"cc1_sha256": sha(self.gcc_build / "cc1")}

    # 5 -------------------------------------------------------------------
    def step_driver(self):
        self.run("driver", ["make", "-j", str(self.args.jobs), *self.gcc_overrides(),
                            "xgcc", "cpp", "collect2", "specs"], self.gcc_build, self.target_environment())
        return {name: sha(self.gcc_build / name) for name in ("xgcc", "cpp", "collect2", "specs")}

    # 6 -------------------------------------------------------------------
    def step_libgcc(self):
        include = self.gcc_build / "include"
        include.mkdir(exist_ok=True)
        syslimits = include / "syslimits.h"
        if not syslimits.exists():
            shutil.copyfile(gcc_source(self.work) / "gcc/gsyslimits.h", syslimits)
        # libgcc.mk re-enters this Makefile with MAKEOVERRIDES= (for the crt
        # objects), so LIBIBERTY/BUILD_LIBIBERTY/CPPLIB overrides are lost
        # and the defaults must resolve: ../libiberty, ../libcpp and
        # ../build-TRIPLE/libiberty, the combined-tree layout (gcc64/build-gcc4.sh
        # links build-TRIPLE to its build directory the same way).
        top = self.gcc_build.parent
        links = {top / "libiberty": self.work / "libiberty/build/libiberty",
                 top / "libcpp": self.work / "libcpp/build/libcpp",
                 top / f"build-{TRIPLE}/libiberty": self.work / "libiberty/build/libiberty"}
        # The Makefile computes AR/RANLIB_FOR_TARGET from ../binutils/ar and
        # ../binutils/ranlib, else (native) the host-side $(AR), which here is
        # the Forth archive adapter and cannot index GNU-as objects.
        links.update({top / "binutils/ar": self.toolchain / "ar",
                      top / "binutils/ranlib": self.toolchain / "ranlib"})
        for link, target in links.items():
            if not link.is_symlink():
                link.parent.mkdir(exist_ok=True)
                link.symlink_to(target, target_is_directory=target.is_dir())
        # No fixincludes (musl's headers need no fixing, and fixincludes would
        # be another host program).  A command-line STMP_FIXINC= does not
        # survive libgcc.mk's MAKEOVERRIDES=, so the configured Makefile's one
        # line is changed, exactly as gcc64/build-gcc4.sh does.
        makefile = self.gcc_build / "Makefile"
        text = makefile.read_text()
        if "\nSTMP_FIXINC = stmp-fixinc\n" in text:
            makefile.write_text(text.replace("\nSTMP_FIXINC = stmp-fixinc\n", "\nSTMP_FIXINC =\n", 1))
        elif "\nSTMP_FIXINC =\n" not in text:
            raise StepFailed("configured Makefile has no STMP_FIXINC line")
        self.run("libgcc", ["make", "-j", str(self.args.jobs), *self.gcc_overrides(),
                            "stmp-multilib"], self.gcc_build, self.target_environment())
        parts = ["libgcc.a", "libgcov.a", "crtbegin.o", "crtend.o", "crtbeginS.o", "crtendS.o", "crtbeginT.o"]
        return {name: sha(self.gcc_build / name) for name in parts}

    # 7 -------------------------------------------------------------------
    def step_install(self):
        # 4.0.4's install-mkheaders installs into install-tools/include
        # without creating it (gcc64/build-gcc4.sh makes it first, too).
        (self.install / f"lib/gcc/{TRIPLE}/4.0.4/install-tools/include").mkdir(parents=True, exist_ok=True)
        self.run("install", ["make", *self.gcc_overrides(), "MAKEINFO=true", "install"],
                 self.gcc_build, self.target_environment())
        return {"gcc": sha(self.gcc)}

    # 8 -------------------------------------------------------------------
    def step_musl(self):
        build = self.work / "musl-build"
        build.mkdir(exist_ok=True)
        environment = self.target_environment()
        for key in ("CPP", "CXX", "CXXCPP", "CC_FOR_BUILD", "AS", "LD", "NM"):
            environment.pop(key, None)
        environment.update({"CC": str(self.gcc), "CFLAGS": "", "CPPFLAGS": "", "LDFLAGS": "",
                            "AR": str(self.toolchain / "ar"), "RANLIB": str(self.toolchain / "ranlib")})
        self.run("musl", ["/bin/sh", self.musl_source() / "configure", "--target=x86_64", "--host=x86_64",
                          "--disable-shared", "--prefix=/usr", "--syslibdir=/lib"], build, environment)
        tools = ["CROSS_COMPILE=", f"AR={self.toolchain / 'ar'}", f"RANLIB={self.toolchain / 'ranlib'}"]
        self.run("musl", ["make", "-j", str(self.args.jobs), *tools], build, environment)
        self.run("musl", ["make", *tools, f"DESTDIR={self.sysroot}", "install"], build, environment)
        lib = self.sysroot / "usr/lib"
        return {name: sha(lib / name) for name in ("libc.a", "crt1.o", "crti.o", "crtn.o")}

    # 9 -------------------------------------------------------------------
    def step_hello(self):
        directory = self.work / "hello"
        directory.mkdir(exist_ok=True)
        environment = {"PATH": str(self.work / "gcc/guard") + ":/usr/bin:/bin", "LC_ALL": "C"}
        shutil.copyfile(HELLO, directory / "hello.c")
        self.run("hello", [self.gcc, "-v", "-static", "-O2", "-o", "hello", "hello.c"], directory, environment)
        self.run("hello", ["./hello"], directory, environment, log=directory / "stdout")
        output = (directory / "stdout").read_bytes()
        printed = output.split(b"\n", 2)[2] if output.startswith(b"\n$ ") else output
        expected = HELLO_EXPECTED.read_bytes()
        if printed != expected:
            raise StepFailed(f"hello output differs from {HELLO_EXPECTED}; see {directory / 'stdout'}")
        symbols = subprocess.run([self.toolchain / "nm", directory / "hello"], capture_output=True,
                                 text=True, check=True).stdout.split()
        if "__divti3" not in symbols:
            raise StepFailed("hello did not link libgcc's __divti3")
        return {"hello_sha256": sha(directory / "hello"), "output_matches": True,
                "libgcc_divti3_linked": True}

    def report(self, failure):
        lines = [f"# Stage C: {'complete' if not failure else 'stopped: ' + failure}", "",
                 "The Forth-built GCC 4.0.4 (xgcc, cc1) with Forth-built binutils builds libgcc "
                 "and musl 1.1.24, then links and runs a static hosted program.", ""]
        for name in STEPS:
            step = self.steps.get(name)
            if not step:
                lines.append(f"- {name}: not reached")
                continue
            seconds = sum(c["seconds"] for c in step.get("commands", []))
            lines.append(f"- {name}: {'ok' if step.get('done') else 'FAILED'} ({seconds:.0f} s)")
            for key, value in sorted(step.get("result", {}).items()):
                lines.append(f"  - {key}: {json.dumps(value) if not isinstance(value, str) else value}")
        attempts = self.work / "gcc/host-tool-attempts.jsonl"
        count = len(attempts.read_text().splitlines()) if attempts.is_file() else 0
        lines += ["", f"Blocked host tool attempts (all steps, including configure probes): {count}"]
        (self.out / "report.md").write_text("\n".join(lines) + "\n")
        (self.out / "report.json").write_text(json.dumps({"failure": failure, "steps": self.steps,
                                                           "host_tool_attempts": count}, indent=2) + "\n")
        print("\n".join(lines))


def gcc_source(work):
    """The pinned GCC source tree configure.py ran gcc/configure from."""
    recorded = json.loads((work / "gcc/configure-command.json").read_text())
    return Path(recorded["command"][1]).parents[1]


class StepFailed(Exception):
    pass


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("work", type=Path)
    parser.add_argument("--binutils", type=Path, required=True, help="finished gcc-direct/binutils.py WORK")
    parser.add_argument("--oyacc", type=Path, required=True)
    parser.add_argument("--flex", type=Path, required=True)
    parser.add_argument("-j", "--jobs", type=int, default=6)
    parser.add_argument("--resume", action="store_true", help="skip steps already successful in WORK")
    args = parser.parse_args()
    if not 1 <= args.jobs <= 8:
        parser.error("jobs must be 1-8")
    args.binutils, args.oyacc, args.flex = (p.resolve() for p in (args.binutils, args.oyacc, args.flex))
    work = args.work.resolve()
    if work.exists() and not args.resume:
        parser.error(f"WORK exists (use --resume): {work}")
    work.mkdir(parents=True, exist_ok=True)
    recipe = Recipe(work, args)
    failure = None
    for name in STEPS:
        if recipe.steps.get(name, {}).get("done"):
            continue
        recipe.steps[name] = {"commands": []}
        print(f"[stage-c] {name}", flush=True)
        try:
            result = getattr(recipe, "step_" + name)()
        except (StepFailed, RuntimeError, OSError, KeyError) as error:
            failure = f"{name}: {error}"
            recipe.steps[name]["error"] = str(error)
            recipe.save()
            break
        recipe.steps[name].update(done=True, result=result)
        recipe.save()
    recipe.report(failure)
    return 1 if failure else 0


if __name__ == "__main__":
    sys.exit(main())
