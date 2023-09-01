# warewulf-overlay-gpu

Reading from a cloned copy? Try `pandoc README.md -t plain`

## Description

`warewulf-overlay-gpu` installs drivers and optionally configures GPUs on a stateless node.

## Overlay Tags

The following tags can be set in the node config to control the GPU setup:

### `ovl_gpu_driver_version`

Sets the version of the driver to install. This value should be the
corresponding ID for a driver branch, see the 
[CUDA Installaion Guide](https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html#precompiled-streams-support-matrix) for additional details.
For example, to set the version to the 520 stream:

```
wwctl node set --tagadd "ovl_gpu_cuda_version=520" NODENAME
```

Defaults to: `latest`

### `ovl_gpu_driver_disable`

Gracefully aborts setup of the GPU drivers. Useful for nodes that will pass
GPUs through to VM guests and for debugging when you want to run the GPU setup
manually.

```
wwctl node set --tagadd "ovl_gpu_driver_disable=true" NODENAME
```

Defaults to `false`

### `ovl_gpu_driver_dkms_disable`

Disables use of the dkms version of the driver. Before disabling consider:

* The precompiled drivers pull in dependencies that may conflict with MOFED or other installed packages.
* The kmod drivers use weak-modules support that may not work with custom kernels.

```
wwctl node set --tagadd "ovl_gpu_driver_dkms_disable=true" NODENAME
```

Defaults to `false`

### `ovl_gpu_virtualgl_enable`

Enables configuration of teh node for VirtualGL. Work in progress, expect
problems and please submit suggestions for improvement.

```
wwctl node set --tagadd "ovl_gpu_virtualgl_enable=true" NODENAME
```

## Repository

The overlay will check the current dnf config for the nVidia repo and use that
if found. If no repo is present it will set up the upstream nVidia repo. This
allows a local mirror to be pre-configured in the dnf config if desired.

## The GPU Card Database

The overlay file `./rootfs/warewulf/etc/warewulf-overlay-gpu-carddb` contains
the PCI IDs of teh cards we recognize and will need to be updated to add new
cards as needed. The cards are represented by an entry in the bash associative array like:

```
CUDA_CARDDB['10de:1b80']="GP104 [GeForce GTX 1080]"
```
Note that the format of these entries may be later expanded to have values that
are a comma separated list of additional data about the individual GPUs.

### Collecting new card info for the GPU Card Database

```
# Harvest from lspic output, no driver required.
clush -w GPUNODELIST lspci -nn | grep -i nvidia | awk '!($1=$2="")'  | sort | uniq -c | sort

# Collect from nvidia-smi, presents a chicken and egg problem but can give better descriptions.
clush -w GPUNODELIST "nvidia-smi -q | grep 'Product Name'" | awk '!($1=$2="")' | sort | uniq -c | sort
```

## App and Use Case Specific Notes

### Slurm

Insert some sample ways to configure Gres here.

### VMware GeForce passthru hints

Using VMWare based nodes with a GPU passthru to a GeForce device.

Host Settings:

* Set host GPU mode to Shared Direct in Graphics tab when·setting up pass-thru.

Guest settings:

* Boot Options | Firmware = EFI
* svga.present = FALSE  (note this disables the console)
* hypervisor.cpuid.v0 = FALSE
* pciPassthru.64bitMMIOSizeGB = 64
* pciPassthru.use64bitMMIO = TRUE



