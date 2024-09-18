# warewulf-overlay-gpu

Reading from a cloned local copy? Try `pandoc README.md -t plain`

## Description

`warewulf-overlay-gpu` installs drivers and optionally configures GPUs on a stateless node.

## Overlay Tags

The following tags can be set in the node config to control the GPU setup:

### `ovl_gpu_driver_install`

Enable/Disable GPU driver install. If set to `false`/`disable`/`no`, then GPU
driver install and related setup/configuration will be gracefuly aborted, e.g.
the setup service will return success without actually installing or
configuring anything. A use case for this might be a GPU server which will pass
through GPUs to VMs rather than use them directly from the provisioned OS.

```
wwctl node set --tagadd "ovl_gpu_driver_install=false" NODENAME
```

Defaults to: `true`

### `ovl_gpu_driver_type`

Set the nVidia driver type. By default the older proprietary driver will be
used, setting this tag to `open` will switch to the newer `open` driver. 

```
wwctl node set --tagadd=ovl_gpu_driver_type=open NODENAME
```

Defaults to the proprietary driver (no value set).

### `ovl_gpu_gsp_firmware_enable`

Enable/Disable GSP firmware. See `/etc/modprobe.d/nvidia-gsp.conf.ww` where
this option is conditionally enabled for the loading of the nvidia.ko module.

```
wwctl node set --tagadd "ovl_gpu_gsp_firmware_enable=true" NODENAME
```

Defaults to: `false` (disable GSP Firmware)

### `ovl_gpu_cuda_version`

Specifies a version of CUDA to install, currently not implemented.

Recommendation is to install CUDA in an NFS location that is shared by all
nodes. See [Lmod](https://lmod.readthedocs.io/en/latest/) for a way to make
that easy to manage.

### `ovl_gpu_dcgm_manager_enable`

Enable the installation of Datacenter GPU Manager package(s) and start of
related services.

```
wwctl node set --tagadd "ovl_gpu_dcgm_manager_enable=true" NODENAME
```

Defaults to: `false`

### `ovl_gpu_virtualgl_enable`

Enables configuration of the node for VirtualGL. Work in progress, expect
problems and please submit suggestions for improvement.

```
wwctl node set --tagadd "ovl_gpu_virtualgl_enable=true" NODENAME
```

Defaults to: `false`

### `ovl_gpu_xorg_enable`

Configure the first GPU for use by Xorg.

```
wwctl node set --tagadd "ovl_gpu_xorg_enable=true" NODENAME
```

Defaults to: `false`

### `ovl_gpu_fabric_manager_enable`

Enables installation of Fabric Manager and starts associated services. This is
only required on systems with NVLink switches (8 GPU SXM systems and up).

TODO: Add an autodetect option to do thei right thing based on the detected
GPUs and fabrics.

```
wwctl node set --tagadd "ovl_gpu_fabric_manager_enable=true" NODENAME
```

Defaults to: `false`

### `ovl_gpu_nvidia_peermem_enable`

Enables loading of the `nvidia-peermem` module. See the the [GPUDirect
RDMA](https://docs.nvidia.com/cuda/gpudirect-rdma/index.html#nvidia-peermem)
docs.

```
wwctl node set --tagadd "ovl_gpu_nvidia_peermem_enable=true" NODENAME
```

Defaults to: `false`

### `ovl_gpu_driver_version`

Sets the version of the driver to install. This value should be the
corresponding ID for a driver branch, see the [CUDA Installaion
Guide](https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html#precompiled-streams-support-matrix)
for additional details.  For example, to set the version to the 520 stream:

```
wwctl node set --tagadd "ovl_gpu_cuda_version=520" NODENAME
```

Defaults to: `latest`

### `ovl_gpu_driver_dkms_disable`

Disables use of the dkms version of the driver. Before disabling consider:

* The precompiled drivers pull in dependencies that may conflict with MOFED or other installed packages.
* The kmod drivers use weak-modules support that may not work with custom kernels.

```
wwctl node set --tagadd "ovl_gpu_driver_dkms_disable=true" NODENAME
```

Defaults to `false`

### `ovl_gpu_pci_disable_acs`

Disables PCIe ACS support. See [PCI Access Control Services](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/troubleshooting.html#pci-access-control-services-acs) in the nVidia docs.

```
wwctl node set --tagadd "ovl_gpu_pci_disable_acs=true" NODENAME
```

Defaults to: `false`

## Repository

The overlay will check the current `dnf`/`yum` config for the nVidia repo and use that
if found. If no repo is present it will set up the upstream nVidia repo. This
allows a local mirror to be pre-configured in the `dnf`/`yum` config if desired.

## The GPU Card Database

The overlay file `./rootfs/warewulf/etc/warewulf-overlay-gpu-carddb` contains
the PCI IDs of the cards we recognize and will need to be updated to add new
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

