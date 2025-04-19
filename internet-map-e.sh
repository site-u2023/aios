#!/bin/sh

# internet-map-e.sh
# Calculates MAP-E parameters based on user IPv6 prefix, aiming for 100% compatibility
# with the logic from https://github.com/missing233/map-e/blob/master/map-e.js

# --- Global Variables ---
# Set by mape_mold, used by mape_display/mape_config
MAPE_STATUS="init" # Status: init, success, fail
RULE_NAME=""       # Matched rule name (e.g., "v6plus_jpne")
IPV4=""            # Calculated user shared IPv4 address
BR=""              # Border Relay IPv6 address
IP6PFX=""          # User's normalized IPv6 prefix used for calculation
CE_ADDR=""         # Calculated CE IPv6 address
IP4PREFIXLEN=""    # User's effective IPv4 prefix length (e.g., 32 for /32)
IP6PREFIXLEN=""    # Rule's IPv6 prefix length (e.g., 32, 48)
EALEN=""           # Calculated EA-bits length
PSIDLEN=""         # Rule's PSID length
OFFSET=""          # Rule's offset (a-bits)
PSID=""            # Calculated PSID value
PORTS=""           # Calculated port range string (e.g., "1024-2047")
RFC=""             # Rule's RFC flag (true/false)

# --- Logging ---
DEBUG=0 # Set to 1 to enable debug messages
log_msg() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        "I") echo "$timestamp [INFO] MAP-E: $msg" ;;
        "E") echo "$timestamp [ERROR] MAP-E: $msg" >&2 ;;
        "D") [ "$DEBUG" -eq 1 ] && echo "$timestamp [DEBUG] MAP-E: $msg" ;;
        *) echo "$timestamp [UNKN] MAP-E: $msg" ;;
    esac
}

# --- Start of Rule Definition Functions ---
# Fully implemented based on map-e.js rules array

get_rule_ids() {
    echo "v6plus_jpne \
ocn_v1 \
ocn_v2 \
transix_ipv4_provider_fix \
transix_ipv4_provider_var \
transix_dsbn_fix \
iijmio_fiberaccess_f \
v6connect_fixed_ip \
v6connect_dynamic_ip \
cross_pass \
v6option \
ocn_for_docomo_net"
}

get_rule_ipv6_cidrs() {
    local rule_id="$1"
    case "$rule_id" in
        "v6plus_jpne") echo "240b:10::/32 240b:11::/32 240b:12::/32 240b:13::/32 240b:250::/32 240b:251::/32 240b:252::/32 240b:253::/32" ;;
        "ocn_v1") echo "2400:4050::/32 2400:4051::/32 2400:4052::/32 2400:4053::/32 2400:4150::/32 2400:4151::/32 2400:4152::/32 2400:4153::/32" ;;
        "ocn_v2") echo "2400:4050::/31 2400:4052::/31 2400:4150::/31 2400:4152::/31" ;;
        "transix_ipv4_provider_fix") echo "240e:10::/32 240e:11::/32 240e:12::/32 240e:13::/32 240e:80::/32 240e:81::/32 240e:82::/32 240e:83::/32 240e:2f0::/32 240e:2f1::/32 240e:2f2::/32 240e:2f3::/32 240e:300::/32 240e:301::/32 240e:302::/32 240e:303::/32 240e:400::/32 240e:401::/32 240e:402::/32 240e:403::/32" ;;
        "transix_ipv4_provider_var") echo "240e:10::/32 240e:11::/32 240e:12::/32 240e:13::/32 240e:80::/32 240e:81::/32 240e:82::/32 240e:83::/32 240e:2f0::/32 240e:2f1::/32 240e:2f2::/32 240e:2f3::/32 240e:300::/32 240e:301::/32 240e:302::/32 240e:303::/32 240e:400::/32 240e:401::/32 240e:402::/32 240e:403::/32" ;;
        "transix_dsbn_fix") echo "2404:7a80::/32" ;;
        "iijmio_fiberaccess_f") echo "2400:2650::/32 2400:2651::/32 2400:2652::/32 2400:2653::/32" ;;
        "v6connect_fixed_ip") echo "240d:1a::/32 240d:1b::/32 240d:1c::/32 240d:1d::/32" ;;
        "v6connect_dynamic_ip") echo "240d:1a::/32 240d:1b::/32 240d:1c::/32 240d:1d::/32" ;;
        "cross_pass") echo "2409:10::/32 2409:11::/32 2409:12::/32 2409:13::/32 2409:250::/32 2409:251::/32 2409:252::/32 2409:253::/32" ;;
        "v6option") echo "2403:8940::/31" ;;
        "ocn_for_docomo_net") echo "2400:4030::/31" ;;
        *) echo "" ;;
    esac
}

get_rule_br() {
    local rule_id="$1"
    case "$rule_id" in
        "v6plus_jpne") echo "240b:10:a0e0::1" ;; # Note: Multiple BRs exist, map-e.js uses this one. Consider logic if specific BR matching is needed.
        "ocn_v1") echo "2404:9200:225:100::64" ;;
        "ocn_v2") echo "2404:9200:225:100::64" ;;
        "transix_ipv4_provider_fix") echo "240e:fffd::1" ;;
        "transix_ipv4_provider_var") echo "240e:fffd::1" ;;
        "transix_dsbn_fix") echo "2404:7a80:fffd::1" ;;
        "iijmio_fiberaccess_f") echo "2400:2600:10a::1" ;;
        "v6connect_fixed_ip") echo "240d:1a:fffd::1" ;;
        "v6connect_dynamic_ip") echo "240d:1a:fffd::1" ;;
        "cross_pass") echo "2409:10:a0e0::1" ;; # Note: Multiple BRs exist, map-e.js uses this one.
        "v6option") echo "2403:8940:ffff::1" ;;
        "ocn_for_docomo_net") echo "2404:9200:225:100::64" ;;
        *) echo "" ;;
    esac
}

get_rule_ip6prefixlen() {
    local rule_id="$1"
    case "$rule_id" in
        "v6plus_jpne") echo "32" ;;
        "ocn_v1") echo "32" ;;
        "ocn_v2") echo "48" ;; # Note: map-e.js uses 48 for calculation despite /31 range
        "transix_ipv4_provider_fix") echo "32" ;;
        "transix_ipv4_provider_var") echo "48" ;; # Note: map-e.js uses 48 for calculation despite /32 range
        "transix_dsbn_fix") echo "48" ;; # Note: map-e.js uses 48 for calculation despite /32 range
        "iijmio_fiberaccess_f") echo "32" ;;
        "v6connect_fixed_ip") echo "48" ;; # Note: map-e.js uses 48 for calculation despite /32 range
        "v6connect_dynamic_ip") echo "48" ;; # Note: map-e.js uses 48 for calculation despite /32 range
        "cross_pass") echo "32" ;;
        "v6option") echo "48" ;; # Note: map-e.js uses 48 for calculation despite /31 range
        "ocn_for_docomo_net") echo "48" ;; # Note: map-e.js uses 48 for calculation despite /31 range
        *) echo "" ;;
    esac
}

get_rule_ip4prefixlen() {
    local rule_id="$1"
    case "$rule_id" in
        "v6plus_jpne") echo "21" ;;
        "ocn_v1") echo "20" ;;
        "ocn_v2") echo "20" ;;
        "transix_ipv4_provider_fix") echo "24" ;;
        "transix_ipv4_provider_var") echo "24" ;;
        "transix_dsbn_fix") echo "24" ;;
        "iijmio_fiberaccess_f") echo "23" ;;
        "v6connect_fixed_ip") echo "24" ;;
        "v6connect_dynamic_ip") echo "24" ;;
        "cross_pass") echo "21" ;;
        "v6option") echo "24" ;;
        "ocn_for_docomo_net") echo "20" ;;
        *) echo "" ;;
    esac
}

