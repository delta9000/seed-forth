/* Narrow, seed-Forth-built Linux/amd64 recipe runner. No shell, PATH search,
 * substitution commands, globs, or host utilities. Recipe and source tree are
 * trusted inputs; directories are private, with no concurrent writers.
 * Every external executable is named explicitly in the committed recipe.
 * int is 64-bit in SF; use long for the same layout in host-only tests. */
long syscall3(long number, long a, long b, long c);
long open(char *p, long flags, long mode);
long read(long fd, char *p, long n);
long write(long fd, char *p, long n);
long close(long fd);
void *malloc(long n);
void exit(long n);
long strlen(char *p);

#define CAP 16384
char root[4096];
char work[4096];
char iobuf[65536];
char hbuf[64];
char hashout[65];
char token_buffer[CAP];
char expansion_buffer[CAP];
long sh[8];
long sw[64];
long sk[64];
long audit_fd;
long repin;
char *context;
char *variables[32];
char *values[32];
long variable_count;
char *args[128];
long argc;
long read_size;

void say(long fd, char *s) {
    long n;
    long k;
    n = strlen(s);
    while (n > 0) {
        k = write(fd, s, n);
        if (k <= 0)
            exit(1);
        s = s + k;
        n = n - k;
    }
}
void fail(char *s) {
    say(2, "amd64-runner: FAIL: ");
    say(2, s);
    say(2, " [");
    if (context)
        say(2, context);
    say(2, "]\n");
    exit(1);
}
/* SF's allocation is a checked bump allocator; the recipe has bounded input
 * sizes, token counts and nesting. Keep transient token buffers reusable. */
void *alloc(long n) {
    void *p;
    p = malloc(n);
    if (!p)
        fail("allocation");
    return p;
}
long eq(char *a, char *b) {
    long i;
    i = 0;
    while (a[i] && a[i] == b[i])
        i = i + 1;
    return a[i] == b[i];
}
long prefix(char *a, char *b) {
    long i;
    i = 0;
    while (b[i]) {
        if (a[i] != b[i])
            return 0;
        i = i + 1;
    }
    return 1;
}
char *dup(char *s) {
    char *r;
    long i;
    r = alloc(strlen(s) + 1);
    if (!r)
        fail("allocation");
    i = 0;
    do {
        r[i] = s[i];
        i = i + 1;
    } while (s[i - 1]);
    return r;
}
char *join(char *a, char *b) {
    char *r;
    long i;
    long j;
    r = alloc(strlen(a) + strlen(b) + 2);
    if (!r)
        fail("allocation");
    i = 0;
    while (a[i]) {
        r[i] = a[i];
        i = i + 1;
    }
    if (i == 0 || r[i - 1] != '/') {
        r[i] = '/';
        i = i + 1;
    }
    j = 0;
    while (b[j]) {
        r[i] = b[j];
        i = i + 1;
        j = j + 1;
    }
    r[i] = 0;
    return r;
}
void checked_close(long fd) {
    if (close(fd) != 0)
        fail("close");
}
void putall(long fd, char *p, long n) {
    long k;
    while (n > 0) {
        k = write(fd, p, n);
        if (k <= 0 || k > n)
            fail("write");
        p = p + k;
        n = n - k;
    }
}
char *slurp(char *p, long cap) {
    long fd;
    long n;
    long k;
    char *b;
    char extra;
    fd = open(p, 0, 0);
    if (fd < 0)
        fail(p);
    b = alloc(cap + 1);
    if (!b)
        fail("allocation");
    n = 0;
    while (n < cap) {
        k = read(fd, b + n, cap - n);
        if (k < 0)
            fail("read");
        if (k == 0)
            break;
        n = n + k;
    }
    if (n == cap && read(fd, &extra, 1) != 0)
        fail("input too large");
    checked_close(fd);
    b[n] = 0;
    read_size = n;
    return b;
}
void copy_to(long out, char *src) {
    long fd;
    long n;
    fd = open(src, 0, 0);
    if (fd < 0)
        fail(src);
    while (1) {
        n = read(fd, iobuf, 65536);
        if (n < 0)
            fail("copy read");
        if (!n)
            break;
        putall(out, iobuf, n);
    }
    checked_close(fd);
}
void copy(char *src, char *dst) {
    long fd;
    fd = open(dst, 577, 420);
    if (fd < 0)
        fail(dst);
    copy_to(fd, src);
    checked_close(fd);
}
void textfile(char *dst, char *s) {
    long fd;
    fd = open(dst, 577, 420);
    if (fd < 0)
        fail(dst);
    putall(fd, s, strlen(s));
    checked_close(fd);
}
void makedir(char *p) {
    long r;
    r = syscall3(83, (long)p, 493, 0);
    if (r != 0 && r != -17)
        fail(p);
}
/* d_type is checked before descent: reject symlinks/special files on copy.
 * Delete never follows them. Ignore .git when copying a pinned source checkout. */
