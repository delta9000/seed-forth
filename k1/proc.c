/* proc.c -- processes, the scheduler, fork/exec/exit/wait, signals.
 *
 * Scheduling is cooperative: a process runs until it blocks in a syscall
 * (wait4, a pipe, a vfork child) or exits; there are no interrupts.
 * Each process has a 16 KiB kernel stack; syscall_entry builds its user
 * register frame at the top, and swtch saves kernel callee-saved state. */

#include "k1.h"

struct proc *cur, *procs;
int k1_verbose;

int nextpid = 1;
#define KSTACK 32768
#define STACK_TOP 0x7FFFFFFFF000UL
#define STACK_MAX (64UL << 20)

static u8 *fxp(struct proc *p) { return (u8 *)ALIGNUP((u64)p->fx, 16); }

struct proc *proc_new(void)
{
    struct proc *p = kmalloc(sizeof *p);
    p->kstack = kmalloc(KSTACK);
    p->pid = nextpid++;
    p->state = P_RUN;
    p->next = procs;
    procs = p;
    return p;
}

static void switch_to(struct proc *p)
{
    struct proc *old = cur;
    if (p == old)
        return;
    fx_save(fxp(old));
    cur = p;
    cur_kstack_top = (u64)p->kstack + KSTACK;
    set_rsp0(cur_kstack_top);
    if (p->mm)
        mm_switch(p->mm);
    wrmsr(0xC0000100, p->fsbase);
    fx_restore(fxp(p));
    swtch(&old->ksp, p->ksp);
}

/* Deliver SIGALRM for every ITIMER_REAL that is due.  K1 has no timer
 * interrupt: this runs on each system call and each pass of the scheduler,
 * which is enough for programs that wait in the kernel for their alarm. */
void check_timers(void)
{
    struct proc *p;
    u64 now = now_ns();
    for (p = procs; p; p = p->next)
        if (p->alarm_at && p->state != P_ZOMBIE && now >= p->alarm_at) {
            p->alarm_at = p->alarm_every ? now + p->alarm_every : 0;
            send_signal(p, 14);
        }
}

static int timer_pending(void)
{
    struct proc *p;
    for (p = procs; p; p = p->next)
        if (p->alarm_at && p->state != P_ZOMBIE)
            return 1;
    return 0;
}

void schedule(void)
{
    struct proc *p, *start = cur;
    for (;;) {
        check_timers();
        p = cur->next;
        for (;;) {
            if (!p)
                p = procs;
            if (p->state == P_RUN) {
                switch_to(p);
                return;
            }
            if (p == start)
                break;
            p = p->next;
        }
        if (!timer_pending())
            break;
        cpu_pause();                    /* everyone sleeps until an alarm */
    }
    kprintf("k1: deadlock; processes:\n");
    for (p = procs; p; p = p->next)
        kprintf("  pid %d ppid %d state %d chan %p %s\n", p->pid, p->ppid, p->state, p->chan, p->comm);
    panic("no runnable process");
}

void sleep_on(void *chan)
{
    cur->chan = chan;
    cur->state = P_SLEEP;
    schedule();
    cur->chan = NULL;
}

void wakeup(void *chan)
{
    struct proc *p;
    for (p = procs; p; p = p->next)
        if (p->state == P_SLEEP && p->chan == chan)
            p->state = P_RUN;
}

void yield(void) { schedule(); }

/* ---- fork ---- */
#define CLONE_VM 0x100
#define CLONE_VFORK 0x4000
#define CLONE_SETTLS 0x80000
#define CLONE_THREAD 0x10000

static void set_child_frame(struct proc *c, struct tframe *tf)
{
    u64 *sp = (u64 *)((u64)c->kstack + KSTACK);
    struct tframe *ctf = (struct tframe *)sp - 1;
    *ctf = *tf;
    c->tf = ctf;
    sp = (u64 *)ctf;
    *--sp = (u64)ret_user;      /* swtch's ret goes to ret_user */
    sp -= 6;                    /* rbp rbx r12 r13 r14 r15 */
    memset(sp, 0, 48);
    c->ksp = (u64)sp;
}

