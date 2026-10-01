/* sys.c -- the Linux x86-64 syscalls K1 implements.
 *
 * User pointers are used directly: the current process's address space is
 * loaded and K1 runs without SMAP.  A bad pointer faults in the kernel and
 * kills the process (SIGSEGV) rather than returning EFAULT. */

#include "k1.h"

int restart_ok(void);

/* ---- file descriptors ---- */
struct file *fd_get(int fd)
{
    if (fd < 0 || fd >= NFD)
        return NULL;
    return cur->fd[fd];
}

int fd_alloc(struct file *f, int min, int cloexec)
{
    int i;
    for (i = min < 0 ? 0 : min; i < NFD; i++)
        if (!cur->fd[i]) {
            cur->fd[i] = f;
            cur->cloexec[i] = cloexec;
            return i;
        }
    return -EMFILE;
}

void fd_close_all(struct proc *p, int only_cloexec)
{
    int i;
    for (i = 0; i < NFD; i++)
        if (p->fd[i] && (!only_cloexec || p->cloexec[i])) {
            file_put(p->fd[i]);
            p->fd[i] = NULL;
            p->cloexec[i] = 0;
        }
}

static i64 sys_close(int fd)
{
    struct file *f = fd_get(fd);
    if (!f)
        return -EBADF;
    cur->fd[fd] = NULL;
    cur->cloexec[fd] = 0;
    file_put(f);
    return 0;
}

static i64 sys_dup3(int old, int new, int flags)
{
    struct file *f = fd_get(old);
    if (!f || new < 0 || new >= NFD)
        return -EBADF;
    if (old == new)
        return flags ? -EINVAL : new;
    if (cur->fd[new])
        file_put(cur->fd[new]);
    f->refs++;
    cur->fd[new] = f;
    cur->cloexec[new] = (flags & O_CLOEXEC) != 0;
    return new;
}

/* ---- path helpers ---- */
static int at_base(int dfd, const char *path, struct inode **base)
{
    struct file *f;
    if (!path)
        return -EFAULT;
    if (path[0] == '/' || dfd == AT_FDCWD) {
        *base = cur->cwd;
        return 0;
    }
    f = fd_get(dfd);
    if (!f || !f->ino)
        return -EBADF;
    if (!S_ISDIR(f->ino->mode))
        return -ENOTDIR;
    *base = f->ino;
    return 0;
}

static int lookup_at(int dfd, const char *path, int follow, struct inode **ip)
{
    struct inode *b;
    int r = at_base(dfd, path, &b);
    return r ? r : namei(b, path, follow, ip);
}

static int parent_at(int dfd, const char *path, struct inode **dir, char *last)
{
    struct inode *b;
    int r = at_base(dfd, path, &b);
    return r ? r : nameiparent(b, path, dir, last);
}

/* Remember the directory and name a non-directory was opened under, with
 * symlinks in the last component followed, so readlink of /proc/self/fd/N
 * can give its canonical path: musl's realpath works that way (Linux's
 * Makefile uses $(realpath ...) on its source tree). */
static void record_name(struct file *f, int dfd, const char *path)
{
    struct inode *dir, *e;
    char last[256];
    int hops;
    if (parent_at(dfd, path, &dir, last))
        return;
    for (hops = 0; hops < 8; hops++) {
        e = dir_lookup(dir, last, strlen(last));
        if (!e)
            return;
        if (!S_ISLNK(e->mode))
            break;
        if (nameiparent(e->target[0] == '/' ? root : dir, e->target, &dir, last))
            return;
    }
    if (e != f->ino)
        return;
    f->dir = dir;
    dir->refs++;
    f->name = kmalloc(strlen(last) + 1);
    strcpy(f->name, last);
}

/* /proc/self/maps, generated when opened: one line per mapping in Linux's
 * format, with [stack] and [heap] marked.  objtool reads it to find the
 * stack (Linux's build runs objtool on every object). */
static void put_hex(char **p, u64 v, int width)
{
    int i;
    for (i = width - 1; i >= 0; i--, v >>= 4)
        (*p)[i] = "0123456789abcdef"[v & 15];
    *p += width;
}

static i64 open_proc_maps(int flags)
{
    struct mm *m = cur->mm;
    struct inode *ip = inode_new(S_IFREG | 0444);
    struct vma *v, *next;
    struct file *f;
    u64 off = 0, last = 0;
    int r;
    for (;;) {                                  /* in address order */
        char line[128], *p = line;
        next = NULL;
        for (v = m->vmas; v; v = v->next)
            if (v->start >= last && (!next || v->start < next->start))
                next = v;
        if (!next)
            break;
        last = next->end;
        put_hex(&p, next->start, 12);
        *p++ = '-';
        put_hex(&p, next->end, 12);
        *p++ = ' ';
        *p++ = next->prot & 1 ? 'r' : '-';
        *p++ = next->prot & 2 ? 'w' : '-';
        *p++ = next->prot & 4 ? 'x' : '-';
        *p++ = 'p';
        memcpy(p, " 00000000 00:00 0", 17);
        p += 17;
        if (next->end == 0x7FFFFFFFF000UL) {
            memcpy(p, "          [stack]", 17);
            p += 17;
        } else if (m->brk > m->brk0 && next->start <= m->brk0 && m->brk0 < next->end) {
            memcpy(p, "          [heap]", 16);
            p += 16;
        }
        *p++ = '\n';
        inode_write(ip, off, line, p - line);
        off += p - line;
    }
    f = file_new();
    f->ino = ip;
    f->flags = O_RDONLY;
    ip->refs++;
    r = fd_alloc(f, 0, (flags & O_CLOEXEC) != 0);
    if (r < 0)
        file_put(f);
    return r;
}

