/* fs.c -- the RAM file system, pipes and devices.
 *
 * Inodes hold regular data in a 3-level radix tree of pages (files up to
 * 512 GiB, sparse holes read as zero), directories as a list in creation
 * order plus a hash table once they grow, symlinks as a string.  An inode
 * is freed when it has no names (nlink) and no users (refs). */

#include "k1.h"

struct inode *root;
static u64 next_ino = 1;

void stamp(struct timespec *t)
{
    u64 ns = now_ns();
    t->sec = realtime_s();
    t->nsec = ns % 1000000000;
}

struct inode *inode_new(u32 mode)
{
    struct inode *ip = kmalloc(sizeof *ip);
    ip->mode = mode;
    ip->ino = next_ino++;
    stamp(&ip->mtime);
    ip->atime = ip->ctime = ip->mtime;
    return ip;
}

/* ---- regular file data ---- */
static void **radix_slot(struct inode *ip, u64 idx, int create)
{
    void **t;
    int lvl;
    if (!ip->pages) {
        if (!create)
            return NULL;
        ip->pages = P2V(palloc());
    }
    t = ip->pages;
    for (lvl = 2; lvl > 0; lvl--) {
        void **e = &t[(idx >> (9 * lvl)) & 511];
        if (!*e) {
            if (!create)
                return NULL;
            *e = P2V(palloc());
        }
        t = *e;
    }
    return &t[idx & 511];
}

static u8 *page_of(struct inode *ip, u64 idx, int create)
{
    void **s = radix_slot(ip, idx, create);
    if (!s)
        return NULL;
    if (!*s && create)
        *s = P2V(palloc());
    return *s;
}

static u64 rnd_state = 0x9E3779B97F4A7C15UL;
static u8 rnd(void)
{
    rnd_state ^= rnd_state << 13;
    rnd_state ^= rnd_state >> 7;
    rnd_state ^= rnd_state << 17;
    return (u8)(rnd_state >> 32);
}

i64 inode_read(struct inode *ip, u64 off, void *buf, u64 n)
{
    u8 *b = buf;
    u64 done = 0;
    if (S_ISCHR(ip->mode)) {
        if (ip->dev == DEV_ZERO) {
            memset(buf, 0, n);
            return n;
        }
        if (ip->dev == DEV_RANDOM) {
            for (; done < n; done++)
                b[done] = rnd();
            return n;
        }
        if (ip->dev == DEV_HDA || ip->dev == DEV_HDB)
            return ata_dev_rw(ip->dev - DEV_HDA, off, buf, n, 0);
        return 0;               /* null, console: end of file */
    }
    if (S_ISDIR(ip->mode))
        return -EISDIR;
    if (off >= ip->size)
        return 0;
    if (n > ip->size - off)
        n = ip->size - off;
    while (done < n) {
        u64 o = (off + done) & (PAGE - 1), k = PAGE - o;
        u8 *pg = page_of(ip, (off + done) / PAGE, 0);
        if (k > n - done)
            k = n - done;
        if (pg)
            memcpy(b + done, pg + o, k);
        else
            memset(b + done, 0, k);
        done += k;
    }
    return n;
}

i64 inode_write(struct inode *ip, u64 off, const void *buf, u64 n)
{
    const u8 *b = buf;
    u64 done = 0;
    if (S_ISCHR(ip->mode)) {
        if (ip->dev == DEV_CONSOLE)
            console_write(buf, n);
        if (ip->dev == DEV_HDA || ip->dev == DEV_HDB)
            return ata_dev_rw(ip->dev - DEV_HDA, off, (void *)buf, n, 1);
        return n;
    }
    if (!S_ISREG(ip->mode))
        return -EISDIR;
    while (done < n) {
        u64 o = (off + done) & (PAGE - 1), k = PAGE - o;
        u8 *pg = page_of(ip, (off + done) / PAGE, 1);
        if (k > n - done)
            k = n - done;
        memcpy(pg + o, b + done, k);
        done += k;
    }
    if (off + n > ip->size)
        ip->size = off + n;
    stamp(&ip->mtime);
    ip->ctime = ip->mtime;
    return n;
}

