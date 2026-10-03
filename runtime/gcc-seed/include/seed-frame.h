#ifndef SEED_GCC_FRAME_H
#define SEED_GCC_FRAME_H
/* Private AMD64 Forth-C ABI, not a general C or host-compiler interface.
   Returns the saved parent RBP of the C function calling this frameless leaf.
   The Forth compiler preserves its RBP chain; temporary RSP changes do not
   affect this result. Do not call from code that omits/repurposes RBP. */
void *__seed_parent_frame(void);
#endif
