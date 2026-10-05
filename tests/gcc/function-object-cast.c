/* Explicit function/object pointer casts on LP64 System V keep all 64 bits.
   Strict C90 leaves them undefined; POSIX dlsym and GCC define them. The
   threaded interpreter mirrors binutils 2.30 bfd/doc/chew.c, which stores a
   dictionary pointer in a stinst_type (void (*)()) slot and casts it back. */
#include <stdio.h>
#include <string.h>

struct record { int value; const char *name; };
typedef int (*unary)(int);
typedef void (*stinst_type)();

static int add_one(int x) { return x + 1; }
static int twice(int x) { return x * 2; }
static struct record target = { 42, "target" };
static int counter;

/* Static initializers use the same pure cast policy as runtime casts. */
static void *static_void = (void *) add_one;
static char *static_char = (char *) twice;
static struct record *static_record = (struct record *) add_one;
static unary *static_slot = (unary *) twice;
static stinst_type static_object = (stinst_type) &target;
static int (*static_null)() = (int (*)()) (void *) 0;
static stinst_type static_table[2] = { (stinst_type) &target, (stinst_type) add_one };
static long *static_offset = &((long *) add_one)[1];

/* A miniature chew.c: pc walks an array of stinst_type words. */
typedef struct dict_struct {
  const char *word;
  stinst_type *code;
} dict_type;
static stinst_type *pc;
static long stack[16];
static int sp;

static void push_number(void) { pc++; stack[sp++] = (long) pc[0]; pc++; }
static void add_top(void) { sp--; stack[sp - 1] += stack[sp]; pc++; }
static void call_word(void) {
  dict_type *e = (dict_type *) (pc[1]);
  stinst_type *oldpc = pc;
  pc = e->code;
  while (*pc)
    (*pc)();
  pc = oldpc + 2;
}
static void increment(void) { counter++; pc++; }

static stinst_type inner_code[] = {
  (stinst_type) increment, (stinst_type) push_number, (stinst_type) 7L,
  (stinst_type) add_top, (stinst_type) 0
};
static dict_type inner = { "inner", inner_code };
static stinst_type outer_code[] = {
  (stinst_type) push_number, (stinst_type) 30L,
  (stinst_type) push_number, (stinst_type) 5L,
  (stinst_type) call_word, (stinst_type) &inner,
  (stinst_type) call_word, (stinst_type) &inner,
  (stinst_type) 0
};

int main(void) {
  void *v = (void *) add_one;
  char *c = (char *) twice;
  struct record *r = (struct record *) add_one;
  unary *slot = (unary *) twice;
  int (**raw)() = (int (**)()) add_one;
  stinst_type s = (stinst_type) &target;
  void *back;
  int failures = 0;

  printf("runtime %d %d %d %d %d\n", ((unary) v)(10), ((unary) c)(10),
         ((int (*)(int)) r)(20), ((unary) slot)(21), ((int (*)(int)) raw)(1));
  printf("static %d %d %d %d\n", ((unary) static_void)(1), ((unary) static_char)(4),
         ((unary) static_record)(5), ((unary) static_slot)(6));
  printf("identity %d %d %d %d\n", (void *) add_one == v, (unary) v == add_one,
         (unary) r == add_one, (char *) twice == c);
  back = (void *) s;
  printf("object %d %d %s %d\n", back == (void *) &target, ((struct record *) s)->value,
         ((struct record *) static_object)->name, (struct record *) static_table[0] == &target);
  printf("table %d null %d\n", ((unary) static_table[1])(99), static_null == 0);
  printf("width %d %d offset %ld\n", (int) sizeof(void *), (int) sizeof(stinst_type),
         (long) ((char *) static_offset - (char *) add_one));
  if ((unsigned long) (void *) add_one != (unsigned long) add_one) failures++;
  if ((unsigned long) (stinst_type) &target != (unsigned long) &target) failures++;

  pc = outer_code;
  while (*pc)
    (*pc)();
  printf("interpreter %ld %ld %ld depth %d counter %d %s\n", stack[0], stack[1],
         stack[0] + stack[1], sp, counter, ((dict_type *) outer_code[5])->word);
  if (sp != 2 || stack[1] != 19 || counter != 2) failures++;
  if (strcmp(((dict_type *) (outer_code[7]))->word, "inner") != 0) failures++;
  printf("failures %d\n", failures);
  return failures;
}
