# Redpill Recovery (arpl-i18n)

This project is a system for redpill’s preinstallation and recovery environment.

## 免责声明 - Disclaimer
* 硬盘有价，数据无价，任何对引导的修改都是有风险的，本人不承担数据丢失的责任。
* 本工具仅用作学习交流，严禁用于商业用途。
----
* The hard drive has a price, but the data is priceless. Any modification to the bootloader is risky. I will not be responsible for data loss.
* This tool is only for learning and communication, and commercial use is strictly prohibited.


### 鸣谢 - Credits
* Arpl: @fbelavenuto
  * https://github.com/fbelavenuto/arpl
* Redpill: @RedPill-TTG @pocopico @jim3ma
  * https://github.com/RedPill-TTG
  * https://github.com/XPEnology-Community/redpill-lkm5
* Framework:
  * https://github.com/buildroot/buildroot
  * https://github.com/eudev-project/eudev
* Addons: @xbl3 @FOXBI @arabezar @007revad
  * https://github.com/xbl3/synocodectool-patch
  * https://github.com/FOXBI/ch_cpuinfo (https://github.com/arabezar/ch_cpuinfo)
  * https://github.com/007revad/Synology_HDD_db
  * https://github.com/007revad/Synology_enable_M2_volume
* Modules: @jim3ma @MoetaYuko
  * https://github.com/jim3ma/synology-igc
  * https://github.com/MoetaYuko/intel-gpu-i915-backports


### 组件: 
<b>https://github.com/wjz304/rr</b>
* addons: https://github.com/wjz304/rr-addons
* modules: https://github.com/wjz304/rr-modules
* rp-lkms: https://github.com/wjz304/rr-lkms

### About GPU: 
* vGPU: https://blog.kkk.rs/
* iGPU: https://jim.plus/
* iGPU: https://github.com/MoetaYuko/intel-gpu-i915-backports

## 说明 - Instructions
* [GUIDE](./guide.md)
* [About get logs](https://github.com/wjz304/rr/issues/173)
* [About not find DSM after "boot the loader"](https://github.com/wjz304/rr/issues/175)
* [About DT(Device Tree) and *portcfg/maxdisks](https://github.com/wjz304/rr/issues/226)

## 翻译 - Translation
* 其他语言的翻译 - Language translation work:
    ```shell
    # If it does not involve adding or deleting, the following process is not required.
    sudo apt install gettext
    git clone https://github.com/wjz304/rr.git
    cd files/initrd/opt/rr
    xgettext -L Shell --keyword=TEXT *.sh -o lang/rr.pot
    sed -i 's/charset=CHARSET/charset=UTF-8/' lang/rr.pot
    # You need to replace the language you need and translate the po file.
    msginit -i lang/rr.pot -l zh_CN.UTF-8 -o lang/zh_CN.po
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


## 打赏一下
* > ### 作者: Ing  
* > QQ群1: 21609194 [点击链接加入QQ群](https://qm.qq.com/cgi-bin/qm/qr?k=z5O89os88QEKXCbz-0gwtEz1AeQiCwk3)
* > QQ群2: 73119176 [点击链接加入QQ群](https://qm.qq.com/cgi-bin/qm/qr?k=6GFSrSYX2LTd9PD0r0hl_YJZsfLp53Oh)
* > QQ频道: redpill2syno [点击链接加入QQ频道](https://pd.qq.com/s/5nmli9qgn)
* > TG频道: redpill2syno [点击链接加入TG频道](https://t.me/redpill2syno)
* <img src="https://raw.githubusercontent.com/wjz304/wjz304/master/my/20220908134226.jpg" width="400">