i64 sys_open_at(int dfd, const char *path, int flags, u32 mode)
{
    if (!strcmp(path, "/proc/self/maps"))
        return open_proc_maps(flags);
    struct inode *ip = NULL, *dir;
    struct file *f;
    char last[256];
    int r, acc = flags & O_ACCMODE;
    if (flags & O_CREAT) {
        r = parent_at(dfd, path, &dir, last);
        if (r == -EEXIST)
            return -EISDIR;
        if (r)
            return r;
        ip = dir_lookup(dir, last, strlen(last));
        if (ip) {
            if (flags & O_EXCL)
                return -EEXIST;
            if (S_ISLNK(ip->mode)) {
                if (flags & O_NOFOLLOW)
                    return -ELOOP;
                r = namei(dir, ip->target, 1, &ip);
                if (r)
                    return r;
            }
        } else {
            if (!S_ISDIR(dir->mode))
                return -ENOTDIR;
            ip = inode_new(S_IFREG | (mode & ~cur->umask & 07777));
            dir_add(dir, last, ip);
        }
    } else {
        r = lookup_at(dfd, path, !(flags & O_NOFOLLOW), &ip);
        if (r)
            return r;
        if (S_ISLNK(ip->mode) && !(flags & O_PATH))
            return -ELOOP;
    }
    if ((flags & O_DIRECTORY) && !S_ISDIR(ip->mode))
        return -ENOTDIR;
    if (S_ISDIR(ip->mode) && acc != O_RDONLY)
        return -EISDIR;
    if ((flags & O_TRUNC) && acc != O_RDONLY && S_ISREG(ip->mode))
        inode_trunc(ip, 0);
    f = file_new();
    f->ino = ip;
    f->flags = flags & ~(O_CREAT | O_EXCL | O_TRUNC | O_CLOEXEC);
    ip->refs++;
    if (!S_ISDIR(ip->mode))
        record_name(f, dfd, path);
    if (S_ISFIFO(ip->mode) && !(flags & O_PATH)) {
        /* A FIFO is a pipe shared by everyone who opens it.  Opens do not
         * wait for the other end (as O_NONBLOCK, or O_RDWR on Linux). */
        if (!ip->fifo) {
            ip->fifo = kmalloc(sizeof *ip->fifo);
            memset(ip->fifo, 0, sizeof *ip->fifo);
        }
        f->pipe = ip->fifo;
        f->wend = acc == O_WRONLY ? 1 : acc == O_RDWR ? 2 : 0;
        if (f->wend)
            f->pipe->writers++;
        if (f->wend != 1)
            f->pipe->readers++;
    }
    r = fd_alloc(f, 0, (flags & O_CLOEXEC) != 0);
    if (r < 0)
        file_put(f);
    return r;
}

/* splice: a read into a kernel buffer, then a write.  Only the form GNU
 * grep uses (no offsets) -- it drains a pipe to /dev/null with it, and
 * treats any failure but EINVAL as an error. */
static i64 sys_splice(int fdin, i64 *offin, int fdout, i64 *offout, u64 len)
{
    static u8 buf[65536];
    struct file *in = fd_get(fdin), *out = fd_get(fdout);
    i64 r, w, done = 0;
    if (!in || !out)
        return -EBADF;
    if (offin || offout)
        return -EINVAL;
    if (len > sizeof buf)
        len = sizeof buf;
    r = file_read(in, buf, len);
    if (r <= 0)
        return r;
    while (done < r) {
        w = file_write(out, buf + done, r - done);
        if (w <= 0)
            return done ? done : w;
        done += w;
    }
    return done;
}

/* mknod: FIFOs only (mkfifo; make 4.4's jobserver). */
static i64 sys_mknod_at(int dfd, const char *path, u32 mode)
{
    struct inode *dir, *ip;
    char last[256];
    int r;
    if (!S_ISFIFO(mode))
        return -EPERM;
    r = parent_at(dfd, path, &dir, last);
    if (r)
        return r == -EEXIST ? -EEXIST : r;
    if (dir_lookup(dir, last, strlen(last)))
        return -EEXIST;
    ip = inode_new(S_IFIFO | (mode & ~cur->umask & 07777));
    return dir_add(dir, last, ip);
}

/* ---- stat ---- */
struct kstat {
    u64 dev, ino, nlink;
    u32 mode, uid, gid, pad0;
    u64 rdev;
    i64 size, blksize, blocks;
    struct timespec atime, mtime, ctime;
    i64 unused[3];
};

static void fill_stat(struct inode *ip, struct kstat *st)
{
    memset(st, 0, sizeof *st);
    st->dev = 1;
    st->ino = ip->ino;
    st->nlink = S_ISDIR(ip->mode) ? 2 : ip->nlink ? ip->nlink : 1;
    st->mode = ip->mode;
    st->uid = ip->uid;
    st->gid = ip->gid;
    st->rdev = S_ISCHR(ip->mode) ? (1 << 8 | ip->dev) : 0;
    st->size = S_ISLNK(ip->mode) ? (i64)strlen(ip->target) : S_ISDIR(ip->mode) ? 4096 : (i64)ip->size;
    st->blksize = 4096;
    st->blocks = (st->size + 511) / 512;
    st->atime = ip->atime;
    st->mtime = ip->mtime;
    st->ctime = ip->ctime;
}

static i64 sys_fstatat(int dfd, const char *path, struct kstat *st, int flags)
{
    struct inode *ip;
    int r;
    if ((flags & AT_EMPTY_PATH) && path && !path[0]) {
        struct file *f = fd_get(dfd);
        if (dfd == AT_FDCWD) {
            fill_stat(cur->cwd, st);
            return 0;
        }
        if (!f)
            return -EBADF;
        if (f->pipe) {
            memset(st, 0, sizeof *st);
            st->mode = S_IFIFO | 0600;
            st->nlink = 1;
            st->blksize = 4096;
            return 0;
        }
        fill_stat(f->ino, st);
        return 0;
    }
    r = lookup_at(dfd, path, !(flags & AT_SYMLINK_NOFOLLOW), &ip);
    if (r)
        return r;
    fill_stat(ip, st);
    return 0;
}

