/* mm.c -- physical pages, kmalloc, per-process address spaces.
 *
 * Physical pages: a free list, then a bump pointer over the e820 RAM
 * regions, so untouched RAM is never written (KVM then never backs it).
 * Address spaces: 4-level page tables; the upper half is the shared
 * direct map, PD entries 0-1 map K1's image (supervisor only), the rest
 * is the process's.  User memory is demand-zero inside its VMAs; fork
 * copies every present page (no copy-on-write). */

#include "k1.h"

struct e820 { u64 addr, len; u32 type; } __attribute__((packed));
extern struct e820 e820_map[];
extern int e820_n;
extern u64 *kpml4, *kpd_low;

#define FSIMG 0x50000000UL

/* ---- physical pages ---- */
static struct { u64 start, end; } reg[40];
static int nreg, curreg;
static u64 bump;
static u64 freelist;            /* physical address of the first free page */
u64 mem_total, mem_used;

static void reg_add(u64 s, u64 e)
{
    s = ALIGNUP(s, PAGE);
    e = ALIGNDN(e, PAGE);
    if (s < e && nreg < 40) {
        reg[nreg].start = s;
        reg[nreg].end = e;
        nreg++;
        mem_total += e - s;
    }
}

void phys_init(void)
{
    /* Keep out: the low 4 MiB (BIOS, K0, K1), K0's boot image and file
     * heap (released after the import), and K0's mmap area. */
    u64 fs_end = *(u32 *)P2V(FSIMG + 0x18);         /* K0's G_HEAP */
    u64 k0bump = *(u32 *)P2V(FSIMG + 0x20);         /* K0's G_BUMP */
    int i, j;
    for (i = 0; i < e820_n; i++) {
        u64 s = e820_map[i].addr, e = s + e820_map[i].len;
        if (e820_map[i].type != 1)
            continue;
        if (s < 0x400000)
            s = 0x400000;
        if (s < FSIMG && e > FSIMG) {
            reg_add(s, FSIMG);
            s = FSIMG;
        }
        if (s < fs_end)
            s = fs_end;
        if (s < 0x80000000UL && e > 0x80000000UL && k0bump > 0x80000000UL) {
            reg_add(s, 0x80000000UL);
            s = k0bump;
        }
        reg_add(s, e);
    }
    /* sort by start (few entries) */
    for (i = 0; i < nreg; i++)
        for (j = i + 1; j < nreg; j++)
            if (reg[j].start < reg[i].start) {
                u64 a = reg[i].start, b = reg[i].end;
                reg[i] = reg[j];
                reg[j].start = a;
                reg[j].end = b;
            }
    curreg = 0;
    bump = reg[0].start;
}

static u64 pbump(u64 n)          /* n contiguous pages from the bump area */
{
    while (curreg < nreg) {
        if (bump + n * PAGE <= reg[curreg].end) {
            u64 p = bump;
            bump += n * PAGE;
            return p;
        }
        curreg++;
        if (curreg < nreg)
            bump = reg[curreg].start;
    }
    panic("out of memory");
    return 0;
}

/* contiguous physical memory for handing off to Linux: never freed */
u64 palloc_contig(u64 bytes, u64 align, u64 min)
{
    while (curreg < nreg) {
        u64 p = ALIGNUP(bump > min ? bump : min, align);
        if (p + bytes <= reg[curreg].end) {
            bump = p + ALIGNUP(bytes, PAGE);
            return p;
        }
        curreg++;
        if (curreg < nreg)
            bump = reg[curreg].start;
    }
    return 0;
}

u64 palloc(void)
{
    u64 p;
    if (freelist) {
        p = freelist;
        freelist = *(u64 *)P2V(p);
    } else
        p = pbump(1);
    memset(P2V(p), 0, PAGE);
    mem_used += PAGE;
    return p;
}

void pfree(u64 pa)
{
    *(u64 *)P2V(pa) = freelist;
    freelist = pa;
    mem_used -= PAGE;
}

/* ---- kmalloc: power-of-two classes 32..4096 (with a 16-byte header);
 * larger requests take contiguous pages: a freed block of up to BIGMAX
 * pages goes on a list for its size and is reused whole, since the bump
 * area never gets pages back (kernel stacks and exec buffers are such
 * blocks, one or more per process) ---- */
