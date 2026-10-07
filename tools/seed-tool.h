/* seed-tool.h -- shared code for the native seed-forth driver programs
   tools/seed-cc.c and tools/seed-ar.c.  Both are compiled by the Forth C
   compiler against runtime/gcc-seed (see tools/SEED-CC.md); no host
   compiler builds them.

   This header holds static definitions, so each program is one translation
   unit.  System calls go straight to Linux through __seed_syscall6 and
   return -errno on failure: error messages can then reproduce the Python
   drivers' "[Errno N] text: 'path'" spelling without depending on the
   bounded runtime's errno or strerror coverage.  The runtime supplies only
   malloc/realloc/free, memcpy/memcmp/strlen and environ. */
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <seed-syscall.h>

#define ST_O_RDONLY 0
#define ST_O_WRONLY 1
#define ST_O_RDWR 2
#define ST_O_CREAT 64
#define ST_O_EXCL 128
#define ST_O_TRUNC 512
#define ST_O_DIRECTORY 65536
#define ST_O_CLOEXEC 524288

#define ST_S_IFMT 0170000
#define ST_S_IFDIR 0040000
#define ST_S_IFREG 0100000
#define ST_S_IFLNK 0120000
#define ST_S_IFCHR 0020000

/* Linux AMD64 struct stat, as returned by the stat family of syscalls. */
struct st_stat {
    unsigned long dev;
    unsigned long ino;
    unsigned long nlink;
    unsigned int mode;
    unsigned int uid;
    unsigned int gid;
    unsigned int pad0;
    unsigned long rdev;
    long size;
    long blksize;
    long blocks;
    long atime;
    long atime_nsec;
    long mtime;
    long mtime_nsec;
    long ctime;
    long ctime_nsec;
    long reserved[3];
};

static long st_sys(long n, long a, long b, long c, long d, long e, long f)
{
    return __seed_syscall6(n, a, b, c, d, e, f);
}
static long st_read(int fd, void *p, unsigned long n) { return st_sys(0, fd, (long)p, (long)n, 0, 0, 0); }
static long st_write(int fd, const void *p, unsigned long n) { return st_sys(1, fd, (long)p, (long)n, 0, 0, 0); }
static long st_open(const char *path, long flags, long mode) { return st_sys(2, (long)path, flags, mode, 0, 0, 0); }
static long st_close(int fd) { return st_sys(3, fd, 0, 0, 0, 0, 0); }
static long st_stat(const char *path, struct st_stat *s) { return st_sys(4, (long)path, (long)s, 0, 0, 0, 0); }
static long st_lstat(const char *path, struct st_stat *s) { return st_sys(6, (long)path, (long)s, 0, 0, 0, 0); }
static long st_dup2(int a, int b) { return st_sys(33, a, b, 0, 0, 0, 0); }
static long st_getpid(void) { return st_sys(39, 0, 0, 0, 0, 0, 0); }
static long st_fork(void) { return st_sys(57, 0, 0, 0, 0, 0, 0); }
static long st_execve(const char *p, char **argv, char **envp) { return st_sys(59, (long)p, (long)argv, (long)envp, 0, 0, 0); }
static void st_exit(int status) { st_sys(231, status, 0, 0, 0, 0, 0); st_sys(60, status, 0, 0, 0, 0, 0); }
static long st_wait4(long pid, int *status) { return st_sys(61, pid, (long)status, 0, 0, 0, 0); }
static long st_fsync(int fd) { return st_sys(74, fd, 0, 0, 0, 0, 0); }
static long st_getcwd(char *p, unsigned long n) { return st_sys(79, (long)p, (long)n, 0, 0, 0, 0); }
static long st_rename(const char *a, const char *b) { return st_sys(82, (long)a, (long)b, 0, 0, 0, 0); }
static long st_mkdir(const char *p, long mode) { return st_sys(83, (long)p, mode, 0, 0, 0, 0); }
static long st_rmdir(const char *p) { return st_sys(84, (long)p, 0, 0, 0, 0, 0); }
static long st_link(const char *a, const char *b) { return st_sys(86, (long)a, (long)b, 0, 0, 0, 0); }
static long st_unlink(const char *p) { return st_sys(87, (long)p, 0, 0, 0, 0, 0); }
static long st_readlink(const char *p, char *b, unsigned long n) { return st_sys(89, (long)p, (long)b, (long)n, 0, 0, 0); }
static long st_chmod(const char *p, long mode) { return st_sys(90, (long)p, mode, 0, 0, 0, 0); }
static long st_fchmod(int fd, long mode) { return st_sys(91, fd, mode, 0, 0, 0, 0); }
static long st_umask(long mask) { return st_sys(95, mask, 0, 0, 0, 0, 0); }
static long st_getdents64(int fd, void *p, unsigned long n) { return st_sys(217, fd, (long)p, (long)n, 0, 0, 0); }
static long st_getrandom(void *p, unsigned long n) { return st_sys(318, (long)p, (long)n, 0, 0, 0, 0); }

