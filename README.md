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
* Redpill: @RedPill-TTG @pocopico @jim3ma @fbelavenuto @MoetaYuko
  * https://github.com/RedPill-TTG
  * https://github.com/XPEnology-Community/redpill-lkm5
  * https://github.com/MoetaYuko/linux_dsm_epyc7002
* Framework:
  * https://github.com/buildroot/buildroot
  * https://github.com/eudev-project/eudev
* Addons: @xbl3 @wirgen @007revad @PeterSuh-Q3
  * https://github.com/xbl3/synocodectool-patch (https://github.com/wirgen/synocodectool-patch)
  * https://github.com/007revad/Synology_HDD_db
  * https://github.com/007revad/Synology_enable_M2_volume (base)
* Modules: @jim3ma @MoetaYuko
  * https://github.com/jim3ma/synology-igc
  * https://github.com/MoetaYuko/intel-gpu-i915-backports


### 组件: 
<b>https://github.com/wjz304/rr</b>


### About GPU: 
* vGPU:
  * https://blog.kkk.rs/  
  * https://github.com/pdbear/syno_nvidia_gpu_driver/
* iGPU:
  * https://jim.plus/  
* iGPU:
  * https://github.com/MoetaYuko/intel-gpu-i915-backports


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
    mkdir -p lang/zh_CN/LC_MESSAGES
    msginit -i lang/rr.pot -l zh_CN.UTF-8 -o lang/zh_CN/LC_MESSAGES/rr.po
    # This process will be automatically processed during packaging.
    msgfmt lang/zh_CN/LC_MESSAGES/rr.po -o lang/zh_CN/LC_MESSAGES/rr.mo
    ```
* I am not proficient in language, and even my English is very poor. 
  Developers who are familiar with various languages are welcome to submit PR.

* Translation maintenance personnel:
   * en_US: @wjz304
   * ko_KR: @EXP <jeong1986>
   * ru_RU: @Alex TG
   * zh_CN: @wjz304
   * zh_HK: @wjz304
   * zh_TW: @March Fun <https://cyber.suma.tw/> (豪客幫)


## Group
* `QQ群1: 21609194` [`点击加入QQ群`](https://qm.qq.com/q/YTPvSXfeU0)
* `QQ群2: 73119176` [`点击加入QQ群`](https://qm.qq.com/q/YV1B0NFvWK)
* `QQ群3: 51929774` [`点击加入QQ群`](https://qm.qq.com/q/aVjM3Wb6KY)
* `QQ群4: 49756829` [`点击加入QQ群`](https://qm.qq.com/q/9PHzmZDkqI)
* `QQ Channel: RROrg` [`点击加入QQ频道`](https://pd.qq.com/s/aklqb0uij)
* `TG Channel: RROrg` [`Click to join`](https://t.me/RR_Org)

## 打赏一下
* * <img src="https://raw.githubusercontent.com/wjz304/wjz304/master/my/20220908134226.jpg" width="400">




