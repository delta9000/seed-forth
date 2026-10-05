struct Cell { char a; long value; };
struct Holder { char before; struct Cell cells[2][3][2]; char after; };
extern unsigned global4[2][3][2][4];
extern struct Holder holder;
unsigned access4(int,int,int,int,unsigned);
long walk4(unsigned (*)[3][2][4],int);
long fill_holder(long);
struct Tiny { char before; char v[1][1][1]; char after; };
struct Medium { long v[1][1][2]; };
struct Large { long v[2][2][2]; };
struct Tiny bump_tiny(struct Tiny);
struct Medium bump_medium(struct Medium);
struct Large bump_large(struct Large);
int main(void)
{
  int a,b,c,d; long sum=0;
  struct Tiny tiny={11,{{{13}}},17},t;
  struct Medium medium={{{{19,23}}}},m;
  struct Large large={{{{1,2},{3,4}},{{5,6},{7,8}}}},l;
  unsigned (*p)[3][2][4]=global4;
  unsigned (*whole)[2][3][2][4]=&global4;
  t=bump_tiny(tiny);m=bump_medium(medium);l=bump_large(large);
  if(sizeof tiny!=3||t.before!=11||t.v[0][0][0]!=16||t.after!=17||tiny.v[0][0][0]!=13)return 9;
  if(sizeof medium!=16||m.v[0][0][0]!=19||m.v[0][0][1]!=30||medium.v[0][0][1]!=23)return 10;
  if(sizeof large!=64||l.v[1][1][1]!=19||large.v[1][1][1]!=8)return 11;
  if(sizeof global4!=192||sizeof global4[0]!=96||sizeof global4[0][0]!=32||sizeof global4[0][0][0]!=16||sizeof global4[0][0][0][0]!=4)return 1;
  if(sizeof *p!=96||sizeof *whole!=192||p+1!=&global4[1]||whole+1!=&global4+1)return 2;
  for(a=0;a<2;a++)for(b=0;b<3;b++)for(c=0;c<2;c++)for(d=0;d<4;d++){
    global4[a][b][c][d]=1+a*24+b*8+c*4+d;
    sum+=1+a*24+b*8+c*4+d;
  }
  if(walk4(global4,2)!=sum||(*whole)[1][2][1][3]!=48||p[1][2][1][3]!=48)return 3;
  for(a=0;a<2;a++)for(b=0;b<2;b++)for(c=0;c<2;c++)for(d=0;d<2;d++)if(access4(a,b,c,d,1+a*8+b*4+c*2+d)!=0)return 4;
  for(a=0;a<2;a++)for(b=0;b<2;b++)for(c=0;c<2;c++)for(d=0;d<2;d++)if(access4(a,b,c,d,0)!=1+a*8+b*4+c*2+d)return 5;
  if(fill_holder(100)!=208||holder.before!=7||holder.after!=9)return 6;
  if(sizeof holder.cells!=192||sizeof holder.cells[0]!=96||sizeof holder.cells[0][0]!=32)return 7;
  for(a=0;a<2;a++)for(b=0;b<3;b++)for(c=0;c<2;c++)if(holder.cells[a][b][c].a!=a*6+b*2+c||holder.cells[a][b][c].value!=100+a*6+b*2+c)return 8;
  return 0;
}