void tree(char *src, char *dst, long deleting, long depth) {
    long fd;
    long n;
    long at;
    long reclen;
    long type;
    char *b;
    char *name;
    char *s;
    char *d;
    if (depth > 64)
        fail("directory nesting limit");
    fd = open(src, 196608, 0);
    if (fd < 0)
        fail(src);
    b = alloc(8192);
    if (!b)
        fail("allocation");
    if (!deleting)
        makedir(dst);
    while (1) {
        n = syscall3(217, fd, (long)b, 8192);
        if (n < 0)
            fail("getdents64");
        if (!n)
            break;
        at = 0;
        while (at < n) {
            if (at + 19 >= n)
                fail("directory record");
            reclen = (b[at + 16] & 255) + ((b[at + 17] & 255) << 8);
            if (reclen < 20 || at + reclen > n)
                fail("directory record length");
            type = b[at + 18] & 255;
            name = b + at + 19;
            if (!eq(name, ".") && !eq(name, "..") && (deleting || !eq(name, ".git"))) {
                s = join(src, name);
                d = 0;
                if (!deleting)
                    d = join(dst, name);
                if (type == 4)
                    tree(s, d, deleting, depth + 1);
                else if (deleting) {
                    if (syscall3(87, (long)s, 0, 0) != 0)
                        fail("unlink");
                } else if (type == 8)
                    copy(s, d);
                else
                    fail("source contains non-regular file");
            }
            at = at + reclen;
        }
    }
    checked_close(fd);
    if (deleting && syscall3(84, (long)src, 0, 0) != 0)
        fail("rmdir");
}
void same(char *a, char *b) {
    long x;
    long y;
    long n;
    long m;
    long i;
    char *u;
    char *v;
    x = open(a, 0, 0);
    y = open(b, 0, 0);
    if (x < 0 || y < 0)
        fail("comparison open");
    u = alloc(65536);
    v = alloc(65536);
    while (1) {
        n = read(x, u, 65536);
        if (n < 0)
            fail("comparison read");
        m = 0;
        while (m < n) {
            i = read(y, v + m, n - m);
            if (i <= 0)
                fail("files differ");
            m = m + i;
        }
        i = 0;
        while (i < n) {
            if (u[i] != v[i])
                fail("files differ");
            i = i + 1;
        }
        if (!n) {
            if (read(y, v, 1) != 0)
                fail("files differ");
            break;
        }
    }
    checked_close(x);
    checked_close(y);
}
long rotr(long x, long n) {
    return (x >> n) | ((x << (32 - n)) & 0xffffffff);
}
void sha_block(void) {
    long a;
    long b;
    long c;
    long d;
    long e;
    long f;
    long g;
    long h;
    long i;
    long t;
    long u;
    i = 0;
    while (i < 16) {
        sw[i] = ((hbuf[i * 4] & 255) << 24) | ((hbuf[i * 4 + 1] & 255) << 16) |
                ((hbuf[i * 4 + 2] & 255) << 8) | (hbuf[i * 4 + 3] & 255);
        i = i + 1;
    }
    while (i < 64) {
        t = sw[i - 15];
        u = sw[i - 2];
        sw[i] = (sw[i - 16] + (rotr(t, 7) ^ rotr(t, 18) ^ (t >> 3)) + sw[i - 7] +
                 (rotr(u, 17) ^ rotr(u, 19) ^ (u >> 10))) &
                0xffffffff;
        i = i + 1;
    }
    a = sh[0];
    b = sh[1];
    c = sh[2];
    d = sh[3];
    e = sh[4];
    f = sh[5];
    g = sh[6];
    h = sh[7];
    i = 0;
    while (i < 64) {
        t = (h + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ ((~e) & g)) +
             sk[i] + sw[i]) &
            0xffffffff;
        u = ((rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) &
            0xffffffff;
        h = g;
        g = f;
        f = e;
        e = (d + t) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (t + u) & 0xffffffff;
        i = i + 1;
    }
    sh[0] = (sh[0] + a) & 0xffffffff;
    sh[1] = (sh[1] + b) & 0xffffffff;
    sh[2] = (sh[2] + c) & 0xffffffff;
    sh[3] = (sh[3] + d) & 0xffffffff;
    sh[4] = (sh[4] + e) & 0xffffffff;
    sh[5] = (sh[5] + f) & 0xffffffff;
    sh[6] = (sh[6] + g) & 0xffffffff;
    sh[7] = (sh[7] + h) & 0xffffffff;
}
void sha(char *path) {
    long fd;
    long n;
    long k;
    long total;
    long i;
    long j;
    char *hex;
    sh[0] = 0x6a09e667;
    sh[1] = 0xbb67ae85;
    sh[2] = 0x3c6ef372;
    sh[3] = 0xa54ff53a;
    sh[4] = 0x510e527f;
    sh[5] = 0x9b05688c;
    sh[6] = 0x1f83d9ab;
    sh[7] = 0x5be0cd19;
    fd = open(path, 0, 0);
    if (fd < 0)
        fail(path);
    total = 0;
    n = 0;
    while (1) {
        k = read(fd, hbuf + n, 64 - n);
        if (k < 0)
            fail("hash read");
        if (!k)
            break;
        n = n + k;
        total = total + k;
        if (n == 64) {
            sha_block();
            n = 0;
        }
    }
    checked_close(fd);
    hbuf[n] = 128;
    n = n + 1;
    if (n > 56) {
        while (n < 64) {
            hbuf[n] = 0;
            n = n + 1;
        }
        sha_block();
        n = 0;
    }
    while (n < 56) {
        hbuf[n] = 0;
        n = n + 1;
    }
    total = total * 8;
    i = 63;
    while (i >= 56) {
        hbuf[i] = total;
        total = total >> 8;
        i = i - 1;
    }
    sha_block();
    hex = "0123456789abcdef";
    i = 0;
    while (i < 8) {
        j = 0;
        while (j < 8) {
            hashout[i * 8 + j] = hex[(sh[i] >> ((7 - j) * 4)) & 15];
            j = j + 1;
        }
        i = i + 1;
    }
    hashout[64] = 0;
}
void pin(char *p, char *want) {
    sha(p);
    if (!eq(hashout, want)) {
        say(2, p);
        say(2, ": ");
        say(2, hashout);
        say(2, "\n");
        fail("SHA256 mismatch");
    }
}
void sha_init(void) {
    sk[0] = 0x428a2f98;
    sk[1] = 0x71374491;
    sk[2] = 0xb5c0fbcf;
    sk[3] = 0xe9b5dba5;
    sk[4] = 0x3956c25b;
    sk[5] = 0x59f111f1;
    sk[6] = 0x923f82a4;
    sk[7] = 0xab1c5ed5;
    sk[8] = 0xd807aa98;
    sk[9] = 0x12835b01;
    sk[10] = 0x243185be;
    sk[11] = 0x550c7dc3;
    sk[12] = 0x72be5d74;
    sk[13] = 0x80deb1fe;
    sk[14] = 0x9bdc06a7;
    sk[15] = 0xc19bf174;
    sk[16] = 0xe49b69c1;
    sk[17] = 0xefbe4786;
    sk[18] = 0x0fc19dc6;
    sk[19] = 0x240ca1cc;
    sk[20] = 0x2de92c6f;
    sk[21] = 0x4a7484aa;
    sk[22] = 0x5cb0a9dc;
    sk[23] = 0x76f988da;
    sk[24] = 0x983e5152;
    sk[25] = 0xa831c66d;
    sk[26] = 0xb00327c8;
    sk[27] = 0xbf597fc7;
    sk[28] = 0xc6e00bf3;
    sk[29] = 0xd5a79147;
    sk[30] = 0x06ca6351;
    sk[31] = 0x14292967;
    sk[32] = 0x27b70a85;
    sk[33] = 0x2e1b2138;
    sk[34] = 0x4d2c6dfc;
    sk[35] = 0x53380d13;
    sk[36] = 0x650a7354;
    sk[37] = 0x766a0abb;
    sk[38] = 0x81c2c92e;
    sk[39] = 0x92722c85;
    sk[40] = 0xa2bfe8a1;
    sk[41] = 0xa81a664b;
    sk[42] = 0xc24b8b70;
    sk[43] = 0xc76c51a3;
    sk[44] = 0xd192e819;
    sk[45] = 0xd6990624;
    sk[46] = 0xf40e3585;
    sk[47] = 0x106aa070;
    sk[48] = 0x19a4c116;
    sk[49] = 0x1e376c08;
    sk[50] = 0x2748774c;
    sk[51] = 0x34b0bcb5;
    sk[52] = 0x391c0cb3;
    sk[53] = 0x4ed8aa4a;
    sk[54] = 0x5b9cca4f;
    sk[55] = 0x682e6ff3;
    sk[56] = 0x748f82ee;
    sk[57] = 0x78a5636f;
    sk[58] = 0x84c87814;
    sk[59] = 0x8cc70208;
    sk[60] = 0x90befffa;
    sk[61] = 0xa4506ceb;
    sk[62] = 0xbef9a3f7;
    sk[63] = 0xc67178f2;
}
long run(char **av, char *in, char *out, char *err, long want) {
    long pid;
    long status;
    long got;
    long fd;
    long r;
    if (!av[0] ||
        (!prefix(av[0], "/") && !prefix(av[0], "./") && !prefix(av[0], "build/")))
        fail("executable must use an explicit path");
    if (audit_fd >= 0) {
        say(audit_fd, av[0]);
        say(audit_fd, "\n");
    }
    pid = syscall3(57, 0, 0, 0);
    if (pid < 0)
        fail("fork");
    if (pid == 0) {
        if (!eq(in, "-")) {
            fd = open(in, 0, 0);
            if (fd < 0)
                exit(121);
            if (syscall3(33, fd, 0, 0) != 0)
                exit(121);
            if (fd != 0)
                close(fd);
        }
        if (!eq(out, "-")) {
            fd = open(out, 577, 420);
            if (fd < 0)
                exit(122);
            if (syscall3(33, fd, 1, 0) != 1)
                exit(122);
            if (fd != 1)
                close(fd);
        }
        if (!eq(err, "-")) {
            fd = open(err, 577, 420);
            if (fd < 0)
                exit(123);
            if (syscall3(33, fd, 2, 0) != 2)
                exit(123);
            if (fd != 2)
                close(fd);
        }
        syscall3(59, (long)av[0], (long)av, 0);
        exit(124);
    }
    status = 0;
    do {
        r = syscall3(61, pid, (long)&status, 0);
    } while (r == -4);
    if (r != pid)
        fail("wait4");
    if (status & 127)
        fail("child terminated by signal");
    got = (status >> 8) & 255;
    if (want >= 0 && got != want) {
        say(2, av[0]);
        say(2, "\n");
        fail("unexpected child exit; inspect recipe log");
    }
    return got;
}
char *expand(char *s) {
    char *r;
    char *v;
    long i;
    long j;
    long k;
    long q;
    long start;
    char *name;
    name = alloc(128);
    r = expansion_buffer;
    if (!r)
        fail("allocation");
    i = 0;
    j = 0;
    while (s[i]) {
        if (s[i] == '$' && s[i + 1] == '{') {
            i = i + 2;
            start = i;
            while (s[i] && s[i] != '}')
                i = i + 1;
            if (!s[i] || i - start >= 128)
                fail("variable syntax");
            k = 0;
            while (start < i) {
                name[k] = s[start];
                start = start + 1;
                k = k + 1;
            }
            name[k] = 0;
            i = i + 1;
            v = 0;
            q = 0;
            while (q < variable_count) {
                if (eq(name, variables[q]))
                    v = values[q];
                q = q + 1;
            }
            if (!v)
                fail("undefined variable");
            k = 0;
            while (v[k]) {
                if (j >= CAP - 1)
                    fail("expanded token too long");
                r[j] = v[k];
                j = j + 1;
                k = k + 1;
            }
        } else {
            if (j >= CAP - 1)
                fail("token too long");
            r[j] = s[i];
            j = j + 1;
            i = i + 1;
        }
    }
    r[j] = 0;
    return dup(r);
}
void setvar(char *name, char *value) {
    long i;
    i = 0;
    while (i < variable_count) {
        if (eq(name, variables[i])) {
            values[i] = dup(value);
            return;
        }
        i = i + 1;
    }
    if (i == 32)
        fail("too many variables");
    variables[i] = dup(name);
    values[i] = dup(value);
    variable_count = i + 1;
}
long number(char *s) {
    long n;
    long i;
    n = 0;
    i = 0;
    if (!s[0])
        fail("empty number");
    while (s[i]) {
        if (s[i] < '0' || s[i] > '9')
            fail("invalid number");
        n = n * 10 + s[i] - '0';
        if (n > 255)
            fail("exit status too large");
        i = i + 1;
    }
    return n;
}
/* One command per line, whitespace-separated tokens; single/double quotes,
 * backslash n/t/quote/backslash. No command substitution, comments only at
 * a token boundary. Variables ${NAME} expand after tokenization. */
