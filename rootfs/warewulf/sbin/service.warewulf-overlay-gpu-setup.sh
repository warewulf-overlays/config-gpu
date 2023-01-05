#!/bin/bash

# Source our common warewulf functions
[[ -f /warewulf/etc/functions ]] && source /warewulf/etc/functions || exit 1

# Script starts here.
# Table with all our known/supported GPU cards.
CARDDB_FILE=/warewulf/etc/warewulf-overlay-gpu-carddb
[[ -f ${CARDDB_FILE} ]] && source ${CARDDB_FILE} || die "$0: ${CARDDB_FILE} not found."

# Make sure we have yq installed.
YQ=$(which yq 2> /dev/null) || die "$0: Please install yq: https://github.com/mikefarah/yq"

# Cuda Driver location. Use a default for now, maybe expand to selectively
# install a specific version per node/category/... later.
CUDA_DRIVER_PATH=/warewulf/shared/drivers/cuda/

# Check node config for specific drvier version override. This will be in a tag in the node config
# called nvidia-driver-version. E.g.:
#   wwctl node set --tag nvidia-driver-version=495.29.05 nodename
# 
# Seed the version with a tag from the node config.
CUDA_VERSION=$(yq ".nodes.${ME}.tags.nvidia-driver-version" < /warewulf/etc/nodes.conf)
CUDA_DRIVER=${CUDA_DRIVER_PATH}/NVIDIA-Linux-$(arch)-${CUDA_VERSION}.run

if [[ -z ${CUDA_VERSION} ]] || [[ ${CUDA_VERSION} == "null" ]] || [[ ! -f ${CUDA_DRIVER_PATH} ]]; then
    warn "$0: Node config driver version invalid or missing, falling back to latest found driver."
    CUDA_VERSION=$(ls -1 ${CUDA_DRIVER_PATH} | grep "NVIDIA-Linux-$(arch)-.*run" | sort -V | tail -1 | sed -e "s/NVIDIA-Linux-$(arch)-\(.*\).run/\1/g")
    CUDA_DRIVER=${CUDA_DRIVER_PATH}/NVIDIA-Linux-$(arch)-${CUDA_VERSION}.run
fi

# Locate the driver and associated fabric manager if applicable. 
# nvidia-fabric-manager-495.29.05-1.x86_64.rpm
CUDA_FABRIC_MANAGER=${CUDA_DRIVER_PATH}/nvidia-fabric-manager-${CUDA_VERSION}-1.x86_64.rpm
   
# Optionally configure ourselves to support VirtualGL. Needs turbovnc and virtualGL packages.
CUDA_VIRTUALGL=false

function cuda_create_users () {
    # We don't really care about uid/gid, let the chips fall where they may. 
    useradd -c "nVidia Driver User" -r -m -d /tmp/cuda -s /bin/nologin cuda
}

# Check if a pci id is a card we recognize.
function cuda_is_gpu () {
  local retval=1
  if [[ -n $1 ]]; then
    for card in ${!CUDA_CARDDB[@]}; do
      if [[ $1 == $card ]]; then
        retval=0
        break
      fi
    done
  fi
  return $retval
}

# Count how many cards we have.
function cuda_count_gpu_devices() {
  # Count the number of cards we have.
  local count=0
  local retval
  local pci_devices=( $(lspci -n | awk '{print $3}') )

  for device in ${pci_devices[@]}; do 
    cuda_is_gpu $device && let count+=1
  done

  if [[ $count -gt 0 ]]; then
    retval=0
  else 
    retval=1
  fi
  echo $count
  return $retval
}

# Check if nouveau is disabled.
function cuda_check_nouveau () {
  local retval
  if [[ $(</proc/cmdline) =~ nouveau.blacklist=yes ]] && [[ $(</proc/cmdline) =~ nomodeset ]]; then
    warn "nomodeset and nouveau.blacklist=yes detected on kernel command line."
    retval=0
  else
    warn "nomodeset and/or nouveau.blacklist=yes not detected on kernel command line."
    retval=1
  fi
  return $retval
}

function cuda_install_driver_runfile () {
  local retval=0
  # Unpack and install driver.
  if ! bash ${CUDA_DRIVER} --accept-license --silent --no-questions --no-x-check; then
    warn "$0: First attempt failed, attempting to reinstall kernel-devel and retrying."
    dnf -y reinstall kernel-devel
    if ! bash ${CUDA_DRIVER} --accept-license --silent --no-questions --no-x-check; then
      warn "$0: Driver install exited with errors." && retval=1
    fi
  fi
  return $retval
}


function cuda_install_driver_dnf () {
  local retval=0
  ARCH=$( /bin/arch )
  # TODO: should detect this
  distribution=rhel8
  dnf config-manager --add-repo http://developer.download.nvidia.com/compute/cuda/repos/$distribution/${ARCH}/cuda-$distribution.repo
  dnf module install nvidia-driver:latest/fm
  return ${retval}
}

function cuda_makedev () {
  local retval=0
  if [[ $1 -lt 1 || $1 -gt 16 ]]; then
    warn "Invalid device count: $1"
    retval=1
  else
    for device in $( seq 0 $(( $1 - 1 )) ); do
        if [[ ! -f /dev/nvidia${device} ]]; then
          mknod /dev/nvidia${device} c 195 $device || retval=1
        fi
      done
    if [[ ! -f /dev/nvidia-uvm ]]; then
      mknod /dev/nvidia-uvm c 245 0 || retval=1
    fi

    if [[ ! /dev/nvidiactl ]]; then
      mknod /dev/nvidiactl 195 255 || retval=1
    fi

    chmod 0666 /dev/nvidia* || retval=1
  fi
  return $retval
}

