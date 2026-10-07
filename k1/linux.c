/* linux.c -- hand the machine to a Linux bzImage (x86-64 64-bit boot protocol).
 *
 * Load the protected-mode kernel at a 2 MiB-aligned address >= 16 MiB with
 * room for init_size, build boot_params (setup header from the bzImage,
 * e820 from fw_cfg, command line, initrd), switch to page tables that
 * identity-map the first 512 GiB, and jump to the 64-bit entry at
 * load + 0x200 with rsi = &boot_params.  CS 0x10 and DS 0x18 are already
 * the flat 64-bit code and data segments the protocol requires. */

#include "k1.h"

extern u8 e820_raw[];
extern int e820_n;
u64 palloc_contig(u64 bytes, u64 align, u64 min);

static i64 slurp(const char *path, u8 **data, u64 *size, u64 align, u64 min, u64 extra)
{
    struct inode *ip;
    u64 pa;
    int r = namei(root, path, 1, &ip);
    if (r)
        return r;
    *size = ip->size;
    pa = palloc_contig(ip->size + extra, align, min);
    if (!pa)
        return -ENOMEM;
    *data = P2V(pa);
    inode_read(ip, 0, *data, ip->size);
    return 0;
}

i64 boot_linux(const char *kernel, const char *initrd, const char *cmdline)
{
    u8 *img, *bp, *rd = NULL, *cl;
    u64 size, rdsize = 0, setup, pm_off, load, init_size, i, *pml4, *pdpt;
    struct inode *ip;
    i64 r;
    u8 hdr[0x300];
    struct inode *kip;
    int setup_sects;
    if ((r = namei(root, kernel, 1, &kip)))
        return r;
    if (inode_read(kip, 0, hdr, sizeof hdr) != sizeof hdr || memcmp(hdr + 0x202, "HdrS", 4))
        return -ENOEXEC;
    if (*(u16 *)(hdr + 0x206) < 0x20C || !(hdr[0x236] & 1))
        return -ENOEXEC;                /* needs the 64-bit entry (XLF_KERNEL_64) */
    setup_sects = hdr[0x1F1] ? hdr[0x1F1] : 4;
    pm_off = (setup_sects + 1) * 512;
    init_size = *(u32 *)(hdr + 0x260);
    /* the protected-mode kernel, with room to decompress in place */
    size = kip->size - pm_off;
    if (init_size < size)
        init_size = size;
    {
        /* the kernel aligns its load address up to kernel_alignment and
         * runs at no less than pref_address, so honour both */
        u64 align = *(u32 *)(hdr + 0x230), pref = *(u64 *)(hdr + 0x258);
        if (align < (2UL << 20))
            align = 2UL << 20;
        if (pref < (16UL << 20))
            pref = 16UL << 20;
        load = palloc_contig(init_size, align, pref);
    }
    if (!load)
        return -ENOMEM;
    inode_read(kip, pm_off, P2V(load), size);
    if (initrd && namei(root, initrd, 1, &ip) == 0) {
        if ((r = slurp(initrd, &rd, &rdsize, PAGE, 16UL << 20, 0)))
            return r;
    }
    bp = P2V(palloc_contig(PAGE, PAGE, 16UL << 20));
    cl = P2V(palloc_contig(PAGE, PAGE, 16UL << 20));
    memset(bp, 0, PAGE);
    memset(cl, 0, PAGE);
    if (cmdline && namei(root, cmdline, 1, &ip) == 0) {
        i64 n = inode_read(ip, 0, cl, PAGE - 1);
        for (i = 0; i < (u64)n; i++)
            if (cl[i] == '\n')
                cl[i] = ' ';
    }
    /* boot_params: copy the setup header (0x1F1 .. 0x202 + hdr[0x201]) */
    setup = 0x202 + hdr[0x201];
    memcpy(bp + 0x1F1, hdr + 0x1F1, setup - 0x1F1);
    bp[0x210] = 0xFF;                           /* type_of_loader: undefined */
    bp[0x211] |= 0x01;                          /* LOADED_HIGH */
    bp[0x211] &= ~0x20;                         /* QUIET_FLAG off */
    *(u32 *)(bp + 0x228) = (u32)V2P(cl);        /* cmd_line_ptr */
    *(u32 *)(bp + 0x0C8) = (u32)(V2P(cl) >> 32);
    if (rd) {
        *(u32 *)(bp + 0x218) = (u32)V2P(rd);    /* ramdisk_image */
        *(u32 *)(bp + 0x0C0) = (u32)(V2P(rd) >> 32);
        *(u32 *)(bp + 0x21C) = (u32)rdsize;
        *(u32 *)(bp + 0x0C4) = (u32)(rdsize >> 32);
    }
    bp[0x1E8] = e820_n;                         /* e820_entries */
    memcpy(bp + 0x2D0, e820_raw, e820_n * 20);
    /* identity map of the first 512 GiB, plus the direct map so this code
     * keeps its stack until the jump */
    pml4 = P2V(palloc_contig(PAGE, PAGE, 16UL << 20));
    pdpt = P2V(palloc_contig(PAGE, PAGE, 16UL << 20));
    memset(pml4, 0, PAGE);
    for (i = 0; i < 512; i++)
        pdpt[i] = i << 30 | 0x83;
    pml4[0] = V2P(pdpt) | 3;
    extern u64 *kpml4;
    for (i = 256; i < 512; i++)
        pml4[i] = kpml4[i];
    kprintf("k1: booting Linux (protocol %x, load %lx, init_size %lx, initrd %lu bytes)\n",
            *(u16 *)(hdr + 0x206), load, init_size, rdsize);
    linux_jump(V2P(pml4), V2P(bp), load + 0x200);
    return 0;
}
