/* C90 grouped stars carry object indirection independently of signatures. */
struct nested_box { int (**slot[2])(int); };
typedef int (*nested_callback)(int);
int nested_apply(void *data, int x) {
  int (*callback)(int) = *(int (**)(int))data;
  return (*callback)(x);
}
int nested_deep(void *data, int x) {
  int (***p)(int) = (int (***)(int))data;
  return (**p)(x);
}
void nested_store(void *data, int (*replacement)(int)) {
  *(int (**)(int))data = replacement;
}
int nested_index(void *data, int x) {
  int (**p)(int) = (int (**)(int))data;
  return p[1](x) + ((int (**)(int))data)[0](x);
}
int nested_member(struct nested_box *box, int x) {
  return (*box->slot[1])(x);
}
int nested_alias(nested_callback *p, int x) {
  int (**q)(int) = p;
  nested_callback *r = q;
  return (*r)(x);
}
int *nested_object_return(void *data, int *x) {
  return (*(int *(**)(int *))data)(x);
}
int nested_callback_argument(void *data, int cb(int), int x) {
  return (*(int (**)(int (*)(int), int))data)(cb, x);
}
double nested_float(void *data, double x, float y, int z) {
  return (*(double (**)(double, float, int))data)(x, y, z);
}
unsigned char nested_narrow(void *data, unsigned char a, long b, int c,
                           int d, int e, int f, int g, int h) {
  return (*(unsigned char (**)(unsigned char, long, int, int, int, int, int, int))data)
    (a, b, c, d, e, f, g, h);
}
int nested_qualified(void *data, int x) {
  int (*const *p)(int) = (int (*const *)(int))data;
  return (*p)(x);
}
int nested_null(void) {
  int (**p)(int) = 0;
  int (***q)(int) = (int (***)(int))0;
  return p == 0 && q == 0 && sizeof(int (**)(int)) == 8 &&
    sizeof(int (***)(int)) == 8;
}
int nested_once(void *next(void), int x) {
  return (*(int (**)(int))next())(x);
}
int nested_returned(void *data, int x) {
  return (*(nested_callback (**)(void))data)()(x);
}
