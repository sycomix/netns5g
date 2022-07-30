#!/bin/bash

#set -e

bridge_name=$(yq -r ".envConfig.network.bridge.name"  values.yaml)
force_disable_ipv6=$(yq -r ".envConfig.network.disableIpv6"  values.yaml)

move_if_to_namespace(){
    local interface=$1
    local namespace=$2

    ip link set $interface netns $namespace
}

create_bridge(){
    ip link add name "$bridge_name" type bridge
    ip link set up dev "$bridge_name"
}

attach_if_to_bridge(){
    local interface=$1
    ip link set dev "$interface" master "$bridge_name"
}

create_interface(){
    echo -e "create_interface: if_local $1, if_bridge $2, namespace $3"
    local if_local="$1"
    local if_bridge="$2"
    local namespace="$3"

    ip link add $if_local type veth peer name $if_bridge
    if [ "$namespace" != "root" ]
    then
        move_if_to_namespace $if_local $namespace
    fi
    attach_if_to_bridge $if_bridge
}

disableIpv6IfRequested(){
    if [ "$force_disable_ipv6" == "true" ]
    then
        echo -e "disableIpv6IfRequested: interface $1, namespace $2"
        local interface="$1"
        local namespace="$2"

        if [ "$namespace" == "root" ]
        then
            echo 1 > /proc/sys/net/ipv6/conf/"$interface"/disable_ipv6
        else
            ip netns exec "$namespace" sh -c "echo 1 > /proc/sys/net/ipv6/conf/$interface/disable_ipv6"
        fi
    fi
}

create_namespace(){
    echo -e "create namespace $1"
    local namespace="$1"
    if [ "$namespace" != "root" ]
    then
        ip netns add "$namespace"
    fi
}

configure_interface(){
    echo -e "configure_interface $1 $2 $3 $4"

    local if_local="$1"
    local if_bridge="$2"
    local namespace="$3"
    local address="$4"

    local cidr=$(yq -r ".envConfig.network.cidr"  values.yaml)

    ip link set up dev "$if_bridge"
    if [ "$namespace" == "root" ]
    then
        ip link set up dev "$if_local"
        ip address add "$address"/"$cidr" dev "$if_local"

    else
        ip netns exec "$namespace" ip link set up dev lo
        ip netns exec "$namespace" ip link set up dev "$if_local"
        ip netns exec "$namespace" ip address add "$address"/"$cidr" dev "$if_local"
    fi
    disableIpv6IfRequested $if_local $namespace
}


create_interfaces(){
    services_length=$(yq -r ".envConfig.services | length"  values.yaml)
    for (( service_idx=0; service_idx<$services_length; service_idx++ ))
    do
        local service_name=$(yq -r ".envConfig.services["$service_idx"].name" values.yaml)
        local namespace=$(yq -r ".envConfig.services["$service_idx"].namespace" values.yaml)
        create_namespace $namespace

        intefaces_length=$(yq -r ".envConfig.services["$service_idx"].interfaces | length"  values.yaml)
        for (( if_idx=0; if_idx<$intefaces_length; if_idx++ ))
        do
            local if_name=$(yq -r ".envConfig.services["$service_idx"].interfaces["$if_idx"].name" values.yaml)
            if_name="$namespace-$if_name"
            if_bridge="v-$if_name"

            create_interface $if_name $if_bridge $namespace

            address=$(yq -r ".envConfig.services["$service_idx"].interfaces["$if_idx"].address" values.yaml)
            configure_interface $if_name $if_bridge $namespace $address
        done
    done
}

main()
{
    create_bridge
    create_interfaces
}

main