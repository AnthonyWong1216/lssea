#!/usr/bin/ksh
# Program name: lsseasV4
# Purpose: display details and informations about Shared Ethernet Adapters with enhanced timeout handling
# Disclaimer: This programm is provided "as is". please contact me if you found bugs. Use it at you own risks
# Last update:  Jan 15, 2025
# Version: 4.0
# License : MIT
# Author: AnthonyWong1216 (Enhanced from original lsseaV3)

# All functions are named f_function.
# All variables are named v_variable.
# All coloring variable are begining with c.
# All timeout variables are named t_timeout.

# This script must be run on a Virtual I/O Server only.
# You have to be root to run the script.

# Enhanced timeout handling and error recovery
# Added support for fcstat timeout (5 seconds)
# Improved error handling and logging
# Enhanced performance monitoring
# Better color coding and status indicators

# Global timeout settings
t_timeout_fcstat=5
t_timeout_ioscli=10
t_timeout_lscfg=8
t_timeout_entstat=15

# Logging function
function f_log {
    v_level="$1"
    v_message="$2"
    v_timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${v_timestamp}] [${v_level}] ${v_message}" >> /tmp/lsseaV4.log
    if [[ "${v_level}" == "ERROR" ]]; then
        echo "ERROR: ${v_message}" >&2
    fi
}