/* ---- directories ---- */
static i64 sys_getdents64(int fd, u8 *buf, u64 n)
{
    struct file *f = fd_get(fd);
    struct inode *d;
    struct dent *e;
    u64 idx = 0, out = 0;
    if (!f || !f->ino)
        return -EBADF;
    d = f->ino;
    if (!S_ISDIR(d->mode))
        return -ENOTDIR;
    e = d->dents;
    for (;;) {
        const char *name;
        u32 nlen;
        struct inode *ip;
        u64 rl;
        if (idx == 0) {
            name = ".", nlen = 1, ip = d;
        } else if (idx == 1) {
            name = "..", nlen = 2, ip = d->parent ? d->parent : d;
        } else {
            if (idx == 2) {
                u64 k;
                e = d->dents;
                for (k = 2; e && k < f->pos; k++)
                    e = e->next;
                if (f->pos > 2)
                    idx = f->pos;
            }
            if (!e)
                break;
            name = e->name, nlen = e->nlen, ip = e->ino;
        }
        if (idx < f->pos && idx < 2) {
            idx++;
            continue;
        }
        rl = ALIGNUP(19 + nlen + 1, 8);
        if (out + rl > n) {
            if (!out)
                return -EINVAL;
            break;
        }
        *(u64 *)(buf + out) = ip->ino;
        *(u64 *)(buf + out + 8) = idx + 1;
        *(u16 *)(buf + out + 16) = rl;
        buf[out + 18] = S_ISDIR(ip->mode) ? 4 : S_ISLNK(ip->mode) ? 10 : S_ISCHR(ip->mode) ? 2 : 8;
        memcpy(buf + out + 19, name, nlen);
        memset(buf + out + 19 + nlen, 0, rl - 19 - nlen);
        out += rl;
        idx++;
        f->pos = idx;
        if (idx > 2)
            e = e->next;
    }
    return out;
}

static i64 sys_mkdirat(int dfd, const char *path, u32 mode)
{
    struct inode *dir, *ip;
    char last[256];
    int r = parent_at(dfd, path, &dir, last);
    if (r == -EINVAL && (!strcmp(last, ".") || !strcmp(last, "..")))
        return -EEXIST;         /* as Linux: tar xf - of "." relies on it */
    if (r)
        return r;
    if (dir_lookup(dir, last, strlen(last)))
        return -EEXIST;
    ip = inode_new(S_IFDIR | (mode & ~cur->umask & 07777));
    dir_add(dir, last, ip);
    return 0;
}

static i64 sys_unlinkat(int dfd, const char *path, int flags)
{
    struct inode *dir, *ip;
    char last[256];
    int r = parent_at(dfd, path, &dir, last);
    if (r)
        return r == -EEXIST ? -EBUSY : r;
    ip = dir_lookup(dir, last, strlen(last));
    if (!ip)
        return -ENOENT;
    if (flags & AT_REMOVEDIR) {
        if (!S_ISDIR(ip->mode))
            return -ENOTDIR;
        if (ip->ndents)
            return -ENOTEMPTY;
        if (ip == root)
            return -EBUSY;
    } else if (S_ISDIR(ip->mode))
        return -EISDIR;
    return dir_remove(dir, last);
}

static i64 sys_linkat(int odfd, const char *old, int ndfd, const char *new, int flags)
{
    struct inode *ip, *dir;
    char last[256];
    int r = lookup_at(odfd, old, (flags & AT_SYMLINK_FOLLOW) != 0, &ip);
    if (r)
        return r;
    if (S_ISDIR(ip->mode))
        return -EPERM;
    r = parent_at(ndfd, new, &dir, last);
    if (r)
        return r;
    if (dir_lookup(dir, last, strlen(last)))
        return -EEXIST;
    dir_add(dir, last, ip);
    return 0;
}

static i64 sys_symlinkat(const char *target, int dfd, const char *path)
{
    struct inode *dir, *ip;
    char last[256];
    int r = parent_at(dfd, path, &dir, last);
    u64 n = strlen(target);
    if (r)
        return r;
    if (dir_lookup(dir, last, strlen(last)))
        return -EEXIST;
    ip = inode_new(S_IFLNK | 0777);
    ip->target = kmalloc(n + 1);
    memcpy(ip->target, target, n + 1);
    ip->size = n;
    dir_add(dir, last, ip);
    return 0;
}

static i64 sys_readlinkat(int dfd, const char *path, char *buf, u64 n)
{
    struct inode *ip;
    u64 l;
    int r;
    if (!memcmp(path, "/proc/self/fd/", 14)) {  /* the open file's canonical path */
        static char p[4096];
        const char *q = path + 14;
        int fd = 0;
        struct file *f;
        for (; *q >= '0' && *q <= '9'; q++)
            fd = fd * 10 + (*q - '0');
        f = *q ? NULL : fd_get(fd);
        if (!f || !f->ino)
            return -ENOENT;
        if (S_ISDIR(f->ino->mode))
            r = path_of(f->ino, p, sizeof p);
        else if (f->dir) {
            r = path_of(f->dir, p, sizeof p);
            if (r > 0) {
                l = strlen(p);
                if (l + 1 + strlen(f->name) + 1 > sizeof p)
                    return -ENAMETOOLONG;
                if (l > 1)
                    p[l++] = '/';
                strcpy(p + l, f->name);
            }
        } else
            return -ENOENT;
        if (r < 0)
            return r;
        l = strlen(p);
        if (l > n)
            l = n;
        memcpy(buf, p, l);
        return l;
    }
    r = lookup_at(dfd, path, 0, &ip);
    if (r)
        return r;
    if (!S_ISLNK(ip->mode))
        return -EINVAL;
    l = strlen(ip->target);
    if (l > n)
        l = n;
    memcpy(buf, ip->target, l);
    return l;
}

static int is_ancestor(struct inode *a, struct inode *d)
{
    while (d && d != root) {
        if (d == a)
            return 1;
        d = d->parent;
    }
    return a == root;
}

