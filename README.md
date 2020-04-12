# GPU/USB audio interface Passthrough from Manjaro Linux

##### Sources:

1. https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF
and discusson: https://wiki.archlinux.org/index.php/Talk:PCI_passthrough_via_OVMF#UEFI_(OVMF)_Compatibility_in_VBIOS

2. https://passthroughpo.st/quick-dirty-arch-passthrough-guide/

3. https://medium.com/@dubistkomisch/gaming-on-arch-linux-and-windows-10-with-vfio-iommu-gpu-passthrough-7c395dde5c2

5. https://www.tauceti.blog/post/linux-amd-x570-nvidia-gpu-pci-passthrough-5-looking-glass/ - five part series for amd setup

6. https://heiko-sieger.info/iommu-groups-what-you-need-to-consider/#How_to_determine_IOMMU_capabilities

##### Required downloads:

1. virtio* drivers for windows10 

**Link**: [here](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.160-1/)

##### Disclamer:

Most of this stuff is in the archlinux guide at the top, read more of that if any of this is confusing or something terribly goes wrong. This is my rig:

---

## Install second GPU ##

I installed secondary gpu for the host after the OS was configured and had to use mhwd to remove drivers for both GPUs and reinstall them again to make it work. (old Radeon for host and 1660 TI for guests)

## PCI passthrough via OVMF (GPU)

### Initialization

1. enable virtualization, set IOMMU to enabled instead of auto

2. modify kernel settings to grub `/etc/default/grub`  by adding 

amd_iommu=on (technically unnecessary in my case as kernel was recognizing and enabling it by defautl)
iommu=pt (recommended by arch wiki to optimize performance on some hardware)
video=efifb:off (kernel was somehow still grabbing the card even though the drivers were showing as virtio and causing the "BAR 3: cannot reserve [mem]" error in dmesg) 

`$ sudo nano /etc/default/grub`

```
GRUB_CMDLINE_LINUX_DEFAULT="quiet apparmor=1 security=apparmor udev.log_priority=3 amd_iommu=on iommu=pt video=efifb:off"
```

3. re-configure your grub:

`$ sudo grub-mkconfig -o /boot/grub/grub.cfg`


4. reboot


`$ sudo reboot now`


### Isolating the GPU

One of the first things you will want to do is isolate your GPU. The goal of this is to prevent the Linux kernel from loading drivers that would take control of the GPU. Because of this, it is necessary to have two GPUs installed and functional within your system. One will be used for interacting with your Linux host (just like normal), and the other will be passed-through to your Windows guest. In the past, this had to be achieved through using a driver called pci-stub. While it is still possible to do so, it is older and holds no advantage over its successor –vfio-pci.

1. find the device ID of the GPU that will be passed through by running lscpi

`$ lspci -nn` or better yet `for d in /sys/kernel/iommu_groups/*/devices/*; do n=${d#*/iommu_groups/*}; n=${n%%/*}; printf 'IOMMU Group %s ' "$n"; lspci -nns "${d##*/}"; done;`

and look through the given output until you find your desired GPU, they're **bold** in this case:
```
IOMMU Group 18 26:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU116 [GeForce GTX 1660 Ti] [**10de:2182**] (rev a1)
IOMMU Group 18 26:00.1 Audio device [0403]: NVIDIA Corporation Device [**10de:1aeb**] (rev a1)
IOMMU Group 18 26:00.2 USB controller [0c03]: NVIDIA Corporation Device [**10de:1aec**] (rev a1)
IOMMU Group 18 26:00.3 Serial bus controller [0c80]: NVIDIA Corporation Device [**10de:1aed**] (rev a1)
```

### Configuring vfio-pci and Regenerating your Initramfs

Next, we need to instruct vfio-pci to target the device in question through the ID numbers gathered above.

1. edit `/etc/modprobe.d/vfio.conf` and adding the following line with **your ids from the last step above**:

```
options vfio-pci ids=10de:2182,10de:1aeb,10de:1aec,10de:1aed
```

Next, we will need to ensure that vfio-pci is loaded before other graphics drivers. 

