#include <assert.h>
static int enabled(void)
{
    int calls = 0;
    int *pointer = &calls;
    assert(++calls == 1);
    assert(pointer);
    return calls;
}
#define NDEBUG
#include <assert.h>
static int disabled(void)
{
    int calls = 0;
    assert(++calls == 1);
    assert(undefined_symbol_must_not_be_evaluated);
    return calls;
}
#undef NDEBUG
#include <assert.h>
int main(int argc, char **argv)
{
    if (enabled() != 1 || disabled() != 0) return 5;
    if (argc > 1) assert(argv == 0);
    return 0;
}
