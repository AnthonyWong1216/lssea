#!/bin/ksh
# Test script to verify VLAN extraction

ENTSTAT_FILE="sample/enstat.ent8.ent6"

echo "Testing VLAN extraction from $ENTSTAT_FILE"
echo "=========================================="

# Test the exact awk script
awk '
    /Port VLAN ID:/                       { port_vlan_id=$NF }
    /Switch ID:/                          { v_switch_found=0 ; v_get_vlan_tag_id=0 ; switch_id=$NF }
    /Switch Mode/                         { v_switch_found=1 ; switch_mode=$NF }
    /Priority:/                           { priority=$2 ; active=$NF }
    /VLAN Tag IDs:/                       { if (v_vlan_captured == 0) { v_get_vlan_tag_id=1 ; v_vlan_captured=1 ; for (i=2;i<=NF;i++) { if ($i ~ /[0-9][0-9]*/ ) { v_all_vlan_tag_id=v_all_vlan_tag_id" "$i } } } }
    END { 
        print "Priority: [" priority "]"
        print "Active: [" active "]"
        print "Port VLAN ID: [" port_vlan_id "]"
        print "Switch ID: [" switch_id "]"
        print "Switch Mode: [" switch_mode "]"
        print "VLAN Tag IDs: [" v_all_vlan_tag_id "]"
    }
' $ENTSTAT_FILE

echo ""
echo "Testing with array assignment:"
OLD_IFS=$IFS
IFS="|"
set -A v_table_veth_details $(awk '
    /Port VLAN ID:/                       { port_vlan_id=$NF }
    /Switch ID:/                          { v_switch_found=0 ; v_get_vlan_tag_id=0 ; switch_id=$NF }
    /Switch Mode/                         { v_switch_found=1 ; switch_mode=$NF }
    /Priority:/                           { priority=$2 ; active=$NF }
    /VLAN Tag IDs:/                       { if (v_vlan_captured == 0) { v_get_vlan_tag_id=1 ; v_vlan_captured=1 ; for (i=2;i<=NF;i++) { if ($i ~ /[0-9][0-9]*/ ) { v_all_vlan_tag_id=v_all_vlan_tag_id" "$i } } } }
    END { printf priority"|"active"|"port_vlan_id"|"switch_id"|"switch_mode"|"v_all_vlan_tag_id }
' $ENTSTAT_FILE)
IFS=$OLD_IFS

echo "Array elements:"
echo "v_table_veth_details[0] = [${v_table_veth_details[0]}]"
echo "v_table_veth_details[1] = [${v_table_veth_details[1]}]"
echo "v_table_veth_details[2] = [${v_table_veth_details[2]}]"
echo "v_table_veth_details[3] = [${v_table_veth_details[3]}]"
echo "v_table_veth_details[4] = [${v_table_veth_details[4]}]"
echo "v_table_veth_details[5] = [${v_table_veth_details[5]}]"

echo ""
echo "Testing f_norm:"
v_vlan_ids=$(echo "${v_table_veth_details[5]}" | sed 's/^[ ]*//;s/[ ]*$//g' | sed 's/\n//g')
echo "After f_norm: [$v_vlan_ids]"
echo "Length: ${#v_vlan_ids}"

echo ""
echo "Testing printf:"
printf "%-7s %-4s %-30s %-8s %-6s %-13s %-15s %-7s %-25s\n" "adapter" "slot" "hardware_path" "priority" "active" "port_vlan_id" "vswitch" "mode" "vlan_tags_ids"
printf "%-7s %-4s %-30s %-8s %-6s %-13s %-15s %-7s %-25s\n" "-------" "----" "-------------" "--------" "------" "------------" "-------" "----" "-------------------------"
printf "%-7s %-4s %-30s %-8s %-6s %-13s %-15s %-7s %-25s\n" "ent6" "C41" "U9105.22A.7892A71-V1-C41-T0" "1" "True" "99" "ETHERNET0" "VEB" "${v_vlan_ids}" 