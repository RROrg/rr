# -*- coding: utf-8 -*-
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

import os, sys, glob, json, yaml, click, shutil, tarfile, kmodule
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
    # Read the model-configs files
    MS = glob.glob("{}/opt/rr/model-configs/*.yml".format(workpath))
    models = {}
    for M in MS:
        with open(M, "r") as f:
            M_name = os.path.splitext(os.path.basename(M))[0]
            M_data = yaml.safe_load(f)
            M_platform = M_data.get("platform", "")
            M_productvers = M_data.get("productvers", [])
            productvers = {}
            for P in M_productvers:
                productvers[P] = M_productvers[P].get("kver", "")
            models[M_name] = {"platform": M_platform, "productvers": productvers}

    if jsonpath:
        with open(jsonpath, "w") as f:
            json.dump(models, f, indent=4, ensure_ascii=False)
    if xlsxpath:
        wb = Workbook()
        ws = wb.active
        ws.append(["Model", "platform", "productvers", "kvernelvers"])
        for k1, v1 in models.items():
            for k2, v2 in v1["productvers"].items():
                ws.append([k1, v1["platform"], k2, v2])
        wb.save(xlsxpath)


@cli.command()
@click.option("-w", "--workpath", type=str, required=True, help="The workpath of RR.")
@click.option("-j", "--jsonpath", type=str, required=True, help="The output path of jsonfile.")
@click.option("-x", "--xlsxpath", type=str, required=False, help="The output path of xlsxfile.")
def getaddons(workpath, jsonpath, xlsxpath):
    # Read the manifest.yml file
    AS = glob.glob("{}/mnt/p3/addons/*/manifest.yml".format(workpath))
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
        ws.append(['Name', 'system', 'en_US', 'zh_CN'])
        for k1, v1 in addons.items():
            ws.append([k1, v1.get("system", False), v1.get("description").get("en_US", ""), v1.get("description").get("zh_CN", "")])   
        wb.save(xlsxpath)


@cli.command()
@click.option("-w", "--workpath", type=str, required=True, help="The workpath of RR.")
@click.option("-j", "--jsonpath", type=str, required=True, help="The output path of jsonfile.")
@click.option("-x", "--xlsxpath", type=str, required=False, help="The output path of xlsxfile.")
def getmodules(workpath, jsonpath, xlsxpath):
    # Read the module files
    MS = glob.glob("{}/mnt/p3/modules/*.tgz".format(workpath))
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
        for K in KS:
            K_name = os.path.splitext(os.path.basename(K))[0]
            K_info = kmodule.modinfo(K)[0]
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
