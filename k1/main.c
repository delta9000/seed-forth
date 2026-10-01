/* main.c -- K1 boot: take the machine over from K0, then start init.
 *
 * K0 execs k1 like any program: ring 0, K0's identity-mapped page tables,
 * rsp at the argv block.  k1_main copies argv, builds its own page tables
 * (the low 4 MiB identity-mapped for K1's image, all RAM at KBASE), GDT,
 * TSS, IDT and syscall MSRs, imports K0's RAM file system and runs init. */

#include "k1.h"

/* ---- memory primitives (tcc emits calls to these) ---- */
void *memmove(void *d, const void *s, unsigned long n)
{
    u8 *a = d;
    const u8 *b = s;
    if (a < b || a >= b + n) {
        __asm__ volatile("rep movsb" : "+D"(a), "+S"(b), "+c"(n) :: "memory");
    } else {
        a += n;
        b += n;
        while (n--)
            *--a = *--b;
    }
    return d;
}
void *memset(void *d, int c, unsigned long n)
{
    void *r = d;
    __asm__ volatile("rep stosb" : "+D"(d), "+c"(n) : "a"(c) : "memory");
    return r;
}
void *memcpy(void *d, const void *s, unsigned long n) { return memmove(d, s, n); }
int memcmp(const void *a, const void *b, u64 n)
{
    const u8 *x = a, *y = b;
    for (; n; n--, x++, y++)
        if (*x != *y)
            return *x - *y;
    return 0;
}
u64 strlen(const char *s)
{
    u64 n = 0;
    while (s[n])
        n++;
    return n;
}
int strcmp(const char *a, const char *b)
{
    while (*a && *a == *b)
        a++, b++;
    return (u8)*a - (u8)*b;
}
int strncmp(const char *a, const char *b, u64 n)
{
    for (; n; n--, a++, b++) {
        if (*a != *b)
            return (u8)*a - (u8)*b;
        if (!*a)
            return 0;
    }
    return 0;
}
char *strcpy(char *d, const char *s)
{
    char *r = d;
    while ((*d++ = *s++))
        ;
    return r;
}

/* ---- varargs, as tcc's stdarg.h defines them for x86-64 ---- */
typedef struct {
    unsigned int gp_offset, fp_offset;
    union { unsigned int overflow_offset; char *overflow_arg_area; };
    char *reg_save_area;
} __va_list_struct;
typedef __va_list_struct va_list[1];
void __va_start(__va_list_struct *ap, void *fp);
void *__va_arg(__va_list_struct *ap, int arg_type, int size, int align);
#define va_start(ap, last) __va_start(ap, __builtin_frame_address(0))
#define va_arg(ap, type) \
    (*(type *)(__va_arg(ap, __builtin_va_arg_types(type), sizeof(type), __alignof__(type))))

/* ---- ports, MSRs ---- */
void outb(u16 port, u8 v) { __asm__ volatile("outb %0, %1" :: "a"(v), "d"(port)); }
u8 inb(u16 port)
{
    u8 v;
    __asm__ volatile("inb %1, %0" : "=a"(v) : "d"(port));
    return v;
}
static void outw(u16 port, u16 v) { __asm__ volatile("outw %0, %1" :: "a"(v), "d"(port)); }
void wrmsr(u32 msr, u64 v)
{
    __asm__ volatile("wrmsr" :: "c"(msr), "a"((u32)v), "d"((u32)(v >> 32)));
}
u64 rdmsr(u32 msr)
{
    u32 lo, hi;
    __asm__ volatile("rdmsr" : "=a"(lo), "=d"(hi) : "c"(msr));
    return lo | (u64)hi << 32;
}
static u64 rdtsc(void)
{
    u32 lo, hi;
    __asm__ volatile("rdtsc" : "=a"(lo), "=d"(hi));
    return lo | (u64)hi << 32;
}

/* ---- console: COM1, output only ---- */
void console_write(const char *s, u64 n)
{
    __asm__ volatile("rep outsb" : "+S"(s), "+c"(n) : "d"(0x3F8) : "memory");
}

