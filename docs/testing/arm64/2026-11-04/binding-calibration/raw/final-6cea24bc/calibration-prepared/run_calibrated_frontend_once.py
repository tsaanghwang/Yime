"""Prepared 6cea24bc workflow. Default is read-only installed validation.

--run consumes an exclusive once-only guard, saves the user's measured 57.5mm
baseline, then runs the already-proved private-Job 18-check controller once.
Its normal-runtime restoration is observed even when host acceptance fails.
No install, registration, default-profile change, or physical acceptance.
"""
import argparse
import ctypes
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import time
import traceback

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
GENERATED = ROOT / '.generated'
SOURCE = '6cea24bc665a4ded31e083a42bebd5d2d039832d'
MANIFEST = '572f66e68ad91effbdc994c6fbe1ca71a705d7ee4c5194b10d41447480ad83f3'
INSTALL = Path(r'C:\Program Files\YimeCore 18u Touch')
TEMPLATE = HERE/'frontend-checkpoints.template.json'
CONTROLLER = HERE/'run_installed_frontend_checkpoints.py'
CAPTURE = HERE/'capture_installed_frontend_identity.py'
GUARD = HERE/'run-once.guard'
EXPECTED_USER = 'S-1-5-21-2466658430-60932705-3086004269-1001'

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def module():
    spec = importlib.util.spec_from_file_location('fixed_frontend_controller', CONTROLLER)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

def checked_capture(pid, output, label):
    args = [sys.executable, '-B', '-X', 'utf8', str(CAPTURE), '--runtime-pid', str(pid), '--output', str(output/label), '--template', str(TEMPLATE), '--wait-seconds', '120']
    completed = subprocess.run(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, creationflags=subprocess.CREATE_NO_WINDOW)
    (output/(label+'.stdout.log')).write_bytes(completed.stdout)
    (output/(label+'.stderr.log')).write_bytes(completed.stderr)
    if completed.returncode:
        raise RuntimeError(label+' identity capture failed; no automatic retry')
    return json.loads((output/label/'config.json').read_text(encoding='utf-8'))

