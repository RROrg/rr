# Automated Redpill Loader

This particular project was created to facilitate my testing with Redpill and I decided to share it with other users.

It is still in alpha stage, with little documentation, but it is functional. I'm Brazilian and my English is not good, so I apologize for my translations.

I tried to make the system as user-friendly as possible, to make life easier. The loader automatically detects which device is being used, SATADom or USB, detecting its VID and PID correctly. redpill-lkm has been edited to allow booting the kernel without setting the variables related to network interfaces so the loader (and user) doesn't have to worry about that. The Jun's code that makes the zImage and Ramdisk patch is embedded, if there is a change in "zImage" or "rd.gz" by some update, the loader re-applies the patches. Builds 42218 and 42661 up to update5 are working. Automatic updates should still be disabled as we are not sure if this technique will work forever. The most important kernel modules are built into the DSM ramdisk image for automatic peripheral detection.

# Use

To use this project, download the latest image available and burn it to a USB stick or SATA disk-on-module. Set the PC to boot from the burned media and follow the informations on the screen. When booting, the user can call the "menu.sh" command from the computer itself, access via SSH or use the virtual terminal (ttyd) by typing the address provided on the screen (http://(ip):7681). The loader will automatically increase the size of the last partition and use this space as cache if it is larger than 2GiB.

## It is highly recommended to use an SSD for the loader in the case of the option via DoM or a fast USB flash drive

The menu system is dynamic and I hope it is intuitive enough that the user can use it without any problems. Its allows you to choose a model, the existing buildnumber for the chosen model, type or randomly create a serial number, add/remove addons, add/remove/view "cmdline" and "synoinfo" entries, choose the LKM version, create the loader, boot, manually edit the configuration file, choose a keymap, update and exit.

Changing addons and synoinfo entries require re-creating the loader, cmdline entries do not.

There is no need to configure the VID/PID (if using a USB stick) or define the MAC Addresses of the network interfaces. If the user wants to modify the MAC Address of any interface, he must manually add "cmdline" entries in the corresponding menu (set "netif_num" according to "mac1..4" entries).

If a model is chosen that uses the Device-tree system to define the HDs, there is no need to configure anything. In the case of models that do not use device-tree, the configurations must be done manually and for this there is an option in the "Cmdline" menu to display the SATA controllers, DUMMY ports and ports in use, to assist in the creation of the "SataPortMap", "DiskIdxMap" and "sata_remap" if necessary.

Another important point is that the loader detects whether or not the CPU has the FMA3 instruction and does not display the models that require it. So if the DS918+ and DVA3221 models are not displayed it is because of the CPU's lack of support for FMA instructions.

I developed a simple patch to no longer display the DUMMY port error on models without device-tree, the user will be able to install without having to worry about it.

# Thanks

All code was based on the work of TTG, pocopico, jumkey and others involved in continuing TTG's original redpill-load project.

More information will be added in the future.