static void kput(char *buf, u64 *n, char c)
{
    if (*n < 1023)
        buf[(*n)++] = c;
}
static void kputnum(char *buf, u64 *n, u64 v, int base, int neg, int width, char pad)
{
    char t[24];
    int i = 0;
    do {
        t[i++] = "0123456789abcdef"[v % base];
        v /= base;
    } while (v);
    if (neg)
        t[i++] = '-';
    while (i < width)
        t[i++] = pad;
    while (i)
        kput(buf, n, t[--i]);
}
void kprintf(const char *fmt, ...)
{
    char buf[1024];
    u64 n = 0;
    va_list ap;
    va_start(ap, fmt);
    for (; *fmt; fmt++) {
        int lng = 0, width = 0;
        char pad = ' ';
        if (*fmt != '%') {
            kput(buf, &n, *fmt);
            continue;
        }
        fmt++;
        if (*fmt == '0')
            pad = '0';
        while (*fmt >= '0' && *fmt <= '9')
            width = width * 10 + *fmt++ - '0';
        while (*fmt == 'l')
            lng = 1, fmt++;
        switch (*fmt) {
        case 's': {
            const char *s = va_arg(ap, const char *);
            if (!s)
                s = "(null)";
            while (*s)
                kput(buf, &n, *s++);
            break;
        }
        case 'c': kput(buf, &n, (char)va_arg(ap, int)); break;
        case 'd': {
            i64 v = lng ? va_arg(ap, i64) : va_arg(ap, int);
            kputnum(buf, &n, v < 0 ? -v : v, 10, v < 0, width, pad);
            break;
        }
        case 'u': kputnum(buf, &n, lng ? va_arg(ap, u64) : va_arg(ap, u32), 10, 0, width, pad); break;
        case 'x': kputnum(buf, &n, lng ? va_arg(ap, u64) : va_arg(ap, u32), 16, 0, width, pad); break;
        case 'p': kput(buf, &n, '0'); kput(buf, &n, 'x');
                  kputnum(buf, &n, va_arg(ap, u64), 16, 0, 0, ' '); break;
        default: kput(buf, &n, *fmt);
        }
    }
    console_write(buf, n);
}

void qemu_exit(int code)
{
    outb(0xF4, code);           /* isa-debug-exit: qemu exits (code << 1) | 1 */
    for (;;)
        __asm__ volatile("hlt");
}

void panic(const char *msg)
{
    kprintf("\nk1: panic: %s\n", msg);
    qemu_exit(0x7F);
}

/* ---- time: TSC calibrated against the PIT; epoch from the CMOS RTC ---- */
static u64 tsc0, tsc_khz, epoch0;
u64 now_ns(void)
{
    u64 d = rdtsc() - tsc0;
    return d / tsc_khz * 1000000 + d % tsc_khz * 1000000 / tsc_khz;
}
u64 realtime_s(void) { return epoch0 + now_ns() / 1000000000; }

static void tsc_calibrate(void)
{
    /* PIT channel 2, one-shot, 11932 ticks = 10 ms, gate via port 0x61 */
    u64 t0, t1;
    outb(0x61, (inb(0x61) & ~0x02) | 0x01);
    outb(0x43, 0xB0);
    outb(0x42, 11932 & 0xFF);
    outb(0x42, 11932 >> 8);
    t0 = rdtsc();
    while (!(inb(0x61) & 0x20))
        ;
    t1 = rdtsc();
    tsc_khz = (t1 - t0) / 10;
    if (!tsc_khz)
        tsc_khz = 1;
    tsc0 = rdtsc();
}

static u8 cmos(int r)
{
    outb(0x70, r);
    return inb(0x71);
}
static int bcd(int v) { return (v & 15) + (v >> 4) * 10; }
static void rtc_read(void)
{
    int s, mi, h, d, mo, y, b, days;
    static const int cum[12] = {0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334};
    while (cmos(0x0A) & 0x80)
        ;
    s = cmos(0), mi = cmos(2), h = cmos(4), d = cmos(7), mo = cmos(8), y = cmos(9);
    b = cmos(0x0B);
    if (!(b & 4))
        s = bcd(s), mi = bcd(mi), h = bcd(h), d = bcd(d), mo = bcd(mo), y = bcd(y);
    y += 2000;
    days = (y - 1970) * 365 + (y - 1969) / 4 + cum[mo - 1] + d - 1;
    if (mo > 2 && y % 4 == 0)
        days++;
    epoch0 = (u64)days * 86400 + h * 3600 + mi * 60 + s;
}

