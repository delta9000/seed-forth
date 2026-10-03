#!/usr/bin/env python3
"""Independent INTEGER/MEMORY cross-ABI matrix; host objects are oracles only."""
from pathlib import Path
import subprocess, hashlib, json, tempfile
ROOT=Path(__file__).resolve().parents[2]
(ROOT/'build-out').mkdir(exist_ok=True)
W=Path(tempfile.mkdtemp(prefix='aggregate-interop-review-',dir=ROOT/'build-out'))
CC=ROOT/'tools/gcc-direct-cc.py'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
report={'scope':'Independent local INTEGER/MEMORY ABI review; host tools supply test oracles only','compiler_sha256':{str(p.relative_to(ROOT)):sha(p) for p in [ROOT/'seed-forth',ROOT/'010-lib.fth',*sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')),CC]},'cases':[]}
def run(args):
 p=subprocess.run(list(map(str,args)),capture_output=True,timeout=90)
 if p.returncode:
  print('FAILED',args,p.returncode,p.stdout.decode(errors='replace'),p.stderr.decode(errors='replace'),flush=True)
  raise RuntimeError(str(args))
 return p
(W/'sret.S').write_text('''.text
.globl invoke_sret
.type invoke_sret,@function
invoke_sret:
 mov %rdi,%r11
 mov %rsi,%rdi
 mov %rdx,%rsi
 sub $8,%rsp
 call *%r11
 add $8,%rsp
 ret
.section .note.GNU-stack,"",@progbits
''')
for n in range(1,34):
 d=W/f'n{n:02d}';d.mkdir(exist_ok=True)
 header=f'struct R {{unsigned char x[{n}];}};\n'
 source=[header]
 host=['#include <stdio.h>\n#include <sys/mman.h>\n#include <unistd.h>\n',header]
 main=['int main(void){struct R p,q,r,e; int i;\n',f'for(i=0;i<{n};i++){{p.x[i]=i*7+3;q.x[i]=i*11+17;}}\n']
 for k in range(8):
  decl=', '.join([f'long a{i}' for i in range(k)]+['struct R p','long t','struct R q','long z'])
  args=', '.join([str(i*13+1) for i in range(k)]+['p','19','q','23'])
  expr='+'.join([f'{i+2}*a{i}' for i in range(k)]+['t','3*z'])
  body=f'{{int i;long s={expr};for(i=0;i<{n};i++){{p.x[i]=p.x[i]+q.x[i]+s+i;q.x[i]=0;}}return p;}}\n'
  source += [f'struct R host_{k}({decl});\n',f'struct R sf_{k}({decl})'+body]
  source += [f'struct R outbound_{k}(struct R p,struct R q){{return host_{k}({args});}}\n']
  source += [f'typedef struct R (*F{k})({decl});\n',f'struct R callback_{k}(F{k} f,struct R p,struct R q){{return f({args});}}\n']
  host += [f'struct R sf_{k}({decl});\n',f'struct R host_{k}({decl})'+body,
           f'struct R outbound_{k}(struct R,struct R);\n',f'typedef struct R (*F{k})({decl});\n',
           f'struct R callback_{k}(F{k},struct R,struct R);\n']
  sm=sum((i+2)*(i*13+1) for i in range(k))+19+3*23
  main += [f'for(i=0;i<{n};i++)e.x[i]=p.x[i]+q.x[i]+{sm}+i;\n']
  for name,call in [('inbound',f'sf_{k}({args})'),('outbound',f'outbound_{k}(p,q)'),('callback_host',f'callback_{k}(host_{k},p,q)'),('callback_forth',f'callback_{k}(sf_{k},p,q)')]:
   main += [f'r={call};for(i=0;i<{n};i++)if(r.x[i]!=e.x[i]||p.x[i]!=(unsigned char)(i*7+3)||q.x[i]!=(unsigned char)(i*11+17)){{fprintf(stderr,"N={n} prefix={k} {name} byte=%d got=%d expected=%d\\n",i,r.x[i],e.x[i]);return 1;}}\n']
 source += ['struct R sf_read(struct R *p){return *p;}\n','struct R host_identity(struct R);\n','struct R sf_forward(struct R *p){return host_identity(*p);}\n']
 host += ['struct R sf_read(struct R *);\n','struct R sf_forward(struct R *);\n','struct R host_identity(struct R p){return p;}\n','void *invoke_sret(void *,void *,void *);\n']
 main += [f'''{{long pg=sysconf(_SC_PAGESIZE);unsigned char *a=mmap(0,pg*2,3,0x22,-1,0),*b=mmap(0,pg*2,3,0x22,-1,0);struct R *p,*q;void *ret;
 if(a==(void*)-1||b==(void*)-1||mprotect(a+pg,pg,0)||mprotect(b+pg,pg,0))return 2;
 p=(struct R *)(a+pg-{n});q=(struct R *)(b+pg-{n});for(i=0;i<{n};i++)p->x[i]=i*3+9;
 r=sf_read(p);for(i=0;i<{n};i++)if(r.x[i]!=p->x[i])return 3;
 r=sf_forward(p);for(i=0;i<{n};i++)if(r.x[i]!=p->x[i])return 4;
''']
 if n>16:
  main += [f'ret=invoke_sret((void*)sf_read,q,p);if(ret!=q){{fprintf(stderr,"N={n} sret RAX mismatch\\n");return 5;}}for(i=0;i<{n};i++)if(q->x[i]!=p->x[i])return 6;\n']
 main += ['if(munmap(a,pg*2)||munmap(b,pg*2))return 7;}return 0;}\n']
 (d/'production.c').write_text(''.join(source));(d/'host.c').write_text(''.join(host+main))
 obj=d/'production.o';run([CC,'-c',d/'production.c','-o',obj])
 entry={'size':n,'signature_count':8,'source_sha256':sha(d/'production.c'),'host_sha256':sha(d/'host.c'),'object_sha256':sha(obj),'executions':[]}
 for opt in ('-O0','-O2'):
  exe=d/f'oracle{opt}';run(['cc',opt,'-fno-pie','-no-pie','-Wl,-z,noexecstack',d/'host.c',obj,W/'sret.S','-o',exe]);run([exe]);entry['executions'].append({'optimization':opt,'sha256':sha(exe)})
 report['cases'].append(entry)
 (W/'matrix-report.json').write_text(json.dumps(report,indent=2)+'\n')
 print(f'PASS N={n}: 8 signatures, bidirectional/callback O0+O2, protected page'+(', sret RAX' if n>16 else ''),flush=True)
assert report['compiler_sha256']=={name:sha(ROOT/name) for name in report['compiler_sha256']}
print('PASS ALL 264 signature layouts / 2112 cross-ABI invocations; sizes 1..33; source unchanged',flush=True)
print(W/'matrix-report.json')