#ifndef K1_MMAP_HINTS
#define K1_MMAP_HINTS 1
#endif
#define BIGMAX 1024                     /* execve's 2 MiB argument buffer is 513 pages */
static void *kfree_lists[8];
static void *big_free[BIGMAX + 1];
void *kmalloc(u64 n)
{
    u64 total = n + 16, sz = 32;
    int c = 0;
    u8 *p;
    if (total > PAGE) {
        u64 pages = ALIGNUP(total, PAGE) / PAGE;
        if (pages <= BIGMAX && big_free[pages]) {
            p = big_free[pages];
            big_free[pages] = *(void **)p;
        } else
            p = P2V(pbump(pages));
        mem_used += pages * PAGE;
        memset(p, 0, pages * PAGE);
        *(u64 *)p = 100 + pages;
        return p + 16;
    }
    while (sz < total)
        sz <<= 1, c++;
    if (!kfree_lists[c]) {
        u8 *pg = P2V(palloc());
        u64 off;
        for (off = 0; off + sz <= PAGE; off += sz) {
            *(void **)(pg + off) = kfree_lists[c];
            kfree_lists[c] = pg + off;
        }
    }
    p = kfree_lists[c];
    kfree_lists[c] = *(void **)p;
    memset(p, 0, sz);
    *(u64 *)p = c;
    return p + 16;
}

void kfree(void *v)
{
    u8 *p = (u8 *)v - 16;
    u64 c;
    if (!v)
        return;
    c = *(u64 *)p;
    if (c >= 100) {
        u64 i, pages = c - 100;
        if (pages <= BIGMAX) {
            *(void **)p = big_free[pages];
            big_free[pages] = p;
            mem_used -= pages * PAGE;
            return;
        }
        for (i = 0; i < pages; i++)
            pfree(V2P(p + i * PAGE));
        return;
    }
    *(void **)p = kfree_lists[c];
    kfree_lists[c] = p;
}

/* ---- page tables ---- */
#define PTE_P 1
#define PTE_W 2
#define PTE_U 4
#define PTE_PS 0x80
#define PTE_ADDR 0x000FFFFFFFFFF000UL

struct mm *mm_new(void)
{
    struct mm *m = kmalloc(sizeof *m);
    u64 *pdpt, *pd;
    int i;
    m->pml4 = P2V(palloc());
    for (i = 256; i < 512; i++)
        m->pml4[i] = kpml4[i];
    pdpt = P2V(palloc());
    pd = P2V(palloc());
    pd[0] = kpd_low[0];
    pd[1] = kpd_low[1];
    pdpt[0] = V2P(pd) | 7;
    m->pml4[0] = V2P(pdpt) | 7;
    m->mmap_top = 0x7F0000000000UL;
    m->refs = 1;
    return m;
}

u64 *pte_get(struct mm *m, u64 va, int create)
{
    u64 *t = m->pml4;
    int lvl;
    if (va < 0x400000 || va >= 0x800000000000UL)
        return NULL;
    for (lvl = 3; lvl > 0; lvl--) {
        u64 *e = &t[(va >> (12 + 9 * lvl)) & 511];
        if (!(*e & PTE_P)) {
            if (!create)
                return NULL;
            *e = palloc() | 7;
        }
        if (*e & PTE_PS)
            return NULL;
        t = P2V(*e & PTE_ADDR);
    }
    return &t[(va >> 12) & 511];
}

static void free_level(u64 *t, int lvl, int top)
{
    int i, n = top ? 256 : 512;
    for (i = 0; i < n; i++) {
        u64 e = t[i];
        if (!(e & PTE_P) || (e & PTE_PS))
            continue;
        if (lvl > 0)
            free_level(P2V(e & PTE_ADDR), lvl - 1, 0);
        pfree(e & PTE_ADDR);
    }
}

void mm_free(struct mm *m)
{
    struct vma *v, *n;
    if (--m->refs > 0)
        return;
    free_level(m->pml4, 3, 1);
    pfree(V2P(m->pml4));
    for (v = m->vmas; v; v = n) {
        n = v->next;
        kfree(v);
    }
    kfree(m);
}

static void copy_level(u64 *src, u64 *dst, int lvl, int top)
{
    int i, n = top ? 256 : 512;
    for (i = 0; i < n; i++) {
        u64 e = src[i];
        if (!(e & PTE_P))
            continue;
        if (e & PTE_PS) {
            dst[i] = e;         /* K1's own 2 MiB pages */
            continue;
        }
        if (!(dst[i] & PTE_P))      /* tables: user rwx; pages: their own bits */
            dst[i] = palloc() | (e & 0xFFF) | (lvl > 0 ? 7 : 0);
        if (lvl > 0)
            copy_level(P2V(e & PTE_ADDR), P2V(dst[i] & PTE_ADDR), lvl - 1, 0);
        else
            memcpy(P2V(dst[i] & PTE_ADDR), P2V(e & PTE_ADDR), PAGE);
    }
}

struct mm *mm_copy(struct mm *m)
{
    struct mm *n = mm_new();
    struct vma *v, **tail = &n->vmas;
    copy_level(m->pml4, n->pml4, 3, 1);
    for (v = m->vmas; v; v = v->next) {
        struct vma *c = kmalloc(sizeof *c);
        *c = *v;
        c->next = NULL;
        *tail = c;
        tail = &c->next;
    }
    n->brk0 = m->brk0;
    n->brk = m->brk;
    n->mmap_top = m->mmap_top;
    return n;
}

