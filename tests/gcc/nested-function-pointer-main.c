struct nested_box { int (**slot[2])(int); };
typedef int (*nested_callback)(int);
int nested_apply(void *, int);
int nested_deep(void *, int);
void nested_store(void *, int (*)(int));
int nested_index(void *, int);
int nested_member(struct nested_box *, int);
int nested_alias(nested_callback *, int);
int *nested_object_return(void *, int *);
int nested_callback_argument(void *, int (*)(int), int);
double nested_float(void *, double, float, int);
unsigned char nested_narrow(void *, unsigned char, long, int, int, int, int, int, int);
int nested_qualified(void *, int);
int nested_null(void);
int nested_once(void *(*)(void), int);
int nested_returned(void *, int);
static int nested_reads;
static void *nested_location;
static void *next_location(void) { nested_reads++; return nested_location; }
static int plus17(int x) { return x + 17; }
static nested_callback return_plus17(void) { return plus17; }
static int (*global_cb)(int) = plus17;
static int (**global_pp)(int) = &global_cb;
static int (***global_ppp)(int) = &global_pp;
static int (**global_cast)(int) = (int (**)(int))&global_cb;
static int (**global_refs[2])(int) = { &global_cb, &global_cb };
static int twice(int x) { return x * 2; }
static int *object_identity(int *x) { return x; }
static int callback_consumer(int cb(int), int x) { return cb(x) + 3; }
static double float_sum(double x, float y, int z) { return x + y + z; }
static unsigned char narrow_sum(unsigned char a, long b, int c, int d,
                               int e, int f, int g, int h) {
  return a + b + c + d + e + f + g + h;
}
int main(void) {
  int (*cb)(int) = plus17;
  int (**p)(int) = &cb;
  int (***q)(int) = &p;
  int (*callbacks[2])(int);
  int (**objects[2])(int);
  int *(*object_cb)(int *) = object_identity;
  int (*nested_cb)(int (*)(int), int) = callback_consumer;
  double (*float_cb)(double, float, int) = float_sum;
  unsigned char (*narrow_cb)(unsigned char, long, int, int, int, int, int, int) = narrow_sum;
  nested_callback (*selector)(void) = return_plus17;
  struct nested_box box;
  int value = 25;
  callbacks[0] = plus17; callbacks[1] = twice;
  objects[0] = p; objects[1] = &callbacks[1];
  box.slot[0] = objects[0]; box.slot[1] = objects[1];
  if (nested_apply(p, 25) != 42) return 1;
  if (nested_deep(q, 25) != 42) return 2;
  if (nested_index(callbacks, 4) != 29) return 3;
  if (nested_member(&box, 21) != 42) return 4;
  if (nested_alias(p, 25) != 42) return 5;
  if (nested_object_return(&object_cb, &value) != &value) return 6;
  if (nested_callback_argument(&nested_cb, plus17, 22) != 42) return 7;
  if (nested_float(&float_cb, 2.5, 3.25, 4) != 9.75) return 8;
  if (nested_narrow(&narrow_cb, 250, 256, 1, 2, 3, 4, 5, 6) != 15) return 9;
  if (nested_qualified(p, 25) != 42 || !nested_null()) return 10;
  nested_store(p, twice);
  if (cb(21) != 42 || (**q)(21) != 42) return 11;
  *(int (**)(int))p = plus17;
  if (cb(25) != 42) return 12;
  nested_reads = 0; nested_location = p;
  if (nested_once(next_location, 25) != 42 || nested_reads != 1) return 13;
  if (nested_returned(&selector, 25) != 42) return 14;
  if ((**global_ppp)(25) != 42 || (*global_cast)(25) != 42 ||
      (*global_refs[1])(25) != 42) return 15;
  return 0;
}
