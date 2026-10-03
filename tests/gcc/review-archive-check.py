#!/usr/bin/env python3
"""Independent archive review: Forth produces target objects/archives/executables.

Python examines bytes and constructs adversarial archive mutations. GNU ar/ld
are independent compatibility oracles only. Source snapshot is hashed in results.
"""
from pathlib import Path
import hashlib, json, os, resource, signal, struct, subprocess, tempfile

ROOT = Path(os.environ.get('SF_REVIEW_ROOT', Path(__file__).resolve().parents[2])).resolve()
OUT = Path(tempfile.mkdtemp(prefix='review-archive-', dir=ROOT / 'build-out'))
PARTS = ['010-lib.fth', '020-cc-arena.fth', '030-cc-io.fth']
BASE = '\n'.join((ROOT / p).read_text() for p in PARTS)
WRITER = BASE + '\n' + (ROOT / '081-cc-object.fth').read_text()
LINKER = BASE + '\n' + (ROOT / '140-cc-link.fth').read_text() + '\n' + (ROOT / '141-archive.fth').read_text()
ASSERT = '\n: review-assert 0= if, [lit] 249 die then, ;\n'
HASHES = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in PARTS + ['081-cc-object.fth', '140-cc-link.fth', '141-archive.fth', 'seed-forth']}
CHECKS, FAILURES = [], []

def word(name, path):
    return '\ncreate ' + name + ' ' + ' '.join(f'[lit] {b} c,' for b in os.fsencode(path)) + ' [lit] 0 c,\n'

def run(name, source, expected=0, fsize=None):
    def limit():
        resource.setrlimit(resource.RLIMIT_FSIZE, (fsize, fsize))
        signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
    p = subprocess.run([ROOT/'seed-forth'], input=(source+'\nbye\n').encode(), capture_output=True, timeout=40, preexec_fn=limit if fsize else None)
    okay = p.returncode == expected and not p.stdout and (f'error {expected}'.encode() in p.stderr if expected else not p.stderr)
    CHECKS.append(dict(name=name, expected=expected, status=p.returncode, okay=okay))
    if not okay:
        (OUT/(name+'.fth')).write_text(source+'\nbye\n')
        FAILURES.append(dict(name=name, expected=expected, status=p.returncode, stdout=p.stdout.decode(errors='replace'), stderr=p.stderr.decode(errors='replace')))
    return okay

def probe(name, fn):
    try: fn()
    except Exception as e:
        FAILURES.append(dict(name=name, exception=repr(e)))

def execute(path, expected=42):
    p = subprocess.run([path], capture_output=True, timeout=5)
    assert (p.returncode,p.stdout,p.stderr)==(expected,b'',b''),(path.name,p.returncode,p.stdout,p.stderr)

def build_object(name, defs=(), refs=(), code=None, call=None):
    """defs = (name,binding,section); refs = (name,binding)."""
    path = OUT/name
    if code is None: code = bytes.fromhex('bf2a000000b83c0000000f05') if any(d[0]=='_start' for d in defs) else bytes.fromhex('b82a000000c3')
    source=WRITER+'\ncc-obj-init\n'
    for b in code: source+=f'[lit] {b} cc-obj-byte\n'
    for sec in (2,3): source+=f'[lit] {sec} cc-obj-use [lit] 42 cc-obj-8le\n'
    source+='cc-obj-bss cc-obj-use [lit] 8 cc-obj-reserve drop\n'
    for i,(symbol,binding,section) in enumerate(defs):
        size=len(code) if section==1 else 8 if section in (2,3,4) else 0
        value=42 if section==65521 else 0
        source+=f'create n{i} s, {symbol}\nn{i} [lit] {len(symbol)} [lit] {binding} cc-obj-notype cc-obj-default [lit] {section} [lit] {value} [lit] {size} cc-obj-symbol drop\n'
    for i,(symbol,binding) in enumerate(refs):
        source+=f'create r{i} s, {symbol}\nr{i} [lit] {len(symbol)} [lit] {binding} cc-obj-notype cc-obj-default cc-obj-undef [lit] 0 [lit] 0 cc-obj-symbol\n'
        source+= ('>r cc-obj-text [lit] 1 cc-obj-plt32 r> [lit] 0 [lit] 4 - cc-obj-reloc\n' if call==symbol else '>r cc-obj-data cc-obj-use cc-obj-data [lit] 8 cc-obj-reserve cc-obj-r64 r> [lit] 0 cc-obj-reloc\n')
    source+=word('out',path)+'out cc-obj-write\n'
    assert run('object-'+name,source)
    return path