def check_calibration(result, own, m):
    if result.get('status') != 'saved-for-next-start' or result.get('physicalAcceptance') is not False or result.get('liveProcessUnchanged') is not True:
        raise ValueError('calibration command did not confirm its limited save operation')
    r = result['measurement']
    if r['schema'] != 'yimecore-18u-display-calibration-v1' or r['widthPixels'] != 3840 or r['heightPixels'] != 2400 or r['baselineScreenWidthMM'] != 597.73 or r['referenceMM'] != 100 or r['observedMM'] != 57.5 or r['measurementSource'] != 'physical-ruler' or not r['monitorDevice'] or not r['monitorInterfaceID']:
        raise ValueError('saved measurement/display differs from the user-reported ASUS baseline')
    expected_ppm = 3840/597.73*100/57.5
    if not math.isclose(result['calibratedPixelsPerMM'], expected_ppm, rel_tol=0, abs_tol=1e-10) or result['keyboardBodyWidthPixels'] != 3832 or result['outerMarginPixels'] != 4 or result['windowWidthPixels'] != 3840 or result['referencePixels'] != 1117:
        raise ValueError('calibration did not preserve the exact body and compact outer margin')
    directory = Path(os.environ['LOCALAPPDATA'])/'YimeCore 18u Touch'/'display-calibration'
    expected_name = hashlib.sha256((r['monitorDevice']+'\0'+r['monitorInterfaceID']).encode('utf-8')).hexdigest()+'.json'
    path = Path(result['configurationPath'])
    if path != directory/expected_name or path.resolve().parent != directory.resolve():
        raise ValueError('calibration settings escaped the existing product user-state directory')
    file_sha = m.digest(path)  # Also rejects reparse components.
    if json.loads(path.read_text(encoding='utf-8')) != r:
        raise ValueError('saved calibration readback differs from command output')
    return {'path': str(path), 'sha256': file_sha, 'measurement': r, 'physicalAcceptance': False}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime-pid', required=True, type=int, help='ordinary-parent runtime PID from this new installation')
    parser.add_argument('--output', type=Path, help='fresh worktree .generated directory; defaults to a fixed preflight/run directory')
    parser.add_argument('--run', action='store_true')
    args = parser.parse_args()
    if args.runtime_pid <= 0:
        raise ValueError('a real post-install runtime PID is required')
    plan = json.loads((HERE/'prepared-plan.json').read_text(encoding='utf-8'))
    if plan['sourceCommit'] != SOURCE or plan['manifestSHA256'] != MANIFEST:
        raise ValueError('prepared plan identity changed')
    for row in plan['files']:
        if sha(HERE/row['path']) != row['sha256']:
            raise ValueError('prepared source changed: '+row['path'])
    cfg = json.loads(TEMPLATE.read_text(encoding='utf-8'))
    if cfg['manifestSHA256'] != MANIFEST or cfg['sourceCommit'] != SOURCE or Path(cfg['installRoot']) != INSTALL or cfg['runningProcesses']:
        raise ValueError('template must be the new manifest with no invented PIDs')
    output = (args.output or GENERATED/('asus-18u-installed-6cea24bc-'+('run' if args.run else 'preflight'))).resolve()
    if output == GENERATED or not output.is_relative_to(GENERATED) or output.exists():
        raise ValueError('a new worktree .generated output directory is required')
    m = module()
    own = m.observe(os.getpid())
    m.same_token(own, own['token'])
    if own['token']['sid'] != EXPECTED_USER:
        raise ValueError('run outside the sandbox as the identified ordinary desktop user; no elevated UAC token')
    output.mkdir(parents=True)
    result = {'sourceCommit': SOURCE, 'manifestSHA256': MANIFEST, 'packageVersion': '0.2.0-18u-arm64.4', 'controller': own, 'runRequested': args.run, 'physicalAcceptance': False, 'registrationChanged': False, 'defaultProfileChanged': False, 'scriptSHA256': sha(__file__), 'planSHA256': sha(HERE/'prepared-plan.json'), 'checkpoints': 0}
    failure = None
    controller_started = False
    try:
        cfg = checked_capture(args.runtime_pid, output, 'initial-identity')
        root, rows, token, held = m.validate(cfg)
        for handle in held:
            m.close(handle)
        result['initialProcesses'] = cfg['runningProcesses']
        installer_receipt = GENERATED/'complete-input-install/asus-18u-6cea24bc/install-result.json'
        if installer_receipt.exists():
            installed = json.loads(installer_receipt.read_text(encoding='utf-8'))
            runtime = next(p for p in cfg['runningProcesses'] if p['relative'] == 'bin/Yime18uInstalledRuntime.exe')
            if installed.get('runtimePID') != runtime['pid'] or installed.get('runtimeCreationTicks') != runtime['creationTicks'] or Path(installed.get('runtimeImage', '')) != INSTALL/'bin/Yime18uInstalledRuntime.exe':
                raise ValueError('installer receipt does not identify the captured normal runtime')
            result['installerReceiptSHA256'] = sha(installer_receipt)
        if not args.run:
            result['readOnlyValidated'] = True
            return
        # Exclusive guard is intentionally never deleted, including on failure.
        # A different output directory must not cause an automatic reattempt.
        with GUARD.open('x', encoding='utf-8') as marker:
            marker.write(json.dumps({'sourceCommit': SOURCE, 'manifestSHA256': MANIFEST, 'output': str(output), 'runtimePID': args.runtime_pid, 'scriptSHA256': sha(__file__), 'createdUTC': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())})+'\n')
            marker.flush()
            os.fsync(marker.fileno())
        result['onceGuard'] = str(GUARD)
        prior_settings = Path(os.environ['LOCALAPPDATA'])/'YimeCore 18u Touch'/'display-calibration'
        result['priorCalibrationFiles'] = []
        if prior_settings.exists():
            (output/'calibration-before').mkdir()
            for path in sorted(prior_settings.glob('*.json')):
                file_sha = m.digest(path)
                if path.stat().st_size > 8192:
                    raise ValueError('unexpected oversized prior calibration file')
                data = path.read_bytes()
                (output/'calibration-before'/path.name).write_bytes(data)
                result['priorCalibrationFiles'].append({'path': str(path), 'sha256': file_sha, 'bytes': len(data)})
        gui = INSTALL/'bin/YimeTouchKeyboard.exe'
        command = [str(gui), '--installed-tsf', '--install-root', str(INSTALL), '--manifest-sha256', MANIFEST, '--save-ruler-observed-mm', '57.5']
        saver = subprocess.Popen(command, cwd=INSTALL, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            seen = m.observe(saver.pid, int(saver._handle))
            m.same_token(seen, own['token'])
            if Path(seen['image']) != gui or m.digest(gui) != rows['bin/yimetouchkeyboard.exe']:
                raise ValueError('calibration saver identity changed')
            result['calibrationSaver'] = seen
            stdout, stderr = saver.communicate(timeout=30)
        except BaseException:
            if saver.poll() is None:
                saver.kill()
            stdout, stderr = saver.communicate()
            (output/'calibration.stdout.log').write_bytes(stdout)
            (output/'calibration.stderr.log').write_bytes(stderr)
            raise
        (output/'calibration.stdout.log').write_bytes(stdout)
        (output/'calibration.stderr.log').write_bytes(stderr)
        result['calibrationExitCode'] = saver.returncode
        if saver.returncode:
            raise RuntimeError('calibration save failed; no retry or runtime stop')
        result['calibration'] = check_calibration(json.loads(stdout.decode('utf-8')), own, m)
        # Saving must leave all three original processes and payloads intact.
        _, _, _, held = m.validate(cfg)
        for handle in held:
            m.close(handle)
        with (output/'checkpoints-controller.stdout.log').open('wb') as log, (output/'checkpoints-controller.stderr.log').open('wb') as error:
            controller_started = True
            completed = subprocess.run([sys.executable, '-B', '-X', 'utf8', str(CONTROLLER), '--config', str(output/'initial-identity/config.json'), '--output', str(output/'checkpoints'), '--run'], stdin=subprocess.DEVNULL, stdout=log, stderr=error, creationflags=subprocess.CREATE_NO_WINDOW)
        result['checkpointsControllerExitCode'] = completed.returncode
        if completed.returncode:
            raise RuntimeError('18-check controller failed; preserve raw evidence and do not replay')
    except BaseException as error:
        failure = error
        result['error'] = str(error)
        (output/'failure.txt').write_text(traceback.format_exc(), encoding='utf-8')
    finally:
        if controller_started:
            try:
                receipt_path = output/'checkpoints/receipt.json'
                if receipt_path.exists():
                    receipt = json.loads(receipt_path.read_text(encoding='utf-8'))
                    if not isinstance(receipt, dict):
                        raise ValueError('inner checkpoint receipt must be an object')
                    result['checkpointReceiptSHA256'] = sha(receipt_path)
                    result['checkpoints'] = receipt.get('checkpoints', 0)
                    result['testJobEmptyBeforeRestore'] = receipt.get('testJobEmptyBeforeRestore', False)
                    result['restorationAttemptedByInnerControllerOnly'] = True
                    restored = receipt.get('restoredRuntime')
                    if restored:
                        if not isinstance(restored, dict) or type(restored.get('pid')) is not int or restored['pid'] <= 0 or type(restored.get('creationTicks')) is not int:
                            raise ValueError('restored runtime receipt lacks a real PID/creation-time anchor')
                        try:
                            final_cfg = checked_capture(restored['pid'], output, 'restored-identity')
                            runtime = next(p for p in final_cfg['runningProcesses'] if p['relative'] == 'bin/Yime18uInstalledRuntime.exe')
                            if runtime['creationTicks'] != restored['creationTicks']:
                                raise ValueError('restored runtime PID reused before final capture')
                            result['restoredProcesses'] = final_cfg['runningProcesses']
                        except BaseException as error:
                            result['restorationObservationError'] = str(error)
                            failure = failure or error
                    else:
                        failure = failure or RuntimeError('no restored normal runtime receipt; no outer retry was attempted')
                    if result['checkpoints'] != 18 or result['testJobEmptyBeforeRestore'] is not True:
                        failure = failure or RuntimeError('18 real readbacks and empty private Job were not both proved')
                else:
                    failure = failure or RuntimeError('inner controller did not produce a receipt; no outer restore or replay attempted')
            except BaseException as error:
                # Even a truncated/malformed inner receipt must preserve this
                # outer first-attempt result and its exclusive guard evidence.
                result['restorationObservationError'] = str(error)
                failure = failure or error
        if result.get('calibration'):
            try:
                if m.digest(result['calibration']['path']) != result['calibration']['sha256']:
                    raise ValueError('calibration file changed after save')
            except BaseException as error:
                failure = failure or error
        result['ok'] = failure is None
        if failure is not None:
            result.setdefault('error', str(failure))
        save(output/'receipt.json', result)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    if failure is not None:
        raise SystemExit(1)

if __name__ == '__main__':
    main()
