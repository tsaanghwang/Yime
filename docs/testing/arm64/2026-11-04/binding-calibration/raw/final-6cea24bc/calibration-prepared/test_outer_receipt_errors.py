"""Pure fault injection of the outer finally block; never import/run products."""
import ast
import hashlib
import json
from pathlib import Path

here = Path(__file__).resolve().parent
source = here/'run_calibrated_frontend_once.py'
tree = ast.parse(source.read_text(encoding='utf-8'))
main = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'main')
outer = next(n for n in main.body if isinstance(n, ast.Try))
cleanup = compile(ast.fix_missing_locations(ast.Module(body=outer.finalbody, type_ignores=[])), str(source), 'exec')
base = here/'script-contract-tests'
base.mkdir(exist_ok=False)
cases = {
    'truncated': '{',
    'non-object': '[]',
    'missing-pid': '{"restoredRuntime":{"creationTicks":123}}',
    'missing-creation-time': '{"restoredRuntime":{"pid":123}}',
    'non-object-runtime': '{"restoredRuntime":"invalid"}',
}
passed = []
for name, raw in cases.items():
    output = base/name
    (output/'checkpoints').mkdir(parents=True)
    (output/'checkpoints/receipt.json').write_text(raw, encoding='utf-8')
    first_error = RuntimeError('first host failure must be preserved')
    calls = []
    def no_capture(*args):
        calls.append(args)
        raise AssertionError('malformed receipt must not reach even a process observation')
    namespace = {
        'controller_started': True, 'output': output, 'json': json,
        'sha': lambda p: hashlib.sha256(p.read_bytes()).hexdigest(),
        'checked_capture': no_capture,
        'failure': first_error,
        'result': {'onceGuard': 'retained-exclusive-guard', 'error': str(first_error)},
        'save': lambda p, v: p.write_text(json.dumps(v), encoding='utf-8'),
        'print': lambda *a, **k: None,
    }
    exec(cleanup, namespace)
    result = json.loads((output/'receipt.json').read_text(encoding='utf-8'))
    assert result['ok'] is False and result['error'] == str(first_error)
    assert result['onceGuard'] == 'retained-exclusive-guard'
    assert result['restorationObservationError'] and not calls
    assert namespace['failure'] is first_error
    passed.append(name)
summary = {'passed': passed, 'count': len(passed), 'productExecuted': False, 'installedChanged': False, 'sourceSHA256': hashlib.sha256(source.read_bytes()).hexdigest()}
(base/'summary.json').write_text(json.dumps(summary, indent=2)+'\n', encoding='utf-8')
print(json.dumps(summary))
