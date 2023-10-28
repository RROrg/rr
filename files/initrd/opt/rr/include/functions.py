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
    The CLI is a commands to arpl.
    """
    pass

@cli.command()
@click.option('-d', "--data", type=str, required=True, help="The data of QRCode.")
@click.option('-l', "--location", type=str, required=True, help="The location of QRCode. (tl, tr, bl, br, mid)")
@click.option('-o', "--output", type=str, required=True, help="The output file of QRCode.")
def makeqr(data, location, output):
    """
    Generate a QRCode.
    """
    import qrcode
    from PIL import Image
    qr = qrcode.QRCode(version=1, box_size=10, error_correction=qrcode.constants.ERROR_CORRECT_H, border=4)
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
        img.paste(icon.resize((int(img.size[0] / 5), int(img.size[1] / 5))), (int((img.size[0] - int(img.size[0] / 5)) / 2), int((img.size[1] - int(img.size[1] / 5)) / 2)))
   
    alpha = Image.new("RGBA", (img.size[0] * 4, img.size[1] * 3), (0, 0, 0, 0))
    if location == "tl":
        loc = (0, 0)
    elif location == "tr":
        loc = (alpha.size[0] - img.size[0], 0)
    elif location == "bl":
        loc = (0, alpha.size[1] - img.size[1])
    elif location == "br":
        loc = (alpha.size[0] - img.size[0], alpha.size[1] - img.size[1])
    else: # elif location == "mid":
        loc = (int((alpha.size[0] - img.size[0]) / 2), int((alpha.size[1] - img.size[1]) / 2))

    alpha.paste(img, loc)
    alpha.save(output)


if __name__ == "__main__":
    cli()