static void free_radix(void **t, int lvl, u64 base, u64 keep)
{
    /* free pages with index >= keep under node t covering [base, ...) */
    u64 i, span = (u64)1 << (9 * lvl);
    for (i = 0; i < 512; i++) {
        u64 lo = base + i * span;
        if (!t[i] || lo + span <= keep)
            continue;
        if (lvl > 0) {
            free_radix(t[i], lvl - 1, lo, keep);
            if (lo >= keep) {
                pfree(V2P(t[i]));
                t[i] = NULL;
            }
        } else if (lo >= keep) {
            pfree(V2P(t[i]));
            t[i] = NULL;
        }
    }
}

void inode_trunc(struct inode *ip, u64 size)
{
    if (!S_ISREG(ip->mode))
        return;
    if (size < ip->size && ip->pages) {
        u64 keep = ALIGNUP(size, PAGE) / PAGE;
        u8 *pg;
        free_radix(ip->pages, 2, 0, keep);
        if (size & (PAGE - 1)) {                /* zero the tail of the last page */
            pg = page_of(ip, size / PAGE, 0);
            if (pg)
                memset(pg + (size & (PAGE - 1)), 0, PAGE - (size & (PAGE - 1)));
        }
        if (!size) {
            pfree(V2P(ip->pages));
            ip->pages = NULL;
        }
    }
    ip->size = size;
    stamp(&ip->mtime);
    ip->ctime = ip->mtime;
}

static void inode_free(struct inode *ip)
{
    struct dent *d, *n;
    if (S_ISREG(ip->mode))
        inode_trunc(ip, 0);
    for (d = ip->dents; d; d = n) {
        n = d->next;
        kfree(d);
    }
    if (ip->htab)
        kfree(ip->htab);
    if (ip->target)
        kfree(ip->target);
    kfree(ip);
}

void iput(struct inode *ip)
{
    if (ip && ip->nlink == 0 && ip->refs <= 0 && ip != root)
        inode_free(ip);
}

/* ---- directories ---- */
static u32 hash(const char *s, u32 n)
{
    u32 h = 2166136261u;
    while (n--)
        h = (h ^ (u8)*s++) * 16777619u;
    return h;
}

struct inode *dir_lookup(struct inode *d, const char *name, u32 n)
{
    struct dent *e;
    u32 h = hash(name, n);
    if (d->htab)
        e = d->htab[h & (d->hsize - 1)];
    else
        e = d->dents;
    for (; e; e = d->htab ? e->hnext : e->next)
        if (e->hash == h && e->nlen == n && !memcmp(e->name, name, n))
            return e->ino;
    return NULL;
}

static void rehash(struct inode *d)
{
    struct dent *e;
    if (d->htab)
        kfree(d->htab);
    d->hsize = 64;
    while (d->hsize < d->ndents * 2)
        d->hsize <<= 1;
    d->htab = kmalloc(d->hsize * sizeof *d->htab);
    for (e = d->dents; e; e = e->next) {
        e->hnext = d->htab[e->hash & (d->hsize - 1)];
        d->htab[e->hash & (d->hsize - 1)] = e;
    }
}

int dir_add(struct inode *d, const char *name, struct inode *ip)
{
    u32 n = strlen(name);
    struct dent *e = kmalloc(sizeof *e + n);
    memcpy(e->name, name, n);
    e->nlen = n;
    e->hash = hash(name, n);
    e->ino = ip;
    e->seq = 3 + d->dseq++;     /* after "." and ".." (offsets 0 and 1) */
    if (d->dlast)
        d->dlast->next = e;
    else
        d->dents = e;
    d->dlast = e;
    d->ndents++;
    if (d->htab && d->ndents <= d->hsize) {
        e->hnext = d->htab[e->hash & (d->hsize - 1)];
        d->htab[e->hash & (d->hsize - 1)] = e;
    } else if (d->ndents > 16)
        rehash(d);
    ip->nlink++;
    if (S_ISDIR(ip->mode))
        ip->parent = d;
    stamp(&d->mtime);
    d->ctime = d->mtime;
    return 0;
}

int dir_remove(struct inode *d, const char *name)
{
    u32 n = strlen(name), h = hash(name, n);
    struct dent **pp, *e, *prev = NULL;
    for (pp = &d->dents; (e = *pp); prev = e, pp = &e->next)
        if (e->hash == h && e->nlen == n && !memcmp(e->name, name, n))
            break;
    if (!e)
        return -ENOENT;
    *pp = e->next;
    if (d->dlast == e)
        d->dlast = prev;
    d->ndents--;
    if (d->htab) {
        struct dent **hp = &d->htab[h & (d->hsize - 1)];
        while (*hp != e)
            hp = &(*hp)->hnext;
        *hp = e->hnext;
    }
    e->ino->nlink--;
    stamp(&d->mtime);
    d->ctime = d->mtime;
    iput(e->ino);
    kfree(e);
    return 0;
}

