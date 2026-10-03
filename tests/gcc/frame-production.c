#include <seed-frame.h>

static void *capture(void) { return __seed_parent_frame(); }
static void *argument(int n, void *frame) { return n == 17 ? frame : 0; }
static int recurse(int depth, void *parent)
{
    void *own = capture();
    if (__seed_parent_frame() != parent) return 1;
    if ((unsigned long)own >= (unsigned long)parent) return 2;
    if (argument(17, capture()) != own) return 3;
    if (depth && recurse(depth - 1, own)) return 4;
    if (capture() != own) return 5;
    return 0;
}
static int callback(void *(*take)(void), void *parent)
{
    void *own = capture();
    if (take() != own || __seed_parent_frame() != parent) return 1;
    return recurse(12, own);
}
int main(void)
{
    void *own = capture();
    int i;
    if (!own) return 10;
    for (i = 0; i < 20; i = i + 1) {
        if (capture() != own || argument(17, capture()) != own) return 11;
        if (callback(capture, own)) return 12;
    }
    return 0;
}
