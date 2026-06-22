#!/usr/bin/env bash
# tools/tangle.sh — literate-programming tangler for the seed-forth book.
#
# The book in book/*.md interleaves prose with fenced code blocks.  Blocks
# tagged with a "file=" attribute are part of the canonical source for
# that file; this script extracts them and verifies them against the
# checked-in source files.
#
# Block format:
#
#     ```forth file=010-lib.fth
#     : over  >r dup r> swap ;
#     ```
#
# For 000-seed.hex0 (which is hand-assembled with strict byte offsets),
# named chunks let us teach by topic rather than by ELF offset:
#
#     ```hex0 file=000-seed.hex0
#     <<elf-header>>
#     <<entry-point>>
#     <<sysvar-init>>
#     ```
#
#     ```hex0 chunk=elf-header
#     7F 45 4C 46         ; magic
#     ...
#     ```
#
# Commands:
#   extract OUTDIR  Tangle book/*.md into OUTDIR/<target-file>.
#   verify          For each file mentioned in the book, every tangled
#                   line must appear in the source file in non-decreasing
#                   order.  Used while the book is in progress.
#   verify --strict Tangled file must equal source byte-for-byte.  This
#                   is what we'll require once every chapter is written.
#   status          Print coverage: tangled-lines / source-lines per file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOK_DIR="$REPO_ROOT/book"
TANGLE_AWK="$SCRIPT_DIR/tangle.awk"

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
}

cmd_extract() {
    local outdir="${1:-}"
    [ -n "$outdir" ] || { echo "extract: missing OUTDIR" >&2; exit 2; }
    mkdir -p "$outdir"
    awk -f "$TANGLE_AWK" -v OUTDIR="$outdir" \
        "$BOOK_DIR"/[0-9]*.md
}

cmd_verify() {
    local strict=""
    if [ "${1:-}" = "--strict" ]; then strict=1; fi

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    cmd_extract "$tmpdir"

    local fail=0
    local any=0
    for t in "$tmpdir"/*; do
        [ -e "$t" ] || continue
        any=1
        local base src
        base="$(basename "$t")"
        src="$REPO_ROOT/$base"
        if [ ! -f "$src" ]; then
            echo "FAIL  $base  (no source file at repo root)" >&2
            fail=1
            continue
        fi

        if [ -n "$strict" ]; then
            if diff -q "$src" "$t" >/dev/null 2>&1; then
                echo "OK    $base  (strict, byte-identical)"
            else
                echo "FAIL  $base  (book does not tangle to byte-identical source)" >&2
                diff -u "$src" "$t" | sed -n '1,40p' >&2
                fail=1
            fi
        else
            if verify_in_order "$src" "$t"; then
                local nt ns
                nt=$(wc -l <"$t")
                ns=$(wc -l <"$src")
                printf 'OK    %-24s  %4d / %4d lines covered\n' "$base" "$nt" "$ns"
            else
                fail=1
            fi
        fi
    done

    if [ "$any" = 0 ]; then
        echo "tangle verify: no file= blocks found in $BOOK_DIR" >&2
        return 0
    fi
    return $fail
}

verify_in_order() {
    local src="$1" tangled="$2"
    awk -v SRC="$src" -v TANGLED="$tangled" '
        BEGIN {
            n = 0
            while ((getline line < SRC) > 0) {
                n++
                src[n] = line
            }
            close(SRC)
            cur = 1
            tno = 0
            while ((getline tline < TANGLED) > 0) {
                tno++
                found = 0
                for (i = cur; i <= n; i++) {
                    if (src[i] == tline) {
                        cur = i + 1
                        found = 1
                        break
                    }
                }
                if (!found) {
                    printf "FAIL  %s  (tangled line %d not found in source at-or-after src:%d)\n", \
                        TANGLED, tno, cur > "/dev/stderr"
                    printf "         tangled: %s\n", tline > "/dev/stderr"
                    exit 1
                }
            }
            close(TANGLED)
            exit 0
        }
    '
}

cmd_status() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT
    cmd_extract "$tmpdir"

    printf '%-28s %10s %10s %8s\n' "file" "covered" "total" "%"
    printf '%-28s %10s %10s %8s\n' "----" "-------" "-----" "-"
    for src in "$REPO_ROOT"/[0-9]*.fth "$REPO_ROOT"/[0-9]*.hex0; do
        [ -f "$src" ] || continue
        local base nt ns pct
        base="$(basename "$src")"
        ns=$(wc -l <"$src")
        if [ -f "$tmpdir/$base" ]; then
            nt=$(wc -l <"$tmpdir/$base")
        else
            nt=0
        fi
        if [ "$ns" -gt 0 ]; then
            pct=$(( 100 * nt / ns ))
        else
            pct=0
        fi
        printf '%-28s %10d %10d %7d%%\n' "$base" "$nt" "$ns" "$pct"
    done
}

case "${1:-}" in
    extract) shift; cmd_extract "$@" ;;
    verify)  shift; cmd_verify  "$@" ;;
    status)  shift; cmd_status  "$@" ;;
    -h|--help|"") usage ;;
    *) echo "unknown command: $1" >&2; usage ;;
esac
