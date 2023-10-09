# Automated Redpill Loader (i18n)

本库为 arpl i18n (多语言优化版): 

### 原版：
<b>https://github.com/fbelavenuto/arpl</b>
* [arpl说明](https://github.com/fbelavenuto/arpl/blob/main/README.md)

### 汉化：
<b>https://github.com/wjz304/arpl-zh_CN</b>
* 仅同步汉化原版, 所以功能与原版保持一致.

### i18n: 
<b>https://github.com/wjz304/arpl-i18n</b>
* addons: https://github.com/wjz304/arpl-addons
* modules: https://github.com/wjz304/arpl-modules
* rp-lkms: https://github.com/wjz304/redpill-lkm

### About GPU: 
* iGPU: https://jim.plus/
* vGPU: https://blog.kkk.rs/

## 说明 - Instructions
* [GUIDE](./guide.md)
* [About get logs](https://github.com/wjz304/arpl-i18n/issues/173)
* [About not find DSM after "boot the loader"](https://github.com/wjz304/arpl-i18n/issues/175)
* [About DT(Device Tree) and *portcfg/maxdisks](https://github.com/wjz304/arpl-i18n/issues/226)

## 翻译 - Translation
* 其他语言的翻译 - Language translation work:
    ```shell
    # If it does not involve adding or deleting, the following process is not required.
    sudo apt install gettext
    git clone https://github.com/wjz304/arpl-i18n.git
    cd files/board/arpl/overlayfs/opt/arpl
    xgettext -L Shell --keyword=TEXT *.sh -o lang/arpl.pot
    sed -i 's/charset=CHARSET/charset=UTF-8/' lang/arpl.pot
    # You need to replace the language you need and translate the po file.
    msginit -i lang/arpl.pot -l zh_CN.UTF-8 -o lang/zh_CN.po
    # This process will be automatically processed during packaging.
    msgfmt lang/zh_CN.po -o lang/zh_CN.mo
    ```
* I am not proficient in language, and even my English is very poor. 
  Developers who are familiar with various languages are welcome to submit PR.

* Translation maintenance personnel:
   * zh_CN: @wjz304
   * zh_TW: @豪客幫

## 教程 - Usage 
* English: https://www.youtube.com/watch?v=VB67_FG5y-E
    ##### `(From: @NETVN82)`
* Español: https://www.youtube.com/watch?v=KC6oCcAyoV4
    ##### `(From: @Jay tech 2023)`
* 한국어: https://www.youtube.com/watch?v=4O7EfU6MT60
    ##### `(From: @pageinnet)`
* ภาษาไทย: https://www.youtube.com/watch?v=4sGrMMEQQ6I
    ##### `(From: @stnology)`
* 中文繁體: https://www.youtube.com/watch?v=cW2eRCjtAEs
    ##### `(From: @豪客幫)`
* 中文简体: https://www.bilibili.com/video/BV1jk4y1Y7B7  
    ##### `(From: http://mi-d.cn)`

## 免责声明 - Disclaimer
* 硬盘有价，数据无价，任何对引导的修改都是有风险的，本人不承担数据丢失的责任。
* 本工具仅用作学习交流，严禁用于商业用途。
----
* The hard drive has a price, but the data is priceless. Any modification to the bootloader is risky. I will not be responsible for data loss.
* This tool is only for learning and communication, and commercial use is strictly prohibited.

## 打赏一下
* > ### 作者: Ing  
* > QQ群1: 21609194 [点击链接加入QQ群](https://qm.qq.com/cgi-bin/qm/qr?k=z5O89os88QEKXCbz-0gwtEz1AeQiCwk3)
* > QQ群2: 73119176 [点击链接加入QQ群](https://qm.qq.com/cgi-bin/qm/qr?k=6GFSrSYX2LTd9PD0r0hl_YJZsfLp53Oh)
* > QQ频道: redpill2syno [点击链接加入QQ频道](https://pd.qq.com/s/5nmli9qgn)
* > TG频道: redpill2syno [点击链接加入TG频道](https://t.me/redpill2syno)
* <img src="https://raw.githubusercontent.com/wjz304/wjz304/master/my/20220908134226.jpg" width="400">



