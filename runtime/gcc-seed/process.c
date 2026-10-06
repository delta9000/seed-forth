/* Original seed-forth implementation; distributed under ../../LICENSE.
   Process termination: exit handlers, exit, _Exit and abort. See
   PROCESS-POSIX.md. This object references only the syscall bridge. */
#include <stdlib.h>
#include <seed-syscall.h>

/* One handler record; atexit handlers ignore STATUS and ARGUMENT. */
struct seed_exit_handler {
    int kind;
    void (*plain)(void);
    void (*with_status)(int, void *);
    void *argument;
};

/* Handlers run newest first. POSIX requires room for at least 32; the
   runtime has no allocator dependency here, so the table is fixed. */
#define SEED_EXIT_HANDLERS 64
static struct seed_exit_handler seed_exit_handlers[SEED_EXIT_HANDLERS];
static int seed_exit_count;

/* Set by a buffered stdio implementation to flush every stream. */
void (*__seed_exit_flush)(void);

int atexit(void (*handler)(void))
{
    if (handler == 0 || seed_exit_count == SEED_EXIT_HANDLERS) return -1;
    seed_exit_handlers[seed_exit_count].kind = 0;
    seed_exit_handlers[seed_exit_count].plain = handler;
    seed_exit_count++;
    return 0;
}

int on_exit(void (*handler)(int, void *), void *argument)
{
    if (handler == 0 || seed_exit_count == SEED_EXIT_HANDLERS) return -1;
    seed_exit_handlers[seed_exit_count].kind = 1;
    seed_exit_handlers[seed_exit_count].with_status = handler;
    seed_exit_handlers[seed_exit_count].argument = argument;
    seed_exit_count++;
    return 0;
}

void _Exit(int status)
{
    /* Linux closes process descriptors; only the low status byte survives.
       A denied syscall must never turn this into a returning function. */
    for (;;) {
        __seed_syscall6(60, (long)(status & 255), 0, 0, 0, 0, 0);
    }
}

void exit(int status)
{
    struct seed_exit_handler *handler;
    /* Each record is removed before it runs, so a handler that calls exit
       continues with the remaining ones instead of repeating itself. A
       handler registered while exiting runs next. */
    while (seed_exit_count > 0) {
        handler = &seed_exit_handlers[--seed_exit_count];
        if (handler->kind) handler->with_status(status, handler->argument);
        else handler->plain();
    }
    if (__seed_exit_flush) __seed_exit_flush();
    _Exit(status);
}

void abort(void)
{
    unsigned long mask = 32;
    unsigned long action[4];
    long process = __seed_syscall6(39, 0, 0, 0, 0, 0, 0);
    long thread = __seed_syscall6(186, 0, 0, 0, 0, 0, 0);

    /* The first delivery honors an installed handler. It may leave through
       a nonreturning action; otherwise abort must still terminate. */
    __seed_syscall6(14, 1, (long)&mask, 0, 8, 0, 0);
    __seed_syscall6(234, process, thread, 6, 0, 0, 0);

    /* AMD64 kernel sigaction: handler, flags, restorer, eight-byte mask.
       Default disposition needs no restorer. Override SIG_IGN or a handler
       that returned, including one that changed the blocked-signal mask. */
    action[0] = 0;
    action[1] = 0;
    action[2] = 0;
    action[3] = 0;
    __seed_syscall6(13, 6, (long)action, 0, 8, 0, 0);
    __seed_syscall6(14, 1, (long)&mask, 0, 8, 0, 0);
    __seed_syscall6(234, process, thread, 6, 0, 0, 0);

    /* A kernel/filter refusal cannot make abort return. Normal operation
       dies from SIGABRT; only failed signal delivery reaches this fallback,
       which runs no exit handlers. */
    _Exit(134);
}
