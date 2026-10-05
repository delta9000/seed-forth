/* Freestanding: no C library exists yet on this route, so talk to Linux directly. */
static long sys3(long n, long a, long b, long c)
{
    long r;
    __asm__ volatile ("syscall" : "=a"(r) : "a"(n), "D"(a), "S"(b), "d"(c) : "rcx", "r11", "memory");
    return r;
}

static int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }

void _start(void)
{
    static const char msg[] = "hello from a GCC built by Forth\n";
    char digits[16];
    int i = 15, v = fib(20);
    sys3(1, 1, (long)msg, sizeof msg - 1);
    digits[i--] = '\n';
    do { digits[i--] = (char)('0' + v % 10); v /= 10; } while (v);
    sys3(1, 1, (long)(digits + i + 1), 15 - i);
    sys3(60, 42, 0, 0);
}
