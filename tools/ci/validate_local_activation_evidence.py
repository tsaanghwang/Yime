"""Offline consistency gate only: never launches programs or authenticates logs."""
import argparse
import json
from pathlib import Path
import re
import sys

SCHEMA='mycomputer-activation-stage1-v1'
SCOPE='mycomputer-registration-activation-only'
FIELDS={'schema','scope','mode','status','stage','code','writesStarted','cleanupVerified','preconditions','prerequisitesSatisfied','actualHostName','threadLanguage','currentLanguage','dllSha256','dllPresent','publisherTrust','brokerEditingVerified','profileActivationApiVerified','actualDllActivationVerified'}
PRECONDITIONS={'nativeX64','hostMatches','hkl0804','tsf0804','elevated','identityAbsent','dllVerified','directTestAbsent'}
MARKER={'stage':'registered-probe/actual-activate-success','kind':'marker','code':0}


def require(condition, reason):
    if not condition: raise ValueError(reason)


def strict_json(text):
    require(isinstance(text,str) and len(text.encode('utf-8'))<=65536,'evidence-size')
    def unique(pairs):
        result={}
        for key,value in pairs:
            require(key not in result,'duplicate-json-key');result[key]=value
        return result
    return json.loads(text,object_pairs_hook=unique,parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite-json')))


def report(text):
    value=strict_json(text)
    require(isinstance(value,dict) and set(value) in (FIELDS,FIELDS|{'diagnostics'}),'report-fields')
    if 'diagnostics' in value:
        d=value['diagnostics']
        require(isinstance(d,dict) and set(d)=={'schema','primaryFailure','cleanupFailures','stages','registryMatch'} and d['schema']=='activation-diagnostics-v1','diagnostic-fields')
        require(d['primaryFailure'] is None and d['cleanupFailures']==[] and d['registryMatch'] is None,'diagnostic-failure')
        require(isinstance(d['stages'],list),'diagnostic-stages')
        for row in d['stages']:
            require(isinstance(row,dict) and set(row)=={'phase','stage','code'} and isinstance(row['phase'],str) and isinstance(row['stage'],str) and type(row['code']) is int and row['code']==0,'diagnostic-stage-failure')
    require(value['schema']==SCHEMA and value['scope']==SCOPE,'report-identity')
    require(value['stage']=='completed' and type(value['code']) is int and value['code']==0,'report-completion')
    require(value['publisherTrust']=='not-established' and value['brokerEditingVerified'] is False and value['actualDllActivationVerified'] is False,'report-claims')
    require(isinstance(value['preconditions'],dict) and set(value['preconditions'])==PRECONDITIONS,'precondition-fields')
    return value


def validate_absence(verify_stdout,verify_stderr,verify_exit):
    require(type(verify_exit) is int and verify_exit==0,'verify-exit')
    verification=report(verify_stdout)
    require(verification['mode']=='verify' and verification['status']=='pass','verify-mode-status')
    require(verification['cleanupVerified'] is True and verification['writesStarted'] is False,'verify-absence')
    require(verification['prerequisitesSatisfied'] is False and verification['profileActivationApiVerified'] is False,'verify-claims')
    require(all(value is None for value in verification['preconditions'].values()),'verify-preconditions')
    for field in ('actualHostName','threadLanguage','currentLanguage','dllSha256','dllPresent'):
        require(verification[field] is None,'verify-uncollected-field')
    require(isinstance(verify_stderr,str) and not verify_stderr.strip(),'verify-stderr')
    return verification


def validate(register_stdout,register_stderr,register_exit,verify_stdout,verify_stderr,verify_exit,expected_dll_sha256):
    require(isinstance(expected_dll_sha256,str) and re.fullmatch('[0-9a-f]{64}',expected_dll_sha256),'expected-dll-sha256')
    require(type(register_exit) is int and register_exit==4 and type(verify_exit) is int and verify_exit==0,'exit-codes')
    registration=report(register_stdout);validate_absence(verify_stdout,verify_stderr,verify_exit)
    require(registration['mode']=='register-once' and registration['status']=='activation-unconfirmed','registration-mode-status')
    for field in ('writesStarted','cleanupVerified','prerequisitesSatisfied','dllPresent','profileActivationApiVerified'):
        require(registration[field] is True,'registration-'+field)
    require(all(value is True for value in registration['preconditions'].values()),'registration-preconditions')
    require(isinstance(registration['actualHostName'],str) and registration['actualHostName'].casefold()=='mycomputer','registration-host')
    for field in ('threadLanguage','currentLanguage'):
        require(type(registration[field]) is int and registration[field]==2052,'registration-language')
    require(registration['dllSha256']==expected_dll_sha256,'registration-dll-hash')
    marker=strict_json(register_stderr)
    require(marker==MARKER and isinstance(marker,dict) and type(marker.get('code')) is int,'unique-actual-dll-marker')
    return {'status':'evidence-consistent','scope':SCOPE,'dllSha256':expected_dll_sha256,
            'actualDllActivationEvidenceConsistent':True,'cleanupEvidenceConsistent':True,
            'sourceAuthenticityVerified':False,'sameInvocationProven':False,
            'publisherTrust':'not-established','brokerEditingVerified':False,'physicalAcceptance':False}


def bounded_read(path):
    with path.open('rb') as stream: data=stream.read(65537)
    require(len(data)<=65536,'evidence-size')
    return data.decode('utf-8-sig')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('register-stdout','register-stderr','verify-stdout','verify-stderr'):
        parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--register-exit',type=int,required=True)
    parser.add_argument('--verify-exit',type=int,required=True)
    parser.add_argument('--expected-dll-sha256',required=True)
    args=parser.parse_args()
    try:
        result=validate(bounded_read(args.register_stdout),bounded_read(args.register_stderr),args.register_exit,
                        bounded_read(args.verify_stdout),bounded_read(args.verify_stderr),args.verify_exit,args.expected_dll_sha256)
    except (OSError,ValueError,UnicodeError) as error:
        print(json.dumps({'status':'rejected','reason':str(error),'sourceAuthenticityVerified':False}));return 1
    print(json.dumps(result));return 0


if __name__=='__main__':sys.exit(main())
