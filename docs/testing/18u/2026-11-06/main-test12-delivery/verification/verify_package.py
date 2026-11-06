"""Static test.12 ZIP audit; reuse the unchanged test.11 verification engine.

Only the expected version/archive name and report identity change. All inventory,
CRC, source, resource, PE and v2-pairing checks remain enabled. No payload runs.
"""
import argparse
import importlib.util
import json
from pathlib import Path

ENGINE = (Path(__file__).resolve().parents[3] / '2026-11-04' /
          'auto-focus-test11/verification/verify_package.py')


def load_verifier():
    spec = importlib.util.spec_from_file_location('test11_static_verifier', ENGINE)
    engine = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(engine)
    engine.VERSION = '0.1.0-18u-test.12'
    engine.ZIP_NAME = 'YimeCore-18u-' + engine.VERSION + '-windows-amd64.zip'
    return engine


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('artifact-zip', 'artifact-metadata', 'ci-receipt', 'output'):
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--source-commit', required=True)
    args = parser.parse_args()
    engine = load_verifier()
    report_path = engine.verify(args)
    report = json.loads(report_path.read_bytes())
    report['schema'] = 'installed-18u-test12-download-verification-v1'
    report['verifierEngine'] = report.pop('verifierScript')
    report['verifierScript'] = engine.digest_file(Path(__file__).resolve())
    report['verifierOverrides'] = {'VERSION': engine.VERSION, 'ZIP_NAME': engine.ZIP_NAME}
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(report_path)


if __name__ == '__main__':
    main()
