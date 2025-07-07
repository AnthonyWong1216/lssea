#!/bin/ksh
# Debug script to test VLAN tag ID extraction

ENTSTAT_FILE="sample/enstat.ent8.ent6"

echo "Testing VLAN tag ID extraction from $ENTSTAT_FILE"
echo "================================================"

# Test the exact awk script from lsseasV4.sh
echo "Raw awk output:"
awk '
    /Port VLAN ID:/                       { printf "Port VLAN ID: " $NF"|" }
    /Switch ID:/                          { v_switch_found=0 ; v_get_vlan_tag_id=0 ; printf "Switch ID: " $NF"|" }
    /Switch Mode/                         { v_switch_found=1 ; printf "Switch Mode: " $NF"|" }
    /Priority:/                           { printf "Priority: " $2"|"$NF"|" }
    /VLAN Tag IDs:/                       { if (v_vlan_captured == 0) { v_get_vlan_tag_id=1 ; v_vlan_captured=1 ; printf "Found VLAN Tag IDs line: "; for (i=2;i<=NF;i++) { if ($i ~ /[0-9][0-9]*/ ) { v_all_vlan_tag_id=v_all_vlan_tag_id" "$i } } } }
    END { printf "VLAN Tag IDs captured: [" v_all_vlan_tag_id "]" }
' $ENTSTAT_FILE

echo ""
echo "================================================"
echo "Testing the complete array assignment:"
echo "================================================"

# Test the complete array assignment like in the script
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
echo "Testing f_norm function:"
echo "f_norm of v_table_veth_details[5] = [$(echo "${v_table_veth_details[5]}" | sed 's/^[ ]*//;s/[ ]*$//g' | sed 's/\n//g')]"

echo ""
echo "Testing printf format:"
v_vlan_ids=$(echo "${v_table_veth_details[5]}" | sed 's/^[ ]*//;s/[ ]*$//g' | sed 's/\n//g')
v_vlan_count=${#v_vlan_ids}
echo "v_vlan_ids = [$v_vlan_ids]"
echo "v_vlan_count = $v_vlan_count"
echo "printf format: %-${#v_vlan_ids}s"

echo ""
echo "================================================"
echo "Expected VLAN Tag IDs from file: 123 456"
echo "================================================" 