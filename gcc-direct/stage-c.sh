#!/bin/bash
# stage-c.sh -- stage C: the seed-built GCC 4.0.4 builds libgcc and musl 1.1.24.
#
# Usage:
#   gcc-direct/stage-c.sh WORK --binutils BINUTILS_WORK --oyacc OYACC \
#       --flex FLEX [-j JOBS] [--resume]
#
# The bash port of stage-c.py, run by the chain's own bash and make.
# BINUTILS_WORK is a finished binutils.sh run; its as-new, ld-new, ar, nm-new,
# objdump and readelf are checked against its stage-B report and copied into
# WORK/toolchain (ranlib there is a two-line `ar s` script).  Steps:
#
# 1. inputs     binutils copied; the pinned GCC tar and musl tarball
#               (plumbing/chain.SOURCES) unpacked into WORK/src.  The one
#               source adjustment is configure.py's --alloca-frame adapter:
#               gcc-direct/patches/alloca-frame.patch applied to
#               libiberty/alloca.c with no fuzz, both hashes checked before
#               and after (gcc-direct/patches/alloca-frame.json).  The
#               collect2 patch in patches/gcc64/gcc-4.0.4/ is applied too (as
#               stage D does): unpatched, a failed link probe with -o /dev/null
#               makes collect2 unlink /dev/null, which as root destroys it.
# 2. headers    musl's Makefile installs its headers into
#               WORK/sysroot/usr/include (`install-headers`, no compiler).
# 3. configure  configure.sh runs the original libiberty, libcpp and gcc
#               configure scripts with seed-cc.  GCC also gets
#               --with-binutils WORK/toolchain and --with-sysroot
#               WORK/sysroot: a native compiler whose target headers and
#               libraries are WORK/sysroot/usr/{include,lib} (4.0.4 then sets
#               SYSTEM_HEADER_DIR there, so limits.h is generated against
#               musl's) and whose as and ld are ours.
# 4. cc1        census.sh --link builds libiberty, every cc1 object, libcpp
#               and cc1.
# 5. driver     GCC's Makefile builds xgcc, cpp, collect2 and specs.
# 6. libgcc     GCC's Makefile builds the target libraries with ./xgcc and
#               ./cc1: `stmp-multilib` = libgcc.a, libgcov.a and the crt
#               objects.  STMP_FIXINC is emptied (no fixincludes;
#               gsyslimits.h is installed as include/syslimits.h, as
#               gcc64/build-gcc4.sh does).
# 7. install    `make install` into WORK/gcc/install.
# 8. musl       musl's own configure and Makefile, out of tree in
#               WORK/musl-build, with CC=WORK/gcc/install/bin/gcc and our ar;
#               installed with DESTDIR=WORK/sysroot (prefix /usr).
# 9. hello      tests/gcc/stage-c-hello.c is compiled and statically linked
#               by that gcc alone (`gcc -static -O2`), run, and its output
#               compared with tests/gcc/stage-c-hello.expected; nm must show
#               libgcc's __divti3.
#
# Every make after step 3 runs with WORK/gcc/configure-env.sh, whose PATH
# starts with the guards, so a host compiler, assembler or linker use is
# blocked and logged in WORK/gcc/host-tool-attempts.log.  No GCC or musl
# source is patched beyond the alloca adapter and the collect2 patch (see
# stage-c.py for why linux-unwind.h's `struct ucontext` builds against musl).
# Build-tree adjustments: the combined-tree links ../libiberty, ../libcpp,
# ../build-TRIPLE/libiberty and ../binutils/{ar,ranlib}; STMP_FIXINC emptied
# in the configured Makefile; gsyslimits.h as include/syslimits.h;
# install-tools/include created before `make install`.
#
# WORK/stage-c/report.txt records each step's commands, seconds and output
# hashes; each step's commands and output are in WORK/stage-c/STEP.log.  With
# --resume, steps recorded as done in WORK/stage-c/done are skipped.
set -e
PROG=stage-c
ROOT=$(cd "${0%/*}/.." && pwd)
. "$ROOT/gcc-direct/chain-lib.sh"

STEPS="inputs headers configure cc1 driver libgcc install musl hello"
work= binutils= oyacc= flex= jobs=6 resume=
while [ $# -gt 0 ]; do
  case $1 in
    --binutils) binutils=$2; shift 2 ;;
    --oyacc) oyacc=$2; shift 2 ;;
    --flex) flex=$2; shift 2 ;;
    -j|--jobs) jobs=$2; shift 2 ;;
    --resume) resume=1; shift ;;
    -*) die "unknown option $1" ;;
    *) work=$1; shift ;;
  esac