char *parse(char *p) {
    char *token;
    long n;
    long quote;
    long c;
    token = token_buffer;
    argc = 0;
    while (*p && *p != '\n') {
        while (*p == ' ' || *p == '\t' || *p == '\r')
            p = p + 1;
        if (*p == '#') {
            while (*p && *p != '\n')
                p = p + 1;
            break;
        }
        if (!*p || *p == '\n')
            break;
        n = 0;
        quote = 0;
        while (*p) {
            c = *p;
            if (!quote && (c == ' ' || c == '\t' || c == '\r' || c == '\n'))
                break;
            p = p + 1;
            if (c == '\'' || c == '"') {
                if (!quote) {
                    quote = c;
                    continue;
                }
                if (quote == c) {
                    quote = 0;
                    continue;
                }
            }
            if (c == '\\') {
                if (!*p)
                    fail("trailing escape");
                c = *p;
                p = p + 1;
                if (c == 'n')
                    c = '\n';
                else if (c == 't')
                    c = '\t';
                else if (c != '\\' && c != '\'' && c != '"')
                    fail("unsupported escape");
            }
            if (n >= CAP - 1)
                fail("token too long");
            token[n] = c;
            n = n + 1;
        }
        if (quote)
            fail("unterminated quote");
        token[n] = 0;
        if (argc >= 127)
            fail("too many arguments");
        args[argc] = expand(token);
        argc = argc + 1;
    }
    if (*p == '\n')
        p = p + 1;
    args[argc] = 0;
    return p;
}
void arity(long n) {
    if (argc != n)
        fail("wrong argument count");
}
void patches(char *manifest, char *data) {
    char *p;
    char *source;
    char *target;
    char *candidate;
    char *before;
    char *after;
    char *pre;
    char *post;
    char *av[8];
    long fd;
    p = slurp(manifest, 65536);
    while (*p) {
        p = parse(p);
        if (!argc)
            continue;
        arity(7);
        source = dup(args[1]);
        target = dup(args[2]);
        candidate = alloc(strlen(target) + 14);
        if (!candidate)
            fail("allocation");
        /* join without slash */
        {
            long i;
            long j;
            char *suffix;
            i = 0;
            while (target[i]) {
                candidate[i] = target[i];
                i = i + 1;
            }
            suffix = ".sf-patch-new";
            j = 0;
            do {
                candidate[i] = suffix[j];
                i = i + 1;
                j = j + 1;
            } while (suffix[j - 1]);
        }
        before = join(data, args[3]);
        after = join(data, args[4]);
        pre = dup(args[5]);
        post = dup(args[6]);
        av[0] = "./simple-patch";
        if (eq(args[0], "replace")) {
            pin(source, pre);
            av[1] = "replace";
            av[2] = source;
            av[3] = before;
            av[4] = after;
            av[5] = candidate;
            av[6] = 0;
        } else if (eq(args[0], "copy")) {
            fd = syscall3(6, (long)target, (long)iobuf, 0);
            if (fd == 0)
                fail("patch add target exists");
            if (fd != -2)
                fail("patch add target lstat");
            source = join(data, source);
            pin(source, pre);
            av[1] = "copy";
            av[2] = source;
            av[3] = candidate;
            av[4] = 0;
        } else
            fail("unknown patch operation");
        run(av, "-", "-", "-", 0);
        pin(candidate, post);
        if (syscall3(82, (long)candidate, (long)target, 0) != 0)
            fail("patch rename");
    }
}
/* Stage exactly the manifest's tracked files: untracked checkout files and
 * .git metadata never enter compiler inputs. Names are trusted committed data. */
