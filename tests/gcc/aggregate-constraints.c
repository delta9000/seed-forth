struct A { long x; };
struct F { double x; };
struct Big { long x,y,z; };
struct A missing(int, ...);
struct A (*fp)(int, ...);
struct F missing_float(struct F);
struct Big missing_big(int,...);
struct Big (*bigfp)(int,...);
static long count;
static struct A made(struct A a){count++;a.x++;return a;}
static struct Big made_big(struct Big a){count++;a.x++;return a;}
static void discarded(struct A a){return (void)made(a);}
static void discarded_big(struct Big a){return (void)made_big(a);}
int main(void){
 struct A a={31};struct A c=a;struct A d=made(a);struct F f={2.5};struct Big big={1,2,3};
 signed char sc=-7;unsigned short us=65535;long q=+sc;double db=+f.x;long x=a.x;
 double cv=a.x;int narrow=a.x;long *p=&a.x;struct A *ap=&a;
 struct A nested[1]={{17}};long array[2]={a.x,c.x};
 if(sizeof(missing(1,a))!=8||sizeof(fp(1,a))!=8)return 1;
 if(sizeof(missing_big(1,a,big))!=24||sizeof(bigfp(1,a,big))!=24)return 2;
 if(sizeof(missing_float(f))!=8)return 3;
 if(sizeof(+sc)!=4||sizeof(+us)!=4||sizeof(+db)!=8)return 4;
 if(q!=-7||db!=2.5||x!=31||cv!=31.0||narrow!=31||*p!=31||ap->x!=31)return 5;
 if(nested[0].x!=17||array[0]!=31||array[1]!=31||c.x!=31||d.x!=32)return 6;
 if(count!=1)return 7;
 (void)a;(void)f;(void)big;(void)made(a);discarded(a);discarded_big(big);
 if(count!=4)return 8;
 if(sizeof(made(a))!=8||sizeof(made_big(big))!=24||count!=4)return 9;
 (void)made_big(made_big(big));if(count!=6)return 10;
 return 0;
}
