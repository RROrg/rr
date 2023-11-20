
# ENV:
* ### 常用工具:   
   * telnet 工具 putty (下载: https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html)  
   * ssh 工具 FinalShell (下载: https://www.hostbuf.com/t/988.html)  
   * sftp 工具 WinSCP (下载: https://winscp.net/eng/index.php)
   * 文本编辑工具 Notepad3 (下载: https://github.com/rizonesoft/Notepad3/releases)
   * 镜像写盘工具 Rufus (下载: https://rufus.ie/zh/)
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

# 安装条件
  1. 引导盘要大于 2GB.
  2. 安装盘要大于 32GB.
  3. 内存需要大于 4GB.
  4. DT的型号（kver 4.4）目前不支持HBA扩展卡.

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
    LOADER_DISK="$(blkid | grep 'LABEL="RR3"' | cut -d3 -f1)"
    unzip -p rr.zip | dd of=${LOADER_DISK} bs=1M conv=fsync
    # 重启 reboot
    reboot
    ```

* RR 开机强行进入到 RR shell:
    ```shell
    # 在 wait IP 的时候, 快速的连上, 杀死 boot.sh 进程.
    kill `ps | grep -v grep | grep boot.sh | awk '{print $1}'`
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
    /usr/bin/rr-reboot.sh "config"
    ```
* dsm下修改sn (Any version):
    ```shell
    sudo -i  # 输入密码
    SN=xxxxxxxxxx   # 输入你要设置的SN
    echo 1 > /proc/sys/kernel/syno_install_flag
    [ -b "/dev/synoboot1" ] && (mkdir -p /tmp/synoboot1; mount /dev/synoboot1 /tmp/synoboot1)
    [ -f "/tmp/synoboot1/user-config.yml" ] && OLD_SN=`grep '^sn:' /tmp/synoboot1/user-config.yml | sed -r 's/sn:(.*)/\1/; s/[\" ]//g'`
    [ -n "${OLD_SN}" ] && sed -i "s/${OLD_SN}/${SN}/g" /tmp/synoboot1/user-config.yml
    reboot
    ```
* 群晖 opkg 包管理:
    ```shell
    wget -O - http://bin.entware.net/x64-k3.2/installer/generic.sh | /bin/sh
    /opt/bin/opkg update
    /opt/bin/opkg install rename
    ```

## DEBUG
* log:
  ```
  # 内核相关
  sysctl -n kernel.syno_serial                     # 查看当前鉴权的SN
  cat /proc/sys/kernel/syno_serial                 # 查看当前鉴权的SN
  sysctl -n kernel.syno_mac_address1               # 查看当前鉴权的mcac1 (kernel.syno_mac_addresses)
  cat /proc/sys/kernel/syno_mac_address1           # 查看当前鉴权的mcac1 (/proc/sys/kernel/syno_mac_addresses)
  sysctl -n kernel.syno_internal_netif_num         # 查看当前鉴权的网卡数量
  cat /proc/sys/kernel/syno_internal_netif_num     # 查看当前鉴权的网卡数量
  nproc                                            # 查看当前线程数
  
  # 驱动相关
  lsmod                                            # 查看已加载驱动
  ls -ld /sys/class/net/*/device/driver            # 查看已加载网卡和对应驱动
  cat /sys/class/net/*/address                     # 查看已加载网卡的MAC地址

  # 磁盘相关
  fdisk -l                                         # 查看硬盘信息
  lspci -d ::106                                   # 查看 ATA 控制器
  lspci -d ::107                                   # 查看 HBA 控制器
  ls -l /sys/class/scsi_host                       # 查看硬盘 host 信息
  ls /sys/block/                                   # 查看块设备
  ls /sys/block/sd*                                # 查看识别的 sata 硬盘 (非设备树(dtb)的型号)
  ls /sys/block/sata*                              # 查看识别的 sata 硬盘  (设备树(dtb)的型号)
  ls /sys/block/nvme*                              # 查看识别的 nvme 硬盘
  cat /sys/block/sd*/device/syno_block_info        # 查看识别的 sata 硬盘挂载点 (非设备树(dtb)的型号)  
  cat /sys/block/sata*/device/syno_block_info      # 查看识别的 sata 硬盘挂载点 (设备树(dtb)的型号)
  cat /sys/block/nvme*/device/syno_block_info      # 查看识别的 nvme 硬盘挂载点

  # 服务相关
  systemctl                                        # 查看服务  
  netstat -tunlp                                   # 查看端口  
  systemctl disable cpufreq.service                # 禁用 CPU 频率调节器

  # 日志相关
  dmesg                                            # 内核日志
  cat /proc/cmdlime                                # 引导参数
  cat /var/log/linuxrc.syno.log                    # 引导态下启动日志
  cat /var/log/messages                            # 引导态下操作日志

  # Intel GPU
  lspci -n | grep 0300 | cut -d " " -f 3           # PIDVID
  ls /dev/dri                                      # 查看显卡设备
  cat /sys/kernel/debug/dri/0/i915_frequency_info  # 显卡驱动详细信息

  # Nvidia GPU
  ls /dev/nvid*                                    # 查看显卡设备
  nvidia-smi                                       # 显卡驱动详细信息

  # Get MD5
  certutil -hashfile xxx.pat MD5                   # windows
  md5sum xxx.pat                                   # linux/mac
  ```
