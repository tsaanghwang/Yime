"""Synthetic offline fixtures; no real activation or trusted source is implied."""
import copy
import json
import unittest
import validate_local_activation_evidence as gate

HASH='a'*64

def fixtures():
    common=dict(schema=gate.SCHEMA,scope=gate.SCOPE,mode='verify',status='pass',stage='completed',code=0,
                writesStarted=False,cleanupVerified=True,preconditions={k:None for k in gate.PRECONDITIONS},
                prerequisitesSatisfied=False,actualHostName=None,threadLanguage=None,currentLanguage=None,
                dllSha256=None,dllPresent=None,publisherTrust='not-established',brokerEditingVerified=False,
                profileActivationApiVerified=False,actualDllActivationVerified=False)
    register=copy.deepcopy(common)
    register.update(mode='register-once',status='activation-unconfirmed',writesStarted=True,
                    preconditions={k:True for k in gate.PRECONDITIONS},prerequisitesSatisfied=True,
                    actualHostName='MyComputer',threadLanguage=2052,currentLanguage=2052,dllSha256=HASH,
                    dllPresent=True,profileActivationApiVerified=True)
    return register,common

class EvidenceTests(unittest.TestCase):
    def validate(self,register=None,verify=None,stderr=None,verify_stderr='',register_exit=4,verify_exit=0,sha=HASH):
        r,v=fixtures()
        return gate.validate(json.dumps(r if register is None else register),json.dumps(gate.MARKER) if stderr is None else stderr,
                             register_exit,json.dumps(v if verify is None else verify),verify_stderr,verify_exit,sha)

    def test_consistent_evidence_does_not_authenticate_source(self):
        result=self.validate()
        self.assertEqual(result['status'],'evidence-consistent')
        for key in ('sourceAuthenticityVerified','sameInvocationProven','brokerEditingVerified','physicalAcceptance'):
            self.assertIs(result[key],False)
        self.assertEqual(result['publisherTrust'],'not-established')

    def test_registration_identity_language_claims_and_unknown_rejected(self):
        r,_=fixtures()
        for field,bad in [('mode','preflight'),('status','pass'),('cleanupVerified',False),('writesStarted',None),
                          ('dllSha256','b'*64),('actualHostName','MSI'),('threadLanguage',1033),('currentLanguage','2052'),
                          ('profileActivationApiVerified',False),('actualDllActivationVerified',True),('publisherTrust','trusted')]:
            changed=copy.deepcopy(r);changed[field]=bad
            with self.subTest(field=field),self.assertRaises(ValueError):self.validate(register=changed)
        for field in gate.PRECONDITIONS:
            changed=copy.deepcopy(r);changed['preconditions'][field]=None
            with self.subTest(precondition=field),self.assertRaises(ValueError):self.validate(register=changed)
        del r['dllSha256']
        with self.assertRaises(ValueError):self.validate(register=r)

    def test_marker_must_be_single_exact_json_without_extra_output(self):
        marker=json.dumps(gate.MARKER)
        for bad in ('',marker+'\n'+marker,'noise\n'+marker,marker[:-1]+',"code":0}',marker.replace('"code": 0','"code": false'),json.dumps({'stage':'registered-probe/actual-activate-success','kind':'marker','code':0,'extra':True})):
            with self.subTest(marker=bad),self.assertRaises(ValueError):self.validate(stderr=bad)

    def test_independent_verify_must_pass_without_mutation(self):
        _,v=fixtures()
        for field,bad in [('mode','register-once'),('status','failed'),('cleanupVerified',None),('writesStarted',True),('dllSha256',HASH)]:
            changed=copy.deepcopy(v);changed[field]=bad
            with self.subTest(field=field),self.assertRaises(ValueError):self.validate(verify=changed)
        for kw in ({'verify_stderr':'unexpected'}, {'register_exit':0}, {'verify_exit':4}, {'register_exit':True}, {'sha':'invalid'}):
            with self.subTest(kw=kw),self.assertRaises(ValueError):self.validate(**kw)

    def test_strict_json_duplicate_nonfinite_and_bound(self):
        for text in ('{"a":1,"a":2}','{"a":NaN}',' '*65537):
            with self.assertRaises(ValueError):gate.strict_json(text)

if __name__=='__main__':unittest.main()