/* ---- QEMU fw_cfg: the e820 memory map ---- */
struct e820 { u64 addr, len; u32 type; } __attribute__((packed));
struct e820 e820_map[32];
int e820_n;

static void fwcfg_sel(u16 k) { outw(0x510, k); }
static void fwcfg_read(void *buf, u64 n)
{
    u8 *b = buf;
    while (n--)
        *b++ = inb(0x511);
}
static u32 be32(u32 v) { return v >> 24 | (v >> 8 & 0xFF00) | (v << 8 & 0xFF0000) | v << 24; }
static void e820_read(void)
{
    u32 count, i;
    fwcfg_sel(0x19);
    fwcfg_read(&count, 4);
    count = be32(count);
    for (i = 0; i < count; i++) {
        struct { u32 size; u16 sel, res; char name[56]; } f;
        fwcfg_read(&f, 64);
        if (!strcmp(f.name, "etc/e820")) {
            u32 sz = be32(f.size);
            fwcfg_sel((u16)(f.sel >> 8 | f.sel << 8));
            e820_n = sz / 20;
            if (e820_n > 32)
                e820_n = 32;
            fwcfg_read(e820_map, e820_n * 20);
            return;
        }
    }
    panic("no etc/e820 in fw_cfg");
}

/* ---- descriptor tables ---- */
static u64 gdt[9];
static u8 tss[104];
static u64 idt[96];             /* 48 gates x 16 bytes: exceptions, then IRQs */
u64 cur_kstack_top;
u64 user_rsp_tmp;
extern u64 isr_table[32];
void syscall_entry(void);

void set_rsp0(u64 v) { *(u64 *)(tss + 4) = v; }

static void tables_init(void)
{
    struct { u16 lim; u64 base; } __attribute__((packed)) d;
    u64 t = (u64)tss;
    int i;
    gdt[0] = 0;
    gdt[1] = 0x00CF9A000000FFFFUL;      /* 0x08 kernel code 32 (unused) */
    gdt[2] = 0x00209A0000000000UL;      /* 0x10 kernel code 64 */
    gdt[3] = 0x0000920000000000UL;      /* 0x18 kernel data */
    gdt[4] = 0x00CFFA000000FFFFUL;      /* 0x20 user code 32 (unused) */
    gdt[5] = 0x0000F20000000000UL;      /* 0x28 user data */
    gdt[6] = 0x0020FA0000000000UL;      /* 0x30 user code 64 */
    gdt[7] = 103 | (t & 0xFFFFFF) << 16 | 0x89UL << 40 | (t >> 24 & 0xFF) << 56;
    gdt[8] = t >> 32;                   /* 0x38: 64-bit TSS */
    d.lim = sizeof gdt - 1;
    d.base = (u64)gdt;
    __asm__ volatile("lgdt %0" :: "m"(d));
    /* reload CS with a far return, then the data segments */
    __asm__ volatile(
        "pushq $0x10\n"
        "leaq 1f(%%rip), %%rax\n"
        "pushq %%rax\n"
        ".byte 0x48, 0xcb\n"            /* lretq */
        "1:\n"
        "movw $0x18, %%ax\n"
        "movw %%ax, %%ds\n"
        "movw %%ax, %%es\n"
        "movw %%ax, %%ss\n"
        "movw $0, %%ax\n"
        "movw %%ax, %%fs\n"
        "movw %%ax, %%gs\n" ::: "rax", "memory");
    __asm__ volatile("ltr %w0" :: "r"(0x38));
    for (i = 0; i < 48; i++) {
        u64 h = isr_table[i];
        idt[2 * i] = (h & 0xFFFF) | 0x10UL << 16 | 0x8EUL << 40 | (h >> 16 & 0xFFFF) << 48;
        idt[2 * i + 1] = h >> 32;
    }
    d.lim = sizeof idt - 1;
    d.base = (u64)idt;
    __asm__ volatile("lidt %0" :: "m"(d));
    /* SYSCALL: CS 0x10/SS 0x18 in; SYSRET: CS 0x33/SS 0x2B out */
    wrmsr(0xC0000080, rdmsr(0xC0000080) | 1);  /* EFER.SCE */
    wrmsr(0xC0000081, 0x10UL << 32 | 0x23UL << 48);  /* base 0x23: RPL 3 in SS too */
    wrmsr(0xC0000082, (u64)syscall_entry);
    wrmsr(0xC0000084, 0x47700);                 /* clear TF DF IF IOPL AC NT */
    /* mask both 8259 PICs: K1 runs with interrupts off */
    outb(0x21, 0xFF);
    outb(0xA1, 0xFF);
}