i64 do_fork(struct tframe *tf, u64 flags, u64 newsp)
{
    struct proc *c;
    int i;
    if (flags & CLONE_THREAD)
        return -EINVAL;
    c = proc_new();
    c->ppid = cur->pid;
    c->pgid = cur->pgid;
    c->sid = cur->sid;
    if (flags & CLONE_VM) {
        c->mm = cur->mm;
        c->mm->refs++;
    } else
        c->mm = mm_copy(cur->mm);
    for (i = 0; i < NFD; i++)
        if ((c->fd[i] = cur->fd[i])) {
            c->fd[i]->refs++;
            c->cloexec[i] = cur->cloexec[i];
        }
    c->cwd = cur->cwd;
    c->cwd->refs++;
    c->umask = cur->umask;
    memcpy(c->sa, cur->sa, sizeof c->sa);
    c->sigmask = cur->sigmask;
    c->fsbase = cur->fsbase;
    memcpy(c->comm, cur->comm, sizeof c->comm);
    memcpy(c->exe, cur->exe, sizeof c->exe);
    fx_save(fxp(cur));
    memcpy(fxp(c), fxp(cur), 512);
    set_child_frame(c, tf);
    c->tf->rax = 0;
    if (newsp)
        c->tf->rsp = newsp;
    if (flags & CLONE_VFORK) {
        int pid = c->pid;
        c->vfork_parent = cur;
        while (c->vfork_parent == cur)
            sleep_on(c);
        return pid;
    }
    return c->pid;
}

static void vfork_release(struct proc *p)
{
    if (p->vfork_parent) {
        p->vfork_parent = NULL;
        wakeup(p);
    }
}

/* ---- exec ---- */
struct ehdr { u8 ident[16]; u16 type, machine; u32 version; u64 entry, phoff, shoff;
              u32 flags; u16 ehsize, phentsize, phnum, shentsize, shnum, shstrndx; };
struct phdr { u32 type, flags; u64 offset, vaddr, paddr, filesz, memsz, align; };

#define MAXARG 4096
static i64 load_elf(struct mm *m, struct inode *ip, u64 *entry, u64 *phdr_va, u64 *phnum)
{
    struct ehdr eh;
    struct phdr ph;
    u64 i, base = 0, hi = 0, lo = ~0UL;
    if (inode_read(ip, 0, &eh, sizeof eh) != sizeof eh || memcmp(eh.ident, "\177ELF\2\1", 6)
        || eh.machine != 62 || (eh.type != 2 && eh.type != 3) || eh.phentsize != sizeof ph)
        return -ENOEXEC;
    if (eh.type == 3)
        base = 0x555555554000UL;        /* static PIE */
    *phdr_va = 0;
    for (i = 0; i < eh.phnum; i++) {
        inode_read(ip, eh.phoff + i * sizeof ph, &ph, sizeof ph);
        if (ph.type == 3)
            return -ENOEXEC;            /* PT_INTERP: no dynamic linking */
        if (ph.type == 6)
            *phdr_va = base + ph.vaddr;
        if (ph.type != 1)
            continue;
        {
            u64 s = ALIGNDN(base + ph.vaddr, PAGE), e = ALIGNUP(base + ph.vaddr + ph.memsz, PAGE);
            u64 done = 0;
            static u8 buf[8192];
            if (s < 0x400000)
                return -ENOEXEC;
            mm_map(m, s, e, 3);
            while (done < ph.filesz) {
                u64 k = ph.filesz - done;
                if (k > sizeof buf)
                    k = sizeof buf;
                i64 got = inode_read(ip, ph.offset + done, buf, k);
                if (got <= 0)
                    break;      /* p_filesz past end of file: Linux maps it, reads zero */
                copy_to_mm(m, base + ph.vaddr + done, buf, got);
                done += got;
            }
            if (ph.offset <= eh.phoff && eh.phoff < ph.offset + ph.filesz && !*phdr_va)
                *phdr_va = base + ph.vaddr + eh.phoff - ph.offset;
            if (e > hi)
                hi = e;
            if (s < lo)
                lo = s;
        }
    }
    if (!hi)
        return -ENOEXEC;
    m->brk0 = m->brk = hi;
    *entry = base + eh.entry;
    *phnum = eh.phnum;
    return 0;
}

static int user_strlen(const char *s, u64 max)
{
    u64 n = 0;
    while (n < max && s[n])
        n++;
    return n < max ? (int)n : -1;
}

/* /proc/self/exe reads back as the program's canonical path: its directory
 * as path_of names it, then its last component (a symlink there is not
 * followed, as Linux would).  Programs that find their files beside their
 * own executable (seed-cc) need it. */
