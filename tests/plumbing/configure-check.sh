#!/usr/bin/env bash
# Opt-in check (not part of check-all.sh): run the pristine configure scripts
# of musl 1.1.24 and binutils 2.30 (top level and every host subdirectory)
# twice, once with the host shell and host tools and once with only the
# plumbing tools on PATH (our bash 2.05b, make 3.82, sed, grep, gawk,
# coreutils...), and require the same configuration from both.
#
# Prerequisites: build-out/plumbing/bin from plumbing stages 1 and 2, the
# lexers stage and bash.kaem; build-out/seed-cc/{seed-cc,seed-ar}; the pinned
# musl and binutils tarballs in build-out/gcc64-cache (gcc64/SOURCES); host
# bash, make and strace.  CONFIGURE_LOG_DIR keeps the work trees (default: a
# temporary directory).  Both runs use seed-cc as CC (MUSL_CC overrides it for
# musl, e.g. stage C's GCC 4.0.4, whose programs EXTRA_EXEC, an extended
# regular expression, then admits to the execve audit), so only the shell and
# the tools differ.  Both runs see the same program names on PATH: a directory
# of symlinks, to the host's programs or to ours, for each plumbing program
# the host also has (otherwise results differ only because the host has ld,
# nm, getconf, m4, perl... and the plumbing has flex).
# Both export _POSIX2_VERSION=199209, as gcc-direct/chain-lib.sh does, so that
# coreutils 5.0 accepts the obsolete `tail -3` forms configure scripts use.
#
# "Same configuration" means: every generated file (config.h, config.mak,
# Makefiles, libtool, config.status...) byte-identical after the two build
# directories and the two shell and make paths are replaced by fixed
# names, and every config.cache holding the same values when read back by a
# shell (bash 2.05b's `set` does not quote values the way bash 5 does).
# config.log (dates, host name, PATH) is not compared.  Two differences are
# expected and reported as KNOWN, not failures:
#   - bash 2.05b has no `+=`, so libtool's configure sets lt_shell_append=no
#     and libtool appends with the portable `eval "$1=\$$1\$2"`;
#   - when the host's mkdir is not GNU's (uutils coreutils, say),
#     AC_PROG_MKDIR_P rejects it and the host run uses `install-sh -c -d`,
#     while ours finds coreutils 5.0's `mkdir -p`.
# The run with our tools is traced: every execve must be a plumbing program,
# seed-cc/seed-ar and the seed they run, a configure test program, or the
# uname and arch that config.log's header runs by absolute path.  Programs
# that configure scripts and tools run by absolute path are reported as WARN:
# libtool's `/usr/bin/file` (LT_ENABLE_LOCK) and the `/bin/sh` that gawk's
# system() runs.  Inside tools/plumbing-root.sh's root, /bin/sh is our bash
# and /usr/bin/file does not exist.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
BIN=$ROOT/build-out/plumbing/bin
CC=$ROOT/build-out/seed-cc/seed-cc
AR=$ROOT/build-out/seed-cc/seed-ar
MUSL_CC=${MUSL_CC:-$CC}
CACHE=${GCC64_CACHE:-$ROOT/build-out/gcc64-cache}
LOG=${CONFIGURE_LOG_DIR:-$(mktemp -d)}
mkdir -p "$LOG"
fail() { echo "FAIL: $*" >&2; echo "logs: $LOG" >&2; exit 1; }

command -v strace >/dev/null || fail "strace is required for the execve audit"
for tool in bash make sed grep gawk cat tr expr; do
  test -x "$BIN/$tool" || fail "$BIN/$tool missing; run the plumbing stages"
done
test -x "$CC" && test -x "$AR" || fail "seed-cc/seed-ar missing"
HOSTBASH=$(command -v bash)
HOSTMAKE=$(command -v make)

pin() { grep "^$1 " gcc64/SOURCES | awk '{print $2}'; }
for f in musl-1.1.24.tar.gz binutils-2.30.tar.xz; do
  test -f "$CACHE/$f" || fail "$CACHE/$f missing (gcc64/SOURCES)"
  [ "$(sha256sum < "$CACHE/$f" | cut -d' ' -f1)" = "$(pin $f)" ] || fail "$f differs from gcc64/SOURCES"