def archive(name, paths, expected=0, destination=None, fsize=None, tail=''):
    dest=destination or OUT/name
    before=dest.read_bytes() if dest.is_file() else None
    source=LINKER+ASSERT+'\n[lit] 314159 arc-init\n'
    for i,path in enumerate(paths): source+=word(f'in{i}',path)+f'in{i} arc-add-object\n'
    source+=word('out',dest)+'out arc-write\n[lit] 314159 = review-assert\n'+tail
    ok=run(name,source,expected,fsize)
    if expected and before is not None: assert dest.read_bytes()==before,(name,'prior output changed')
    if not expected and ok: assert dest.is_file()
    assert not list(OUT.glob('*.lnk-*')),(name,'temporary file leak')
    return dest

def link(name, paths, expected=0, count=None, destination=None, fsize=None, tail=''):
    dest=destination or OUT/name
    before=dest.read_bytes() if dest.is_file() else None
    source=LINKER+ASSERT+'\n[lit] 314159 lnk-init\n'
    for i,path in enumerate(paths): source+=word(f'in{i}',path)+f'in{i} '+('lnk-add-archive' if path.suffix=='.a' else 'lnk-add-object')+'\n'
    if count is not None: source+=f'lnk-count @ [lit] {count} = review-assert\n'
    source+='create entry s, _start\nentry [lit] 6 lnk-entry\n'+word('out',dest)+'out lnk-link\n[lit] 314159 = review-assert\n'+tail
    ok=run(name,source,expected,fsize)
    if expected and before is not None: assert dest.read_bytes()==before,(name,'prior output changed')
    if not expected and ok: execute(dest)
    assert not list(OUT.glob('*.lnk-*')),(name,'temporary file leak')
    return dest

def check(name, data, expected=0):
    path=OUT/(name+'.a'); path.write_bytes(data)
    run(name,LINKER+ASSERT+word('in',path)+'[lit] 314159 in arc-check [lit] 314159 = review-assert\n',expected)
    return path

def members(data):
    rows=[]; p=8
    assert data[:8]==b'!<arch>\n'
    while p<len(data):
        h=data[p:p+60]; n=int(h[48:58]); rows.append((p,h[:16].rstrip(),p+60,n));p+=60+n+(n%2)
    assert p==len(data)
    return rows

def index(data):
    row=next(r for r in members(data) if r[1]==b'/')
    _,_,p,n=row; count=struct.unpack_from('>I',data,p)[0]
    offsets=struct.unpack_from('>'+str(count)+'I',data,p+4)
    names=data[p+4+4*count:p+n].split(b'\0')[:count]
    return list(zip(names,offsets))

def oracle(name, paths, expected=0):
    dest=OUT/(name+'-gnu'); p=subprocess.run(['ld','-o',dest,*paths],capture_output=True,timeout=30)
    assert (p.returncode==0)==(expected==0),(name,p.returncode,p.stderr)
    if not expected: execute(dest)
    CHECKS.append(dict(name=name+'-gnu-ld',okay=True,status=p.returncode))

def mutate(name, original, offset, replacement, expected=250):
    data=bytearray(original);data[offset:offset+len(replacement)]=replacement
    return check(name,data,expected)

