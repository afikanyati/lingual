"""Inventory every Swift source line and validate explicit review decisions against source hashes."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / 'docs/native-source-audit.json'

def inventory(path):
    relative = str(path.relative_to(ROOT))
    source = path.read_bytes()
    lines = source.decode().splitlines()
    parsed = subprocess.run(['swiftc', '-frontend', '-dump-parse', relative], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    declarations = []
    for line in parsed.splitlines():
        match = re.search(r'\((func_decl|constructor_decl|destructor_decl|accessor_decl).*?range=\[.*?:(\d+):\d+ - line:(\d+):\d+\](.*)', line)
        if not match: continue
        start, end = int(match[2]), int(match[3])
        name = re.search(r'"([^"]+)"', match[4])
        declarations.append((start, end, name[1] if name else match[1]))
    # Outer declarations own nested helper bodies; every line has exactly one review owner.
    units = []
    cursor = 1
    for start, end, name in sorted(set(declarations), key=lambda item: (item[0], -item[1])):
        if start < cursor: continue
        if start > cursor: units.append({'start': cursor, 'end': start - 1, 'symbol': 'declarations/comments'})
        units.append({'start': start, 'end': end, 'symbol': name})
        cursor = end + 1
    if cursor <= len(lines): units.append({'start': cursor, 'end': len(lines), 'symbol': 'declarations/comments'})
    for unit in units:
        unit.update(status='unreviewed', react=[], tests=[], decision='')
    return {'path': relative, 'lines': len(lines), 'sha256': hashlib.sha256(source).hexdigest(), 'units': units}

parser = argparse.ArgumentParser()
parser.add_argument('--initialize', action='store_true')
parser.add_argument('--summary', action='store_true')
parser.add_argument('--add-sources', action='store_true')
parser.add_argument('--report', action='store_true')
parser.add_argument('--require-parity', action='store_true')
args = parser.parse_args()
paths = sorted([p for p in ROOT.glob('diction-processor*/**/*.swift') if p.is_file()] + [ROOT / 'native/Package.swift'] + list((ROOT / 'native/Sources').glob('**/*.swift')) + list((ROOT / 'native/Tests').glob('**/*.swift')))
if args.initialize:
    if MANIFEST.exists(): raise SystemExit('Audit exists; preserve review decisions and update deliberately.')
    with ThreadPoolExecutor(max_workers=4) as pool: files = list(pool.map(inventory, paths))
    MANIFEST.write_text(json.dumps({'baseline': 'Recovered working Swift sources; includes prior authorized fixes.', 'files': files}, indent=2) + '\n')
document = json.loads(MANIFEST.read_text())
files = document['files']
if args.add_sources:
    known = {f['path'] for f in files}
    files.extend(inventory(p) for p in paths if str(p.relative_to(ROOT)) not in known)
    files.sort(key=lambda f: f['path'])
    MANIFEST.write_text(json.dumps(document, indent=2) + '\n')
assert {str(p.relative_to(ROOT)) for p in paths} == {f['path'] for f in files}, 'Swift file inventory changed'
counts = {}
for file in files:
    path = ROOT / file['path']
    assert hashlib.sha256(path.read_bytes()).hexdigest() == file['sha256'], f"Re-review changed source: {path}"
    cursor = 1
    for unit in file['units']:
        assert unit['start'] == cursor and unit['end'] >= cursor, f"Overlapping/missing lines: {path}:{cursor}"
        cursor = unit['end'] + 1
        status = unit['status']
        assert status in {'unreviewed', 'implemented', 'adapted', 'inactive', 'native-test', 'gap', 'support'}
        counts[status] = counts.get(status, 0) + unit['end'] - unit['start'] + 1
        if status != 'unreviewed': assert unit['decision'], f"Missing decision: {path}:{unit['start']}"
        if status in {'implemented', 'adapted'}: assert unit['react'], f"Missing React mapping: {path}:{unit['start']}"
        for target in unit['react'] + unit['tests']: assert (ROOT / target.split(':')[0]).exists(), f"Missing target {target}"
    assert cursor == file['lines'] + 1, f"Unaccounted tail: {path}"
print(json.dumps({'files': len(files), 'lines': sum(f['lines'] for f in files), 'lineStatus': counts}))
if args.report:
    report = ['# Swift source review', '',
        'Every source line has one review owner in [native-source-audit.json](native-source-audit.json). The audit validates the file inventory, source hashes, continuous line ranges, decisions and existing React/test targets. It includes blank lines, comments, native scaffolding and inactive experiments. **Review coverage is not feature parity or test coverage.**', '',
        f"Reviewed inventory: {len(files)} Swift files, {sum(f['lines'] for f in files):,} lines. Unreviewed: {counts.get('unreviewed', 0)}. Lines in units with remaining gaps: {counts.get('gap', 0):,}.", '',
        'Status meanings: `adapted` maps behavior to browser APIs with the stated differences; `implemented` has a direct counterpart; `support` is platform/diagnostic infrastructure; `inactive` is an unused experiment or disabled path; `native-test` is test scaffolding; `gap` is incomplete or not yet sufficiently verified.', '',
        'Run `yarn test:source-audit` to detect stale or missing review decisions. `python3 scripts/native-source-audit.py --require-parity` additionally fails while any recorded gap remains. Neither command substitutes for behavioral tests or physical microphone/headphone review.', '',
        '## File inventory', '', '| Swift source | Lines | Gap units |', '| --- | ---: | ---: |']
    for file in files:
        gaps = [u for u in file['units'] if u['status'] == 'gap' and u['symbol'] != 'declarations/comments']
        report.append(f"| [{file['path']}](../{file['path']}) | {file['lines']} | {len(gaps)} |")
    report += ['', '## Remaining gaps', '']
    for file in files:
        gaps = [u for u in file['units'] if u['status'] == 'gap']
        if not gaps: continue
        report += [f"### {file['path']}", '']
        seen = set()
        for unit in gaps:
            decision = unit['decision'].removeprefix(unit['symbol'] + ': ')
            if decision in seen: continue
            seen.add(decision)
            report.append(f"- Lines {unit['start']}–{unit['end']} (`{unit['symbol']}`): {decision}")
        report.append('')
    (ROOT / 'docs/native-source-review.md').write_text('\n'.join(report) + '\n')
if not args.summary and not args.initialize:
    assert not counts.get('unreviewed'), 'Review is incomplete; unreviewed lines must not be called feature parity.'
if args.require_parity:
    assert not counts.get('gap'), 'Recorded behavior gaps remain. Source review alone does not establish feature parity.'
