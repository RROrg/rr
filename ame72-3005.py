import hashlib
import os
import subprocess

r = ['669066909066906690', 'B801000000', '30']
s = [(0x3718, 0), (0x60A5, 1), (0x60D1, 1), (0x6111, 1), (0x6137, 1), (0xB5F0, 2)]

prefix = '/var/packages/CodecPack/target/usr'
so = prefix + '/lib/libsynoame-license.so'

print("Patching")
with open(so, 'r+b') as fh:
    full = fh.read()
    if hashlib.md5(full).digest().hex() != '09e3adeafe85b353c9427d93ef0185e9':
        print("MD5 mismatch")
        exit(1)
    for x in s:
        fh.seek(x[0] + 0x8000, 0)
        fh.write(bytes.fromhex(r[x[1]]))

lic = '/usr/syno/etc/license/data/ame/offline_license.json'
os.makedirs(os.path.dirname(lic), exist_ok=True)
with open(lic, 'w') as licf:
    licf.write('[{"attribute": {"codec": "hevc", "type": "free"}, "status": "valid", "extension_gid": null, "expireTime": 0, "appName": "ame", "follow": ["device"], "duration": 1576800000, "appType": 14, "licenseContent": 1, "registered_at": 1649315995, "server_time": 1685421618, "firstActTime": 1649315995, "licenseCode": "0"}, {"attribute": {"codec": "aac", "type": "free"}, "status": "valid", "extension_gid": null, "expireTime": 0, "appName": "ame", "follow": ["device"], "duration": 1576800000, "appType": 14, "licenseContent": 1, "registered_at": 1649315995, "server_time": 1685421618, "firstActTime": 1649315995, "licenseCode": "0"}]')

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