#!/usr/bin/env python3
"""Bounded source-only Forth C driver for GCC bootstrap experiments.

Python handles arguments, byte-preserving snapshots, hashes and publication.
The seed runs all preprocessing, compilation, object writing and linking.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "seed-forth direct C compiler (experimental)"
TARGET = "x86_64-pc-linux-gnu"
RUNTIME = "runtime/gcc-seed"
# Fixed per-translation-unit arena: complete original insn-emit.c measures
# 21,103,808 bytes. Round up to 21 MiB, keeping the legacy 32 KiB slab
# and native TinyCC 8 MiB driver unchanged. Never grow or retry on exhaustion.
ARENA_BYTES = 21 * 1024 * 1024
BASE = ("010-lib.fth", "020-cc-arena.fth", "030-cc-io.fth")
IDENT = r"[A-Za-z_][A-Za-z_0-9]*"
MACRO = re.compile(IDENT + r"(?:\(\s*(?:" + IDENT + r"(?:\s*,\s*" + IDENT + r")*)?\s*\))?\Z")


class Failure(Exception):
    def __init__(self, message, status=1):
        super().__init__(message)
        self.status = status


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(name, data):
    """Encode data as Forth bytes; never interpolate a pathname as source."""
    return "create " + name + "\n" + "".join(f"[lit] {b} c,\n" for b in data)


def path_word(name, path):
    return encoded(name, os.fsencode(path) + b"\0")


def checked_path(path, directory=False):
    # The preprocessor's path buffer also needs room for a trailing slash.
    if len(os.fsencode(path)) > (253 if directory else 254):
        raise Failure(f"path exceeds the Forth preprocessor limit: {path}")
    return path


def parse(arguments):
    options = {"mode": "link", "output": None, "includes": [], "macros": [],
               "inputs": [], "verbose": False, "nostdinc": False,
               "nostdlib": False, "query": None}
    mode = None
    language = None
    index = 0
    while index < len(arguments):
        arg = arguments[index]
        index += 1
        if arg == "--":
            options["inputs"].extend((a, language) for a in arguments[index:])
            break
        if arg in ("-c", "-E"):
            if mode and mode != arg:
                raise Failure("-c and -E cannot be combined", 2)
            mode = arg
            options["mode"] = "compile" if arg == "-c" else "preprocess"
        elif arg in ("--version", "-dumpmachine", "--print-source-hash"):
            if options["query"] and options["query"] != arg:
                raise Failure("conflicting information options", 2)
            options["query"] = arg
        elif arg == "-v":
            options["verbose"] = True
        elif arg in ("-static", "-O0", "-g0"):
            pass  # These describe the actual static, unoptimized, no-debug output.
        elif arg in ("-nostdinc", "-nostdlib"):
            options[arg[1:]] = True
        elif arg == "-x" or (arg.startswith("-x") and len(arg) > 2):
            if arg == "-x":
                if index == len(arguments):
                    raise Failure("missing argument to -x", 2)
                language = arguments[index]
                index += 1
            else:
                language = arg[2:]
            if language not in ("c", "none"):
                raise Failure(f"unsupported language: {language}", 2)
            if language == "none":
                language = None
        elif arg[:2] in ("-o", "-I", "-D", "-U"):
            flag, value = arg[:2], arg[2:]
            if not value:
                if index == len(arguments):
                    raise Failure(f"missing argument to {flag}", 2)
                value = arguments[index]
                index += 1
            if "\0" in value or "\n" in value or "\r" in value:
                raise Failure(f"invalid newline or NUL in {flag} argument", 2)
            if flag == "-o":
                if options["output"] is not None:
                    raise Failure("multiple output options", 2)
                options["output"] = value
            elif flag == "-I":
                if value == "-":
                    raise Failure("-I- is unsupported", 2)
                options["includes"].append(checked_path(Path(value).absolute(), True))
            else:
                name, separator, body = value.partition("=")
                if flag == "-U":
                    if separator or not re.fullmatch(IDENT, name):
                        raise Failure(f"invalid -U argument: {value}", 2)
                    directive = "#undef " + name + "\n"
                else:
                    if not MACRO.fullmatch(name):
                        raise Failure(f"unsupported -D macro spelling: {name}", 2)
                    directive = "#define " + name + " " + (body if separator else "1") + "\n"
                options["macros"].append(directive)
        elif arg == "-lm":
            options["inputs"].append((arg, "seed-library"))
        elif arg.startswith("-") and arg != "-":
            raise Failure(f"unsupported option: {arg}", 2)
        else:
            options["inputs"].append((arg, language))
    if options["query"]:
        if options["inputs"]:
            raise Failure("information options cannot be combined with inputs", 2)
        return options
    if not options["inputs"]:
        if options["verbose"]:
            return options
        raise Failure("no input files", 2)
    if options["mode"] != "link" and any(kind == "seed-library" for _, kind in options["inputs"]):
        raise Failure("-lm requires link mode", 2)
    if options["mode"] != "link" and options["output"] and len(options["inputs"]) != 1:
        raise Failure("a single -o requires one input with -c or -E", 2)
    if options["mode"] != "preprocess" and options["output"] == "-":
        raise Failure("binary output to standard output is unsupported", 2)
    return options


def input_names():
    return sorted(set(["000-seed.hex0", "seed-forth", "010-lib.fth",
                       "tools/gcc-direct-cc.py"]
                      + [p.name for p in ROOT.glob("[0-9][0-9][0-9]-cc-*.fth")
                         if p.name != "120-cc-main.fth"]
                      + (["141-archive.fth"] if (ROOT / "141-archive.fth").is_file() else [])
                      + [str(p.relative_to(ROOT)) for p in (ROOT / RUNTIME).rglob("*")
                         if p.is_file() and p.suffix in (".c", ".h")]))


class Toolchain:
    def __init__(self, work):
        names = input_names()
        self.inputs = {name: (ROOT / name).read_bytes() for name in names}
        if names != input_names() or any((ROOT / name).read_bytes() != data
                                        for name, data in self.inputs.items()):
            raise Failure("compiler inputs changed while taking the snapshot; retry")
        # Verify the existing executable against hex0 source. This comparison
        # does not generate an executable or substitute a host-built compiler.
        hexadecimal = b"".join(re.split(rb"[;#]", line, maxsplit=1)[0]
                               for line in self.inputs["000-seed.hex0"].splitlines())
        if bytes.fromhex(hexadecimal.decode("ascii")) != self.inputs["seed-forth"]:
            raise Failure("seed-forth does not match 000-seed.hex0; rebuild with build.sh")
        self.hashes = {name: digest(data) for name, data in self.inputs.items()}
        self.identity = digest(json.dumps(self.hashes, sort_keys=True).encode())
        self.work = work
        self.seed = work / "seed-forth"
        self.seed.write_bytes(self.inputs["seed-forth"])
        self.seed.chmod(0o700)
        self.runtime = work / "runtime"
        for name, data in self.inputs.items():
            if name.startswith(RUNTIME + "/"):
                path = self.runtime / name.removeprefix(RUNTIME + "/")
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
        self.compiler = ["010-lib.fth"] + [name for name in names
                          if re.fullmatch(r"\d{3}-cc-.*\.fth", name)
                          and name != "140-cc-link.fth"]

    def forth(self, modules, driver, source=b""):
        program = b"\n".join(self.inputs[name] for name in modules)
        result = subprocess.run([self.seed], input=program + b"\n" + driver.encode() + source,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.stderr:
            sys.stderr.buffer.write(result.stderr)
        if result.stdout:
            sys.stderr.buffer.write(result.stdout)
        if result.returncode:
            raise Failure("Forth compilation/link failed", result.returncode if result.returncode > 0 else 1)
        if result.stdout:
            raise Failure("unexpected Forth output; no result published")

    def compile(self, source, source_name, output, includes, macros=(), preprocess=False):
        source_name = checked_path(source_name)
        driver = f"cc-sysv-object-enable\n[lit] {ARENA_BYTES} cc-arena-map\n"
        driver += ("cc-io-direct-workspace cc-prep-direct-workspace\n"
                   "cc-om-direct-workspace cc-label-direct-workspace\n"
                   "cc-obj-direct-workspace cc-gfixup-direct-workspace\n")
        driver += path_word("driver-output", output)
        driver += path_word("driver-source", source_name)
        driver += f"driver-source [lit] {len(os.fsencode(source_name))} cc-prep-source-name\n"
        for index, include in enumerate(includes):
            checked_path(include, True)
            driver += path_word(f"driver-inc-{index}", include)
            driver += f"driver-inc-{index} [lit] {len(os.fsencode(include))} cc-prep-add-include\n"
        if macros:
            text = "".join(macros).encode()
            driver += encoded("driver-macros", text)
            # Forth processes real directives after target predefines. Reset
            # the output/line counters so command-line options add no lines.
            driver += ": driver-predefines cc-target-predefines\n"
            driver += "driver-macros cc-prep-src-addr !\n"
            driver += f"[lit] {len(text)} cc-prep-src-len !\n"
            driver += "[lit] 0 cc-prep-src-pos ! true cc-prep-in-file !\n"
            driver += "cc-pp-scan [lit] 0 cc-pp-out-pos ! [lit] 1 cc-src-line ! ;\n"
            driver += "' driver-predefines is cc-prep-target-fwd\n"
        if preprocess:
            driver += "variable driver-fd variable driver-done\n"
            driver += ": driver-main cc-load-stdin cc-preprocess\n"
            driver += "driver-output [lit] 577 [lit] 384 open dup 0< if, [lit] 22 cc-die then, driver-fd !\n"
            driver += "begin, driver-done @ cc-src-len @ < while,\n"
            driver += "driver-fd @ cc-src-buf driver-done @ + cc-src-len @ driver-done @ - write\n"
            driver += "dup [lit] 0 [lit] 4 - = if, drop else, dup [lit] 0 <= if, [lit] 22 cc-die then, driver-done +! then, repeat,\n"
            driver += "driver-fd @ close if, [lit] 22 cc-die then, bye ;\n"
        else:
            driver += ": driver-main cc-load-stdin cc-preprocess cc-out-init cc-globals-init\n"
            driver += "cc-sysv-object-program driver-output cc-obj-write bye ;\n"
        self.forth(self.compiler, driver + "driver-main\n", source)

    def runtime_objects(self):
        cache_root = ROOT / "build-out/gcc-direct-cache"
        cache_root.mkdir(parents=True, exist_ok=True)
        cache = cache_root / self.identity
        names = [Path(name).stem + ".o" for name in self.inputs
                 if name.startswith(RUNTIME + "/") and name.endswith(".c")
                 and name != RUNTIME + "/math.c"]
        names += ["syscall.o", "errno.o", "start.o", "frame.o", "sigreturn.o", "setjmp.o", "longjmp.o"]

        def verified():
            try:
                report = json.loads((cache / "manifest.json").read_text())
                return (report["source_sha256"] == self.hashes
                        and set(report["artifact_sha256"]) == set(names)
                        and all(digest((cache / name).read_bytes()) == report["artifact_sha256"][name]
                                for name in names))
            except (OSError, ValueError, KeyError, TypeError):
                return False

        if verified():
            # Copy verified bytes privately before consuming them. Verify
            # again, detecting a concurrently replaced/corrupted cache file.
            private = self.work / "runtime-objects"
            private.mkdir()
            report = json.loads((cache / "manifest.json").read_text())
            for name in names:
                data = (cache / name).read_bytes()
                if digest(data) != report["artifact_sha256"][name]:
                    raise Failure("runtime cache changed during read; retry")
                (private / name).write_bytes(data)
            return [private / name for name in names]
        # Never overwrite a damaged cache entry. It is not a trusted input.
        # Rebuild privately; a verified concurrent winner may remain cached.
        with tempfile.TemporaryDirectory(prefix=".build-", dir=cache_root) as directory:
            build = Path(directory)
            for source in sorted(self.runtime.glob("*.c")):
                if source.name == "math.c":
                    continue
                self.compile(source.read_bytes(), source, build / (source.stem + ".o"),
                             [self.runtime / "include"])
            driver = ""
            for name, builder in (("syscall", "cc-sysrt-object"),
                                  ("errno", "cc-sysrt-errno-object"),
                                  ("start", "cc-sysrt-runtime-start-object"),
                                  ("frame", "cc-sysrt-frame-object"),
                                  ("sigreturn", "cc-sysrt-sigreturn-object"),
                                  ("setjmp", "cc-sysrt-setjmp-object"),
                                  ("longjmp", "cc-sysrt-longjmp-object")):
                driver += path_word(name + "-path", build / (name + ".o"))
                driver += f"{builder} {name}-path cc-obj-write\n"
            self.forth(list(BASE) + ["081-cc-object.fth", "122-cc-sysv-runtime.fth"], driver + "bye\n")
            report = {"source_sha256": self.hashes,
                      "artifact_sha256": {name: digest((build / name).read_bytes()) for name in names},
                      "producer": VERSION, "host_compiler": False, "host_linker": False}
            (build / "manifest.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
            private = self.work / "runtime-objects"
            shutil.copytree(build, private)
            try:
                os.rename(build, cache)
            except OSError:
                if not cache.exists():
                    raise
            return [private / name for name in names]

    def runtime_archive(self, objects, name="libseed.a"):
        # Keep startup eager so its main reference precedes user archives.
        # All remaining runtime members are selected by the Forth linker
        # only when an unresolved symbol needs them.
        output = self.work / name
        driver = "arc-init\n" + path_word("driver-runtime-archive", output)
        for index, path in enumerate(objects):
            if path.name == "start.o":
                continue
            name = f"driver-runtime-member-{index}"
            driver += path_word(name, path) + f"{name} arc-add-object\n"
        driver += "driver-runtime-archive arc-write bye\n"
        self.forth(list(BASE) + ["140-cc-link.fth", "141-archive.fth"], driver)
        return output

    def math_archive(self):
        # This exact builtin library is source-built, never found in host
        # search paths. Explicit -lm remains explicit even with -nostdlib.
        archive = self.work / "libm.a"
        if archive.exists():
            return archive
        source = self.runtime / "math.c"
        if not source.is_file() or not (self.runtime / "include/math.h").is_file():
            raise Failure("-lm requires the source-built math.c and math.h", 2)
        output = self.work / "math.o"
        self.compile(source.read_bytes(), source, output, [self.runtime / "include"])
        return self.runtime_archive([output], "libm.a")

    def link(self, objects, output):
        archives = any(path.suffix == ".a" for path in objects)
        if archives and "141-archive.fth" not in self.inputs:
            raise Failure("archive input requires the Forth 141-archive.fth layer", 2)
        driver = "lnk-init\n"
        for index, path in enumerate(objects):
            driver += path_word(f"driver-obj-{index}", path)
            operation = "lnk-add-archive" if path.suffix == ".a" else "lnk-add-object"
            driver += f"driver-obj-{index} {operation}\n"
        driver += "create driver-entry s, _start\ndriver-entry [lit] 6 lnk-entry\n"
        driver += path_word("driver-output", output) + "driver-output lnk-link bye\n"
        self.forth(list(BASE) + ["140-cc-link.fth"] + (["141-archive.fth"] if archives else []), driver)


def publish(source, destination, mode):
    # Sibling private temporary plus rename: preserve an existing destination
    # on errors, and do not follow destination symlinks during publication.
    creation_mask = os.umask(0)
    os.umask(creation_mask)
    with tempfile.NamedTemporaryFile(prefix=".seed-cc-", dir=destination.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(source.read_bytes())
            stream.flush()
            os.fchmod(stream.fileno(), mode & ~creation_mask)
            os.fsync(stream.fileno())
            os.replace(temporary, destination)
        finally:
            temporary.unlink(missing_ok=True)


def main(arguments):
    options = parse(arguments)
    if options["query"] == "--version":
        print(VERSION + "\nTarget: " + TARGET + "\nStatic Linux AMD64 LP64; bounded C/runtime subset")
        return
    if options["query"] == "-dumpmachine":
        print(TARGET)
        return
    if options["verbose"]:
        print(VERSION + "\nTarget: " + TARGET, file=sys.stderr)
        if not options["inputs"] and not options["query"]:
            return
    inputs = []
    stdin_seen = False
    for spelling, language in options["inputs"]:
        if language == "seed-library":
            inputs.append((ROOT / RUNTIME / "math.c", "math", b""))
        elif spelling == "-":
            if stdin_seen or (language != "c" and options["mode"] != "preprocess"):
                raise Failure("stdin requires -x c (or -E), and can occur only once", 2)
            stdin_seen = True
            inputs.append((Path.cwd() / "<stdin>", "stdin", sys.stdin.buffer.read()))
        else:
            path = Path(spelling).absolute()
            kind = "c" if language == "c" or path.suffix == ".c" else path.suffix[1:] if path.suffix in (".o", ".a") else None
            if kind is None:
                raise Failure(f"unsupported input type: {spelling}; use -x c for C", 2)
            if kind in ("o", "a") and options["mode"] != "link":
                raise Failure("object/archive inputs require link mode", 2)
            inputs.append((path, kind, path.read_bytes()))
    destinations = []
    if options["mode"] == "link" and inputs:
        destinations = [Path(options["output"] or "a.out").absolute()]
    elif options["mode"] == "compile":
        destinations = [Path(options["output"] or (path.stem + ".o")).absolute() for path, _, _ in inputs]
    elif options["output"] and options["output"] != "-":
        destinations = [Path(options["output"]).absolute()]
    aliases = set()
    protected = [path for path, _, _ in inputs] + [ROOT / name for name in input_names()]
    for destination in destinations:
        resolved = destination.resolve()
        if resolved in aliases:
            raise Failure("multiple inputs select the same output pathname", 2)
        aliases.add(resolved)
        for path in protected:
            if resolved == path.resolve() or (destination.exists() and path.exists()
                                             and destination.samefile(path)):
                raise Failure(f"output aliases an input: {destination}", 2)
        if not destination.parent.is_dir() or destination.is_dir():
            raise Failure(f"output directory is missing or output is a directory: {destination}")
    with tempfile.TemporaryDirectory(prefix="seed-gcc-") as directory:
        work = Path(directory)
        toolchain = Toolchain(work)
        if options["query"] == "--print-source-hash":
            print(toolchain.identity)
            return
        includes = options["includes"] + ([] if options["nostdinc"] else [toolchain.runtime / "include"])
        objects = []
        results = []
        for index, (path, kind, data) in enumerate(inputs):
            if kind == "math":
                objects.append(toolchain.math_archive())
                continue
            output = work / f"input-{index}.{'a' if kind == 'a' else 'o'}"
            if kind in ("o", "a"):
                output.write_bytes(data)
            else:
                toolchain.compile(data, b"" if kind == "stdin" else path, output, includes, options["macros"],
                                  options["mode"] == "preprocess")
            objects.append(output)
            results.append(output)
        if options["mode"] == "link":
            if not options["nostdlib"]:
                runtime = toolchain.runtime_objects()
                objects = ([path for path in runtime if path.name == "start.o"]
                           + objects + [toolchain.runtime_archive(runtime)])
            output = work / "program"
            toolchain.link(objects, output)
            results = [output]
        if options["mode"] == "preprocess" and not destinations:
            for output in results:
                sys.stdout.buffer.write(output.read_bytes())
        else:
            for source, destination in zip(results, destinations):
                publish(source, destination, 0o777 if options["mode"] == "link" else 0o666)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except Failure as error:
        print(f"seed-forth-cc: {error}", file=sys.stderr)
        sys.exit(error.status)
    except (OSError, ValueError) as error:
        print(f"seed-forth-cc: {error}", file=sys.stderr)
        sys.exit(1)