static i64 sys_renameat(int odfd, const char *old, int ndfd, const char *new)
{
    struct inode *od, *nd, *src, *dst;
    char ol[256], nl[256];
    int r = parent_at(odfd, old, &od, ol);
    if (r)
        return r == -EEXIST ? -EBUSY : r;
    r = parent_at(ndfd, new, &nd, nl);
    if (r)
        return r == -EEXIST ? -EBUSY : r;
    src = dir_lookup(od, ol, strlen(ol));
    if (!src)
        return -ENOENT;
    dst = dir_lookup(nd, nl, strlen(nl));
    if (dst == src)
        return 0;
    if (S_ISDIR(src->mode) && is_ancestor(src, nd))
        return -EINVAL;
    if (dst) {
        if (S_ISDIR(dst->mode) && !S_ISDIR(src->mode))
            return -EISDIR;
        if (!S_ISDIR(dst->mode) && S_ISDIR(src->mode))
            return -ENOTDIR;
        if (S_ISDIR(dst->mode) && dst->ndents)
            return -ENOTEMPTY;
        dir_remove(nd, nl);
    }
    src->refs++;
    dir_remove(od, ol);
    dir_add(nd, nl, src);
    src->refs--;
    return 0;
}

static i64 sys_chdir_ip(struct inode *ip)
{
    if (!S_ISDIR(ip->mode))
        return -ENOTDIR;
    ip->refs++;
    cur->cwd->refs--;
    iput(cur->cwd);
    cur->cwd = ip;
    return 0;
}

#define UTIME_NOW ((1L << 30) - 1)
#define UTIME_OMIT ((1L << 30) - 2)
static i64 sys_utimensat(int dfd, const char *path, struct timespec *ts, int flags)
{
    struct inode *ip;
    struct timespec now;
    int r;
    if (!path) {
        struct file *f = fd_get(dfd);
        if (!f || !f->ino)
            return -EBADF;
        ip = f->ino;
    } else if ((r = lookup_at(dfd, path, !(flags & AT_SYMLINK_NOFOLLOW), &ip)))
        return r;
    stamp(&now);
    if (!ts) {
        ip->atime = ip->mtime = now;
    } else {
        if (ts[0].nsec != UTIME_OMIT)
            ip->atime = ts[0].nsec == UTIME_NOW ? now : ts[0];
        if (ts[1].nsec != UTIME_OMIT)
            ip->mtime = ts[1].nsec == UTIME_NOW ? now : ts[1];
    }
    ip->ctime = now;
    return 0;
}

/* ---- poll / select ---- */
static int pollq;
struct pollfd { int fd; short events, revents; };
static int poll_one(int fd, int events)
{
    struct file *f = fd_get(fd);
    int rv = 0;
    if (!f)
        return 0x20;            /* POLLNVAL */
    if (f->pipe) {
        struct pipe *p = f->pipe;
        if (f->wend != 1) {
            if (p->r < p->w)
                rv |= 1;
            if (!p->writers)
                rv |= 0x10;     /* POLLHUP */
        }
        if (f->wend) {
            if (p->w - p->r < PIPESZ)
                rv |= 4;
            if (!p->readers)
                rv |= 8;
        }
    } else
        rv = 1 | 4;
    return rv & (events | 0x38);
}

/* pselect6 and ppoll install the caller's signal mask for the wait only,
 * as rt_sigsuspend does: GNU make blocks SIGCHLD and unblocks it just while
 * it waits.  If a signal interrupts the wait, the handler's frame restores
 * the old mask (suspend_mask) and the call fails with EINTR; otherwise the
 * old mask comes back at once. */
static void mask_during_wait(u64 *m)
{
    if (!m)
        return;
    cur->suspend_mask = cur->sigmask;
    cur->suspended = 1;
    cur->sigmask = *m & ~(1UL << 8 | 1UL << 18);    /* never SIGKILL, SIGSTOP */
}

static i64 mask_after_wait(u64 *m, i64 r)
{
    if (!m)
        return r;
    if (r == -ERESTART || r == -EINTR)
        return -EINTR;
    cur->sigmask = cur->suspend_mask;
    cur->suspended = 0;
    return r;
}

static i64 do_poll(struct pollfd *fds, u64 n, i64 timeout_ms)
{
    u64 deadline = timeout_ms > 0 ? now_ns() + timeout_ms * 1000000UL : 0, i;
    for (;;) {
        int cnt = 0;
        for (i = 0; i < n; i++) {
            fds[i].revents = fds[i].fd < 0 ? 0 : poll_one(fds[i].fd, fds[i].events);
            if (fds[i].revents)
                cnt++;
        }
        if (cnt || timeout_ms == 0)
            return cnt;
        if (timeout_ms > 0 && now_ns() >= deadline)
            return 0;
        if (signal_pending())
            return -ERESTART;
        if (timeout_ms < 0)
            sleep_on(&pollq);
        else
            yield();
    }
}

static i64 do_select(int n, u64 *rd, u64 *wr, u64 *ex, i64 timeout_ms)
{
    u64 deadline = timeout_ms > 0 ? now_ns() + timeout_ms * 1000000UL : 0;
    u64 r0[16], w0[16];
    int i, words = (n + 63) / 64;
    if (n > 1024)
        return -EINVAL;
    for (i = 0; i < words; i++) {
        r0[i] = rd ? rd[i] : 0;
        w0[i] = wr ? wr[i] : 0;
    }
    for (;;) {
        int cnt = 0;
        for (i = 0; i < n; i++) {
            u64 b = 1UL << (i % 64);
            int want = ((r0[i / 64] & b) ? 1 : 0) | ((w0[i / 64] & b) ? 4 : 0), got;
            if (!want)
                continue;
            got = poll_one(i, want);
            if (got & 0x20)
                return -EBADF;
            if (rd) {
                if ((got & 0x19) && (r0[i / 64] & b))
                    rd[i / 64] |= b, cnt++;
                else
                    rd[i / 64] &= ~b;
            }
            if (wr) {
                if ((got & 0xC) && (w0[i / 64] & b))
                    wr[i / 64] |= b, cnt++;
                else
                    wr[i / 64] &= ~b;
            }
        }
        if (ex)
            for (i = 0; i < words; i++)
                ex[i] = 0;
        if (cnt || timeout_ms == 0)
            return cnt;
        if (timeout_ms > 0 && now_ns() >= deadline)
            return 0;
        if (signal_pending())
            return -ERESTART;
        if (timeout_ms < 0)
            sleep_on(&pollq);
        else
            yield();
    }
}

