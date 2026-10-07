#!/bin/sh
# Host-side smoke checks; not part of the configure-free build recipes.
set -eu
MODE=${1:-all}
case $MODE in all|make|bash|coreutils) ;; *) exit 2;; esac
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
W=$ROOT/build-out/modern-work
T=$W/checks
mkdir -p "$T"
if [ "$MODE" = all ] || [ "$MODE" = make ]; then
"$W/make-4.4.1/make" --version
cat > "$T/Makefile" <<'EOF'
.PHONY: all left right
WORD = ok
all: left right
	printf 'make-$(WORD)\n'
left:
	printf 'left\n'
right:
	printf 'right\n'
EOF
"$W/make-4.4.1/make" -s -j2 -f "$T/Makefile" > "$T/make.out"
grep -qx make-ok "$T/make.out"
grep -qx left "$T/make.out"
grep -qx right "$T/make.out"
fi
if [ "$MODE" = all ] || [ "$MODE" = bash ]; then
"$W/bash-5.2.37/bash" --version
"$W/bash-5.2.37/bash" --noprofile --norc -c '
set -eu
MODE=${1:-all}
case $MODE in all|make|bash|coreutils) ;; *) exit 2;; esac
x=world; test "hello $x" = "hello world"
a=(one two); test "${a[1]}" = two
test "$((6 * 7))" -eq 42
f() { printf "%s\n" "$1"; }; test "$(f ok)" = ok
case abc in a*) :;; *) exit 1;; esac
printf "bash-ok\n"
'
fi
if [ "$MODE" = all ] || [ "$MODE" = coreutils ]; then
C=$W/coreutils-9.5/src
"$C/printf" 'z\na\na\n' > "$T/input"
"$C/mkdir" -p "$T/core"
"$C/cp" "$T/input" "$T/core/copy"
"$C/cat" "$T/core/copy" > "$T/cat.out"
cmp "$T/input" "$T/cat.out"
"$C/sort" "$T/input" > "$T/sort.out"
printf 'a\na\nz\n' > "$T/expected"
cmp "$T/expected" "$T/sort.out"
"$C/wc" -l < "$T/input" > "$T/wc.out"
"$C/tr" -d ' ' < "$T/wc.out" > "$T/count.out"
test "$("$C/cat" "$T/count.out")" = 3
"$C/ls" "$T/core" > "$T/ls.out"
grep -qx copy "$T/ls.out"
test "$(TZ=UTC0 "$C/date" -d @0 +%Y-%m-%d)" = 1970-01-01
# Each pipeline stages output in a file so set -e sees every program's status.
test "$("$C/head" -n 1 "$T/input")" = z
test "$("$C/tail" -n 1 "$T/input")" = a
"$C/uniq" "$T/sort.out" > "$T/uniq.out"
test "$("$C/cat" "$T/uniq.out")" = "$(printf 'a\nz')"
"$C/tr" az AZ < "$T/uniq.out" > "$T/tr.out"
test "$("$C/cat" "$T/tr.out")" = "$(printf 'A\nZ')"
"$C/printf" 'a:1\nb:2\n' > "$T/fields"
"$C/cut" -d : -f 2 "$T/fields" > "$T/cut.out"
test "$("$C/cat" "$T/cut.out")" = "$(printf '1\n2')"
"$C/printf" 'a 1\nb 2\n' > "$T/left"
"$C/printf" 'a x\nb y\n' > "$T/right"
"$C/join" "$T/left" "$T/right" > "$T/join.out"
test "$("$C/cat" "$T/join.out")" = "$(printf 'a 1 x\nb 2 y')"
"$C/paste" -d : "$T/uniq.out" "$T/cut.out" > "$T/paste.out"
test "$("$C/cat" "$T/paste.out")" = "$(printf 'a:1\nz:2')"
"$C/comm" -12 "$T/uniq.out" "$T/uniq.out" > "$T/comm.out"
cmp "$T/uniq.out" "$T/comm.out"
"$C/printf" abc > "$T/abc"
test "$("$C/od" -An -tx1 "$T/abc")" = ' 61 62 63'
"$C/md5sum" "$T/abc" > "$T/md5.out"
"$C/cut" -d ' ' -f 1 "$T/md5.out" > "$T/hash.out"
test "$("$C/cat" "$T/hash.out")" = 900150983cd24fb0d6963f7d28e17f72
"$C/sha256sum" "$T/abc" > "$T/sha256.out"
"$C/cut" -d ' ' -f 1 "$T/sha256.out" > "$T/hash.out"
test "$("$C/cat" "$T/hash.out")" = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
test "$("$C/basename" /a/b.txt .txt)" = b
test "$("$C/dirname" /a/b.txt)" = /a
"$C/test" 7 -gt 3
"$C/[" abc = abc ']'
if "$C/test" 7 -lt 3; then exit 1; fi
test "$("$C/expr" 6 '*' 7)" = 42
test "$("$C/expr" abc : 'a\(.*\)')" = bc
test "$("$C/factor" 42)" = '42: 2 3 7'
test "$("$C/seq" -s , 1 3)" = 1,2,3
"$C/env" -i RECIPE_CHECK=ok "$C/printenv" RECIPE_CHECK > "$T/env.out"
test "$("$C/cat" "$T/env.out")" = ok
# Recreate a dedicated area to make the checks repeatable.
"$C/rm" -r -f "$T/core-files"
"$C/mkdir" "$T/core-files"
"$C/install" -m 640 "$T/abc" "$T/core-files/installed"
test "$("$C/stat" -c %a "$T/core-files/installed")" = 640
"$C/ln" "$T/core-files/installed" "$T/core-files/hard"
test "$("$C/stat" -c %h "$T/core-files/hard")" = 2
"$C/mv" "$T/core-files/hard" "$T/core-files/moved"
"$C/test" ! -e "$T/core-files/hard"
"$C/touch" -d @0 "$T/core-files/moved"
test "$("$C/stat" -c %Y "$T/core-files/moved")" = 0
"$C/du" -sb "$T/core-files/installed" > "$T/du.out"
"$C/cut" -f 1 "$T/du.out" > "$T/size.out"
test "$("$C/cat" "$T/size.out")" = 3
"$C/df" -P "$T/core-files" > "$T/df.out"
test "$("$C/wc" -l < "$T/df.out")" -eq 2
"$C/stat" -f -c %S "$T/core-files" > "$T/stat-fs.out"
test "$("$C/cat" "$T/stat-fs.out")" -gt 0
"$C/rm" "$T/core-files/moved" "$T/core-files/installed"
"$C/test" ! -e "$T/core-files/moved"
fi
printf '%s smoke checks passed\n' "$MODE"
