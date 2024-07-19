import hashlib
import os
import subprocess

r = ['669066909066906690', 'B801000000', '30']
s = [(0x1F28, 0), (0x48F5, 1), (0x4921, 1), (0x4953, 1), (0x4975, 1), (0x9AC8, 2)]

prefix = '/var/packages/CodecPack/target/usr'
so = prefix + '/lib/libsynoame-license.so'

print("Patching")
with open(so, 'r+b') as fh:
    full = fh.read()
    if hashlib.md5(full).digest().hex() != 'fcc1084f4eadcf5855e6e8494fb79e23':
        print("MD5 mismatch")
        exit(1)
    for x in s:
        fh.seek(x[0] + 0x8000, 0)
        fh.write(bytes.fromhex(r[x[1]]))

lic = '/usr/syno/etc/license/data/ame/offline_license.json'
os.makedirs(os.path.dirname(lic), exist_ok=True)
with open(lic, 'w') as licf:
    licf.write('[{"appType": 14, "appName": "ame", "follow": ["device"], "server_time": 1666000000, "registered_at": 1651000000, "expireTime": 0, "status": "valid", "firstActTime": 1651000001, "extension_gid": null, "licenseCode": "0", "duration": 1576800000, "attribute": {"codec": "hevc", "type": "free"}, "licenseContent": 1}, {"appType": 14, "appName": "ame", "follow": ["device"], "server_time": 1666000000, "registered_at": 1651000000, "expireTime": 0, "status": "valid", "firstActTime": 1651000001, "extension_gid": null, "licenseCode": "0", "duration": 1576800000, "attribute": {"codec": "aac", "type": "free"}, "licenseContent": 1}]')

subprocess.run(['/usr/syno/etc/rc.sysv/apparmor.sh', 'remove_packages_profile', '0', 'CodecPack'])

apparmor = '/var/packages/CodecPack/target/apparmor'
if os.path.exists(apparmor):
    os.rename(apparmor, apparmor + ".bak")

print("Checking whether patch is successful...")
ret = os.system(prefix + "/bin/synoame-bin-check-license")
if ret == 0:
    print("Successful, updating codecs...")
    os.system(prefix + "/bin/synoame-bin-auto-install-needed-codec")
    print("Done")
else:
    print(f"Patch is unsuccessful, retcode = {ret}")