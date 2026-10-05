struct S { int value; }; typedef struct S *rtx;
static void invoke(void *data, rtx x) { void (*callback)(rtx) = *(void (**)(rtx))data; (*callback)(x); }
static void add(rtx x) { x->value += 17; }
int main(void) { struct S s; void (*cb)(rtx)=add; s.value=25; invoke(&cb,&s); return s.value; }