done
mkdir -p "$LOG/src" "$LOG/path-host" "$LOG/path-ours"
for tool in "$BIN"/*; do
  name=${tool##*/}
  host=$(PATH=/usr/bin:/bin command -v "$name") || continue
  case $host in /*) ;; *) continue ;; esac
  ln -sf "$host" "$LOG/path-host/$name"
  ln -sf "$tool" "$LOG/path-ours/$name"
done
tar -C "$LOG/src" -xzf "$CACHE/musl-1.1.24.tar.gz"
tar -C "$LOG/src" -xJf "$CACHE/binutils-2.30.tar.xz"

# configure NAME SHELL PATH MAKE PACKAGE ENV: one configure (and for binutils
# the subdirectory configures, through `make configure-host`) in the existing
# directory $LOG/NAME-PACKAGE, started by the env program ENV.
configure() {
  local dir=$LOG/$1-$5
  local env=("$6" -i PATH="$3" LC_ALL=C _POSIX2_VERSION=199209
             CONFIG_SITE=/dev/null CONFIG_SHELL="$2"
             SHELL="$2" CC="$CC" CFLAGS= CPPFLAGS= LDFLAGS= LIBS= AR="$AR")
  if [ "$5" = musl ]; then
    (cd "$dir" && "${env[@]}" CC="$MUSL_CC" "$2" "$LOG/src/musl-1.1.24/configure" \
       --target=x86_64 --host=x86_64 --prefix=/usr --disable-shared) \
      > "$dir.log" 2>&1
  else
    (cd "$dir" && "${env[@]}" CC_FOR_BUILD="$CC" CXX=no RANLIB=true \
       "$2" "$LOG/src/binutils-2.30/configure" \
       --build=x86_64-pc-linux-gnu --host=x86_64-pc-linux-gnu \
       --target=x86_64-pc-linux-gnu --prefix=/usr --disable-shared \
       --disable-nls --disable-multilib --disable-gold --disable-gprof \
       --disable-plugins --disable-werror \
       && "${env[@]}" "$4" -k configure-host CONFIG_SHELL="$2" SHELL="$2") \
      > "$dir.log" 2>&1
  fi
}

normalize() {
  sed -e "s#$LOG/path-host/#TOOL/#g; s#$LOG/path-ours/#TOOL/#g" \
      -e "s#$LOG/host-#WORK-#g; s#$LOG/ours-#WORK-#g" \
      -e "s#$BIN/bash#SHELL#g; s#$HOSTBASH#SHELL#g" \
      -e "s#$BIN/make#MAKE#g; s#$HOSTMAKE#MAKE#g" "$1"
}

cache_values() {
  env -i "$HOSTBASH" -c ". '$1'; set" | grep -E '^[a-z]+_cv_' \
    | sed -e "s#$LOG/path-host/#TOOL/#g; s#$LOG/path-ours/#TOOL/#g" \
          -e "s#$LOG/host-#WORK-#g; s#$LOG/ours-#WORK-#g"
}

# known: drop the lines that carry the two expected differences.
known() {
  grep -Ev 'lt_shell_append=|eval "\$1\+=|eval "\$1=\\\$\$1|^ *(MKDIR_P|mkdir_p) *=|^S\["(MKDIR_P|mkdir_p)"\]=|ac_cv_path_mkdir=|^MKDIR_P=' || true
}

status=0
for package in musl binutils; do
  mkdir "$LOG/host-$package" "$LOG/ours-$package"
  configure host "$HOSTBASH" "$LOG/path-host" "$HOSTMAKE" $package "$(command -v env)" \
    || fail "$package configure with the host shell (see host-$package.log)"
  strace -f -qq --seccomp-bpf -e trace=execve -o "$LOG/execve-$package.txt" \
    bash -c "$(declare -f configure); LOG='$LOG' CC='$CC' AR='$AR' MUSL_CC='$MUSL_CC'; configure ours '$BIN/bash' '$LOG/path-ours' '$BIN/make' $package '$BIN/env'" \
    || fail "$package configure with our tools (see ours-$package.log)"

  # The strace wrapper itself runs host bash once; everything else must be ours.
  grep 'execve(' "$LOG/execve-$package.txt" | grep ' = 0$' \
    | sed -E 's/^[0-9]+ +execve\("([^"]*)".*/\1/' | tail -n +2 > "$LOG/execve-$package-paths.txt"
  allowed="^($BIN/[a-z0-9_.+-]+|$LOG/path-ours/[a-z0-9_.+-]+|$CC|$AR|/.*/seed-(gcc|ar)-[^/]+/seed-forth|(\./)?(conftest|a\.out)|/(usr/)?bin/(uname|arch)|$LOG/ours-$package/.*conftest${EXTRA_EXEC:+|$EXTRA_EXEC})$"
  grep -Ev "$allowed" "$LOG/execve-$package-paths.txt" | sort | uniq -c > "$LOG/execve-$package-unexpected.txt" || true
  if grep -Ev ' (/bin/sh|/usr/bin/file)$' "$LOG/execve-$package-unexpected.txt" > "$LOG/execve-$package-bad.txt"; then
    echo "FAIL $package: unexpected execve: $(head -5 "$LOG/execve-$package-bad.txt" | tr -s ' \n' ' ')"
    status=1
  fi
  if grep -E ' (/bin/sh|/usr/bin/file)$' "$LOG/execve-$package-unexpected.txt" > /dev/null; then
    echo "WARN $package: absolute-path host programs: $(grep -E ' (/bin/sh|/usr/bin/file)$' "$LOG/execve-$package-unexpected.txt" | tr -s ' \n' ' ')"
  fi
  echo "$package execve audit: $(wc -l < "$LOG/execve-$package-paths.txt") calls"

  (cd "$LOG/host-$package" && find . -type f | sort) > "$LOG/$package-host.files"
  (cd "$LOG/ours-$package" && find . -type f | sort) > "$LOG/$package-ours.files"
  # Without LINENO, autoconf writes configure.lineno; both shells here have it.
  if ! diff "$LOG/$package-host.files" "$LOG/$package-ours.files" > "$LOG/$package-files.diff"; then
    echo "FAIL $package: different file sets (see $package-files.diff)"; status=1
  fi
  same=0; differ=0; expected=0
  while read -r f; do
    h=$LOG/host-$package/$f o=$LOG/ours-$package/$f
    [ -f "$o" ] || continue
    if cmp -s "$h" "$o"; then same=$((same + 1)); continue; fi
    case $f in
      */config.log|./config.log) continue ;;
      */config.cache|./config.cache)
        a=$(cache_values "$h"); b=$(cache_values "$o") ;;
      *)
        a=$(normalize "$h"); b=$(normalize "$o") ;;
    esac
    if [ "$a" = "$b" ]; then same=$((same + 1)); continue; fi
    if [ "$(known <<< "$a")" = "$(known <<< "$b")" ]; then
      expected=$((expected + 1)); echo "KNOWN $package $f"; continue
    fi
    differ=$((differ + 1)); echo "DIFF $package $f"; status=1
  done < "$LOG/$package-host.files"
  echo "$package: $same files equivalent, $expected with only the known differences, $differ differ"
done
[ $status = 0 ] || fail "configure results differ"
echo "PASS: musl and binutils configure identically under our bash and tools"