/* ---------------------------------------------------------------- buffers */

struct buf {
    char *data;
    unsigned long len;
    unsigned long cap;
};

static const char *st_prog = "seed-tool";

static void st_raw_fail(const char *text)
{
    st_write(2, text, strlen(text));
    st_exit(1);
}

static void *st_alloc(unsigned long n)
{
    void *p = malloc(n ? n : 1);
    if (!p)
        st_raw_fail("out of memory\n");
    return p;
}

static void b_reserve(struct buf *b, unsigned long extra)
{
    unsigned long need = b->len + extra + 1;
    char *p;
    if (need <= b->cap)
        return;
    if (b->cap < 64)
        b->cap = 64;
    while (b->cap < need)
        b->cap = b->cap * 2;
    p = (char *)st_alloc(b->cap);
    if (b->len)
        memcpy(p, b->data, b->len);
    if (b->data)
        free(b->data);
    b->data = p;
}

static void b_add(struct buf *b, const void *p, unsigned long n)
{
    b_reserve(b, n);
    if (n)
        memcpy(b->data + b->len, p, n);
    b->len = b->len + n;
    b->data[b->len] = 0;
}

static void b_str(struct buf *b, const char *s) { b_add(b, s, strlen(s)); }
static void b_chr(struct buf *b, int c) { char t = (char)c; b_add(b, &t, 1); }

static void b_dec(struct buf *b, long v)
{
    char t[24];
    int n = 0;
    unsigned long u;
    if (v < 0) {
        b_chr(b, '-');
        u = (unsigned long)0 - (unsigned long)v;
    } else
        u = (unsigned long)v;
    do {
        t[n] = (char)('0' + u % 10);
        n = n + 1;
        u = u / 10;
    } while (u);
    while (n) {
        n = n - 1;
        b_chr(b, t[n]);
    }
}

static void b_init(struct buf *b) { b->data = 0; b->len = 0; b->cap = 0; b_reserve(b, 0); b->data[0] = 0; }
static void b_free(struct buf *b) { if (b->data) free(b->data); b->data = 0; b->len = 0; b->cap = 0; }
static char *b_take(struct buf *b) { char *p; if (!b->data) b_init(b); p = b->data; b->data = 0; b->len = 0; b->cap = 0; return p; }

static char *st_strdup(const char *s)
{
    unsigned long n = strlen(s);
    char *p = (char *)st_alloc(n + 1);
    memcpy(p, s, n + 1);
    return p;
}

static char *st_cat3(const char *a, const char *b, const char *c)
{
    struct buf r;
    b_init(&r);
    b_str(&r, a);
    b_str(&r, b);
    b_str(&r, c);
    return b_take(&r);
}

static int st_ends(const char *s, const char *suffix)
{
    unsigned long a = strlen(s), b = strlen(suffix);
    return a >= b && memcmp(s + a - b, suffix, b) == 0;
}

static int st_cmp(const char *a, const char *b)
{
    const unsigned char *x = (const unsigned char *)a, *y = (const unsigned char *)b;
    while (*x && *x == *y) {
        x = x + 1;
        y = y + 1;
    }
    return (int)*x - (int)*y;
}

/* ----------------------------------------------------- output and errors */

static void st_write_all(int fd, const char *p, unsigned long n)
{
    while (n) {
        long w = st_write(fd, p, n);
        if (w == -4)
            continue;
        if (w <= 0)
            return;
        p = p + w;
        n = n - (unsigned long)w;
    }
}

static void st_puts(int fd, const char *s) { st_write_all(fd, s, strlen(s)); }

/* Directories and files to remove before exiting: the private work
   directory, a runtime staging directory, a publication temporary. */
#define ST_CLEAN_MAX 8
static char *st_clean_dirs[ST_CLEAN_MAX];
static char *st_clean_file;
static void st_rm_rf(const char *path);