start=build_object('start.o',[('_start',1,1)])
demand=build_object('demand.o',[('_start',1,1)],[('foo',1)])
provider=build_object('provider.o',[('foo',1,1)])
chain=build_object('chain.o',[('foo',1,1)],[('bar',1)])
bar=build_object('bar.o',[('bar',1,1)])
unused=build_object('unused.o',[('unused',1,1)],[('missing',1)])
weak=build_object('weak.o',[('foo',2,1)])
local=build_object('local.o',[('foo',0,1)])
weak_demand=build_object('weak-demand.o',[],[('foo',2)])
strong_demand=build_object('strong-demand.o',[],[('foo',1)])
call_start=build_object('call-start.o',[('_start',1,1)],[('foo',1)],bytes.fromhex('e80000000089c7b83c0000000f05'),'foo')
long=build_object('a-very-long-object-member-name.o',[('foo',1,1)])
short15=build_object('123456789012345',[('f15',1,1)])
long16=build_object('1234567890123456',[('f16',1,1)])
base=archive('base.a',[provider]); basebytes=base.read_bytes()
archive('deterministic.a',[provider]);assert (OUT/'deterministic.a').read_bytes()==basebytes
for p in (base,):
    x=subprocess.run(['ar','p',p,provider.name],capture_output=True);assert x.returncode==0 and x.stdout==provider.read_bytes()
    x=subprocess.run(['ar','t',p],capture_output=True);assert x.returncode==0 and x.stdout==b'provider.o\n'
check('self-parse',basebytes)
link('runtime',[call_start,base],count=2);oracle('runtime',[call_start,base])
link('basic',[demand,base],count=2);oracle('basic',[demand,base])
link('unused-library',[start,base],count=1)
link('archive-before-demand',[base,demand],253);oracle('archive-before-demand',[base,demand],253)
link('repeat-library',[base,demand,base],count=2);oracle('repeat-library',[base,demand,base])
reverse=archive('reverse.a',[bar,chain,unused,provider])
link('fixed-point',[demand,reverse],count=3);oracle('fixed-point',[demand,reverse])
local_lib=archive('local.a',[local,provider]);assert [n for n,_ in index(local_lib.read_bytes())]==[b'foo']
link('local-not-indexed',[demand,local_lib],count=2)
weaklib=archive('weak.a',[weak,provider]);assert len(index(weaklib.read_bytes()))==2
link('weak-provider-first',[demand,weaklib],count=2);oracle('weak-provider-first',[demand,weaklib])
link('weak-undefined-no-extract',[start,weak_demand,base],count=2);oracle('weak-undefined-no-extract',[start,weak_demand,base])
link('weak-then-strong-demand',[start,weak_demand,strong_demand,base],count=4);oracle('weak-then-strong-demand',[start,weak_demand,strong_demand,base])
link('strong-then-weak-demand',[start,strong_demand,weak_demand,base],count=4)
link('weak-definition-stops-extraction',[demand,weak,base],count=2);oracle('weak-definition-stops-extraction',[demand,weak,base])
link('ordinary-strong-after-weak',[demand,weak,provider],count=3)
link('ordinary-duplicate',[demand,provider,provider],252)
# A reference newly introduced by a later ordinary object needs another archive occurrence.
foo_only=archive('foo-only.a',[chain]);bar_only=archive('bar-only.a',[bar])
link('cross-archive-no-group',[demand,bar_only,foo_only],253);oracle('cross-archive-no-group',[demand,bar_only,foo_only],253)
link('cross-archive-repeat',[demand,bar_only,foo_only,bar_only],count=3);oracle('cross-archive-repeat',[demand,bar_only,foo_only,bar_only])
# Every supported nonlocal binding / definition section is indexed, local is excluded.
all_defs=[]
for bind in (0,1,2):
    for sec in (1,2,3,4,65521): all_defs.append((f's{bind}_{sec}',bind,sec))
combo=build_object('all-sections.o',all_defs)
combo_lib=archive('all-sections.a',[combo]); names={n.decode() for n,_ in index(combo_lib.read_bytes())}
assert names=={n for n,b,s in all_defs if b},names
for n,b,s in all_defs:
    if b:
        need=build_object(f'need-{n}.o',[('_start',1,1)],[(n,1)])
        link(f'section-{n}',[need,combo_lib],count=2)