void mm_switch(struct mm *m) { load_cr3(V2P(m->pml4)); }

struct vma *vma_find(struct mm *m, u64 va)
{
    struct vma *v;
    for (v = m->vmas; v; v = v->next)
        if (va >= v->start && va < v->end)
            return v;
    return NULL;
}

/* Page-table bits for a mapping's protection (PROT_READ 1, WRITE 2, EXEC 4):
 * PROT_NONE pages are present but not user-accessible; read-only pages
 * lack W.  K1 never sets CR0.WP, so the kernel itself still writes them. */
static u64 prot_bits(int prot)
{
    return PTE_P | (prot ? PTE_U : 0) | ((prot & 2) ? PTE_W : 0);
}

/* A user access at va (a write if write): map a zeroed page if its mapping
 * allows the access; -1 if no mapping allows it (the caller's SIGSEGV). */
int mm_fault(struct mm *m, u64 va, int write)
{
    struct vma *v = vma_find(m, va);
    u64 *pte;
    if (!v || !v->prot || (write && !(v->prot & 2)))
        return -1;
    pte = pte_get(m, va, 1);
    if (!pte)
        return -1;
    if (!(*pte & PTE_P))
        *pte = palloc() | prot_bits(v->prot);
    else {                          /* present: make its bits match, then retry */
        *pte = (*pte & ~(u64)(PTE_W | PTE_U)) | prot_bits(v->prot);
        __asm__ volatile("invlpg (%0)" :: "r"(va) : "memory");
    }
    return 0;
}

/* Split the mapping containing at (strictly inside it) into two. */
static void vma_split(struct mm *m, u64 at)
{
    struct vma *v = vma_find(m, at), *w;
    if (!v || v->start == at)
        return;
    w = kmalloc(sizeof *w);
    w->start = at;
    w->end = v->end;
    w->prot = v->prot;
    w->next = v->next;
    v->end = at;
    v->next = w;
}

int copy_to_mm(struct mm *m, u64 va, const void *src, u64 n)
{
    const u8 *s = src;
    while (n) {
        u64 *pte = pte_get(m, va, 1), off = va & (PAGE - 1), k = PAGE - off;
        if (!pte)
            return -EFAULT;
        if (!(*pte & PTE_P))
            *pte = palloc() | 7;
        if (k > n)
            k = n;
        if (s)
            memcpy((u8 *)P2V(*pte & PTE_ADDR) + off, s, k);
        s = s ? s + k : NULL;
        va += k;
        n -= k;
    }
    return 0;
}

/* remove [start, end) from the VMAs and free its pages */
void mm_unmap(struct mm *m, u64 start, u64 end)
{
    struct vma **pp = &m->vmas, *v;
    u64 va;
    while ((v = *pp)) {
        if (v->end <= start || v->start >= end) {
            pp = &v->next;
            continue;
        }
        if (v->start < start && v->end > end) {        /* split */
            struct vma *t = kmalloc(sizeof *t);
            t->start = end;
            t->end = v->end;
            t->prot = v->prot;
            t->next = v->next;
            v->end = start;
            v->next = t;
            pp = &t->next;
            continue;
        }
        if (v->start >= start && v->end <= end) {
            *pp = v->next;
            kfree(v);
            continue;
        }
        if (v->start < start)
            v->end = start;
        else
            v->start = end;
        pp = &v->next;
    }
    for (va = start; va < end; va += PAGE) {
        u64 *pte = pte_get(m, va, 0);
        if (pte && (*pte & PTE_P)) {
            pfree(*pte & PTE_ADDR);
            *pte = 0;
        }
    }
    load_cr3(V2P(cur->mm->pml4));       /* flush the TLB */
}

int mm_map(struct mm *m, u64 start, u64 end, int prot)
{
    struct vma *v;
    for (v = m->vmas; v; v = v->next)
        if (v->end == start && v->prot == prot) {   /* extend an adjacent VMA */
            v->end = end;
            return 0;
        }
    v = kmalloc(sizeof *v);
    v->start = start;
    v->end = end;
    v->prot = prot;
    v->next = m->vmas;
    m->vmas = v;
    return 0;
}

/* ---- syscalls ---- */
#define MAP_SHARED 1
#define MAP_FIXED 0x10
#define MAP_ANON 0x20

/* No mapping overlaps [start, end), which is in user space below the stack. */
static int range_free(struct mm *m, u64 start, u64 end)
{
    struct vma *v;
    if (end <= start || start < 0x10000 || end > 0x7FFFF0000000UL)
        return 0;
    for (v = m->vmas; v; v = v->next)
        if (v->start < end && v->end > start)
            return 0;
    return 1;
}

