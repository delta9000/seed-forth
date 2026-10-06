# User and group databases and the login name

`ls -l`, `id`, `chown`, `tar`, `make` (`~user`), `bash` and `whoami` look up
users and groups. The runtime reads the two classic files directly; there is
no NSS, NIS, LDAP or systemd lookup.

## Files and parsing

`pwd.h` declares `struct passwd` (glibc's member order) and `getpwnam`,
`getpwuid`, `getpwent`, `setpwent`, `endpwent`; `grp.h` declares
`struct group` and the `getgr*` equivalents plus `setgroups`
([IDENTITY.md](IDENTITY.md)).

Each lookup reads the whole of `/etc/passwd` or `/etc/group` into memory
(`dbfile.c`) and scans it line by line, following glibc's `files` service:

- leading blanks are skipped; empty lines and lines starting with `#` are
  ignored;
- a passwd entry needs seven colon-separated fields; the seventh (the shell)
  keeps any further colons; a group entry needs three or four (an absent
  member list means no members);
- user and group IDs must be 1 to 10 decimal digits below 2^32, otherwise the
  line is skipped (glibc also rejects `-1`, `abc` and 11-digit values);
- group members are split at commas and empty names are dropped, so
  `a,b,` lists two members;
- the first matching entry wins, so a duplicate name or ID later in the file
  is reachable only through enumeration.

Lines beginning with `+` are NIS compatibility markers; glibc's `files`
service returns a name-only record for them, while this runtime has no NIS
and skips them. Lines beginning with `-` are ordinary entries.

## Results and state

All functions share one static `struct passwd` (and one `struct group`) whose
strings point into the file text that the call read; the next call of any
passwd (or group) function may overwrite them, as POSIX allows. Lookups use
their own copy of the file, so `getpwnam` in the middle of a `getpwent` scan
does not disturb the scan. `setpwent` and `endpwent` discard the scan (the
next `getpwent` rereads the file from the start). A missing entry returns
NULL with errno unchanged; a missing file behaves as an empty one; any other
read failure returns NULL with the kernel's errno.

## getlogin

`getlogin_r(buffer, size)` uses glibc's first method: it reads the session's
audit login UID from `/proc/self/loginuid` and maps it through `getpwuid`.
There is no utmp fallback. A process without a login session (UID
4294967295, as in daemons and many containers) gets `ENXIO`; an unknown
UID gives `ENOENT`, a short buffer `ERANGE`, and an unreadable `/proc` the
`open` error. The error is returned (not stored in errno). `getlogin`
returns a static copy, or NULL with that error in errno.

## Gate

`python3 tests/gcc/posix-users-check.py` runs each build in a private user
and mount namespace (`unshare -rm`) where `tests/gcc/posix-users/passwd`,
`group` and an `nsswitch.conf` limited to `files` are bind-mounted over
`/etc`, so the host glibc oracle (`-O0`, `-O2`) reads exactly the same data.
The files contain comments, blank and indented lines, malformed and
oversized IDs, short lines, a `-` entry, an extra-colon shell, empty fields,
a 32-bit ID above 2^31, a duplicate name and a final line without a
newline; groups include empty, trailing-comma and absent member lists. The
fixture enumerates both databases, restarts scans, interleaves a lookup with
a scan, looks up by name and ID (present, missing, duplicate, malformed) and
calls `getlogin`/`getlogin_r`. Output must be identical. Without
unprivileged namespaces the gate reports SKIP.