/* ---- path resolution ---- */
static int walk(struct inode *start, const char *path, int follow, struct inode **out,
                struct inode **parent, char *last, int depth)
{
    struct inode *c = path[0] == '/' ? root : start;
    const char *p = path;
    if (depth > 40)
        return -ELOOP;
    if (!*path)
        return -ENOENT;
    for (;;) {
        const char *s;
        u32 n;
        int is_last, trailing;
        struct inode *nx;
        while (*p == '/')
            p++;
        if (!*p) {
            if (parent) {               /* "/" or "x/" handled by caller */
                *parent = c;
                last[0] = 0;
            }
            *out = c;
            return 0;
        }
        s = p;
        while (*p && *p != '/')
            p++;
        n = p - s;
        if (n > 255)
            return -ENAMETOOLONG;
        trailing = *p == '/';
        while (*p == '/')
            p++;
        is_last = !*p;
        if (!S_ISDIR(c->mode))
            return -ENOTDIR;
        if (is_last && parent) {
            *parent = c;
            memcpy(last, s, n);
            last[n] = 0;
            if (n == 1 && s[0] == '.')
                return -EINVAL;
            if (n == 2 && s[0] == '.' && s[1] == '.')
                return -EINVAL;
            return 0;
        }
        if (n == 1 && s[0] == '.') {
            nx = c;
        } else if (n == 2 && s[0] == '.' && s[1] == '.') {
            nx = c->parent ? c->parent : root;
        } else {
            nx = dir_lookup(c, s, n);
            if (!nx)
                return -ENOENT;
            if (S_ISLNK(nx->mode) && (!is_last || follow || trailing)) {
                int r = walk(c, nx->target, 1, &nx, NULL, NULL, depth + 1);
                if (r)
                    return r;
            }
        }
        if (is_last) {
            if (trailing && !S_ISDIR(nx->mode))
                return -ENOTDIR;
            *out = nx;
            return 0;
        }
        c = nx;
    }
}

/* /proc/self/fd/N names the file open on descriptor N.  It is the only
 * part of /proc K1 has: musl's fchmodat(AT_SYMLINK_NOFOLLOW) and fchownat
 * reach the file through it (GNU tar sets every extracted file's mode). */
static int proc_self_fd(const char *path, struct inode **out)
{
    const char *p = path + 14;
    long n = 0;
    if (memcmp(path, "/proc/self/fd/", 14) || !*p)
        return 1;
    for (; *p; p++) {
        if (*p < '0' || *p > '9')
            return 1;
        n = n * 10 + (*p - '0');
        if (n >= NFD)
            return -EBADF;
    }
    if (!cur || !cur->fd[n] || !cur->fd[n]->ino)
        return -EBADF;
    *out = cur->fd[n]->ino;
    return 0;
}

int namei(struct inode *cwd, const char *path, int follow, struct inode **out)
{
    int r = proc_self_fd(path, out);
    if (r <= 0)
        return r;
    return walk(cwd, path, follow, out, NULL, NULL, 0);
}

/* the directory that would hold path's last component, and that name */
int nameiparent(struct inode *cwd, const char *path, struct inode **dir, char *last)
{
    struct inode *dummy;
    int r = walk(cwd, path, 1, &dummy, dir, last, 0);
    if (r)
        return r;
    if (!last[0])
        return -EEXIST;         /* "/" itself */
    return 0;
}

int path_of(struct inode *d, char *buf, u64 n)
{
    char tmp[4096];
    u64 len = 0;
    tmp[0] = 0;
    if (d == root) {
        if (n < 2)
            return -ERANGE;
        strcpy(buf, "/");
        return 2;
    }
    while (d != root && d->parent) {
        struct inode *p = d->parent;
        struct dent *e;
        for (e = p->dents; e; e = e->next)
            if (e->ino == d)
                break;
        if (!e || len + e->nlen + 1 >= sizeof tmp)
            return -ENOENT;
        memmove(tmp + e->nlen + 1, tmp, len + 1);
        tmp[0] = '/';
        memcpy(tmp + 1, e->name, e->nlen);
        len += e->nlen + 1;
        d = p;
    }
    if (len + 1 > n)
        return -ERANGE;
    memcpy(buf, tmp, len + 1);
    return len + 1;
}

