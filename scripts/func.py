# -*- coding: utf-8 -*-
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

import os, sys, glob, json, yaml, click, shutil, tarfile, kmodule, requests
from openpyxl import Workbook


@click.group()
def cli():
    """
    The CLI is a commands to RR.
    """
    pass


@cli.command()
@click.option("-w", "--workpath", type=str, required=True, help="The workpath of RR.")
@click.option("-j", "--jsonpath", type=str, required=True, help="The output path of jsonfile.")
@click.option("-x", "--xlsxpath", type=str, required=False, help="The output path of xlsxfile.")
def getmodels(workpath, jsonpath, xlsxpath):

    models = {}
    with open("{}/opt/rr/platforms.yml".format(workpath), "r") as f:
        P_data = yaml.safe_load(f)
        P_platforms = P_data.get("platforms", [])
        for P in P_platforms:
            productvers = {}
            for V in P_platforms[P]["productvers"]:
                if P_platforms[P]["productvers"][V].get("kpre", "") != "":
                    productvers[V] = (P_platforms[P]["productvers"][V].get("kpre", "") + "-" + P_platforms[P]["productvers"][V].get("kver", ""))
                else:
                    productvers[V] = P_platforms[P]["productvers"][V].get("kver", "")
            models[P] = {"productvers": productvers, "models": []}

    req = requests.get("https://autoupdate.synology.com/os/v2")
    req.encoding = "utf-8"
    data = json.loads(req.text)

    for I in data["channel"]["item"]:
        if not I["title"].startswith("DSM"):
            continue
        for J in I["model"]:
            arch = J["mUnique"].split("_")[1].lower()
            name = J["mLink"].split("/")[-1].split("_")[1].replace("%2B", "+")
            if arch not in models.keys():
                continue
            if name in (A for B in models for A in models[B]["models"]):
                continue
            models[arch]["models"].append(name)

    if jsonpath:
        with open(jsonpath, "w") as f:
            json.dump(models, f, indent=4, ensure_ascii=False)
    if xlsxpath:
        wb = Workbook()
        ws = wb.active
        ws.append(["platform", "productvers", "Model"])
        for k, v in models.items():
            ws.append([k, str(v["productvers"]), str(v["models"])])
        wb.save(xlsxpath)

@cli.command()
@click.option("-w", "--workpath", type=str, required=True, help="The workpath of RR.")
@click.option("-j", "--jsonpath", type=str, required=True, help="The output path of jsonfile.")
@click.option("-x", "--xlsxpath", type=str, required=False, help="The output path of xlsxfile.")
def getpats(workpath, jsonpath, xlsxpath):
    def __fullversion(ver):
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

    platforms = []
    models = []
    with open("{}/opt/rr/platforms.yml".format(workpath), "r") as f:
        data = yaml.safe_load(f)
        platforms = data.get("platforms", [])

    req = requests.get("https://autoupdate.synology.com/os/v2")
    req.encoding = "utf-8"
    data = json.loads(req.text)

    for I in data["channel"]["item"]:
        if not I["title"].startswith("DSM"):
            continue
        for J in I["model"]:
            arch = J["mUnique"].split("_")[1].lower()
            name = J["mLink"].split("/")[-1].split("_")[1].replace("%2B", "+")
            if arch not in platforms:
                continue
            if name in models:
                continue
            models.append(name)
    
    pats = {}
    for M in models:
        pats[M] = {}
        version = '7'
        urlInfo = "https://www.synology.com/api/support/findDownloadInfo?lang=en-us"
        urlSteps = "https://www.synology.com/api/support/findUpgradeSteps?"
        #urlInfo = "https://www.synology.cn/api/support/findDownloadInfo?lang=zh-cn"
        #urlSteps = "https://www.synology.cn/api/support/findUpgradeSteps?"

        major = "&major={}".format(version.split('.')[0]) if len(version.split('.')) > 0 else ""
        minor = "&minor={}".format(version.split('.')[1]) if len(version.split('.')) > 1 else ""
        req = requests.get("{}&product={}{}{}".format(urlInfo, M.replace("+", "%2B"), major, minor))
        req.encoding = "utf-8"
        data = json.loads(req.text)

        build_ver = data['info']['system']['detail'][0]['items'][0]['build_ver']
        build_num = data['info']['system']['detail'][0]['items'][0]['build_num']
        buildnano = data['info']['system']['detail'][0]['items'][0]['nano']
        V=__fullversion("{}-{}-{}".format(build_ver, build_num, buildnano))
        if not V in pats[M]:
            pats[M][V]={}
            pats[M][V]['url'] = data['info']['system']['detail'][0]['items'][0]['files'][0]['url'].split('?')[0]
            pats[M][V]['sum'] = data['info']['system']['detail'][0]['items'][0]['files'][0]['checksum']

        from_ver=0
        for I in data['info']['pubVers']:
            if from_ver == 0 or I['build'] < from_ver: from_ver = I['build']

        for I in data['info']['productVers']:
            if not I['version'].startswith(version): continue
            if major == "" or minor == "":
                majorTmp = "&major={}".format(I['version'].split('.')[0]) if len(I['version'].split('.')) > 0 else ""
                minorTmp = "&minor={}".format(I['version'].split('.')[1]) if len(I['version'].split('.')) > 1 else ""
                reqTmp = requests.get("{}&product={}{}{}".format(urlInfo, M.replace("+", "%2B"), majorTmp, minorTmp))
                reqTmp.encoding = "utf-8"
                dataTmp = json.loads(reqTmp.text)

                build_ver = dataTmp['info']['system']['detail'][0]['items'][0]['build_ver']
                build_num = dataTmp['info']['system']['detail'][0]['items'][0]['build_num']
                buildnano = dataTmp['info']['system']['detail'][0]['items'][0]['nano']
                V=__fullversion("{}-{}-{}".format(build_ver, build_num, buildnano))
                if not V in pats[M]:
                    pats[M][V]={}
                    pats[M][V]['url'] = dataTmp['info']['system']['detail'][0]['items'][0]['files'][0]['url'].split('?')[0]
                    pats[M][V]['sum'] = dataTmp['info']['system']['detail'][0]['items'][0]['files'][0]['checksum']

            for J in I['versions']:
                to_ver=J['build']
                reqSteps = requests.get("{}&product={}&from_ver={}&to_ver={}".format(urlSteps, M.replace("+", "%2B"), from_ver, to_ver))
                if reqSteps.status_code != 200: continue
                reqSteps.encoding = "utf-8"
                dataSteps = json.loads(reqSteps.text)
                for S in dataSteps['upgrade_steps']:
                    if not 'full_patch' in S or S['full_patch'] is False: continue
                    if not 'build_ver' in S or not S['build_ver'].startswith(version): continue
                    V=__fullversion("{}-{}-{}".format(S['build_ver'], S['build_num'], S['nano']))
                    if not V in pats[M]:
                        pats[M][V] = {}
                        pats[M][V]['url'] = S['files'][0]['url'].split('?')[0]
                        pats[M][V]['sum'] = S['files'][0]['checksum']

    if jsonpath:
        with open(jsonpath, "w") as f:
            json.dump(pats, f, indent=4, ensure_ascii=False)
    if xlsxpath:
        wb = Workbook()
        ws = wb.active
        ws.append(["Model", "version", "url", "sum"])
        for k1, v1 in pats.items():
            for k2, v2 in v1.items():
                ws.append([k1, k2, v2["url"], v2["sum"]])
        wb.save(xlsxpath)

