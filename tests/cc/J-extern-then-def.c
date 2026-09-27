/* A global declared extern, used, then defined with an initializer.  The
   declaration used to allocate a slot of its own and the definition a
   second one, so f read the first (0) while the initializer went to the
   second.  Both declarations now name one slot: exit 3. */
extern int g;
int f() { return g; }
int g = 3;
int main() { return f(); }
