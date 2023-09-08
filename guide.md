
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
  1. 引导盘只支持 sata / usb.
  2. 安装盘要大于 32GB.
  3. 内存需要大于 4GB.
  4. DT的型号不支持sas控制器.

# GPU
* iGPU: https://jim.plus/
* vGPU: https://blog.kkk.rs/

# ARPL:
* ### [命令输入方法演示](https://www.bilibili.com/video/BV1T84y1P7Kq)  https://www.bilibili.com/video/BV1T84y1P7Kq  

* arpl各版本间切换(手动方式, 全量) (Any version):  
    ```shell
    # 在 shell 中下载需要的版本或者手动上传到/opt/arpl/下
    # Download the required version in the shell or manually upload it to/opt/arpl/
    curl -kL -o /opt/arpl/arpl.zip https://github.com/wjz304/arpl-i18n/releases/download/23.4.5/arpl-i18n-23.4.5.img.zip
    # 卸载挂载的引导盘
    # Uninstalling the mounted boot disk
    umount /mnt/p1 /mnt/p2 /mnt/p3
    # 解压 并写入到引导盘
    # Decompress and write to the boot disk
    unzip -p arpl.zip | dd of=`blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1` bs=1M conv=fsync
    # 重启 reboot
    reboot
    ```
* arpl各版本间切换(菜单更新, 增量)(arpl / arpl-zh_CN / arpl-i18n(ver < 23.4.5)):  
    ```shell
    # shell 下输入以下命令修改更新 repo. 
    # 如果要切换原版修改第二条命令中的 wjz304/arpl-i18n 为 fbelavenuto/arpl
    # 如果切换中文版修改第二条命令中的 wjz304/arpl-i18n 为 wjz304/arpl-zh_CN
    # Enter the following command under the shell to modify and update repo
    # If you want to switch the original version and modify wjz304/arpl-i18n to fbelavenuto/arpl in the second command.
    # If you switch to the Chinese version and modify the wjz304/arpl-i18n to wjz304/arpl_zh_CN in the second command.
    CURREPO=`grep "github.com.*update" menu.sh | sed -r 's/.*com\/(.*)\/releases.*/\1/'`
    sed -i "s|${CURREPO}|wjz304/arpl-i18n|g" /opt/arpl/menu.sh
    # 进入设置菜单执行更新arpl操作即可. 更新后请重启.
    # Simply enter the main menu and perform the update arpl operation. Please restart after the update.
    ```
* arpl 备份 (Any version):
    ```shell
    # 备份为 disk.img.gz, 自行导出.
    dd if=`blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1` | gzip > disk.img.gz
    # 结合 transfer.sh 直接导出链接
    curl -skL --insecure -w '\n' --upload-file disk.img.gz https://transfer.sh
    ```
* arpl 持久化 /opt/arpl 目录的修改 (Any version):
    ```shell
    RDXZ_PATH=/tmp/rdxz_tmp
    mkdir -p "${RDXZ_PATH}"
    (cd "${RDXZ_PATH}"; xz -dc < "/mnt/p3/initrd-arpl" | cpio -idm) >/dev/null 2>&1 || true
    rm -rf "${RDXZ_PATH}/opt/arpl"
    cp -rf "/opt/arpl" "${RDXZ_PATH}/opt"
    (cd "${RDXZ_PATH}"; find . 2>/dev/null | cpio -o -H newc -R root:root | xz --check=crc32 > "/mnt/p3/initrd-arpl") || true
    rm -rf "${RDXZ_PATH}"
    ```
