/* Fault double checks exact arguments, ABI widths and every kernel errno. */
#include <sys/mman.h>
#include <limits.h>
#include <errno.h>
#include <stdio.h>
void *tested_mmap(void *, size_t, int, int, int, off_t);
int tested_munmap(void *, size_t);
static long answer;
static int calls;
static long arguments[7];
long mapping_fake(long n, long a, long b, long c, long d, long e, long f)
{
    calls++;
    arguments[0] = n; arguments[1] = a; arguments[2] = b;
    arguments[3] = c; arguments[4] = d; arguments[5] = e; arguments[6] = f;
    return answer;
}
#define CHECK(x) do { if (!(x)) { printf("fault failure %d\n", __LINE__); return 1; } } while (0)
int main(void)
{
    int i;
    int before;
    void *pointer;
    unsigned long results[6];
    results[0] = 0; results[1] = 0x100000000UL; results[2] = 0x7fff12345000UL;
    results[3] = 0xffff800012345000UL; results[4] = (unsigned long)-4096;
    results[5] = 0x8000000000000000UL;
    for (i = 1; i <= 4095; i++) {
        answer = -i; errno = 777; before = calls;
        CHECK(tested_mmap(0, 4096, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0) == MAP_FAILED);
        CHECK(errno == i && calls == before + 1);
        errno = 777; before = calls;
        CHECK(tested_munmap((void *)0x12345000UL, 4096) == -1);
        CHECK(errno == i && calls == before + 1);
    }
    for (i = 0; i < 6; i++) {
        answer = (long)results[i]; errno = 777; before = calls;
        pointer = tested_mmap((void *)0xffff800098765432UL,
                    (size_t)0x8000000100000001UL, PROT_READ | PROT_WRITE,
                    MAP_PRIVATE, -2147483647 - 1, (off_t)0x7fffffff00001000L);
        CHECK((unsigned long)pointer == results[i] && errno == 777 && calls == before + 1);
        CHECK(arguments[0] == 9 && (unsigned long)arguments[1] == 0xffff800098765432UL);
        CHECK((unsigned long)arguments[2] == 0x8000000100000001UL);
        CHECK(arguments[3] == 3 && arguments[4] == 2);
        CHECK(arguments[5] == -2147483647L - 1 && arguments[6] == 0x7fffffff00001000L);
    }
    answer = 0; errno = 777; before = calls;
    CHECK(tested_munmap((void *)0xffff800012345000UL, (size_t)0x8000000100000001UL) == 0);
    CHECK(errno == 777 && calls == before + 1 && arguments[0] == 11);
    CHECK((unsigned long)arguments[1] == 0xffff800012345000UL);
    CHECK((unsigned long)arguments[2] == 0x8000000100000001UL);
    CHECK(arguments[3] == 0 && arguments[4] == 0 && arguments[5] == 0 && arguments[6] == 0);
    answer = -4096; errno = 777;
    CHECK(tested_munmap(0, 4096) == -4096 && errno == 777);
    /* Every unsupported flag/protection bit rejects before a syscall. */
    for (i = 0; i < 32; i++) {
        unsigned int bit = 1U << i;
        if (bit != 2 && bit != 32) {
            before = calls; errno = 0;
            CHECK(tested_mmap(0, 4096, 3, (int)(34U | bit), -1, 0) == MAP_FAILED);
            CHECK(errno == EINVAL && calls == before);
        }
        if (bit != 1 && bit != 2) {
            before = calls; errno = 0;
            CHECK(tested_mmap(0, 4096, (int)bit, 34, -1, 0) == MAP_FAILED);
            CHECK(errno == EINVAL && calls == before);
        }
    }
    before = calls;
    CHECK(tested_mmap(0, 4096, 0, 0, -1, 0) == MAP_FAILED && errno == EINVAL);
    CHECK(tested_mmap(0, 4096, 0, 32, -1, 0) == MAP_FAILED && errno == EINVAL);
    CHECK(tested_mmap(0, 4096, 0, 34, -1, -1) == MAP_FAILED && errno == EINVAL);
    CHECK(tested_mmap(0, 4096, 0, 34, -1, LONG_MIN) == MAP_FAILED && errno == EINVAL);
    CHECK(tested_mmap(0, 4096, 0, 34, -1, LONG_MAX) == MAP_FAILED && errno == EINVAL);
    CHECK(tested_mmap(0, 4096, 0, 34, -1, 1) == MAP_FAILED && errno == EINVAL);
    CHECK(calls == before);
    puts("mapping fault contracts passed");
    return 0;
}
