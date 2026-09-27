import sys
f,b,a=sys.argv[1:4]; s=open(f).read(); bb=open(b).read(); aa=open(a).read()
assert s.count(bb)==1, "before text not found exactly once in "+f
open(f,'w').write(s.replace(bb,aa))
