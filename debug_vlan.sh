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
echo "Expected VLAN Tag IDs from file: 123 456"
echo "================================================" 