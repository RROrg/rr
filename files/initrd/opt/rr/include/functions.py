# -*- coding: utf-8 -*-
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

import os, click

WORK_PATH = os.path.abspath(os.path.dirname(__file__))


@click.group()
def cli():
    """
    The CLI is a commands to RR.
    """
    pass


def mutually_exclusive_options(ctx, param, value):
    other_option = "file" if param.name == "data" else "data"
    if value is not None and ctx.params.get(other_option) is not None:
        raise click.UsageError(f"Illegal usage: `{param.name}` is mutually exclusive with `{other_option}`.")
    return value


def validate_required_param(ctx, param, value):
    if not value and "file" not in ctx.params and "data" not in ctx.params:
        raise click.MissingParameter(param_decls=[param.name])
    return value


@cli.command()
@click.option("-d", "--data", type=str, callback=mutually_exclusive_options, is_eager=True, help="The data of QRCode.")
@click.option("-f", "--file", type=str, callback=mutually_exclusive_options, is_eager=True, help="The file of QRCode.")
@click.option("--validate", is_flag=True, callback=validate_required_param, expose_value=False, is_eager=True)
@click.option("-l", "--location", type=click.IntRange(0, 7), required=True, help="The location of QRCode. (range 0<=x<=7)")
@click.option("-o", "--output", type=str, required=True, help="The output file of QRCode.")
def makeqr(data, file, location, output):
    """
    Generate a QRCode.
    """
    import fcntl, struct
    import qrcode
    from PIL import Image

    FBIOGET_VSCREENINFO = 0x4600
    FBIOPUT_VSCREENINFO = 0x4601
    FBIOGET_FSCREENINFO = 0x4602
    FBDEV = "/dev/fb0"
    if data is not None:
        qr = qrcode.QRCode(version=1, box_size=10, error_correction=qrcode.constants.ERROR_CORRECT_H, border=4,)
        qr.add_data(data)
        qr.make(fit=True)
        img = qr.make_image(fill_color="purple", back_color="white")
        img = img.convert("RGBA")
        pixels = img.load()
        for i in range(img.size[0]):
            for j in range(img.size[1]):
                if pixels[i, j] == (255, 255, 255, 255):
                    pixels[i, j] = (255, 255, 255, 0)

        if os.path.exists(os.path.join(WORK_PATH, "logo.png")):
            icon = Image.open(os.path.join(WORK_PATH, "logo.png"))
            icon = icon.convert("RGBA")
            img.paste(icon.resize((int(img.size[0] / 5), int(img.size[1] / 5))), (int((img.size[0] - int(img.size[0] / 5)) / 2), int((img.size[1] - int(img.size[1] / 5)) / 2),),)

    if file is not None:
        img = Image.open(file)
        # img = img.convert("RGBA")
        # pixels = img.load()
        # for i in range(img.size[0]):
        #     for j in range(img.size[1]):
        #         if pixels[i, j] == (255, 255, 255, 255):
        #             pixels[i, j] = (255, 255, 255, 0)

    (xres, yres) = (1920, 1080)
    with open(FBDEV, "rb") as fb:
        vi = fcntl.ioctl(fb, FBIOGET_VSCREENINFO, bytes(160))
        res = struct.unpack("I" * 40, vi)
        if res[0] != 0 and res[1] != 0:
            (xres, yres) = (res[0], res[1])
    xqr, yqr = (int(xres / 8), int(xres / 8))
    img = img.resize((xqr, yqr))

    alpha = Image.new("RGBA", (xres, yres), (0, 0, 0, 0))
    if int(location) not in range(0, 8):
        location = 0
    loc = (img.size[0] * int(location), alpha.size[1] - img.size[1])
    alpha.paste(img, loc)
    alpha.save(output)


@cli.command()
@click.option("-p", "--platforms", type=str, help="The platforms of Syno.")
def getmodels(platforms=None):
    """
    Get Syno Models.
    """
    import json, requests, urllib3
    from requests.adapters import HTTPAdapter
    from requests.packages.urllib3.util.retry import Retry # type: ignore

    adapter = HTTPAdapter(max_retries=Retry(total=3, backoff_factor=0.5, status_forcelist=[500, 502, 503, 504]))
    session = requests.Session()
    session.mount('http://', adapter)
    session.mount('https://', adapter)
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    
    if platforms is not None and platforms != "":
        PS = platforms.lower().replace(",", " ").split()
    else:
        PS = []

    models = []
    if len(models) == 0:
        try:
            req = session.get("https://autoupdate.synology.com/os/v2", timeout=10, verify=False)
            req.encoding = "utf-8"
            data = json.loads(req.text)

            for I in data["channel"]["item"]:
                if not I["title"].startswith("DSM"):
                    continue
                for J in I["model"]:
                    arch = J["mUnique"].split("_")[1]
                    name = J["mLink"].split("/")[-1].split("_")[1].replace("%2B", "+")
                    if len(PS) > 0 and arch.lower() not in PS:
                        continue
                    if any(name == B["name"] for B in models):
                        continue
                    models.append({"name": name, "arch": arch})

            models = sorted(models, key=lambda k: (k["arch"], k["name"]))

        except:
            pass

    if len(models) == 0:
        try:
            import re
            from bs4 import BeautifulSoup
            #url="https://kb.synology.com/en-us/DSM/tutorial/What_kind_of_CPU_does_my_NAS_have"
            url="https://kb.synology.cn/zh-cn/DSM/tutorial/What_kind_of_CPU_does_my_NAS_have"
            req = session.get(url, timeout=10, verify=False)
            req.encoding = "utf-8"
            bs = BeautifulSoup(req.text, "html.parser")
            p = re.compile(r"data: (.*?),$", re.MULTILINE | re.DOTALL)
            data = json.loads(p.search(bs.find("script", string=p).prettify()).group(1))
            model = "(.*?)"  # (.*?): all, FS6400: one
            p = re.compile(r"<td>{}<\/td><td>(.*?)<\/td><td>(.*?)<\/td><td>(.*?)<\/td><td>(.*?)<\/td><td>(.*?)<\/td><td>(.*?)<\/td>".format(model), re.MULTILINE | re.DOTALL,)
            it = p.finditer(data["preload"]["content"].replace("\n", "").replace("\t", ""))
            for i in it:
                d = i.groups()
                if len(d) == 6:
                    d = model + d
                if len(PS) > 0 and d[5].lower() not in PS:
                    continue
                models.append({"name": d[0].split("<br")[0], "arch": d[5].lower()})
        except:
            pass

    models.sort(key=lambda x: (x["arch"], x["name"]))
    print(json.dumps(models, indent=4))


if __name__ == "__main__":
    cli()