longlib=archive('longs.a',[short15,long16,long]);longbytes=longlib.read_bytes()
assert subprocess.run(['ar','t',longlib],capture_output=True).stdout.splitlines()==[os.fsencode(p.name) for p in (short15,long16,long)]
link('long-name',[demand,longlib],count=2);oracle('long-name',[demand,longlib])
# Independently produced GNU ar serves as a reader interoperability oracle.
gnu=OUT/'gnu-oracle.a';subprocess.run(['ar','rcsD',gnu,long,provider],check=True,capture_output=True)
check('gnu-reader',gnu.read_bytes());link('gnu-reader-link',[demand,gnu],count=2)
# Unselected invalid ELF and unresolved/duplicate symbols must remain untouched.
unusedlib=archive('unused-invalid.a',[provider,unused]);bad=bytearray(unusedlib.read_bytes()); rows=members(bad);bad[rows[-1][2]:rows[-1][2]+4]=b'BAD!';unusedlib.write_bytes(bad)
link('unselected-invalid',[demand,unusedlib],count=2);check('invalid-payload-envelope',bad)
duplicate=archive('duplicate-unused.a',[provider,provider]);link('unselected-duplicate',[demand,duplicate],count=2)
selected_bad=bytearray(basebytes);selected_bad[members(basebytes)[-1][2]:members(basebytes)[-1][2]+4]=b'BAD!'
invalid=check('selected-invalid-envelope',selected_bad);link('selected-invalid-elf',[demand,invalid],250)
# Archive error / I/O publication preserves preexisting destination and all input bytes.
prior=OUT/'prior-output';prior.write_bytes(b'previous-output')
link('prior-unresolved',[demand],253,destination=prior)
link('prior-malformed-member',[demand,invalid],250,destination=prior)
link('prior-write-failure',[demand,base],255,destination=prior,fsize=100)
archive('archive-write-failure',[provider],255,destination=prior,fsize=100)
link('archive-output-alias',[demand,base],255,destination=base);assert base.read_bytes()==basebytes
hard=OUT/'hard-alias.a';os.link(base,hard);link('archive-hardlink-alias',[demand,base],255,destination=hard);assert hard.read_bytes()==basebytes
symlink=OUT/'symlink-alias.a';symlink.symlink_to(base);link('archive-symlink-alias',[demand,base],255,destination=symlink)
archive('writer-input-alias',[provider],255,destination=provider)
objhard=OUT/'object-hardlink.o';os.link(provider,objhard);archive('writer-hardlink-alias',[provider],255,destination=objhard)
# Rejected archive envelope/index/name boundaries.
for n in (0,1,7,9,67,len(basebytes)-1): check(f'truncate-{n}',basebytes[:n],250)
mutate('bad-magic',basebytes,0,b'?');mutate('thin-magic',basebytes,0,b'!<thin>\n')
mutate('bad-header-trailer',basebytes,8+58,b'!\n')
for label,value in [('negative',b'-1        '),('overflow',b'9999999999'),('junk',b'10x       '),('all-space',b'          '),('leading-space',b' 4        ')]: mutate('size-'+label,basebytes,8+48,value)
mutate('index-too-short',basebytes,8+48,b'3         ')
mutate('index-count-overflow',basebytes,68,b'\xff\xff\xff\xff',251)
mutate('index-count-overrun',basebytes,68,struct.pack('>I',100))
for off in (0,8,68,len(basebytes),members(basebytes)[-1][0]+1,members(basebytes)[-1][2]):mutate(f'index-offset-{off}',basebytes,72,struct.pack('>I',off))
mutate('index-empty-name',basebytes,76,b'\0')
indexrow=members(basebytes)[0]
mutate('index-unterminated',basebytes,indexrow[2]+indexrow[3]-1,b'X')
# A member with odd payload exercises mandatory newline padding independently.
odd=bytearray(basebytes);m=members(odd)[-1]; payload=odd[m[2]:m[2]+m[3]];odd=odd[:m[0]]+odd[m[0]:m[2]]+payload+b'X\n';odd[m[0]+48:m[0]+58]=str(m[3]+1).encode().ljust(10,b' ')
check('odd-payload-envelope',odd)
mutate('odd-padding-non-newline',odd,len(odd)-1,b'X')
check('odd-padding-missing',odd[:-1],250)
for label,raw in [('empty',b' '*16),('control',b'a\x01/            '),('nul',b'a\0/            '),('bsd-index',b'__.SYMDEF/      '),('bad-long-ref',b'/a              ')]:
    mutate('name-'+label,basebytes,members(basebytes)[-1][0],raw.ljust(16,b' '))
