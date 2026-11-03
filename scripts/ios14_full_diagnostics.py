#!/usr/bin/env python3
"""Type-check every app source in one compiler invocation, without fail-fast build jobs."""
from pathlib import Path
import json, re, shlex, subprocess
log = Path('logs/build.log').read_text(errors='replace')
lines = [x for x in log.splitlines() if 'builtin-SwiftDriver -- ' in x and '-module-name Minis ' in x]
if not lines:
    raise SystemExit('No Minis compiler invocation found; inspect dependency failure first')
args = shlex.split(lines[-1].split('builtin-SwiftDriver -- ', 1)[1])
drop = {'-c', '-incremental', '-enable-batch-mode', '-save-temps',
        '-use-frontend-parseable-output', '-serialize-diagnostics', '-emit-dependencies',
        '-emit-module', '-emit-objc-header', '-emit-localized-strings', '-emit-const-values',
        '-experimental-emit-module-separately', '-profile-coverage-mapping', '-profile-generate'}
pairs = {'-output-file-map', '-emit-module-path', '-emit-objc-header-path',
         '-emit-localized-strings-path', '-index-store-path', '-num-threads', '-j', '-o'}
clean = []
i = 0
while i < len(args):
    a = args[i]
    if a == '-Xfrontend' and i + 1 < len(args) and args[i+1] == '-const-gather-protocols-file':
        i += 4
        continue
    if a == '-Xfrontend' and i + 1 < len(args) and args[i+1] == '-serialize-debugging-options':
        i += 2
        continue
    if a in pairs:
        i += 2
        continue
    if a in drop or re.fullmatch(r'-j\d+', a):
        i += 1
        continue
    clean.append(a)
    i += 1
clean += ['-typecheck', '-whole-module-optimization', '-continue-building-after-errors', '-suppress-warnings']
Path('logs/full-typecheck-command.json').write_text(json.dumps(clean, indent=2))
filelists = [Path(a[1:]) for a in clean if a.startswith('@')]
count = sum(len(p.read_text().splitlines()) for p in filelists)
print(f'FULL COMPATIBILITY AUDIT: checking all {count} app source files together', flush=True)
assert count > 100, 'Expected the complete app target, not a compatibility-only check'
with Path('logs/full-typecheck.log').open('w') as f:
    result = subprocess.run(clean, stdout=f, stderr=subprocess.STDOUT, timeout=5400)
text = Path('logs/full-typecheck.log').read_text(errors='replace')
errors = []
seen = set()
for line in text.splitlines():
    if 'error:' not in line or line in seen:
        continue
    seen.add(line)
    errors.append(line)
Path('logs/compatibility-errors.json').write_text(json.dumps(
    {'source_files': count, 'compiler_exit_code': result.returncode, 'errors': errors}, indent=2))
report = f'# Full iOS 14.3 compatibility audit\n\nSources checked: {count}\n\nCompiler exit: {result.returncode}\n\n'
report += '\n'.join('- ' + x for x in errors) + '\n'
Path('logs/compatibility-errors.md').write_text(report)
print(report, flush=True)
if result.returncode != 0 and not errors:
    print(text[-15000:], flush=True)