/* ---- open files and pipes ---- */
struct file *file_new(void)
{
    struct file *f = kmalloc(sizeof *f);
    f->refs = 1;
    return f;
}

void file_put(struct file *f)
{
    if (--f->refs > 0)
        return;
    if (f->pipe) {
        struct pipe *p = f->pipe;
        if (f->wend)
            p->writers--;
        if (f->wend != 1)
            p->readers--;
        wakeup(p);
        poll_wakeup();
        if (!p->readers && !p->writers) {
            int i;
            for (i = 0; i < 16; i++)
                if (p->pg[i])
                    pfree(V2P(p->pg[i]));
            kfree(p);
            if (f->ino && f->ino->fifo == p)
                f->ino->fifo = NULL;
        }
    }
    if (f->ino) {
        f->ino->refs--;
        iput(f->ino);
    }
    if (f->dir) {
        f->dir->refs--;
        iput(f->dir);
        kfree(f->name);
    }
    kfree(f);
}

static i64 pipe_read(struct pipe *p, u8 *buf, u64 n)
{
    u64 done = 0;
    while (p->r == p->w) {
        if (!p->writers)
            return 0;
        if (signal_pending())
            return -ERESTART;
        sleep_on(p);
    }
    while (done < n && p->r < p->w) {
        u64 o = p->r % PIPESZ, k = PAGE - o % PAGE;
        if (k > p->w - p->r)
            k = p->w - p->r;
        if (k > n - done)
            k = n - done;
        memcpy(buf + done, p->pg[o / PAGE] + o % PAGE, k);
        p->r += k;
        done += k;
    }
    wakeup(p);
    poll_wakeup();
    return done;
}

static i64 pipe_write(struct pipe *p, const u8 *buf, u64 n)
{
    u64 done = 0;
    while (done < n) {
        u64 space, o, k;
        if (!p->readers) {
            send_signal(cur, 13);       /* SIGPIPE */
            return done ? (i64)done : -EPIPE;
        }
        space = PIPESZ - (p->w - p->r);
        if (!space) {
            wakeup(p);
            if (signal_pending())
                return done ? (i64)done : -ERESTART;
            sleep_on(p);
            continue;
        }
        o = p->w % PIPESZ;
        k = PAGE - o % PAGE;
        if (k > space)
            k = space;
        if (k > n - done)
            k = n - done;
        if (!p->pg[o / PAGE])
            p->pg[o / PAGE] = P2V(palloc());
        memcpy(p->pg[o / PAGE] + o % PAGE, buf + done, k);
        p->w += k;
        done += k;
    }
    wakeup(p);
    poll_wakeup();
    return done;
}

int make_pipe(struct file **r, struct file **w)
{
    struct pipe *p = kmalloc(sizeof *p);
    *r = file_new();
    *w = file_new();
    (*r)->pipe = (*w)->pipe = p;
    (*w)->wend = 1;
    (*w)->flags = O_WRONLY;
    p->readers = p->writers = 1;
    return 0;
}

i64 file_read(struct file *f, void *buf, u64 n)
{
    i64 r;
    if (f->pipe)
        return f->wend == 1 ? -EBADF : pipe_read(f->pipe, buf, n);
    if ((f->flags & O_ACCMODE) == O_WRONLY)
        return -EBADF;
    r = inode_read(f->ino, f->pos, buf, n);
    if (r > 0 && (!S_ISCHR(f->ino->mode) || f->ino->dev >= DEV_HDA))
        f->pos += r;
    return r;
}

i64 file_write(struct file *f, const void *buf, u64 n)
{
    i64 r;
    if (f->pipe)
        return f->wend ? pipe_write(f->pipe, buf, n) : -EBADF;
    if ((f->flags & O_ACCMODE) == O_RDONLY)
        return -EBADF;
    if (f->flags & O_APPEND)
        f->pos = f->ino->size;
    r = inode_write(f->ino, f->pos, buf, n);
    if (r > 0 && (!S_ISCHR(f->ino->mode) || f->ino->dev >= DEV_HDA))
        f->pos += r;
    return r;
}