static void set_exe(const char *path)
{
    struct inode *dir;
    char last[256];
    u64 l;
    cur->exe[0] = 0;
    if (nameiparent(cur->cwd, path, &dir, last) || path_of(dir, cur->exe, sizeof cur->exe) <= 0) {
        cur->exe[0] = 0;
        return;
    }
    l = strlen(cur->exe);
    if (l + 1 + strlen(last) + 1 > sizeof cur->exe) {
        cur->exe[0] = 0;
        return;
    }
    if (l > 1)
        cur->exe[l++] = '/';
    strcpy(cur->exe + l, last);
}

static i64 exec_inner(const char *path, char **argv, int argc, char **envp, int envc, int depth)
{
    struct inode *ip;
    struct mm *m, *old;
    u64 entry, phdr_va, phnum, sp, strs, total = 0, i, ptrs;
    char head[256];
    i64 r, n;
    r = namei(cur->cwd, path, 1, &ip);
    if (r)
        return r;
    if (!S_ISREG(ip->mode))
        return -EACCES;
    if (!(ip->mode & 0111))
        return -EACCES;
    n = inode_read(ip, 0, head, sizeof head - 1);
    if (n >= 2 && head[0] == '#' && head[1] == '!') {
        /* #!interp [arg] */
        char *p = head + 2, *interp, *arg = NULL, **nargv;
        int k = 0, j;
        head[n] = 0;
        for (j = 0; j < n; j++)
            if (head[j] == '\n') {
                head[j] = 0;
                break;
            }
        while (*p == ' ' || *p == '\t')
            p++;
        interp = p;
        while (*p && *p != ' ' && *p != '\t')
            p++;
        if (*p) {
            *p++ = 0;
            while (*p == ' ' || *p == '\t')
                p++;
            if (*p) {
                char *e = p + strlen(p);
                while (e > p && (e[-1] == ' ' || e[-1] == '\t' || e[-1] == '\r'))
                    *--e = 0;
                arg = p;
            }
        }
        if (depth > 4 || argc > MAXARG)
            return -ELOOP;
        nargv = kmalloc((argc + 3) * sizeof *nargv);   /* not on the kernel stack */
        nargv[k++] = interp;
        if (arg)
            nargv[k++] = arg;
        nargv[k++] = (char *)path;
        for (j = 1; j < argc; j++)
            nargv[k++] = argv[j];
        r = exec_inner(interp, nargv, k, envp, envc, depth + 1);
        kfree(nargv);
        return r;
    }
    m = mm_new();
    r = load_elf(m, ip, &entry, &phdr_va, &phnum);
    if (r) {
        mm_free(m);
        return r;
    }
    mm_map(m, STACK_TOP - STACK_MAX, STACK_TOP, 3);
    /* strings: argv, envp, the path (AT_EXECFN), 16 random bytes */
    for (i = 0; i < (u64)argc; i++)
        total += strlen(argv[i]) + 1;
    for (i = 0; i < (u64)envc; i++)
        total += strlen(envp[i]) + 1;
    total += strlen(path) + 1 + 16;
    if (total > (2UL << 20)) {
        mm_free(m);
        return -E2BIG;
    }
    strs = ALIGNDN(STACK_TOP - total, 16);
    ptrs = 1 + argc + 1 + envc + 1 + 2 * 16;
    sp = ALIGNDN(strs - ptrs * 8, 16);
    {
        u64 *vec = kmalloc(ptrs * 8), s = strs, k = 0;
        u64 execfn, rnd;
        vec[k++] = argc;
        for (i = 0; i < (u64)argc; i++) {
            u64 l = strlen(argv[i]) + 1;
            copy_to_mm(m, s, argv[i], l);
            vec[k++] = s;
            s += l;
        }
        vec[k++] = 0;
        for (i = 0; i < (u64)envc; i++) {
            u64 l = strlen(envp[i]) + 1;
            copy_to_mm(m, s, envp[i], l);
            vec[k++] = s;
            s += l;
        }
        vec[k++] = 0;
        execfn = s;
        copy_to_mm(m, s, path, strlen(path) + 1);
        s += strlen(path) + 1;
        rnd = s;
        {
            u64 t[2];
            t[0] = now_ns() * 0x9E3779B97F4A7C15UL;
            t[1] = t[0] ^ 0xD1B54A32D192ED03UL;
            copy_to_mm(m, s, t, 16);
        }
#define AUX(a, v) (vec[k++] = (a), vec[k++] = (v))
        AUX(3, phdr_va); AUX(4, 56); AUX(5, phnum); AUX(6, PAGE); AUX(7, 0);
        AUX(8, 0); AUX(9, entry); AUX(11, 0); AUX(12, 0); AUX(13, 0); AUX(14, 0);
        AUX(17, 100); AUX(23, 0); AUX(25, rnd); AUX(31, execfn); AUX(0, 0);
        copy_to_mm(m, sp, vec, k * 8);
        kfree(vec);
    }
    /* point of no return */
    set_exe(path);
    {
        const char *b = path, *q;
        for (q = path; *q; q++)
            if (*q == '/')
                b = q + 1;
        memset(cur->comm, 0, sizeof cur->comm);
        memcpy(cur->comm, b, strlen(b) < 63 ? strlen(b) : 63);
    }
    {
        u64 at = 0, l;
        int j;
        memset(cur->cmdline, 0, sizeof cur->cmdline);
        for (j = 0; j < argc && at < sizeof cur->cmdline - 2; j++) {
            l = strlen(argv[j]);
            if (l > sizeof cur->cmdline - 2 - at)
                l = sizeof cur->cmdline - 2 - at;
            memcpy(cur->cmdline + at, argv[j], l);
            at += l;
            cur->cmdline[at++] = ' ';
        }
    }
    fd_close_all(cur, 1);
    for (i = 1; i < NSIG; i++)
        if (cur->sa[i].handler > 1)
            memset(&cur->sa[i], 0, sizeof cur->sa[i]);
    old = cur->mm;
    cur->mm = m;
    mm_switch(m);
    if (old)
        mm_free(old);
    vfork_release(cur);
    memset(cur->tf, 0, sizeof *cur->tf);
    cur->tf->rip = entry;
    cur->tf->rsp = sp;
    cur->tf->rflags = 0x202;    /* IF: the timer tick reaches user code */
    cur->fsbase = 0;
    wrmsr(0xC0000100, 0);
    memcpy(fxp(cur), fx_default, 512);
    fx_restore(fxp(cur));
    return 0;
}

