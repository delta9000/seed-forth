/* Error 44: a function-like macro call whose ')' never comes: the call
   runs off the end of its region (here, a macro body). */
#define ADD(a, b) ((a) + (b))
#define HALF ADD(1,
int main() {
  return HALF 2);
}
