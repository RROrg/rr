# 自动Redpill装载程序

这个特别的项目是为了方便我用Redpill进行测试而创建的，我决定与其他用户分享它。

我是巴西人，我的英语不好，所以我为我的翻译道歉。

我试着让这个系统尽可能的人性化，让生活更简单。加载器自动检测哪个设备正在使用，SATADoM或USB，检测其VID和PID正确。redpilll -lkm已经被编辑，允许在不设置与网络接口相关的变量的情况下引导内核，这样加载程序(和用户)就不必担心了。制作zImage和Ramdisk补丁的Jun代码是嵌入的，如果smallupdate在“zImage”或“rd.gz”中有变化，加载器会重新应用补丁。最重要的内核模块被内置到DSM ramdisk映像中，用于自动外围设备检测。

# 重要注意事项

 - 一部分用户启动时间过长。在这种情况下，强烈建议在DoM选项或快速USB闪存驱动器的情况下使用SSD作为加载器;

 - 你必须有至少4GB的内存，无论是在裸机和虚拟机;

 - DSM内核兼容SATA端口，不兼容SAS/SCSI等。对于设备树型号，只有SATA端口工作。对于其他型号，可以使用其他类型的磁盘;

 - 可以使用HBA卡，但SMART和序列号仅适用于DS3615xs, DS3617xs和DS3622xs+型号。

# 使用

## 一般

要使用这个项目，请下载可用的最新映像，并将其刻录到USB闪存或SATA硬盘模块上。将电脑设置为从刻录媒体启动，并遵循屏幕上的信息。

如果最后一个分区的大小大于2GiB，加载器将自动增加该分区的大小，并将该空间用作缓存。

## 访问加载器

### 通过终端

从计算机本身调用“menu.sh”命令。

### 通过网络

从另一台机器进入同一网络，在浏览器中输入屏幕上提供的地址`http://<ip>:7681`。

### 通过ssh

从另一台机器进入同一网络，使用ssh客户端，用户名： `root` 和密码： `Redp1lL-1s-4weSomE`

## 使用加载器

菜单系统是动态的，我希望它足够直观，用户可以没有任何问题的使用它

不需要配置VID/PID(如果使用u盘)或定义网络接口的MAC地址。如果用户想修改任何接口的MAC地址，使用“Change MAC”到“cmdline”菜单。

如果选择使用Device-tree系统定义hd的模型，则不需要配置任何内容。在不使用device-tree的情况下，配置必须手动完成，在“cmdline”菜单中有一个选项可以显示SATA控制器、虚拟端口和正在使用的端口，如果需要，可以帮助创建“satapportmap”、“DiskIdxMap”和“sata_remap”。

另一个重要的一点是，加载器检测CPU是否有MOVBE指令，并且不显示需要它的型号。因此，如果DS918+和DVA3221型号没有显示，这是因为CPU缺乏对MOVBE指令的支持。您可以禁用此限制并自行承担测试风险。

我开发了一个简单的补丁，在没有device-tree的模型上不再显示虚拟端口错误，用户将能够安装而不必担心它。

## 快速入门指南

启动加载程序后，应该出现以下屏幕。输入 menu.sh 并按 `<ENTER>`:

![](doc/first-screen.png)

如果你愿意，你可以通过网络访问:

![](doc/ttyd.png)

选择“型号”选项，并选择您喜欢的型号:

![](doc/model.png)

选择“Buildnumber”选项并选择第一个选项:

![](doc/buildnumber.png)

进入“Serial”菜单，选择“Generate a random Serial number”。

选择“Build”选项，等待加载器生成:

![](doc/making.png)

选择“Boot”选项，等待DSM启动:

![](doc/DSM%20boot.png)

由于DSM内核不会在屏幕上显示消息，因此需要通过浏览器访问地址`http://<ip>`来继续配置DSM的过程。
有一些关于如何在互联网上配置DSM的教程，这里不做介绍。

# 教程

ARPL用户(Rikkie)创建了一个在proxmox服务器上安装ARPL的教程:
https://hotstuff.asia/2023/01/03/xpenology-with-arpl-on-proxmox-the-easy-way/

# 麻烦/问题/等等

如果您的问题已经被讨论和解决，请搜索论坛 https://xpenology.com/forum 如果你找不到解决方案，请使用 github issues。

# 感谢

所有代码都是基于TTG、pocopico、jumkey和其他参与继续TTG最初的redpill-load项目的人的工作。

更多信息将在未来添加。
