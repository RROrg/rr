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
* 多语言支持.
* 6.2&7.2支持.
* other.


## 说明 - Instructions
* ### [命令输入方法演示](https://www.bilibili.com/video/BV1T84y1P7Kq)  https://www.bilibili.com/video/BV1T84y1P7Kq  
* arpl各版本间切换(菜单更新, 增量):  
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
* arpl各版本间切换(手动方式, 全量):  
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


## 翻译 - Translation
* 其他语言的翻译 - Language translation work:
    ```shell
    # If it does not involve adding or deleting, the following process is not required.
    sudo apt install gettext
    git clone https://github.com/wjz304/arpl-i18n.git
    cd arpl-i18n/files/board/arpl/overlayfs/opt/arpl
    xgettext -L Shell --keyword=TEXT *.sh -o lang/arpl.pot
    sed -i 's/charset=CHARSET/charset=UTF-8/' lang/arpl.pot
    # You need to replace the language you need and translate the po file.
    msginit -i lang/arpl.pot -l zh_CN.UTF-8 -o lang/zh_CN.po
    # This process will be automatically processed during packaging.
    msgfmt lang/zh_CN.po -o lang/zh_CN.mo
    ```

## 教程 - Usage 
* 中文: https://www.bilibili.com/video/BV1jk4y1Y7B7  
    ##### `(From: http://mi-d.cn)`
* English: https://www.youtube.com/watch?v=mmwKCOiHGWA
    ##### `(From: @markstar6449)`


## 打赏一下
* > ### 作者: Ing  QQ群: 21609194  QQ频道: 0pg8m22666
* <img src="https://raw.githubusercontent.com/wjz304/wjz304/master/my/20220908134226.jpg" width="400">



