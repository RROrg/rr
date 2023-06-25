# -*- coding: utf-8 -*-
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

import os, re, sys, subprocess, hashlib, requests, json, yaml
from urllib.parse import urlparse
from bs4 import BeautifulSoup

FILE_PATH = os.path.dirname(os.path.abspath(__file__))

headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3",
    "Referer": "https://archive.synology.com/download/Os/DSM/",
    "Accept-Language": "en-US,en;q=0.5",
}


def fullversion(ver):
    out = ver
    arr = ver.split("-")
    if len(arr) > 0:
        a = arr[0].split(".")[0] if len(arr[0].split(".")) > 0 else "0"
        b = arr[0].split(".")[1] if len(arr[0].split(".")) > 1 else "0"
        c = arr[0].split(".")[2] if len(arr[0].split(".")) > 2 else "0"
        d = arr[1] if len(arr) > 1 else "00000"
        e = arr[2] if len(arr) > 2 else "0"
        out = "{}.{}.{}-{}-{}".format(a, b, c, d, e)
    return out


def md5sum(file):
    md5Obj = ""
    if os.path.isfile(file):
        with open(file, "rb") as f:
            md5Obj = hashlib.md5(f.read()).hexdigest()
    return md5Obj


def getPATmd5sum(url):
    filename = os.path.basename(url)
    os.remove(filename)
    # req = requests.get(url.replace(urlparse(url).netloc, 'cndl.synology.cn'))
    req = requests.get(url)
    with open(filename, "wb") as f:
        f.write(req.content)
    md5 = md5sum(filename)
    os.remove(filename)
    return md5


def main():
    # Get models
    models = []

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

    req = requests.get("https://archive.synology.com/download/Os/DSM", headers=headers)
    req.encoding = "utf-8"
    bs = BeautifulSoup(req.text, "html.parser")
    p = re.compile(r"(.*?)-(.*?)", re.MULTILINE | re.DOTALL)
    l = bs.find_all("a", string=p)
    for i in l:
        ver = i.attrs["href"].split("/")[-1]
        if not any([ver.startswith("6.2.4"), ver.startswith("7")]):
            continue
        req = requests.get(
            "https://archive.synology.com{}".format(i.attrs["href"]), headers=headers
        )
        req.encoding = "utf-8"
        bs = BeautifulSoup(req.text, "html.parser")
        p = re.compile(r"^(.*?)_(.*?)_(.*?).pat$", re.MULTILINE | re.DOTALL)
        data = bs.find_all("a", string=p)
        for item in data:
            p = re.compile(r"DSM_(.*?)_(.*?).pat", re.MULTILINE | re.DOTALL)
            rels = p.search(item.attrs["href"])
            if rels != None:
                info = p.search(item.attrs["href"]).groups()
                model = info[0].replace("%2B", "+")
                if model not in models:
                    continue
                if model not in pats.keys():
                    pats[model] = {}
                pats[model][fullversion(ver)] = item.attrs["href"]

    print(json.dumps(pats, indent=4))

    for filename in os.listdir(os.path.join(FILE_PATH, configs)):
        if ".yml" not in filename:  # filename.endswith(".yml"):
            continue
        model = filename.split(".yml")[0]

        data = ""
        with open(
            os.path.join(FILE_PATH, configs, filename), "r", encoding="utf-8"
        ) as f:
            data = yaml.load(f, Loader=yaml.BaseLoader)
        try:
            isChange = False
            for ver in data["builds"].keys():
                tmp, url = "0.0.0-00000-0", ""
                for item in pats[model].keys():
                    if str(ver) not in item:
                        continue
                    if item > tmp:
                        tmp, url = item, pats[model][item]
                if url != "":
                    print("[I] {} get md5sum ...".format(url))
                    md5 = getPATmd5sum(url)
                    if md5 == "":
                        print("[E] {} get md5sum error".format(url))
                        return

                    isChange = True
                    # config.yml
                    # data["builds"][ver]["pat"] = hashdata  # pyyaml 会修改文件格式
                    # yq -iy '.builds."25556".pat |= {url:"...", hash:"..."}' DS918+.yml  # yq 也会修改文件格式
                    pat = data["builds"][ver]["pat"]
                    if not all(bool(key) for key in pat.keys()):
                        print("[E] {}  builds.{} key error".format(filename, ver))
                        return
                    commands = [
                        "sed",
                        "-i",
                        "s|{}|{}|; s|{}|{}|".format(pat["url"], url, pat["md5"], md5),
                        os.path.join(FILE_PATH, configs, filename),
                    ]
                    result = subprocess.check_output(commands)

            # # pyyaml 会修改文件格式
            # if isChange is True:
            #     with open(os.path.join(FILE_PATH, configs, filename), "w", encoding='utf-8') as f:
            #         yaml.dump(data, f, Dumper=yaml.SafeDumper, sort_keys=False)  # 双引号: default_style='"',
        except:
            pass


if __name__ == "__main__":
    main()
