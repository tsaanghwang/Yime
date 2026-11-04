"""Bind only the fixed identity constants; never execute either installer."""
from pathlib import Path
import ast,hashlib,json
ROOT=Path(__file__).resolve().parents[2]
SOURCE='6cea24bc665a4ded31e083a42bebd5d2d039832d'
DIR=ROOT/'.generated/asus-18u-wait-repair-6cea24bc'
OLD=ROOT/'.generated/armfull-tools/install-asus-18u-cb77b675.py'
NEW=ROOT/'.generated/armfull-tools/install-asus-18u-6cea24bc.py'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(OLD)=='15a6a3bbab0dfb980b59b7bac390d807278640d97a2a255b4339569891ea704d'
receipt=read(DIR/'complete-package-receipt.json')
assert receipt['sourceCommit']==SOURCE and receipt['version']=='0.2.0-18u-arm64.4' and receipt['payloadCount']==20
package=DIR/'simple/package';identity_path=DIR/'complete/yime-yimecore-18u-windows-arm64-6cea24bc665a.identity.json'
assert Path(receipt['package'])==package and Path(receipt['identity'])==identity_path
identity=read(identity_path)
assert identity['source']['commit']==SOURCE and identity['source']['clean'] and identity['deliveryState']=='source-frozen'
assert identity['product']=='yimecore-18u' and identity['target']=='windows-arm64' and len(identity['files'])==1156
assert identity['zip']==receipt['zip'] and receipt['zip']['name']=='yime-yimecore-18u-windows-arm64-6cea24bc665a.zip'
assert (DIR/'complete'/receipt['zip']['name']).stat().st_size==receipt['zip']['bytes']
assert read(package/'product-package.json')['version']=='0.2.0-18u-arm64.4'
values={'ZIP_SHA':receipt['zip']['sha256'],'ZIP_BYTES':receipt['zip']['bytes'],'IDENTITY_SHA':sha(identity_path),'IDENTITY_BYTES':identity_path.stat().st_size,
        'PLAN_SHA':receipt['planSHA256'],'HELPER_SHA':receipt['maintenanceSHA256'],'MANIFEST_SHA':receipt['installedManifestSHA256']}
assert sha(package/'maintenance-plan.json')==values['PLAN_SHA'] and sha(package/'YimeMaintenance.exe')==values['HELPER_SHA']
assert sha(package/'payload/installed-18u-product.json')==values['MANIFEST_SHA']
text=NEW.read_text(encoding='utf-8');lines=text.splitlines(keepends=True);tree=ast.parse(text)
for node in reversed(tree.body):
    if isinstance(node,ast.Assign) and len(node.targets)==1 and isinstance(node.targets[0],ast.Name) and node.targets[0].id in values:
        name=node.targets[0].id;assert node.lineno==node.end_lineno
        lines[node.lineno-1]=name+'='+repr(values[name])+'\n'
candidate=''.join(lines)
compile(candidate,str(NEW),'exec')
# Normalize only the requested source/version/output-prefix and identity edits.
old=OLD.read_text(encoding='utf-8')
old=old.replace('cb77b675ff6964c7b069294222200a5060316bd2',SOURCE).replace('cb77b675ff69','6cea24bc665a').replace('asus-18u-race-repair-cb77b675','asus-18u-wait-repair-6cea24bc').replace('18u-race-repair-release-cb77b675','18u-wait-repair-release-6cea24bc').replace('test-arm64-18u-upgrade-cb77b675','test-arm64-18u-wait-6cea24bc').replace('cb77b675','6cea24bc').replace('0.2.0-18u-arm64.3','0.2.0-18u-arm64.4')
def normalized(text):
    tree=ast.parse(text)
    for node in tree.body:
        if isinstance(node,ast.Assign) and len(node.targets)==1 and isinstance(node.targets[0],ast.Name) and node.targets[0].id in values:
            node.value=ast.Constant(value='ALLOWED_FIXED_IDENTITY')
    return ast.dump(tree,include_attributes=False)
assert normalized(old)==normalized(candidate),'Unexpected restoration/installation logic change'
NEW.write_text(candidate,encoding='utf-8')
report={'schema':'fixed-installer-rebind-audit-v1','sourceCommit':SOURCE,'version':'0.2.0-18u-arm64.4','baseInstallerSHA256':sha(OLD),'installer':str(NEW),'installerSHA256':sha(NEW),
        'identityConstants':values,'allowedSourceVersionPrefixAndIdentityChangesOnly':True,'restoreAndSingleInstallLogicUnchanged':True,'compilePassed':True,'mainExecuted':False,'productCalls':0}
destination=ROOT/'.generated/armfull-tools/install-asus-18u-6cea24bc.audit.json'
destination.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,indent=2))
