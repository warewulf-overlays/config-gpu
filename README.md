# warewulf-overlay-gpu
Overlay for Warewulf to set up GPU on node boot.


# VMware passthru hints

Using VMWare based nodes with a GPU passthru to a GeForce device.

Host Settings:

* Set host GPU mode to Shared Direct in Graphics tab when·setting up pass-thru.

Guest settings:

* Boot Options | Firmware = EFI
* svga.present = FALSE  (note this disables the console)
* hypervisor.cpuid.v0 = FALSE
* pciPassthru.64bitMMIOSizeGB = 64
* pciPassthru.use64bitMMIO = TRUE


# Collecting new card info for the card database

```
    clush -w GPUNODELIST lspci -nn | grep -i nvidia | awk '!($1=$2="")'  | sort | uniq -c | sort
    clush -w GPUNODELIST "nvidia-smi -q | grep 'Product Name'" | awk '!($1=$2="")' | sort | uniq -c | sort
```


