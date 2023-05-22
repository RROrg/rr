# -*- coding: utf-8 -*-
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
# 
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

import os, re, sys, subprocess, hashlib, requests, json, yaml
import xml.etree.ElementTree as ET
from urllib.parse import urlparse
from bs4 import BeautifulSoup

FILE_PATH = os.path.dirname(os.path.abspath(__file__))

headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3',
    'Referer': 'https://archive.synology.com/download/Os/DSM/',
    'Accept-Language': 'en-US,en;q=0.5'
}

def fullversion(ver):
    out = ver
    arr = ver.split('-')
    if len(arr) > 0:
        a = arr[0].split('.')[0] if len(arr[0].split('.')) > 0 else '0'
        b = arr[0].split('.')[1] if len(arr[0].split('.')) > 1 else '0'
        c = arr[0].split('.')[2] if len(arr[0].split('.')) > 2 else '0'
        d = arr[1] if len(arr) > 1 else '00000'
        e = arr[2] if len(arr) > 2 else '0'
        out = '{}.{}.{}-{}-{}'.format(a,b,c,d,e)
    return out

def sha256sum(file):
    sha256Obj = ''
    if os.path.isfile(file):
        with open(file, "rb") as f:
            sha256Obj = hashlib.sha256(f.read()).hexdigest()
    return sha256Obj

def md5sum(file):
    md5Obj = ''
    if os.path.isfile(file):
        with open(file, "rb") as f:
            md5Obj = hashlib.md5(f.read()).hexdigest()
    return md5Obj

def synoextractor(url):
    data={'url': '', 'hash': '', 'md5-hash': '', 'ramdisk-hash': '', 'zimage-hash': '', 'unique': ''}

    filename = os.path.basename(url)
    filepath = os.path.splitext(filename)[0]

    commands = ['sudo', 'rm', '-rf', filename, filepath]
    result = subprocess.check_output(commands)
    
    # req = requests.get(url.replace(urlparse(url).netloc, 'cndl.synology.cn'))
    req = requests.get(url)
    with open(filename, "wb") as f:
        f.write(req.content)

    # Get the first two bytes of the file and extract the third byte
    output = subprocess.check_output(["od", "-bcN2", filename])
    header = output.decode().splitlines()[0].split()[2]

    if header == '105':
        # print("Uncompressed tar")
        isencrypted = False
    elif header == '213':
        # print("Compressed tar")
        isencrypted = False
    elif header == '255':
        # print("Encrypted")
        isencrypted = True
    else:
        # print("error")
        return data

    os.mkdir(filepath)

    if isencrypted is True:
        TOOL_PATH = os.path.join(FILE_PATH, 'extractor')
        if not os.path.exists(TOOL_PATH):
            commands = ["bash", "-c", ". {}; getExtractor {}".format(os.path.join(FILE_PATH, 'scripts/func.sh'), TOOL_PATH)] 
            result = subprocess.check_output(commands)
        
        commands = ["sudo", "LD_LIBRARY_PATH={}".format(TOOL_PATH), "{}/syno_extract_system_patch".format(TOOL_PATH), filename, filepath] 
        result = subprocess.check_output(commands)
        pass
    else:
        commands = ['tar', '-xf', filename, '-C', filepath]
        result = subprocess.check_output(commands)
    
    if os.path.exists(filename): 
        data['url'] = url
        data['md5-hash'] = md5sum(filename)
        data['hash'] = sha256sum(filename)
        if os.path.exists(os.path.join(filepath, "rd.gz")): data['ramdisk-hash'] = sha256sum(os.path.join(filepath, "rd.gz"))
        if os.path.exists(os.path.join(filepath, "zImage")): data['zimage-hash'] = sha256sum(os.path.join(filepath, "zImage"))
        if os.path.exists(os.path.join(filepath, "VERSION")): 
            with open(os.path.join(filepath, "VERSION"), 'r') as f: 
                for line in f.readlines():
                    if line.startswith('unique'):
                        data['unique'] = line.split('=')[1].replace('"','').strip()


    commands = ['sudo', 'rm', '-rf', filename, filepath]
    result = subprocess.check_output(commands)
    print(data)
    
    return data


