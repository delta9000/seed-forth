# chain-lib.sh -- helpers shared by the bash stage scripts (sourced, not run).
#
# Written for the chain's own bash 2.05b (plumbing/bash.kaem), which is built
# without arrays, brace expansion, `set -o pipefail` or `+=`.  The scripts use
# only programs the plumbing stages build: coreutils 5.0, sed, grep, gawk, tar,
# gzip, patch, diffutils, make, stage0's sha256sum and unbz2, oyacc, flex,
# and seed-cc/seed-ar.  Each caller sets PROG and ROOT before sourcing.

TRIPLE=x86_64-pc-linux-gnu
SEED_CC=$ROOT/build-out/seed-cc/seed-cc
SEED_AR=$ROOT/build-out/seed-cc/seed-ar
LC_ALL=C
# coreutils 5.0 follows the runtime's _POSIX2_VERSION (200809) and so
# rejects obsolete forms such as `tail -3`, which gcc/configure's eh_frame
# probe uses; the probe would fail and wrongly define
# USE_AS_TRADITIONAL_FORMAT.  This is the variable coreutils 5.0 documents
# for running older scripts.
_POSIX2_VERSION=199209
export LC_ALL _POSIX2_VERSION

die() { echo "$PROG: $*" >&2; exit 1; }
note() { echo "[$PROG] $*"; }

# sha FILE: FILE's SHA-256 (stage0's sha256sum reads named files only).
sha() { sha256sum "$1" | sed 's/ .*//'; }

# absdir DIR: DIR as an absolute path (DIR must exist).
absdir() { (cd "$1" && pwd) || die "no directory $1"; }

# absfile FILE: FILE as an absolute path (its directory must exist).
absfile() {
  case $1 in
    */*) echo "$(absdir "${1%/*}")/${1##*/}" ;;
    *) echo "$(pwd)/$1" ;;
  esac
}

# run LOG CMD...: append "$ (cd DIR) CMD" and CMD's output to LOG; any
# nonzero exit stops the script.
run() {
  local log=$1
  shift
  printf '\n$ (cd %s) %s\n' "$PWD" "$*" >> "$log"
  "$@" >> "$log" 2>&1 || die "exit $? from $1; see $log"
}

# pinned NAME: the SHA-256 that plumbing/chain.SOURCES
# records for archive NAME.
pinned() {
  local hash
  hash=$(gawk -v n="$1" '$1 == n { print $2; exit }' "$ROOT/plumbing/chain.SOURCES")
  [ -n "$hash" ] || die "no pin for $1 in plumbing/chain.SOURCES"
  echo "$hash"
}

# verify ARCHIVE: ARCHIVE's SHA-256 must equal its pin.
verify() {
  local got want
  want=$(pinned "${1##*/}")
  got=$(sha "$1")
  [ "$got" = "$want" ] || die "$1: sha256 $got, pinned $want"
}

# untar ARCHIVE DEST [TOP]: verify ARCHIVE, then unpack it so that its top
# directory TOP becomes DEST.  DEST must not exist.  tar 1.12 predates the
# ustar prefix field: the 71 members of gcc's libstdc++-v3/testsuite whose
# names exceed 100 bytes land in the staging directory under their last name
# component, as does git's pax_global_header; everything outside TOP is
# discarded, and with it the incomplete libstdc++-v3/testsuite.
untar() {
  local archive=$1 dest=$2 top=$3 staging
  [ -e "$dest" ] && die "$dest exists"
  verify "$archive"
  staging=$dest.unpack
  rm -rf "$staging"
  mkdir -p "$staging"
  case $archive in
    *.tar.gz) (cd "$staging" && gzip -dc "$archive" | tar -xf -) ;;
    *.tar) (cd "$staging" && tar -xf "$archive") ;;
    *) die "unknown archive type: $archive" ;;
  esac 2> "$staging.log" || { cat "$staging.log" >&2; die "unpacking $archive failed"; }
  [ -d "$staging/$top" ] || die "$archive has no $top"
  mv "$staging/$top" "$dest"
  rm -rf "$staging" "$staging.log"
  if [ -d "$dest/libstdc++-v3/testsuite" ]; then rm -rf "$dest/libstdc++-v3/testsuite"; fi
}

# The pinned chain inputs (see plumbing/chain.SOURCES).
GCC_TAR=$ROOT/build-out/direct-gcc-inputs/gcc-4.0.4-git-944765863e.tar
BINUTILS_TAR=$ROOT/build-out/stage-b-inputs/binutils-2.30.tar
MUSL_TGZ=$ROOT/build-out/stage-c-inputs/musl-1.1.24.tar.gz

# files DIR: every regular file below DIR (following symlinks to files, not
# to directories), relative to DIR, one per line, unsorted.
files() {
  (cd "$1" && files_walk .) | sed 's|^\./||'
}
files_walk() {
  local entry
  for entry in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    if [ -d "$entry" ] && [ ! -L "$entry" ]; then
      files_walk "$entry"
    elif [ -f "$entry" ]; then
      echo "$entry"
    fi
  done
}

# require_tool NAME PATH: PATH must be an executable file.
require_tool() {
  [ -f "$2" ] && [ -x "$2" ] || die "--$1 must name an executable file: $2"
}