mutate('missing-long-table',basebytes,members(basebytes)[-1][0],b'/0              ')
longrows=members(longbytes);longtable=next(r for r in longrows if r[1]==b'//');longmember=next(r for r in longrows if r[1]==b'/0')
mutate('long-name-mid-entry',longbytes,longmember[0],b'/1              ')
mutate('long-name-outside',longbytes,longmember[0],b'/99999          ')
mutate('long-name-missing-slash',longbytes,longtable[2]+len(long16.name),b'X')
mutate('long-name-missing-newline',longbytes,longtable[2]+longtable[3]-1,b'X')
# BSD extended names replace a single member; GNU symbol index remains in place.
m=members(basebytes)[-1];bsd_name=b'bsd-extended-object-name.o\0\0\0'; bsd=bytearray(basebytes[:m[0]]);header=bytearray(basebytes[m[0]:m[2]]);header[:16]=f'#1/{len(bsd_name)}'.encode().ljust(16,b' ');newsize=m[3]+len(bsd_name);header[48:58]=str(newsize).encode().ljust(10,b' ');bsd+=header+bsd_name+basebytes[m[2]:m[2]+m[3]];bsd+=b'\n' if newsize%2 else b''
bsdpath=check('bsd-extended',bsd);link('bsd-extended-link',[demand,bsdpath],count=2)
mutate('bsd-name-zero',bsd,m[0],b'#1/0            ')
mutate('bsd-name-overrun',bsd,m[0],b'#1/999999       ')
mutate('bsd-name-empty',bsd,m[2],b'\0'*len(bsd_name))
# Empty archive is valid; a nonempty archive without GNU index is outside contract.
empty=archive('empty.a',[]);assert subprocess.run(['ar','t',empty],capture_output=True).returncode==0
check('bare-empty',b'!<arch>\n');check('no-index',b'!<arch>\n'+basebytes[m[0]:],250)
# All selected members have private mappings; reset/close must release ownership.
release=LINKER+ASSERT+word('start',demand)+word('lib',base)+'''
lnk-init start lnk-add-object lib lnk-add-archive
variable selected-map [lit] 1 lnk-object @ selected-map !
create resident [lit] 1 allot
lnk-release
selected-map @ [lit] 4096 resident [lit] 0 [lit] 0 [lit] 0 [lit] 27 syscall6 [lit] 0 [lit] 12 - = review-assert
'''
run('selected-map-release',release)
# Writer release, reader release, and successive sessions including alias ledger reset.
reset=LINKER+ASSERT+word('obj',provider)+word('lib',base)+word('entryobj',start)+word('dest',OUT/'reset-output')+'''
arc-init obj arc-add-object
variable writer-map [lit] 0 arc-member @ writer-map !
arc-init
create resident [lit] 1 allot
writer-map @ [lit] 4096 resident [lit] 0 [lit] 0 [lit] 0 [lit] 27 syscall6 [lit] 0 [lit] 12 - = review-assert
lib arc-open variable reader-map arc-image @ reader-map ! arc-close
reader-map @ [lit] 4096 resident [lit] 0 [lit] 0 [lit] 0 [lit] 27 syscall6 [lit] 0 [lit] 12 - = review-assert
lnk-init lib lnk-add-archive lnk-count @ [lit] 0 = review-assert
lnk-init lnk-input-count @ [lit] 0 = review-assert entryobj lnk-add-object
create entry s, _start entry [lit] 6 lnk-entry dest lnk-link
lnk-init lnk-count @ [lit] 0 = review-assert lnk-input-count @ [lit] 0 = review-assert
lnk-release
'''
run('session-reset-release',reset)
# Ordinary object outputs match a baseline-only linker session exactly.
plain=BASE+'\n'+(ROOT/'140-cc-link.fth').read_text()+word('a',call_start)+word('b',provider)+word('out',OUT/'plain-link')+'lnk-init a lnk-add-object b lnk-add-object create e s, _start e [lit] 6 lnk-entry out lnk-link\n'
run('plain-object-baseline',plain);objlinked=link('objects-with-archive-layer',[call_start,provider]);assert objlinked.read_bytes()==(OUT/'plain-link').read_bytes()
repeat_write=LINKER+ASSERT+word('obj',provider)+word('one',OUT/'repeat-write-one.a')+word('two',OUT/'repeat-write-two.a')+word('extra',bar)+word('three',OUT/'repeat-write-three.a')+'''
arc-init obj arc-add-object one arc-write two arc-write extra arc-add-object three arc-write arc-init lnk-release
'''
run('repeat-writer-session',repeat_write)
assert (OUT/'repeat-write-one.a').read_bytes()==basebytes==(OUT/'repeat-write-two.a').read_bytes()
check('extended-writer-session',(OUT/'repeat-write-three.a').read_bytes())
assert len(members((OUT/'repeat-write-three.a').read_bytes()))==3

