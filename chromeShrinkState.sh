#!/bin/bash
#
# author: Aleksander Bizjak (nethawk)
# description:
# This script is created to help with the resizing of the ChromeOS STATE patition
# and preparing the KERNEL and ROOTFS C partition for dual booting with another OS.
#
# licence: The MIT License (MIT)
#
# Copyright (c) [2016] [Aleksander Bizjak]
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Information on the filesystem has been taken from:
# https://www.chromium.org/chromium-os/chromiumos-design-docs/disk-format#TOC-GUID-Partition-Table-GPT-
#
# The partition table set out kernel-c and rootfs-c as unused by google, this might change in the future though (March 4 2016)
# Partition	Usage					Purpose
# 1		user state, aka "stateful partition"	User's browsing history, downloads, cache, etc. Encrypted per-user.
# 2		kernel A				Initially installed kernel.
# 3		rootfs A				Initially installed rootfs.
# 4		kernel B				Alternate kernel, for use by automatic upgrades.
# 5		rootfs B				Alternate rootfs, for use by automatic upgrades.
# 6		kernel C				Minimal-size partition for future third kernel. There are rare cases where a third partition could help us avoid recovery mode (AU in progress + random corruption on boot partition + system crash). We decided it's not worth the space in V1, but that may change.
# 7		rootfs C				Minimal-size partition for future third rootfs. Same reasons as above.
# 8		OEM customization			Web pages, links, themes, etc. from OEM.
# 9		reserved				Minimal-size partition, for unknown future use.
# 10		reserved				Minimal-size partition, for unknown future use.
# 11		reserved				Minimal-size partition, for unknown future use.
# 12		EFI System Partition			Contains 64-bit grub2 bootloader for EFI BIOSes, and second-stage syslinux bootloader for legacy BIOSes.
#
#
# set strict mode
set -e

show_usage()
{
echo -e "usage: $0 options
Options:
  -d        Do a dry run. This will not actually change the partition
            table, but do all the steps to there and then print the commands
            it would have run.
  -b 128    Size of space to reserve for the kernel in MB (default 128MB)
  -h        Shows this message

For use in scirpts:
  -r XXXX   Size of the root filesystem to be created in MB
            this will skip the sizing question (for use in scripts)
  -Y        Don't ask for confirmation before resizing (for use in scripts)

Examples:
bash $0 -b 256 -d
bash $0
"
}

# description: Converts the size read from cgpt on ChromeOS to Mega or GigaBytes.
# The "B" option is used to get the grpt size value from user input (MegaBytes->Bytes)
# usage: getSize "M" 1234
# returns: The converted size
getSize()
{
  local var
  if [[ "$1" == "M" ]]; then
    echo $(($2/1024/2))
  fi
  if [[ "$1" == "G" ]]; then
    echo $(($2/1024/1024/2))
  fi
  if [[ "$1" == "B" ]]; then
    # in the case we are converting from Megabytes to Bytes
    echo $(($2*1024*2))
  fi
}

echo_reboot()
{
    echo -e "A Reboot is neccessary at this point.

WARNING: The Reboot WILL destroy all your data on ChromeOS. You have been warned.
"
    echo -e "You NEED to BOOT to ChromeOS in order for it
to REBUILD it's STATE partition. The rebuilding of the state
partition causes it to DESTROY ALL DATA on it. You have been warned!"
  # Wait for user confirmation or skip and exit
  if [[ -z $DRY_RUN ]]; then
    while true; do
      read -p "Confirm that you have read the above and are ready to reboot. Yes/No: " reboot_confirm
      echo ""
      if [[ "$reboot_confirm" == "Yes" ]]; then
        echo "Going for a reboot now"
	echo ""
	echo "$0 is done. Have a good day"
        reboot
        exit 0
      fi
      if [[ "$reboot_confirm" == "No" ]]; then
        echo "WARNING: Reboot aborted by user"
        echo -e "
Please be aware that you will NEED to reboot to ChromeOS to be usefull.
Currently it has no usable STATE partition and as such will be of limited use, until 
the device has rebooted into ChromeOS at which point it will rebuild the drive,
which will cause you to loose all data stored on the local machine."
        echo ""
	echo "$0 is done. Have a good day"
        exit 0
      else
        echo "ERROR: Invalid answer!"
        echo "Please type \"Yes\" or \"No\""
        continue
      fi
    done
  else
    echo ""
    echo "$0 is done. Have a good day"
    exit 0
  fi
}

# Make sure only root can run our script
if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

# Set the defaults
# get the root device
dev_root=$(rootdev -d -s)
# these are the default partition numbers
state_part=1
kern_part=6
root_part=7
# default size for kernel
kern_user=128

while getopts "hdyr:b:" opt; do
  case $opt in
    d)
      echo "INFO: Doing a dry run"
      DRY_RUN="True"
      ;;
    r)
      if printf '%f' "$OPTARG" &>/dev/null; then
        root_user=$OPTARG
      else
        echo "ERROR: Root filesystem size is not a number"
        exit 1
      fi
      ;;
    b)
      kern_user=$OPTARG
      ;;
    h)
      show_usage
      exit 0
      ;;
    \?)
      show_usage
      exit 1
      ;;
  esac
done

echo -e "Welcome to $0. This script will help you re-partition
the ChromeOS State drive and make space for dual booting with
another linux partition."
echo ""
echo "INFO: Collecting information:"
state_size=$(cgpt show -i $state_part -n -s -q ${dev_root})
state_start=$(cgpt show -i $state_part -n -b -q ${dev_root})
kern_size=$(cgpt show -i $kern_part -n -s -q ${dev_root})
root_size=$(cgpt show -i $root_part -n -s -q ${dev_root})

