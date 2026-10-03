#!/usr/bin/env python3
"""Independent literal-splice audit. Host CPP/code is an oracle only."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / 'tools/gcc-direct-cc.py'
BASELINE = ROOT / 'build-out/computed-include-checkpoint-20261003T1752/040-cc-prep.fth'
TOKEN = re.compile(rb'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[A-Za-z_][A-Za-z_0-9]*|[0-9]+|[^\s]', re.S)
BS = b'\\'
SPLICE = BS + b'\n'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def tokens(data):
    return [t for t in TOKEN.findall(data) if not t.startswith((b'/*', b'//'))]


def run(argv, data=None):
    return subprocess.run([str(a) for a in argv], input=data, capture_output=True, timeout=90, cwd=ROOT)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, help='Also write a report to this explicitly selected path')
    parser.add_argument('--baseline', type=Path, help='Frozen preceding 040 layer; a missing explicitly selected file is an error')
    args = parser.parse_args()
    baseline_path = args.baseline if args.baseline is not None else BASELINE
    has_baseline = baseline_path.is_file()
    if args.baseline is not None and not has_baseline:
        parser.error('explicit baseline is not a readable file: '+str(baseline_path))
    if not has_baseline:
        print('SKIP: historical byte-identity comparisons; default frozen 040 baseline is absent', flush=True)
    spec = importlib.util.spec_from_file_location('literal_review_driver', DRIVER)
    driver = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(driver)
    (ROOT/'build-out').mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='review-literal-splice-', dir=ROOT/'build-out'))
    (work/'toolchain').mkdir()
    toolchain = driver.Toolchain(work/'toolchain')
    before = dict(toolchain.inputs)
    if has_baseline:
        before['040-cc-prep.fth'] = baseline_path.read_bytes()
    programs = {label: b'\n'.join(inputs[n] for n in toolchain.compiler) + b'\n'
                for label, inputs in ([('before', before)] if has_baseline else []) + [('after', toolchain.inputs)]}
    script_hash = sha(Path(__file__).read_bytes())
    cases = {
        'string-leading-and-repeated': b'"'+SPLICE+b'A'+SPLICE+SPLICE+b'B" __LINE__\n__LINE__\n',
        'character-after-value': b"'A"+SPLICE+b"' __LINE__\n__LINE__\n",
        'character-before-value': b"'"+SPLICE+b"A' __LINE__\n",
        'empty-string': b'"'+SPLICE+b'" __LINE__\n',
        'adjacent-strings': b'"a'+SPLICE+b'b" "c'+SPLICE+b'd" __LINE__\n',
        'escaped-quote': b'"a'+BS+b'"'+SPLICE+b'b" __LINE__\n',
        'split-hex-escape': b'"'+BS+b'x4'+SPLICE+b'1" __LINE__\n',
        'split-octal-escape': b'"'+BS+b'10'+SPLICE+b'1" __LINE__\n',
        'definition-repeat': b'#define V "a'+SPLICE+b'b"\nV V __LINE__\n',
        'definition-function': b'#define F(x) "a'+SPLICE+b'b",x\nF(7) __LINE__\n',
        'prescan': b'#define ID(x) x\nID("a'+SPLICE+b'b") __LINE__\n__LINE__\n',
        'prescan-nested': b'#define ID(x) x\n#define TWO(x) ID(x),ID(x)\nTWO("a'+SPLICE+b'b") __LINE__\n',
        'prescan-arguments': b'#define BOTH(a,b) b,a,__LINE__\nBOTH("a'+SPLICE+b'b","c'+SPLICE+b'd") __LINE__\n',
        'prescan-unused': b'#define DROP(x) 9\nDROP("a'+SPLICE+b'b") __LINE__\n',
        'stringify': b'#define S(x) #x\nS("a'+SPLICE+b'b") __LINE__\n',
        'stringify-and-expand': b'#define S(x) x,#x,x,#x\nS("a'+SPLICE+b'b") __LINE__\n',
        'stringify-nested': b'#define S(x) #x\n#define X(x) S(x)\nX("a'+SPLICE+b'b") __LINE__\n',
        'stringify-comment-spacing': b'#define S(x) #x\nS(a /* one\n two */ "b'+SPLICE+b'c" d) __LINE__\n',
        'stringify-raw-identifier': b'#define S(x) #x\nS(a'+SPLICE+b'b) __LINE__\n',
        'stringify-trailing-splice': b'#define S(x) #x\nS(a'+SPLICE+b') __LINE__\n',
        'stringify-only-splice': b'#define S(x) #x\nS( '+SPLICE+b' ) __LINE__\n',
        'stringify-edge-splices': b'#define S(x) #x\nS('+SPLICE+b' "a'+SPLICE+b'b" '+SPLICE+b') __LINE__\n',
        'stringify-trailing-comment': b'#define S(x) #x\nS(a /* end */ '+SPLICE+b' ) __LINE__\n',
        'stringify-nested-trailing-splice': b'#define S(x) #x\n#define ID(x) x\nID(S(a'+SPLICE+b')) __LINE__\n',
        'empty-paste-string': b'#define P(a,b) a##b\nP("a'+SPLICE+b'b",) __LINE__\n',
        'wide-prefix-paste': b'#define P(a,b) a##b\nP(L,"a'+SPLICE+b'b") __LINE__\n',
        'escape-through-repeated-splices': b'"a'+BS+SPLICE+SPLICE+b'b" __LINE__\n',
        'character-escape-through-splice': b"'"+BS+SPLICE+b"n' __LINE__\n",
        'skip-branch': b'#if 0\n"a'+SPLICE+b'b"\n#if 1\n"c'+SPLICE+b'd"\n#endif\n#endif\n__LINE__\n',
        'if-character': b"#if 'A"+SPLICE+b"' == 65\nselected __LINE__\n#else\nwrong\n#endif\n__LINE__\n",
        'no-final-newline': b'"a'+SPLICE+b'b"',
    }
    for count in range(1, 7):
        lit = b'"a'+BS*count+b'\nb"'
        cases['slash-run-'+str(count)] = lit+b' __LINE__\n'
        cases['stringify-slash-run-'+str(count)] = b'#define S(x) #x\nS('+lit+b') __LINE__\n'
    for count in (2,4):
        # After phase 2 this is an escaped quote, not the end of the literal.
        cases['splice-makes-escaped-quote-'+str(count)] = b'"a'+BS*count+b'\n"b" __LINE__\n'
    (work/'sub').mkdir()
    (work/'sub/child.h').write_bytes(b'"child'+SPLICE+b'text" __LINE__ __FILE__\n#define CHILD "de'+SPLICE+b'f"\n')
    (work/'parent.h').write_bytes(b'"parent'+SPLICE+b'text" __LINE__ __FILE__\n#define H "sub/chi'+SPLICE+b'ld.h"\n#include H\nCHILD __LINE__ __FILE__\n')
    cases['nested-includes'] = b'#include "parent.h"\n"root'+SPLICE+b'text" CHILD __LINE__ __FILE__\n'
    cases['computed-function-header'] = b'#define ID(x) x\n#include ID("sub/chi'+SPLICE+b'ld.h")\n__LINE__\n'
    cases['computed-stringified-header'] = b'#define S(x) #x\n#include S(sub/chi'+SPLICE+b'ld.h)\n__LINE__\n'
    boundaries = {
        'outside-identifier-splice': b'__LI'+SPLICE+b'NE__\n',
        'direct-header-splice': b'#include "sub/chi'+SPLICE+b'ld.h"\n__LINE__\n',
        'crlf-literal': b'"a'+BS+b'\r\nb" __LINE__\r\n',
    }
    report = {'production_source_sha256': toolchain.hashes,
              'baseline_040_sha256': sha(before['040-cc-prep.fth']) if has_baseline else None,
              'historical_comparison': 'RUN' if has_baseline else 'SKIP: default frozen 040 baseline absent',
              'script_sha256': script_hash, 'work': str(work),
              'scope': 'Literal and raw-stringification LF splicing; generic outside-token phase 2 remains excluded',
              'oracle': 'Host cc -E -P tokens and independent executable values; no host products feed production',
              'cases': [], 'boundaries': [], 'historical': []}

    def preprocess(label, source, path, mode='direct'):
        config = {'direct': 'cc-sysv-object-enable\n[lit] 8388608 cc-arena-map\n',
                  'native': 'true cc-target-lp64 ! true cc-prep-direct !\n[lit] 8388608 cc-arena-map\n',
                  'legacy': ''}[mode]
        config += driver.path_word('review-source', path)
        config += f'review-source [lit] {len(str(path).encode())} cc-prep-source-name\n'
        config += ': review-main cc-load-stdin cc-preprocess [lit] 1 cc-src-buf cc-src-len @ write drop bye ;\nreview-main\n'
        return run([toolchain.seed], programs[label]+config.encode()+source)

    for group, fixtures in [('cases', cases), ('boundaries', boundaries)]:
        for name, source in fixtures.items():
            path = work/(name+'.c'); path.write_bytes(source)
            expected = run(['cc','-E','-P',path])
            entry = {'name': name, 'source_sha256': sha(source), 'oracle_status': expected.returncode,
                     'oracle_stderr': expected.stderr.decode(errors='backslashreplace')}
            (work/(name+'.host.i')).write_bytes(expected.stdout)
            for label in programs:
                actual = preprocess(label, source, path)
                (work/(name+'.'+label+'.i')).write_bytes(actual.stdout)
                entry[label] = {'status': actual.returncode,
                                'tokens_equal_host': actual.returncode == expected.returncode == 0 and tokens(actual.stdout) == tokens(expected.stdout),
                                'stdout': actual.stdout.decode(errors='backslashreplace'),
                                'stderr': actual.stderr.decode(errors='backslashreplace')}
            report[group].append(entry)
            status = 'BOUNDARY' if group == 'boundaries' else ('PASS' if entry['after']['tokens_equal_host'] else 'FAIL')
            print(status+': '+name, flush=True)

    ordinary = b'#define ID(x) x\n#define WORD "a\\tb"\nID(WORD) "escaped\\\"quote" \'\\n\'\n'
    spliced = b'#define ID(x) x\n#define WORD "a'+SPLICE+b'b"\nID(WORD) "c'+SPLICE+b'd" \'A'+SPLICE+b"'\n"
    for mode in ('native','legacy') if has_baseline else ():
        for name, source in [('ordinary',ordinary),('spliced',spliced)]:
            path=work/(mode+'-'+name+'.c');path.write_bytes(source)
            outputs={label:preprocess(label,source,path,mode) for label in ('before','after')}
            expected=run(['cc','-E','-P',path])
            record={'mode':mode,'name':name,'unchanged_bytes':outputs['before'].stdout==outputs['after'].stdout,
                    'matches_host':outputs['after'].returncode==expected.returncode==0 and tokens(outputs['after'].stdout)==tokens(expected.stdout),
                    'after_sha256':sha(outputs['after'].stdout)}
            report['historical'].append(record)
            print('HISTORICAL:',record,flush=True)

    source = work/'execute.c'
    source.write_bytes(b'#include <stdio.h>\n#define S(x) #x\n#define V "a'+SPLICE+b'b"\nint main(void){\nconst char *s=V;\nconst char *t="a'+BS*2+b'\nb";\nconst char *u=S("x'+SPLICE+b'y");\nif(s[0]!=97||s[1]!=98||s[2]!=0)return 1;\nif(t[0]!=97||t[1]!=8||t[2]!=0)return 2;\nif(u[0]!=34||u[1]!=120||u[2]!=121||u[3]!=34||u[4]!=0)return 3;\nif(\'A'+SPLICE+b"'!=65)return 4;\nputs(s);return 0;}\n")
    report['execution'] = {}
    for label, argv in [('host',['cc',source,'-o',work/'host-execute']),('forth',[DRIVER,source,'-o',work/'forth-execute'])]:
        result=run(argv)
        entry={'compile_status':result.returncode,'stderr':result.stderr.decode(errors='backslashreplace')}
        if result.returncode==0:
            result=run([work/(label+'-execute')]);entry.update(status=result.returncode,stdout=result.stdout.decode(errors='backslashreplace'))
        report['execution'][label]=entry
    report['historical_execution'] = []
    for mode in ('native', 'legacy') if has_baseline else ():
        artifacts = []
        for label in ('before', 'after'):
            output=work/(mode+'-'+label+'-execute')
            config='true cc-target-lp64 ! true cc-prep-direct ! [lit] 8388608 cc-arena-map\n' if mode=='native' else ''
            config+=driver.path_word('review-output',output)
            config+=': review-main cc-load-stdin cc-preprocess cc-out-init cc-globals-init cc-emit-elf-header '
            config+=('cc-native-program' if mode=='native' else 'cc-parse-program')
            config+=' cc-finalize-globals cc-finalize-elf review-output cc-write-output bye ;\nreview-main\n'
            body=b'int main(void){char *s="AB"; if(s[0]!=65||s[1]!=66||s[2]!=0)return 1;return 0;}\n'
            result=run([toolchain.seed],programs[label]+config.encode()+body)
            entry={'mode':mode,'label':label,'compile_status':result.returncode,'stderr':result.stderr.decode(errors='backslashreplace')}
            if result.returncode==0:
                output.chmod(0o700);executed=run([output]);artifacts.append(output.read_bytes())
                entry.update(status=executed.returncode,sha256=sha(output.read_bytes()))
            report['historical_execution'].append(entry)
        report['historical_execution'].append({'mode':mode,'ordinary_binary_unchanged':len(artifacts)==2 and artifacts[0]==artifacts[1]})
    report['production_changed_during_review']=[n for n,b in toolchain.inputs.items() if (ROOT/n).read_bytes()!=b]
    failures=[r['name'] for r in report['cases'] if not r['after']['tokens_equal_host']]
    report['failed_cases']=failures
    execution_ok = all(r.get('status')==0 and r.get('compile_status')==0 and r.get('stdout')=='ab\n' for r in report['execution'].values())
    historical_ok = all(r['matches_host'] and (r['name']!='ordinary' or r['unchanged_bytes']) for r in report['historical'])
    historical_execution_ok = all(r.get('ordinary_binary_unchanged',r.get('status')==0 and r.get('compile_status')==0) for r in report['historical_execution'])
    report['status']='PASS' if not failures and execution_ok and historical_ok and historical_execution_ok and not report['production_changed_during_review'] else 'FAIL'
    destination = work/'report.json'
    destination.write_text(json.dumps(report,indent=2)+'\n')
    if args.report:
        args.report.write_text(json.dumps(report,indent=2)+'\n')
    print(report['status'],destination,flush=True)
    print('Retained work:',work,flush=True)
    return 0 if report['status']=='PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
