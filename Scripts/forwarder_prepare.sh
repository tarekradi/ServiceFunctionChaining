#!/bin/bash

# Copyright (c) 2015-2016, Intel Corporation
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#    * Redistributions of source code must retain the above copyright notice,
#      this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above copyright
#      notice, this list of conditions and the following disclaimer in the
#      documentation and/or other materials provided with the distribution.
#    * Neither the name of Intel Corporation nor the names of its contributors
#      may be used to endorse or promote products derived from this software
#      without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#set -x

#SCRIPT - Get and install OVS, DPDK and set up OVS bridges/ports


source gilan_config

export demo_dir="${PWD}"
export RTE_SDK="${demo_dir}"/dpdk-2.1.0
export RTE_TARGET=x86_64-native-linuxapp-gcc
export DPDK_BUILD="${RTE_SDK}/${RTE_TARGET}"



function get_files()
{
    #FUNCTION - Grab required files for installation and apply patch
    #Ingredient checklist:
    #1) dpdk
    #2) openvswitch
    #3) patch for ovs

    #get dpdk, unpack
    cd "${demo_dir}" || exit $?
    echo "Downloading dpdk..."
    wget "${dpdk_url}"
    tar xvf dpdk-2.1.0.tar.gz

    #get openvswitch via git and reset to specific commit id for patch
    cd "${demo_dir}" || exit $?
    echo "Cloning into ovs git..."
    git clone "${ovs_git_url}"
    cd ovs || exit $?
    git branch "${ovs_git_branch}"
    git checkout "${ovs_git_branch}"
    git reset --hard "${ovs_git_id}"


    #Apply patches because release versions of OVS/DPDK/ODL are not yet compatible with SFC
    #Get ovs-patch files from 01.org. Exact url TBD -OR- are we distributing the patches as part of a tarball that includes this script?

    #---Placeholder code---
    #wget $ovs_patch_url
    #tar xvzf ovs_patch.tar.gz $demo_dir/patch/ovs

    echo "Applying OVS patches..."
    cd "${demo_dir}"/ovs || exit $?

    for patch_file in "${demo_dir}"/patch/ovs/*
    do
        if ! patch -p1 < "${patch_file}"
        then
            echo "Error: Problem applying OVS Patches"
            exit 1
        fi
    done

    #get sfc specific scripts/vm images from 01.org? TBD

}

function install_files()
{
    #FUNCTION - After applying patches, build the required libraries
    echo "entering install_files"

    #Define DPDK build directory
    export RTE_SDK="${demo_dir}"/dpdk-2.1.0
    export RTE_TARGET=x86_64-native-linuxapp-gcc
    export DPDK_BUILD="${RTE_SDK}/${RTE_TARGET}"

    #Change config file to allow for combined libraries and vhost; then run make install
    cd "${RTE_SDK}" || exit $?
    sed -i 's/CONFIG_RTE_BUILD_COMBINE_LIBS=n/CONFIG_RTE_BUILD_COMBINE_LIBS=y/g' config/common_linuxapp
    sed -i 's/CONFIG_RTE_LIBRTE_VHOST=n/CONFIG_RTE_LIBRTE_VHOST=y/g' config/common_linuxapp
    sed -i 's/CONFIG_RTE_PKTMBUF_HEADROOM=128/CONFIG_RTE_PKTMBUF_HEADROOM=256/g' config/common_linuxapp
   
    echo "Building DPDK ..."
    make install T="${RTE_TARGET}"

    if [[ $? != 0 ]]
    then
        echo "Problem installing DPDK"
        exit 1
    fi

    echo "Exit building DPDK ..."
    #Build Openvswitch and configure to run with dpdk
    cd "${demo_dir}"/ovs || exit $?
    echo "Building DPDK-OVS ..."
    echo "Running  boot.sh ..."
    ./boot.sh
    echo "Running  configure ..."
    ./configure --with-dpdk="${DPDK_BUILD}" CFLAGS="-g -O2 -Wno-cast-align"
    echo "Running  make ..."
    if ! make install
    then
        echo "Error installing Openvswitch"
        exit 1
    fi
    echo "exit  make ..."
}

set -x

function setup_dpdk()
{
    #FUNCTION - Set up DPDK environment:
    #-Bind DPDK to NIC
    #-Create hugepages

    echo "enter  setup dpdk ..."

    # Load igb_uio driver and bind DPDK to NIC ($net3 in onps_config).
    modprobe uio
    insmod "${DPDK_BUILD}"/kmod/igb_uio.ko
    "${RTE_SDK}"/tools/dpdk_nic_bind.py --bind=igb_uio "em3"

    # echo 0 | tee /proc/sys/kernel/randomize_va_space

    rm -f /dev/vhost-net

    echo "setting hugepages  ..."
    #Set hugepages: 8192 for classifer, 16384 for SFF
    if [[ "${SFC_NODE}" == "CLS" ]]
    then
        huge_page_size=8192
    else
        huge_page_size=16384
    fi

    #HUGEPAGES=$(grep hugepage /proc/cmdline)
    #if [[ "${HUGEPAGES}" == "" ]]
    #then
    #    echo "$huge_page_size" | tee /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages
    #else
    #    exit 0
    #fi

    echo "mount hugepages  ..."
    HUGEMOUNT=$(mount | grep hugetlbfs | awk '{ print $3 }' | head -1)
    export HUGEMOUNT
    #while [[ "${HUGEMOUNT}" != "" ]]
    #do
    #    umount "${HUGEMOUNT}"
    #    sleep 5
    #    HUGEMOUNT=$(mount | grep hugetlbfs | awk ' { print $3 } ' | head -1)
    #done
    mount -t hugetlbfs nodev /dev/hugepages
    echo "exit  setup dpdk ..."

}

function setup_first_ovs()
{
    #FUNCTION - OVS First time set-up.
    #Create database and schema

    echo "enter  first setup ovs ..."
    mkdir -p /usr/local/etc/openvswitch
    mkdir -p /usr/local/var/run/openvswitch

    # ignore failure if file doesn't exist
    rm /usr/local/etc/openvswitch/conf.db 2>/dev/null || true

    ovsdb-tool create /usr/local/etc/openvswitch/conf.db  \
    /usr/local/share/openvswitch/vswitch.ovsschema
    echo "exit  first setup ovs ..."


}

set -x

function start_ovsdb()
{
    #Start Openvswitch database (ovsdb)

    echo "enter  start ovsdb ..."
    if [[ -d "${demo_dir}"/openvswitch ]] ;then
        export OVS_DIR="${demo_dir}"/openvswitch
        echo "Set OVS_DIR as /opt/demo/openvswitch"
    fi

    if ! OVSDBSRV=$(which ovsdb-server)
    then
        echo "ovsdb-server is not found, use source directory"
        OVSDBSRV="${OVS_DIR}"/ovsdb/ovsdb-server
    fi

    if ! VSCTL=$(which ovs-vsctl)
    then
        echo "ovs-vsctl is not found, use source directory"
        VSCTL="${OVS_DIR}"/utilities/ovs-vsctl
    fi

    export DB_SOCK=/usr/local/var/run/openvswitch/db.sock

    echo "Starting ovsdb-server..."
    screen -dmS ovsdb "${OVSDBSRV}" --remote=punix:"${DB_SOCK}" \
        --remote=db:Open_vSwitch,Open_vSwitch,manager_options \
        --pidfile
    sleep 5
    "${VSCTL}" --no-wait init
    echo "exit  start ovsdb ..."


}

function start_vswitchd()
{
    if [[ -d "${demo_dir}"/openvswitch ]] ;then
        export OVS_DIR="${demo_dir}"/openvswitch
        echo "Set OVS_DIR as /opt/demo/openvswitch"
    fi

    if ! VSWITCHD=$(which ovs-vswitchd)
    then
        echo "ovs-vswitchd is not found, use source directory"
        VSWITCHD="${OVS_DIR}"/vswitchd/ovs-vswitchd
    fi

    if [[ -r /usr/local/var/run/openvswitch/db.sock ]] ;then
        export DB_SOCK=/usr/local/var/run/openvswitch/db.sock
    else
        echo "OVSDB may have error, please check it manually, exit."
        exit 1
    fi

    echo "Starting vswitchd..."
    screen -dmS vswitchd "${VSWITCHD}" --dpdk -c 0xf -n 4 --socket-mem 2048,2048 \
            -- unix:"${DB_SOCK}" --pidfile --log-file="${demo_dir}"/logs/ovs-vswitchd.log
    echo "Started vswitchd..."


}

function start_pkt_fwding()
{

    echo "exter start pkt fwd ..."
    if ! VSCTL=$(which ovs-vsctl)
    then
        echo "ovs-vsctl is not found, use source directory"
        VSCTL="${OVS_DIR}"/utilities/ovs-vsctl
    fi

    if ! OFCTL=$(which ovs-ofctl)
    then
        echo "ovs-ofctl is not found, use source directory"
        OFCTL="${OVS_DIR}"/utilities/ovs-ofctl
    fi
    export OFCTL

    echo "Creating OvS bridge and adding ports into it..."

    #Add DPDK bridge/port to ovs and set IP address

    "${VSCTL}" add-br "${DPDK_BR}" -- set bridge "${DPDK_BR}" datapath_type=netdev
    "${VSCTL}" add-port "${DPDK_BR}" dpdk0 -- set Interface dpdk0 type=dpdk

    DPDK_IP="172.16.20.5"

    ip link set "${DPDK_BR}" up
    ip addr add "${DPDK_IP}"/24 dev "${DPDK_BR}"
    #setting MTU with `ip link set` doesn't actually do anything

    #Add vxlan bridge and port
    #Destination Port 4790 is specifically designated for NSH
    #Set local IP so traffic can go through dpdk bridge

    #"${VSCTL}" add-br "${VXLAN_BR}" -- set bridge "${VXLAN_BR}" datapath_type=netdev
    "${VSCTL}" add-port "${DPDK_BR}" vxlan4 -- set interface vxlan4 type=vxlan \
    options:key=flow options:local_ip=flow options:remote_ip=flow options:dst_port=4790 \
    options:tun_nodecap=true options:in_nsi=flow options:in_nsp=flow \
    options:nshc1=flow options:nshc2=flow options:nshc3=flow options:nshc4=flow \

    #ip link set "${VXLAN_BR}" up
    #ip addr add "${VXLAN_IP}"/24 dev "${VXLAN_BR}"

    #Add controller's IP address to OVS
    ovs-vsctl set-controller SW4 tcp:"${ODL_CONTROLLER_IP}":6633
    ovs-vsctl set-manager tcp:"${ODL_CONTROLLER_IP}":6640

    #NOT SURE IF STILL NEEDED
    #if [[ $SFC_NODE == "CLS" ]]
    #then
    #   sleep 1
        #echo "Adding traffic steering rules..."
        #"${OFCTL}" add-flow br-int "in_port=1,ip,nw_src=10.0.0.1  actions=set_nsi:2, set_nsp=1001, output:2"
        #"${OFCTL}" add-flow br-int "in_port=1,ip,nw_src=10.0.0.2  actions=set_nsi:2, set_nsp=1002, output:2"
        #"${OFCTL}" add-flow br-int "in_port=1,ip,nw_src=10.0.0.3  actions=set_nsi:2, set_nsp=1003, output:2"
    #else
        #add ports for vhost-users - each VM will be assigned 2 of these ports
        #Configure openflow
        #echo "Adding traffic steering rules..."
        #"${OFCTL}" del-flows br-int
        #"${OFCTL}" add-flow br-int "table=0, priority=1, actions=drop"
        #"${OFCTL}" add-flow br-int "table=0, priority=256, in_port=1 actions=output:local"
        #"${OFCTL}" add-flow br-int "table=0, priority=256, in_port=3 actions=output:local"
        #"${OFCTL}" add-flow br-int "table=0, priority=256, in_port=4 actions=output:local"
        #"${OFCTL}" add-flow br-int "table=0, priority=256, in_port=5 actions=output:local"
        #"${OFCTL}" add-flow br-int "table=0, priority=256, in_port=6 actions=output:local"
        #"${OFCTL}" add-flow br-int "table=0, priority=256, in_port=7 actions=output:local"
        #"${OFCTL}" add-flow br-int "table=0, priority=256, in_port=8 actions=output:local"
        #"${OFCTL}" add-flow br-int "table=0, priority=256, in_port=2 actions=goto_table:1"

        #"${OFCTL}" add-flow br-int "table=1, priority=1, actions=drop"
        #"${OFCTL}" add-flow br-int "table=1, priority=256, nsi=2, nsp=1001 actions=output:3"
        #"${OFCTL}" add-flow br-int "table=1, priority=256, nsi=2, nsp=1002 actions=output:5"
        #"${OFCTL}" add-flow br-int "table=1, priority=256, nsi=2, nsp=1003 actions=output:7"

        #SFF1
        #"${OFCTL}" add-flow br-int "table=1, priority=256, nsp=1001, nsi=1, actions=mod_dl_dst:68:05:ca:30:6e:08,mod_nw_dst:200.2.0.103,output:1"
        #"${OFCTL}" add-flow br-int "table=1, priority=256, nsp=1002, nsi=1, actions=mod_dl_dst:68:05:ca:30:6e:08,mod_nw_dst:200.2.0.103,output:1"
        #"${OFCTL}" add-flow br-int "table=1, priority=256, nsp=1003, nsi=1, actions=mod_dl_dst:68:05:ca:30:6e:08,mod_nw_dst:200.2.0.103,output:1"

        #SFF2
        #"${OFCTL}" add-flow br-int "table=1, priority=256, nsp=1001, nsi=0, actions=mod_dl_src:68:05:ca:30:6e:08,mod_nw_src:200.2.0.103,mod_dl_dst:68:05:ca:30:6c:b0,mod_nw_dst:200.2.0.101,output:1"
        #"${OFCTL}" add-flow br-int "table=1, priority=256, nsp=1002, nsi=0, actions=mod_dl_src:68:05:ca:30:6e:08,mod_nw_src:200.2.0.103,mod_dl_dst:68:05:ca:30:6c:b0,mod_nw_dst:200.2.0.101,output:1"
        #"${OFCTL}" add-flow br-int "table=1, priority=256, nsp=1003, nsi=0, actions=mod_dl_src:68:05:ca:30:6e:08,mod_nw_src:200.2.0.103,mod_dl_dst:68:05:ca:30:6c:b0,mod_nw_dst:200.2.0.101,output:1"
    #fi
}


#============MAIN===============

    #Check if running as root


    if [[ $EUID == 0 ]] ;then
        get_files
        install_files
        setup_dpdk
        setup_first_ovs
        start_ovsdb
        start_vswitchd
        start_pkt_fwding
        #ovs-vsctl set bridge SW4 other-config:hwaddr=ec:f4:bb:d7:85:13
    else

        echo "You are currently not logged in as root. Please run this script as root"

    fi