2. edit `/etc/mkinitcpio.conf`. At the very top of your file you should see a section titled MODULES. Towards the bottom of this section you should see the uncommented line: MODULES= . Add the in the following order before any other drivers (nouveau, radeon, nvidia, etc but in my case it was empty) which may be listed: vfio vfio_iommu_type1 vfio_pci vfio_virqfd. The line should look like the following:

```
MODULES="vfio_pci vfio vfio_iommu_type1 vfio_virqfd"
```

In the same file, also make sure modconf is present in the HOOKS line:

```
HOOKS="modconf"
```

3. rebuild initramfs, make sure to specify right kernel verion.

`mkinitcpio -p linux54`

4. reboot
`$ sudo reboot now`

### Checking whether it worked

1. check pci devices:

`$ lspci -nnk`

Find your GPU and ensure that under “Kernel driver in use:” vfio-pci is displayed:


```
1:00.0 VGA compatible controller [0300]: NVIDIA Corporation GM204 [GeForce GTX 980] [10de:13c0] (rev a1)
	Subsystem: Micro-Star International Co., Ltd. [MSI] GM204 [GeForce GTX 980] [1462:3177]
	Kernel driver in use: vfio-pci
	Kernel modules: nouveau
01:00.1 Audio device [0403]: NVIDIA Corporation GM204 High Definition Audio Controller [10de:0fbb] (rev a1)
	Subsystem: Micro-Star International Co., Ltd. [MSI] GM204 High Definition Audio Controller [1462:3177]
	Kernel driver in use: vfio-pci
	Kernel modules: snd_hda_intel
```

2. ???
3. profit


---
 

### Configuring OVMF and Running libvirt

1. download libvirt, virt-manager, ovmf, and qemu (these are all available in the AUR). OVMF is an open-source UEFI firmware designed for KVM and QEMU virtual machines. ovmf may be omitted if your hardware does not support it, or if you would prefer to use SeaBIOS. However, configuring it is very simple and typically worth the effort.

`sudo pacman -S libvirt virt-manager ovmf qemu`

2. edit `/etc/libvirt/qemu.conf` and add the path to your OVMF firmware image:

```
nvram = ["/usr/share/ovmf/ovmf_code_x64.bin:/usr/share/ovmf/ovmf_vars_x64.bin"]
```
**I ran into this bug:** https://bugs.archlinux.org/task/64175#comment183769
had to delete the content in /usr/share/qemu/firmware to make it work, fix is available right now in testing branch, need to re-evaluate after the update

3. start and enable both libvirtd and its logger, virtlogd.socket in systemd if you use a different init system, substitute it's commands in for systmectl start

```
$ sudo systemctl start libvirtd.service 
$ sudo systemctl start virtlogd.socket
$ sudo systemctl enable libvirtd.service
$ sudo systemctl enable virtlogd.socket
```
enable default network bridge:
sudo virsh net-start default
sudo virsh net-autostart default

With libvirt running, and your GPU bound, you are now prepared to open up virt-manager and begin configuring your virtual machine. 

---


### virt-manager, a GUI for managing virtual machines

#### setting up virt-manager

**virt-manager** has a fairly comprehensive and intuitive GUI, so you should have little trouble getting your Windows guest up and running. 

1. download virt-manager

`$ sudo pacman -S virt-manager`

2. add yourself to the libvirt group (replace vanities with your username)

`$ sudo usermod -a -G libvirt vanities`

3. launch virt-manager

`$ virt-manager &`

4. when the VM creation wizard asks you to name your VM (final step before clicking "Finish"), check the "Customize before install" checkbox.

5. in the "Overview" section, set your chipset to Q35 and firmware to "UEFI". If the option is grayed out, make sure that you have correctly specified the location of your firmware in /etc/libvirt/qemu.conf and restart libvirtd.service by running  `sudo systemctl restart libvirtd`

