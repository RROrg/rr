<img src="https://avatars.githubusercontent.com/u/151816514?s=200&v=4" alt="logo" width="140" height="140" align="left" />

<h1>RR: <small>Yet a Better Redistributed Fork of ARPL for Redpill Bootload Automation</small></h1>


> The ultimate solution to self-centralized Synology DSM OS on any local machine with any x86/x64 CPU architecture via a single flash of bootload pre-installation process in addition within recovery environment.

### 1: Disclaimer
硬盘有价，数据无价，任何对引导的修改都是有风险的，本人/组织不承担数据丢失的责任。本工具仅用作学习交流，严禁用于商业用途。
Hardware/hard-drives are priced whilst data are priceless, any user-specific custom modification of the tested & prebuilt bootloader images could potentially cause irreversible data destruction towards your local machine. Us, as (RROrg) are not responsibly liable for damage nor personal loss of any types. The project with its affiliation is released for educational and learning purpose only, commercial application of the software is strictly prohibited.


### 2: Documentation & FAQ

- [Quick start guide](./guide.md)
- [How to fetch debug logs](https://github.com/rrorg/rr/issues/173)
- [Temporary workaround for "DSM not found" after bootloading](https://github.com/rrorg/rr/issues/175)
- [DT(Device Tree) and -portcfg/maxdisks](https://github.com/rrorg/rr/issues/226)

### 3: Components

Please refer to [rr-modules](https://github.com/RROrg/rr-modules) and [rr-addons](https://github.com/RROrg/rr-addons) for details and further practices if you intend to manually build rr from source.

### 4: GPU: 

- vGPU:
  - [蔚然小站](https://blog.kkk.rs/) 
  - [syno_nvidia_gpu_driver](https://github.com/pdbear/syno_nvidia_gpu_driver/)
- iGPU:
  - [Jim's Blog](https://jim.plus/)
- iGPU:
  - [intel-gpu-i915-backports](https://github.com/MoetaYuko/intel-gpu-i915-backports)

## 5: Contributing

- The following is a roughly truncated guide to involve in project localization for internationalization.

  ```shell
  # If deletion nor addition proces of code hunk is not required, comply with the following process
  sudo apt install gettext
  git clone https://github.com/rrorg/rr.git
  cd files/initrd/opt/rr
  xgettext -L Shell --keyword=TEXT -.sh -o lang/rr.pot
  sed -i 's/charset=CHARSET/charset=UTF-8/' lang/rr.pot
  # If you have to replace certain language string of the project, please suggest and modify translation changes within each correlated PO file
  mkdir -p lang/zh_CN/LC_MESSAGES
  msginit -i lang/rr.pot -l zh_CN.UTF-8 -o lang/zh_CN/LC_MESSAGES/rr.po
  # This formatting process will be automatically conducted during packaging.
  msgfmt lang/zh_CN/LC_MESSAGES/rr.po -o lang/zh_CN/LC_MESSAGES/rr.mo
  ```

- PRs of new language translations towards the project is welcomed with appreciation.

- Community maintainers of each supporting list of languages are accredited below.

  - `en_US`: `@rrorg`
  - `ja_JP`: `@andatoshiki` & `@toshikidev`
  - `ko_KR`:  `@EXP` : jeong1986
  - `ru_RU`: `@Alex`: TG
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
- Addons: `@xbl3` `@wirgen` `@007revad` `@PeterSuh-Q3`
  - [synocodectool-patch](https://github.com/xbl3/synocodectool-patch)
  - [Synology_HDD_db](https://github.com/007revad/Synology_HDD_db)
  - [Synology_enable_M2_volume](https://github.com/007revad/Synology_enable_M2_volume)
- Modules:`@jim3ma` `@MoetaYuko`
  - [ynology-igc](https://github.com/jim3ma/synology-igc)
  - [intel-gpu-i915-backports](https://github.com/MoetaYuko/intel-gpu-i915-backports)

### 7: Links & Community

#### 7.1: Group

- `QQ群1: 21609194` [`点击加入QQ群`](https://qm.qq.com/q/YTPvSXfeU0)
- `QQ群2: 73119176` [`点击加入QQ群`](https://qm.qq.com/q/YV1B0NFvWK)
- `QQ群3: 51929774` [`点击加入QQ群`](https://qm.qq.com/q/aVjM3Wb6KY)
- `QQ群4: 49756829` [`点击加入QQ群`](https://qm.qq.com/q/9PHzmZDkqI)
- `QQ Channel: RROrg` [`点击加入QQ频道`](https://pd.qq.com/s/aklqb0uij)
- `Telegram Channel: RROrg` [`Click to join`](https://t.me/RR_Org)

### 7: Sponsoring

- <img src="https://raw.githubusercontent.com/wjz304/wjz304/master/my/buymeacoffee.png" width="700">

### 8: License

- [GPL-V3](https://github.com/RROrg/rr/blob/main/LICENSE)