/* ---- setup ---- */
static struct inode *mkdir_p(const char *path, u32 mode)
{
    char comp[256];
    struct inode *c = root;
    const char *p = path;
    while (*p) {
        const char *s;
        struct inode *nx;
        u32 n;
        while (*p == '/')
            p++;
        if (!*p)
            break;
        s = p;
        while (*p && *p != '/')
            p++;
        n = p - s;
        memcpy(comp, s, n);
        comp[n] = 0;
        nx = dir_lookup(c, comp, n);
        if (!nx) {
            nx = inode_new(S_IFDIR | mode);
            dir_add(c, comp, nx);
        }
        c = nx;
    }
    return c;
}

static void mkdev(struct inode *dev, const char *name, int which)
{
    struct inode *ip = inode_new(S_IFCHR | 0666);
    ip->dev = which;
    dir_add(dev, name, ip);
}

struct inode *fs_mkdir_p(const char *path, u32 mode)
{
    return mkdir_p(path, mode);
}

/* A new regular file at path (its directories made as needed). */
struct inode *fs_create(const char *path, u32 mode)
{
    char dir[4096];
    const char *slash = NULL, *q;
    struct inode *d = root, *ip;
    for (q = path; *q; q++)
        if (*q == '/')
            slash = q;
    if (slash) {
        if ((u64)(slash - path) >= sizeof dir)
            return NULL;
        memcpy(dir, path, slash - path);
        dir[slash - path] = 0;
        d = mkdir_p(dir, 0755);
    }
    ip = inode_new(S_IFREG | (mode & 07777));
    if (dir_add(d, slash ? slash + 1 : path, ip))
        return NULL;
    return ip;
}

void fs_init(void)
{
    struct inode *dev, *tmp;
    root = inode_new(S_IFDIR | 0755);
    root->parent = root;
    root->nlink = 1;
    dev = mkdir_p("dev", 0755);
    mkdev(dev, "null", DEV_NULL);
    mkdev(dev, "zero", DEV_ZERO);
    mkdev(dev, "tty", DEV_CONSOLE);
    mkdev(dev, "console", DEV_CONSOLE);
    mkdev(dev, "random", DEV_RANDOM);
    mkdev(dev, "urandom", DEV_RANDOM);
    mkdev(dev, "hda", DEV_HDA);
    mkdev(dev, "hdb", DEV_HDB);
    tmp = mkdir_p("tmp", 01777);
    tmp->mode = S_IFDIR | 01777;
    rnd_state ^= now_ns();
}

/* Copy K0's file table (k0/mkfs.py's format) into the RAM fs, then give
 * K0's image memory back to the page allocator. */
#define FSIMG 0x50000000UL
void fs_import_k0(const char *prefix)
{
    u32 end = *(u32 *)P2V(FSIMG + 0x10), heap = *(u32 *)P2V(FSIMG + 0x18);
    u32 e;
    u64 files = 0, bytes = 0, pa;
    char name[4096];
    for (e = FSIMG + 0x4000; e < end; e += 24) {
        u32 *ent = P2V(e);
        u32 nlen = ent[1], type = ent[5];
        char *slash;
        struct inode *dir, *ip;
        if (!type || !nlen || nlen >= sizeof name)
            continue;
        {
            u64 pl = strlen(prefix);
            if (pl + nlen >= sizeof name)
                continue;
            memcpy(name, prefix, pl);
            memcpy(name + pl, P2V(ent[0]), nlen);
            name[pl + nlen] = 0;
        }
        if (type == 2) {
            mkdir_p(name, 0755);
            continue;
        }
        slash = NULL;
        {
            char *q;
            for (q = name; *q; q++)
                if (*q == '/')
                    slash = q;
        }
        if (slash) {
            *slash = 0;
            dir = mkdir_p(name, 0755);
            *slash = '/';
        } else
            dir = root;
        ip = inode_new(S_IFREG | 0755);
        inode_write(ip, 0, P2V(ent[2]), ent[3]);
        dir_add(dir, slash ? slash + 1 : name, ip);
        files++;
        bytes += ent[3];
    }
    for (pa = FSIMG; pa < ALIGNUP((u64)heap, PAGE); pa += PAGE) {
        mem_used += PAGE;
        pfree(pa);
    }
    kprintf("k1: imported %lu files, %lu KiB from K0%s%s\n", files, bytes >> 10,
            *prefix ? " into /" : "", prefix);
}