@cli.command()
@click.option("-w", "--workpath", type=str, required=True, help="The workpath of RR.")
@click.option("-j", "--jsonpath", type=str, required=True, help="The output path of jsonfile.")
@click.option("-x", "--xlsxpath", type=str, required=False, help="The output path of xlsxfile.")
def getaddons(workpath, jsonpath, xlsxpath):
    # Read the manifest.yml file
    AS = glob.glob("{}/mnt/p3/addons/*/manifest.yml".format(workpath))
    AS.sort()
    addons = {}
    for A in AS:
        with open(A, "r") as file:
            A_data = yaml.safe_load(file)
            A_name = A_data.get("name", "")
            A_system = A_data.get("system", False)
            A_description = A_data.get("description", {"en_US": "Unknown", "zh_CN": "Unknown"})
            addons[A_name] = {"system": A_system, "description": A_description}
    if jsonpath:
        with open(jsonpath, "w") as f:
            json.dump(addons, f, indent=4, ensure_ascii=False)
    if xlsxpath:
        wb = Workbook()
        ws = wb.active
        ws.append(["Name", "system", "en_US", "zh_CN"])
        for k1, v1 in addons.items():
            ws.append([k1, v1.get("system", False), v1.get("description").get("en_US", ""), v1.get("description").get("zh_CN", ""),])
        wb.save(xlsxpath)


@cli.command()
@click.option("-w", "--workpath", type=str, required=True, help="The workpath of RR.")
@click.option("-j", "--jsonpath", type=str, required=True, help="The output path of jsonfile.")
@click.option("-x", "--xlsxpath", type=str, required=False, help="The output path of xlsxfile.")
def getmodules(workpath, jsonpath, xlsxpath):
    # Read the module files
    MS = glob.glob("{}/mnt/p3/modules/*.tgz".format(workpath))
    MS.sort()
    modules = {}
    TMP_PATH = "/tmp/modules"
    if os.path.exists(TMP_PATH):
        shutil.rmtree(TMP_PATH)
    for M in MS:
        M_name = os.path.splitext(os.path.basename(M))[0]
        M_modules = {}
        # Extract the module
        os.makedirs(TMP_PATH)
        with tarfile.open(M, "r") as tar:
            tar.extractall(TMP_PATH)
        # Traverse the extracted files
        KS = glob.glob("{}/*.ko".format(TMP_PATH))
        KS.sort()
        for K in KS:
            K_name = os.path.splitext(os.path.basename(K))[0]
            K_info = kmodule.modinfo(K, basedir=os.path.dirname(K), kernel=None)[0]
            K_description = K_info.get("description", "")
            K_depends = K_info.get("depends", "")
            M_modules[K_name] = {"description": K_description, "depends": K_depends}
        modules[M_name] = M_modules
        if os.path.exists(TMP_PATH):
            shutil.rmtree(TMP_PATH)
    if jsonpath:
        with open(jsonpath, "w") as file:
            json.dump(modules, file, indent=4, ensure_ascii=False)
    if xlsxpath:
        wb = Workbook()
        ws = wb.active
        ws.append(["Name", "Arch", "description", "depends"])
        for k1, v1 in modules.items():
            for k2, v2 in v1.items():
                ws.append([k2, k1, v2["description"], v2["depends"]])
        wb.save(xlsxpath)


if __name__ == "__main__":
    cli()