function cuda_modprobe () {
  # Load 'em up.
  local retval=1 
  modprobe nvidia || retval=1
  modprobe nvidia-uvm || retval=1
  nvidia-modprobe -u -c=0 || retval=1
  return $retval
}

function cuda_persistence_daemon () {
  # Create systemd service file.
  if [[ ! -d /etc/systemd/system ]]; then 
    warn "systemd doesn't seem to be here."
  else
    case $(arch) in 
        x86_64) PERSIST_USER='--user cuda' ;;
        ppc64le) PERSIST_USER='--user root' ;;
        *) PERSIST_USER=''
    esac
    cat > /etc/systemd/system/nvidia-persistenced.service <<- EOF
	# NVIDIA Persistence Daemon Init Script
	#
	# Copyright (c) 2013 NVIDIA Corporation
	#
	# Permission is hereby granted, free of charge, to any person obtaining a
	# copy of this software and associated documentation files (the "Software"),
	# to deal in the Software without restriction, including without limitation
	# the rights to use, copy, modify, merge, publish, distribute, sublicense,
	# and/or sell copies of the Software, and to permit persons to whom the
	# Software is furnished to do so, subject to the following conditions:
	#
	# The above copyright notice and this permission notice shall be included in
	# all copies or substantial portions of the Software.
	#
	# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
	# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
	# DEALINGS IN THE SOFTWARE.
	#
	# This is a sample systemd service file, designed to show how the NVIDIA
	# Persistence Daemon can be started.
	#
	
	[Unit]
	Description=NVIDIA Persistence Daemon
	Wants=syslog.target
	
	[Service]
	Type=forking
	ExecStart=/usr/bin/nvidia-persistenced ${PERSIST_USER}
	ExecStopPost=/bin/rm -rf /var/run/nvidia-persistenced
	
	[Install]
	WantedBy=multi-user.target
	EOF

    systemctl daemon-reload
    systemctl enable nvidia-persistenced
    systemctl start nvidia-persistenced
  fi
}

function cuda_nvidia_xconfig_workstation () {
  # Configure node for optionally starting X
#  cat > /etc/X11/xorg.conf.d/00-nvidia.conf <<- EOF
#	# Allow headless GPU with X. 
#	Section "ServerLayout"
#	        Identifier "layout"
#	        Option "AllowNVIDIAGPUScreens"
#	EndSection
#	EOF

  # Find busid for our device.
  cuda_busid=$(nvidia-xconfig --query-gpu-info | awk '/PCI BusID :/ {print $4}')

  # Generate an X configuration.
  # nvidia-xconfig -a \
  #                --allow-empty-initial-configuration \
  #                --use-display-device=None \
  #                --virtual=1920x1080 \
  #                --busid ${cuda_busid}
  
  nvidia-xconfig || return 1
  return 0

}

function cuda_nvidia_xconfig_virtualgl () {
  local cuda_num_gpus cuda_busid
  cuda_num_gpus=$(nvidia-xconfig --query-gpu-info | awk '/Number of GPUs:/ {print $4}')
  if [[ ${cuda_num_gpus} -gt 1 ]]; then
    warn "Go figure out how to set up multiple GPUs."
    return 1
  fi

  # Find busid for our device.
  cuda_busid=$(nvidia-xconfig --query-gpu-info | awk '/PCI BusID :/ {print $4}')

  # Generate X config.
  nvidia-xconfig -a \
                 --allow-empty-initial-configuration \
                 --use-display-device=None \
                 --virtual=1920x1200 \
                 --busid ${cuda_busid}

  # Configure system for virtualGL
  /opt/VirtualGL/bin/vglserver_config -config +s +f -t 

  # Start display manager
  systemctl start lightdm
  systemctl status lightdm
}

# Install/enable fabric manager.
function cuda_nvidia_fabric_manager () {
  # Enable and start fabric manager.
  local retval=0
  if [[ ! -f ${CUDA_FABRIC_MANAGER} ]]; then
    warn "$0: ${CUDA_FABRIC_MANAGER} not found, skipping install of fabric manager."
    retval=1
  else
    if dnf -y localinstall ${CUDA_FABRIC_MANAGER}; then
      systemctl enable nvidia-fabricmanager
      systemctl start nvidia-fabricmanager
    else
      warn "Failed to install nvidia fabric-manager."
      retval=1
    fi
  fi
  return ${retval}
}

# Work starts here.
state_file=/warewulf/var/state/nvidia-gpu.state
dev_count=$(cuda_count_gpu_devices)

if [[ ${dev_count} -gt 0 ]]; then
  warn "Detected $dev_count devices."

  if [[ -f ${state_file} ]]; then
    warn "Previous install of cuda found, not overwriting."
  else
    # Driver install.
    cuda_install_driver_runfile 

    if ! cuda_makedev ${dev_count}; then
      warn "Error creating /dev/entries."
    fi

    cuda_modprobe

    if $CUDA_VIRTUALGL; then
      cuda_nvidia_xconfig_virtualgl
    else
      # Configure for normal X using first GPU.
      cuda_nvidia_xconfig_workstation
    fi

    # nvidia-smi --persistence-mode=${CUDA_PERSITENT_MODE}
    warn "Enabling CUDA persistence daemon."
    cuda_create_users
    cuda_persistence_daemon

    # This rpm should not be installed, but just in case.
    systemctl disable dcgm
    systemctl stop dcgm

    touch ${state_file}
  fi
else
  warn "$0: No card detected, is ${ME} A CPU node or perhaps CUDA_CARDDB needs to be updated?"
fi


