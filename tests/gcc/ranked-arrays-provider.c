struct Cell { char a; long value; };
struct Holder { char before; struct Cell cells[2][3][2]; char after; };
unsigned global4[2][3][2][4];
struct Holder holder;
unsigned access4(int a, int b, int c, int d, unsigned value)
{
  static unsigned costs[2][2][2][2];
  unsigned old=costs[a][b][c][d];
  costs[a][b][c][d]=value;
  return old;
}
long walk4(unsigned (*p)[3][2][4], int n)
{
  int a,b,c,d;long sum=0;
  for(a=0;a<n;a++)for(b=0;b<3;b++)for(c=0;c<2;c++)for(d=0;d<4;d++)sum+=p[a][b][c][d];
  return sum;
}
long fill_holder(long n)
{
  int a,b,c;
  holder.before=7;holder.after=9;
  for(a=0;a<2;a++)for(b=0;b<3;b++)for(c=0;c<2;c++){
    holder.cells[a][b][c].a=a*6+b*2+c;
    holder.cells[a][b][c].value=n+a*6+b*2+c;
  }
  return sizeof holder;
}
struct Tiny { char before; char v[1][1][1]; char after; };
struct Medium { long v[1][1][2]; };
struct Large { long v[2][2][2]; };
struct Tiny bump_tiny(struct Tiny x){x.v[0][0][0]+=3;return x;}
struct Medium bump_medium(struct Medium x){x.v[0][0][1]+=7;return x;}
struct Large bump_large(struct Large x){x.v[1][1][1]+=11;return x;}
