#!/bin/bash

#set -e

bridge_name=$(yq -r ".envConfig.network.bridge.name"  values.yaml)


delete_bridge(){
    ip link set dev "$bridge_name" down
    ip link del name "$bridge_name" type bridge
}

delete_if_from_bridge(){
    local interface=$1
    ip link set "$interface" nomaster
}


delete_interfaces(){
    services_length=$(yq -r ".envConfig.services | length"  values.yaml)
    for (( service_idx=0; service_idx<$services_length; service_idx++ ))
    do
        local namespace=$(yq -r ".envConfig.services["$service_idx"].namespace" values.yaml)
        intefaces_length=$(yq -r ".envConfig.services["$service_idx"].interfaces | length"  values.yaml)
        for (( if_idx=0; if_idx<$intefaces_length; if_idx++ ))
        do
            local if_name=$(yq -r ".envConfig.services["$service_idx"].interfaces["$if_idx"].name" values.yaml)
            if_bridge="v-$namespace-$if_name"

            delete_if_from_bridge "$if_bridge"
            ip link del dev "$if_bridge"

        done
    done
}

delete_namespaces(){
    services_length=$(yq -r ".envConfig.services | length"  values.yaml)
    for (( service_idx=0; service_idx<$services_length; service_idx++ ))
    do
        local namespace=$(yq -r ".envConfig.services["$service_idx"].namespace" values.yaml)
        if [ "$namespace" != "root" ]
        then
            ip netns del "$namespace"
        fi
    done
}

main(){
    delete_interfaces
    delete_namespaces
    delete_bridge
}

main