void poll_wakeup(void) { wakeup(&pollq); }

static i64 sleep_ns(u64 ns)
{
    u64 deadline = now_ns() + ns;
    while (now_ns() < deadline) {
        if (signal_pending())
            return -EINTR;
        yield();
        __asm__ volatile("pause");
    }
    return 0;
}

/* ITIMER_REAL only; the CPU-time timers are accepted and never fire.
 * struct itimerval: interval {sec, usec}, value {sec, usec}. */
static i64 sys_getitimer(int which, i64 *v)
{
    u64 now = now_ns(), left = cur->alarm_at > now ? cur->alarm_at - now : 0;
    memset(v, 0, 32);
    if (which != 0)
        return 0;
    v[0] = cur->alarm_every / 1000000000UL;
    v[1] = cur->alarm_every % 1000000000UL / 1000;
    v[2] = left / 1000000000UL;
    v[3] = left % 1000000000UL / 1000;
    if (cur->alarm_at && !left)
        v[3] = 1;
    return 0;
}

static i64 sys_setitimer(int which, i64 *nv, i64 *old)
{
    u64 value, every;
    if (old)
        sys_getitimer(which, old);
    if (which != 0 || !nv)
        return 0;
    every = nv[0] * 1000000000UL + nv[1] * 1000UL;
    value = nv[2] * 1000000000UL + nv[3] * 1000UL;
    cur->alarm_every = value ? every : 0;
    cur->alarm_at = value ? now_ns() + value : 0;
    return 0;
}

/* ---- misc ---- */
struct utsname { char f[6][65]; };
static void set_str(char *d, const char *s) { strcpy(d, s); }

static i64 sys_fcntl(int fd, int cmd, u64 arg)
{
    struct file *f = fd_get(fd);
    if (!f)
        return -EBADF;
    switch (cmd) {
    case 0: f->refs++; { int r = fd_alloc(f, arg, 0); if (r < 0) f->refs--; return r; }
    case 1030: f->refs++; { int r = fd_alloc(f, arg, 1); if (r < 0) f->refs--; return r; }
    case 1: return cur->cloexec[fd];
    case 2: cur->cloexec[fd] = arg & 1; return 0;
    case 3: return f->flags;
    case 4: f->flags = (f->flags & O_ACCMODE) | (arg & ~(u64)O_ACCMODE); return 0;
    case 5: *(short *)arg = 2; return 0;        /* F_GETLK: unlocked */
    case 6: case 7: return 0;
    default: return 0;
    }
}

static i64 sys_ioctl(int fd, u64 req, u64 arg)
{
    struct file *f = fd_get(fd);
    if (!f)
        return -EBADF;
    if (req == 0x541B) {                /* FIONREAD */
        *(int *)arg = f->pipe ? (int)(f->pipe->w - f->pipe->r)
                    : f->ino && S_ISREG(f->ino->mode) ? (int)(f->ino->size - f->pos) : 0;
        return 0;
    }
    if (req == 0x5451) { cur->cloexec[fd] = 1; return 0; }     /* FIOCLEX */
    if (req == 0x5450) { cur->cloexec[fd] = 0; return 0; }
    return -ENOTTY;
}

static i64 sys_rlimit(int res, u64 *old)
{
    if (old) {
        old[0] = old[1] = ~0UL;
        if (res == 7)
            old[0] = old[1] = NFD;              /* RLIMIT_NOFILE */
        if (res == 3)
            old[0] = 8 << 20;                   /* RLIMIT_STACK */
    }
    return 0;
}

static i64 rw_vec(int fd, u64 *iov, int cnt, int wr)
{
    struct file *f = fd_get(fd);
    i64 total = 0;
    int i;
    if (!f)
        return -EBADF;
    for (i = 0; i < cnt; i++) {
        i64 r;
        if (!iov[2 * i + 1])
            continue;
        r = wr ? file_write(f, (void *)iov[2 * i], iov[2 * i + 1])
               : file_read(f, (void *)iov[2 * i], iov[2 * i + 1]);
        if (r < 0)
            return total ? total : r;
        total += r;
        if ((u64)r < iov[2 * i + 1])
            break;
    }
    return total;
}

/* ---- dispatch ---- */
static int unknown_seen[512];

