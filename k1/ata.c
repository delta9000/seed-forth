/* K1: the two disks on QEMU's primary IDE channel, by programmed I/O.
 *
 * hda (master) holds the starting tree as an archive k1/mkdisk.py writes;
 * K1 imports it as / at boot.  hdb (slave) is scratch the chain writes its
 * results to (tar -cf /dev/hdb ...) for the host to read back.  Both are
 * also /dev/hda and /dev/hdb: byte-addressed files over 512-byte sectors.
 *
 * LBA48 READ/WRITE SECTORS EXT, polling, interrupts off at the device
 * (nIEN).  Archive format (little-endian): "K1DISK1\0", then records
 *   u32 namelen, u32 mode, u64 size, name, data, zero pad to 8 bytes
 * ended by namelen 0.  mode is S_IFDIR or S_IFREG plus permissions. */
#include "k1.h"

#define ATA_DATA 0x1F0
#define ATA_COUNT 0x1F2
#define ATA_LBA0 0x1F3
#define ATA_LBA1 0x1F4
#define ATA_LBA2 0x1F5
#define ATA_DRIVE 0x1F6
#define ATA_CMD 0x1F7                   /* status when read */
#define ATA_CTRL 0x3F6
#define ST_BSY 0x80
#define ST_DRQ 0x08
#define ST_ERR 0x01
#define SECT 512
#define CHUNK 128                       /* sectors per command */

u64 ata_sectors[2];                     /* 0: no drive */

static u16 inw(u16 port)
{
    u16 v;
    __asm__ volatile("inw %1, %0" : "=a"(v) : "d"(port));
    return v;
}

static void outw(u16 port, u16 v)
{
    __asm__ volatile("outw %0, %1" :: "a"(v), "d"(port));
}

static int ata_wait(int drq)
{
    u8 s;
    u64 spins = 0;
    for (;;) {
        s = inb(ATA_CMD);
        if (s == 0xFF)
            return -1;                  /* no device */
        if (!(s & ST_BSY)) {
            if (s & ST_ERR)
                return -1;
            if (!drq || (s & ST_DRQ))
                return 0;
        }
        if (++spins > 100000000UL)
            return -1;
    }
}

static void ata_select(int drive, u64 lba, u32 n)
{
    outb(ATA_DRIVE, 0x40 | (drive << 4));
    outb(ATA_COUNT, (u8)(n >> 8));
    outb(ATA_LBA0, (u8)(lba >> 24));
    outb(ATA_LBA1, (u8)(lba >> 32));
    outb(ATA_LBA2, (u8)(lba >> 40));
    outb(ATA_COUNT, (u8)n);
    outb(ATA_LBA0, (u8)lba);
    outb(ATA_LBA1, (u8)(lba >> 8));
    outb(ATA_LBA2, (u8)(lba >> 16));
}

/* n sectors (1..CHUNK) at lba, to or from buf. */
static int ata_rw(int drive, u64 lba, u32 n, u8 *buf, int write)
{
    u32 i;
    if (ata_wait(0))
        return -EIO;
    ata_select(drive, lba, n);
    outb(ATA_CMD, write ? 0x34 : 0x24);
    for (i = 0; i < n; i++) {
        u8 *p = buf + (u64)i * SECT;
        u64 cnt = SECT / 2;
        if (ata_wait(1))
            return -EIO;
        /* one string instruction per sector: KVM batches it, where a
         * loop of inw/outw costs one exit to QEMU per 2 bytes */
        if (write)
            __asm__ volatile("rep outsw" : "+S"(p), "+c"(cnt) : "d"((u16)ATA_DATA) : "memory");
        else
            __asm__ volatile("rep insw" : "+D"(p), "+c"(cnt) : "d"((u16)ATA_DATA) : "memory");
    }
    if (write) {
        if (ata_wait(0))
            return -EIO;
        outb(ATA_CMD, 0xEA);            /* FLUSH CACHE EXT */
        if (ata_wait(0))
            return -EIO;
    }
    return 0;
}