# Forth archive emission copies every payload and pads an odd-sized valid object.
oddobj=OUT/'odd-object.o';oddobj.write_bytes(provider.read_bytes()+b'X')
oddlib=archive('writer-odd-member.a',[oddobj]);raw=oddlib.read_bytes();row=members(raw)[-1]
assert raw[row[2]:row[2]+row[3]]==oddobj.read_bytes() and raw[-1:]==b'\n'
check('writer-odd-member-parse',raw);link('writer-odd-member-link',[demand,oddlib],count=2)
for lib,originals in ((combo_lib,[combo]),(longlib,[short15,long16,long]),(reverse,[bar,chain,unused,provider])):
    for obj in originals:
        p=subprocess.run(['ar','p',lib,obj.name],capture_output=True)
        assert p.returncode==0 and p.stdout==obj.read_bytes(),(lib,obj,'payload changed')

# Writer validation must not publish names its own reader would reject.
def unnamed(path, filename):
    data=bytearray(path.read_bytes()); shoff=struct.unpack_from('<Q',data,40)[0]
    symoff=struct.unpack_from('<Q',data,shoff+7*64+24)[0]
    struct.pack_into('<I',data,symoff+24,0)
    target=OUT/filename;target.write_bytes(data);return target
archive('empty-global-definition',[unnamed(provider,'empty-defined.o')],250,destination=prior)
archive('empty-global-undefined',[unnamed(strong_demand,'empty-undefined.o')],250,destination=prior)
for filename in ('__.SYMDEF', '__.SYMDEF_64'):
    reserved=OUT/filename;reserved.write_bytes(provider.read_bytes())
    archive('reserved-writer-'+filename,[reserved],250,destination=prior)
allowed=OUT/'__.SYMDEFordinary.o';allowed.write_bytes(provider.read_bytes())
allowedlib=archive('ordinary-reserved-prefix.a',[allowed])
check('ordinary-reserved-prefix-parse',allowedlib.read_bytes())
link('ordinary-reserved-prefix-link',[demand,allowedlib],count=2)