void stage_inputs(char *manifest, char *src, char *dst) {
    char *p;
    char *name;
    char *out;
    long i;
    long n;
    char saved;
    p = slurp(manifest, 1048576);
    n = strlen(src);
    makedir(dst);
    while (*p) {
        p = parse(p);
        if (!argc)
            continue;
        arity(2);
        name = dup(args[1]);
        if (!prefix(name, src) || name[n] != '/')
            fail("manifest source prefix");
        pin(name, args[0]);
        out = join(dst, name + n + 1);
        i = strlen(dst) + 1;
        while (out[i]) {
            if (out[i] == '/') {
                saved = out[i];
                out[i] = 0;
                makedir(out);
                out[i] = saved;
            }
            i = i + 1;
        }
        copy(name, out);
    }
}
void command(void) {
    long i;
    long fd;
    long n;
    char *a;
    char *b;
    char **v;
    v = alloc(1024);
    if (!argc)
        return;
    context = args[0];
    if (eq(args[0], "set")) {
        arity(3);
        setvar(args[1], args[2]);
    } else if (eq(args[0], "cd")) {
        arity(2);
        if (syscall3(80, (long)args[1], 0, 0) != 0)
            fail(args[1]);
    } else if (eq(args[0], "mkdir")) {
        arity(2);
        makedir(args[1]);
    } else if (eq(args[0], "copy")) {
        arity(3);
        copy(args[1], args[2]);
    } else if (eq(args[0], "stage")) {
        arity(4);
        a = dup(args[1]);
        b = dup(args[2]);
        stage_inputs(a, b, dup(args[3]));
    } else if (eq(args[0], "tree")) {
        arity(3);
        tree(args[1], args[2], 0, 0);
    } else if (eq(args[0], "text")) {
        arity(3);
        textfile(args[1], args[2]);
    } else if (eq(args[0], "cat")) {
        if (argc < 3)
            fail("cat arguments");
        fd = open(args[1], 577, 420);
        if (fd < 0)
            fail(args[1]);
        i = 2;
        while (i < argc) {
            copy_to(fd, args[i]);
            i = i + 1;
        }
        checked_close(fd);
    } else if (eq(args[0], "chmod")) {
        arity(2);
        if (syscall3(90, (long)args[1], 493, 0) != 0)
            fail("chmod");
    } else if (eq(args[0], "rename")) {
        arity(3);
        if (syscall3(82, (long)args[1], (long)args[2], 0) != 0)
            fail("rename");
    } else if (eq(args[0], "unlink")) {
        arity(2);
        n = syscall3(87, (long)args[1], 0, 0);
        if (n != 0 && n != -2)
            fail("unlink");
    } else if (eq(args[0], "same")) {
        arity(3);
        same(args[1], args[2]);
    } else if (eq(args[0], "pin")) {
        arity(3);
        pin(args[1], args[2]);
    } else if (eq(args[0], "artifact")) {
        arity(3);
        if (repin) {
            sha(args[1]);
            say(1, "REPIN ");
            say(1, args[1]);
            say(1, " ");
            say(1, hashout);
            say(1, "\n");
        } else
            pin(args[1], args[2]);
    } else if (eq(args[0], "hash")) {
        arity(2);
        sha(args[1]);
        say(1, hashout);
        say(1, "\n");
    } else if (eq(args[0], "pins")) {
        arity(2);
        a = slurp(args[1], 1048576);
        while (*a) {
            a = parse(a);
            if (argc) {
                arity(2);
                pin(args[1], args[0]);
            }
        }
    } else if (eq(args[0], "patches")) {
        arity(3);
        a = dup(args[1]);
        b = dup(args[2]);
        patches(a, b);
    } else if (eq(args[0], "run")) {
        if (argc < 6)
            fail("run arguments");
        i = 5;
        while (i < argc) {
            v[i - 5] = args[i];
            i = i + 1;
        }
        v[i - 5] = 0;
        run(v, args[2], args[3], args[4], number(args[1]));
    } else if (eq(args[0], "contains")) {
        arity(3);
        a = slurp(args[1], 1048576);
        i = 0;
        n = 0;
        while (a[i]) {
            if (prefix(a + i, args[2]))
                n = n + 1;
            i = i + 1;
        }
        if (n != 1)
            fail("expected unique output text");
    } else if (eq(args[0], "say")) {
        arity(2);
        say(1, args[1]);
        say(1, "\n");
    } else
        fail("unknown recipe command");
}
/* Cleanup paths must be normalized and have no symlink component. This is
 * not a concurrent-writer sandbox; it protects ordinary mistaken BUILDROOTs. */
