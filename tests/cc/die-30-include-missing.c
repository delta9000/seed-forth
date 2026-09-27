/* Error 30: an #include "..." file opens neither as given nor under tests/cc/. */
#include "no-such-header.h"
int main() { return 0; }
