"""Read Win32 digitizer capability bits only; no UI, input or calibration."""
import argparse
import ctypes as c
from ctypes import wintypes as w
import datetime
import json
import os
from pathlib import Path

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report',required=True,type=Path)
    parser.add_argument('--context',required=True)
    args=parser.parse_args()
    report=args.report.absolute()
    if report.exists(): raise ValueError('fresh report required')
    user=c.WinDLL('user32',use_last_error=True)
    kernel=c.WinDLL('kernel32',use_last_error=True)
    metrics=user.GetSystemMetrics; metrics.argtypes=[c.c_int]; metrics.restype=c.c_int
    flags={'NID_INTEGRATED_TOUCH':1,'NID_EXTERNAL_TOUCH':2,'NID_INTEGRATED_PEN':4,'NID_EXTERNAL_PEN':8,'NID_MULTI_INPUT':64,'NID_READY':128}
    raw=metrics(94)
    session=w.DWORD()
    kernel.ProcessIdToSessionId.argtypes=[w.DWORD,c.POINTER(w.DWORD)]; kernel.ProcessIdToSessionId.restype=w.BOOL
    if not kernel.ProcessIdToSessionId(os.getpid(),c.byref(session)): raise c.WinError(c.get_last_error())
    kernel.GetCurrentProcess.restype=w.HANDLE
    process,native=w.USHORT(),w.USHORT()
    kernel.IsWow64Process2.argtypes=[w.HANDLE,c.POINTER(w.USHORT),c.POINTER(w.USHORT)]; kernel.IsWow64Process2.restype=w.BOOL
    if not kernel.IsWow64Process2(kernel.GetCurrentProcess(),c.byref(process),c.byref(native)): raise c.WinError(c.get_last_error())
    data={'schema':'18u-win32-display-readiness-v1','observedUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
      'computer':os.environ.get('COMPUTERNAME'),'observationContext':args.context,'pid':os.getpid(),'sessionId':session.value,
      'processMachine':hex(process.value),'nativeMachine':hex(native.value),
      'SM_DIGITIZER':{'index':94,'decimal':raw,'hex':hex(raw),'flags':{name:bool(raw&bit) for name,bit in flags.items()},'unknownBits':hex(raw&~sum(flags.values()))},
      'SM_MAXIMUMTOUCHES':{'index':95,'value':metrics(95)},
      'SM_CMONITORS':{'index':80,'value':metrics(80)},'SM_REMOTESESSION':{'index':0x1000,'value':metrics(0x1000)},
      'screenMetricsForThisProcess':{'width':metrics(0),'height':metrics(1),'dpiAwarenessChanged':False,'physicalMeasurement':False},
      'constantSource':'C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/um/WinUser.h:7365,15915',
      'systemReportedCapabilitiesOnly':True,'perMonitorDigitizerMappingEstablished':False,'fingerInputObserved':False,'penInputObserved':False,
      'touchKeyboardAcceptance':False,'calibrationChanged':False,'geometryChanged':False,'uiAutomation':False}
    report.parent.mkdir(parents=True,exist_ok=True)
    report.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(data,indent=2))

if __name__=='__main__': main()