/* ---- page tables for the kernel ---- */
static u8 ptmem[5 * 4096];
u64 *kpml4;                     /* every mm copies its upper half and low PD */
u64 *kpd_low;

static void paging_init(void)
{
    u64 base = ALIGNUP((u64)ptmem, 4096), i;
    u64 *pml4 = (u64 *)base, *pdpt_low = pml4 + 512, *pd_low = pml4 + 1024,
        *pdpt_dm = pml4 + 1536;
    memset(pml4, 0, 4 * 4096);
    for (i = 0; i < 512; i++)
        pdpt_dm[i] = i << 30 | 0x83;            /* 1 GiB pages: all RAM at KBASE */
    pd_low[0] = 0x000000 | 0x83;                /* 0-4 MiB: K1's image, kernel only */
    pd_low[1] = 0x200000 | 0x83;
    pdpt_low[0] = (u64)pd_low | 3;
    pml4[0] = (u64)pdpt_low | 3;
    pml4[256] = (u64)pdpt_dm | 3;
    load_cr3((u64)pml4);
    kpml4 = (u64 *)P2V(pml4);
    kpd_low = (u64 *)P2V(pd_low);
}

/* ---- trap handler ---- */
struct trapframe {
    u64 r15, r14, r13, r12, r11, r10, r9, r8, rdi, rsi, rbp, rbx, rdx, rcx, rax;
    u64 vec, err, rip, cs, rflags, rsp, ss;
};
/* A fault in user mode: run the program's handler for sig if it has one
 * and has not blocked it (on its sigaltstack if it asked), else kill it.
 * gnulib's stack-overflow probe and c-stack depend on this.  The handler
 * sees the fault address in si_addr. */
static void user_fault(struct trapframe *f, int sig, u64 addr)
{
    struct tframe t;
    if (cur->sa[sig].handler <= 1 || (cur->sigmask & (1UL << (sig - 1))))
        do_exit(sig);
    t.r15 = f->r15; t.r14 = f->r14; t.r13 = f->r13; t.r12 = f->r12;
    t.rbp = f->rbp; t.rbx = f->rbx; t.r9 = f->r9; t.r8 = f->r8; t.r10 = f->r10;
    t.rdx = f->rdx; t.rsi = f->rsi; t.rdi = f->rdi; t.rax = f->rax;
    t.rip = f->rip; t.rflags = f->rflags; t.rsp = f->rsp;
    cur->sigpend = (cur->sigpend & ~(1UL << (sig - 1))) | (1UL << (sig - 1));
    async_rcx = f->rcx;
    async_r11 = f->r11;
    async_full = 1;
    deliver_signals(&t);
    async_full = 0;
    if (t.rip == f->rip)                         /* not delivered */
        do_exit(sig);
    ((u32 *)t.rsi)[2] = sig == 11 ? 1 : 0;       /* si_code: SEGV_MAPERR */
    ((u64 *)t.rsi)[2] = addr;                    /* si_addr */
    f->r15 = t.r15; f->r14 = t.r14; f->r13 = t.r13; f->r12 = t.r12;
    f->rbp = t.rbp; f->rbx = t.rbx; f->r9 = t.r9; f->r8 = t.r8; f->r10 = t.r10;
    f->rdx = t.rdx; f->rsi = t.rsi; f->rdi = t.rdi; f->rax = t.rax;
    f->rip = t.rip; f->rflags = t.rflags; f->rsp = t.rsp;
}