/* argv and envp live in the caller's memory, which stays mapped until
 * exec_inner switches address spaces; copy them to the kernel first. */
i64 do_execve(const char *upath, char **uargv, char **uenvp)
{
    char **argv, **envp, *path, *buf;
    int argc = 0, envc = 0, i;
    u64 used = 0, cap = 2UL << 20;
    i64 r;
    for (; uargv && uargv[argc]; argc++)
        if (argc >= MAXARG)
            return -E2BIG;
    for (; uenvp && uenvp[envc]; envc++)
        if (envc >= MAXARG)
            return -E2BIG;
    argv = kmalloc((argc + 1) * 8);
    envp = kmalloc((envc + 1) * 8);
    buf = kmalloc(cap);
#define GRAB(dst, src) do { int l_ = user_strlen(src, 131072); \
        if (l_ < 0 || used + l_ + 1 > cap) { r = -E2BIG; goto out; } \
        dst = buf + used; memcpy(dst, src, l_ + 1); used += l_ + 1; } while (0)
    GRAB(path, upath);
    for (i = 0; i < argc; i++)
        GRAB(argv[i], uargv[i]);
    for (i = 0; i < envc; i++)
        GRAB(envp[i], uenvp[i]);
    r = exec_inner(path, argv, argc, envp, envc, 0);
    if (r && k1_verbose)
        kprintf("k1: pid %d: execve %s: error %ld\n", cur->pid, path, r);
out:
    kfree(argv);
    kfree(envp);
    kfree(buf);
    return r;
}

/* ---- exit and wait ---- */
extern u64 *kpml4;
void do_exit(int status)
{
    struct proc *p, *parent = NULL;
    int i;
    if (cur->pid == 1) {
        int code = (status & 0x7F) ? 128 + (status & 0x7F) : (status >> 8) & 0xFF;
        kprintf("k1: init exited with status %d\n", code);
        qemu_exit(code);
    }
    if (status && k1_verbose)
        kprintf("k1: pid %d (%s) exits with status %x\n", cur->pid, cur->comm, status);
    for (i = 0; i < NFD; i++)
        if (cur->fd[i]) {
            file_put(cur->fd[i]);
            cur->fd[i] = NULL;
        }
    if (cur->cwd) {
        cur->cwd->refs--;
        iput(cur->cwd);
        cur->cwd = NULL;
    }
    load_cr3(V2P(kpml4));
    if (cur->mm)
        mm_free(cur->mm);
    cur->mm = NULL;
    vfork_release(cur);
    for (p = procs; p; p = p->next) {
        if (p->ppid == cur->pid) {
            p->ppid = 1;
            if (p->state == P_ZOMBIE)
                wakeup(procs);
        }
        if (p->pid == cur->ppid)
            parent = p;
    }
    cur->state = P_ZOMBIE;
    cur->status = status;
    if (parent) {
        send_signal(parent, 17);        /* SIGCHLD */
        wakeup(parent);
    }
    for (p = procs; p; p = p->next)     /* init reaps orphans */
        if (p->pid == 1 && cur->ppid == 1)
            wakeup(p);
    schedule();
    panic("zombie ran");
}