static i64 dispatch(struct tframe *tf, i64 nr, u64 a, u64 b, u64 c, u64 d, u64 e, u64 g)
{
    struct file *f;
    struct inode *ip;
    i64 r;
    switch (nr) {
    case 0: f = fd_get(a); return f ? file_read(f, (void *)b, c) : -EBADF;
    case 1: f = fd_get(a); return f ? file_write(f, (void *)b, c) : -EBADF;
    case 2: return sys_open_at(AT_FDCWD, (char *)a, b, c);
    case 3: return sys_close(a);
    case 4: return sys_fstatat(AT_FDCWD, (char *)a, (void *)b, 0);
    case 5: return sys_fstatat(a, "", (void *)b, AT_EMPTY_PATH);
    case 6: return sys_fstatat(AT_FDCWD, (char *)a, (void *)b, AT_SYMLINK_NOFOLLOW);
    case 7: return do_poll((void *)a, b, (int)c);
    case 8: {
        f = fd_get(a);
        if (!f)
            return -EBADF;
        if (f->pipe)
            return -ESPIPE;
        if (c == 0) r = b;
        else if (c == 1) r = f->pos + b;
        else if (c == 2) r = f->ino->size + b;
        else return -EINVAL;
        if (r < 0)
            return -EINVAL;
        f->pos = r;
        return r;
    }
    case 9: return sys_mmap(a, b, c, d, e, g);
    case 10: return sys_mprotect(a, b, c);
    case 11: return sys_munmap(a, b);
    case 12: return sys_brk(a);
    case 13: return sys_rt_sigaction(a, (void *)b, (void *)c, d);
    case 14: return sys_rt_sigprocmask(a, (void *)b, (void *)c, d);
    case 15: return sys_rt_sigreturn(tf);
    case 16: return sys_ioctl(a, b, c);
    case 17: f = fd_get(a); if (!f || !f->ino) return -EBADF; return inode_read(f->ino, d, (void *)b, c);
    case 18: f = fd_get(a); if (!f || !f->ino) return -EBADF; return inode_write(f->ino, d, (void *)b, c);
    case 19: return rw_vec(a, (u64 *)b, c, 0);
    case 20: return rw_vec(a, (u64 *)b, c, 1);
    case 21:
        r = lookup_at(AT_FDCWD, (char *)a, 1, &ip);
        if (r) return r;
        if ((b & 1) && !S_ISDIR(ip->mode) && !(ip->mode & 0111)) return -EACCES;
        return 0;
    case 269: case 439:
        r = lookup_at(a, (char *)b, !(d & AT_SYMLINK_NOFOLLOW), &ip);
        if (r) return r;
        if ((c & 1) && !S_ISDIR(ip->mode) && !(ip->mode & 0111)) return -EACCES;
        return 0;
    case 22: case 293: {
        struct file *fr, *fw;
        int *fds = (int *)a, x, y, ce = nr == 293 && (b & O_CLOEXEC);
        make_pipe(&fr, &fw);
        x = fd_alloc(fr, 0, ce);
        if (x < 0) { file_put(fr); file_put(fw); return x; }
        y = fd_alloc(fw, 0, ce);
        if (y < 0) { sys_close(x); file_put(fw); return y; }
        fds[0] = x;
        fds[1] = y;
        return 0;
    }
    case 23: {
        i64 to = -1;
        if (e) to = ((i64 *)e)[0] * 1000 + ((i64 *)e)[1] / 1000;
        return do_select(a, (u64 *)b, (u64 *)c, (u64 *)d, to);
    }
    case 270: {                             /* pselect6 */
        i64 to = -1, r;
        u64 *m = g ? *(u64 **)g : NULL;     /* 6th argument: { const sigset_t *, size } */
        if (e) to = ((i64 *)e)[0] * 1000 + ((i64 *)e)[1] / 1000000;
        mask_during_wait(m);
        r = do_select(a, (u64 *)b, (u64 *)c, (u64 *)d, to);
        return mask_after_wait(m, r);
    }
    case 271: {                             /* ppoll */
        i64 to = -1, r;
        if (c) to = ((i64 *)c)[0] * 1000 + ((i64 *)c)[1] / 1000000;
        mask_during_wait((u64 *)d);
        r = do_poll((void *)a, b, to);
        return mask_after_wait((u64 *)d, r);
    }
    case 24: yield(); return 0;
    case 34:                                /* pause */
        while (!signal_pending())
            sleep_on(cur);
        return -EINTR;
    case 25: return sys_mremap(a, b, c, d, e);
    case 28: case 221: return 0;                    /* madvise, fadvise64 */
    case 32: f = fd_get(a); if (!f) return -EBADF; f->refs++; r = fd_alloc(f, 0, 0); if (r < 0) f->refs--; return r;
    case 33: if (a == b) return fd_get(a) ? (i64)b : -EBADF; return sys_dup3(a, b, 0);
    case 292: return sys_dup3(a, b, c);
    case 35: return sleep_ns(((i64 *)a)[0] * 1000000000UL + ((i64 *)a)[1]);
    case 230: return sleep_ns(((i64 *)c)[0] * 1000000000UL + ((i64 *)c)[1]);
    case 36: return sys_getitimer(a, (i64 *)b);
    case 37: {                                      /* alarm */
        u64 now = now_ns(), left = cur->alarm_at > now ? cur->alarm_at - now : 0;
        cur->alarm_at = a ? now + a * 1000000000UL : 0;
        cur->alarm_every = 0;
        return (left + 999999999UL) / 1000000000UL;
    }
    case 38: return sys_setitimer(a, (i64 *)b, (i64 *)c);
    case 39: case 186: return cur->pid;
    case 110: return cur->ppid;
    case 41: return -EAFNOSUPPORT;
    case 56: return do_fork(tf, a, b);
    case 57: case 58: return do_fork(tf, 0, 0);
    case 59: return do_execve((char *)a, (char **)b, (char **)c);
    case 60: case 231: do_exit((a & 0xFF) << 8); return 0;
    case 61: return do_wait4(a, (int *)b, c);
    case 62: return sys_kill(a, b);
    case 200: case 234: return sys_kill(nr == 200 ? a : b, nr == 200 ? b : c);
    case 63: {
        struct utsname *u = (void *)a;
        memset(u, 0, sizeof *u);
        set_str(u->f[0], "Linux");
        set_str(u->f[1], "k1");
        set_str(u->f[2], "6.6.0-k1");
        set_str(u->f[3], "#1");
        set_str(u->f[4], "x86_64");
        return 0;
    }
    case 72: return sys_fcntl(a, b, c);
    case 73: case 74: case 75: case 162: return 0;  /* flock, fsync, fdatasync, sync */
    case 76: r = lookup_at(AT_FDCWD, (char *)a, 1, &ip); if (r) return r;
        if (b < ip->size) inode_trunc(ip, b); else ip->size = b; return 0;
    case 77: f = fd_get(a); if (!f || !f->ino) return -EBADF;
        if (b < f->ino->size) inode_trunc(f->ino, b); else f->ino->size = b;
        stamp(&f->ino->mtime); return 0;
    case 79: r = path_of(cur->cwd, (char *)a, b); return r;
    case 80: r = lookup_at(AT_FDCWD, (char *)a, 1, &ip); return r ? r : sys_chdir_ip(ip);
    case 81: f = fd_get(a); return f && f->ino ? sys_chdir_ip(f->ino) : -EBADF;
    case 82: return sys_renameat(AT_FDCWD, (char *)a, AT_FDCWD, (char *)b);
    case 264: case 316: return sys_renameat(a, (char *)b, c, (char *)d);
    case 83: return sys_mkdirat(AT_FDCWD, (char *)a, b);
    case 258: return sys_mkdirat(a, (char *)b, c);
    case 84: return sys_unlinkat(AT_FDCWD, (char *)a, AT_REMOVEDIR);
    case 85: return sys_open_at(AT_FDCWD, (char *)a, O_CREAT | O_WRONLY | O_TRUNC, b);
    case 86: return sys_linkat(AT_FDCWD, (char *)a, AT_FDCWD, (char *)b, 0);
    case 265: return sys_linkat(a, (char *)b, c, (char *)d, e);
    case 87: return sys_unlinkat(AT_FDCWD, (char *)a, 0);
    case 263: return sys_unlinkat(a, (char *)b, c);
    case 88: return sys_symlinkat((char *)a, AT_FDCWD, (char *)b);
    case 266: return sys_symlinkat((char *)a, b, (char *)c);
    case 89: return sys_readlinkat(AT_FDCWD, (char *)a, (char *)b, c);
    case 267: return sys_readlinkat(a, (char *)b, (char *)c, d);
    case 90: r = lookup_at(AT_FDCWD, (char *)a, 1, &ip); if (r) return r;
        ip->mode = (ip->mode & S_IFMT) | (b & 07777); return 0;
    case 268: r = lookup_at(a, (char *)b, 1, &ip); if (r) return r;
        ip->mode = (ip->mode & S_IFMT) | (c & 07777); return 0;
    case 91: f = fd_get(a); if (!f || !f->ino) return -EBADF;
        f->ino->mode = (f->ino->mode & S_IFMT) | (b & 07777); return 0;
    case 92: case 94: r = lookup_at(AT_FDCWD, (char *)a, nr == 92, &ip); if (r) return r;
        if ((int)b != -1) ip->uid = b; if ((int)c != -1) ip->gid = c; return 0;
    case 93: f = fd_get(a); if (!f || !f->ino) return -EBADF;
        if ((int)b != -1) f->ino->uid = b; if ((int)c != -1) f->ino->gid = c; return 0;
    case 260: r = lookup_at(a, (char *)b, !(g & AT_SYMLINK_NOFOLLOW), &ip); if (r) return r;
        if ((int)c != -1) ip->uid = c; if ((int)d != -1) ip->gid = d; return 0;
    case 95: r = cur->umask; cur->umask = a & 0777; return r;
    case 96: { u64 ns = now_ns(); if (a) { ((i64 *)a)[0] = realtime_s(); ((i64 *)a)[1] = ns % 1000000000 / 1000; } return 0; }
    case 201: if (a) *(i64 *)a = realtime_s(); return realtime_s();
    case 228: {
        u64 ns = now_ns();
        i64 *ts = (i64 *)b;
        if (a == 0 || a == 5 || a == 8) { ts[0] = realtime_s(); ts[1] = ns % 1000000000; }
        else { ts[0] = ns / 1000000000; ts[1] = ns % 1000000000; }
        return 0;
    }
    case 229: if (b) { ((i64 *)b)[0] = 0; ((i64 *)b)[1] = 1; } return 0;
    case 97: return sys_rlimit(a, (u64 *)b);
    case 160: return 0;
    case 302: return sys_rlimit(b, (u64 *)d);
    case 98: memset((void *)b, 0, 144); return 0;
    case 100: if (a) memset((void *)a, 0, 32); return now_ns() / 10000000;
    case 99: {
        u64 *s = (u64 *)a;
        memset(s, 0, 112);
        s[0] = now_ns() / 1000000000;
        s[4] = mem_total;
        s[5] = mem_total - mem_used;
        *(u16 *)((u8 *)s + 80) = 10;
        *(u32 *)((u8 *)s + 104) = 1;
        return 0;
    }
    case 102: case 104: case 107: case 108: return 0;
    case 105: case 106: case 113: case 114: case 116: case 117: case 119: case 122: case 123: return 0;
    case 115: return 0;                     /* getgroups: none */
    case 118: case 120:                     /* getresuid, getresgid */
        *(u32 *)a = 0; *(u32 *)b = 0; *(u32 *)c = 0; return 0;
    case 109: {
        struct proc *p;
        int pid = a ? (int)a : cur->pid;
        for (p = procs; p; p = p->next)
            if (p->pid == pid) {
                p->pgid = b ? (int)b : pid;
                return 0;
            }
        return -ESRCH;
    }
    case 111: return cur->pgid;
    case 121: {
        struct proc *p;
        if (!a) return cur->pgid;
        for (p = procs; p; p = p->next) if (p->pid == (int)a) return p->pgid;
        return -ESRCH;
    }
    case 112: cur->sid = cur->pgid = cur->pid; return cur->pid;
    case 124: return cur->sid;
    case 127: *(u64 *)a = cur->sigpend & cur->sigmask; return 0;
    case 130:                               /* rt_sigsuspend */
        cur->suspend_mask = cur->sigmask;
        cur->suspended = 1;
        cur->sigmask = *(u64 *)a & ~(1UL << 8 | 1UL << 18);
        while (!signal_pending())
            sleep_on(cur);
        return -EINTR;          /* the handler's frame restores the old mask */
    case 131: {                     /* sigaltstack: stack_t { sp, int flags, size } */
        u64 *ss = (u64 *)a, *old = (u64 *)b;
        if (old) {
            old[0] = cur->ss_sp;
            old[1] = cur->ss_size ? 0 : 2;          /* SS_DISABLE */
            old[2] = cur->ss_size;
        }
        if (ss) {
            if ((int)ss[1] & 2) {
                cur->ss_sp = cur->ss_size = 0;
            } else {
                if (ss[2] < 2048)
                    return -ENOMEM;
                cur->ss_sp = ss[0];
                cur->ss_size = ss[2];
            }
        }
        return 0;
    }
    case 132: {                             /* utime */
        struct timespec t[2];
        if (!b) return sys_utimensat(AT_FDCWD, (char *)a, NULL, 0);
        t[0].sec = ((i64 *)b)[0]; t[0].nsec = 0; t[1].sec = ((i64 *)b)[1]; t[1].nsec = 0;
        return sys_utimensat(AT_FDCWD, (char *)a, t, 0);
    }
    case 235: case 261: {                   /* utimes, futimesat */
        struct timespec t[2];
        i64 *tv = (i64 *)(nr == 235 ? b : c);
        const char *p = (char *)(nr == 235 ? a : b);
        int dfd = nr == 235 ? AT_FDCWD : (int)a;
        if (!tv) return sys_utimensat(dfd, p, NULL, 0);
        t[0].sec = tv[0]; t[0].nsec = tv[1] * 1000; t[1].sec = tv[2]; t[1].nsec = tv[3] * 1000;
        return sys_utimensat(dfd, p, t, 0);
    }
    case 280: return sys_utimensat(a, (char *)b, (void *)c, d);
    case 137: case 138: {
        u64 *s = (u64 *)b;
        memset(s, 0, 120);
        s[0] = 0x01021994;                  /* TMPFS_MAGIC */
        s[1] = 4096;
        s[2] = mem_total / 4096;
        s[3] = s[4] = (mem_total - mem_used) / 4096;
        s[5] = 1 << 20;
        s[6] = 1 << 20;
        s[8] = 255;
        s[9] = 4096;
        return 0;
    }
    case 157: return 0;                     /* prctl */
    case 158:
        if (a == 0x1002) { cur->fsbase = b; wrmsr(0xC0000100, b); return 0; }
        if (a == 0x1003) { *(u64 *)b = cur->fsbase; return 0; }
        return -EINVAL;
    case 169: {                             /* reboot */
        if (c == 0x4321FEDC || c == 0xCDEF0123) { kprintf("k1: power off\n"); qemu_exit(0); }
        if (c == 0x45584543) return boot_linux("/boot/bzImage", "/boot/initrd.cpio", "/boot/cmdline");
        return -EINVAL;
    }
    case 202: return 0;                     /* futex: one thread per process */
    case 204: if (b >= 8) { *(u64 *)c = 1; return 8; } return -EINVAL;
    case 218: cur->clear_tid = a; return cur->pid;
    case 273: return 0;                     /* set_robust_list */
    case 217: return sys_getdents64(a, (u8 *)b, c);
    case 257: return sys_open_at(a, (char *)b, c, d);
    case 275: return sys_splice(a, (i64 *)b, c, (i64 *)d, e);
    case 133: return sys_mknod_at(AT_FDCWD, (char *)a, b);
    case 259: return sys_mknod_at(a, (char *)b, c);
    case 262: return sys_fstatat(a, (char *)b, (void *)c, d);
    case 318: { u8 *p = (u8 *)a; u64 i; f = NULL; for (i = 0; i < b; i++) p[i] = (u8)(now_ns() * 0x9E3779B97F4A7C15UL >> 56) ^ (u8)i; return b; }
    case 40: case 326: case 332: case 334: case 435: case 285: case 247:
        return -ENOSYS;
    }
    if (nr >= 0 && nr < 512 && !unknown_seen[nr]) {
        unknown_seen[nr] = 1;
        kprintf("k1: unimplemented syscall %ld (%s)\n", nr, cur->comm);
    }
    return -ENOSYS;
}

