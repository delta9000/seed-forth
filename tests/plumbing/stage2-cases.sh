# Fixed cases for tests/plumbing/stage2-check.sh, sourced with PATH holding
# only build-out/plumbing/bin and the working directory a fresh scratch
# directory.  Each case is: check NAME EXPECTED-OUTPUT COMMAND (run by bash,
# so pipes and redirections are the harness's; every program is ours).
# The expected outputs are those of the same upstream versions built by host
# GCC (the discovery oracles) and, where versions agree, of host GNU tools.

printf 'hello world\nfoo bar baz\n\nThe Quick brown FOX\nabc123def\n' > t
printf 'one\ntwo\nthree\n' > a
printf 'one\n2\nthree\nfour\n' > b
printf 's/o/0/g\n/^$/d\n' > script.sed
mkdir -p d/sub && printf 'x\n' > d/f && printf 'y\n' > d/sub/g

check sed-subst 'ehll0 w0rld' "printf 'hello world\n' | sed 's/o/0/g;s/\(h\)\(e\)/\2\1/'"
check sed-ere 'world hello' "printf 'hello world\n' | sed -r 's/([a-z]+) ([a-z]+)/\2 \1/'"
check sed-join '1,2,3,4,5' "seq 1 5 | sed ':a;N;\$!ba;s/\n/,/g'"
check sed-count '100' "seq 1 100 | sed -n '\$='"
check sed-hold '2 1 4 3' "seq 1 4 | sed -n 'h;n;G;p' | tr '\n' ' ' | sed 's/ \$//'"
gap sed-file 'hell0 w0rld|f00 bar baz|The Quick br0wn FOX|abc123def' "sed -f script.sed t | tr '\n' '|' | sed 's/|\$//'"
check grep-count '3' "grep -c o t"
check grep-bre 'abc123def' "grep '[[:digit:]]\{3\}' t"
check egrep-alt 'hello world|foo bar baz' "egrep 'wor|baz' t | tr '\n' '|' | sed 's/|\$//'"
check fgrep-n '4:The Quick brown FOX' "fgrep -n -i fox t"
check grep-vc '4' "grep -v -c '^\$' t"
check awk-math '1.414 0.333333 1e+100 3' "awk 'BEGIN{printf \"%.3f %g %g %d\n\", sqrt(2), 1/3, 1e100, 3.9}'"
check awk-fields '6 4' "printf '1 2\n3\n' | awk '{s+=\$1; n+=NF} END{print s+2, n+1}'"
check awk-strings 'HELLO 3 lo' "awk 'BEGIN{s=\"hello\"; print toupper(s), index(s,\"l\"), substr(s,4)}'"
check awk-printf '[    3.1416][3.142e+04 ][ 3.14159e-05]' "awk 'BEGIN{printf \"[%10.4f][%-10.3e][%12g]\n\", 3.14159265, 31415.9265, 0.0000314159}'"
check seq-float '1 1.5 2 2.5 3' "seq 1 0.5 3 | tr '\n' ' ' | sed 's/ \$//'"
check printf-float '  3.14 1.000000e+10 0.1' "printf '%6.2f %e %g\n' 3.14159 1e10 0.1"
check sort-n '-5 1 2 3 10 20' "printf '3\n1\n20\n10\n2\n-5\n' | sort -n | tr '\n' ' ' | sed 's/ \$//'"
check uniq-c $'2\ta,1\tb' "printf 'a\na\nb\n' | uniq -c | sed 's/^ *//' | tr '\n' ',' | sed 's/,\$//'"
check cut-f 'a:b:c' "printf 'a:b:c\n' | cut -d: -f2,1,3"
check wc-lwc '5 10 55' "wc t | sed 's/^ *//;s/  */ /g;s/ t\$//'"
check md5sum '900150983cd24fb0d6963f7d28e17f72' "printf abc | md5sum | cut -c1-32"
check sha1sum 'a9993e364706816aba3e25717850c26c9cd0d89d' "printf abc | sha1sum | cut -c1-40"
check expr '42' "expr 6 '*' 7"
check factor '360: 2 2 2 3 3 5' "factor 360"
check od-c '0000000   a   b  \n' "printf 'ab\n' | od -c | head -n 1"
check date-utc '1970-01-02 03:04:05' "TZ=UTC0 date -d '1970-01-02 03:04:05 UTC' '+%Y-%m-%d %H:%M:%S'"
check readlink-f-rel 'OK' "test \"\$(readlink -f d/sub/../f)\" = \"\$(pwd)/d/f\" && echo OK"
check ls-r 'd:|f|sub||d/sub:|g' "ls -R d | tr '\n' '|' | sed 's/|\$//'"
check basename-dirname 'c /a/b' "echo \$(basename /a/b/c) \$(dirname /a/b/c)"
check head-tail '3 8' "echo \$(seq 1 10 | head -n 3 | tail -n 1) \$(seq 1 10 | tail -n 3 | head -n 1)"
check join 'k1 v1 w1' "printf 'k1 v1\nk2 v2\n' > j1; printf 'k1 w1\nk3 w3\n' > j2; join j1 j2"
check tac-nl '     1	3|     2	2|     3	1' "seq 1 3 | tac | nl | tr '\n' '|' | sed 's/|\$//'"
check cp-mv-rm 'moved' "cp a c && mv c e && cmp a e && rm e && test ! -e e && echo moved"
check install-mode '755' "install -m 755 a inst && ls -l inst | cut -c2-10 | sed 's/rwxr-xr-x/755/'"
check test-bracket 'yes' "[ -d d ] && test -f d/f && echo yes"
check diff-u '--- a|+++ b|@@ -1,3 +1,4 @@| one|-two|+2| three|+four' "diff -u a b | sed 's/\t.*//' | tr '\n' '|' | sed 's/|\$//'"
check diff-patch 'patched' "diff -u a b > p.diff; cp a pa; patch -s pa p.diff && cmp pa b && echo patched"
check diff-patch-R 'reversed' "patch -s -R pa p.diff && cmp pa a && echo reversed"
check cmp-diff 'a b differ: char 5, line 2' "cmp a b"
check gzip-roundtrip 'roundtrip' "gzip -9 -c t > t.gz && gunzip -c t.gz | cmp - t && zcat t.gz | cmp - t && echo roundtrip"
check gzip-bytes 'f834f115556115c8241f23f8a8fa7b74' "seq 1 2000 | gzip -9 -n | md5sum | cut -c1-32"
check tar-roundtrip 'tar ok' "tar -cf x.tar d && mkdir x && (cd x && tar -xf ../x.tar) && diff -r d x/d && echo tar ok"
check tar-list 'd/|d/f|d/sub/|d/sub/g' "tar -tf x.tar | sort | tr '\n' '|' | sed 's/|\$//'"
check tar-z 'tgz ok' "tar -czf x.tgz d && gzip -dc x.tgz | cmp - x.tar && echo tgz ok"
# diff3 and sdiff are not run here: they execute DIFF_PROGRAM, /usr/bin/diff
# (see plumbing/diffutils-2.7/config.h), which is not ours on this host.
