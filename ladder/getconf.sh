#!/bin/sh
# getconf VAR: the few values the ladder's builds ask for (musl ships no getconf).
case $1 in
_NPROCESSORS_ONLN|_NPROCESSORS_CONF) nproc ;;
ARG_MAX) echo 2097152 ;;
PAGESIZE|PAGE_SIZE) echo 4096 ;;
LONG_BIT) echo 64 ;;
*) echo "getconf: $1 unsupported" >&2; exit 1 ;;
esac
