<img src="https://avatars.githubusercontent.com/u/151816514?s=200&v=4" alt="logo" width="140" height="140" align="left" />

<h1>RR: <small>redpill’s preinstallation and recovery environment</small></h1>

[![点击数](https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https://github.com/rrorg/rr&edge_flat=true)](https://github.com/rrorg/rr)
[![GitHub Release](https://img.shields.io/github/v/release/rrorg/rr?logo=github&style=flat-square)](https://github.com/rrorg/rr/releases/latest)
[![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/rrorg/rr/total?logo=github&style=flat-square)](https://github.com/rrorg/rr/releases)
[![GitHub Issues or Pull Requests by label](https://img.shields.io/github/issues-closed-raw/rrorg/rr/custom?logo=github&style=flat-square&label=custom)](https://rrorg.github.io/rr/)

> The ultimate solution to self-centralized Synology DSM OS on any local machine with any x86/x64 CPU architecture via a single flash of bootload pre-installation process in addition within recovery environment.

### 1: Disclaimer

硬盘有价，数据无价，任何对引导的修改都是有风险的，本人/组织不承担数据丢失的责任。本工具仅用作学习交流，严禁用于商业用途。
----
Hardware/hard-drives are priced whilst data are priceless, any user-specific custom modification of the tested & prebuilt bootloader images could potentially cause irreversible data destruction towards your local machine. Us, as (RROrg) are not responsibly liable for damage nor personal loss of any types. The project with its affiliation is released for educational and learning purpose only, commercial application of the software is strictly prohibited.


### 2: Documentation & FAQ

- [RRManager](https://github.com/T-REX-XP/RRManager)
- [blog](https://rrorg.cn)
- [docs](https://rrorg.github.io/rr-docs)
- [📣](https://github.com/orgs/RROrg/discussions)

### 3: Components

For the packag of has been initialized and build image, please go to [RR-CUSTOM](https://rrorg.github.io/rr/).

### 4: GPU: 

- vGPU:
  - [蔚然小站](https://blog.kkk.rs/) 
  - [syno_nvidia_gpu_driver](https://github.com/pdbear/syno_nvidia_gpu_driver/)
- iGPU:
  - [Jim's Blog](https://jim.plus/)
- iGPU:
  - [intel-gpu-i915-backports](https://github.com/MoetaYuko/intel-gpu-i915-backports)

## 5: Contributing

  * The following is a roughly truncated guide to involve in project localization for internationalization.

  ```shell
  # If deletion nor addition proces of code hunk is not required, comply with the following process
  sudo apt install gettext
  git clone https://github.com/rrorg/rr.git
  cd files/initrd/opt/rr
  xgettext -L Shell --keyword=TEXT *.sh -o lang/rr.pot
  sed -i 's/charset=CHARSET/charset=UTF-8/' lang/rr.pot
  # If you have to replace certain language string of the project, please suggest and modify translation changes within each correlated PO file
  mkdir -p lang/zh_CN/LC_MESSAGES
  msginit -i lang/rr.pot -l zh_CN.UTF-8 -o lang/zh_CN/LC_MESSAGES/rr.po
  # Update translation files
  for I in $(find lang -path *rr.po); do msgmerge --width=256 -U ${I} lang/rr.pot; done
  # This formatting process will be automatically conducted during packaging.
  for I in $(find lang -path *rr.po); do msgfmt ${I} -o ${I/.po/.mo}; done
  ```

- PRs of new language translations towards the project is welcomed with appreciation.

- Community maintainers of each supporting list of languages are accredited below.

  - `en_US`: `@rrorg`
  - `ja_JP`: `@andatoshiki` & `@toshikidev`
  - `ko_KR`: `@EXP` : jeong1986
  - `ru_RU`: `@Alex`: TG
  - `tr_TR`: `@miraç bahadır öztürk`: miracozturk
  - `vi_VN`: `@Ngọc Anh Trần`: mr.ngocanhtran
  - `zh_CN`: `@rrorg`
  - `zh_HK`: `@rrorg`
  - `zh_TW`: `@March Fun`: [豪客幫](<https://cyber.suma.tw/>)

### 6: Acknowledgment & Credits

- [ARPL](https://github.com/fbelavenuto/arpl): `@fbelavenuto`
- Redpill: `@RedPill-TTG` `@pocopico` `@jim3ma` `@fbelavenuto` `@MoetaYuko`
  - [RedPill-TTG](https://github.com/RedPill-TTG)
  - [redpill-lkm5](https://github.com/XPEnology-Community/redpill-lkm5)
  - [linux_dsm_epyc7002](https://github.com/MoetaYuko/linux_dsm_epyc7002)
- Framework:
  - [Buildroot](https://github.com/buildroot/buildroot)
  - [Eudev](https://github.com/eudev-project/eudev)
  - [Grub](https://git.savannah.gnu.org/git/grub)
- Addons: `@xbl3&@wirgen` `@007revad` `@PeterSuh-Q3` `@jim3ma` `@jinlife`
  - [synocodectool-patch](https://github.com/xbl3/synocodectool-patch)
  - [Synology_HDD_db](https://github.com/007revad/Synology_HDD_db)
  - [nvme-cache](https://github.com/PeterSuh-Q3/tcrp-addons/tree/main/nvme-cache)
  - [Synology_enable_M2_volume](https://github.com/007revad/Synology_enable_M2_volume)
  - [synology-installation-with-nvme-disks-only](https://jim.plus/blog/post/jim/synology-installation-with-nvme-disks-only)
  - [Synology_Photos_Face_Patch](https://github.com/jinlife/Synology_Photos_Face_Patch)
- Modules:`@jim3ma` `@MoetaYuko`
  - [synology-igc](https://github.com/jim3ma/synology-igc)
  - [intel-gpu-i915-backports](https://github.com/MoetaYuko/intel-gpu-i915-backports)




### 8: License

- [GPL-V3](https://github.com/RROrg/rr/blob/main/LICENSE)