static void st_cleanup(void)
{
    int i;
    if (st_clean_file) {
        st_unlink(st_clean_file);
        st_clean_file = 0;
    }
    for (i = ST_CLEAN_MAX - 1; i >= 0; i = i - 1)
        if (st_clean_dirs[i]) {
            st_rm_rf(st_clean_dirs[i]);
            st_clean_dirs[i] = 0;
        }
}

static void st_track_dir(char *path)
{
    int i;
    for (i = 0; i < ST_CLEAN_MAX; i = i + 1)
        if (!st_clean_dirs[i]) {
            st_clean_dirs[i] = path;
            return;
        }
    st_raw_fail("too many temporary directories\n");
}

static void st_untrack_dir(const char *path)
{
    int i;
    for (i = 0; i < ST_CLEAN_MAX; i = i + 1)
        if (st_clean_dirs[i] == path)
            st_clean_dirs[i] = 0;
}

static void st_finish(int status)
{
    st_cleanup();
    st_exit(status);
}

/* "PROG: MESSAGE\n" on stderr, clean up, exit with STATUS. */
static void st_fail(int status, const char *message)
{
    struct buf m;
    b_init(&m);
    b_str(&m, st_prog);
    b_str(&m, ": ");
    b_str(&m, message);
    b_chr(&m, '\n');
    st_write_all(2, m.data, m.len);
    st_finish(status);
}

static void st_fail2(int status, const char *a, const char *b)
{
    char *m = st_cat3(a, b, "");
    st_fail(status, m);
}

/* glibc strerror texts, which Python's OSError messages contain. */
static const char *st_errtext(long e)
{
    switch (e) {
    case 1: return "Operation not permitted";
    case 2: return "No such file or directory";
    case 4: return "Interrupted system call";
    case 5: return "Input/output error";
    case 6: return "No such device or address";
    case 9: return "Bad file descriptor";
    case 11: return "Resource temporarily unavailable";
    case 12: return "Cannot allocate memory";
    case 13: return "Permission denied";
    case 16: return "Device or resource busy";
    case 17: return "File exists";
    case 18: return "Invalid cross-device link";
    case 20: return "Not a directory";
    case 21: return "Is a directory";
    case 22: return "Invalid argument";
    case 23: return "Too many open files in system";
    case 24: return "Too many open files";
    case 26: return "Text file busy";
    case 27: return "File too large";
    case 28: return "No space left on device";
    case 30: return "Read-only file system";
    case 31: return "Too many links";
    case 36: return "File name too long";
    case 39: return "Directory not empty";
    case 40: return "Too many levels of symbolic links";
    case 122: return "Disk quota exceeded";
    }
    return 0;
}

/* Python's repr() of a str path (ASCII escapes; other bytes verbatim). */
static void b_repr(struct buf *b, const char *s)
{
    int quote = '\'';
    const unsigned char *p;
    if (strchr(s, '\'') && !strchr(s, '"'))
        quote = '"';
    b_chr(b, quote);
    for (p = (const unsigned char *)s; *p; p = p + 1) {
        int c = *p;
        if (c == quote || c == '\\') {
            b_chr(b, '\\');
            b_chr(b, c);
        } else if (c == '\t')
            b_str(b, "\\t");
        else if (c == '\n')
            b_str(b, "\\n");
        else if (c == '\r')
            b_str(b, "\\r");
        else if (c < 32 || c == 127) {
            const char *hex = "0123456789abcdef";
            b_str(b, "\\x");
            b_chr(b, hex[c / 16]);
            b_chr(b, hex[c % 16]);
        } else
            b_chr(b, c);
    }
    b_chr(b, quote);
}

/* Python OSError text: "[Errno N] Text: 'path'" (or "'a' -> 'b'"). */
static char *st_oserror(long e, const char *path, const char *path2)
{
    struct buf m;
    const char *text = st_errtext(e);
    b_init(&m);
    b_str(&m, "[Errno ");
    b_dec(&m, e);
    b_str(&m, "] ");
    if (text)
        b_str(&m, text);
    else {
        b_str(&m, "Unknown error ");
        b_dec(&m, e);
    }
    if (path) {
        b_str(&m, ": ");
        b_repr(&m, path);
        if (path2) {
            b_str(&m, " -> ");
            b_repr(&m, path2);
        }
    }
    return b_take(&m);
}

static int st_os_status = 1;

static void st_fail_os(long negative, const char *path, const char *path2)
{
    st_fail(st_os_status, st_oserror(-negative, path, path2));
}

