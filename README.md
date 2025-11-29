<img src="https://avatars.githubusercontent.com/u/151816514?s=200&v=4" alt="logo" width="140" height="140" align="left" />

<h1>RR: <small>redpill’s preinstallation and recovery environment</small></h1>

[![GitHub Release](https://img.shields.io/github/v/release/rrorg/rr?logo=github&style=flat-square)](https://github.com/rrorg/rr/releases/latest)
[![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/rrorg/rr/total?logo=github&style=flat-square)](https://github.com/rrorg/rr/releases)
[![GitHub Issues or Pull Requests by label](https://img.shields.io/github/issues-closed-raw/rrorg/rr/custom?logo=github&style=flat-square&label=custom)](https://rrorg.github.io/rr/)

> The ultimate solution to self-centralized Synology DSM OS on any local machine with any x86/x64 CPU architecture via a single flash of bootload pre-installation process in addition within recovery environment.

### 1: Disclaimer

* 硬盘有价，数据无价，任何对引导的修改都是有风险的，本人/组织不承担数据丢失的责任。本工具仅用作学习交流，严禁用于商业用途。
----
* Hardware/hard-drives are priced whilst data are priceless, any user-specific custom modification of the tested & prebuilt bootloader images could potentially cause irreversible data destruction towards your local machine. Us, as (RROrg) are not responsibly liable for damage nor personal loss of any types. The project with its affiliation is released for educational and learning purpose only, commercial application of the software is strictly prohibited.


### 2: Documentation & FAQ

- [RRManager](https://github.com/T-REX-XP/RRManager)
- [rr-tools](https://github.com/RROrg/rr-tools)
- [blog](https://rrorg.cn)
- [docs](https://rrorg.github.io/rr-docs)
- [📣](https://github.com/orgs/RROrg/discussions)

### 3: Components

- During the compilation process, you need to connect to the Internet to obtain model and version information and download the corresponding ROM.
If you cannot connect to the Internet, please build a pre-compiled bootloader through [RR-CUSTOM](https://rrorg.github.io/rr/).
  - Models: [models](https://github.com/RROrg/rr/raw/main/docs/models.xlsx)
  - PATs: [pats](https://github.com/RROrg/rr/raw/main/docs/pats.xlsx)
  - Addons: [addons](https://github.com/RROrg/rr/raw/main/docs/addons.xlsx)
  - Modules: [modules](https://github.com/RROrg/rr/raw/main/docs/modules.xlsx)

- Proxmox VE One Click Install:
  ```
  curl -fsSL https://github.com/RROrg/rr/raw/refs/heads/main/scripts/pve.sh | bash -s -- --bltype usb

  # Optional Parameters:
  --onboot <0|1>           Enable VM on boot, default 1 (enable)
  --efi <0|1>              Enable UEFI boot, default 1 (enable)
  --bltype <sata|usb|nvme> Bootloader disk type, default sata
  --9ppath <path>          Set to /path/to/9p to mount 9p share
  --tag <tag>              Image tag, download latest release if not set
  --img <path>             Local image path, use local image if set
  ```

- Docker Compose:
  ```yml
  # 请从最新版本中下载 rr.img 文件。
  # 并将 <path_to_rr.img> 替换为你的 rr.img 文件的实际路径.
  # Please download the rr.img file from the latest release.
  # And replace <path_to_rr.img> with the actual path to your rr.img file.

  version: "3.9"
  services:
    rr:
      image: qemux/qemu:latest
      container_name: rr
      environment:
        BOOT: ""
        RAM_SIZE: "4G"  # >= 4G recommended for DSM
        CPU_CORES: "2"
        DISK_TYPE: "sata"
        DISK_SIZE: "32G"  # data disk size
        ARGUMENTS: "-device nec-usb-xhci,id=usb0,multifunction=on -drive file=/rr.img,media=disk,format=raw,if=none,id=udisk1 -device usb-storage,bus=usb0.0,port=1,drive=udisk1,bootindex=999,removable=on"
      devices:
        - /dev/kvm
        - /dev/net/tun
      cap_add:
        - NET_ADMIN
      ports:
        - 5000:5000  # For DSM management
        - 5001:5001  # For DSM management
        - 7681:7681  # For RR management
        - 7304:7304  # For RR management
        - 7080:7080  # For RR management
        - 8006:8006  # For QEMU management
      volumes:
        - ./rr.img:/rr.img  # <path_to_rr.img>:/rr.img
        - ./data:/storage
      restart: always
      stop_grace_period: 2m

  ```

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

  - `de_DE`: `@Tim Krämer`: [Tim Krämer](https://tim-kraemer.de)
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

### 7: Links & Community

#### 7.1: Group

- `QQ群1: 21609194` [`点击加入QQ群`](https://qm.qq.com/q/YTPvSXfeU0)
- `QQ群2: 73119176` [`点击加入QQ群`](https://qm.qq.com/q/YV1B0NFvWK)
- `QQ群3: 51929774` [`点击加入QQ群`](https://qm.qq.com/q/aVjM3Wb6KY)
- `QQ群4: 49756829` [`点击加入QQ群`](https://qm.qq.com/q/9PHzmZDkqI)
- `QQ群5: 30267817` [`点击加入QQ群`](https://qm.qq.com/q/6RgVDfOSXe)
- `QQ群6: 68640297` [`点击加入QQ群`](https://qm.qq.com/q/PU71eSXAic)
- `QQ Channel: RROrg` [`点击加入QQ频道`](https://pd.qq.com/s/aklqb0uij)
- `Telegram Channel: RROrg` [`Click to join`](https://t.me/RR_Org)

### 7: Sponsoring

- <img src="https://raw.githubusercontent.com/wjz304/wjz304/master/my/buymeacoffee.png" width="700">

### 8: License

- [GPL-V3](https://github.com/RROrg/rr/blob/main/LICENSE)