* arpl 修改所有的pat下载源 (Any version):
    ```shell
    sed -i 's/global.synologydownload.com/cndl.synology.cn/g' /opt/arpl/menu.sh `find /opt/arpl/model-configs/ -type f'`
    sed -i 's/global.download.synology.com/cndl.synology.cn/g' /opt/arpl/menu.sh `find /opt/arpl/model-configs/ -type f'`
    ```
* arpl 更新慢的解决办法 (arpl-zh_CN / arpl):
    ```shell
    sed -i 's|https://.*/https://|https://|g' /opt/arpl/menu.sh 
    sed -i 's|https://github.com|https://ghproxy.homeboyc.cn/&|g' /opt/arpl/menu.sh 
    sed -i 's|https://api.github.com|http://ghproxy.homeboyc.cn/&|g' /opt/arpl/menu.sh
    ```
* arpl 去掉pat的hash校验 (Any version):
    ```shell
    sed -i 's/HASH}" ]/& \&\& false/g' /opt/arpl/menu.sh
    ```
* arpl 下获取网卡驱动 (Any version):
    ```shell
    for i in `ls /sys/class/net | grep -v 'lo'`; do echo $i -- `ethtool -i $i | grep driver`; done
    ```
* arpl 使用自定义的dts文件 (arpl(ver > v1.1-beta2a / arpl-zh_CN):
    ```shell
    # 将dts文件放到/mnt/p1下,并重命名为model.dts. "/mnt/p1/model.dts"
    sed -i '/^.*\/addons\/disks.sh.*$/a [ -f "\/mnt\/p1\/model.dts" ] \&\& cp "\/mnt\/p1\/model.dts" "${RAMDISK_PATH}\/addons\/model.dts"' /opt/arpl/ramdisk-patch.sh
    ```
* arpl 离线安装 (arpl_zh_CN(ver > ++-v1.3) / arpl-i18n(ver < 23.7.0>)):
    ```shell
    1. arpl 下
    # arpl下获取型号版本的pat下载地址 (替换以下命令中的 版本号和型号部分)
    yq eval '.builds.42218.pat.url' "/opt/arpl/model-configs/DS3622xs+.yml"
    # 将pat重命名为<型号>-<版本>.pat, 放入 /mnt/p3/dl/ 下
    # 例: /mnt/p3/dl/DS3622xs+-42218.pat

    2. pc 下
    # 通过 DG等其他软件打开arpl.img, 将pat重命名为<型号>-<版本>.pat, 放入 第3个分区的 /dl/ 下.
    ```
* arpl 增删驱动 (Any version):
    ```shell
    # 1.首先你要有对应平台的驱动 比如 SA6400 7.1.1 增加 r8125
    # 略
    # 2.解包
    mkdir -p /mnt/p3/modules/epyc7002-5.10.55
    gzip -dc /mnt/p3/modules/epyc7002-5.10.55.tgz | tar xf - -C /mnt/p3/modules/epyc7002-5.10.55
    # 3.放入或删除驱动
    # 略
    # 4.打包
    tar -cf /mnt/p3/modules/epyc7002-5.10.55.tar -C /mnt/p3/modules/epyc7002-5.10.55 .
    gzip -c /mnt/p3/modules/epyc7002-5.10.55.tar > /mnt/p3/modules/epyc7002-5.10.55.tgz
    rm -rf /mnt/p3/modules/epyc7002-5.10.55.tar /mnt/p3/modules/epyc7002-5.10.55
    ```
* arpl 开机强行进入到arpl (Any version):
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
* dsm下重启到arpl(免键盘) (Any version):
    ```shell
    sudo -i  # 输入密码
    /usr/bin/arpl-reboot.sh "config"
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
  # 驱动相关
  lsmod                                            # 查看已加载驱动  
  ls -ld /sys/class/net/*/device/driver            # 查看已加载网卡和对应驱动  
  cat /sys/class/net/*/address                     # 查看已加载网卡的MAC地址

  # 磁盘相关   
  fdisk -l                                         # 查看硬盘信息 
  ls /sys/block/                                   # 查看块设备  
  ls /sys/block/sd*                                # 查看识别的 sata 硬盘 (非设备树(dtb)的型号)    
  ls /sys/block/sata*                              # 查看识别的 sata 硬盘  (设备树(dtb)的型号)  
  ls /sys/block/nvme*                              # 查看识别的 nvme 硬盘  
  cat /sys/block/sd*/device/syno_block_info        # 查看识别的 sata 硬盘挂载点 (非设备树(dtb)的型号)  
  cat /sys/block/sata*/device/syno_block_info      # 查看识别的 sata 硬盘挂载点 (设备树(dtb)的型号)  
  cat /sys/block/nvme*/device/syno_block_info      # 查看识别的 nvme 硬盘挂载点  

  systemctl                                        # 查看服务  

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
