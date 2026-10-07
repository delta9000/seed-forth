/* k1.h -- shared declarations for K1.  See README.md for the design. */

typedef unsigned long u64;
typedef long i64;
typedef unsigned int u32;
typedef int i32;
typedef unsigned short u16;
typedef unsigned char u8;

/* The compilers call these for struct copies; they must be declared before use. */
void *memmove(void *d, const void *s, unsigned long n);
void *memset(void *d, int c, unsigned long n);
void *memcpy(void *d, const void *s, unsigned long n);
int memcmp(const void *a, const void *b, u64 n);
u64 strlen(const char *s);
int strcmp(const char *a, const char *b);
int strncmp(const char *a, const char *b, u64 n);
char *strcpy(char *d, const char *s);

#define NULL ((void *)0)
#define PAGE 4096UL
#define KBASE 0xFFFF800000000000UL /* direct map of physical memory */
#define P2V(p) ((void *)((u64)(p) + KBASE))
#define V2P(v) ((u64)(v) - KBASE)
#define ALIGNUP(x, a) (((x) + (a) - 1) & ~((a) - 1))
#define ALIGNDN(x, a) ((x) & ~((a) - 1))

/* errno */
#define EPERM 1
#define ENOENT 2
#define ESRCH 3
#define EINTR 4
#define EIO 5
#define ENXIO 6
#define E2BIG 7
#define ENOEXEC 8
#define EBADF 9
#define ECHILD 10
#define EAGAIN 11
#define ENOMEM 12
#define EACCES 13
#define EFAULT 14
#define EBUSY 16
#define EEXIST 17
#define EXDEV 18
#define ENOTDIR 20
#define EISDIR 21
#define EINVAL 22
#define EMFILE 24
#define ENOTTY 25
#define EFBIG 27
#define ENOSPC 28
#define ESPIPE 29
#define EROFS 30
#define EMLINK 31
#define EPIPE 32
#define ERANGE 34
#define ENAMETOOLONG 36
#define ENOSYS 38
#define ENOTEMPTY 39
#define ELOOP 40
#define ENODATA 61
#define EOPNOTSUPP 95
#define EAFNOSUPPORT 97
#define ERESTART 512 /* internal: restart the syscall after a handler */

/* inode types (as st_mode high bits) */
#define S_IFMT 0170000
#define S_IFDIR 0040000
#define S_IFCHR 0020000
#define S_IFREG 0100000
#define S_IFLNK 0120000
#define S_IFIFO 0010000
#define S_ISFIFO(m) (((m) & S_IFMT) == S_IFIFO)
#define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
#define S_ISREG(m) (((m) & S_IFMT) == S_IFREG)
#define S_ISLNK(m) (((m) & S_IFMT) == S_IFLNK)
#define S_ISCHR(m) (((m) & S_IFMT) == S_IFCHR)

/* open flags */
#define O_ACCMODE 3
#define O_RDONLY 0
#define O_WRONLY 1
#define O_RDWR 2
#define O_CREAT 0100
#define O_EXCL 0200
#define O_NOCTTY 0400
#define O_TRUNC 01000
#define O_APPEND 02000
#define O_NONBLOCK 04000
#define O_DIRECTORY 0200000
#define O_NOFOLLOW 0400000
#define O_CLOEXEC 02000000
#define O_PATH 010000000
#define AT_FDCWD (-100)
#define AT_SYMLINK_NOFOLLOW 0x100
#define AT_REMOVEDIR 0x200
#define AT_SYMLINK_FOLLOW 0x400
#define AT_EMPTY_PATH 0x1000

struct timespec { i64 sec, nsec; };

struct dent {                   /* a name in a directory */
    struct dent *next;          /* directory order (for getdents) */
    struct dent *hnext;         /* hash chain */
    struct inode *ino;
    u64 seq;                    /* getdents offset: rises in directory order */
    u32 nlen;
    u32 hash;
    char name[1];
};

struct inode {
    u32 mode, nlink;
    u64 ino;
    u64 size;
    i32 refs;                   /* open files and cwds */
    u32 uid, gid;
    struct timespec atime, mtime, ctime;
    int dev;                    /* S_IFCHR: DEV_* */
    void **pages;               /* S_IFREG: 3-level radix of data pages */
    struct dent *dents, *dlast; /* S_IFDIR */
    struct dent **htab;         /* S_IFDIR: hash buckets, once large */
    u32 ndents, hsize;
    u64 dseq;                   /* S_IFDIR: entries added so far */
    struct inode *parent;       /* S_IFDIR */
    char *target;               /* S_IFLNK */
    struct pipe *fifo;          /* S_IFIFO: while it is open */
};
#define DEV_NULL 1
#define DEV_ZERO 2
#define DEV_CONSOLE 3
#define DEV_RANDOM 4
#define DEV_HDA 5
#define DEV_HDB 6

