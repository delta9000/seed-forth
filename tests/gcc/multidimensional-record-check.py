#!/usr/bin/env python3
"""Fixed two-dimensional record fields: Forth production and host ABI oracles."""
from pathlib import Path
import argparse, hashlib, json, os, resource, subprocess, sys, tempfile
ROOT = Path(__file__).resolve().parents[2]
LIMIT = 1024 * 1024 * 1024
REJECT = {
    'inherited-anonymous-initialize': ('struct S { char a; struct { short b; int m[2][3]; }; char z; };\nstruct S g={1,{2,{{3,4,5},{6,7,8}}},9};\nint main(void){struct S s={11,{12,{{13,14,15},{16,17,18}}},19};return g.a!=1||g.b!=2||g.m[1][2]!=8||g.z!=9||s.a!=11||s.b!=12||s.m[1][2]!=18||s.z!=19;}', 227),
    'inherited-anonymous-union-initialize': ('struct S { char a; union { int m[2][3]; long spare; }; char z; };\nstruct S g={1,{{{3,4,5},{6,7,8}}},9};\nint main(void){struct S s={11,{{{13,14,15},{16,17,18}}},19};return g.a!=1||g.m[1][2]!=8||g.z!=9||s.a!=11||s.m[1][2]!=18||s.z!=19;}', 227),
    'inherited-static-decay': ('struct S { int m[2][3]; } s={{{1,2,3},{4,5,6}}};int (*p)[3]=s.m;int *q=s.m[1];\nint main(void){return p[1][2]!=6||q[2]!=6;}', 240),
    'outer-zero': ('struct S {int m[0][3];};', 238),
    'inner-zero': ('struct S {int m[2][0];};', 238),
    'outer-negative': ('struct S {int m[-2][3];};', 238),
    'inner-negative': ('struct S {int m[2][-3];};', 238),
    'outer-incomplete': ('struct S {int m[][3];};', 238),
    'product-limit': ('struct S {long m[16384][16384];};', 245),
    'product-overflow': ('struct S {long m[1073741824][1073741824];};', 245),
    'row-overflow': ('struct S {long m[2][9223372036854775807L];};', 245),
    'bitfield-overflow': ('struct S {char m[32768][32768];unsigned tail:1;};', 245),
    'record-overflow': ('struct S {char m[32768][32768];char tail;};', 245),
    'padding-overflow': ('struct S {char m[32768][32767];long tail[4097];};', 245),
    'record-element-overflow': ('struct E {long a[2];};struct S {struct E m[8192][16384];};', 245),
    'array-assignment': ('struct S {int m[2][3];};void f(struct S*p,struct S*q){p->m=q->m;}', 120),
    'row-assignment': ('struct S {int m[2][3];};void f(struct S*p,struct S*q){p->m[1]=q->m[1];}', 120),
    'array-increment': ('struct S {int m[2][3];};void f(struct S*p){p->m++;}', 113),
    'row-increment': ('struct S {int m[2][3];};void f(struct S*p){p->m[1]++;}', 113),
    'matrix-member': ('struct E{long v;};struct S{struct E m[2][3];};long f(struct S*p){return p->m.v;}', 238),
    'matrix-arrow': ('struct E{long v;};struct S{struct E m[2][3];};long f(struct S*p){return p->m->v;}', 238),
    'scalar-subscript': ('struct S{int m[2][3];};long f(struct S*p){return p->m[1][2][0];}', 238),
    'row-type-mismatch': ('struct S {int m[2][3];};void f(struct S*p){int (*q)[2]=p->m;}', 237),
    'row-element-mismatch': ('struct S {int m[2][3];};void f(struct S*p){long (*q)[3]=p->m;}', 237),
    'scalar-pointer-mismatch': ('struct S {int m[2][3];};void f(struct S*p){int*q=p->m;}', 237),
    'outer-initializers': ('struct S {int m[2][3];}s={{{1,2,3},{4,5,6},{7,8,9}}};', 226),
    'inner-initializers': ('struct S {int m[2][3];}s={{{1,2,3,4},{5,6,7}}};', 226),
    'record-initializers': ('struct E {long x;};struct S {struct E m[1][1];}s={{{{1},{2}}}};', 226),
    'string-bound': ('struct S {char m[2][2];}s={{"abc","d"}};', 223),
    'static-outer-bound': ('struct S {int m[2][3];}s;int(*p)[3]=&s.m[3];', 240),
    'static-inner-bound': ('struct S {int m[2][3];}s;int*p=&s.m[1][4];', 240),
    'qualified-decay': ('struct S {const int m[2][3];};void f(struct S*p){int(*q)[3]=p->m;}', 238),
    'qualified-address-discard': ('struct S {const int m[2][3];}s;int(*p)[2][3]=&s.m;', 238),
}
# Qualified matrix members decay and take addresses as qualified rows.
ACCEPT = {
    'qualified-decay': 'struct S {const int m[2][3];};void f(struct S*p){const int(*q)[3]=p->m;}',
    'qualified-address': 'struct S {const int m[2][3];}s;const int(*p)[2][3]=&s.m;',
    'qualified-record-address': 'struct S {int m[2][3];};void f(const struct S*p){sizeof(&p->m);}',
    'qualified-row-address': 'struct S {volatile int m[2][3];};void f(struct S*p){sizeof(&p->m[1]);}',
}

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path)
    parser.add_argument('--baseline-root', type=Path)
    parser.add_argument('--source-root', type=Path)
    parser.add_argument('--generated-dir', type=Path)
    args = parser.parse_args()
    resource.setrlimit(resource.RLIMIT_AS, (LIMIT, LIMIT))
    work = (args.work or Path(tempfile.mkdtemp(prefix='multidimensional-record-', dir=ROOT/'build-out'))).resolve()
    work.mkdir(parents=True, exist_ok=True)
    events = []
    env = dict(os.environ, LC_ALL='C', PYTHONWARNINGS="ignore:'maxsplit' is passed as positional argument:DeprecationWarning")
    def run(command, expected=0, **kw):
        command = list(map(str, command))
        p = subprocess.run(command, capture_output=True, timeout=180, env=env, **kw)
        events.append(dict(command=command, status=p.returncode, stdout=p.stdout.decode(errors='replace'), stderr=p.stderr.decode(errors='replace')))
        (work/'commands.json').write_text(json.dumps(events, indent=2)+'\n')
        assert p.returncode == expected, events[-1]
        return p.stdout
    cc = [sys.executable, ROOT/'tools/gcc-direct-cc.py']
    before = run(cc+['--print-source-hash']).decode().strip()
    fixture = ROOT/'tests/gcc'
    units = [fixture/('multidimensional-record-'+part+'.c') for part in ('provider','main')]
    objects = [work/(part+'.o') for part in ('provider','main')]
    for source, obj in zip(units, objects): run(cc+['-I'+str(fixture), '-c', source, '-o', obj])
    binary = work/'forth-only'
    run(cc+objects+['-o', binary])
    output = run([binary])
    assert output == b'matrix: 168 4 32 128 136 161; mixed ABI and execution passed\n'
    for opt in ('-O0', '-O2'):
        hosts = [work/(part+opt+'.o') for part in ('provider','main')]
        for source, obj in zip(units, hosts):
            run(['gcc', '-std=gnu90', opt, '-fno-pie', '-fno-stack-protector', '-I'+str(fixture), '-c', source, '-o', obj])
        for name, inputs in [('host', hosts), ('forth-provider', [objects[0],hosts[1]]), ('forth-caller', [hosts[0],objects[1]])]:
            binary = work/(name+opt)
            run(['gcc', '-no-pie', '-Wl,-z,noexecstack', *inputs, '-o', binary])
            assert run([binary]) == output
    boundary=work/'exact-size-boundary.c'
    boundary.write_text('struct S {char m[32768][32768];}; union U {struct S s;long a;};int main(void){return sizeof(struct S)!=1073741824UL||sizeof(union U)!=1073741824UL;}\n')
    run(cc+[boundary,'-o',work/'exact-size-boundary']);run([work/'exact-size-boundary'])
    for opt in ('-O0','-O2'):
        run(['gcc',opt,boundary,'-o',work/('exact-size-boundary'+opt)]);run([work/('exact-size-boundary'+opt)])
    for name, source in ACCEPT.items():
        path=work/(name+'.c');path.write_text(source+'\n')
        run(cc+['-c',path,'-o',work/(name+'.o')])
    for name, (source, status) in REJECT.items():
        path=work/(name+'.c');path.write_text(source+'\n');obj=work/(name+'.o')
        original=b'preserve-existing-output\n';obj.write_bytes(original)
        run(cc+['-c',path,'-o',obj],status)
        assert obj.read_bytes()==original,name
    if args.source_root:
        assert args.generated_dir, '--source-root needs --generated-dir'
        header=args.source_root/'gcc/optabs.h';raw=header.read_bytes()
        assert sha(header)=='12aee9dc3f7e9a8ef19c81790461ae77ab4d1ff5d4274ef8d86a48edf81055db', 'Original GCC 4.0.4 optabs.h changed'
        begin=raw.index(b'struct optab_handlers GTY(())')
        end=raw.index(b'typedef struct convert_optab *convert_optab;')+len(b'typedef struct convert_optab *convert_optab;')
        snippet=raw[begin:end]
        # Exact original declaration bytes; surrounding names are explicit shims.
        source=work/'original-optabs.c'
        source.write_bytes(b'#include "insn-modes.h"\n#include "insn-codes.h"\n#define GTY(X)\nstruct rtx_def;typedef struct rtx_def *rtx;enum rtx_code {UNKNOWN};\n'+snippet+b'''
static struct convert_optab table;
int main(void){int i,j;for(i=0;i<NUM_MACHINE_MODES;i++)for(j=0;j<NUM_MACHINE_MODES;j++)table.handlers[i][j].insn_code=i*NUM_MACHINE_MODES+j;
if(sizeof(table.handlers)!=sizeof(struct optab_handlers)*NUM_MACHINE_MODES*NUM_MACHINE_MODES)return 1;
if(sizeof(table.handlers[0])!=sizeof(struct optab_handlers)*NUM_MACHINE_MODES)return 2;
for(i=0;i<NUM_MACHINE_MODES;i++)for(j=0;j<NUM_MACHINE_MODES;j++)if(table.handlers[i][j].insn_code!=i*NUM_MACHINE_MODES+j)return 3;return 0;}
''')
        flags=['-I'+str(args.generated_dir.resolve())]
        run(cc+flags+[source,'-o',work/'original-optabs']);run([work/'original-optabs'])
        for opt in ('-O0','-O2'):
            run(['gcc','-std=gnu90',opt,*flags,source,'-o',work/('original-optabs'+opt)])
            run([work/('original-optabs'+opt)])
        (work/'original-inputs.json').write_text(json.dumps({'optabs.h':sha(header),'extracted_declarations_sha256':hashlib.sha256(snippet).hexdigest(),**{name:sha(args.generated_dir/name) for name in ('insn-modes.h','insn-codes.h')},'scope':'Exact original record declaration bytes with explicit rtx/rtx_code/GTY shims; not the full GCC translation unit'},indent=2)+'\n')
    preservation = []
    if args.baseline_root:
        libraries=[ROOT/'010-lib.fth']+[p for p in sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')) if p.name not in ('120-cc-main.fth','140-cc-link.fth')]
        vocabs=[b'\n'.join((base/p.name).read_bytes() for p in libraries) for base in (args.baseline_root,ROOT)]
        for native,names in [(False,['P1-conditionals','P2-fn-macros','P3-casts','P8-libc-shims']),(True,['basics','layout','stack-call','literals','many-args','switch-goto'])]:
            for name in names:
                source=(ROOT/('tests/tcc/native-'+name+'.c' if native else 'tests/cc/'+name+'.c')).read_bytes()
                setup=b'true cc-target-lp64 ! true cc-prep-direct ! [lit] 8388608 cc-arena-map\n' if native else b''
                parse=b'cc-native-program' if native else b'cc-parse-program'
                script=setup+b': preservation cc-load-stdin cc-preprocess cc-out-init cc-globals-init cc-emit-elf-header '+parse+b' cc-finalize-globals cc-finalize-elf [lit] 1 cc-out-buf cc-out-pos @ write drop bye ;\npreservation\n'
                outputs=[run([ROOT/'seed-forth'],input=v+b'\n'+script+source,cwd=ROOT) for v in vocabs]
                assert outputs[0]==outputs[1],name
                filenames=[]
                for label,data in zip(('baseline','candidate'),outputs):
                    path=work/('preserve-'+('native-' if native else 'legacy-')+name+'-'+label+'.elf')
                    path.write_bytes(data);filenames.append(path.name)
                preservation.append({'case':name,'target':'native' if native else 'legacy','sha256':hashlib.sha256(outputs[0]).hexdigest(),'bytes':len(outputs[0]),'files':filenames})
    (work/'preservation.json').write_text(json.dumps(preservation,indent=2)+'\n')
    assert run(cc+['--print-source-hash']).decode().strip()==before
    assert (ROOT/'seed-forth').stat().st_size==1772
    assert sha(ROOT/'seed-forth')=='697e340e38cabeecbff430d6626e29f4ed3a55498f89d7bda16d8f65e4de774e'
    (work/'report.json').write_text(json.dumps({'source_identity':before,'seed_sha256':sha(ROOT/'seed-forth'),'production':'Forth compiler, object writer, runtime and linker','oracles':'Independent host O0/O2 and both mixed ABI directions','negative_cases':len(REJECT),'original_declaration_proof':bool(args.source_root),'legacy_native_byte_preservation':bool(args.baseline_root),'memory_limit':LIMIT,'commands':'commands.json'},indent=2)+'\n')
    print('PASS: two-dimensional fields, initialization, layout, indexing, addresses, bounded errors and mixed O0/O2 ABI')
    print(work/'report.json')
if __name__=='__main__':main()
