#!/bin/ksh
# check_vlan.sh: Extract VLAN IDs from a sample entstat file and output to test_ent.txt

# Input entstat file (simulate /tmp/enstat.{sea_adapter}.{sea_adapter})
ENTSTAT_FILE="$(dirname $0)/sample/entstat.ent28.ent28"
OUTPUT_FILE="test_ent.txt"

awk '
  /VLAN Ids :/                               { v_a_get_vlan_ids=1; v_a_get_flags=0 }
  /Real Side Statistics:/                    { v_a_get_vlan_ids=0 }
  /ent[0-9]*:/                               { if (v_a_get_vlan_ids == 1) {$1=""; v_all_vlan_id=v_all_vlan_id $0} }
  END { print v_all_vlan_id }
' "$ENTSTAT_FILE" > "$OUTPUT_FILE"

echo "VLAN IDs extracted to $OUTPUT_FILE" 