void ata_init(void)
{
    static u16 id[256];
    int d, w;
    outb(ATA_CTRL, 0x02);               /* nIEN: no interrupts */
    for (d = 0; d < 2; d++) {
        outb(ATA_DRIVE, 0xA0 | (d << 4));
        if (inb(ATA_CMD) == 0 || inb(ATA_CMD) == 0xFF)
            continue;
        outb(ATA_CMD, 0xEC);            /* IDENTIFY DEVICE */
        if (inb(ATA_CMD) == 0 || ata_wait(1))
            continue;
        for (w = 0; w < 256; w++)
            id[w] = inw(ATA_DATA);
        ata_sectors[d] = (u64)id[100] | (u64)id[101] << 16 | (u64)id[102] << 32 | (u64)id[103] << 48;
        if (ata_sectors[d])
            kprintf("k1: hd%c: %lu MiB\n", 'a' + d, ata_sectors[d] >> 11);
    }
}

/* /dev/hda, /dev/hdb: bytes at off, through a sector bounce buffer. */
i64 ata_dev_rw(int drive, u64 off, void *buf, u64 n, int write)
{
    static u8 bounce[CHUNK * SECT];
    u8 *b = buf;
    u64 done = 0, size = ata_sectors[drive] * SECT;
    if (!ata_sectors[drive])
        return -EIO;
    if (off >= size)
        return write ? -ENOSPC : 0;
    if (n > size - off)
        n = size - off;
    while (done < n) {
        u64 pos = off + done, lba = pos / SECT, skip = pos % SECT;
        u64 k = CHUNK * SECT - skip, secs;
        if (k > n - done)
            k = n - done;
        secs = (skip + k + SECT - 1) / SECT;
        if (write && (skip || k % SECT)) {
            if (ata_rw(drive, lba, secs, bounce, 0))
                return done ? (i64)done : -EIO;
        }
        if (write) {
            memcpy(bounce + skip, b + done, k);
            if (ata_rw(drive, lba, secs, bounce, 1))
                return done ? (i64)done : -EIO;
        } else {
            if (ata_rw(drive, lba, secs, bounce, 0))
                return done ? (i64)done : -EIO;
            memcpy(b + done, bounce + skip, k);
        }
        done += k;
    }
    return n;
}

/* ---- the starting tree: hda's archive into the RAM fs ---- */
static u64 rd_off;

static int rd(void *buf, u64 n)
{
    i64 r = ata_dev_rw(0, rd_off, buf, n, 0);
    if (r != (i64)n)
        return -1;
    rd_off += n;
    return 0;
}

int disk_import(void)
{
    static u8 data[CHUNK * SECT];
    char magic[8], name[4096];
    u32 hdr[4];
    u64 files = 0, bytes = 0;
    if (!ata_sectors[0])
        return 0;
    rd_off = 0;
    if (rd(magic, 8) || memcmp(magic, "K1DISK1", 8))
        return 0;
    for (;;) {
        u32 nlen, mode;
        u64 size, left, at;
        struct inode *ip;
        if (rd(hdr, 16))
            panic("hda: truncated archive");
        nlen = hdr[0];
        mode = hdr[1];
        size = (u64)hdr[2] | (u64)hdr[3] << 32;
        if (!nlen)
            break;
        if (nlen >= sizeof name || rd(name, nlen))
            panic("hda: bad name");
        name[nlen] = 0;
        if (S_ISDIR(mode)) {
            fs_mkdir_p(name, mode & 07777);
        } else {
            ip = fs_create(name, mode);
            if (!ip)
                panic("hda: cannot create file");
            for (left = size, at = 0; left;) {
                u64 k = left < sizeof data ? left : sizeof data;
                if (rd(data, k))
                    panic("hda: truncated data");
                inode_write(ip, at, data, k);
                at += k;
                left -= k;
            }
            files++;
            bytes += size;
        }
        rd_off = ALIGNUP(rd_off, 8);
    }
    kprintf("k1: imported %lu files, %lu MiB from hda\n", files, bytes >> 20);
    return 1;
}