get_rule_psidlen() {
    local rule_id="$1"
    case "$rule_id" in
        "v6plus_jpne") echo "8" ;;
        "ocn_v1") echo "6" ;;
        "ocn_v2") echo "6" ;;
        "transix_ipv4_provider_fix") echo "0" ;;
        "transix_ipv4_provider_var") echo "12" ;;
        "transix_dsbn_fix") echo "0" ;;
        "iijmio_fiberaccess_f") echo "8" ;;
        "v6connect_fixed_ip") echo "0" ;;
        "v6connect_dynamic_ip") echo "12" ;;
        "cross_pass") echo "8" ;;
        "v6option") echo "12" ;;
        "ocn_for_docomo_net") echo "6" ;;
        *) echo "" ;;
    esac
}

get_rule_offset() {
    local rule_id="$1"
    case "$rule_id" in
        "v6plus_jpne") echo "4" ;;
        "ocn_v1") echo "6" ;;
        "ocn_v2") echo "6" ;;
        "transix_ipv4_provider_fix") echo "0" ;;
        "transix_ipv4_provider_var") echo "6" ;;
        "transix_dsbn_fix") echo "0" ;;
        "iijmio_fiberaccess_f") echo "7" ;;
        "v6connect_fixed_ip") echo "0" ;;
        "v6connect_dynamic_ip") echo "6" ;;
        "cross_pass") echo "4" ;;
        "v6option") echo "6" ;;
        "ocn_for_docomo_net") echo "6" ;;
        *) echo "" ;;
    esac
}

get_rule_rfc() {
    local rule_id="$1"
    case "$rule_id" in
        "v6plus_jpne") echo "false" ;;
        "ocn_v1") echo "false" ;;
        "ocn_v2") echo "false" ;;
        "transix_ipv4_provider_fix") echo "true" ;;
        "transix_ipv4_provider_var") echo "true" ;;
        "transix_dsbn_fix") echo "true" ;;
        "iijmio_fiberaccess_f") echo "false" ;;
        "v6connect_fixed_ip") echo "true" ;;
        "v6connect_dynamic_ip") echo "true" ;;
        "cross_pass") echo "false" ;;
        "v6option") echo "true" ;;
        "ocn_for_docomo_net") echo "false" ;;
        *) echo "false" ;; # Default to false
    esac
}

# --- End of Rule Definition Functions ---

# --- Start of Fixed IPv4 Mapping Helper Function ---

# Checks if the given IPv6 prefix matches any fixed mapping rules (ruleprefixXX from map-e.js).
# Usage: get_fixed_ipv4_mapping <user_ipv6_dec_segments>
# Returns: The mapped IPv4 address string if a match is found, otherwise empty string.
# Note: This function assumes extract_ipv6_bits is available and works correctly.
get_fixed_ipv4_mapping() {
    local user_ip6_dec="$1"
    local prefix31_val prefix38_val
    local mapped_ipv4=""

    # --- 1. Extract Prefix Bits ---
    # Extract first 31 bits
    prefix31_val=$(extract_ipv6_bits 0 31 "$user_ip6_dec")
    if [ $? -ne 0 ]; then
        log_msg E "get_fixed_ipv4_mapping: Failed to extract first 31 bits."
        # Decide if we should proceed to 38-bit check or return error
        # Let's try 38-bit check for now.
    fi

    # Extract first 38 bits
    prefix38_val=$(extract_ipv6_bits 0 38 "$user_ip6_dec")
     if [ $? -ne 0 ]; then
        log_msg E "get_fixed_ipv4_mapping: Failed to extract first 38 bits."
        # If both extractions fail, return empty
        if [ -z "$prefix31_val" ]; then
             echo ""
             return 1
        fi
    fi

    log_msg D "get_fixed_ipv4_mapping: Extracted prefix values - 31bit=$prefix31_val, 38bit=$prefix38_val"

    # --- 2. Check ruleprefix31 ---
    # Keys are decimal representations of the first 31 bits (hex values from map-e.js converted)
    # 0x240b0010 -> 604700688
    # 0x240b0012 -> 604700690
    # 0x240b0250 -> 604701264
    # 0x240b0252 -> 604701266
    # 0x24047a80 -> 604257920
    # 0x24047a84 -> 604257924
    if [ -n "$prefix31_val" ]; then
        case "$prefix31_val" in
            "604700688") mapped_ipv4="106.72.x.x" ;; # Special format, needs handling later
            "604700690") mapped_ipv4="14.8.x.x" ;;   # Special format
            "604701264") mapped_ipv4="14.10.x.x" ;;  # Special format
            "604701266") mapped_ipv4="14.12.x.x" ;;  # Special format
            "604257920") mapped_ipv4="133.200.x.x" ;; # Special format
            "604257924") mapped_ipv4="133.206.x.x" ;; # Special format
        esac
    fi

    # If ruleprefix31 matched, return the partial IPv4. The caller needs to complete it.
    # map-e.js logic seems to overwrite with ruleprefix38 if both match. Let's follow that.
    # So, we don't return here, just potentially set mapped_ipv4.

    # --- 3. Check ruleprefix38 and ruleprefix38_20 ---
    # Keys are decimal representations of the first 38 bits
    # 0x24047a8200 -> 154688721920
    # 0x24047a8204 -> 154688721924
    # ... (Need to convert all keys)
    # Note: 38-bit numbers likely exceed standard 32-bit integer limits in ash.
    # extract_ipv6_bits might return large numbers as strings or handle them inconsistently.
    # Comparison using standard shell arithmetic might fail.
    # Workaround: Use string comparison if extract_ipv6_bits returns consistent strings for large numbers.
    # Or, if extract_ipv6_bits handles large numbers correctly, direct comparison might work on some ash versions.
    # Let's try direct numeric comparison first, assuming extract_ipv6_bits works.

    if [ -n "$prefix38_val" ]; then
        # Convert hex keys from map-e.js to decimal for comparison
        # Example: 0x24047a8200 -> 154688721920
        # Example: 0x24047a8204 -> 154688721924
        # Example: 0x24047a8218 -> 154688721944
        # Example: 0x24047a821c -> 154688721948
        # Example: 0x24047a8220 -> 154688721952 (ruleprefix38_20 start)
        # Example: 0x24047a8224 -> 154688721956
        # Example: 0x24047a8228 -> 154688721960
        # Example: 0x24047a822c -> 154688721964
        # Example: 0x24047a8230 -> 154688721968
        # Example: 0x24047a8234 -> 154688721972
        # Example: 0x24047a8238 -> 154688721976
        # Example: 0x24047a823c -> 154688721980

        # Note: These large decimal values MUST be handled correctly by the shell's arithmetic.
        # Using string comparison might be safer if arithmetic is limited.
        # Let's use case with string comparison for robustness.
        case "$prefix38_val" in
            # ruleprefix38
            "154688721920") mapped_ipv4="125.196.208.$(extract_ipv6_bits 48 8 "$user_ip6_dec")" ;; # Combine with bits 48-55
            "154688721924") mapped_ipv4="125.196.212.$(extract_ipv6_bits 48 8 "$user_ip6_dec")" ;;
            "154688721928") mapped_ipv4="125.198.140.$(extract_ipv6_bits 48 8 "$user_ip6_dec")" ;; # 0x...a8208
            "154688721932") mapped_ipv4="125.198.144.$(extract_ipv6_bits 48 8 "$user_ip6_dec")" ;; # 0x...a820c
            "154688721936") mapped_ipv4="125.198.212.$(extract_ipv6_bits 48 8 "$user_ip6_dec")" ;; # 0x...a8210
            "154688721940") mapped_ipv4="125.198.244.$(extract_ipv6_bits 48 8 "$user_ip6_dec")" ;; # 0x...a8214
            "154688721944") mapped_ipv4="122.131.104.$(extract_ipv6_bits 48 8 "$user_ip6_dec")" ;; # 0x...a8218
            "154688721948") mapped_ipv4="122.131.108.$(extract_ipv6_bits 48 8 "$user_ip6_dec")" ;; # 0x...a821c
            # ruleprefix38_20
            "154688721952") mapped_ipv4="125.196.209.$(extract_ipv6_bits 48 8 "$user_ip6_dec")" ;; # 0x...a8220
            "154688721956") mapped_ipv4="125.196.213.$(extract_ipv6_bits 48 8 "$user_ip6_dec")" ;; # 0x...a8224
            "154688721960") mapped_ipv4="125.198.141.$(extract_ipv6_bits 48 8 "$user_ip6_dec")" ;; # 0x...a8228
            "154688721964") mapped_ipv4="125.198.145.$(extract_ipv6_bits 48 8 "$user_ip6_dec")" ;; # 0x...a822c
            "154688721968") mapped_ipv4="125.198.213.$(extract_ipv6_bits 48 8 "$user_ip6_dec")" ;; # 0x...a8230
            "154688721972") mapped_ipv4="125.198.245.$(extract_ipv6_bits 48 8 "$user_ip6_dec")" ;; # 0x...a8234
            "154688721976") mapped_ipv4="122.131.105.$(extract_ipv6_bits 48 8 "$user_ip6_dec")" ;; # 0x...a8238
            "154688721980") mapped_ipv4="122.131.109.$(extract_ipv6_bits 48 8 "$user_ip6_dec")" ;; # 0x...a823c
        esac
    fi

    # --- 4. Handle ruleprefix31 special format ---
    # If ruleprefix38 didn't match but ruleprefix31 did, complete the IPv4
    if [ -z "$mapped_ipv4" ] && echo "$prefix31_val" | grep -qE '^(604700688|604700690|604701264|604701266|604257920|604257924)$'; then
         log_msg D "get_fixed_ipv4_mapping: ruleprefix31 matched, completing IPv4."
         local octet3 octet4
         # map-e.js uses bits 32-39 for octet3 and 40-47 for octet4
         octet3=$(extract_ipv6_bits 32 8 "$user_ip6_dec")
         octet4=$(extract_ipv6_bits 40 8 "$user_ip6_dec")
          if [ $? -ne 0 ] || [ -z "$octet3" ] || [ -z "$octet4" ]; then
              log_msg E "get_fixed_ipv4_mapping: Failed to extract octet 3/4 for ruleprefix31 completion."
              echo "" # Return empty on error
              return 1
          fi

         # Reconstruct mapped_ipv4 based on the initial match
         case "$prefix31_val" in
            "604700688") mapped_ipv4="106.72.$octet3.$octet4" ;;
            "604700690") mapped_ipv4="14.8.$octet3.$octet4" ;;
            "604701264") mapped_ipv4="14.10.$octet3.$octet4" ;;
            "604701266") mapped_ipv4="14.12.$octet3.$octet4" ;;
            "604257920") mapped_ipv4="133.200.$octet3.$octet4" ;;
            "604257924") mapped_ipv4="133.206.$octet3.$octet4" ;;
         esac
    elif echo "$mapped_ipv4" | grep -q '\.x\.x$'; then
         # This case should not be reached if ruleprefix38 check is done correctly after ruleprefix31
         log_msg W "get_fixed_ipv4_mapping: Partial IPv4 from ruleprefix31 was not overridden or completed."
         mapped_ipv4="" # Reset if it's still partial
    fi


    # --- 5. Return result ---
    if [ -n "$mapped_ipv4" ]; then
        log_msg I "get_fixed_ipv4_mapping: Found fixed mapping: $mapped_ipv4"
        echo "$mapped_ipv4"
        return 0
    else
        log_msg D "get_fixed_ipv4_mapping: No fixed mapping rule matched."
        echo ""
        return 1 # Indicate no match found (using return code)
    fi
}

