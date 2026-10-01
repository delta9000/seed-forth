#!/bin/sh
# Host-side helper for K1 tests: the chain's tcc-musl (a copy in
# build-out/k1/tc) with explicit paths, since the copy's built-in
# paths point at build-out/gcc64.  Not part of the chain.
TC=$(cd "$(dirname "$0")/../build-out/k1/tc" && pwd)
link=1
n=$#
while [ $n -gt 0 ]; do
    a=$1; shift; n=$((n - 1))
    case $a in
        -c|-E|-S) link=0; set -- "$@" "$a" ;;
        -Wp,-MD,*) set -- "$@" -MD -MF "${a#-Wp,-MD,}" ;;
        *) set -- "$@" "$a" ;;
    esac
done
if [ $link = 0 ]; then
    exec "$TC/bin/tcc" -nostdinc -I"$TC/include" "$@"
fi
exec "$TC/bin/tcc" -nostdinc -I"$TC/include" -nostdlib -static \
    "$TC/lib/crt1.o" "$TC/lib/crti.o" "$@" "$TC/lib/libc.a" \
    "$TC/lib/tcc/libtcc1.a" "$TC/lib/libc.a" "$TC/lib/crtn.o"