/* Room for len bytes below everything mmap has placed so far.  A hinted or
 * fixed mapping may sit in the way, so step under it. */
static u64 top_alloc(struct mm *m, u64 len)
{
    struct vma *v;
    u64 va = m->mmap_top - len;
    for (;;) {
        for (v = m->vmas; v; v = v->next)
            if (v->start < va + len && v->end > va)
                break;
        if (!v)
            break;
        va = v->start - len;
    }
    m->mmap_top = va;
    return va;
}

i64 sys_mmap(u64 addr, u64 len, u64 prot, u64 flags, i64 fd, u64 off)
{
    struct mm *m = cur->mm;
    struct file *f = NULL;
    u64 va;
    if (!len)
        return -EINVAL;
    len = ALIGNUP(len, PAGE);
    if (!(flags & MAP_ANON)) {
        f = fd_get(fd);
        if (!f || !f->ino)
            return -EBADF;
    }
    if (flags & MAP_FIXED) {
        if (addr & (PAGE - 1))
            return -EINVAL;
        va = addr;
        mm_unmap(m, va, va + len);
    } else if (K1_MMAP_HINTS && addr && !(addr & (PAGE - 1)) && range_free(m, addr, addr + len)) {
        va = addr;              /* a hint, honoured when the range is free (GCC's PCH) */
    } else {
        va = top_alloc(m, len);
    }
    mm_map(m, va, va + len, prot);
    if (f) {                    /* private copy of the file's bytes */
        u64 done = 0;
        while (done < len) {
            u8 buf[512];
            i64 k = inode_read(f->ino, off + done, buf, sizeof buf);
            if (k <= 0)
                break;
            copy_to_mm(m, va + done, buf, k);
            done += k;
        }
    }
    return va;
}

i64 sys_munmap(u64 addr, u64 len)
{
    if (addr & (PAGE - 1))
        return -EINVAL;
    mm_unmap(cur->mm, addr, addr + ALIGNUP(len, PAGE));
    return 0;
}

i64 sys_mprotect(u64 a, u64 len, u64 prot)
{
    struct mm *m = cur->mm;
    struct vma *v;
    u64 va, end, *pte;
    if (a & (PAGE - 1))
        return -EINVAL;
    end = a + ALIGNUP(len, PAGE);
    vma_split(m, a);
    vma_split(m, end);
    for (v = m->vmas; v; v = v->next)
        if (v->start >= a && v->end <= end)
            v->prot = prot & 7;
    for (va = a; va < end; va += PAGE) {
        pte = pte_get(m, va, 0);
        if (pte && (*pte & PTE_P))
            *pte = (*pte & ~(u64)(PTE_W | PTE_U)) | prot_bits(prot & 7);
    }
    mm_switch(m);                       /* flush the TLB */
    return 0;
}

#define MREMAP_MAYMOVE 1
#define MREMAP_FIXED 2
i64 sys_mremap(u64 old, u64 olen, u64 nlen, u64 flags, u64 naddr)
{
    struct mm *m = cur->mm;
    struct vma *v = vma_find(m, old), *w;
    u64 va, i;
    int clash = 0;
    olen = ALIGNUP(olen, PAGE);
    nlen = ALIGNUP(nlen, PAGE);
    if (!v || (old & (PAGE - 1)))
        return -EFAULT;
    if (nlen <= olen) {
        if (nlen < olen)
            mm_unmap(m, old + nlen, old + olen);
        return old;
    }
    if (v->end == old + olen) {         /* grow in place if nothing follows */
        for (w = m->vmas; w; w = w->next)
            if (w->start < old + nlen && w->end > old + olen)
                clash = 1;
        if (!clash) {
            v->end = old + nlen;
            return old;
        }
    }
    if (!(flags & MREMAP_MAYMOVE))
        return -ENOMEM;
    va = top_alloc(m, nlen);
    mm_map(m, va, va + nlen, v->prot);
    for (i = 0; i < olen; i += PAGE) {          /* move the pages, no copy */
        u64 *s = pte_get(m, old + i, 0);
        if (s && (*s & PTE_P)) {
            u64 *d = pte_get(m, va + i, 1);
            *d = *s;
            *s = 0;
        }
    }
    mm_unmap(m, old, old + olen);
    return va;
}

i64 sys_brk(u64 b)
{
    struct mm *m = cur->mm;
    u64 oldend = ALIGNUP(m->brk, PAGE), newend = ALIGNUP(b, PAGE);
    if (b < m->brk0)
        return m->brk;
    if (newend < oldend)
        mm_unmap(m, newend, oldend);
    else if (newend > oldend) {
        if (!range_free(m, oldend, newend))
            return m->brk;              /* a mapping is in the way: malloc falls back to mmap */
        mm_map(m, oldend, newend, 3);
    }
    m->brk = b;
    return b;
}