/* ------------------------------------------------------------- file I/O */

/* Read a whole file.  Returns 0, or -errno with *B left empty. */
static long st_try_read(const char *path, struct buf *b)
{
    char chunk[65536];
    long fd = st_open(path, ST_O_RDONLY | ST_O_CLOEXEC, 0);
    b_init(b);
    if (fd < 0)
        return fd;
    for (;;) {
        long n = st_read((int)fd, chunk, sizeof chunk);
        if (n == -4)
            continue;
        if (n < 0) {
            st_close((int)fd);
            b_free(b);
            b_init(b);
            return n;
        }
        if (n == 0)
            break;
        b_add(b, chunk, (unsigned long)n);
    }
    st_close((int)fd);
    return 0;
}

static void st_read_file(const char *path, struct buf *b)
{
    long r = st_try_read(path, b);
    if (r < 0)
        st_fail_os(r, path, 0);
}

static void st_read_fd(int fd, struct buf *b)
{
    char chunk[65536];
    b_init(b);
    for (;;) {
        long n = st_read(fd, chunk, sizeof chunk);
        if (n == -4)
            continue;
        if (n < 0)
            st_fail_os(n, "<stdin>", 0);
        if (n == 0)
            return;
        b_add(b, chunk, (unsigned long)n);
    }
}

static long st_write_fd_all(int fd, const char *p, unsigned long n)
{
    while (n) {
        long w = st_write(fd, p, n);
        if (w == -4)
            continue;
        if (w < 0)
            return w;
        if (w == 0)
            return -5;
        p = p + w;
        n = n - (unsigned long)w;
    }
    return 0;
}

/* Create PATH (truncating) with MODE and the given bytes. */
static void st_write_file(const char *path, const char *p, unsigned long n, long mode)
{
    long fd = st_open(path, ST_O_WRONLY | ST_O_CREAT | ST_O_TRUNC | ST_O_CLOEXEC, mode);
    long r;
    if (fd < 0)
        st_fail_os(fd, path, 0);
    r = st_write_fd_all((int)fd, p, n);
    if (r < 0) {
        st_close((int)fd);
        st_fail_os(r, path, 0);
    }
    r = st_close((int)fd);
    if (r < 0)
        st_fail_os(r, path, 0);
}

static int st_is_dir(const char *path)
{
    struct st_stat s;
    return st_stat(path, &s) == 0 && (s.mode & ST_S_IFMT) == ST_S_IFDIR;
}

static int st_is_file(const char *path)
{
    struct st_stat s;
    return st_stat(path, &s) == 0 && (s.mode & ST_S_IFMT) == ST_S_IFREG;
}

static int st_exists(const char *path)
{
    struct st_stat s;
    return st_stat(path, &s) == 0;
}

static int st_lexists(const char *path)
{
    struct st_stat s;
    return st_lstat(path, &s) == 0;
}

/* --------------------------------------------------- directory listings */

struct names {
    char **items;
    unsigned long count;
    unsigned long cap;
};

static void n_add(struct names *n, char *s)
{
    if (n->count == n->cap) {
        char **p;
        unsigned long i;
        n->cap = n->cap ? n->cap * 2 : 32;
        p = (char **)st_alloc(n->cap * sizeof(char *));
        for (i = 0; i < n->count; i = i + 1)
            p[i] = n->items[i];
        if (n->items)
            free(n->items);
        n->items = p;
    }
    n->items[n->count] = s;
    n->count = n->count + 1;
}

static void n_sort(struct names *n)
{
    unsigned long i, j;
    for (i = 1; i < n->count; i = i + 1) {
        char *v = n->items[i];
        j = i;
        while (j > 0 && st_cmp(n->items[j - 1], v) > 0) {
            n->items[j] = n->items[j - 1];
            j = j - 1;
        }
        n->items[j] = v;
    }
}

/* Entry names of DIR, excluding "." and "..".  Returns 0 or -errno. */
static long st_list_dir(const char *dir, struct names *out)
{
    char block[16384];
    long fd = st_open(dir, ST_O_RDONLY | ST_O_DIRECTORY | ST_O_CLOEXEC, 0);
    out->items = 0;
    out->count = 0;
    out->cap = 0;
    if (fd < 0)
        return fd;
    for (;;) {
        long n = st_getdents64((int)fd, block, sizeof block), at = 0;
        if (n < 0) {
            st_close((int)fd);
            return n;
        }
        if (n == 0)
            break;
        while (at < n) {
            unsigned char *rec = (unsigned char *)block + at;
            unsigned int reclen = rec[16] + 256 * rec[17];
            char *name = (char *)rec + 19;
            if (!(name[0] == '.' && (name[1] == 0 || (name[1] == '.' && name[2] == 0))))
                n_add(out, st_strdup(name));
            at = at + (long)reclen;
        }
    }
    st_close((int)fd);
    return 0;
}

