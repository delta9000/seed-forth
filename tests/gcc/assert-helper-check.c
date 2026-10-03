#include <assert.h>
int main(void)
{
    __assert_fail("helper test", "owned-fixture.c", 73, "test_function");
    return 8;
}