/* The PIT at 100 Hz on IRQ 0, through the 8259 PIC remapped to vectors
 * 32-47 with every other line masked.  Interrupts are on only in user
 * mode (programs run with IF set; syscalls and gates clear it), so the
 * tick never interrupts the kernel. */
void timer_init(void)
{
    u32 div = 1193182 / 100;
    outb(0x20, 0x11); outb(0xA0, 0x11);         /* ICW1: init, ICW4 follows */
    outb(0x21, 32);   outb(0xA1, 40);           /* ICW2: vector bases */
    outb(0x21, 4);    outb(0xA1, 2);            /* ICW3: cascade on IRQ 2 */
    outb(0x21, 1);    outb(0xA1, 1);            /* ICW4: 8086 mode */
    outb(0x21, 0xFE); outb(0xA1, 0xFF);         /* only IRQ 0 */
    outb(0x43, 0x34);                           /* channel 0, rate generator */
    outb(0x40, div & 0xFF);
    outb(0x40, div >> 8);
}

/* A tick that interrupted user code: fire due alarms, run a pending
 * signal's handler (or its default action), and let another runnable
 * process have the CPU.  A program spinning without system calls -- gnulib's
 * "strcasestr works in linear time" probe under alarm(5) -- is stopped by
 * its SIGALRM here, as on Linux. */
static void user_tick(struct trapframe *f)
{
    struct tframe t;
    check_timers();
    if (signal_pending()) {
        async_rcx = f->rcx;
        async_r11 = f->r11;
        async_full = 1;
        t.r15 = f->r15; t.r14 = f->r14; t.r13 = f->r13; t.r12 = f->r12;
        t.rbp = f->rbp; t.rbx = f->rbx; t.r9 = f->r9; t.r8 = f->r8; t.r10 = f->r10;
        t.rdx = f->rdx; t.rsi = f->rsi; t.rdi = f->rdi; t.rax = f->rax;
        t.rip = f->rip; t.rflags = f->rflags; t.rsp = f->rsp;
        deliver_signals(&t);
        async_full = 0;
        f->r15 = t.r15; f->r14 = t.r14; f->r13 = t.r13; f->r12 = t.r12;
        f->rbp = t.rbp; f->rbx = t.rbx; f->r9 = t.r9; f->r8 = t.r8; f->r10 = t.r10;
        f->rdx = t.rdx; f->rsi = t.rsi; f->rdi = t.rdi; f->rax = t.rax;
        f->rip = t.rip; f->rflags = t.rflags; f->rsp = t.rsp;
    }
    yield();
}