done
[ -n "$work" ] && [ -n "$binutils" ] && [ -n "$oyacc" ] && [ -n "$flex" ] \
  || die "usage: stage-c.sh WORK --binutils BINUTILS_WORK --oyacc OYACC --flex FLEX [-j JOBS] [--resume]"
[ "$jobs" -ge 1 ] && [ "$jobs" -le 8 ] || die "jobs must be 1-8"
binutils=$(absdir "$binutils") oyacc=$(absfile "$oyacc") flex=$(absfile "$flex")
require_tool oyacc "$oyacc"
require_tool flex "$flex"
if [ -e "$work" ] && [ -z "$resume" ]; then die "WORK exists (use --resume): $work"; fi
mkdir -p "$work/stage-c"
work=$(absdir "$work")
out=$work/stage-c
toolchain=$work/toolchain
sysroot=$work/sysroot
gcc_source=$work/src/gcc-4.0.4
musl_source=$work/src/musl-1.1.24
gcc_build=$work/gcc/build/gcc
install=$work/gcc/install
gcc=$install/bin/gcc
libiberty=$work/libiberty/build/libiberty/libiberty.a
OVERRIDES="CFLAGS= LDFLAGS= BISON=$oyacc FLEX=$flex LIBIBERTY=$libiberty BUILD_LIBIBERTY=$libiberty CPPLIB=$work/libcpp/build/libcpp/libcpp.a"
touch "$out/done"

# result KEY VALUE: one line of the current step's result.
result() { echo "  $1: $2" >> "$out/$step.result"; }

# A subshell with GCC's recorded configure environment (guards first in PATH).
target_env() { . "$work/gcc/configure-env.sh"; }

