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
test "$("$C/wc" -l < "$T/input" | tr -d ' ')" = 3
"$C/ls" "$T/core" > "$T/ls.out"
grep -qx copy "$T/ls.out"
test "$(TZ=UTC0 "$C/date" -d @0 +%Y-%m-%d)" = 1970-01-01
fi
printf '%s smoke checks passed\n' "$MODE"