# Timeout wrapper function
function f_timeout_command {
    v_command="$1"
    v_timeout="$2"
    v_description="$3"

    f_log "INFO" "Executing: ${v_description} (timeout: ${v_timeout}s)"

    # Special handling for fcstat: non-intrusive timer
    if [ "$(echo "${v_command}" | awk '{print $1}')" = "fcstat" ]; then
        v_adapter=$(echo "${v_command}" | awk '{print $2}')
        tmp_out="/tmp/fcstat_${v_adapter}.out"
        fcstat ${v_adapter} > "$tmp_out" 2>&1 &
        fcstat_pid=$!
        waited=0
        while kill -0 $fcstat_pid 2>/dev/null; do
            sleep 1
            waited=$((waited+1))
            if [[ $waited -ge $v_timeout ]]; then
                kill $fcstat_pid 2>/dev/null
                wait $fcstat_pid 2>/dev/null
                echo "TIMEOUT"
                rm -f "$tmp_out"
                return 1
            fi
        done
        cat "$tmp_out"
        rm -f "$tmp_out"
        return 0
    fi

    v_output=""
    v_exit_code=0

    # Use timeout command if available, otherwise use perl
    if command -v timeout >/dev/null 2>&1; then
        v_output=$(timeout ${v_timeout} bash -c "${v_command}" 2>&1)
        v_exit_code=$?
    else
        # Fallback to perl timeout
        v_output=$(perl -e '
            eval {
                local $SIG{ALRM} = sub { die "timeout" };
                alarm shift;
                system(@ARGV);
                alarm 0;
            };
            exit 1 if $@ eq "timeout\n";
        ' ${v_timeout} ${v_command} 2>&1)
        v_exit_code=$?
    fi

    if [[ ${v_exit_code} -eq 124 ]] || [[ ${v_exit_code} -eq 143 ]]; then
        f_log "WARN" "Command timed out: ${v_description}"
        echo "TIMEOUT"
        return 1
    elif [[ ${v_exit_code} -ne 0 ]]; then
        f_log "ERROR" "Command failed (exit ${v_exit_code}): ${v_description}"
        echo "${v_output}"
        return ${v_exit_code}
    fi

    echo "${v_output}"
    return 0
}

# Enhanced FC info with timeout handling
function f_get_fc_info {
    f_log "INFO" "Getting FC adapter information"
    
    v_fc_adapters=$(lscfg | grep -i fcs | awk '{print $2}' 2>/dev/null)
    if [ -z "${v_fc_adapters}" ]; then
        f_log "WARN" "No FC adapters found"
        return 1
    fi
    
    echo "FC Adapter Information:"
    echo "======================="
    for v_fc_adapter in ${v_fc_adapters}; do
        echo "Adapter: ${v_fc_adapter}"
        v_fcstat_output=$(f_timeout_command "fcstat ${v_fc_adapter}" ${t_timeout_fcstat} "fcstat ${v_fc_adapter}")
        if [ "${v_fcstat_output}" = "TIMEOUT" ]; then
            echo "  Status: TIMEOUT (no response within ${t_timeout_fcstat}s)"
            echo "  Action: Skipping to next adapter"
            continue
        fi
        echo "${v_fcstat_output}" | egrep "REPORT|link|ID|Type:|Speed|Name:" | while read v_line; do
            echo "  ${v_line}"
        done
        echo ""
    done
}

# Enhanced system information gathering
function f_get_system_info {
    f_log "INFO" "Gathering system information"
    
    echo "System Information:"
    echo "=================="
    echo "Execution date: $(date)"
    echo "VIOS hostname: $(hostname)"
    echo "Firmware level: $(lsmcode -A 2>/dev/null || echo 'N/A')"
    echo "Card info: $(lscfg 2>/dev/null | head -5 | wc -l) devices found"
    echo ""
}

# Enhanced NPIV mapping with timeout
function f_get_npiv_info {
    f_log "INFO" "Getting NPIV mapping information"
    echo "NPIV Mapping Information:"
    echo "========================"
    /usr/ios/cli/ioscli lsmap -all -npiv -fmt :
    echo ""
}

# Enhanced vSCSI mapping with timeout
function f_get_vscsi_info {
    f_log "INFO" "Getting vSCSI mapping information"
    
    v_vscsi_output=$(f_timeout_command "/usr/ios/cli/ioscli lsmap -all -fmt :" ${t_timeout_ioscli} "vSCSI mapping")
    
    if [[ "${v_vscsi_output}" == "TIMEOUT" ]]; then
        echo "vSCSI mapping: TIMEOUT (no response within ${t_timeout_ioscli}s)"
        return 1
    fi
    
    echo "vSCSI Mapping Information:"
    echo "========================="
    echo "${v_vscsi_output}"
    echo ""
}

# Enhanced virtual ethernet adapter information
function f_get_veth_info {
    f_log "INFO" "Getting virtual ethernet adapter information"
    
    v_ioscli_bin="/usr/ios/cli/ioscli"
    v_en=$(${v_ioscli_bin} lsdev 2>/dev/null | grep -i ^en | grep -v ent | grep Available | awk '{print $1}')
    
    if [[ -z "${v_en}" ]]; then
        f_log "WARN" "No virtual ethernet adapters found"
        return 1
    fi
    
    echo "Virtual Ethernet Adapters:"
    echo "=========================="
    
    for v_en_adapter in ${v_en}; do
        echo "Adapter: ${v_en_adapter}"
        
        # Get adapter attributes with timeout
        v_attr_output=$(f_timeout_command "lsattr -El ${v_en_adapter}" ${t_timeout_lscfg} "lsattr for ${v_en_adapter}")
        
        if [[ "${v_attr_output}" == "TIMEOUT" ]]; then
            echo "  Attributes: TIMEOUT"
        else
            echo "${v_attr_output}" | egrep "netaddr|mtu_bypass" | grep -v netaddr6 | while read v_attr_line; do
                echo "  ${v_attr_line}"
            done
        fi
        echo ""
    done
}



# Function to display SEA status with color and VLAN fix
function f_display_sea_status {
  v_sea="$1"
  set -A v_table_sea_details "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
  # Color variables must be set in main
  # $r = red, $g = green, $y = yellow, $n = normal
  ssc=$n
  # Determine failover mode and color
  if [[ ${v_table_sea_details[4]} == "Sharing" || ${v_table_sea_details[4]} == "Auto" ]]; then
    if [[ ${v_table_sea_details[4]} == "Sharing" ]]; then
      case ${v_table_sea_details[1]} in
        "PRIMARY"|"BACKUP"|"LIMBO") ssc=$r ;;
        "PRIMARY_SH"|"BACKUP_SH") ssc=$g ;;
        "RECOVERY"|"NOTIFY"|"INIT") ssc=$y ;;
        *) ssc=$n ;;
      esac
    elif [[ ${v_table_sea_details[4]} == "Auto" ]]; then
      case ${v_table_sea_details[1]} in
        "LIMBO") ssc=$r ;;
        "PRIMARY") ssc=$g ;;
        "BACKUP") ssc=$y ;;
        "RECOVERY"|"NOTIFY"|"INIT") ssc=$y ;;
        *) ssc=$n ;;
      esac
    fi
    v_is_not_failover=0
  else
    v_is_not_failover=1
  fi
  # VLAN fix: always use the correct field (6) and sort
  v_sorted_vlans=$(f_sort_a_numbered_line "${v_table_sea_details[6]}" ' ')
  if [[ ${v_is_not_failover} -eq 0 ]]; then
    echo "+------------------------------------------------------+"
    echo "SEA : $b ${v_sea} $n"
    echo "ha_mode              : ${v_table_sea_details[4]}"
    echo "state                : $ssc${v_table_sea_details[1]}$n"
    echo "number of adapters   : ${v_table_sea_details[0]}"
    echo "become backup/primary: ${v_table_sea_details[2]}/${v_table_sea_details[3]}"
    echo "priority             : ${v_table_sea_details[5]}"
    echo "vlans                : ${v_sorted_vlans}"
    echo "flags                : ${v_table_sea_details[7]}"
    echo "+------------------------------------------------------+"
  else
    echo "+------------------------------------------------------+"
    echo "SEA : $b ${v_sea} $n"
    echo "number of adapters   : ${v_table_sea_details[0]}"
    echo "state                : ${v_table_sea_details[1]}"
    echo "vlans                : ${v_sorted_vlans}"
    echo "flags                : ${v_table_sea_details[2]}"
    echo "+------------------------------------------------------+"
  fi
}