def main(isUpdateConfigs = True, isUpdateRss = True):
    # Get models
    models=[]
    
    configs = "files/board/arpl/overlayfs/opt/arpl/model-configs"

    for filename in os.listdir(os.path.join(FILE_PATH, configs)):
        if ".yml" in filename:  # filename.endswith(".yml"):
            models.append(filename.split(".yml")[0])

    print(models)
    
    pats = {}

    # # Get beta pats
    # # 临时对策, RC 64551 目前并没有在 archive.synology.com 上线, beta 又为 64216, 临时用 64216 的地址进行替换.
    # req = requests.get('https://prerelease.synology.com/webapi/models?event=dsm72_beta', headers=headers)
    # rels = json.loads(req.text)
    # if "models" in rels and len(rels["models"]) > 0:
    #     for i in rels["models"]:
    #         if "name" not in i or "dsm" not in i: continue
    #         if i["name"] not in models: continue
    #         if i["name"] not in pats.keys(): pats[i["name"]]={}
    #         pats[i["name"]][fullversion(i["dsm"]["version"]).replace('64216','64551')] = i["dsm"]["url"].split('?')[0].replace('beta','release').replace('64216','64551')

    req = requests.get('https://archive.synology.com/download/Os/DSM', headers=headers)
    req.encoding = 'utf-8'
    bs=BeautifulSoup(req.text, 'html.parser')
    p = re.compile(r"(.*?)-(.*?)", re.MULTILINE | re.DOTALL)
    l = bs.find_all('a', string=p)
    for i in l:
        ver = i.attrs['href'].split('/')[-1]
        if not any([ver.startswith('6.2.4'), ver.startswith('7')]): continue
        req = requests.get('https://archive.synology.com{}'.format(i.attrs['href']), headers=headers)
        req.encoding = 'utf-8'
        bs=BeautifulSoup(req.text, 'html.parser')
        p = re.compile(r"^(.*?)_(.*?)_(.*?).pat$", re.MULTILINE | re.DOTALL)
        data = bs.find_all('a', string=p)
        for item in data:
            p = re.compile(r"DSM_(.*?)_(.*?).pat", re.MULTILINE | re.DOTALL)
            rels = p.search(item.attrs['href'])
            if rels != None:
                info = p.search(item.attrs['href']).groups()
                model = info[0].replace('%2B', '+')
                if model not in models: continue
                if model not in pats.keys(): pats[model]={}
                pats[model][fullversion(ver)] = item.attrs['href']
          
    print(json.dumps(pats, indent=4))

    # Update configs, rss.xml, rss.json
    rssxml=None
    rssxml = ET.parse('rsshead.xml')

    rssjson = {}
    with open('rsshead.json', "r", encoding='utf-8') as f:
        rssjson = json.loads(f.read())

    for filename in os.listdir(os.path.join(FILE_PATH, configs)):
        if ".yml" not in filename:  # filename.endswith(".yml"):
            continue
        model = filename.split(".yml")[0]
        
        data = ''
        with open(os.path.join(FILE_PATH, configs, filename), "r", encoding='utf-8') as f:
            data = yaml.load(f, Loader=yaml.BaseLoader)
        try:
            isChange=False
            for ver in data["builds"].keys():
                tmp, url = '0.0.0-00000-0', ''
                for item in pats[model].keys():
                    if str(ver) not in item: continue
                    if item > tmp: tmp, url = item, pats[model][item]
                if url != '':
                    print("[I] {} synoextractor ...".format(url))
                    hashdata = synoextractor(url)
                    if not all(bool(key) for key in hashdata.keys()):
                        print("[E] {} synoextractor error".format(url))
                        return 
                    
                    if isUpdateConfigs is True:
                        isChange = True
                        # config.yml
                        # data["builds"][ver]["pat"] = hashdata  # pyyaml 会修改文件格式
                        # yq -iy '.builds."25556".pat |= {url:"...", hash:"..."}' DS918+.yml  # yq 也会修改文件格式
                        pat = data["builds"][ver]["pat"]
                        if not all(bool(key) for key in pat.keys()):
                            print("[E] {}  builds.{} key error".format(filename, ver))
                            return 
                        commands = ['sed', '-i', 's|{}|{}|; s|{}|{}|; s|{}|{}|; s|{}|{}|; s|{}|{}|'.format(pat["url"], hashdata["url"], pat["hash"], hashdata["hash"], pat["ramdisk-hash"], hashdata["ramdisk-hash"], pat["zimage-hash"], hashdata["zimage-hash"], pat["md5-hash"], hashdata["md5-hash"]), os.path.join(FILE_PATH, configs, filename)]
                        result = subprocess.check_output(commands)

                    if isUpdateRss is True:
                        # rss.xml
                        for n in rssxml.findall('.//item'): 
                            if n.find('.//BuildNum').text  == str(ver):
                                n.append(ET.fromstring("<model>\n<mUnique>{}</mUnique>\n<mLink>{}</mLink>\n<mCheckSum>{}</mCheckSum>\n</model>\n".format(hashdata["unique"], hashdata["url"], hashdata["md5-hash"])))
                        # rss.json
                        for idx in range(len(rssjson["channel"]["item"])):
                            if rssjson["channel"]["item"][idx]["BuildNum"] == int(ver):
                                rssjson["channel"]["item"][idx]["model"].append({"mUnique": hashdata["unique"], "mLink": hashdata["url"], "mCheckSum": hashdata["md5-hash"]})
            # if isUpdateConfigs is True:
            #     # pyyaml 会修改文件格式
            #     if isChange is True:
            #         with open(os.path.join(FILE_PATH, configs, filename), "w", encoding='utf-8') as f:
            #             yaml.dump(data, f, Dumper=yaml.SafeDumper, sort_keys=False)  # 双引号: default_style='"', 
        except:
            pass

    rssxml.write("rss.xml", xml_declaration=True)
    # ET 处理 rss 的后与原有rss会多一个encode
    commands = ['sed', '-i', 's|^<?xml .*\?>$|<?xml version="1.0"?>|', os.path.join(FILE_PATH, 'rss.xml')]
    result = subprocess.check_output(commands)
    # ET 处理 rss 的并不会格式化
    commands = ['xmllint', '--format', 'rss.xml', '-o', 'rss_new.xml']
    result = subprocess.check_output(commands)
    commands = ['mv', 'rss_new.xml', 'rss.xml']
    result = subprocess.check_output(commands)

    with open('rss.json', 'w', encoding='utf-8') as f:
        f.write(json.dumps(rssjson, indent=4))


if __name__ == '__main__':

    isUpdateConfigs = True
    isUpdateRss = True

    if len(sys.argv) >= 2:
        try:
            isUpdateConfigs = bool(int(sys.argv[1]))
        except ValueError:
            isUpdateConfigs = bool(sys.argv[1])

    if len(sys.argv) >= 3:
        try:
            isUpdateRss = bool(int(sys.argv[2]))
        except ValueError:
            isUpdateRss = bool(sys.argv[2])

    main(isUpdateConfigs, isUpdateRss)