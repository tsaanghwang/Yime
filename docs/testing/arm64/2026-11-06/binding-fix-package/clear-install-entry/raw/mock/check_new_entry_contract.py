"""Isolated control-flow verification; no native API or maintenance process runs."""
import json
from pathlib import Path
import tempfile
import types

SOURCE = Path("C:/dev/Yime-deliveries/18u-binding-636cef68-20261106/run_18u_binding_install.py")
OUTPUT = Path("C:/dev/Yime/.wt/bindfix/.generated/binding-upgrade-20261106")


def forbidden(*args, **kwargs):
    raise AssertionError("A prohibited branch was entered")


def fixture(name):
    module = types.ModuleType("isolated_local_entry")
    module.__file__ = str(SOURCE)
    exec(compile(SOURCE.read_text(encoding="utf-8"), str(SOURCE), "exec"), module.__dict__)
    module.ROOT = Path(tempfile.mkdtemp(prefix="entry-contract-" + name + "-", dir=OUTPUT))
    module.PACKAGE = module.ROOT / "package"
    module.ATTEMPT = module.ROOT / "attempt.json"
    module.verify_pins = lambda: None
    module.verify_archive = lambda emit: None
    module.require_ordinary_token = forbidden
    module.query_dll_users = forbidden
    calls = {"checks": 0, "installs": 0}

    def check(argv, **kwargs):
        assert argv == [str(module.PACKAGE / "YimeMaintenance.exe"), "-action", "Check"]
        calls["checks"] += 1
        return types.SimpleNamespace(returncode=0)

    module.subprocess = types.SimpleNamespace(run=check, Popen=forbidden, STDOUT=-2)
    return module, calls


passed = []
m, calls = fixture("check")
assert m.main(["--check"]) == 0
assert calls == {"checks": 1, "installs": 0} and not m.ATTEMPT.exists()
report = json.loads(next(m.ROOT.glob("18u-check-*.json")).read_text(encoding="utf-8"))
assert report["restartManagerQueried"] is False and report["installLaunched"] is False
passed.append("--check cannot query tokens, RM, or install")

m, calls = fixture("occupied")
m.require_ordinary_token = lambda: None
m.query_dll_users = lambda: [{"application": "Synthetic host", "pid": 123}]
assert m.main([]) == 3
assert calls == {"checks": 1, "installs": 0} and not m.ATTEMPT.exists()
passed.append("DLL users prevent Install and do not reserve an installation attempt")

m, calls = fixture("rm-error")
m.require_ordinary_token = lambda: None
assert m.main([]) == 1
assert calls == {"checks": 1, "installs": 0} and not m.ATTEMPT.exists()
passed.append("RM failure prevents Install")

m, calls = fixture("check-error")
m.require_ordinary_token = lambda: None
m.subprocess.run = lambda *args, **kwargs: types.SimpleNamespace(returncode=8)
assert m.main([]) == 1 and not m.ATTEMPT.exists()
passed.append("native Check failure prevents RM and Install")

m, calls = fixture("once")
m.require_ordinary_token = lambda: None
m.query_dll_users = lambda: []


class FakeInstaller:
    def __init__(self, argv, **kwargs):
        assert argv == [str(m.PACKAGE / "YimeMaintenance.exe"), "-action", "Install"]
        assert m.ATTEMPT.exists()
        calls["installs"] += 1

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return None

    def wait(self):
        return 1


m.subprocess.Popen = FakeInstaller
assert m.main([]) == 1
assert calls == {"checks": 1, "installs": 1}
assert m.main([]) == 1
assert calls == {"checks": 1, "installs": 1}
passed.append("failed Install preserves atomic marker and a second invocation cannot retry")
print(json.dumps({"passed": passed, "nativeActionsExecuted": False, "liveStateSampled": False}, indent=2))
