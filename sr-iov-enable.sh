#!/bin/bash
#
# Author: dotslash.lu <dotslash.lu@gmail.com>
#
# NOTE
# 1. when creating vf, the NIC driver need to be restarted
# the network may be LOST temporarily
#
# 2. if intel_iommu is not enabled in bootup parameters,
# this script will add it automatically and REBOOT

pf=$1


function print_usage
{
    echo "Usage:"
    echo "$0 <physical function>"
}

function check_iommu
{
    echo checking iommu in grub
    if ! egrep -q "^[[:space:]]*kernel.+intel_iommu" /boot/grub/grub.conf; then
        echo iommu not enabled, enabling and reboot
        sed -i '/\s*kernel/s/$/ intel_iommu=on/' /boot/grub/grub.conf
        reboot
    else
        echo OK
    fi
}

function check_mod
{
    echo checking igb mod
    ret=$(lsmod | grep -c '^igb')
    if [ $ret -eq 0 ]; then
        echo No mod igb found
        exit 1
    else
        echo OK
    fi
}

function create_vf
{
    echo creating vf
    modprobe -r igb
    modprobe igb max_vfs=7
    if !grep -q "max_vfs"; then
        echo "options igb max_vfs=7" >>/etc/modprobe.d/igb.conf
    fi
    count=$(lspci | grep "Virtual Function")
    if [ $count -eq 0 ]; then
        echo No vf found
        exit
    fi
}

##
## after libvirt 0.10.0, directly use PCI address is not preferable,
## use the function below instead
##
# function add_dev
# {
#     dev_addrs=($(lspci | grep "Virtual Function" | awk '{print $1}' | sed 's/[:\.]/_/g'))
#     for addr in "${dev_addrs[@]}"; do
#         xml=$(virsh nodedev-dumpxml pci_0000_$addr)
#         domain=$(grep -oPm1 "(?<=<domain>)[^<]+" <<< "$xml")
#         bus=$(grep -oPm1 "(?<=<bus>)[^<]+" <<< "$xml")
#         slot=$(grep -oPm1 "(?<=<slot>)[^<]+" <<< "$xml")
#         func=$(grep -oPm1 "(?<=<function>)[^<]+" <<< "$xml")
#         tmp_file=/tmp/if-${addr}.xml
#         echo -e "\
# <interface type='hostdev' managed='yes'>\n\
#   <source>\n\
#     <address type='pci' domain='0' bus='$bus' slot='$slot' function='$func'/>\n\
#   </source>\n\
# </interface>" > $tmp_file
#
#     done
# }

function add_dev
{
    echo define passthrough network in libvirt
    cat > /tmp/passthrough-${pf}.xml <<EOF
<network>
  <name>passthrough-$pf</name>
  <forward mode='hostdev' managed='yes'>
    <pf dev='$pf'/>
  </forward>
</network>
EOF
    virsh net-define /tmp/passthrough-${pf}.xml
    virsh net-autostart passthrough-$pf
    virsh net-start passthrough-$pf
}


if [ -z $pf ]; then
    print_usage
    exit 1
fi

check_iommu
check_mod
create_vf
add_dev

# sr-iov added, use it by
# virsh attach-interface --config --source passthrough-<iface> --type network --domain <domain name>