void check_work_path(char *path) {
    char *p;
    char *st;
    long i;
    long result;
    long mode;
    p = dup(path);
    st = alloc(144);
    i = 1;
    if (path[0] != '/' || !path[1])
        fail("absolute build root required");
    while (1) {
        if (p[i] == '/' || !p[i]) {
            if (p[i - 1] == '/')
                fail("repeated/trailing slash in build root");
            if (i > 1 && p[i - 1] == '.' && p[i - 2] == '/')
                fail("dot component in build root");
            if (p[i] == '/') {
                p[i] = 0;
                result = syscall3(6, (long)p, (long)st, 0);
                p[i] = '/';
            } else
                result = syscall3(6, (long)p, (long)st, 0);
            if (result == 0) {
                mode = (st[24] & 255) | ((st[25] & 255) << 8);
                if ((mode & 61440) != 16384)
                    fail("build root component is not a real directory");
            } else if (result != -2)
                fail("build root lstat");
            if (!p[i])
                break;
        }
        i = i + 1;
    }
}
int main(int ac, char **av) {
    char *p;
    char *r;
    long n;
    long fd;
    long i;
    audit_fd = -1;
    sha_init();
    context = "startup";
    if (syscall3(79, (long)root, 4096, 0) <= 0)
        fail("getcwd");
    setvar("ROOT", root);
    if (ac == 3 && eq(av[1], "--recipe")) {
        p = slurp(av[2], 1048576);
        while (*p) {
            p = parse(p);
            command();
        }
        return 0;
    }
    if (ac != 1)
        fail("usage: amd64-runner [--recipe FILE]");
    n = syscall3(0, 8, (long)work, 2);
    if (n > 0 && work[0] == '1')
        repin = 1;
    n = syscall3(0, 9, (long)work, 4095);
    if (n == -9) {
        r = join(root, "build-out/pnut-amd64");
    } else {
        if (n <= 0 || n >= 4095)
            fail("launch build directory");
        work[n] = 0;
        if (work[n - 1] == '\n')
            work[n - 1] = 0;
        i = 0;
        while (work[i]) {
            if (work[i] == '\n' || work[i] == '\r')
                fail("launch path newline");
            i = i + 1;
        }
        if (work[0] == '/')
            r = dup(work);
        else
            r = join(root, work);
    }
    /* Destructive cleanup is bounded to this checkout's build-out child dirs.
     * An external BUILDROOT must be a new directory. Never follow symlinks. */
    p = join(root, "build-out/");
    if (eq(r, root) || eq(r, p) || eq(r, "/"))
        fail("unsafe build root");
    i = 0;
    while (r[i]) {
        if (r[i] == '.' && r[i + 1] == '.')
            fail("dot-dot build root");
        i = i + 1;
    }
    check_work_path(r);
    fd = open(r, 196608, 0);
    if (fd >= 0) {
        checked_close(fd);
        if (!prefix(r, p))
            fail("external build root must be absent");
        tree(r, 0, 1, 0);
    }
    makedir(r);
    setvar("W", r);
    audit_fd = open(join(r, "executables.log"), 524865, 420);
    if (audit_fd < 0)
        fail("execution log");
    p = slurp("tools/amd64.recipe", 1048576);
    while (*p) {
        p = parse(p);
        command();
    }
    checked_close(audit_fd);
    if (repin) {
        say(1, "amd64-runner: REPIN requires independent comparison before updating recipe hashes\n");
        return 1;
    }
    say(1, "amd64-runner: PASS (seed-built tools only)\n");
    return 0;
}
