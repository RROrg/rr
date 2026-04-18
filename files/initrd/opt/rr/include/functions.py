# -*- coding: utf-8 -*-
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# This script is a CLI to RR.
#
# # Backup the original python3 executable.
# sudo mv -f "$(realpath $(which python3))/EXTERNALLY-MANAGED" "$(realpath $(which python3))/EXTERNALLY-MANAGED.bak" 2>/dev/null || true
# sudo pip3 install -U click requests requests-toolbelt qrcode[pil] beautifulsoup4

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


def __fullversion(ver):
    arr = ver.split('-')
    a, b, c = (arr[0].split('.') + ['0', '0', '0'])[:3]
    d = arr[1] if len(arr) > 1 else '00000'
    e = arr[2] if len(arr) > 2 else '0'
    return f'{a}.{b}.{c}-{d}-{e}'


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
    try:
        import fcntl, struct
        import qrcode
        from PIL import Image

        FBIOGET_VSCREENINFO = 0x4600
        FBIOPUT_VSCREENINFO = 0x4601
        FBIOGET_FSCREENINFO = 0x4602
        FBDEV = "/dev/fb0"

        if data:
            qr = qrcode.QRCode(version=1, box_size=10, error_correction=qrcode.constants.ERROR_CORRECT_H, border=4)
            qr.add_data(data)
            qr.make(fit=True)
            img = qr.make_image(fill_color="purple", back_color="white").convert("RGBA")
            pixels = img.load()
            for i in range(img.size[0]):
                for j in range(img.size[1]):
                    if pixels[i, j] == (255, 255, 255, 255):
                        pixels[i, j] = (255, 255, 255, 0)

            logo_path = os.path.join(WORK_PATH, "logo.png")
            if os.path.exists(logo_path):
                icon = Image.open(logo_path).convert("RGBA")
                img.paste(icon.resize((img.size[0] // 5, img.size[1] // 5)), ((img.size[0] - img.size[0] // 5) // 2, (img.size[1] - img.size[1] // 5) // 2))

        elif file:
            img = Image.open(file)
            # img = img.convert("RGBA")
            # pixels = img.load()
            # for i in range(img.size[0]):
            #     for j in range(img.size[1]):
            #         if pixels[i, j] == (255, 255, 255, 255):
            #             pixels[i, j] = (255, 255, 255, 0)
        else:
            raise click.UsageError("Either data or file must be provided.")

        with open(FBDEV, "rb") as fb:
            vi = fcntl.ioctl(fb, FBIOGET_VSCREENINFO, bytes(160))
            res = struct.unpack("I" * 40, vi)
            xres, yres = res[0], res[1] if res[0] and res[1] else (1920, 1080)

        img = img.resize((xres // 8, xres // 8))
        alpha = Image.new("RGBA", (xres, yres), (0, 0, 0, 0))
        loc = (img.size[0] * location, alpha.size[1] - img.size[1])
        alpha.paste(img, loc)
        alpha.save(output)

    except Exception as e:
        click.echo(f"Error: {e}")


@cli.command()
@click.option("-p", "--platforms", type=str, help="The platforms of Syno.")
def getmodels(platforms=None):
    """
    Get Syno Models.
    """
    import re, json, requests, urllib3
    from requests.adapters import HTTPAdapter
    from requests.packages.urllib3.util.retry import Retry  # type: ignore

    adapter = HTTPAdapter(max_retries=Retry(total=3, backoff_factor=1, status_forcelist=[500, 502, 503, 504]))
    session = requests.Session()
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    PS = platforms.lower().replace(",", " ").split() if platforms else []

    models = []
    try:
        url = "http://update7.synology.com/autoupdate/genRSS.php?include_beta=1"
        #url = "https://update7.synology.com/autoupdate/genRSS.php?include_beta=1"

        req = session.get(url, timeout=10, verify=False)
        req.encoding = "utf-8"
        p = re.compile(r"<mUnique>(.*?)</mUnique>.*?<mLink>(.*?)</mLink>", re.MULTILINE | re.DOTALL)
        data = p.findall(req.text)
        for item in data:
            if not "DSM" in item[1]:
                continue
            arch = item[0].split("_")[1]
            name = item[1].split("/")[-1].split("_")[1].replace("%2B", "+")
            if PS and arch.lower() not in PS:
                continue
            if not any(m["name"] == name for m in models):
                models.append({"name": name, "arch": arch})

        models.sort(key=lambda k: (k["arch"], k["name"]))

    except Exception as e:
        # click.echo(f"Error: {e}")
        pass

    print(json.dumps(models, indent=4))


@cli.command()
@click.option("-p", "--platforms", type=str, help="The platforms of Syno.")
def getmodelsbykb(platforms=None):
    """
    Get Syno Models.
    """
    import re, json, requests, urllib3
    from bs4 import BeautifulSoup
    from requests.adapters import HTTPAdapter
    from requests.packages.urllib3.util.retry import Retry  # type: ignore

    adapter = HTTPAdapter(max_retries=Retry(total=3, backoff_factor=1, status_forcelist=[500, 502, 503, 504]))
    session = requests.Session()
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    PS = platforms.lower().replace(",", " ").split() if platforms else []

    models = []
    try:
        url = "https://kb.synology.com/en-us/DSM/tutorial/What_kind_of_CPU_does_my_NAS_have"
        #url = "https://kb.synology.cn/zh-cn/DSM/tutorial/What_kind_of_CPU_does_my_NAS_have"

        req = session.get(url, timeout=10, verify=False)
        req.encoding = "utf-8"
        bs = BeautifulSoup(req.text, "html.parser")
        p = re.compile(r"data: (.*?),$", re.MULTILINE | re.DOTALL)
        data = json.loads(p.search(bs.find("script", string=p).prettify()).group(1))
        model = "(.*?)"  # (.*?): all, FS6400: one
        p = re.compile(r"<td>{}<\/td><td>(.*?)<\/td><td>(.*?)<\/td><td>(.*?)<\/td><td>(.*?)<\/td><td>(.*?)<\/td><td>(.*?)<\/td>".format(model), re.MULTILINE | re.DOTALL)
        it = p.finditer(data["preload"]["content"].replace("\n", "").replace("\t", ""))
        for i in it:
            d = i.groups()
            if len(d) == 6:
                d = model + d
            if PS and d[5].lower() not in PS:
                continue
            models.append({"name": d[0].split("<br")[0], "arch": d[5].lower()})
    except Exception as e:
        # click.echo(f"Error: {e}")
        pass

    models.sort(key=lambda x: (x["arch"], x["name"]))
    print(json.dumps(models, indent=4))


@cli.command()
@click.option("-m", "--model", type=str, required=True, help="The model of Syno.")
@click.option("-v", "--version", type=str, required=True, help="The version of Syno.")
def getpats4mv(model, version):
    import json, requests, urllib3
    from requests.adapters import HTTPAdapter
    from requests.packages.urllib3.util.retry import Retry  # type: ignore

    adapter = HTTPAdapter(max_retries=Retry(total=3, backoff_factor=1, status_forcelist=[500, 502, 503, 504]))
    session = requests.Session()
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    pats = {}
    try:
        urlInfo = "https://www.synology.com/api/support/findDownloadInfo?lang=en-us"
        urlSteps = "https://www.synology.com/api/support/findUpgradeSteps?"
        #urlInfo = "https://www.synology.cn/api/support/findDownloadInfo?lang=zh-cn"
        #urlSteps = "https://www.synology.cn/api/support/findUpgradeSteps?"

        major = f"&major={version.split('.')[0]}" if len(version.split('.')) > 0 else ""
        minor = f"&minor={version.split('.')[1]}" if len(version.split('.')) > 1 else ""
        req = session.get(f"{urlInfo}&product={model.replace('+', '%2B')}{major}{minor}", timeout=10, verify=False)
        req.encoding = "utf-8"
        data = json.loads(req.text)

        build_ver = data['info']['system']['detail'][0]['items'][0]['build_ver']
        build_num = data['info']['system']['detail'][0]['items'][0]['build_num']
        buildnano = data['info']['system']['detail'][0]['items'][0]['nano']
        V = __fullversion(f"{build_ver}-{build_num}-{buildnano}")
        if V not in pats:
            pats[V] = {
                'url': data['info']['system']['detail'][0]['items'][0]['files'][0]['url'].split('?')[0],
                'sum': data['info']['system']['detail'][0]['items'][0]['files'][0].get('checksum', '0' * 32)
            }

        from_ver = min(I['build'] for I in data['info']['pubVers'])

        for I in data['info']['productVers']:
            if not I['version'].startswith(version):
                continue
            if not major or not minor:
                majorTmp = f"&major={I['version'].split('.')[0]}" if len(I['version'].split('.')) > 0 else ""
                minorTmp = f"&minor={I['version'].split('.')[1]}" if len(I['version'].split('.')) > 1 else ""
                reqTmp = session.get(f"{urlInfo}&product={model.replace('+', '%2B')}{majorTmp}{minorTmp}", timeout=10, verify=False)
                reqTmp.encoding = "utf-8"
                dataTmp = json.loads(reqTmp.text)

                build_ver = dataTmp['info']['system']['detail'][0]['items'][0]['build_ver']
                build_num = dataTmp['info']['system']['detail'][0]['items'][0]['build_num']
                buildnano = dataTmp['info']['system']['detail'][0]['items'][0]['nano']
                V = __fullversion(f"{build_ver}-{build_num}-{buildnano}")
                if V not in pats:
                    pats[V] = {
                        'url': dataTmp['info']['system']['detail'][0]['items'][0]['files'][0]['url'].split('?')[0],
                        'sum': dataTmp['info']['system']['detail'][0]['items'][0]['files'][0].get('checksum', '0' * 32)
                    }

            for J in I['versions']:
                to_ver = J['build']
                reqSteps = session.get(f"{urlSteps}&product={model.replace('+', '%2B')}&from_ver={from_ver}&to_ver={to_ver}", timeout=10, verify=False)
                if reqSteps.status_code != 200:
                    continue
                reqSteps.encoding = "utf-8"
                dataSteps = json.loads(reqSteps.text)
                for S in dataSteps['upgrade_steps']:
                    if not S.get('full_patch') or not S['build_ver'].startswith(version):
                        continue
                    V = __fullversion(f"{S['build_ver']}-{S['build_num']}-{S['nano']}")
                    if V not in pats:
                        reqPat = session.head(S['files'][0]['url'].split('?')[0], timeout=10, verify=False)
                        if reqPat.status_code == 403:
                            continue
                        pats[V] = {
                            'url': S['files'][0]['url'].split('?')[0],
                            'sum': S['files'][0].get('checksum', '0' * 32)
                        }
    except Exception as e:
        # click.echo(f"Error: {e}")
        pass

    pats = {k: pats[k] for k in sorted(pats.keys(), reverse=True)}
    print(json.dumps(pats, indent=4))


@cli.command()
@click.option("-p", "--models", type=str, help="The models of Syno.")
def getpats(models=None):
    import re, json, requests, urllib3
    from bs4 import BeautifulSoup
    from requests.adapters import HTTPAdapter
    from requests.packages.urllib3.util.retry import Retry  # type: ignore

    adapter = HTTPAdapter(max_retries=Retry(total=3, backoff_factor=1, status_forcelist=[500, 502, 503, 504]))
    session = requests.Session()
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    MS = models.lower().replace(",", " ").split() if models else []

    pats = {}
    try:
        req = session.get('https://archive.synology.com/download/Os/DSM', timeout=10, verify=False)
        req.encoding = 'utf-8'
        bs = BeautifulSoup(req.text, 'html.parser')
        p = re.compile(r"(.*?)-(.*?)", re.MULTILINE | re.DOTALL)
        l = bs.find_all('a', string=p)
        for i in l:
            ver = i.attrs['href'].split('/')[-1]
            if not ver.startswith('7'):
                continue
            req = session.get(f'https://archive.synology.com{i.attrs["href"]}', timeout=10, verify=False)
            req.encoding = 'utf-8'
            bs = BeautifulSoup(req.text, 'html.parser')
            p = re.compile(r"DSM_(.*?)_(.*?).pat", re.MULTILINE | re.DOTALL)
            data = bs.find_all('a', string=p)
            for item in data:
                rels = p.search(item.attrs['href'])
                if rels:
                    model, _ = rels.groups()
                    model = model.replace('%2B', '+')
                    if MS and model.lower() not in MS:
                        continue
                    if model not in pats:
                        pats[model] = {}
                    pats[model][__fullversion(ver)] = item.attrs['href']
    except Exception as e:
        # click.echo(f"Error: {e}")
        pass

    print(json.dumps(pats, indent=4))


if __name__ == "__main__":
    cli()
