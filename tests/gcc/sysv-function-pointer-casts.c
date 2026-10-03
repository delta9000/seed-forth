/* Only restored, matching signatures are called. Different signatures are
   storage representations, as in GCC 4.0.4 libiberty/obstack.c. */
struct _obstack_chunk { long value; };
typedef struct _obstack_chunk *(*chunk_callback)(void *, long);
typedef void (*generic_callback)();
struct callbacks { generic_callback allocate; generic_callback release; };
struct _obstack_chunk *make_chunk(void *context, long n) {
    struct _obstack_chunk *p = context;
    p->value = n;
    return p;
}
void release_chunk(void *context, struct _obstack_chunk *p) {
    long *count = context;
    *count = *count + p->value;
}
chunk_callback choose_chunk(long selector) {
    if (selector == 7) return make_chunk;
    return make_chunk;
}
long narrow_value(signed char a, unsigned short b, long c) {
    return a + b + c;
}
int main(void) {
    struct _obstack_chunk chunk;
    struct _obstack_chunk *p;
    struct callbacks callbacks;
    generic_callback chunkfun;
    generic_callback selector;
    generic_callback narrow;
    chunk_callback restored;
    long released;
    released = 0;
    chunkfun = (void (*)())make_chunk;
    restored = (struct _obstack_chunk * (*)(void *, long)) chunkfun;
    if (restored != make_chunk) return 1;
    if ((generic_callback)restored != chunkfun) return 2;
    p = restored(&chunk, 41);
    if (p != &chunk || p->value != 41) return 3;
    if (((struct _obstack_chunk *(*)(void *, long))chunkfun)(&chunk, 42)->value != 42) return 4;
    if (((chunk_callback)(generic_callback)make_chunk)(&chunk, 43)->value != 43) return 5;
    callbacks.allocate = (generic_callback)make_chunk;
    callbacks.release = (generic_callback)release_chunk;
    p = ((chunk_callback)callbacks.allocate)(&chunk, 44);
    ((void (*)(void *, struct _obstack_chunk *))callbacks.release)(&released, p);
    if (released != 44) return 6;
    selector = (generic_callback)choose_chunk;
    if (((chunk_callback (*)(long))selector)(7)(&chunk, 45)->value != 45) return 7;
    narrow = (generic_callback)narrow_value;
    if (((long (*)(signed char, unsigned short, long))narrow)(255, 65537, 9) != 9) return 8;
    if (((long (* const)(signed char, unsigned short, long))narrow)(254, 65538, 9) != 9) return 9;
    if (sizeof(struct _obstack_chunk *(*)(void *, long)) != sizeof(chunkfun)) return 10;
    (void)chunkfun;
    return 0;
}
