#!/usr/bin/env python3
"""Source/design guardrails. Not a sandbox, native test suite or complete secret scanner."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def path_errors(paths, config):
    errors = []
    for raw in paths:
        p = Path(raw)
        if p.suffix.lower() in config['forbidden_tracked_extensions']:
            errors.append('Forbidden tracked build/signing file: ' + raw)
        if any(part in config['forbidden_directory_segments'] for part in p.parts):
            errors.append('Forbidden tracked generated directory: ' + raw)
    return errors


def dag_errors(tasks, roles):
    errors, seen, active = [], set(), set()
    by_id = {t['id']: t for t in tasks}
    if len(by_id) != len(tasks):
        errors.append('Duplicate task ID')
    for task in tasks:
        if task['role'] not in roles:
            errors.append('Unknown role: ' + task['role'])
        for dep in task['depends_on']:
            if dep not in by_id:
                errors.append('Unknown dependency: ' + dep)
    def visit(key):
        if key in active:
            errors.append('Task dependency cycle: ' + key)
            return
        if key in seen or key not in by_id:
            return
        active.add(key)
        for dep in by_id[key]['depends_on']:
            visit(dep)
        active.remove(key)
        seen.add(key)
    for key in by_id:
        visit(key)
    return errors


def release_errors(approval, evidence, revision, required):
    errors = []
    if approval.get('status') != 'approved' or not approval.get('decision_reference'):
        errors.append('Product/design approval is pending or lacks actual decision reference')
    if evidence.get('source_revision') != revision:
        errors.append('Release evidence does not match current source revision')
    checks = {x.get('name'): x for x in evidence.get('checks', [])}
    for name in required:
        check = checks.get(name, {})
        if check.get('result') != 'passed' or not check.get('evidence_reference'):
            errors.append('Missing passed release evidence: ' + name)
    return errors


def tracked_paths(root):
    return subprocess.check_output(['git','ls-files','-z'], cwd=root).decode().split('\0')[:-1]


def verify(root=ROOT):
    config = read_json(root / '.harness/guardrails.json')
    dag = read_json(root / '.harness/orchestration.json')
    errors = path_errors(tracked_paths(root), config) + dag_errors(dag['tasks'], dag['roles'])
    feature = root / 'specs/001-native-mail'
    required = ['spec.md','plan.md','tasks.md','research.md','data-model.md','feature-inventory.md','qa-evidence.md','release-runbook.md','contracts/README.md','design/design-system.md','design/tokens.json','design/mockup.html','design/flows.md']
    for item in required:
        if not (feature / item).is_file():
            errors.append('Missing artifact: ' + item)
    tokens_file = feature / 'design/tokens.json'
    if tokens_file.is_file():
        tokens = read_json(tokens_file)
        if tokens.get('touchMin',0) < 48:
            errors.append('Design touch target floor must be at least 48')
        if set(tokens.get('color',{})) != {'light','dark'}:
            errors.append('Both light/dark token themes are required')
    documents = list(feature.rglob('*.md')) + list((root/'docs/adr').glob('*.md'))
    for p in documents:
        text = p.read_text(encoding='utf-8')
        if '[NEEDS CLARIFICATION' in text:
            errors.append('Unresolved specification marker in ' + str(p.relative_to(root)))
        for target in re.findall(r'\]\(([^)]+)\)', text):
            if '://' in target or target.startswith('#'):
                continue
            target = target.split('#')[0].strip('<>')
            if target and not (p.parent / target).exists():
                errors.append('Broken local link in ' + str(p.relative_to(root)) + ': ' + target)
    # Narrow high-confidence patterns only. Manual review / a dedicated scanner remains necessary.
    secret = re.compile(r'(?:gh[pousr]_[A-Za-z0-9]{36,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)')
    for raw in tracked_paths(root):
        p = root / raw
        if p.is_file() and p.stat().st_size < 2_000_000:
            try:
                if secret.search(p.read_text(encoding='utf-8')):
                    errors.append('Potential secret material in ' + raw)
            except UnicodeDecodeError:
                pass
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command',choices=['verify','status','release-check'])
    args = parser.parse_args()
    if args.command == 'status':
        dag = read_json(ROOT/'.harness/orchestration.json')
        approval = read_json(ROOT/'.harness/approval.json')
        print('Phase:',dag['phase'],'| approval:',approval['status'],'| runtime:',dag['runtime']['mode'])
        done = {t['id'] for t in dag['tasks'] if t['status']=='done'}
        for task in dag['tasks']:
            blockers = [d for d in task['depends_on'] if d not in done]
            if task['approval_required'] and approval['status']!='approved':
                blockers.append('product/design approval')
            print(task['id'],task['status'],'BLOCKED: '+', '.join(blockers) if blockers else 'ready for assigned stage')
        return 0
    errors = verify()
    if args.command == 'release-check':
        revision = subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
        errors += release_errors(read_json(ROOT/'.harness/approval.json'),read_json(ROOT/'.harness/evidence.json'),revision,read_json(ROOT/'.harness/guardrails.json')['release_checks'])
        if not (ROOT/'apps/mobile/pubspec.yaml').is_file():
            errors.append('Native mobile application has not been scaffolded')
    for error in errors:
        print('FAIL:',error)
    if not errors:
        print('PASS:',args.command,'(source/design validation only)' if args.command=='verify' else '')
    return 1 if errors else 0

if __name__ == '__main__':
    sys.exit(main())