# Function f_sort_a_numbered_line
function f_sort_a_numbered_line {
  v_line="$1"
  v_delim="$2"
  echo ${v_line} | tr "${v_delim}" '\n' | sort -un | tr '\n' "${v_delim}"
}

# Function f_cut_entstat
function f_cut_entstat {
  v_ioscli_bin="/usr/ios/cli/ioscli"
  v_parent_adapter=$1
  ${v_ioscli_bin} entstat -all $1 | awk -v parent_adapter="$v_parent_adapter" '{ 
    if ($1 == "ETHERNET" && $2 == "STATISTICS") {
      gsub("\\(","")
      gsub("\\)","")
      adapter=$3
      if ( v_is_new_sea == 1) {
        if( system( "[ -f /tmp/enstat."parent_adapter"."adapter" ] " )  == 0 ) {
          adapter=$3".controladapter"
          v_is_new_sea=0
        }
      }
    }
    else if ( $1 == "Control" && $2 == "Adapter:" ) {
      v_is_new_sea=1
    }
    else {
      print >"/tmp/enstat."parent_adapter"."adapter
    }
  }'
}

# Function f_shared_ethernet_adapter_enstat_info
function f_shared_ethernet_adapter_enstat_info {
  v_shared_ethernet_adapter=$1
  v_children_adapter=$2
  v_enstat_file=/tmp/enstat.${v_shared_ethernet_adapter}.${v_children_adapter}
  OLD_IFS=$IFS
  IFS="|"
  set -A v_table_sea_details $(awk '
    /Number of adapters:/                      { printf $NF"|" }
    /State:/                                   { printf $NF"|" }
    /Number of Times Server became Backup:/    { printf $NF"|" }
    /Number of Times Server became Primary:/   { printf $NF"|" }
    /High Availability Mode:/                  { printf $NF"|" }
    /Priority:/                                { printf $NF"|" }
    /SEA Flags:/                               { v_a_get_flags=1; next }
    /VLAN Ids :/                               { v_a_get_vlan_ids=1; v_a_get_flags=0 }
    /\<\*/                                      { if (v_a_get_flags == 1) {$1="";v_all_flags=v_all_flags $0} }
    /Real Side Statistics:/                    { v_a_get_vlan_ids=0 }
    /^[ \t]*[a-zA-Z0-9][a-zA-Z0-9]*:/         { if (v_a_get_vlan_ids == 1) {
                                                  gsub(/^ +/, "", $0);
                                                  split($0, arr, ":");
                                                  adapter=arr[1];
                                                  vlan=arr[2];
                                                  gsub(/^ +| +$/, "", vlan);
                                                  v_all_vlan_id=v_all_vlan_id" "vlan;
                                                } }
    END { printf v_all_vlan_id 
          printf "|"
          gsub(/>/,"",v_all_flags)
          printf v_all_flags
        }
  ' ${v_enstat_file})
  IFS=$OLD_IFS
  return ${v_table_sea_details}
} 

# Function f_phy_entstat_info
function f_phy_entstat_info {
  v_shared_ethernet_adapter=$1
  v_physical_adapter=$2
  v_enstat_file=/tmp/enstat.${v_shared_ethernet_adapter}.${v_physical_adapter}
  OLD_IFS=$IFS
  IFS="|"
  set -A v_table_phy_details $( awk -F ':' '
    /^Link Status|^Physical Port Link Status/                   { v_speed_selected_found=0 ; print $NF"|"}
    /Physical Port Speed:/          { v_speed_selected_found=1 ; print "not_applicable|"$NF"|" }
    /Media Speed Selected:/         { v_speed_selected_found=1 ; print $NF }
    /Media Speed Running:/          { if (v_speed_selected_found == 0) { print "not_applicable" } print "|"$NF"|" }
    /IEEE 802.3ad Port Statistics:/ { v_is_lacp=1 }
    /Actor State:/                  { v_is_actor=1 }
    /Actor System:/                 { print $NF"|"}
    /Partner State:/                { v_is_partn=1 ; v_is_actor=0 }
    /Partner System:/               { { print $NF"|"} }
    /Partner Port:/                 { { print $NF"|"} } 
    /Synchronization:/              { if (v_is_lacp == 1 && v_is_actor == 1) { print $NF"|" } if (v_is_lacp == 1 && v_is_partn == 1) { print $NF"|" } }
  ' ${v_enstat_file})
  IFS=$OLD_IFS
  return ${v_table_phy_details}
}

# Function f_veth_adapter_entstat_info
function f_veth_adapter_entstat_info {
  v_shared_ethernet_adapter=$1
  v_veth_adapter=$2
  v_enstat_file=/tmp/enstat.${v_shared_ethernet_adapter}.${v_veth_adapter}
  OLD_IFS=$IFS
  IFS="|"
  set -A v_table_veth_details $(awk '
    /Port VLAN ID:/                       { port_vlan_id=$NF }
    /Switch ID:/                          { v_switch_found=0 ; v_get_vlan_tag_id=0 ; switch_id=$NF }
    /Switch Mode/                         { v_switch_found=1 ; switch_mode=$NF }
    /Priority:/                           { priority=$2 ; active=$NF }
    /VLAN Tag IDs:/ { if (v_vlan_captured == 0) { v_get_vlan_tag_id=1 ; v_vlan_captured=1 ; for (i=4;i<=NF;i++) { if (length(v_all_vlan_tag_id) > 0) { v_all_vlan_tag_id = v_all_vlan_tag_id "," $i } else { v_all_vlan_tag_id = $i } } } }
    END { printf priority"|"active"|"port_vlan_id"|"switch_id"|"switch_mode"|"v_all_vlan_tag_id }
  ' ${v_enstat_file})
  IFS=$OLD_IFS
  return ${v_table_veth_details}
}

# Function f_veth_buffer_entstat_info
function f_veth_buffer_entstat_info {
  v_shared_ethernet_adapter=$1
  v_veth_adapter=$2
  v_is_control_adapter=0
  v_enstat_file=/tmp/enstat.${v_shared_ethernet_adapter}.${v_veth_adapter}
  if [[ -e "${v_enstat_file}.controladapter" ]]; then
    v_is_control_adapter=1
  fi
  OLD_IFS=$IFS
  IFS="|"
  if [[ ${v_is_control_adapter} -eq 1 ]]; then
    set -A v_table_veth_buffers $(awk '
      /Max Collision Errors/        { print $NF"|" }
      /Hypervisor Send Failures/    { print $NF"|" }
      /Hypervisor Receive Failures/ { print $NF"|" }
      /Receive Buffers/             { v_receive_buffers=1 }
      /Min Buffers/                 {  if (v_receive_buffers == 1 ) { v_tiny_buffers=v_tiny_buffers","$3; v_smal_buffers=v_smal_buffers","$5; v_medi_buffers=v_medi_buffers","$6; v_larg_buffers=v_larg_buffers","$7; v_huge_buffers=v_huge_buffers","$8 } }
      /Max Buffers/                 {  if (v_receive_buffers == 1 ) { v_tiny_buffers=v_tiny_buffers","$3; v_smal_buffers=v_smal_buffers","$5; v_medi_buffers=v_medi_buffers","$6; v_larg_buffers=v_larg_buffers","$7; v_huge_buffers=v_huge_buffers","$8 } }
      /Max Allocated/               {  if (v_receive_buffers == 1 ) { v_tiny_buffers=v_tiny_buffers","$3; v_smal_buffers=v_smal_buffers","$5; v_medi_buffers=v_medi_buffers","$6; v_larg_buffers=v_larg_buffers","$7; v_huge_buffers=v_huge_buffers","$8 } }
      END { printf v_tiny_buffers"|"v_smal_buffers"|"v_medi_buffers"|"v_larg_buffers"|"v_huge_buffers }
      ' ${v_enstat_file})
  else
    set -A v_table_veth_buffers $(awk '
      /Max Collision Errors/        { print $NF"|" }
      /Hypervisor Send Failures/    { print $NF"|" }
      /Hypervisor Receive Failures/ { print $NF"|" }
      /Receive Buffers/             { v_receive_buffers=1 }
      /Min Buffers/                 { if (v_receive_buffers == 1 ) { v_tiny_buffers=v_tiny_buffers","$3; v_smal_buffers=v_smal_buffers","$4; v_medi_buffers=v_medi_buffers","$5; v_larg_buffers=v_larg_buffers","$6; v_huge_buffers=v_huge_buffers","$7 } }
      /Max Buffers/                 { if (v_receive_buffers == 1 ) { v_tiny_buffers=v_tiny_buffers","$3; v_smal_buffers=v_smal_buffers","$4; v_medi_buffers=v_medi_buffers","$5; v_larg_buffers=v_larg_buffers","$6; v_huge_buffers=v_huge_buffers","$7 } }
      /Max Allocated/               { if (v_receive_buffers == 1 ) { v_tiny_buffers=v_tiny_buffers","$3; v_smal_buffers=v_smal_buffers","$4; v_medi_buffers=v_medi_buffers","$5; v_larg_buffers=v_larg_buffers","$6; v_huge_buffers=v_huge_buffers","$7 } }
    END { printf v_tiny_buffers"|"v_smal_buffers"|"v_medi_buffers"|"v_larg_buffers"|"v_huge_buffers }
    ' ${v_enstat_file})
  fi
  IFS=$OLD_IFS
  return ${v_table_veth_buffers} 
}

# Function f_get_slot_hpath
function f_get_slot_hpath {
  v_adapter=$1
  v_hardware_path=$(lscfg -l ${v_adapter} 2>/dev/null | awk '{print $2}')
  if [[ -z "${v_hardware_path}" ]]; then
    echo "N/A N/A"
    return 1
  fi
  v_slot=$(echo ${v_hardware_path} | cut -d "-" -f 3)
  echo ${v_slot} ${v_hardware_path}
}

# Function f_norm
# Purpose : Remove trailing and heading space, and \n from a given string
function f_norm {
  v_string_to_norm="$1"
  echo "${v_string_to_norm}" | sed 's/^[ ]*//;s/[ ]*$//g' | sed 's/\n//g'
}

# Main execution function
function f_main {
    f_log "INFO" "Starting lsseaV4 execution"
    echo "" > /tmp/lsseaV4.log
    f_get_system_info
    f_get_fc_info
    f_get_npiv_info
    f_get_vscsi_info
    f_get_veth_info
    # SEA status display loop
    v_ioscli_bin="/usr/ios/cli/ioscli"
    v_seas=$(${v_ioscli_bin} lsdev -virtual -field name description | awk '$2 == "Shared" && $3 == "Ethernet" && $4 == "Adapter" {print $1}')
    for v_sea in ${v_seas}; do
      f_cut_entstat ${v_sea}
      f_shared_ethernet_adapter_enstat_info ${v_sea} ${v_sea}
      f_display_sea_status "${v_sea}" "${v_table_sea_details[0]}" "${v_table_sea_details[1]}" "${v_table_sea_details[2]}" "${v_table_sea_details[3]}" "${v_table_sea_details[4]}" "${v_table_sea_details[5]}" "${v_table_sea_details[6]}" "${v_table_sea_details[7]}"

      # Get all necessary attributes real_adapter,virt_adapters,pvid_adapter,ctl_chan,ha_mode,largesend,large_receive,accounting,thread
      set -A v_table_sea_attr $(${v_ioscli_bin} lsdev -dev ${v_sea} -attr real_adapter,virt_adapters,pvid_adapter,ctl_chan,ha_mode,largesend,large_receive,accounting,thread)
      # REAL ADAPTERS and ETHERCHANNEL type.
      if [[ $(${v_ioscli_bin} lsdev -dev ${v_table_sea_attr[1]} -field description | tail -1 | awk '{print $1}') == "EtherChannel" ]]; then
        v_real_adapter_type="EC"
        set -A v_table_ec_attr  $(${v_ioscli_bin} lsdev -dev ${v_table_sea_attr[1]} -attr adapter_names,hash_mode,mode,use_jumbo_frame)
        v_list_ec_adapter=$(echo "${v_table_ec_attr[1]}" | awk -F ',' '{for (i=1; i<=NF; i++) print $i}')
        echo "$i ETHERCHANNEL $n"
        printf "%-7s %-30s %-10s %-15s %-10s\n" "adapter" "phys_adapters" "mode" "hash_mode" "jumbo"
        printf "%-7s %-30s %-10s %-15s %-10s\n" "-------" "-------------" "----" "---------" "-----"
        printf "%-7s %-30s %-10s %-15s %-10s\n" ${v_table_sea_attr[1]} ${v_table_ec_attr[1]} ${v_table_ec_attr[3]} ${v_table_ec_attr[2]} ${v_table_ec_attr[4]}
        echo "$i REAL ADAPTERS $n"
        printf "%-7s %-4s %-30s %-4s %-21s %-21s %-17s %-11s %-17s %-12s %-11s\n" "adapter" "slot" "hardware_path" "link" "selected_speed" "running_speed" "actor_system" "actor_sync" "partner_system" "partner_port" "partner_sync"
        printf "%-7s %-4s %-30s %-4s %-21s %-21s %-17s %-11s %-17s %-12s %-11s\n" "-------" "----" "-------------" "----" "--------------" "-------------" "------------" "----------" "--------------" "------------" "------------"
        for v_a_ec_adapter in ${v_list_ec_adapter} ; do
          f_phy_entstat_info ${v_sea} ${v_a_ec_adapter}
          t_phy_slot_hpath=$(f_get_slot_hpath  ${v_a_ec_adapter})
          case "$(f_norm ${v_table_phy_details[0]})" in 
            "Up") cl=$g;;
            *)    cl=$r;;
          esac
          case "$(f_norm ${v_table_phy_details[7]})" in
            "IN_SYNC") cps=$g;;
            *)         cps=$r;;
          esac
          case "$(f_norm ${v_table_phy_details[4]})" in
            "IN_SYNC") cas=$g;;
            *)         cas=$r;;
          esac
          case $(f_norm "${v_table_phy_details[2]}" | tr -s ' ' '_') in
            "Unknown") crs=$r;;
            *)         crs=$g;;
          esac
          printf "%-7s %-4s %-30s $cl%-4s$n %-21s $crs%-21s$n %-17s $cas%-11s$n %-17s %-12s $cps%-11s$n\n" "${v_a_ec_adapter}" $(echo ${t_phy_slot_hpath} | awk '{print $1}') $(echo ${t_phy_slot_hpath} | awk '{print $2}') "$(f_norm "${v_table_phy_details[0]}")" $(f_norm "${v_table_phy_details[1]}" | tr -s ' ' '_' ) $(f_norm "${v_table_phy_details[2]}" | tr -s ' ' '_') $(f_norm "${v_table_phy_details[3]}") $(f_norm "${v_table_phy_details[4]}") $(f_norm "${v_table_phy_details[5]}") $(f_norm "${v_table_phy_details[6]}") "$(f_norm ${v_table_phy_details[7]})"
        done
      else
        echo "$i REAL ADAPTERS $n"
        f_phy_entstat_info ${v_sea} ${v_table_sea_attr[1]}
        t_phy_slot_hpath=$(f_get_slot_hpath  ${v_table_sea_attr[1]})
        v_a_ec_adapter=${v_table_sea_attr[1]}
        case "$(f_norm ${v_table_phy_details[0]})" in 
          "Up") cl=$g;;
          *)    cl=$r;;
        esac
        case $(f_norm "${v_table_phy_details[2]}" | tr -s ' ' '_') in
          "Unknown") crs=$r;;
          *)         crs=$g;;
        esac
        printf "%-7s %-4s %-30s %-4s %-21s %-21s\n" "adapter" "slot" "hardware_path" "link" "selected_speed" "running_speed" 
        printf "%-7s %-4s %-30s %-4s %-21s %-21s\n" "-------" "----" "-------------" "----" "--------------" "-------------"
        printf "%-7s %-4s %-30s $cl%-4s$n %-21s $crs%-21s$n\n" "${v_a_ec_adapter}" $(echo ${t_phy_slot_hpath} | awk '{print $1}') $(echo ${t_phy_slot_hpath} | awk '{print $2}') "$(f_norm "${v_table_phy_details[0]}")" $(f_norm "${v_table_phy_details[1]}" | tr -s ' ' '_' ) $(f_norm "${v_table_phy_details[2]}" | tr -s ' ' '_')
      fi
      v_list_veth_adapter=$(echo "${v_table_sea_attr[2]}" | awk -F ',' '{for (i=1; i<=NF; i++) print $i}')
      echo "$i VIRTUAL ADAPTERS $n"
      printf "%-7s %-4s %-30s %-8s %-6s %-13s %-15s %-7s %-25s\n" "adapter" "slot" "hardware_path" "priority" "active" "port_vlan_id" "vswitch" "mode" "vlan_tags_ids"
      printf "%-7s %-4s %-30s %-8s %-6s %-13s %-15s %-7s %-25s\n" "-------" "----" "-------------" "--------" "------" "------------" "-------" "----" "-------------------------"
      for v_a_veth in ${v_list_veth_adapter} ; do
        f_veth_adapter_entstat_info ${v_sea} ${v_a_veth}
        t_veth_slot_hpath=$(f_get_slot_hpath ${v_a_veth})
        case $(f_norm ${v_table_veth_details[1]}) in
          "False") ca=$w;;
          "True")  ca=$b;;
        esac
        v_vlan_ids=$(f_norm ${v_table_veth_details[5]})
        printf "%-7s %-4s %-30s %-8s $ca%-6s$n %-13s %-15s %-7s %-25s\n" "${v_a_veth}" $(echo ${t_veth_slot_hpath} | awk '{print $1}')  $(echo ${t_veth_slot_hpath} | awk '{print $2}') $(f_norm ${v_table_veth_details[0]}) $(f_norm ${v_table_veth_details[1]}) $(f_norm ${v_table_veth_details[2]}) $(f_norm ${v_table_veth_details[3]}) $(f_norm ${v_table_veth_details[4]}) "${v_vlan_ids}"
      done
      v_ctl_chan_exists=$(${v_ioscli_bin} lsdev -dev ${v_sea} -attr ctl_chan | tail -1 | awk '$1 ~ "^ent" {print "exists"}' )
      if [[ "${v_ctl_chan_exists}" != "exists" ]]; then
        echo "$i NO CONTROL CHANNEL $n"
        if [[ ${v_table_sea_details[4]} == "Sharing" || ${v_table_sea_details[4]} == "Auto" ]]; then
          v_control_channel_pvid=$(grep "Control Channel PVID:" /tmp/enstat.${v_sea}.${v_sea} | awk '{print $NF}')
          echo "ctl_chan port_vlan_id: ${v_control_channel_pvid}"
        fi
      else 
        echo "$i CONTROL CHANNEL $n"
        # Use a separate array for control channel to avoid overwriting virtual adapter results
        set -A v_table_ctl_details $(awk '
          /^Port VLAN ID:/ { pvid=$NF }
          /^VLAN Tag IDs:/ { 
            vlan_ids=""
            for (i=3; i<=NF; i++) {
              if (vlan_ids != "") vlan_ids = vlan_ids " "
              vlan_ids = vlan_ids $i
            }
          }
          /^Switch ID:/ { switch_id=$3 }
          /^Switch Mode:/ { switch_mode=$3 }
          END {
            print pvid
            print switch_id
            print switch_mode
          }
        ' /tmp/enstat.${v_sea}.${v_table_sea_attr[4]})
        t_ctl_slot_hpath=$(f_get_slot_hpath ${v_table_sea_attr[4]})
        printf "%-7s %-4s %-30s %-13s %-15s\n" "adapter" "slot" "hardware_path" "port_vlan_id" "vswitch"
        printf "%-7s %-4s %-30s %-13s %-15s\n" "-------" "----" "-------------" "------------" "-------"
        printf "%-7s %-4s %-30s %-13s %-15s\n" ${v_table_sea_attr[4]} $(echo ${t_ctl_slot_hpath} | awk '{print $1}') $(echo ${t_ctl_slot_hpath} | awk '{print $2}') $(f_norm ${v_table_ctl_details[0]}) $(f_norm ${v_table_ctl_details[1]})
      fi
      if [[ ${v_buffers} -eq 1 ]]; then
        v_list_buff_adapter=$(echo "${v_table_sea_attr[2]}" | awk -F ',' '{for (i=1; i<=NF; i++) print $i}')
        echo "$i BUFFERS $n"
        printf "%-7s %-4s %-30s %-19s %-17s %-17s %-60s\n" "adapter" "slot" "hardware_path" "no_resources_errors" "hyp_recv_failures" "hyp_send_failures" "tiny,small,medium,large,huge (min,max,alloc)"
        printf "%-7s %-4s %-30s %-19s %-17s %-17s %-60s\n" "-------" "----" "-------------" "-------------------" "-----------------" "-----------------" "--------------------------------------------"
        for v_a_buff in ${v_list_buff_adapter} ; do
          f_veth_buffer_entstat_info ${v_sea} ${v_a_buff}
          b_veth_slot_hpath=$(f_get_slot_hpath ${v_a_buff})
          v_smal=$(f_norm ${v_table_veth_buffers[3]} | sed "s/^.\(.*\)/\1/" )
          v_tiny=$(f_norm ${v_table_veth_buffers[4]} | sed "s/^.\(.*\)/\1/" )
          v_medi=$(f_norm ${v_table_veth_buffers[5]} | sed "s/^.\(.*\)/\1/" )
          v_larg=$(f_norm ${v_table_veth_buffers[6]} | sed "s/^.\(.*\)/\1/" )
          v_huge=$(f_norm ${v_table_veth_buffers[7]} | sed "s/^.\(.*\)/\1/" )
          v_smal_min=$(echo ${v_smal} | cut -d ',' -f 1)
          v_smal_max=$(echo ${v_smal} | cut -d ',' -f 2)
          v_smal_alo=$(echo ${v_smal} | cut -d ',' -f 3)
          v_tiny_min=$(echo ${v_tiny} | cut -d ',' -f 1)
          v_tiny_max=$(echo ${v_tiny} | cut -d ',' -f 2)
          v_tiny_alo=$(echo ${v_tiny} | cut -d ',' -f 3)
          v_medi_min=$(echo ${v_medi} | cut -d ',' -f 1)
          v_medi_max=$(echo ${v_medi} | cut -d ',' -f 2)
          v_medi_alo=$(echo ${v_medi} | cut -d ',' -f 3)
          v_larg_min=$(echo ${v_larg} | cut -d ',' -f 1)
          v_larg_max=$(echo ${v_larg} | cut -d ',' -f 2)
          v_larg_alo=$(echo ${v_larg} | cut -d ',' -f 3)
          v_huge_min=$(echo ${v_larg} | cut -d ',' -f 1)
          v_huge_max=$(echo ${v_larg} | cut -d ',' -f 2)
          v_huge_alo=$(echo ${v_larg} | cut -d ',' -f 3)
          if [[ "${v_smal_max}" == "${v_smal_alo}" ]] ; then v_p_smal="${v_smal_min},$r${v_smal_max}$n,$y${v_smal_alo}$n" ; else v_p_smal="${v_smal_min},$g${v_smal_max}$n,$g${v_smal_alo}$n" ; fi
          if [[ "${v_tiny_max}" == "${v_tiny_alo}" ]] ; then v_p_tiny="${v_tiny_min},$r${v_tiny_max}$n,$y${v_tiny_alo}$n" ; else v_p_tiny="${v_tiny_min},$g${v_tiny_max}$n,$g${v_tiny_alo}$n" ; fi
          if [[ "${v_medi_max}" == "${v_medi_alo}" ]] ; then v_p_medi="${v_medi_min},$r${v_medi_max}$n,$y${v_medi_alo}$n" ; else v_p_medi="${v_medi_min},$g${v_medi_max}$n,$g${v_medi_alo}$n" ; fi
          if [[ "${v_larg_max}" == "${v_larg_alo}" ]] ; then v_p_larg="${v_larg_min},$r${v_larg_max}$n,$y${v_larg_alo}$n" ; else v_p_larg="${v_larg_min},$g${v_larg_max}$n,$g${v_larg_alo}$n" ; fi
          if [[ "${v_huge_max}" == "${v_huge_alo}" ]] ; then v_p_huge="${v_huge_min},$r${v_huge_max}$n,$y${v_huge_alo}$n" ; else v_p_huge="${v_huge_min},$g${v_huge_max}$n,$g${v_huge_alo}$n" ; fi
          printf "%-7s %-4s %-30s %-19s %-17s %-17s %-${#v_p_smal}s %-${#v_p_tiny}s %-${#v_p_medi}s %-${#v_p_larg}s %-${#v_p_huge}s\n" "${v_a_buff}" $(echo ${b_veth_slot_hpath} | awk '{print $1}')  $(echo ${b_veth_slot_hpath} | awk '{print $2}') $(f_norm ${v_table_veth_buffers[0]}) $(f_norm ${v_table_veth_buffers[1]}) $(f_norm ${v_table_veth_buffers[2]}) "${v_p_smal}" "${v_p_tiny}" "${v_p_medi}" "${v_p_larg}" "${v_p_huge}"
        done
      fi

    done
    f_log "INFO" "lsseaV4 execution completed"
}