struct pipe {
    u8 *pg[16];                 /* 64 KiB ring */
    u64 r, w;                   /* bytes read / written so far */
    int readers, writers;
};
#define PIPESZ (16 * PAGE)

struct file {
    int refs;
    int flags;
    u64 pos;
    struct inode *ino;
    struct pipe *pipe;          /* pipes: ino == NULL */
    int wend;                   /* pipe: 0 read end, 1 write end, 2 both (O_RDWR FIFO) */
    struct inode *dir;          /* where it was opened: dir and name, for */
    char *name;                 /* readlink("/proc/self/fd/N") (realpath) */
};

struct vma {
    struct vma *next;
    u64 start, end;
    int prot;
};

struct mm {
    u64 *pml4;                  /* virtual (direct map) */
    struct vma *vmas;
    u64 brk0, brk;
    u64 mmap_top;               /* next mmap goes below this */
    int refs;
};

struct tframe {                 /* user registers, as syscall_entry pushes them */
    u64 r15, r14, r13, r12, rbp, rbx, r9, r8, r10, rdx, rsi, rdi, rax;
    u64 rip, rflags, rsp;
};

struct sigact { u64 handler, flags, restorer, mask; };
#define SA_ONSTACK 0x08000000

#define NFD 256
#define NSIG 65
enum { P_FREE, P_RUN, P_SLEEP, P_ZOMBIE };

struct proc {
    struct proc *next;          /* all processes */
    int pid, ppid, pgid, sid;
    int state;
    int status;                 /* wait status once a zombie */
    void *chan;                 /* sleeping on */
    struct mm *mm;
    struct file *fd[NFD];
    u8 cloexec[NFD];
    struct inode *cwd;
    u32 umask;
    struct sigact sa[NSIG];
    u64 sigmask, sigpend;
    u8 *kstack;                 /* 4 pages */
    u64 ksp;                    /* saved by swtch */
    struct tframe *tf;
    u64 fsbase, clear_tid;
    struct proc *vfork_parent;  /* CLONE_VFORK: parent waits for exec/exit */
    i64 orig_rax;
    u64 suspend_mask;           /* rt_sigsuspend: the mask to restore */
    int suspended;
    u64 utime_start;
    u64 alarm_at, alarm_every;  /* ITIMER_REAL, in now_ns() time; 0: off */
    u64 ss_sp, ss_size;         /* sigaltstack; ss_size 0: none */
    int ret_full;               /* rt_sigreturn: back through iretq with ... */
    u64 ret_rcx, ret_r11;       /* ... these, to code a signal interrupted */
    char comm[64];
    char cmdline[2048];         /* argv joined by spaces, for fault reports */
    char exe[1024];             /* /proc/self/exe: the image's canonical path */
    u8 fx[512 + 16];            /* fxsave area (aligned at runtime) */
};

/* main.c */
void kprintf(const char *fmt, ...);
void panic(const char *msg);
u64 now_ns(void);
u64 realtime_s(void);
void qemu_exit(int code);
extern u64 tss_rsp0_slot;
void set_rsp0(u64 v);
extern u64 cur_kstack_top;
struct e820 { u64 addr, len; u32 type; };   /* unpacked from fw_cfg's 20-byte records */

/* mm.c */
void phys_init(void);
u64 palloc(void);               /* physical address of a zeroed page */
void pfree(u64 pa);
void *kmalloc(u64 n);
void kfree(void *p);
struct mm *mm_new(void);
void mm_free(struct mm *m);
struct mm *mm_copy(struct mm *m);
void mm_switch(struct mm *m);
int mm_fault(struct mm *m, u64 va, int write);
u64 *pte_get(struct mm *m, u64 va, int create);
int copy_to_mm(struct mm *m, u64 va, const void *src, u64 n);
int mm_map(struct mm *m, u64 start, u64 end, int prot);
void mm_unmap(struct mm *m, u64 start, u64 end);
struct vma *vma_find(struct mm *m, u64 va);
i64 sys_mmap(u64 addr, u64 len, u64 prot, u64 flags, i64 fd, u64 off);
i64 sys_munmap(u64 addr, u64 len);
i64 sys_mremap(u64 old, u64 olen, u64 nlen, u64 flags, u64 naddr);
i64 sys_brk(u64 b);
i64 sys_mprotect(u64 a, u64 len, u64 prot);
extern u64 mem_total, mem_used;