echo -e "partition \t size \t\t size (MB) \t size (GB)
STATE \t\t $state_size \t $(getSize "M" $state_size) \t\t $(getSize "G" $state_size)
KERN-C \t\t $kern_size \t\t $(getSize "M" $kern_size) \t\t $(getSize "G" $kern_size)
ROOT-C \t\t $root_size \t\t $(getSize "M" $root_size) \t\t $(getSize "G" $root_size)
"

# Make sure the kernel-c and root-c have not been touched yet
if [[ "$kern_size" -ne "1" ]]; then
  echo "ERROR: Kernel size is not 1!"
  echo "This means that someone has already created this filesystem."
  echo "Cowardly refusing to continue..."
  exit 1
fi
if [[ "$root_size" -ne "1" ]]; then
  echo "ERROR: Rootfs size is not 1!"
  echo "This means that someone has already created this filesystem."
  echo "Cowardly refusing to continue..."
  exit 1
fi

# Ask the user how much disk space to leave for root filesystem
root_max=$(($(getSize "M" $state_size)-1024-kernel_user))
echo -e "The maximum size is smaller then the STATE partition, this is to allow
ChromeOS some space. The space reserved is calculated
as 1024MB + the size of the kernel partition (usually 128MB).
The maximum size for the root filesystem is: $root_max MB
The recommended size for the root filesystem is: $(($root_max-4096)) MB.
Please enter a value the is a multiple of 2. The formula to convert from
GB to MB is : 4 GB = 4*1024 = 4096 MB"

if [[ -z $root_user ]]; then
while true; do
  read -p "Size of rootfs (in MB):" root_user

  # Test is the user input is a number, exit otherwise
  if ! printf '%f' "$root_user" &>/dev/null; then
    echo "Not a number!"
    continue
  fi

  # Test if the user input is smaller then the maximum size
  if [[ $root_user < $root_max ]]; then
    break
  else
    echo "The size entered: $root_user is larger the the maximum size: $root_max"
    continue
  fi
done
else
  echo "Root size set on command line: $root_user MB"
  # Test if the user input is larger then the maximum size
  if [[ $root_user -gt $root_max ]]; then
    echo "ERROR: The size entered: $root_user is larger the the maximum size: $root_max"
    echo "Aborting..."
    exit 1
  fi
fi

# We've got the information, do the calculation
echo "Crunching numbers...."

# Get root and kern_user sizes in sectors
root_user_size=$(getSize "B" $root_user)
kern_user_size=$(getSize "B" $kern_user)

# Subtract kern and root_user_sector from STATE to get the new size
echo "state: $state_size kernel: $kern_user_size root: $root_user_size state_start: $state_start"
state_size=$(($state_size - $root_user_size - $kern_user_size))
echo "NEW state: $state_size"
# get the kernel and root start sectors
kern_start=$(($state_start + $state_size))
root_start=$(($kern_start + $kern_user_size))

echo -e "The desired partition layout
partition \t start \t\t size \t\t size (MB) \t size (GB)
STATE \t\t $state_start \t $state_size \t $(getSize "M" $state_size) \t\t $(getSize "G" $state_size)
KERN-C \t\t $kern_start \t $kern_user_size \t $(getSize "M" $kern_user_size) \t\t $(getSize "G" $kern_user_size)
ROOT-C \t\t $root_start \t $root_user_size \t $(getSize "M" $root_user_size) \t\t $(getSize "G" $root_user_size)
"

echo -e "The commands that will be run in order:
umount -f /mnt/stateful_partition
cgpt add -i $state_part -b $state_start -s $state_size -l STATE ${dev_root}
cgpt add -i $kern_part -b $kern_start -s $kern_user_size -l KERN-C -t "kernel" ${dev_root}
cgpt add -i $root_part -b $root_start -s $root_user_size -l ROOT-C ${dev_root}
"

if ! [[ -z $DRY_RUN ]]; then
  echo "INFO: Dry run selected. The configuration will NOT be applied."
  echo_reboot
else
  # Now that we have all require information it's time to resize the partitions
  echo -e "The Configuration is ready to be applied, please review the values and above.
Applying the configuration means changing the partition table, this process should not be
interrupted under any circumstances, so DO NOT remove your power plug, play with ChromeOS
settings, or do anything else. Leave this to finish, it doesn't take long.
Once you are certain that you want to proceed enter: Proceed"
  while true; do
    read -p "command: " proceed
    if [[ "$proceed" == "Proceed" ]]; then
      echo ""
      break
    else
      echo "ERROR: Invalid option: $proceed"
      echo "Please enter \"Proceed\" once you are ready to apply the configuration."
      continue
    fi
  done
  echo "Unmounting the state partition..."
  echo "Beginning resize of partitions: "
  echo "Partition: $state_part name: STATE start: $state_start size: $state_size"
  cgpt add -i $state_part -b $state_start -s $state_size -l STATE ${dev_root}
  echo "Partition: $kern_part name: KERN-C start: $kern_start size: $kern_user_size"
  cgpt add -i $kern_part -b $kern_start -s $kern_user_size -l KERN-C -t "kernel" ${dev_root}
  echo "Partition: $root_part name: ROOT-C start: $root_start size: $root_user_size"
  cgpt add -i $root_part -b $root_start -s $root_user_size -l ROOT-C ${dev_root}
  echo "Partition resize complete"
  echo ""
  echo_reboot
fi