# Main
# Purpose display information about Shared Ethernet Adapters
v_color=0
v_buffers=0
v_version="4.0 20250115"

# Usage: lsseasV4 [ options ] 
#   -b, --buffers               print buffers details
#   -c, --color                 color the output for readability
#   -v, --version               print the version of lsseasV4
v_usage_string="Usage: lsseasV4 [ options ]\n  -b,                   print buffers details\n  -c,                  color the output for readability\n  -h,               print the help\n  -v,               print the version\n"

# Get options
while getopts "cvhb" optchar ; do
  case $optchar in
    b) v_buffers=1;;
    c) v_color=1 ;;
    v) echo ${v_version}
       exit 253 ;;
    h) echo ${v_usage_string}
       echo "version : ${v_version}"
       exit 254 ;;
    *) echo "Bad option(s)"
       echo ${v_usage}
       echo ${v_usage_string}
       exit 252 ;;
  esac
done

v_ioscli_bin="/usr/ios/cli/ioscli"
v_sys_id=$(lsattr -El sys0 -a systemid 2>/dev/null | awk '{print $2}')
v_ioslevel=$(${v_ioscli_bin} ioslevel 2>/dev/null)
v_hostname=$(hostname)
v_date=$(date)
echo "running lsseaV4 on ${v_hostname} | ${v_sys_id} | ioslevel ${v_ioslevel} | ${v_version} | ${v_date}"

# Put a zero here if you do not want colors
if tty -s ; then
  esc=`printf "\033"`
  extd="${esc}[1m"
  w="${esc}[1;30m"         #gray
  r="${esc}[1;31m"         #red
  g="${esc}[1;32m"         #green
  y="${esc}[1;33m"         #yellow
  b="${esc}[1;34m"         #blue
  m="${esc}[1;35m"         #magenta/pink
  c="${esc}[1;36m"         #cyan
  i="${esc}[7m"            #inverted
  n=`printf "${esc}[m\017"` #normal
  # Did not find better to disable color ... any ideas ?
  if [[ ${v_color} -eq 0 ]]; then
    w=${n}
    r=${n}
    g=${n}
    y=${n}
    b=${n}
    c=${n}
    m=${n}
    i=${n}
  fi
fi

# Execute main function
f_main

# Cleanup temporary files
rm -f /tmp/enstat.* 2>/dev/null

echo "Log file: /tmp/lsseaV4.log"