static void reap(struct proc *z)
{
    struct proc **pp;
    for (pp = &procs; *pp != z; pp = &(*pp)->next)
        ;
    *pp = z->next;
    kfree(z->kstack);
    kfree(z);
}

#define WNOHANG 1
i64 do_wait4(int pid, int *status, int options)
{
    for (;;) {
        struct proc *p;
        int any = 0;
        for (p = procs; p; p = p->next) {
            if (p->ppid != cur->pid || p == cur)
                continue;
            if (pid > 0 && p->pid != pid)
                continue;
            if (pid == 0 && p->pgid != cur->pgid)
                continue;
            if (pid < -1 && p->pgid != -pid)
                continue;
            any = 1;
            if (p->state == P_ZOMBIE) {
                int id = p->pid;
                if (status)
                    *status = p->status;
                reap(p);
                return id;
            }
        }
        if (!any)
            return -ECHILD;
        if (options & WNOHANG)
            return 0;
        if (signal_pending())
            return -ERESTART;
        sleep_on(cur);
    }
}

/* ---- signals ---- */
#define SA_RESTORER 0x04000000
#define SA_RESTART 0x10000000
#define SA_NODEFER 0x40000000
#define SA_RESETHAND 0x80000000UL
#define BIT(s) (1UL << ((s) - 1))

static int ignored_by_default(int sig)
{
    return sig == 17 || sig == 18 || sig == 23 || sig == 28 || (sig >= 19 && sig <= 22);
}

int send_signal(struct proc *p, int sig)
{
    if (sig <= 0 || sig >= NSIG)
        return sig ? -EINVAL : 0;
    if (p->state == P_ZOMBIE)
        return 0;
    if (sig != 9) {
        if (p->sa[sig].handler == 1)
            return 0;
        if (p->sa[sig].handler == 0 && ignored_by_default(sig))
            return 0;
    }
    p->sigpend |= BIT(sig);
    if (p->state == P_SLEEP && ((p->sigpend & ~p->sigmask) || sig == 9))
        p->state = P_RUN;
    return 0;
}

static int next_signal(void)
{
    u64 pend = cur->sigpend & (~cur->sigmask | BIT(9));
    int s;
    for (s = 1; s < NSIG; s++)
        if (pend & BIT(s))
            return s;
    return 0;
}

int signal_pending(void) { return next_signal() != 0; }

/* After an interrupted blocking call: restart it transparently unless a
 * handler without SA_RESTART is about to run. */
int restart_ok(void)
{
    int s = next_signal();
    struct sigact *sa;
    if (!s)
        return 1;
    sa = &cur->sa[s];
    if (sa->handler == 1 || (sa->handler == 0 && ignored_by_default(s)))
        return 1;
    return sa->handler > 1 && (sa->flags & SA_RESTART);
}

struct sigframe {
    u64 retaddr;
    u64 info[16];               /* siginfo_t: si_signo first */
    struct tframe saved;
    u64 mask;
    u64 rcx, r11, full;         /* full: rcx and r11 were live (see async_full) */
};
u64 async_rcx, async_r11;
int async_full;