# --- End of Fixed IPv4 Mapping Helper Function ---

# --- Start of IPv6 Helper Functions ---

calculate_ipv6_bitmask() {
    local num_bits="$1"
    local mask=0
    if [ "$num_bits" -le 0 ]; then
        echo 0
    elif [ "$num_bits" -ge 16 ]; then
        echo 65535 # 0xFFFF
    else
        mask=$(( 0xFFFF >> (16 - num_bits) ))
        mask=$(( mask << (16 - num_bits) ))
        mask=$(( mask & 0xFFFF ))
        echo "$mask"
    fi
}

normalize_ipv6() {
    local ip="$1"
    local expanded_ip=""
    local num_segments=$(echo "$ip" | awk -F':' '{print NF}')
    local num_colons=$((num_segments - 1))

    if echo "$ip" | grep -q '::'; then
        local segments_to_add=$((8 - num_segments + 1))
        local zero_block=""
        local i=0
        while [ $i -lt $segments_to_add ]; do
            if [ $i -eq 0 ]; then
                zero_block="0000"
            else
                zero_block="${zero_block}:0000"
            fi
            i=$((i + 1))
        done
        case "$ip" in
            "::"*) ip=$(echo "$ip" | sed "s/::/$zero_block/") ;;
            *"::") ip=$(echo "$ip" | sed "s/::/:$zero_block/") ;;
            *) ip=$(echo "$ip" | sed "s/::/:$zero_block:/") ;;
        esac
        num_segments=$(echo "$ip" | awk -F':' '{print NF}')
    fi

    local old_ifs="$IFS"
    IFS=':'
    set -- $ip
    num_segments=$#
    local current_segment=1
    expanded_ip=""
    while [ $current_segment -le 8 ]; do
        local segment_val="0000"
        if [ $current_segment -le $num_segments ] && [ -n "$1" ]; then
             local current_seg_val="$1"
             local padded_seg=$(printf "%04s" "$current_seg_val" | awk '{gsub(/ /,"0"); print}')
             segment_val="$padded_seg"
        fi

        if [ $current_segment -lt 8 ]; then
             expanded_ip="${expanded_ip}${segment_val}:"
        else
             expanded_ip="${expanded_ip}${segment_val}"
        fi

        if [ $current_segment -le $num_segments ]; then
            shift
        fi
        current_segment=$((current_segment + 1))
    done
    IFS="$old_ifs"

    echo "$expanded_ip"
}