/* fs.c */
extern struct inode *root;
void fs_init(void);
void fs_import_k0(const char *prefix);
struct inode *fs_mkdir_p(const char *path, u32 mode);
struct inode *fs_create(const char *path, u32 mode);
void ata_init(void);
i64 ata_dev_rw(int drive, u64 off, void *buf, u64 n, int write);
int disk_import(void);
struct inode *inode_new(u32 mode);
void iput(struct inode *ip);
int namei(struct inode *cwd, const char *path, int follow, struct inode **out);
int nameiparent(struct inode *cwd, const char *path, struct inode **dir, char *last);
struct inode *dir_lookup(struct inode *d, const char *name, u32 n);
int dir_add(struct inode *d, const char *name, struct inode *ip);
int dir_remove(struct inode *d, const char *name);
i64 inode_read(struct inode *ip, u64 off, void *buf, u64 n);
i64 inode_write(struct inode *ip, u64 off, const void *buf, u64 n);
void inode_trunc(struct inode *ip, u64 size);
struct file *file_new(void);
void file_put(struct file *f);
i64 file_read(struct file *f, void *buf, u64 n);
i64 file_write(struct file *f, const void *buf, u64 n);
int make_pipe(struct file **r, struct file **w);
void stamp(struct timespec *t);
int path_of(struct inode *d, char *buf, u64 n);

/* proc.c */
extern struct proc *cur, *procs;
extern int nextpid;
void sleep_on(void *chan);
void wakeup(void *chan);
void schedule(void);
void yield(void);
void check_timers(void);
struct proc *proc_new(void);
i64 do_fork(struct tframe *tf, u64 flags, u64 newsp);
i64 do_execve(const char *path, char **argv, char **envp);
void do_exit(int status);
i64 do_wait4(int pid, int *status, int options);
int send_signal(struct proc *p, int sig);
int signal_pending(void);
void deliver_signals(struct tframe *tf);
/* Set around deliver_signals when the signal interrupts arbitrary user code
 * (a timer tick or a fault), where rcx and r11 are live: the frame keeps them. */
extern u64 async_rcx, async_r11;
extern int async_full;
void iret_frame(void *frame);   /* k1.S: never returns */
i64 sys_rt_sigaction(int sig, struct sigact *act, struct sigact *old, u64 sz);
i64 sys_rt_sigprocmask(int how, u64 *set, u64 *old, u64 sz);
i64 sys_rt_sigreturn(struct tframe *tf);
i64 sys_kill(int pid, int sig);
void init_start(int argc, char **argv, const char *stdin_path);
void fx_save(void *p);
void fx_restore(void *p);
extern u8 fx_default[512];

/* sys.c */
void poll_wakeup(void);
int restart_ok(void);
void syscall_c(struct tframe *tf);
i64 sys_open_at(int dfd, const char *path, int flags, u32 mode);
int fd_alloc(struct file *f, int min, int cloexec);
struct file *fd_get(int fd);
void fd_close_all(struct proc *p, int only_cloexec);

/* linux.c */
i64 boot_linux(const char *kernel, const char *initrd, const char *cmdline);

/* asm (k1.S): everything that needs an instruction C cannot express, so
 * the C files have no inline assembly and any C compiler can build them */
void swtch(u64 *old_ksp, u64 new_ksp);
void ret_user(void);
void load_cr3(u64 pa);
u64 read_cr2(void);
void copy_forward(void *d, const void *s, u64 n);     /* rep movsb */
void console_write(const char *s, u64 n);             /* rep outsb to COM1 */
void outb(u16 port, u8 v);
u8 inb(u16 port);
void outw(u16 port, u16 v);
u16 inw(u16 port);
void port_insw(u16 port, void *buf, u64 count);       /* rep insw */
void port_outsw(u16 port, const void *buf, u64 count);
void wrmsr(u32 msr, u64 v);
u64 rdmsr(u32 msr);
u64 rdtsc(void);
void load_gdt(u64 base, u64 limit);     /* then reload CS and the data segments */
void load_idt(u64 base, u64 limit);
void load_tr(u64 selector);
void invlpg(u64 va);
void fpu_init(void);                    /* fninit */
void cpu_halt(void);
void cpu_pause(void);
void enter_user(u64 *sp);               /* rsp = sp, then ret_user */
void linux_jump(u64 pml4, u64 boot_params, u64 entry);
