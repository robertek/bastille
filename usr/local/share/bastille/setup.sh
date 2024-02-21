#!/bin/sh
#
# Copyright (c) 2018-2023, Christer Edwards <christer.edwards@gmail.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
#
# * Neither the name of the copyright holder nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

. /usr/local/share/bastille/common.sh
. /usr/local/etc/bastille/bastille.conf

usage() {
    error_exit "Usage: bastille setup [pf|bastille0|zfs|vnet]"
}

# Check for too many args
if [ $# -gt 1 ]; then
    usage
fi

# Configure bastille0 network interface
configure_bastille0() {
    info "Configuring bastille0 loopback interface"
    sysrc cloned_interfaces+=lo1
    sysrc ifconfig_lo1_name="bastille0"

    info "Bringing up new interface: bastille0"
    service netif cloneup
}

configure_vnet() {
    info "Configuring bridge interface"
    sysrc cloned_interfaces+=bridge1
    sysrc ifconfig_bridge1_name=bastille1

    info "Bringing up new interface: bastille1"
    service netif cloneup

    if [ ! -f /etc/devfs.rules ]; then
        info "Creating bastille_vnet devfs.rules"
        cat << EOF > /etc/devfs.rules
[bastille_vnet=13]
add include \$devfsrules_hide_all
add include \$devfsrules_unhide_basic
add include \$devfsrules_unhide_login
add include \$devfsrules_jail
add include \$devfsrules_jail_vnet
add path 'bpf*' unhide
EOF
    fi
}

# Configure pf firewall
configure_pf() {
if [ ! -f "${bastille_pf_conf}" ]; then
    local ext_if
    ext_if=$(netstat -rn | awk '/default/ {print $4}' | head -n1)
    info "Determined default network interface: ($ext_if)"
    info "${bastille_pf_conf} does not exist: creating..." 
    
    ## creating pf.conf
    cat << EOF > ${bastille_pf_conf}
## generated by bastille setup
ext_if="$ext_if"

set block-policy return
scrub in on \$ext_if all fragment reassemble
set skip on lo

table <jails> persist
nat on \$ext_if from <jails> to any -> (\$ext_if:0)
rdr-anchor "rdr/*"

block in all
pass out quick keep state
antispoof for \$ext_if inet
pass in inet proto tcp from any to any port ssh flags S/SA keep state
EOF
    sysrc pf_enable=YES
else
    error_exit "${bastille_pf_conf} already exists. Exiting."
fi
}

# Configure ZFS
configure_zfs() {
    if [ ! "$(kldstat -m zfs)" ]; then
        info "ZFS module not loaded; skipping..."
    else
        ## attempt to determine bastille_zroot from `zpool list`
        bastille_zroot=$(zpool list | grep -v NAME | awk '{print $1}')
        sysrc -f "${bastille_prefix}/bastille.conf" bastille_zfs_enable=YES
        sysrc -f "${bastille_prefix}/bastille.conf" bastille_zfs_zpool="${bastille_zroot}"
    fi
}

# Run all base functions (w/o vnet) if no args
if [ $# -eq 0 ]; then
    sysrc bastille_enable=YES
    configure_bastille0
    configure_pf
    configure_zfs
fi

# Handle special-case commands first.
case "$1" in
help|-h|--help)
    usage
    ;;
pf|firewall)
    configure_pf
    ;;
bastille0|loopback)
    configure_bastille0
    ;;
zfs|storage)
    configure_zfs
    ;;
bastille1|vnet|bridge)
    configure_vnet
    ;;
esac