static void st_rm_rf(const char *path)
{
    struct st_stat s;
    if (st_lstat(path, &s) < 0)
        return;
    if ((s.mode & ST_S_IFMT) == ST_S_IFDIR) {
        struct names n;
        unsigned long i;
        if (st_list_dir(path, &n) == 0)
            for (i = 0; i < n.count; i = i + 1) {
                char *child = st_cat3(path, "/", n.items[i]);
                st_rm_rf(child);
                free(child);
            }
        st_rmdir(path);
    } else
        st_unlink(path);
}

/* --------------------------------------------------------------- SHA-256 */

static const unsigned int st_k256[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
    0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
    0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu, 0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
    0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u, 0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
    0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u, 0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
    0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u, 0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u
};

static unsigned int st_ror(unsigned int x, int n) { return (x >> n) | (x << (32 - n)); }

static void st_sha_block(unsigned int *h, const unsigned char *p)
{
    unsigned int w[64], a, b, c, d, e, f, g, k, t1, t2;
    int i;
    for (i = 0; i < 16; i = i + 1)
        w[i] = ((unsigned int)p[4 * i] << 24) | ((unsigned int)p[4 * i + 1] << 16)
             | ((unsigned int)p[4 * i + 2] << 8) | (unsigned int)p[4 * i + 3];
    for (i = 16; i < 64; i = i + 1) {
        unsigned int s0 = st_ror(w[i - 15], 7) ^ st_ror(w[i - 15], 18) ^ (w[i - 15] >> 3);
        unsigned int s1 = st_ror(w[i - 2], 17) ^ st_ror(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    a = h[0]; b = h[1]; c = h[2]; d = h[3]; e = h[4]; f = h[5]; g = h[6]; k = h[7];
    for (i = 0; i < 64; i = i + 1) {
        t1 = k + (st_ror(e, 6) ^ st_ror(e, 11) ^ st_ror(e, 25)) + ((e & f) ^ (~e & g)) + st_k256[i] + w[i];
        t2 = (st_ror(a, 2) ^ st_ror(a, 13) ^ st_ror(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
        k = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    h[0] = h[0] + a; h[1] = h[1] + b; h[2] = h[2] + c; h[3] = h[3] + d;
    h[4] = h[4] + e; h[5] = h[5] + f; h[6] = h[6] + g; h[7] = h[7] + k;
}

/* Lowercase hexadecimal SHA-256 of N bytes into OUT (65 bytes). */
static void st_sha256(const char *data, unsigned long n, char *out)
{
    unsigned int h[8];
    unsigned char tail[128];
    unsigned long full = n / 64 * 64, rest = n - full, i, tn;
    unsigned long bits = n * 8;
    const char *hex = "0123456789abcdef";
    h[0] = 0x6a09e667u; h[1] = 0xbb67ae85u; h[2] = 0x3c6ef372u; h[3] = 0xa54ff53au;
    h[4] = 0x510e527fu; h[5] = 0x9b05688cu; h[6] = 0x1f83d9abu; h[7] = 0x5be0cd19u;
    for (i = 0; i < full; i = i + 64)
        st_sha_block(h, (const unsigned char *)data + i);
    memset(tail, 0, sizeof tail);
    if (rest)
        memcpy(tail, data + full, rest);
    tail[rest] = 0x80;
    tn = rest < 56 ? 64 : 128;
    for (i = 0; i < 8; i = i + 1)
        tail[tn - 1 - i] = (unsigned char)(bits >> (8 * i));
    st_sha_block(h, tail);
    if (tn == 128)
        st_sha_block(h, tail + 64);
    for (i = 0; i < 32; i = i + 1) {
        unsigned int v = (h[i / 4] >> (24 - 8 * (i % 4))) & 255u;
        out[2 * i] = hex[v / 16];
        out[2 * i + 1] = hex[v % 16];
    }
    out[64] = 0;
}

/* ------------------------------------------------------- pathlib spelling */

static char *st_cwd(void)
{
    char *p = (char *)st_alloc(8192);
    long r = st_getcwd(p, 8192);
    if (r < 0)
        st_fail_os(r, 0, 0);
    return p;
}

/* str(PurePosixPath(s)): drop empty and "." components; keep "..";
   exactly two leading slashes survive, more collapse to one. */
static char *st_pnorm(const char *s)
{
    struct buf r;
    const char *p = s;
    int first = 1;
    b_init(&r);
    if (s[0] == '/') {
        if (s[1] == '/' && s[2] != '/')
            b_str(&r, "//");
        else
            b_str(&r, "/");
    }
    while (*p) {
        const char *q;
        unsigned long n;
        while (*p == '/')
            p = p + 1;
        q = p;
        while (*q && *q != '/')
            q = q + 1;
        n = (unsigned long)(q - p);
        if (n && !(n == 1 && p[0] == '.')) {
            if (!first)
                b_chr(&r, '/');
            b_add(&r, p, n);
            first = 0;
        }
        p = q;
    }
    if (r.len == 0)
        b_str(&r, ".");
    return b_take(&r);
}

/* str(Path(s).absolute()) */
static char *st_pabs(const char *s)
{
    char *n = st_pnorm(s), *cwd, *r;
    if (n[0] == '/')
        return n;
    cwd = st_cwd();
    if (n[0] == '.' && n[1] == 0)
        r = st_strdup(cwd);
    else if (cwd[0] == '/' && cwd[1] == 0)
        r = st_cat3("/", n, "");
    else
        r = st_cat3(cwd, "/", n);
    free(n);
    free(cwd);
    return r;
}

/* PATH / NAME, then pathlib-normalized. */
static char *st_pjoin(const char *path, const char *name)
{
    char *j = name[0] == '/' ? st_strdup(name) : st_cat3(path, "/", name);
    char *r = st_pnorm(j);
    free(j);
    return r;
}

/* Path.name: the final component of a normalized path. */
static const char *st_pname(const char *path)
{
    const char *s = strrchr(path, '/');
    return s ? s + 1 : path;
}

/* Path.parent of an absolute normalized path. */
static char *st_pparent(const char *path)
{
    const char *s = strrchr(path, '/');
    unsigned long n;
    char *r;
    if (!s)
        return st_strdup(".");
    n = (unsigned long)(s - path);
    while (n > 0 && path[n - 1] == '/')
        n = n - 1;
    if (n == 0)
        n = (unsigned long)(s - path) + 1;
    r = (char *)st_alloc(n + 1);
    memcpy(r, path, n);
    r[n] = 0;
    return r;
}

/* Path.suffix: ".c" for "a.c"; "" for ".c", "a." or "a". */
static const char *st_psuffix(const char *path)
{
    const char *name = st_pname(path), *dot = strrchr(name, '.');
    if (!dot || dot == name || dot[1] == 0)
        return "";
    return dot;
}

/* Path.stem */
static char *st_pstem(const char *path)
{
    const char *name = st_pname(path), *suffix = st_psuffix(path);
    unsigned long n = strlen(name) - strlen(suffix);
    char *r = (char *)st_alloc(n + 1);
    memcpy(r, name, n);
    r[n] = 0;
    return r;
}

/* os.path.realpath(path, strict=False) for an absolute PATH. */
static void st_real_into(struct buf *out, const char *rest, int depth)
{
    const char *p = rest;
    while (*p) {
        const char *q;
        unsigned long n;
        while (*p == '/')
            p = p + 1;
        q = p;
        while (*q && *q != '/')
            q = q + 1;
        n = (unsigned long)(q - p);
        if (n == 0 || (n == 1 && p[0] == '.')) {
            p = q;
            continue;
        }
        if (n == 2 && p[0] == '.' && p[1] == '.') {
            while (out->len > 1 && out->data[out->len - 1] != '/')
                out->len = out->len - 1;
            if (out->len > 1)
                out->len = out->len - 1;
            out->data[out->len] = 0;
            p = q;
            continue;
        }
        {
            unsigned long saved = out->len;
            struct st_stat s;
            if (out->len > 1)
                b_chr(out, '/');
            b_add(out, p, n);
            if (st_lstat(out->data, &s) == 0 && (s.mode & ST_S_IFMT) == ST_S_IFLNK) {
                char target[4097];
                long k = st_readlink(out->data, target, 4096);
                if (k >= 0 && depth < 40) {
                    target[k] = 0;
                    out->len = saved;
                    out->data[out->len] = 0;
                    if (target[0] == '/') {
                        out->len = 1;
                        out->data[1] = 0;
                    }
                    st_real_into(out, target, depth + 1);
                } else if (k >= 0) {
                    /* Symlink loop: keep the unresolved remainder. */
                    b_str(out, q);
                    return;
                }
            }
        }
        p = q;
    }
}

static char *st_resolve(const char *abspath)
{
    struct buf out;
    b_init(&out);
    b_chr(&out, '/');
    st_real_into(&out, abspath, 0);
    return b_take(&out);
}

static int st_samefile(const char *a, const char *b)
{
    struct st_stat x, y;
    if (st_stat(a, &x) < 0 || st_stat(b, &y) < 0)
        return 0;
    return x.dev == y.dev && x.ino == y.ino;
}

/* --------------------------------------------------------- private names */

static unsigned long st_random_state;

static void st_random_name(char *out, int n)
{
    const char *alphabet = "abcdefghijklmnopqrstuvwxyz0123456789_";
    unsigned char raw[16];
    int i;
    if (st_getrandom(raw, (unsigned long)n) != n) {
        st_random_state = st_random_state * 6364136223846793005ul + 1442695040888963407ul
                        + (unsigned long)st_getpid();
        for (i = 0; i < n; i = i + 1)
            raw[i] = (unsigned char)(st_random_state >> (8 * (i % 8)));
    }
    for (i = 0; i < n; i = i + 1)
        out[i] = alphabet[raw[i] % 37];
    out[n] = 0;
}

/* tempfile.gettempdir(): TMPDIR, TEMP, TMP, /tmp, /var/tmp, /usr/tmp, cwd. */
static char *st_mkdtemp_in(const char *dir, const char *prefix, long *error)
{
    int attempt;
    for (attempt = 0; attempt < 100; attempt = attempt + 1) {
        char name[16];
        char *path, *full;
        long r;
        st_random_name(name, 8);
        full = st_cat3(prefix, name, "");
        path = st_cat3(dir, "/", full);
        free(full);
        r = st_mkdir(path, 0700);
        if (r == 0)
            return path;
        free(path);
        if (r != -17) {
            *error = r;
            return 0;
        }
    }
    *error = -17;
    return 0;
}

static char *st_mkdtemp(const char *prefix)
{
    const char *env[3];
    const char *fixed[3];
    int i;
    long error = -2;
    env[0] = getenv("TMPDIR");
    env[1] = getenv("TEMP");
    env[2] = getenv("TMP");
    fixed[0] = "/tmp";
    fixed[1] = "/var/tmp";
    fixed[2] = "/usr/tmp";
    for (i = 0; i < 7; i = i + 1) {
        const char *candidate = i < 3 ? env[i] : i < 6 ? fixed[i - 3] : 0;
        char *dir, *made;
        if (i < 3 && (!candidate || !candidate[0]))
            continue;
        dir = candidate ? st_pabs(candidate) : st_cwd();
        made = st_mkdtemp_in(dir, prefix, &error);
        free(dir);
        if (made)
            return made;
    }
    st_fail(1, "No usable temporary directory found");
    return 0;
}

/* --------------------------------------------------------- seed checking */

/* Python: bytes.fromhex of 000-seed.hex0 with ';'/'#' comments removed,
   compared with the existing seed-forth executable. */
static void st_check_seed(const struct buf *hex0, const struct buf *seed, const char *err_prefix)
{
    struct buf bytes;
    unsigned long i = 0, line_start = 0, pos = 0;
    int in_comment = 0, have_high = 0, high = 0;
    b_init(&bytes);
    (void)line_start;
    for (i = 0; i < hex0->len; i = i + 1) {
        int c = (unsigned char)hex0->data[i];
        int v = -1;
        if (c == '\n' || c == '\r') {
            in_comment = 0;
            continue;
        }
        if (in_comment)
            continue;
        if (c == ';' || c == '#') {
            in_comment = 1;
            continue;
        }
        if (c >= '0' && c <= '9')
            v = c - '0';
        else if (c >= 'a' && c <= 'f')
            v = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F')
            v = c - 'A' + 10;
        if (v < 0 && !have_high && (c == ' ' || c == '\t' || c == 11 || c == 12)) {
            pos = pos + 1;
            continue;
        }
        if (v < 0) {
            struct buf m;
            b_init(&m);
            b_str(&m, err_prefix);
            b_str(&m, "non-hexadecimal number found in fromhex() arg at position ");
            b_dec(&m, (long)pos);
            st_fail(st_os_status, m.data);
        }
        if (have_high) {
            b_chr(&bytes, high * 16 + v);
            have_high = 0;
        } else {
            high = v;
            have_high = 1;
        }
        pos = pos + 1;
    }
    if (have_high) {
        struct buf m;
        b_init(&m);
        b_str(&m, err_prefix);
        b_str(&m, "non-hexadecimal number found in fromhex() arg at position ");
        b_dec(&m, (long)pos);
        st_fail(st_os_status, m.data);
    }
    if (bytes.len != seed->len || memcmp(bytes.data, seed->data, bytes.len) != 0)
        st_fail(st_os_status, "seed-forth does not match 000-seed.hex0; rebuild with build.sh");
    b_free(&bytes);
}

/* ------------------------------------------------------------ source root */

/* The seed-forth checkout: $SEED_CC_ROOT, else two directories above this
   executable (its default home is ROOT/build-out/seed-cc/). */
static char *st_find_root(void)
{
    const char *env = getenv("SEED_CC_ROOT");
    char exe[4097];
    char *abs, *joined, *root;
    long n;
    if (env && env[0]) {
        abs = st_pabs(env);
        root = st_resolve(abs);
        free(abs);
        return root;
    }
    n = st_readlink("/proc/self/exe", exe, 4096);
    if (n <= 0)
        st_fail(1, "cannot locate this executable through /proc/self/exe; set SEED_CC_ROOT");
    exe[n] = 0;
    abs = st_pparent(exe);
    joined = st_cat3(abs, "/../..", "");
    root = st_resolve(joined);
    free(abs);
    free(joined);
    return root;
}

static char *st_self_exe(void)
{
    char exe[4097];
    long n = st_readlink("/proc/self/exe", exe, 4096);
    if (n <= 0)
        return 0;
    exe[n] = 0;
    return st_strdup(exe);
}

/* --------------------------------------------------- running the seed */

/* Run SEED with STDIN_DATA on standard input, capturing its standard
   output and error into OUT and ERR.  Files in WORK carry the streams, so
   no pipe can deadlock.  Returns the exit status, or -signal. */
static long st_run_seed(const char *work, const char *seed, const struct buf *stdin_data,
                        struct buf *out, struct buf *err)
{
    char *in_path = st_cat3(work, "/", "forth-stdin");
    char *out_path = st_cat3(work, "/", "forth-stdout");
    char *err_path = st_cat3(work, "/", "forth-stderr");
    long in_fd, out_fd, err_fd, pid, r;
    int status = 0;
    char *argv[2];
    st_write_file(in_path, stdin_data->data, stdin_data->len, 0600);
    in_fd = st_open(in_path, ST_O_RDONLY | ST_O_CLOEXEC, 0);
    if (in_fd < 0)
        st_fail_os(in_fd, in_path, 0);
    out_fd = st_open(out_path, ST_O_RDWR | ST_O_CREAT | ST_O_TRUNC | ST_O_CLOEXEC, 0600);
    if (out_fd < 0)
        st_fail_os(out_fd, out_path, 0);
    err_fd = st_open(err_path, ST_O_RDWR | ST_O_CREAT | ST_O_TRUNC | ST_O_CLOEXEC, 0600);
    if (err_fd < 0)
        st_fail_os(err_fd, err_path, 0);
    argv[0] = (char *)seed;
    argv[1] = 0;
    pid = st_fork();
    if (pid < 0)
        st_fail_os(pid, 0, 0);
    if (pid == 0) {
        if (st_dup2((int)in_fd, 0) < 0 || st_dup2((int)out_fd, 1) < 0 || st_dup2((int)err_fd, 2) < 0)
            st_exit(127);
        st_execve(seed, argv, environ);
        st_exit(127);
    }
    for (;;) {
        r = st_wait4(pid, &status);
        if (r == -4)
            continue;
        break;
    }
    st_close((int)in_fd);
    st_close((int)out_fd);
    st_close((int)err_fd);
    if (r < 0)
        st_fail_os(r, 0, 0);
    st_read_file(out_path, out);
    st_read_file(err_path, err);
    st_unlink(in_path);
    st_unlink(out_path);
    st_unlink(err_path);
    free(in_path);
    free(out_path);
    free(err_path);
    if ((status & 127) == 0)
        return (status >> 8) & 255;
    return -(long)(status & 127);
}

static long st_umask_value(void)
{
    long mask = st_umask(0);
    st_umask(mask);
    return mask;
}