![alt text](https://github.com/vanities/GPU-Passthrough-Arch-Linux-to-Windows10/blob/master/pics/uefi.png)

**I ran into this bug:** https://bugs.archlinux.org/task/64175#comment183769
had to delete the content in /usr/share/qemu/firmware to make it work, fix is available right now in testing branch, need to re-evaluate after the update

6. in the "CPUs" section, change your CPU model to "**host-passthrough**". If it is not in the list, you will have to type it by hand. This will ensure that your CPU is detected properly, since it causes libvirt to expose your CPU capabilities exactly as they are instead of only those it recognizes (which is the preferred default behavior to make CPU behavior easier to reproduce). Without it, some applications may complain about your CPU being of an unknown model.
![alt text](https://github.com/vanities/GPU-Passthrough-Arch-Linux-to-Windows10/blob/master/pics/cpu.png)

I also set topology manually but might need to play with it a bit further (1 socket, 2 cores, 2 threads)


7. go into "Add Hardware" and add a Controller for **SCSI** drives of the "VirtIO SCSI" model. (**didn't do that, selected virtio disk bus directly for my drive in step 8**)
![alt text](https://github.com/vanities/GPU-Passthrough-Arch-Linux-to-Windows10/blob/master/pics/virtioscsi.png)


8. then change the default IDE disk for a **SCSI** disk, which will bind to said controller.
![alt text](https://github.com/vanities/GPU-Passthrough-Arch-Linux-to-Windows10/blob/master/pics/scsi.png)


a. windows VMs will not recognize those drives by default, so you need to download the ISO containing the drivers from the link at the top of the page and add an **SATA** CD-ROM storage device linking to said ISO, otherwise you will not be able to get Windows to recognize it during the installation process.

9. make sure there is another **SATA** CD-ROM device that is handling your windows10 iso from the top links.
![alt text](https://github.com/vanities/GPU-Passthrough-Arch-Linux-to-Windows10/blob/master/pics/satavirtio.png)

10. setup your GPU, navigate to the “Add Hardware” section and select all GPU related devices that were isolated previously in the **PCI** tab
![alt text](https://github.com/vanities/GPU-Passthrough-Arch-Linux-to-Windows10/blob/master/pics/gpu.png)
![alt text](https://github.com/vanities/GPU-Passthrough-Arch-Linux-to-Windows10/blob/master/pics/gpu-audio.png)

11. lastly, attach your usb keyboard and mouse (use a second pair)
![alt text](https://github.com/vanities/GPU-Passthrough-Arch-Linux-to-Windows10/blob/master/pics/keyboard.png)
![alt text](https://github.com/vanities/GPU-Passthrough-Arch-Linux-to-Windows10/blob/master/pics/mouse.png)

12. don't forget to pass some good RAM as well
![alt text](https://github.com/vanities/GPU-Passthrough-Arch-Linux-to-Windows10/blob/master/pics/ram.png)

13. Enable edit xml in preferences and hide virtualization from nvidia driver using following properties in features section:
- kvm hidden state
- vendor_od
- ioapic 

```xml
<features>
    <acpi/>
    <apic/>
    <hyperv>
      <relaxed state="on"/>
      <vapic state="on"/>
      <spinlocks state="on" retries="8191"/>
      <vendor_id state="on" value="2134657890ab"/>
    </hyperv>
    <kvm>
      <hidden state="on"/>
    </kvm>
    <vmport state="off"/>
    <ioapic driver="kvm"/>
</features>
```
14. edit GPU devices to make it a single multifuction device, i.e. same bus slot and enumerated functions:
```xml
<hostdev mode="subsystem" type="pci" managed="yes">
  <source>
    <address domain="0x0000" bus="0x26" slot="0x00" function="0x0"/>
  </source>
  <address type="pci" domain="0x0000" bus="0x06" slot="0x00" function="0x0" multifunction="on"/>
</hostdev>
```
```xml
<hostdev mode="subsystem" type="pci" managed="yes">
  <source>
    <address domain="0x0000" bus="0x26" slot="0x00" function="0x1"/>
  </source>
  <address type="pci" domain="0x0000" bus="0x06" slot="0x00" function="0x1"/>
</hostdev>```
```xml
<hostdev mode="subsystem" type="pci" managed="yes">
  <source>
    <address domain="0x0000" bus="0x26" slot="0x00" function="0x2"/>
  </source>
  <address type="pci" domain="0x0000" bus="0x06" slot="0x00" function="0x2"/>
</hostdev>
```
```xml
<hostdev mode="subsystem" type="pci" managed="yes">
  <source>
    <address domain="0x0000" bus="0x26" slot="0x00" function="0x3"/>
  </source>
  <address type="pci" domain="0x0000" bus="0x06" slot="0x00" function="0x3"/>
</hostdev>
```

15. I also removed USB redirectors and bunch of sumulated devices such as tablet/video etc. (technically after installing windows as I was troubleshooting GPU passthrough)


#### installing windows

1. test to see if it works by pressing the **play** button after configuring your VM and install windows

You may see this screen, just type `exit` and bo to the BIOs screen.
![alt text](https://github.com/vanities/GPU-Passthrough-Arch-Linux-to-Windows10/blob/master/pics/exit.jpg)

From the BIOs screen, select and `enter` the **Boot Manager**
![alt text](https://github.com/vanities/GPU-Passthrough-Arch-Linux-to-Windows10/blob/master/pics/select_boot.jpg)

Lastly, pick one of the DVD-ROM ones from these menus
![alt text](https://github.com/vanities/GPU-Passthrough-Arch-Linux-to-Windows10/blob/master/pics/select_dvd.jpg)

2. from here, you should be able to see windows 10 booting up, we need to load the **virtio-scsi** drivers

When you get to **Windows Setup** click `Custom: Install windows only (advanced)`
![alt text](https://github.com/vanities/GPU-Passthrough-Arch-Linux-to-Windows10/blob/master/pics/advanced_windows.JPG)

You should notice that our SCSI hard drive hasn't been detected yet, click `Load driver`
![alt_text](https://github.com/vanities/GPU-Passthrough-Arch-Linux-to-Windows10/blob/master/pics/load_drivers.jpg)

Select the correct CD-ROM labled `virto-win-XXXXX**`
![alt_text](https://github.com/vanities/GPU-Passthrough-Arch-Linux-to-Windows10/blob/master/pics/select_iso.jpg)

Finally, select the `amd64` architecture
![alt_text](https://github.com/vanities/GPU-Passthrough-Arch-Linux-to-Windows10/blob/master/pics/select_arch.jpg)

3. your **SCSI** hard drive device should be there and you should be able to contiune the windows10 install


---


## Performance Tuning

Check out my [virth xml file](https://github.com/olaf500/GPU-Passthrough-Manjaro-Linux-to-Windows10/blob/master/win10-gpu.xml)

### CPU pinnging

#### CPU topology

1. check your cpu topology by running

`lscpu -e`

![alt_text](https://github.com/vanities/GPU-Passthrough-Arch-Linux-to-Windows10/blob/master/pics/lscpu.png)


### editing virsh

edit by running something similar with your desired editor and VM name:

`sudo EDITOR=nvim virsh edit win10`

if this doesn't work, check your VM name:

`sudo virsh list`

![alt_text](https://github.com/vanities/GPU-Passthrough-Arch-Linux-to-Windows10/blob/master/pics/cpupinning.png)

your virsh config file should look something like this if your cpu is like mine, otherwise revert to the arch guide:
[cpu-pinning guide](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF#CPU_pinning)

### enabling hugepages
1. edit `/etc/defualt/grub`

`$ sudo nvim /etc/default/grub`

2. add `hugepages=2048` to **GRUB_COMMAND_LINE_DEFAULT**

your final grub should look like this:

![alt_text](https://github.com/vanities/GPU-Passthrough-Arch-Linux-to-Windows10/blob/master/pics/grub.png)

3. re-configure your grub:

`$ sudo grub-mkconfig -o /boot/grub/grub.cfg`

4. reboot and test it out

### Networking setup
libvirt: https://jamielinux.com/docs/libvirt-networking-handbook/index.html
NetworkManager https://wiki.archlinux.org/index.php/NetworkManager
- removed Ethernet interface from a host in NetworkManager
- setup bridge and used it to expose VMs on public interface

### USB Passthrough
Ryzen 3rd gen have an issue with the current BIOS (7B85v1B/Release Date 2019-11-13 which includes AMD ComboPI1.0.0.4 Patch B (SMU v46.54)) where FLR flag is set on PCIE devices for Matisse USB hub and Starship/Matisse HD Audio Controllers, but devices themselves do not support resets. When passed through, they lockup the host. See description at https://www.reddit.com/r/VFIO/comments/eba5mh/workaround_patch_for_passing_through_usb_and/

it ultimately required a kernel patch (this is for linux54):
```diff
diff --git a/drivers/pci/quirks.c b/drivers/pci/quirks.c
index 29f473ebf20f..62e0578d3f72 100644
--- a/drivers/pci/quirks.c
+++ b/drivers/pci/quirks.c
@@ -5042,6 +5042,10 @@ static void quirk_intel_no_flr(struct pci_dev *dev)
 DECLARE_PCI_FIXUP_EARLY(PCI_VENDOR_ID_INTEL, 0x1502, quirk_intel_no_flr);
 DECLARE_PCI_FIXUP_EARLY(PCI_VENDOR_ID_INTEL, 0x1503, quirk_intel_no_flr);
 
+/* FLR causes Ryzen 3000s built-in HD Audio & USB Controllers to hang on VFIO passthrough */
+DECLARE_PCI_FIXUP_EARLY(PCI_VENDOR_ID_AMD, 0x149c, quirk_intel_no_flr);
+DECLARE_PCI_FIXUP_EARLY(PCI_VENDOR_ID_AMD, 0x1487, quirk_intel_no_flr);
+
 static void quirk_no_ext_tags(struct pci_dev *pdev)
 {
 	struct pci_host_bridge *bridge = pci_find_host_bridge(pdev->bus);
```

kernel build process described here: https://forum.manjaro.org/t/how-to-compile-the-mainline-kernel-the-manjaro-way/51700/10
but ultimately you need to:
* clone repo https://forum.manjaro.org/t/how-to-compile-the-mainline-kernel-the-manjaro-way/51700/10
* add patch file to the root of your working directory, where most likely bunch of other manjaro patches will be
* add your patch to sources, SHA256 and add command for patching to the PKGBUILD:
```sh
# TODO: remove if/when AMD deals with it 
  # https://www.reddit.com/r/VFIO/comments/eba5mh/workaround_patch_for_passing_through_usb_and/
  patch -Np1 -i "${srcdir}/no_flr.patch"
```
* makepkg -s (in my case took ~16-17 minutes to build the kernel)
* sudo pacman -U linux54-headers-5.4.22-1-x86_64.pkg.tar.xz linux54-5.4.22-1-x86_64.pkg.tar.xz

once you reboot with new kernel, USB controller (0x149c) passthrough worked for me

### Stability issue with amd-ucode package
update caused instability and hardware error for CPU 20200302.r1589.0148cfe-1. reverted to 20200224.r1582.efcfa03-1 and added amd-ucode to the list of ignored packages in /etc/pacman.conf

### HiDPI scaling with mixed monitors
Not related to GPU passthrough thought, just to keep track

XFCE 2x scaling factor is ok for hiDPI monitor but a secondary one everything is too big. Xrandr solves it and arandr makes it easy to generate layout
```
#!/bin/sh
xrandr --output DisplayPort-0 --mode 3840x2160 --pos 0x0 --rotate normal --output HDMI-0 --mode 1920x1080 --pos 3840x0 --rotate normal --scale 2x2 --output DVI-0 --off
```

If hiDPI is still too big, you can apply fractional scaling with xrandr by adding --scale 1.25x1.25 to that output. When screens change configuration, you might need to reapply it, I didn't find a solution that does it out of the box. I also added it as a startup script in XFCE settings/Sessions and startups/Applicaiton Autostart/
```
sh -c "sleep 3 && /home/max/.screenlayout/dual1.sh"
```

### Autosuspend of external audio interface
An annoying thing that pulse audio was doing. Comment out in /etc/pulse/default.pa
```
load-module module-suspend-on-idle
```
and restart the service with ```systemctl restart --user pulseaudio```

### Set discard option to unmap for VirtIO drivers
- for SSDs mounted as RAW guest OS should perform the trim (how to verify that? https://askubuntu.com/questions/464306/a-command-which-checks-that-trim-is-working)
- for qcow2 drives it should release space on deletes

