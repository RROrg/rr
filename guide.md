
# ENV:
* ### 常用工具:
   * telnet 工具 putty (下载: https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html)
   * ssh 工具 WindTerm (下载: https://github.com/kingToolbox/WindTerm)  
   * sftp 工具 WinSCP (下载: https://winscp.net/eng/index.php)
   * 文本编辑工具 Notepad3 (下载: https://github.com/rizonesoft/Notepad3/releases)
   * 镜像写盘工具 Rufus (下载: https://rufus.ie/zh/)
   * 镜像转换工具 qemu-img (下载: https://cloudbase.it/qemu-img-windows/)
   * 镜像转换工具 StarWind V2V Image Converter (下载: https://www.starwindsoftware.com/starwind-v2v-converter)
   * 磁盘管理工具 Diskgenius (下载: https://www.diskgenius.com/)

# LINK:
   * 查找: 
     * http://find.synology.cn/
     * http://find.synology.com/
   * 下载: 
     * https://archive.synology.cn/download/Os/DSM
     * https://archive.synology.com/download/Os/DSM  
   * 介绍:
     * https://www.synology.cn/zh-cn/products#specs
     * https://www.synology.com/en-us/products#specs
   * 型号列表: 
     * https://kb.synology.cn/zh-cn/DSM/tutorial/What_kind_of_CPU_does_my_NAS_have
     * https://kb.synology.com/en-us/DSM/tutorial/What_kind_of_CPU_does_my_NAS_have
   * RAID计算: 
     * https://www.synology.cn/zh-cn/support/RAID_calculator
     * https://www.synology.com/en-us/support/RAID_calculator
   * 恢复数据:
     * https://kb.synology.cn/zh-cn/DSM/tutorial/How_can_I_recover_data_from_my_DiskStation_using_a_PC
     * https://kb.synology.com/en-us/DSM/tutorial/How_can_I_recover_data_from_my_DiskStation_using_a_PC
   * SDK:
     * https://dataupdate7.synology.com/toolchain/v1/get_download_list?identify=toolkit&version=7.2&platform=base
     * https://dataupdate7.synology.com/toolchain/v1/get_download_list?identify=toolkit&version=7.2&platform=purley

# 安装条件
  1. 引导盘：当前支持 SATA/SCSI/NVME/MMC/IDE or USB 设备, 且要大于 2GB. (SCSI 比较复杂, 并不是全部可用)
  2. 安装盘: 至少需要 1 个 SATA 接口硬盘(DT 型号支持 NVME 安装) 或者 1 个 MMC 作为存储设备. 且要大于 32GB 才可创建存储池.
  3. 内存: 需要大于 4GB.
  4. DT 的型号目前不支持 HBA 扩展卡(较新版本的RR引导 SA6400 支持).
  5. NVME 的 PCIPATH 有两种格式, 单层深度路径的仅兼容 DT 的型号, 多层深度路径的兼容 DT 和非 DT 等型号.
  
# 镜像格式
  ```shell
  # 安装 qemu-img
  # https://cloudbase.it/qemu-img-windows/     # Windows
  # apt install qemu-img                       # Debian/Ubuntu
  # yum install qemu-img                       # CentOS
  # brew install qemu-img                      # MacOS

  # img to vmdk (VMWare / ESXi6 / ESXi7)
  qemu-img convert -O vmdk -o adapter_type=lsilogic,subformat=monolithicSparse,compat6 rr.img rr.vmdk

  # img to vmdk (ESXi8)
  qemu-img convert -O vmdk -o adapter_type=lsilogic,subformat=monolithicFlat,compat6 rr.img rr.vmdk

  # img to vhdx (Hyper-V)
  qemu-img convert -O vhdx -o subformat=dynamic rr.img rr.vhdx

  # img to vhd (Parallels Desktop)
  qemu-img convert -O vpc rr.img rr.vhd
  ```


# GPU
* vGPU: https://blog.kkk.rs/
* iGPU: https://jim.plus/
* iGPU: https://github.com/MoetaYuko/intel-gpu-i915-backports

# RR:
* RR 各版本间切换(手动方式, 全量):  
    ```shell
    # 在 shell 中下载需要的版本或者手动上传到 ~/ 下
    # Download the required version in the shell or manually upload it to ~/
    curl -kL -o ~/rr.zip https://github.com/wjz304/rr/releases/download/23.4.5/rr-23.11.1.img.zip
    # 卸载挂载的引导盘
    # Uninstalling the mounted boot disk
    umount /mnt/p1 /mnt/p2 /mnt/p3
    # 解压 并写入到引导盘
    # Decompress and write to the boot disk
    # 获取当前的引导盘
    LOADER_DISK="$(blkid -L RR3 2>/dev/null | cut -d3 -f1)"
    unzip -p rr.zip | dd of=${LOADER_DISK} bs=1M conv=fsync
    # 重启 reboot
    reboot
    ```
* RR 备份 (Any version):
    ```shell
    # 备份为 disk.img.gz, 自行导出.
    dd if="$(blkid -L RR3 2>/dev/null | cut -d3 -f1)" | gzip > disk.img.gz
    # 结合 transfer.sh 直接导出链接
    curl -skL --insecure -w '\n' --upload-file disk.img.gz https://transfer.sh
    ```

* RR 开机强行进入到 RR shell:
    ```shell
    # 在 wait IP 的时候, 快速的连上, 杀死 boot.sh 进程.
    kill $(ps | grep -v grep | grep boot.sh | awk '{print $1}')
    ```

# SYNO:
* ssh 开启 root 权限:
    ```shell
    sudo -i
    sed -i 's/^.*PermitRootLogin.*$/PermitRootLogin yes/' /etc/ssh/sshd_config  
    synouser --setpw root xxxxxx  # xxxxxx 为你要设置的密码
    systemctl restart sshd
    ```
* dsm下挂载引导盘:
    ```shell
    sudo -i
    echo 1 > /proc/sys/kernel/syno_install_flag
    ls /dev/synoboot*    # 正常会有 /dev/synoboot  /dev/synoboot1  /dev/synoboot2  /dev/synoboot3
    # 挂载第1个分区
    mkdir -p /tmp/synoboot1 
    mount /dev/synoboot1 /tmp/synoboot1 
    ls /tmp/synoboot1/
    # 挂载第2个分区
    mkdir -p /tmp/synoboot2
    mount /dev/synoboot2 /tmp/synoboot2
    ls /tmp/synoboot2/
    ```
* dsm下重启到RR(免键盘) (Any version):
    ```shell
    sudo -i  # 输入密码
    /usr/bin/loader-reboot.sh "config"
    ```
* dsm下修改sn (Any version):
    ```shell
    sudo -i  # 输入密码
    SN=xxxxxxxxxx   # 输入你要设置的SN
    echo 1 > /proc/sys/kernel/syno_install_flag
    [ -b "/dev/synoboot1" ] && (mkdir -p /tmp/synoboot1; mount /dev/synoboot1 /tmp/synoboot1)
    [ -f "/tmp/synoboot1/user-config.yml" ] && OLD_SN=$(sed -E 's/^sn:(.*)/\1/; s/[\" ]//g' /tmp/synoboot1/user-config.yml)
    [ -n "${OLD_SN}" ] && sed -i "s/${OLD_SN}/${SN}/g" /tmp/synoboot1/user-config.yml
    reboot
    ```
* 群晖 opkg 包管理:
    ```shell
    curl -#kL http://bin.entware.net/x64-k3.2/installer/generic.sh | /bin/sh
    /opt/bin/opkg update
    /opt/bin/opkg install rename
    ```
* 群晖 ipkg 包管理:
    ```shell
    curl -#kL http://ipkg.nslu2-linux.org/feeds/optware/syno-i686/cross/unstable/syno-i686-bootstrap_1.2-7_i686.xsh | /bin/sh
    ipkg update
    ipkg install lm-sensors
    ```
* 群晖 python pip 包管理:
    ```shell
    curl -#kL https://bootstrap.pypa.io/get-pip.py | python3
    ```
* virt-what (MEV):
    ```shell
    kvm          ---- Proxmox VE / Unraid  ...
    qemu         ---- QEMU (windows)
    vmware       ---- VMware / VMware ESXi
    parallels    ---- Parallels Desktop
    virtualbox   ---- VirtualBox
    ```

## DEBUG
* log:
  ```
  # 内核相关
  sysctl -n kernel.syno_serial                     # 查看当前鉴权的 SN
  cat /proc/sys/kernel/syno_serial                 # 查看当前鉴权的 SN
  sysctl -n kernel.syno_mac_address1               # 查看当前鉴权的 mac1 (kernel.syno_mac_addresses)
  cat /proc/sys/kernel/syno_mac_address1           # 查看当前鉴权的 mac1 (/proc/sys/kernel/syno_mac_addresses)
  sysctl -n kernel.syno_internal_netif_num         # 查看当前鉴权的网卡数量
  cat /proc/sys/kernel/syno_internal_netif_num     # 查看当前鉴权的网卡数量
  sysctl -w kernel.syno_CPU_info_core=32           # 设置线程数 (无效)
  
  ls -d /sys/devices/system/node/node* | wc -l              # 查看当前 CPU 物理路数
  cat /proc/cpuinfo | grep "physical id" | sort -u | wc -l  # 查看当前 CPU 物理路数
  cat /proc/cpuinfo | grep "core id" | sort -u | wc -l      # 查看当前 CPU 核心数
  cat /proc/cpuinfo | grep "processor" | wc -l              # 查看当前 CPU 核心数
  cat /proc/sys/kernel/syno_CPU_info_core                   # 查看当前线程数 (only syno)
  nproc                                                     # 查看当前 CPU 核心数
  lscpu | grep 'NUMA node(s):'                              # 查看当前 NUMA 数量

  # 设备相关
  lsmod                                            # 查看已加载驱动
  lsusb                                            # 查看 USB 设备
  lsblk                                            # 查看磁盘设备
  lspci -Qnnk                                      # 查看 PCI 设备

  # 网卡
  ls -ld /sys/class/net/*/device/driver            # 查看已加载网卡和对应驱动
  cat /sys/class/net/*/address                     # 查看已加载网卡的 MAC 地址
  ethtool -i eth0                                  # 查看网卡驱动信息
  ethtool -s eth0 wol g                            # 配置网卡进入低功耗模式
  ethtool -s eth0 autoneg on                       # 开启网卡自动协商
  ethtool -s eth0 speed 1000                       # 设置网卡速度为 1000 Mbps
  ethtool -s eth0 duplex full                      # 设置网卡全双工

  # 串口
  cat /proc/tty/drivers                            # 查看串口属性
  cat /proc/tty/driver/serial                      # 查看串口属性
  stty -F /dev/ttyS0 -a                            # 查看串口参数
  stty -F /dev/ttyS0 ispeed 115200 ospeed 115200 cs8 -parenb -cstopb -echo  # 设置串口参数
  stty size                                        # 打印终端的行数和列数
  echo helloworld >/dev/ttyS0                      # 向串口发送数据
  cat /dev/ttyS0                                   # 读取串口数据
  getty -L /dev/ttyS0 115200                       # 启动串口终端
  agetty -L /dev/ttyS0 115200                      # 启动串口终端

  # 磁盘相关
  fdisk -l                                         # 查看硬盘信息
  lspci -d ::100                                   # 查看 SCSI 存储控制器 https://admin.pci-ids.ucw.cz/read/PD/
  lspci -d ::101                                   # 查看 IDE 接口
  lspci -d ::102                                   # 查看 软盘 磁盘控制器
  lspci -d ::103                                   # 查看 IPI 总线控制器
  lspci -d ::104                                   # 查看 RAID 总线控制器
  lspci -d ::105                                   # 查看 ATA 总线控制器
  lspci -d ::106                                   # 查看 SATA 总线控制器
  lspci -d ::107                                   # 查看 SAS 总线控制器
  lspci -d ::108                                   # 查看 NVM 控制器

  ls -l /sys/class/scsi_host                       # 查看 ATA 硬盘 host 信息
  ls -l /sys/class/mmc_host                        # 查看 MMC 硬盘 host 信息
  ls -l /sys/class/nvme                            # 查看 NVME 硬盘 host 信息
  ls /sys/block/                                   # 查看块设备
  ls /sys/block/sd*                                # 查看识别的 sata 硬盘 (非设备树(dtb)的型号)
  ls /sys/block/sata*                              # 查看识别的 sata 硬盘 (设备树(dtb)的型号)
  ls /sys/block/nvme*                              # 查看识别的 nvme 硬盘
  ls /sys/block/mmc*                               # 查看识别的 mmc 硬盘
  ls /sys/block/usb*                               # 查看识别的 usb 硬盘
  cat /sys/block/sd*/device/syno_block_info        # 查看识别的 sata 硬盘挂载点 (非设备树(dtb)的型号)  
  cat /sys/block/sata*/device/syno_block_info      # 查看识别的 sata 硬盘挂载点 (设备树(dtb)的型号)
  cat /sys/block/nvme*/device/syno_block_info      # 查看识别的 nvme 硬盘挂载点

  # 判断是否支持热插拔 (返回 min_power, medium_power 则可能支持热插拔; 返回 max_performance 则可能不支持热插拔.)
  cat /sys/class/scsi_host/host*/link_power_management_policy

  # Raid 相关
  lsblk -f                                         # 查看 磁盘 信息
  cat /proc/mdstat                                 # 查看 Raid 状态
  mdadm --detail --scan                            # 查看 Raid 信息 (-D, --detail; -s, --scan)
  mdadm --assemble --scan                          # 扫描所有的磁盘，尝试组装所有可以找到的 RAID 设备 (-A, --assemble; -s, --scan)
  mdadm -AsfR                                      # 扫描所有的磁盘，尝试组装所有可以找到的 RAID 设备并强制启动 (-f, --force; -R, --run)
  vgchange -ay                                     # 激活所有的逻辑卷组
  
  mdadm -D /dev/md0                                # 查看 Raid 0 的详细信息 (-D, --detail)
  mdadm -C /dev/md0 -e 1.2 -amd -R -l1 -f -n2 /dev/sda1 /dev/sdb1    # 创建 Raid 0  (-C, --create; -R, --run; -l, --level; -n, --raid-devices)
  mdadm -S /dev/md0                                # 停止 Raid 0 (-S, --stop)
  mdadm --add /dev/md0 /dev/sda1                   # 添加一个磁盘到 Raid 0 中
  mdadm --remove /dev/md0 /dev/sda1                # 移除 Raid 0 中的一个磁盘
  mdadm --monitor /dev/md0                         # 监控 Raid 0 状态
  mdadm --grow /dev/md0 --level=5                  # 将 Raid 0 设备的级别改变为 RAID 5
  mdadm --zero-superblock /dev/sda1                # 清除 sda1 磁盘分区的 RAID 超级块 (使这个磁盘分区不再被识别为 RAID 设备的一部分)

  # eudev 
  udevadm control --reload-rules                               # 重新加载 udev 规则
  udevadm trigger                                              # 触发 udev 事件
  udevadm info --query all --name /dev/sata1                   # 查看 udev 属性
  udevadm info --query all --path /sys/class/net/eth0          # 查看 udev 属性
  udevadm info --attribute-walk --name=/dev/sata1              # 列出 udev 属性
  udevadm monitor --property --udev                            # 监控 udev 事件
  udevadm test /dev/sata1                                      # 测试 udev 规则
  
  # 服务相关
  journalctl -xe                                   # 查看服务日志
  systemctl                                        # 查看服务
  systemctl | grep failed                          # 查看失败的服务
  systemctl list-unit-files                        # 查看服务配置文件
  systemctl list-units                             # 查看服务状态
  systemctl daemon-reload                          # 重新加载配置文件
  systemctl status cpufreq.service                 # 查看 CPU 频率调节器状态
  systemctl start cpufreq.service                  # 启动 CPU 频率调节器
  systemctl stop cpufreq.service                   # 停止 CPU 频率调节器
  systemctl enable cpufreq.service                 # 开机启动 CPU 频率调节器
  systemctl disable cpufreq.service                # 永久停止 CPU 频率调节器
  netstat -tunlp                                   # 查看端口  
  lsof -i :7681                                    # 查看 7681 端口占用情况

  # CPU
  cat /sys/devices/system/cpu/cpufreq/boost                                    # 查看 CPU 睿频状态
  echo 1 > /sys/devices/system/cpu/cpufreq/boost                               # 开启 CPU 睿频
  echo 0 > /sys/devices/system/cpu/cpufreq/boost                               # 关闭 CPU 睿频
  cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_available_governors         # 查看可用的 CPU 频率调节器状态
  cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor                    # 查看 CPU 频率调节器状态
  echo userspace | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor   # 设置 CPU 频率调节器状态为 userspace
  cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq                    # 查看 CPU 当前频率
  cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq                    # 查看 CPU 最大频率
  echo 2000000 | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq     # 设置 CPU 最大频率
  cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq                    # 查看 CPU 最小频率
  echo 1000000 | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq     # 设置 CPU 最小频率
  cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_setspeed                    # 查看 CPU 设置频率
  echo 1000000 | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_setspeed     # 设置 CPU 设置频率


  # 日志相关
  dmesg                                            # 内核日志
  cat /proc/cmdline                                # 内核启动参数
  cat /var/log/messages                            # 系统消息日志
  cat /var/log/linuxrc.syno.log                    # 系统 linuxrc 日志 (junior mode)
  cat /tmp/installer_sh.log                        # 系统安装日志 (junior mode)
  systemctl enable  syslog-ng.service              # 开机启动所有日志
  systemctl disable syslog-ng.service              # 永久停止所有日志

  # 显卡相关
  lspci -d ::300                                   # 查看 VGA 兼容控制器
  lspci -d ::301                                   # 查看 XGA 控制器
  lspci -d ::302                                   # 查看 3D 控制器 (不是 VGA 兼容)

  # Intel GPU
  lspci -nd ::300 | cut -d' ' -f3                  # PIDVID 
  ls /dev/dri                                      # 查看显卡设备
  cat /sys/kernel/debug/dri/0/i915_frequency_info  # 显卡驱动详细信息

  # Nvidia GPU
  ls /dev/nvid*                                    # 查看显卡设备
  nvidia-smi                                       # 显卡驱动详细信息

  # 管理软件包
  synopkg list                                     # 列出所有已安装软件包
  synopkg show <package_name>                      # 查看软件包信息
  synopkg install <package_path_or_url>            # 安装软件包
  synopkg install "$(synopkg show CodecPack 2>/dev/null | jq -r '.link')"    # 安装软件包, url 方式
  synopkg install_from_server CodecPac             # 安装软件包, 自动从服务器下载
  synopkg uninstall <package_name>                 # 卸载软件包
  synopkg start <package_name>                     # 启动软件包
  synopkg stop <package_name>                      # 停止软件包
  synopkg restart <package_name>                   # 重启软件包
 
  # 初始化
  synodsdefault --reinstall                        # 重装系统
  synodsdefault --factory-default                  # 重置系统 (清空全部数据)

  # 虚拟机
  virsh -h                                         # 列出所有虚拟机命令
  virsh list --all                                 # 列出所有虚拟机
  virsh console <guest_name>                       # 进入虚拟机控制台

  etcdctl -h                                       # 列出所有 etcd 命令
  etcdctl ls /syno/live_cluster/guests/            # 列出所有虚拟机 (etcd)

  # API
  # 获取系统信息
  synowebapi --exec api=SYNO.Core.System method=info version=3
  synowebapi --exec api=SYNO.Core.System method=info version=3 type='"firmware"'
  # 获取设备信息
  synowebapi --exec api=SYNO.Core.System.Utilization method=get version=1
  # 关机
  synowebapi --exec api=SYNO.Core.System method=shutdown version=2 local=true force=false
  # 重启
  synowebapi --exec api=SYNO.Core.System method=reboot version=2 local=true force=false

  # 关闭 自动 https 重定向
  synowebapi --exec api=SYNO.Core.Web.DSM method=set version=2 enable_https_redirect=false
  # 开启 telnet/ssh
  synowebapi --exec api=SYNO.Core.Terminal method=set version=3 enable_telnet=true enable_ssh=true ssh_port=22 forbid_console=false

  # 强制以下用户启用双重验证
  synowebapi --exec api=SYNO.Core.OTP.EnforcePolicy method=set version=1 enable_otp_enforcement=true otp_enforce_option='"none"'    # 开 管理员群组用户
  synowebapi --exec api=SYNO.Core.OTP.EnforcePolicy method=set version=1 enable_otp_enforcement=true otp_enforce_option='"user"'    # 开 所有用户
  synowebapi --exec api=SYNO.Core.OTP.EnforcePolicy method=custom_set version=1 type='"local_user"' settings='[{"id":"1026","is_enforced":true}]'
  synowebapi --exec api=SYNO.Core.OTP.EnforcePolicy method=set version=1 enable_otp_enforcement=true otp_enforce_option='"custom"'  # 开 指定用户或群组
  synowebapi --exec api=SYNO.Core.OTP.EnforcePolicy method=set version=1 enable_otp_enforcement=false otp_enforce_option='"none"'   # 关

  # 为管理员群组的用户启用自适应多重验证
  synowebapi --exec api=SYNO.SecureSignIn.AMFA.Policy method=set version=1 type='"admin"'  # 开
  synowebapi --exec api=SYNO.SecureSignIn.AMFA.Policy method=set version=1 type='"none"'   # 关

  # 启用帐户保护
  synowebapi --exec api=SYNO.Core.SmartBlock method=set version=1 enabled=true untrust_try=5 untrust_minute=1 untrust_lock=30 trust_try=10 trust_minute=1 trust_lock=30   # 开
  synowebapi --exec api=SYNO.Core.SmartBlock method=set version=1 enabled=false untrust_try=5 untrust_minute=1 untrust_lock=30 trust_try=10 trust_minute=1 trust_lock=30  # 关

  # 禁用双重验证 (admin 用户)
  synowebapi --exec api=SYNO.SecureSignIn.Method.Admin method=reset version=1 account='"admin"' keep_amfa_settings=true


  # Get MD5
  certutil -hashfile xxx.pat MD5                   # windows
  md5sum xxx.pat                                   # linux/mac
  ```