void trap_c(struct trapframe *f)
{
    if (f->vec >= 32) {                         /* an IRQ */
        if (f->vec >= 40)
            outb(0xA0, 0x20);
        outb(0x20, 0x20);                       /* EOI */
        if (f->vec == 32 && (f->cs & 3) == 3)
            user_tick(f);
        return;
    }
    if (f->vec == 14) {
        u64 va = read_cr2();
        if (cur && cur->mm && va < 0x800000000000UL && mm_fault(cur->mm, va, (f->err & 2) != 0) == 0)
            return;
        if ((f->cs & 3) == 3) {
            if (cur->sa[11].handler <= 1)
                kprintf("k1: pid %d (%s): segfault at %lx rip %lx\n  cmdline: %s\n", cur->pid, cur->comm, va, f->rip, cur->cmdline);
            user_fault(f, 11, va);
            return;
        }
        if (cur && va < 0x800000000000UL) {
            kprintf("k1: pid %d (%s): segfault at %lx rip %lx (kernel mode, syscall %ld a=%lx b=%lx c=%lx)\n",
                    cur->pid, cur->comm, va, f->rip, cur->orig_rax,
                    cur->tf ? cur->tf->rdi : 0, cur->tf ? cur->tf->rsi : 0, cur->tf ? cur->tf->rdx : 0);
            do_exit(11);        /* a bad user pointer passed to a syscall */
        }
        kprintf("k1: kernel page fault at %lx rip %lx err %lx\n", va, f->rip, f->err);
        panic("page fault");
    }
    if ((f->cs & 3) == 3) {
        int sig = f->vec == 0 ? 8 : f->vec == 6 ? 4 : f->vec == 3 ? 5 : f->vec == 16 || f->vec == 19 ? 8 : 11;
        if (cur->sa[sig].handler <= 1)
            kprintf("k1: pid %d (%s): trap %ld at rip %lx err %lx\n", cur->pid, cur->comm, f->vec, f->rip, f->err);
        user_fault(f, sig, f->rip);
        return;
    }
    kprintf("k1: kernel trap %ld rip %lx err %lx cs %lx ss %lx rsp %lx\n", f->vec, f->rip, f->err, f->cs, f->ss, f->rsp);
    {
        int i;
        u64 *fr = (u64 *)f->rsp;
        u64 *bp = (u64 *)f->rbp;
        (void)fr;
        kprintf("  rdi %lx rsi %lx rcx %lx syscall %ld pid %d\n", f->rdi, f->rsi, f->rcx,
                cur ? cur->orig_rax : -1, cur ? cur->pid : 0);
        for (i = 0; i < 12 && (u64)bp > 0x200000; i++) {
            kprintf("  bt %lx\n", bp[1]);
            bp = (u64 *)bp[0];
        }
    }
    panic("trap");
}

/* ---- entry ---- */
u8 boot_stack[65536];
u8 fx_default[512] __attribute__((aligned(16)));
static char argbuf[4096];
static char *args[64];

void k1_main(u64 *k0sp)
{
    int argc = (int)k0sp[0], i, n = 0;
    char *in = NULL;
    u8 fxtmp[512 + 16];
    u8 *fx = (u8 *)ALIGNUP((u64)fxtmp, 16);
    u64 p = 0;
    for (i = 0; i < argc && i < 63; i++) {
        char *s = (char *)k0sp[1 + i];
        u64 l = strlen(s) + 1;
        if (p + l > sizeof argbuf)
            break;
        memcpy(argbuf + p, s, l);
        args[n++] = argbuf + p;
        p += l;
    }
    kprintf("k1: starting\n");
    e820_read();
    paging_init();
    tables_init();
    timer_init();
    tsc_calibrate();
    rtc_read();
    __asm__ volatile("fninit");
    fx_save(fx);
    *(u32 *)(fx + 24) = 0x1F80;         /* MXCSR default */
    memcpy(fx_default, fx, 512);
    phys_init();
    fs_init();
    ata_init();
    /* With a starting tree on hda, it is / and K0's files (which built
     * this K1) move to /k0; without one, K0's files are /. */
    fs_import_k0(disk_import() ? "k0/" : "");
    kprintf("k1: %lu MiB RAM, TSC %lu kHz\n", mem_total >> 20, tsc_khz);
    /* arguments: /k1.args, one per line: [-i stdin] prog args... */
    {
        struct inode *ip;
        static char abuf[4096];
        i64 len;
        char *q;
        n = 0;
        if (namei(root, "/k1.args", 1, &ip) == 0) {
            len = inode_read(ip, 0, abuf, sizeof abuf - 1);
            abuf[len < 0 ? 0 : len] = 0;
            for (q = abuf; *q && n < 63;) {
                args[n++] = q;
                while (*q && *q != '\n')
                    q++;
                if (*q)
                    *q++ = 0;
            }
        }
    }
    i = 0;
    if (i < n && !strcmp(args[i], "-v")) {
        extern int k1_verbose;
        k1_verbose = 1;
        i++;
    }
    if (i + 1 < n && !strcmp(args[i], "-i")) {
        in = args[i + 1];
        i += 2;
    }
    if (i >= n)
        panic("usage: /k1.args holds [-v] [-i stdin] prog args...");
    init_start(n - i, args + i, in);
}

void abort(void) { panic("abort"); }
