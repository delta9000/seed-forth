typedef unsigned int u32;
typedef unsigned long u64;
typedef struct T { char a; short b; u32 c; u64 d; } T;
union U { char b[8]; u64 n; };
struct A { int a; union { long v; struct { int x; int y; }; }; int z; };
int main(void) { T t; struct A a; t.a = 5; t.b = -4; t.c = 7; t.d = 9; a.x=11; a.y=23; a.z=31; return t.a + t.b + t.c + t.d + a.x + a.y + a.z - 82; }