void syscall_c(struct tframe *tf)
{
    i64 nr = tf->rax, r;
    cur->tf = tf;
    cur->orig_rax = nr;
    check_timers();
    r = dispatch(tf, nr, tf->rdi, tf->rsi, tf->rdx, tf->r10, tf->r8, tf->r9);
    if (nr == 15) {             /* rt_sigreturn restored the whole frame */
        if (cur->ret_full) {    /* another handler's frame must keep rcx, r11 */
            async_rcx = cur->ret_rcx;
            async_r11 = cur->ret_r11;
            async_full = 1;
        }
        deliver_signals(tf);
        if (cur->ret_full && async_full) {      /* nothing delivered: resume */
            static struct trapframe_k { u64 r15, r14, r13, r12, r11, r10, r9, r8, rdi, rsi,
                rbp, rbx, rdx, rcx, rax, vec, err, rip, cs, rflags, rsp, ss; } k;
            async_full = 0;
            cur->ret_full = 0;
            k.r15 = tf->r15; k.r14 = tf->r14; k.r13 = tf->r13; k.r12 = tf->r12;
            k.r11 = cur->ret_r11; k.r10 = tf->r10; k.r9 = tf->r9; k.r8 = tf->r8;
            k.rdi = tf->rdi; k.rsi = tf->rsi; k.rbp = tf->rbp; k.rbx = tf->rbx;
            k.rdx = tf->rdx; k.rcx = cur->ret_rcx; k.rax = tf->rax;
            k.rip = tf->rip; k.cs = 0x33; k.rflags = tf->rflags; k.rsp = tf->rsp; k.ss = 0x2B;
            iret_frame(&k);
        }
        async_full = 0;
        cur->ret_full = 0;
        return;
    }
    if (r == -ERESTART) {
        if (restart_ok()) {
            tf->rax = nr;
            tf->rip -= 2;       /* re-execute the syscall instruction */
        } else
            tf->rax = -EINTR;
    } else if (nr != 59 || r != 0)
        tf->rax = r;
    deliver_signals(tf);
    if (cur->suspended) {       /* sigsuspend without a handler run */
        cur->sigmask = cur->suspend_mask;
        cur->suspended = 0;
    }
}