ipv6_to_dec_segments() {
    local norm_ip="$1"
    local dec_segments=""
    local old_ifs="$IFS"
    IFS=':'
    set -- $norm_ip
    while [ $# -gt 0 ]; do
        local dec_val=$(printf "%d" "0x$1")
        dec_segments="${dec_segments}${dec_val} "
        shift
    done
    IFS="$old_ifs"
    echo "${dec_segments% }"
}

dec_segments_to_ipv6() {
    local dec_segments="$1"
    local norm_ip=""
    local old_ifs="$IFS"
    IFS=' '
    set -- $dec_segments
    local count=0
    while [ $# -gt 0 ] && [ $count -lt 8 ]; do
        # Handle potential empty arguments if input string has multiple spaces
        if [ -z "$1" ]; then
            shift
            continue
        fi
        local hex_val=$(printf "%04x" "$1")
        norm_ip="${norm_ip}${hex_val}"
        count=$((count + 1))
        if [ $count -lt 8 ]; then
            norm_ip="${norm_ip}:"
        fi
        shift
    done
    IFS="$old_ifs"
    echo "$norm_ip"
}


ipv6_cidr_match() {
    local ip1_raw="$1"
    local ip2_raw="$2"
    local prefix_len="$3"
    local ip1_norm ip2_norm
    local ip1_dec ip2_dec
    local seg1 seg2
    local full_segments=$((prefix_len / 16))
    local remaining_bits=$((prefix_len % 16))
    local i=1
    local match="true"

    if [ -z "$ip1_raw" ] || [ -z "$ip2_raw" ] || [ -z "$prefix_len" ] || [ "$prefix_len" -lt 0 ] || [ "$prefix_len" -gt 128 ]; then
        echo "false"
        return 1
    fi

    ip1_norm=$(normalize_ipv6 "$ip1_raw")
    ip2_norm=$(normalize_ipv6 "$ip2_raw")
    ip1_dec=$(ipv6_to_dec_segments "$ip1_norm")
    ip2_dec=$(ipv6_to_dec_segments "$ip2_norm")

    while [ $i -le $full_segments ]; do
        seg1=$(echo "$ip1_dec" | cut -d' ' -f$i)
        seg2=$(echo "$ip2_dec" | cut -d' ' -f$i)
        if [ "$seg1" -ne "$seg2" ]; then
            match="false"
            break
        fi
        i=$((i + 1))
    done

    if [ "$match" = "true" ] && [ $remaining_bits -gt 0 ]; then
        # Check if segment index $i exists before accessing
        seg1=$(echo "$ip1_dec" | cut -d' ' -f$i 2>/dev/null)
        seg2=$(echo "$ip2_dec" | cut -d' ' -f$i 2>/dev/null)
        if [ -z "$seg1" ] || [ -z "$seg2" ]; then # Should not happen with normalized IPs
             match="false"
        else
            local mask=$(calculate_ipv6_bitmask "$remaining_bits")
            if [ $((seg1 & mask)) -ne $((seg2 & mask)) ]; then
                match="false"
            fi
        fi
    fi

    echo "$match"
}

extract_ipv6_bits() {
    local start_bit="$1"
    local length="$2"
    local dec_segments="$3"
    local end_bit=$((start_bit + length))
    local value=0
    local bits_in_segment=16

    log_msg D "extract_ipv6_bits: Called with start_bit=$start_bit, length=$length, dec_segments='$dec_segments'"

    if [ "$start_bit" -lt 0 ] || [ "$length" -le 0 ] || [ "$end_bit" -gt 128 ]; then
        log_msg E "extract_ipv6_bits: Invalid bit range (start=$start_bit, length=$length, end=$end_bit > 128)"
        echo "" # Return empty string on error
        return 1
    fi

    # Use multiplication for combining results to potentially avoid shift limits
    local use_multiplication_combine=1
    if [ "$length" -gt 32 ]; then
        # BusyBox ash (used in OpenWrt) generally supports 64-bit integers if compiled with them.
        # However, excessive bit shifts can still be problematic or slow.
        # Multiplication is often safer for combining large bit parts.
        log_msg D "extract_ipv6_bits: Extracting more than 32 bits ($length). Using multiplication combine method."
    fi

    local start_seg_idx=$((start_bit / bits_in_segment))
    local end_seg_idx=$(( (end_bit - 1) / bits_in_segment ))

    local current_pos=$start_bit
    local bits_remaining_to_extract=$length

    local i=$start_seg_idx
    while [ $i -le $end_seg_idx ] && [ $bits_remaining_to_extract -gt 0 ]; do
        # Extract the i-th segment (0-indexed internally, 1-indexed for cut)
        local segment_val=$(echo "$dec_segments" | cut -d' ' -f $((i + 1)) 2>/dev/null)

        # Validate segment value
        if [ -z "$segment_val" ] || ! expr "$segment_val" + 0 > /dev/null 2>&1; then
            log_msg E "extract_ipv6_bits: Error accessing or invalid segment value at index $((i + 1)). Segment: '$segment_val'"
            echo "" # Return empty string on error
            return 1
        fi
        log_msg D "extract_ipv6_bits: Loop i=$i, segment_val=$segment_val, bits_remaining=$bits_remaining_to_extract"

        local bit_offset_in_seg=$((current_pos % bits_in_segment))
        local bits_to_extract_from_seg=$((bits_in_segment - bit_offset_in_seg))
        if [ $bits_to_extract_from_seg -gt $bits_remaining_to_extract ]; then
            bits_to_extract_from_seg=$bits_remaining_to_extract
        fi
        log_msg D "extract_ipv6_bits: Loop i=$i, bit_offset_in_seg=$bit_offset_in_seg, bits_to_extract_from_seg=$bits_to_extract_from_seg"

        # Calculate the right shift amount
        # Example: 16 bits total, offset 4, extract 8 => shift right by (16 - 4 - 8) = 4
        local shift_right=$((bits_in_segment - bit_offset_in_seg - bits_to_extract_from_seg))
        if [ "$shift_right" -lt 0 ]; then
             # This should not happen with correct logic, but check for safety
             log_msg E "extract_ipv6_bits: Internal error - negative shift_right ($shift_right)"
             echo ""
             return 1
        fi
        local extracted_part=$((segment_val >> shift_right))
        log_msg D "extract_ipv6_bits: Loop i=$i, shift_right=$shift_right, pre_mask_extracted_part=$extracted_part"

        # Create a mask for the bits we want to keep
        # Example: bits_to_extract_from_seg = 8 => mask = (1 << 8) - 1 = 255
        local mask=$(( (1 << bits_to_extract_from_seg) - 1 ))
        # Handle edge cases for mask calculation with large shifts
        if [ "$bits_to_extract_from_seg" -eq 16 ]; then mask=65535; # 0xFFFF
        elif [ "$bits_to_extract_from_seg" -le 0 ]; then mask=0;
        elif [ "$bits_to_extract_from_seg" -ge 31 ]; then
             # For 31 bits or more, standard shift might overflow. Calculate differently.
             # Create a full mask by calculation or known value if needed.
             # For simplicity, assume 64-bit support allows large shifts for now.
             # If issues arise, refine mask calculation for >31 bits.
             mask=$(( ( (1 << ($bits_to_extract_from_seg - 1)) - 1 ) * 2 + 1 )) # Safer way for large numbers potentially
             log_msg D "extract_ipv6_bits: Calculated large mask for $bits_to_extract_from_seg bits: $mask"
        fi
        extracted_part=$((extracted_part & mask))
        log_msg D "extract_ipv6_bits: Loop i=$i, mask=$mask, final_extracted_part=$extracted_part"

        # Combine the extracted part with the current value
        if [ "$use_multiplication_combine" -eq 1 ]; then
            # Calculate multiplier: 2 ^ bits_to_extract_from_seg
            local multiplier=1
            local j=0
            # Use a loop for multiplier calculation to avoid large shifts in the multiplier itself
            while [ $j -lt $bits_to_extract_from_seg ]; do
                multiplier=$((multiplier * 2))
                # Check for potential overflow in multiplier (though unlikely for <= 16 bits)
                 if ! expr "$multiplier" + 0 > /dev/null 2>&1; then
                      log_msg E "extract_ipv6_bits: Multiplier overflow during calculation."
                      echo ""
                      return 1
                 fi
                j=$((j + 1))
            done
            log_msg D "extract_ipv6_bits: Loop i=$i, combine_multiplier=$multiplier"
            # Combine: value = (value * multiplier) + extracted_part
            value=$(( (value * multiplier) + extracted_part ))
        else
             # Original shift approach (might hit limits sooner for large 'value'):
             value=$(( (value << bits_to_extract_from_seg) | extracted_part ))
        fi
        # Validate intermediate value
        if ! expr "$value" + 0 > /dev/null 2>&1; then
             log_msg E "extract_ipv6_bits: Intermediate value became non-numeric after combining."
             echo ""
             return 1
        fi
        log_msg D "extract_ipv6_bits: Loop i=$i, intermediate_combined_value=$value"

        bits_remaining_to_extract=$((bits_remaining_to_extract - bits_to_extract_from_seg))
        current_pos=$((current_pos + bits_to_extract_from_seg))
        i=$((i + 1))
    done

    # --- Final Validation ---
    log_msg D "extract_ipv6_bits: Final calculated value before validation: $value"
    if expr "$value" + 0 > /dev/null 2>&1; then
        log_msg D "extract_ipv6_bits: Succeeded. Returning value: $value"
        echo "$value"
        return 0
    else
        log_msg E "extract_ipv6_bits: Final calculated value '$value' is not a valid number."
        echo "" # Return empty string on error
        return 1
    fi
}

# --- End of IPv6 Helper Functions ---


# --- Start of New Helper Functions for mape_mold ---

dec_to_ipv4() {
    local dec_val="$1"
    local octet1 octet2 octet3 octet4

    octet1=$(( (dec_val >> 24) & 255 ))
    octet2=$(( (dec_val >> 16) & 255 ))
    octet3=$(( (dec_val >> 8) & 255 ))
    octet4=$(( dec_val & 255 ))

    echo "${octet1}.${octet2}.${octet3}.${octet4}"
}

apply_ipv6_mask() {
    local dec_segments="$1"
    local prefix_len="$2"
    local masked_segments=""
    local full_segments=$((prefix_len / 16))
    local remaining_bits=$((prefix_len % 16))
    local i=1
    local segment_val mask

    local old_ifs="$IFS"
    IFS=' '
    set -- $dec_segments

    while [ $i -le $full_segments ] && [ $# -gt 0 ]; do
        masked_segments="${masked_segments}$1 "
        shift
        i=$((i + 1))
    done

    if [ $remaining_bits -gt 0 ] && [ $# -gt 0 ]; then
        segment_val="$1"
        mask=$(calculate_ipv6_bitmask "$remaining_bits")
        masked_segments="${masked_segments}$((segment_val & mask)) "
        shift
        i=$((i + 1))
    fi

    while [ $i -le 8 ]; do
        masked_segments="${masked_segments}0 "
        i=$((i + 1))
    done

    IFS="$old_ifs"
    echo "${masked_segments% }"
}

shift_value_to_ipv6_position() {
    local value="$1"
    local start_bit="$2"
    local length="$3"
    local segments_array=(0 0 0 0 0 0 0 0)
    local bits_in_segment=16

    if [ "$length" -le 0 ]; then
        echo "0 0 0 0 0 0 0 0"
        return
    fi
     if [ "$length" -gt 32 ]; then
         log_msg D "shift_value_to_ipv6_position: Warning - Shifting values longer than 32 bits ($length) might have precision issues."
     fi

    local lsb_target_pos=$((start_bit + length - 1))
    local target_seg_idx=$((lsb_target_pos / bits_in_segment))
    local bit_offset_in_target_seg=$((lsb_target_pos % bits_in_segment))

    if [ "$target_seg_idx" -ge 8 ] || [ "$target_seg_idx" -lt 0 ]; then # Basic bounds check
         log_msg E "shift_value_to_ipv6_position: Calculated target segment index ($target_seg_idx) out of bounds."
         echo "0 0 0 0 0 0 0 0" # Return zero segments on error
         return 1
    fi

    local bits_in_target=$((bit_offset_in_target_seg + 1))
    if [ $bits_in_target -gt $length ]; then
        bits_in_target=$length
    fi

    local target_seg_mask=$(( (1 << bits_in_target) - 1 ))
     if [ "$bits_in_target" -eq 16 ]; then target_seg_mask=65535;
     elif [ "$bits_in_target" -le 0 ]; then target_seg_mask=0;
     elif [ "$bits_in_target" -ge 31 ]; then target_seg_mask=$(( ( (1 << ($bits_in_target - 1)) - 1 ) * 2 + 1 ));
     fi
    local target_seg_part=$((value & target_seg_mask))

    local target_shift_left=$((bit_offset_in_target_seg - bits_in_target + 1))
    # Check shift bounds
    if [ "$target_shift_left" -ge 0 ] && [ "$target_shift_left" -lt 16 ]; then
         segments_array[$target_seg_idx]=$((target_seg_part << target_shift_left))
    elif [ "$target_shift_left" -lt 0 ]; then # Handle case where bits span across segment boundary leftwards (should be handled by loop below)
         log_msg D "shift_value_to_ipv6_position: Negative target_shift_left ($target_shift_left), handled by loop."
         # The initial segment might be partially filled by the loop later.
         # Set segment to 0 initially if shift is negative.
         segments_array[$target_seg_idx]=0
    else # Shift >= 16
         log_msg E "shift_value_to_ipv6_position: Calculated target_shift_left ($target_shift_left) >= 16."
         segments_array[$target_seg_idx]=0 # Or handle error differently
    fi


    local bits_remaining=$((length - bits_in_target))
    local current_value_part=$((value >> bits_in_target))
    local current_seg_idx=$((target_seg_idx - 1))

    while [ $bits_remaining -gt 0 ] && [ $current_seg_idx -ge 0 ]; do
        local bits_to_take=$bits_in_segment
        if [ $bits_to_take -gt $bits_remaining ]; then
            bits_to_take=$bits_remaining
        fi

        local current_seg_mask=$(( (1 << bits_to_take) - 1 ))
         if [ "$bits_to_take" -eq 16 ]; then current_seg_mask=65535;
         elif [ "$bits_to_take" -le 0 ]; then current_seg_mask=0;
         elif [ "$bits_to_take" -ge 31 ]; then current_seg_mask=$(( ( (1 << ($bits_to_take - 1)) - 1 ) * 2 + 1 ));
         fi
        local current_seg_part=$((current_value_part & current_seg_mask))

        local current_shift_left=$((bits_in_segment - bits_to_take))
         # Check shift bounds
         if [ "$current_shift_left" -ge 0 ] && [ "$current_shift_left" -lt 16 ]; then
             segments_array[$current_seg_idx]=$((current_seg_part << current_shift_left))
         else
             log_msg E "shift_value_to_ipv6_position: Calculated current_shift_left ($current_shift_left) out of bounds [0-15]."
             segments_array[$current_seg_idx]=0 # Or handle error
         fi

        current_value_part=$((current_value_part >> bits_to_take))
        bits_remaining=$((bits_remaining - bits_to_take))
        current_seg_idx=$((current_seg_idx - 1))
    done

    # If bits still remain after filling all segments down to index 0, it's an error (value too large for position)
    if [ "$bits_remaining" -gt 0 ]; then
         log_msg E "shift_value_to_ipv6_position: Value too large ($length bits) to fit starting at bit $start_bit."
         # Return zero segments or handle error
         echo "0 0 0 0 0 0 0 0"
         return 1
    fi


    echo "${segments_array[*]}"
}


bitwise_or_ipv6() {
    local segments1="$1"
    local segments2="$2"
    local result_segments=""
    local i=1
    local seg1 seg2 arr1 arr2

    local old_ifs="$IFS"
    IFS=' '
    # Read segments into arrays carefully
    set -- $segments1; arr1=($@)
    set -- $segments2; arr2=($@)
    IFS="$old_ifs"

    # Pad arrays with 0 if they have less than 8 elements
    while [ ${#arr1[@]} -lt 8 ]; do arr1+=(0); done
    while [ ${#arr2[@]} -lt 8 ]; do arr2+=(0); done

    while [ $i -le 8 ]; do
        seg1=${arr1[$((i-1))]:-0} # Use :-0 default for safety
        seg2=${arr2[$((i-1))]:-0}
        result_segments="${result_segments}$((seg1 | seg2)) "
        i=$((i + 1))
    done

    echo "${result_segments% }"
}

# --- End of New Helper Functions ---


# --- Start of Revised mape_mold Function ---

# --- Start of Revised mape_mold Function (incorporating fixed mapping) ---

# --- Start of Revised mape_mold Function (incorporating fixed mapping and scope fix) ---

mape_mold() {
    local user_ip6_raw="$1"
    local norm_user_ip6=""
    local user_ip6_dec=""
    local matched_rule_id=""
    local rule_ipv6_cidrs=""
    local cidr=""
    local rule_ip6_prefix=""
    local rule_cidr_len=""
    local match_result=""
    local fixed_ipv4=""
    local fixed_mapping_found=1 # 0 if found, 1 if not found
    local rule_ip4prefixlen="" # <<< MODIFIED: Declared local variable here

    # Reset global status and variables
    MAPE_STATUS="fail"
    RULE_NAME="" IPV4="" BR="" IP6PFX="" CE_ADDR="" IP4PREFIXLEN="" IP6PREFIXLEN=""
    EALEN="" PSIDLEN="" OFFSET="" PSID="" PORTS="" RFC=""

    # --- 1. Input Validation and Normalization ---
    if [ -z "$user_ip6_raw" ]; then
        log_msg E "mape_mold: User IPv6 prefix is empty."
        return 1
    fi
    norm_user_ip6=$(normalize_ipv6 "$user_ip6_raw")
    if [ -z "$norm_user_ip6" ]; then
         log_msg E "mape_mold: Failed to normalize IPv6 prefix: $user_ip6_raw"
         return 1
    fi
    user_ip6_dec=$(ipv6_to_dec_segments "$norm_user_ip6")
    log_msg D "mape_mold: Normalized User IPv6: $norm_user_ip6 ($user_ip6_dec)"
    IP6PFX="$norm_user_ip6" # Set global

    # --- 2. Rule Matching (Find Generic Rule) ---
    log_msg D "mape_mold: Starting rule matching for generic rule..."
    local all_rule_ids=$(get_rule_ids)
    for rule_id in $all_rule_ids; do
        log_msg D "mape_mold: Checking rule: $rule_id"
        rule_ipv6_cidrs=$(get_rule_ipv6_cidrs "$rule_id")
        for cidr in $rule_ipv6_cidrs; do
            rule_ip6_prefix=$(echo "$cidr" | cut -d'/' -f1)
            rule_cidr_len=$(echo "$cidr" | cut -d'/' -f2)
            if [ -z "$rule_ip6_prefix" ] || [ -z "$rule_cidr_len" ]; then
                 log_msg E "mape_mold: Invalid CIDR format '$cidr' for rule $rule_id"
                 continue
            fi
            match_result=$(ipv6_cidr_match "$norm_user_ip6" "$rule_ip6_prefix" "$rule_cidr_len")
            if [ "$match_result" = "true" ]; then
                log_msg D "mape_mold: Match found! Generic Rule: $rule_id, CIDR: $cidr"
                matched_rule_id="$rule_id"
                break
            fi
        done
        if [ -n "$matched_rule_id" ]; then
            break
        fi
    done

    if [ -z "$matched_rule_id" ]; then
        log_msg E "mape_mold: No matching generic MAP-E rule found for $norm_user_ip6."
        # Even if no generic rule matches, a fixed mapping might still apply (though unlikely based on map-e.js structure)
        # Let's check fixed mapping anyway, but BR etc. might be missing later.
        # Consider returning error here if strict adherence to map-e.js (which finds rule first) is needed.
        # For now, proceed to check fixed mapping.
        # return 1 # Option: uncomment to return error if no generic rule found
    fi
    RULE_NAME="$matched_rule_id" # Set RULE_NAME even if empty for now

    # --- 3. Check for Fixed IPv4 Mapping ---
    log_msg D "mape_mold: Checking for fixed IPv4 mapping rules..."
    fixed_ipv4=$(get_fixed_ipv4_mapping "$user_ip6_dec")
    fixed_mapping_found=$? # 0 if found, 1 if not found

    # --- 4. Parameter Retrieval (Needed for PSID, Port, CE calc regardless of fixed IP) ---
    if [ -n "$RULE_NAME" ]; then
        log_msg D "mape_mold: Retrieving parameters for generic rule: $RULE_NAME"
        BR=$(get_rule_br "$RULE_NAME")
        IP6PREFIXLEN=$(get_rule_ip6prefixlen "$RULE_NAME")
        rule_ip4prefixlen=$(get_rule_ip4prefixlen "$RULE_NAME") # <<< MODIFIED: Removed 'local' keyword
        PSIDLEN=$(get_rule_psidlen "$RULE_NAME")
        OFFSET=$(get_rule_offset "$RULE_NAME")
        RFC=$(get_rule_rfc "$RULE_NAME")

        if [ -z "$BR" ] || [ -z "$IP6PREFIXLEN" ] || [ -z "$rule_ip4prefixlen" ] || [ -z "$PSIDLEN" ] || [ -z "$OFFSET" ] || [ -z "$RFC" ]; then
            log_msg E "mape_mold: Failed to retrieve all parameters for rule $RULE_NAME. Cannot proceed."
            return 1
        fi
        log_msg D "mape_mold: Rule Params - BR=$BR, IP6Len=$IP6PREFIXLEN, RuleIP4Len=$rule_ip4prefixlen, PSIDLen=$PSIDLEN, Offset=$OFFSET, RFC=$RFC"
    elif [ "$fixed_mapping_found" -eq 0 ]; then
         # Fixed mapping found, but no generic rule matched. This is problematic.
         # We need rule parameters (like PSIDLEN, OFFSET, RFC) for subsequent calculations.
         log_msg E "mape_mold: Fixed IPv4 mapping found, but no matching generic rule to determine other parameters (PSIDLen, Offset, RFC, etc.). Cannot proceed."
         return 1
    else
         # No generic rule and no fixed mapping found. Error already logged in step 2.
         return 1
    fi

    # --- 5. Calculate EALEN and PSID (Needed for Port, CE calc, and generic IPv4 calc) ---
    # Check if rule_ip4prefixlen is set before using it
    if [ -z "$rule_ip4prefixlen" ]; then
         log_msg E "mape_mold: Internal error - rule_ip4prefixlen is not set before EALEN calculation."
         return 1
    fi
    EALEN=$((128 - IP6PREFIXLEN - rule_ip4prefixlen))
    log_msg D "mape_mold: Calculated EALen=$EALEN"

    # Basic validation for EALEN
    if [ "$EALEN" -lt "$PSIDLEN" ] || [ "$EALEN" -lt 0 ]; then
         log_msg E "mape_mold: Invalid calculated EALEN ($EALEN) for rule $RULE_NAME (IP6Len=$IP6PREFIXLEN, RuleIP4Len=$rule_ip4prefixlen, PSIDLen=$PSIDLEN)."
         return 1
    fi

    # Calculate PSID
    if [ "$PSIDLEN" -gt 0 ]; then
        # PSID = user_ipv6[ip6prefixlen+ealen-psidlen : ip6prefixlen+ealen]
        PSID=$(extract_ipv6_bits $((IP6PREFIXLEN + EALEN - PSIDLEN)) $PSIDLEN "$user_ip6_dec")
        if [ $? -ne 0 ] || [ "$PSID" = "" ]; then # Check exit status and emptiness more robustly
             log_msg E "mape_mold: Failed to extract PSID."
             return 1
        fi
        log_msg D "mape_mold: Calculated PSID: $PSID (extracted from bit $((IP6PREFIXLEN + EALEN - PSIDLEN)) for $PSIDLEN bits)"
    else
        PSID=0
        log_msg D "mape_mold: PSID is 0 for this rule (PSIDLen=0)."
    fi

    # --- 6. Determine IPv4 Address and Prefix Length ---
    if [ "$fixed_mapping_found" -eq 0 ]; then
        # --- 6a. Fixed Mapping Found ---
        log_msg I "mape_mold: Using fixed IPv4 mapping result."
        IPV4="$fixed_ipv4"
        IP4PREFIXLEN=32 # Fixed mappings imply /32
        log_msg I "mape_mold: Set User IPv4: $IPV4/$IP4PREFIXLEN (from fixed mapping)"

    else
        # --- 6b. No Fixed Mapping - Use Generic Calculation ---
        log_msg I "mape_mold: No fixed mapping found. Using generic calculation for IPv4."
        # Calculate User's effective IPv4 prefix length for generic case
        IP4PREFIXLEN=$((32 - (EALEN - PSIDLEN)))
        log_msg D "mape_mold: Calculated UserIP4Len=$IP4PREFIXLEN for generic case"

        # Validate UserIP4Len
        if [ "$IP4PREFIXLEN" -lt 0 ] || [ "$IP4PREFIXLEN" -gt 32 ]; then
            log_msg E "mape_mold: Invalid calculated UserIP4Len ($IP4PREFIXLEN) for generic rule $RULE_NAME."
            return 1
        fi

        # Perform Generic IPv4 Calculation
        local br_norm=$(normalize_ipv6 "$BR")
        local br_dec=$(ipv6_to_dec_segments "$br_norm")

        # shared_ipv4 = br[32 : 32+rule_ip4prefixlen]
        local shared_ipv4_part_dec=$(extract_ipv6_bits 32 $rule_ip4prefixlen "$br_dec")
        if [ $? -ne 0 ] || [ "$shared_ipv4_part_dec" = "" ]; then log_msg E "mape_mold: Failed to extract shared IPv4 part from BR."; return 1; fi
        log_msg D "mape_mold: Generic - Extracted shared IPv4 part from BR: $shared_ipv4_part_dec"

        # user_ipv4_suffix = user_ipv6[ip6prefixlen : ip6prefixlen+ealen-psidlen]
        local user_ipv4_part_len=$((EALEN - PSIDLEN))
        local user_ipv4_part_dec=0
        if [ "$user_ipv4_part_len" -gt 0 ]; then
             user_ipv4_part_dec=$(extract_ipv6_bits $IP6PREFIXLEN $user_ipv4_part_len "$user_ip6_dec")
             if [ $? -ne 0 ] || [ "$user_ipv4_part_dec" = "" ]; then log_msg E "mape_mold: Failed to extract user IPv4 part from User IPv6."; return 1; fi
        fi
        log_msg D "mape_mold: Generic - Extracted user IPv4 part from User IPv6: $user_ipv4_part_dec (length $user_ipv4_part_len)"

        # Combine: (shared_ipv4 << (32-rule_ip4prefixlen)) | (user_ipv4_suffix << psidlen) | psid
        local shift1=$((32 - rule_ip4prefixlen)) # Now rule_ip4prefixlen should be accessible
        local shift2=$PSIDLEN
        local part1_shifted=0; local part2_shifted=0; local part3=$PSID

        if [ "$shift1" -ge 0 ] && [ "$shift1" -lt 32 ]; then part1_shifted=$((shared_ipv4_part_dec << shift1)); fi
        if [ "$shift2" -ge 0 ] && [ "$shift2" -lt 32 ]; then part2_shifted=$((user_ipv4_part_dec << shift2)); fi

        # Perform the OR operation carefully, ensuring variables are valid numbers
        if ! expr "$part1_shifted" + 0 > /dev/null 2>&1; then part1_shifted=0; log_msg W "mape_mold: Invalid part1_shifted for OR."; fi
        if ! expr "$part2_shifted" + 0 > /dev/null 2>&1; then part2_shifted=0; log_msg W "mape_mold: Invalid part2_shifted for OR."; fi
        if ! expr "$part3" + 0 > /dev/null 2>&1; then part3=0; log_msg W "mape_mold: Invalid part3 (PSID) for OR."; fi

        local user_ipv4_full_dec=$((part1_shifted | part2_shifted | part3))
        log_msg D "mape_mold: Generic - Combined IPv4 decimal value: $user_ipv4_full_dec ( $part1_shifted | $part2_shifted | $part3 )"

        IPV4=$(dec_to_ipv4 "$user_ipv4_full_dec")
        log_msg I "mape_mold: Calculated User IPv4: $IPV4/$IP4PREFIXLEN (generic calculation)"
    fi

    # --- 7. Calculate Port Range ---
    local port_start=0
    local port_end=0
    if [ "$PSIDLEN" -le "$OFFSET" ]; then
        port_start=1024
        port_end=65535
        log_msg D "mape_mold: Port calculation: PSIDLen ($PSIDLEN) <= Offset ($OFFSET), using ports 1024-65535"
    else
        # Check if OFFSET is valid before shifting
        if [ "$OFFSET" -lt 0 ] || [ "$OFFSET" -gt 16 ]; then
             log_msg E "mape_mold: Invalid OFFSET ($OFFSET) for port calculation."
             return 1
        fi
        # Ensure PSID is a valid number before shifting
        if ! expr "$PSID" + 0 > /dev/null 2>&1; then
             log_msg E "mape_mold: Invalid PSID value ($PSID) for port calculation."
             return 1
        fi
        local psid_shifted_right=$((PSID >> OFFSET))
        # Check if (16-OFFSET) is valid before shifting
        local port_shift=$((16 - OFFSET))
        if [ "$port_shift" -lt 0 ] || [ "$port_shift" -gt 16 ]; then
             log_msg E "mape_mold: Invalid derived port shift ($port_shift) from OFFSET ($OFFSET)."
             return 1
        fi
        local port_multiplier=$((1 << port_shift))

        port_start=$((psid_shifted_right * port_multiplier))
        port_end=$((port_start + port_multiplier - 1))

        if [ "$port_start" -lt 1024 ]; then port_start=1024; fi
        if [ "$port_end" -gt 65535 ]; then port_end=65535; fi
        if [ "$port_start" -gt "$port_end" ]; then
             log_msg E "mape_mold: Invalid port range calculated (start $port_start > end $port_end). Setting empty."
             port_start=0; port_end=0; PORTS=""
        fi
        log_msg D "mape_mold: Port calculation: PSID=$PSID, Offset=$OFFSET -> Multiplier=$port_multiplier -> Clamped Range $port_start-$port_end"
    fi
    if [ "$port_start" -le "$port_end" ] && [ "$port_end" -gt 0 ]; then
         PORTS="${port_start}-${port_end}"
    else
         PORTS=""
         log_msg W "mape_mold: Resulting port range is invalid or empty."
         # Consider if an empty port range should be a fatal error
         # return 1 # Option: uncomment if empty ports are fatal
    fi
    log_msg I "mape_mold: Calculated Port Range: $PORTS"


    # --- 8. Calculate CE Address ---
    if [ "$RFC" = "true" ]; then
        CE_ADDR="$norm_user_ip6"
        log_msg D "mape_mold: CE Address (RFC=true): $CE_ADDR"
    else
        log_msg D "mape_mold: Calculating non-RFC CE Address (NetworkPrefix:PSID::1)..."
        local net_dec=$(apply_ipv6_mask "$user_ip6_dec" "$IP6PREFIXLEN")
        if [ $? -ne 0 ] || [ "$net_dec" = "" ]; then log_msg E "mape_mold: Failed to apply mask for CE Address."; return 1; fi
        log_msg D "mape_mold: CE Addr - Network part (dec): $net_dec"

        local psid_shifted_dec="0 0 0 0 0 0 0 0" # Default if PSIDLen is 0
        if [ "$PSIDLEN" -gt 0 ]; then
             psid_shifted_dec=$(shift_value_to_ipv6_position "$PSID" "$IP6PREFIXLEN" "$PSIDLEN")
             if [ $? -ne 0 ] || [ "$psid_shifted_dec" = "" ]; then log_msg E "mape_mold: Failed to shift PSID for CE Address."; return 1; fi
        fi
        log_msg D "mape_mold: CE Addr - Shifted PSID part (dec): $psid_shifted_dec"

        local suffix_1_dec="0 0 0 0 0 0 0 1"

        local ce_base_dec=$(bitwise_or_ipv6 "$net_dec" "$psid_shifted_dec")
        if [ $? -ne 0 ] || [ "$ce_base_dec" = "" ]; then log_msg E "mape_mold: Failed to OR Network and PSID for CE Address."; return 1; fi

        local ce_final_dec=$(bitwise_or_ipv6 "$ce_base_dec" "$suffix_1_dec")
         if [ $? -ne 0 ] || [ "$ce_final_dec" = "" ]; then log_msg E "mape_mold: Failed to OR Suffix ::1 for CE Address."; return 1; fi
        log_msg D "mape_mold: CE Addr - Final segments with ::1 (dec): $ce_final_dec"

        CE_ADDR=$(dec_segments_to_ipv6 "$ce_final_dec")
        log_msg D "mape_mold: CE Address (RFC=false): $CE_ADDR"
    fi
    log_msg I "mape_mold: Calculated CE IPv6 Address: $CE_ADDR"

    # --- 9. Final Status ---
    # Ensure all essential results are non-empty
    if [ -n "$RULE_NAME" ] && \
       [ -n "$IPV4" ] && \
       [ -n "$IP4PREFIXLEN" ] && \
       [ -n "$CE_ADDR" ] && \
       [ -n "$BR" ] && \
       [ -n "$PORTS" ]; then # Check PORTS is not empty
        MAPE_STATUS="success"
        log_msg I "mape_mold: MAP-E calculation successful for rule $RULE_NAME."
        return 0
    else
        log_msg E "mape_mold: Failed to calculate all required MAP-E parameters (check logs for empty values)."
        MAPE_STATUS="fail"
        # Explicitly clear globals on failure
        RULE_NAME="" IPV4="" BR="" IP6PFX="" CE_ADDR="" IP4PREFIXLEN="" IP6PREFIXLEN="" EALEN="" PSIDLEN="" OFFSET="" PSID="" PORTS="" RFC=""
        return 1
    fi
}

# --- End of Revised mape_mold Function ---


# --- Placeholder for User Functions ---
# These functions need to be implemented or adapted based on the original script's logic.

# Displays the calculated MAP-E parameters.
# Uses global variables set by mape_mold.
mape_display() {
    log_msg I "--- MAP-E Parameters ---"
    if [ "$MAPE_STATUS" = "success" ]; then
        echo "Status: $MAPE_STATUS"
        echo "Rule Name: $RULE_NAME"
        echo "User IPv6 Prefix: $IP6PFX"
        echo "Border Relay (BR): $BR"
        echo "Shared IPv4: $IPV4 / $IP4PREFIXLEN"
        echo "CE IPv6 Address: $CE_ADDR"
        echo "Port Range: $PORTS"
        echo "EA Length: $EALEN bits"
        echo "PSID Length: $PSIDLEN bits"
        echo "Offset (a-bits): $OFFSET bits"
        echo "PSID Value: $PSID"
        echo "RFC Compliant: $RFC"
    else
        echo "Status: $MAPE_STATUS"
        echo "Calculation failed. Check logs for details."
    fi
    log_msg I "------------------------"
}

# Configures the system (e.g., using UCI) with the calculated MAP-E parameters.
# Uses global variables set by mape_mold.
# !!! This function requires specific implementation based on OpenWrt UCI commands !!!
mape_config() {
    log_msg I "Applying MAP-E configuration (Placeholder)..."
    if [ "$MAPE_STATUS" != "success" ]; then
        log_msg E "mape_config: Cannot configure, calculation was not successful."
        return 1
    fi

    # Example UCI commands (adjust path/options as needed):
    # uci set network.wan6.map_ipv4addr="$IPV4"
    # uci set network.wan6.map_ipv6prefix="$CE_ADDR/64" # Assuming /64 for CE, adjust if needed
    # uci set network.wan6.map_peeraddr="$BR"
    # uci set network.wan6.map_psid="$PSID"
    # uci set network.wan6.map_psid_offset="$OFFSET" # Check if UCI uses offset or length directly
    # uci set network.wan6.map_rule_ipv6prefixlen="$IP6PREFIXLEN" # Custom? Or derived?
    # uci set network.wan6.map_rule_ipv4prefixlen="$rule_ip4prefixlen" # Need rule_ip4prefixlen here
    # uci set network.wan6.map_ealen="$EALEN" # Custom? Or derived?
    # uci commit network
    # /etc/init.d/network reload

    log_msg I "mape_config: Placeholder - UCI commands would go here."
    log_msg I "mape_config: Rule=$RULE_NAME, IPv4=$IPV4/$IP4PREFIXLEN, BR=$BR, CE=$CE_ADDR, Ports=$PORTS, PSID=$PSID"

    # Add actual UCI commands here based on your OpenWrt map-e package configuration

    log_msg I "Configuration applied (Placeholder)."
    return 0
}

# --- End of Placeholder User Functions ---


# --- Main Execution Logic ---

main() {
    if [ $# -eq 0 ]; then
        echo "Usage: $0 <user_ipv6_prefix>"
        echo "Example: $0 240b:10:a0e0:1234::1"
        exit 1
    fi

    local user_prefix="$1"

    log_msg I "Starting MAP-E calculation for prefix: $user_prefix"

    # Run the calculation
    mape_mold "$user_prefix"
    local result=$?

    # Display results
    mape_display

    # Apply configuration if successful
    if [ "$result" -eq 0 ]; then
        mape_config
    else
        log_msg E "MAP-E calculation failed. Configuration not applied."
        exit 1
    fi

    log_msg I "MAP-E script finished."
    exit 0
}

# Call main function with script arguments
main "$@"