/* called with a syscall's result already in tf->rax */
void deliver_signals(struct tframe *tf)
{
    int sig = next_signal();
    struct sigact *sa;
    struct sigframe *f;
    u64 sp;
    if (!sig)
        return;
    cur->sigpend &= ~BIT(sig);
    sa = &cur->sa[sig];
    if (sa->handler == 1)
        return;
    if (sa->handler == 0) {
        if (ignored_by_default(sig))
            return;
        do_exit(sig);
    }
    sp = tf->rsp;
    if ((sa->flags & SA_ONSTACK) && cur->ss_size &&
        !(sp > cur->ss_sp && sp <= cur->ss_sp + cur->ss_size))
        sp = cur->ss_sp + cur->ss_size;         /* switch to the alternate stack */
    sp = ALIGNDN(sp - 128 - sizeof *f, 16) - 8;
    f = (struct sigframe *)sp;
    if (mm_fault(cur->mm, sp, 1) || mm_fault(cur->mm, sp + sizeof *f - 1, 1))
        do_exit(11);
    memset(f, 0, sizeof *f);
    f->retaddr = sa->restorer;
    f->info[0] = sig;
    f->saved = *tf;
    f->rcx = async_rcx;
    f->r11 = async_r11;
    f->full = async_full;
    async_full = 0;
    f->mask = cur->suspended ? cur->suspend_mask : cur->sigmask;
    cur->suspended = 0;
    tf->rip = sa->handler;
    tf->rdi = sig;
    tf->rsi = (u64)f->info;
    tf->rdx = (u64)&f->saved;
    tf->rsp = sp;
    tf->rax = 0;
    cur->sigmask |= sa->mask;
    if (!(sa->flags & SA_NODEFER))
        cur->sigmask |= BIT(sig);
    if (sa->flags & SA_RESETHAND)
        sa->handler = 0;
    cur->sigmask &= ~(BIT(9) | BIT(19));
}

i64 sys_rt_sigreturn(struct tframe *tf)
{
    struct sigframe *f = (struct sigframe *)(tf->rsp - 8);
    *tf = f->saved;
    cur->sigmask = f->mask & ~(BIT(9) | BIT(19));
    cur->ret_full = (int)f->full;
    cur->ret_rcx = f->rcx;
    cur->ret_r11 = f->r11;
    return tf->rax;
}

i64 sys_rt_sigaction(int sig, struct sigact *act, struct sigact *old, u64 sz)
{
    if (sig <= 0 || sig >= NSIG || sig == 9 || sig == 19)
        return act ? -EINVAL : 0;
    if (old)
        *old = cur->sa[sig];
    if (act) {
        cur->sa[sig] = *act;
        if (act->handler == 1 || (act->handler == 0 && ignored_by_default(sig)))
            cur->sigpend &= ~BIT(sig);
    }
    return 0;
}

i64 sys_rt_sigprocmask(int how, u64 *set, u64 *old, u64 sz)
{
    if (old)
        *old = cur->sigmask;
    if (set) {
        if (how == 0)
            cur->sigmask |= *set;
        else if (how == 1)
            cur->sigmask &= ~*set;
        else if (how == 2)
            cur->sigmask = *set;
        else
            return -EINVAL;
        cur->sigmask &= ~(BIT(9) | BIT(19));
    }
    return 0;
}

i64 sys_kill(int pid, int sig)
{
    struct proc *p;
    int found = 0;
    for (p = procs; p; p = p->next) {
        if (p->state == P_ZOMBIE)
            continue;
        if (pid > 0 ? p->pid == pid : pid == 0 ? p->pgid == cur->pgid
            : pid == -1 ? (p->pid != 1 && p != cur) : p->pgid == -pid) {
            found = 1;
            send_signal(p, sig);
        }
    }
    return found ? 0 : -ESRCH;
}

/* ---- the first process ---- */
static char *init_env[] = { "PATH=/usr/bin:/bin:/usr/sbin:/sbin", "HOME=/root", "TERM=dumb", NULL };

void init_start(int argc, char **argv, const char *in)
{
    struct proc *p = proc_new();
    struct file *f;
    struct inode *ip, *con;
    i64 r;
    u64 *sp;
    p->pgid = p->sid = p->pid;
    p->umask = 022;
    p->cwd = root;
    root->refs++;
    p->mm = mm_new();
    memcpy(fxp(p), fx_default, 512);
    cur = p;
    cur_kstack_top = (u64)p->kstack + KSTACK;
    set_rsp0(cur_kstack_top);
    namei(root, "/dev/console", 1, &con);
    if (in && namei(root, in, 1, &ip) == 0) {
        f = file_new();
        f->ino = ip;
        ip->refs++;
    } else {
        namei(root, "/dev/null", 1, &ip);
        f = file_new();
        f->ino = ip;
        ip->refs++;
    }
    p->fd[0] = f;
    f = file_new();
    f->ino = con;
    f->flags = O_RDWR;
    con->refs += 2;
    f->refs = 2;
    p->fd[1] = p->fd[2] = f;
    p->tf = (struct tframe *)(cur_kstack_top - sizeof(struct tframe));
    r = do_execve(argv[0], argv, init_env);
    if (r) {
        kprintf("k1: cannot exec %s: %ld\n", argv[0], r);
        panic("init");
    }
    sp = (u64 *)p->tf;
    enter_user(sp);
}
