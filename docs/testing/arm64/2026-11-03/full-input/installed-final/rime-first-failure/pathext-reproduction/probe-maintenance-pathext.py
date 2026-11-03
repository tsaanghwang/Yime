from pathlib import Path
import json,os,subprocess,sys
root=Path(__file__).resolve().parents[2]
out=root/'.generated/armfull-tools/native-pathext-probe';out.mkdir(exist_ok=False)
stage=Path(r'C:\Program Files\Yime Maintenance\rime-pime\039ad1d05244980b1ee49c2c4e88fd4551134899621eda0b3da462ef327ca4df')
shell=stage/'maintenance/powershell'
assert (shell/'pwsh.exe').is_file()
sysroot=Path(os.environ['SystemRoot'])
env={name:os.environ[name] for name in ('SystemRoot','WINDIR','ProgramFiles','USERPROFILE','LOCALAPPDATA','APPDATA')}
env.update(PATH=str(shell)+';'+str(sysroot/'System32'),TEMP=str(sysroot/'Temp'),TMP=str(sysroot/'Temp'),PSModulePath=str(shell/'Modules')+';'+str(sysroot/'System32/WindowsPowerShell/v1.0/Modules'))
rows=[]
for case,pathext in [('absent',None),('exe-only','.EXE'),('fixed-native-list','.COM;.EXE;.BAT;.CMD')]:
    for architecture,directory in [('arm64','System32'),('x86','SysWOW64')]:
        caseenv=env.copy()
        if pathext is not None:caseenv['PATHEXT']=pathext
        path=str(sysroot/directory/'cmd.exe')
        command="""$ErrorActionPreference='Stop';$env:PATH=Join-Path $env:SystemRoot 'System32'
$r=[ordered]@{shell=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName;version=$PSVersionTable.PSVersion.ToString();architecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString();pathext=$env:PATHEXT;executable='EXEPATH';success=$false;exitCode=$null;errorId=$null}
try { & 'EXEPATH' /d /c 'echo yime-native-exe-probe' | Out-Host; $r.exitCode=$LASTEXITCODE; $r.success=($LASTEXITCODE -eq 0) }
catch {$r.errorId=$_.FullyQualifiedErrorId}
Write-Output ('PROBE_JSON='+($r|ConvertTo-Json -Compress))
""".replace('EXEPATH',path)
        p=subprocess.run([sys.executable,'-B','-X','utf8','tools/powershell/run_checked.py','--edition','ps7','--command',command],cwd=root,env=caseenv,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',timeout=45)
        (out/(case+'-'+architecture+'.log')).write_text(p.stdout,encoding='utf-8')
        encoded=[s[len('PROBE_JSON='):] for s in p.stdout.splitlines() if s.startswith('PROBE_JSON=')]
        assert p.returncode==0 and len(encoded)==1,(case,architecture,p.returncode,p.stdout)
        record=json.loads(encoded[0]);record.update(case=case,executableArchitecture=architecture,entryExit=p.returncode)
        rows.append(record);print(json.dumps(record),flush=True)
        assert record['architecture']=='Arm64'
        if pathext is None:assert not record['success'] and record['errorId']=='CantActivateDocumentInPipeline'
        else:assert record['success'] and record['exitCode']==0 and record['errorId'] is None
report={'scope':'Ordinary-user protected-stage ARM64 PS7 runs only system-owned cmd.exe /d /c echo through the same native pipeline. No package executable, installer, registrar or product maintenance executed. Child environment matches helper allowlist except an initial PSHOME PATH entry used solely by run_checked shell discovery; command immediately resets PATH to System32.','processGlobalEnvironmentChanged':False,'sourceChanged':False,'rows':rows,'conclusion':'Absent PATHEXT reproduces exact CantActivateDocumentInPipeline for both ARM64 and x86 .exe. Fixed .EXE alone suffices for both architectures without user PATHEXT inheritance.'}
(out/'summary.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print('PASS all six controlled PATHEXT cases',flush=True)
