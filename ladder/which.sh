#!/bin/sh
# which NAME...: the first executable NAME on PATH.  GNU which-2.21 does not
# build with tcc; gcc64's scripts only need this much of it.
rc=0
for n in "$@"; do
    found=
    case $n in
    */*) [ -x "$n" ] && found=$n ;;
    *)
        IFS=:
        for d in $PATH; do
            d=${d:-.}
            if [ -x "$d/$n" ] && [ ! -d "$d/$n" ]; then found=$d/$n; break; fi
        done
        unset IFS ;;
    esac
    if [ -n "$found" ]; then echo "$found"; else rc=1; fi
done
exit $rc
