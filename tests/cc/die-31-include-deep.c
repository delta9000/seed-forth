/* Error 31: #include nested deeper than the 4 include-pool slots.  This
   file includes itself, so every level opens one more. */
#include "die-31-include-deep.c"
int main() { return 0; }
