#!/bin/ksh
# check_vlan.sh: Group VLAN IDs by adapter using ksh arrays and output to test_ent.txt

# Input entstat file (simulate /tmp/enstat.{sea_adapter}.{sea_adapter})
ENTSTAT_FILE="$(dirname $0)/sample/entstat.ent28.ent28"
OUTPUT_FILE="test_ent.txt"

# Arrays to hold adapter names and their VLAN IDs
set -A adapters
set -A vlans

vlan_section=0
adapter_count=0

while IFS= read -r line; do
  if echo "$line" | grep -q "VLAN Ids :"; then
    vlan_section=1
    continue
  fi
  if echo "$line" | grep -q "Real Side Statistics:"; then
    vlan_section=0
    continue
  fi
  if [ $vlan_section -eq 1 ]; then
    if echo "$line" | grep -q '^[a-zA-Z0-9][a-zA-Z0-9]*:'; then
      adapter=$(echo "$line" | awk -F: '{print $1}')
      vlan_ids=$(echo "$line" | awk -F: '{print $2}' | xargs)
      adapters[adapter_count]="$adapter"
      vlans[adapter_count]="$vlan_ids"
      adapter_count=$((adapter_count+1))
    fi
  fi
done < "$ENTSTAT_FILE"

# Output the results
> "$OUTPUT_FILE"
for ((i=0; i<adapter_count; i++)); do
  echo "${adapters[i]}: ${vlans[i]}" >> "$OUTPUT_FILE"
done

echo "VLAN IDs grouped by adapter written to $OUTPUT_FILE" 