step_inputs() {
  local path name tool
  mkdir -p "$toolchain" "$work/src"
  for path in gas/as-new ld/ld-new binutils/ar binutils/nm-new binutils/objdump binutils/readelf; do
    case $path in
      gas/as-new) name=as ;; ld/ld-new) name=ld ;; binutils/nm-new) name=nm ;; *) name=${path##*/} ;;
    esac
    tool=$binutils/build/top/$path
    grep -qx "tool: $path $(sha "$tool")" "$binutils/stage-b/report.txt" \
      || die "$tool differs from its stage-B report"
    cp -p "$tool" "$toolchain/$name"
    result "$name" "$(sha "$toolchain/$name")"
  done
  printf '#!%s\nexec %s s "$@"\n' "$BASH" "$toolchain/ar" > "$toolchain/ranlib"
  chmod 755 "$toolchain/ranlib"
  rm -rf "$gcc_source" "$gcc_source.unpack" "$musl_source" "$musl_source.unpack"
  untar "$GCC_TAR" "$gcc_source" gcc-4.0.4
  untar "$MUSL_TGZ" "$musl_source" musl-1.1.24
  result gcc_archive "$(pinned "${GCC_TAR##*/}")"
  result musl_archive "$(pinned "${MUSL_TGZ##*/}")"
  alloca_frame "$gcc_source"
  collect2_patch "$gcc_source"
}

# collect2_patch SOURCE: the collect2 patch stage D and gcc64 apply.  An
# unpatched 4.0.4 collect2 unlinks its -o output whenever a link fails; musl's
# configure probes linker flags with -o /dev/null, so as root a failed probe
# would replace the /dev/null device with a regular file.
collect2_patch() {
  local patch
  for patch in "$ROOT"/patches/gcc64/gcc-4.0.4/*.diff; do
    (cd "$1" && run "$out/inputs.log" patch -t -N -F0 -p1 -i "$patch")
    result patch "${patch##*/} $(sha "$patch")"
  done
}

# alloca_frame SOURCE: configure.py's --alloca-frame adapter, applied exactly.
alloca_frame() {
  local manifest=$ROOT/gcc-direct/patches/alloca-frame.json patch=$ROOT/gcc-direct/patches/alloca-frame.patch
  local file before after want_patch
  file=$(sed -n 's/.*"source": *"\([^"]*\)".*/\1/p' "$manifest")
  before=$(sed -n 's/.*"before_sha256": *"\([0-9a-f]*\)".*/\1/p' "$manifest")
  after=$(sed -n 's/.*"after_sha256": *"\([0-9a-f]*\)".*/\1/p' "$manifest")
  want_patch=$(sed -n 's/.*"patch_sha256": *"\([0-9a-f]*\)".*/\1/p' "$manifest")
  [ -n "$file" ] && [ "$(sha "$1/$file")" = "$before" ] && [ "$(sha "$patch")" = "$want_patch" ] \
    || die "alloca target adapter source or patch hash differs"
  (cd "$1" && run "$out/inputs.log" patch -t -N -F0 -p1 -i "$patch")
  [ "$(sha "$1/$file")" = "$after" ] || die "exact alloca target adapter application failed"
  result alloca_adapter "$file $after"
}

step_headers() {
  mkdir -p "$work/musl-headers"
  (cd "$work/musl-headers" && run "$out/headers.log" make -f "$musl_source/Makefile" "srcdir=$musl_source" \
     ARCH=x86_64 prefix=/usr "DESTDIR=$sysroot" install-headers)
  result headers "$(files "$sysroot/usr/include" | wc -l | tr -d ' ')"
}

step_configure() {
  local component
  for component in libiberty libcpp gcc; do
    if [ $component = gcc ]; then
      run "$out/configure.log" "$BASH" "$ROOT/gcc-direct/configure.sh" --component gcc --forth-ar \
        --source "$gcc_source" --work "$work/gcc" --with-binutils "$toolchain" --with-sysroot "$sysroot"
    else
      run "$out/configure.log" "$BASH" "$ROOT/gcc-direct/configure.sh" --component $component --forth-ar \
        --source "$gcc_source" --work "$work/$component"
    fi
  done
  result components "libiberty libcpp gcc"
}

step_cc1() {
  run "$out/cc1.log" "$BASH" "$ROOT/gcc-direct/census.sh" "$work" --oyacc "$oyacc" --flex "$flex" --link -j "$jobs"
  result cc1 "$(sha "$gcc_build/cc1")"
}

step_driver() {
  local name
  (target_env; cd "$gcc_build" && run "$out/driver.log" make -j "$jobs" $OVERRIDES xgcc cpp collect2 specs)
  for name in xgcc cpp collect2 specs; do result $name "$(sha "$gcc_build/$name")"; done
}

step_libgcc() {
  local top=$work/gcc/build name
  mkdir -p "$gcc_build/include"
  if [ ! -e "$gcc_build/include/syslimits.h" ]; then
    cp "$gcc_source/gcc/gsyslimits.h" "$gcc_build/include/syslimits.h"
  fi
  # libgcc.mk re-enters this Makefile with MAKEOVERRIDES= (for the crt
  # objects), so the LIBIBERTY, BUILD_LIBIBERTY and CPPLIB overrides are lost
  # and the defaults must resolve: ../libiberty, ../libcpp and
  # ../build-TRIPLE/libiberty, the combined-tree layout.  The Makefile takes
  # AR/RANLIB_FOR_TARGET from ../binutils/ar and ../binutils/ranlib, else
  # (native) the host-side $(AR), here seed-ar, which cannot index GNU as
  # objects.
  mkdir -p "$top/build-$TRIPLE" "$top/binutils"
  [ -L "$top/libiberty" ] || ln -s "$work/libiberty/build/libiberty" "$top/libiberty"
  [ -L "$top/libcpp" ] || ln -s "$work/libcpp/build/libcpp" "$top/libcpp"
  [ -L "$top/build-$TRIPLE/libiberty" ] || ln -s "$work/libiberty/build/libiberty" "$top/build-$TRIPLE/libiberty"
  [ -L "$top/binutils/ar" ] || ln -s "$toolchain/ar" "$top/binutils/ar"
  [ -L "$top/binutils/ranlib" ] || ln -s "$toolchain/ranlib" "$top/binutils/ranlib"
  # No fixincludes (musl's headers need no fixing).  A command-line
  # STMP_FIXINC= does not survive libgcc.mk's MAKEOVERRIDES=, so the
  # configured Makefile's one line is changed, as gcc64/build-gcc4.sh does.
  if grep -qx 'STMP_FIXINC = stmp-fixinc' "$gcc_build/Makefile"; then
    sed 's/^STMP_FIXINC = stmp-fixinc$/STMP_FIXINC =/' "$gcc_build/Makefile" > "$gcc_build/Makefile.new"
    mv "$gcc_build/Makefile.new" "$gcc_build/Makefile"
  elif ! grep -qx 'STMP_FIXINC =' "$gcc_build/Makefile"; then
    die "configured Makefile has no STMP_FIXINC line"
  fi
  (target_env; cd "$gcc_build" && run "$out/libgcc.log" make -j "$jobs" $OVERRIDES stmp-multilib)
  for name in libgcc.a libgcov.a crtbegin.o crtend.o crtbeginS.o crtendS.o crtbeginT.o; do
    result $name "$(sha "$gcc_build/$name")"
  done
}

step_install() {
  # 4.0.4's install-mkheaders installs into install-tools/include without
  # creating it (gcc64/build-gcc4.sh makes it first, too).
  mkdir -p "$install/lib/gcc/$TRIPLE/4.0.4/install-tools/include"
  (target_env; cd "$gcc_build" && run "$out/install.log" make $OVERRIDES MAKEINFO=true install)
  result gcc "$(sha "$gcc")"
}

step_musl() {
  local name
  mkdir -p "$work/musl-build"
  (target_env
   unset CPP CXX CXXCPP CC_FOR_BUILD AS LD NM
   CC=$gcc CFLAGS= CPPFLAGS= LDFLAGS= AR=$toolchain/ar RANLIB=$toolchain/ranlib
   export CC CFLAGS CPPFLAGS LDFLAGS AR RANLIB
   cd "$work/musl-build"
   run "$out/musl.log" "$BASH" "$musl_source/configure" --target=x86_64 --host=x86_64 \
     --disable-shared --prefix=/usr --syslibdir=/lib
   run "$out/musl.log" make -j "$jobs" CROSS_COMPILE= "AR=$AR" "RANLIB=$RANLIB"
   run "$out/musl.log" make CROSS_COMPILE= "AR=$AR" "RANLIB=$RANLIB" "DESTDIR=$sysroot" install)
  for name in libc.a crt1.o crti.o crtn.o; do result $name "$(sha "$sysroot/usr/lib/$name")"; done
}

step_hello() {
  local dir=$work/hello
  mkdir -p "$dir"
  cp "$ROOT/tests/gcc/stage-c-hello.c" "$dir/hello.c"
  (PATH=$work/gcc/guard:$PATH
   cd "$dir"
   run "$out/hello.log" "$gcc" -v -static -O2 -o hello hello.c
   ./hello > stdout 2> stderr) || die "hello failed; see $dir"
  cmp -s "$dir/stdout" "$ROOT/tests/gcc/stage-c-hello.expected" \
    || die "hello output differs from tests/gcc/stage-c-hello.expected; see $dir/stdout"
  "$toolchain/nm" "$dir/hello" | grep -q ' __divti3$' || die "hello did not link libgcc's __divti3"
  result hello "$(sha "$dir/hello")"
  result output_matches yes
  result libgcc_divti3_linked yes
}

report() {
  local name
  {
    if [ -z "$1" ]; then echo "# Stage C: complete"; else echo "# Stage C: stopped: $1"; fi
    echo
    echo "The seed-built GCC 4.0.4 (xgcc, cc1) with seed-built binutils builds libgcc"
    echo "and musl 1.1.24, then links and runs a static hosted program."
    echo
    for name in $STEPS; do
      if grep -qx "$name" "$out/done"; then echo "- $name: ok"
      elif [ -f "$out/$name.result" ]; then echo "- $name: FAILED"
      else echo "- $name: not reached"; fi
      if [ -f "$out/$name.result" ]; then cat "$out/$name.result"; fi
    done
    echo
    if [ -f "$work/gcc/host-tool-attempts.log" ]; then
      echo "Blocked host tool attempts (including configure probes): $(wc -l < "$work/gcc/host-tool-attempts.log" | tr -d ' ')"
    else
      echo "Blocked host tool attempts (including configure probes): 0"
    fi
  } > "$out/report.txt"
  cat "$out/report.txt"
}

failure=
for step in $STEPS; do
  if grep -qx "$step" "$out/done"; then continue; fi
  note "$step"
  started=$(date +%s)
  : > "$out/$step.result"
  # set -e does not reach a subshell run as an if or || condition.
  set +e
  ( set -e; "step_$step" )
  status=$?
  set -e
  if [ $status -eq 0 ]; then
    result seconds $(( $(date +%s) - started ))
    echo "$step" >> "$out/done"
  else
    failure="$step (see $out/$step.log)"
    break
  fi
done
report "$failure"
[ -z "$failure" ]