# The documented lifecycle permits reading after a writer collection.
transition=LINKER+ASSERT+word('obj',provider)+word('lib',base)+'''
arc-init obj arc-add-object variable old-writer-map [lit] 0 arc-member @ old-writer-map !
lib arc-check create resident [lit] 1 allot
old-writer-map @ [lit] 4096 resident [lit] 0 [lit] 0 [lit] 0 [lit] 27 syscall6 [lit] 0 [lit] 12 - = review-assert
arc-init lnk-release
'''
run('writer-to-reader-release',transition)
link('unselected-archive-output-alias',[start,base],255,destination=base)
# Writer member capacity, including maximum supported envelope and next rejection.
maxlib=archive('member-limit.a',[provider]*256)
check('reader-member-limit',maxlib.read_bytes())
link('member-limit-selection',[demand,maxlib],count=2)
archive('writer-member-over-limit',[provider]*257,251,destination=prior)
last=members(maxlib.read_bytes())[-1]; raw=maxlib.read_bytes()
check('reader-member-over-limit',raw+raw[last[0]:],251)
# Duplicate special tables and unsupported 64-bit symbol index are rejected.
rows=members(basebytes);ir=rows[0]
check('duplicate-symbol-index',basebytes+basebytes[ir[0]:ir[2]+ir[3]+ir[3]%2],250)
mutate('index64-unsupported',basebytes,8,b'/SYM64/         ')
raw=longbytes;lr=next(r for r in members(raw) if r[1]==b'//')
check('duplicate-long-table',raw+raw[lr[0]:lr[2]+lr[3]+lr[3]%2],250)
# Forced extraction of another name still registers duplicate/strong-over-weak definitions.
extra=build_object('extra-provider.o',[('foo',1,1),('bar',1,1)])
extraweak=build_object('extra-weak-provider.o',[('foo',2,1),('bar',1,1)])
bar_demand=build_object('bar-demand.o',[],[('bar',1)])
extra_lib=archive('extra-provider.a',[extra])
extraweak_lib=archive('extra-weak-provider.a',[extraweak])
link('selected-strong-duplicate',[demand,provider,bar_demand,extra_lib],252)
oracle('selected-strong-duplicate',[demand,provider,bar_demand,extra_lib],252)
link('selected-strong-replaces-weak',[demand,weak,bar_demand,extra_lib],count=4)
oracle('selected-strong-replaces-weak',[demand,weak,bar_demand,extra_lib])
link('selected-weak-keeps-strong',[demand,provider,bar_demand,extraweak_lib],count=4)
oracle('selected-weak-keeps-strong',[demand,provider,bar_demand,extraweak_lib])
# Refactoring 140 preserves byte identity against the tracked pre-archive source.
old140=subprocess.run(['git','show','f6777bf6b657cbd10601f52d482891959da3a05f:140-cc-link.fth'],cwd=ROOT,capture_output=True,check=True).stdout
oldplain=BASE+'\n'+old140.decode()+word('a',call_start)+word('b',provider)+word('out',OUT/'pre-archive-object-link')+'lnk-init a lnk-add-object b lnk-add-object create e s, _start e [lit] 6 lnk-entry out lnk-link\n'
run('pre-archive-object-baseline',oldplain)
assert objlinked.read_bytes()==(OUT/'pre-archive-object-link').read_bytes()
BASELINE_HASH=hashlib.sha256(old140).hexdigest()
assert BASELINE_HASH=='9be639f99a6ffeef31baf456e3db765f83c9dd75c54054904c340febe81d84f8'

# Freeze exact evidence, including assertions that inspection did not alter input layers.
assert HASHES=={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in HASHES},'source changed during review'
result=dict(fixture_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),book44_sha256=hashlib.sha256((ROOT/'book/44-direct-gcc-archives.md').read_bytes()).hexdigest(),baseline_revision='f6777bf6b657cbd10601f52d482891959da3a05f',baseline_140_sha256=BASELINE_HASH,root=str(ROOT),output=str(OUT),hashes=HASHES,checks=CHECKS,failures=FAILURES)
(OUT/'results.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(dict(output=str(OUT),checks=len(CHECKS),failures=FAILURES),indent=2))
raise SystemExit(bool(FAILURES))
