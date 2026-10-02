#define EXPANDED changed
#define STR(x) #x
#define CAT(a,b) a ## b
#define WRAP(a,b) CAT(a,b)
#define ElfW(type) Elf##64##_##type
#define DEF_ASM(x) DEF(TOK_ASM_ ## x, #x)
#define DEF(a,b) a, b
STR(EXPANDED)
STR( a   + /* comment */ b )
STR("x\\y")
CAT(EXPANDED,x)
WRAP(EXPANDED,x)
ElfW(Sym)
DEF_ASM(mov)
#define ALIAS DEF_ASM
ALIAS(add)
#define INFO(x,y) ((x)+(y))
#define MAKE(x) x##FO
MAKE(IN)(1,2)
#define GET(x) x##FO
GET(IN)(1, GET(IN)(2,3))
#define M(a,b) a
STR(M(1,2,3))
#define RAW_AND_EXPAND(x) #x, x
RAW_AND_EXPAND(EXPANDED)
#define EQ(a,b) a ## b
EQ(,empty)
EQ(empty,)
