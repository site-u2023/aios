#!/bin/ash
# internet-map-e.sh - MAP-E parameter calculation script (fc2 compatible logic)
# Copyright (C) 2025 site-u2023 <your_email>
# License: CC0 (Public Domain)

SCRIPT_VERSION="2025.04.20-13-50" # Updated version reflecting OpenWrt integration

# =========================================================
# 📌 OpenWrt / Alpine Linux POSIX-Compliant Shell Script
# 🚀 Last Update: 2025-04-20
#
# 🏷️ License: CC0 (Public Domain)
# 🎯 Compatibility: OpenWrt >= 19.07 (Tested on 24.10.0)
#
# ⚠️ IMPORTANT NOTICE:
# OpenWrt OS exclusively uses **Almquist Shell (ash)** and
# is **NOT** compatible with Bourne-Again Shell (bash).
#
# 📢 POSIX Compliance Guidelines:
# ✅ Use `[` instead of `[[` for conditions
# ✅ Use $(command) instead of backticks `command`
# ✅ Use $(( )) for arithmetic instead of let
# ✅ Define functions as func_name() {} (no function keyword)
# ✅ No associative arrays (declare -A is NOT supported)
# ✅ No here-strings (<<< is NOT supported)
# ✅ No -v flag in test or [[
# ✅ Avoid bash-specific string operations like ${var:0:3}
# ✅ Avoid arrays entirely when possible (even indexed arrays can be problematic)
# ✅ Use printf followed by read instead of read -p
# ✅ Use printf instead of echo -e for portable formatting
# ✅ Avoid process substitution <() and >()
# ✅ Prefer case statements over complex if/elif chains
# ✅ Use command -v instead of which or type for command existence checks
# ✅ Keep scripts modular with small, focused functions
# ✅ Use simple error handling instead of complex traps
# ✅ Test scripts with ash/dash explicitly, not just bash
#
# 🛠️ Keep it simple, POSIX-compliant, and lightweight for OpenWrt!
### =========================================================
### 📌 AI Assistance Request: POSIX-Compliant Debugging Guide
###
### When debugging or fixing errors in this POSIX shell script:
###
### 1️⃣ Create a minimal reproducible test case (avoid bash features)
### 2️⃣ Test with ash/dash explicitly: dash ./test.sh
### 3️⃣ Use portable debugging methods: echo, printf, or set -x
### 4️⃣ Validate fixes against all POSIX compliance guidelines
### 5️⃣ Ensure the solution works in resource-constrained OpenWrt
###
### ⚠️ IMPORTANT:
### - Avoid suggesting bash-specific solutions
### - Always test fixes with ash/dash before implementation
### - Prefer simple solutions over complex ones
### - Do not modify production code without test verification
###
### 🛠️ Keep debugging simple, focused, and POSIX-compliant!
### =========================================================

# --- Configuration ---
SCRIPT_NAME=$(basename "$0")
DEBUG_LEVEL="${DEBUG_LEVEL:-INFO}" # DEBUG, INFO, WARN, ERROR
BASE_DIR="/tmp/aios" # Use the same base directory as aios for consistency
LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"

# --- Create Directories ---
mkdir -p "$LOG_DIR" || {
  echo "FATAL: Cannot create log directory: $LOG_DIR" >&2
  exit 1
}
# Create directory for bc temporary files if it doesn't exist
mkdir -p "$BASE_DIR" || {
  echo "FATAL: Cannot create base directory: $BASE_DIR" >&2
  exit 1
}


# --- Check Dependencies ---
command -v bc >/dev/null 2>&1 || {
  # Use echo for initial fatal error as debug_log might not be defined yet
  echo "$(date '+%Y-%m-%d %H:%M:%S') [FATAL] ${SCRIPT_NAME}: 'bc' command not found. Please install the 'bc' package (e.g., 'opkg update && opkg install bc' or 'apk update && apk add bc')." >&2
  exit 1
}

# --- Global Variables ---
# Rule Definitions (Global Variables)
# Parameters for the 'fc2_ocn' rule based on https://ipv4.web.fc2.com/map-e.html logic
RULE_FC2_OCN_NAME="fc2_ocn"
RULE_FC2_OCN_IP6PREFIX_STR="2400:4151::" # Rule's IPv6 prefix string
RULE_FC2_OCN_IP6PREFIXLEN="32"
RULE_FC2_OCN_PSIDLEN="6"
RULE_FC2_OCN_OFFSET="6" # a-bits
RULE_FC2_OCN_BR_IPV4_STR="2.37.0.1" # Base IPv4 string for calculation
RULE_FC2_OCN_RULE_IP4MASK_DEC="4294967232" # Decimal for 0xFFFFFFC0 (/26 mask)
RULE_FC2_OCN_IS_RFC="0" # 0 for false, 1 for true
RULE_FC2_OCN_PEERADDR_STR="2404:9200:225:100::64" # BR IPv6 address string

# Pre-calculated/converted values for the rule (populated by load_rules)
RULE_FC2_OCN_IP6PREFIX_SEGS="" # Rule's IPv6 prefix as decimal segments
RULE_FC2_OCN_IP6NETWORK_SEGS="" # Rule's Network address as decimal segments
RULE_FC2_OCN_BR_IPV4_DEC="" # Rule's Base IPv4 as decimal number

# Global Variables for Calculated Parameters
MAPE_USER_PREFIX_SEGS=""
MAPE_RULE_NAME=""
MAPE_PSID=""
MAPE_IPV4=""
MAPE_CE_IPV6_SEGS="" # Store CE IPv6 as decimal segments initially
MAPE_CE_IPV6=""      # Store final formatted CE IPv6 string
MAPE_PORT_RANGE=""
MAPE_BR_IPV6=""      # Store final formatted BR IPv6 string
MAPE_EA_LEN=""       # Effective EA length (derived if needed)

# Function: bc_calc
# Description: Executes calculation using bc with basic error checking
# Arguments: $1: Calculation string to pass to bc
# Output: Prints the result of the calculation to stdout
# Returns: 0 on success, 1 on error (e.g., bc error)
bc_calc() {
  local expression="$1"
  local result=""
  local bc_stderr=""
  local exit_code=0
  local stderr_file="${BASE_DIR}/${SCRIPT_NAME}_bc_stderr.$$"

  mkdir -p "$BASE_DIR" 2>/dev/null

  debug_log "DEBUG" "bc_calc: Executing: echo \"$expression\" | bc"

  result=$(echo "$expression" | bc 2> "$stderr_file")
  exit_code=$?
  if [ -f "$stderr_file" ]; then
    bc_stderr=$(cat "$stderr_file")
    rm -f "$stderr_file"
  else
    bc_stderr=""
 fi

  if [ "$exit_code" -ne 0 ] || [ -n "$bc_stderr" ]; then
    debug_log "ERROR" "bc calculation failed (Exit Code: $exit_code) for expression: '${expression}'. bc stderr: ${bc_stderr:-<none>}"
    return 1
  fi

  if printf "%s" "$result" | grep -q '[^[:space:]]'; then
      printf "%s\n" "$result"
  else
      if echo "$expression" | grep -q "^0"; then
          printf "0\n"
      else
          debug_log "WARN" "bc returned empty or whitespace result for expression: '${expression}'"
          printf "%s\n" "$result"
      fi
  fi

  return 0
}

# Function: ipv6_to_dec_segments
# Description: Converts an IPv6 address string (including compressed format)
#              to a space-separated string of 8 decimal segments.
# Arguments: $1: IPv6 address string (e.g., "2400:4151::1", "::1")
# Output: Prints space-separated decimal segments (e.g., "9216 16721 0 0 0 0 0 1")
# Returns: 0 on success, 1 on invalid input format
ipv6_to_dec_segments() {
    local ipv6_addr="$1"
    local full_ipv6=""
    local segment=""
    local dec_segments=""
    local i=0
    local num_segments=0
    local num_zeros=0

    debug_log "DEBUG" "ipv6_to_dec_segments: Input IPv6: $ipv6_addr"

    # 1. Expand "::" if present
    if echo "$ipv6_addr" | grep -q "::"; then
        local part1=$(echo "$ipv6_addr" | cut -d':' -f1)
        local part2=$(echo "$ipv6_addr" | cut -d':' -f2-)

        local segments_before=$(echo "$ipv6_addr" | sed 's/::.*//' | tr -cd ':' | wc -c)
        local segments_after=$(echo "$ipv6_addr" | sed 's/.*:://' | tr -cd ':' | wc -c)

        if echo "$ipv6_addr" | grep -q '^::'; then segments_before=0; else segments_before=$((segments_before + 1)); fi
        if echo "$ipv6_addr" | grep -q '::$'; then segments_after=0; else segments_after=$((segments_after + 1)); fi

        num_segments=$((segments_before + segments_after))
        num_zeros=$((8 - num_segments))

        local zero_padding=""
        i=0
        while [ "$i" -lt "$num_zeros" ]; do
            zero_padding="${zero_padding}:0"
            i=$((i + 1))
        done
        if echo "$ipv6_addr" | grep -q '^::'; then zero_padding=$(echo "$zero_padding" | cut -c2-); fi

        full_ipv6=$(echo "$ipv6_addr" | sed "s/::/${zero_padding}:/" | sed 's/:$//')
        if [ "$ipv6_addr" = "::" ]; then full_ipv6="0:0:0:0:0:0:0:0"; fi

    else
        full_ipv6="$ipv6_addr"
        if [ "$(echo "$full_ipv6" | tr -cd ':' | wc -c)" -ne 7 ]; then
             debug_log "ERROR" "Invalid non-compressed IPv6 format: $ipv6_addr"
             return 1
        fi
    fi

    # 2. Convert each hex segment to decimal
    local OLD_IFS="$IFS"
    IFS=':'
    set -- $full_ipv6
    IFS="$OLD_IFS"

    i=1
    while [ "$i" -le 8 ]; do
        eval segment=\$$i
        [ -z "$segment" ] && segment="0"

        if ! printf "%s" "$segment" | grep -q '^[0-9a-fA-F]\{1,4\}$'; then
             debug_log "ERROR" "Invalid hex segment '$segment' in IPv6: $full_ipv6"
             return 1
        fi

        local dec_val
        dec_val=$(printf "%d" "0x${segment}" 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$dec_val" ] && [ "$segment" != "0" ]; then
            debug_log "ERROR" "Failed to convert hex segment '$segment' to decimal."
            return 1
        fi
        [ "$segment" = "0" ] && dec_val="0"

        if [ -z "$dec_segments" ]; then
            dec_segments="$dec_val"
        else
            dec_segments="$dec_segments $dec_val"
        fi
        i=$((i + 1))
    done

    local segment_count=$(($(echo "$dec_segments" | tr -cd ' ' | wc -c) + 1))
    if [ "$segment_count" -ne 8 ]; then
        debug_log "ERROR" "Conversion resulted in $segment_count segments, expected 8. Input: $ipv6_addr, Full: $full_ipv6, Dec: $dec_segments"
        return 1
    fi

    debug_log "DEBUG" "ipv6_to_dec_segments: Output Decimal: $dec_segments"
    printf "%s\n" "$dec_segments"
    return 0
}

# Function: dec_segments_to_ipv6
# Description: Converts a space-separated string of 8 decimal IPv6 segments
#              to a colon-separated string of 8 hexadecimal segments (no compression).
# Arguments: $1: Space-separated decimal segments (e.g., "9216 16721 0 0 0 0 0 1")
# Output: Prints colon-separated hexadecimal IPv6 address (e.g., "2400:4151:0:0:0:0:0:1")
# Returns: 0 on success, 1 on invalid input format
dec_segments_to_ipv6() {
    local dec_segments="$1"
    local hex_ipv6=""
    local segment=""
    local i=1

    debug_log "DEBUG" "dec_segments_to_ipv6: Input Decimal: $dec_segments"

    local OLD_IFS="$IFS"
    IFS=' '
    set -- $dec_segments
    IFS="$OLD_IFS"

    if [ "$#" -ne 8 ]; then
        debug_log "ERROR" "Invalid input: Expected 8 decimal segments, got $#. Input: $dec_segments"
        return 1
    fi

    while [ "$i" -le 8 ]; do
        eval segment=\$$i

        if ! printf "%s" "$segment" | grep -q '^[0-9]\+$'; then
             debug_log "ERROR" "Invalid decimal segment '$segment'. Input: $dec_segments"
             return 1
        fi
        if [ "$segment" -lt 0 ] || [ "$segment" -gt 65535 ]; then
             debug_log "ERROR" "Decimal segment '$segment' out of range (0-65535). Input: $dec_segments"
             return 1
        fi

        local hex_val
        hex_val=$(printf "%x" "$segment" 2>/dev/null)
         if [ $? -ne 0 ] || [ -z "$hex_val" ] && [ "$segment" != "0" ]; then
            debug_log "ERROR" "Failed to convert decimal segment '$segment' to hex."
            return 1
        fi

        if [ -z "$hex_ipv6" ]; then
            hex_ipv6="$hex_val"
        else
            hex_ipv6="${hex_ipv6}:${hex_val}"
        fi
        i=$((i + 1))
    done

    debug_log "DEBUG" "dec_segments_to_ipv6: Output IPv6: $hex_ipv6"
    printf "%s\n" "$hex_ipv6"
    return 0
}

# Function: ipv4_to_dec
# Description: Converts an IPv4 address string ("A.B.C.D") to its decimal representation.
# Arguments: $1: IPv4 address string (e.g., "192.168.1.1")
# Output: Prints the decimal value as a string.
# Returns: 0 on success, 1 on invalid input format or calculation error
ipv4_to_dec() {
    local ipv4_addr="$1"
    local o1 o2 o3 o4
    local dec_val=""

    debug_log "DEBUG" "ipv4_to_dec: Input IPv4: $ipv4_addr"

    local OLD_IFS="$IFS"
    IFS='.'
    set -- $ipv4_addr
    IFS="$OLD_IFS"

    if [ "$#" -ne 4 ]; then
        debug_log "ERROR" "Invalid IPv4 format: Expected 4 octets, got $#. Input: $ipv4_addr"
        return 1
    fi
    o1=$1; o2=$2; o3=$3; o4=$4

    for octet in $o1 $o2 $o3 $o4; do
        if ! printf "%s" "$octet" | grep -q '^[0-9]\+$'; then
            debug_log "ERROR" "Invalid IPv4 octet: '$octet' is not numeric. Input: $ipv4_addr"
            return 1
        fi
        if [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
            debug_log "ERROR" "Invalid IPv4 octet: '$octet' out of range (0-255). Input: $ipv4_addr"
            return 1
        fi
    done

    local expression="${o1} * (2^24) + ${o2} * (2^16) + ${o3} * (2^8) + ${o4}"

    dec_val=$(bc_calc "$expression")
    if [ $? -ne 0 ]; then
        debug_log "ERROR" "bc calculation failed during IPv4 to decimal conversion."
        return 1
    fi

    debug_log "DEBUG" "ipv4_to_dec: Output Decimal: $dec_val"
    printf "%s\n" "$dec_val"
    return 0
}

# Function: dec_to_ipv4
# Description: Converts a decimal number string to its IPv4 address representation ("A.B.C.D").
# Arguments: $1: Decimal number string (e.g., "3232235777")
# Output: Prints the IPv4 address string.
# Returns: 0 on success, 1 on invalid input or calculation error
dec_to_ipv4() {
    local dec_val="$1"
    local o1 o2 o3 o4
    local ipv4_addr=""

    debug_log "DEBUG" "dec_to_ipv4: Input Decimal: $dec_val"

    if ! printf "%s" "$dec_val" | grep -q '^[0-9]\+$'; then
        debug_log "ERROR" "Invalid input: '$dec_val' is not a non-negative integer."
        return 1
    fi

    local max_ipv4_dec="4294967295"
    local is_in_range=$(bc_calc "${dec_val} >= 0 && ${dec_val} <= ${max_ipv4_dec}")
    if [ "$is_in_range" != "1" ]; then
         debug_log "ERROR" "Invalid input: Decimal value '$dec_val' out of range for IPv4 (0-${max_ipv4_dec})."
         return 1
    fi

    local bc_script="
scale=0;
pow24 = 2^24; pow16 = 2^16; pow8  = 2^8; dec = ${dec_val};
o1 = dec / pow24; o2 = (dec % pow24) / pow16; o3 = (dec % pow16) / pow8; o4 = dec % pow8;
print o1, \" \", o2, \" \", o3, \" \", o4, \"\n\";
"
    local octets_str=$(bc_calc "$bc_script")
    if [ $? -ne 0 ] || [ -z "$octets_str" ]; then
        debug_log "ERROR" "bc calculation failed during decimal to IPv4 conversion."
        return 1
    fi

    local OLD_IFS="$IFS"
    IFS=' '
    set -- $octets_str
    IFS="$OLD_IFS"

    if [ "$#" -ne 4 ]; then
         debug_log "ERROR" "bc did not return 4 octets. bc output: '$octets_str'"
         return 1
    fi
    o1=$1; o2=$2; o3=$3; o4=$4

    ipv4_addr="${o1}.${o2}.${o3}.${o4}"

    debug_log "DEBUG" "dec_to_ipv4: Output IPv4: $ipv4_addr"
    printf "%s\n" "$ipv4_addr"
    return 0
}

# Function: bc_bitwise_and
# Description: Simulates bitwise AND operation using bc.
# Arguments: $1: First non-negative integer string
#            $2: Second non-negative integer string
# Output: Prints the result of ( $1 AND $2 ) to stdout.
# Returns: 0 on success, 1 on bc error or invalid input.
bc_bitwise_and() {
    local num1="$1"
    local num2="$2"
    local result=""

    if ! printf "%s" "$num1" | grep -q '^[0-9]\+$' || ! printf "%s" "$num2" | grep -q '^[0-9]\+$'; then
        debug_log "ERROR" "bc_bitwise_and: Invalid input - requires two non-negative integers. Got '$num1', '$num2'."
        return 1
    fi

    debug_log "DEBUG" "bc_bitwise_and: Calculating $num1 & $num2"

    local bc_script="
scale=0;
define band(n1, n2) {
    auto r, p;
    r = 0; p = 1;
    while (n1 > 0 && n2 > 0) {
        if ((n1 % 2) == 1 && (n2 % 2) == 1) { r = r + p; }
        n1 = n1 / 2; n2 = n2 / 2; p = p * 2;
    }
    return r;
}
print band(${num1}, ${num2});
"
    result=$(bc_calc "$bc_script")
    if [ $? -ne 0 ]; then
        debug_log "ERROR" "bc_bitwise_and: bc calculation failed."
        return 1
    fi

    printf "%s\n" "$result"
    return 0
}

# Function: bc_bitwise_or
# Description: Simulates bitwise OR operation using bc.
# Arguments: $1: First non-negative integer string
#            $2: Second non-negative integer string
# Output: Prints the result of ( $1 OR $2 ) to stdout.
# Returns: 0 on success, 1 on bc error or invalid input.
bc_bitwise_or() {
    local num1="$1"
    local num2="$2"
    local result=""

    if ! printf "%s" "$num1" | grep -q '^[0-9]\+$' || ! printf "%s" "$num2" | grep -q '^[0-9]\+$'; then
        debug_log "ERROR" "bc_bitwise_or: Invalid input - requires two non-negative integers. Got '$num1', '$num2'."
        return 1
    fi

    debug_log "DEBUG" "bc_bitwise_or: Calculating $num1 | $num2"

    local bc_script="
scale=0;
define bor(n1, n2) {
    auto r, p;
    r = 0; p = 1;
    while (n1 > 0 || n2 > 0) {
        if ((n1 % 2) == 1 || (n2 % 2) == 1) { r = r + p; }
        n1 = n1 / 2; n2 = n2 / 2; p = p * 2;
    }
    return r;
}
print bor(${num1}, ${num2});
"
    result=$(bc_calc "$bc_script")
    if [ $? -ne 0 ]; then
        debug_log "ERROR" "bc_bitwise_or: bc calculation failed."
        return 1
    fi

    printf "%s\n" "$result"
    return 0
}

# Function: bc_shift_left
# Description: Performs bitwise left shift using bc (multiplication by power of 2).
# Arguments: $1: Non-negative integer string (number to shift)
#            $2: Non-negative integer string (shift amount)
# Output: Prints the result of ( $1 << $2 ) to stdout.
# Returns: 0 on success, 1 on bc error or invalid input.
bc_shift_left() {
    local num="$1"
    local shift_amount="$2"
    local result=""

    if ! printf "%s" "$num" | grep -q '^[0-9]\+$' || ! printf "%s" "$shift_amount" | grep -q '^[0-9]\+$'; then
        debug_log "ERROR" "bc_shift_left: Invalid input - requires two non-negative integers. Got '$num', '$shift_amount'."
        return 1
    fi

    debug_log "DEBUG" "bc_shift_left: Calculating $num << $shift_amount"

    local expression="${num} * (2^${shift_amount})"

    result=$(bc_calc "$expression")
    if [ $? -ne 0 ]; then
        debug_log "ERROR" "bc_shift_left: bc calculation failed."
        return 1
    fi

    printf "%s\n" "$result"
    return 0
}

# Function: bc_shift_right
# Description: Performs bitwise right shift using bc (integer division by power of 2).
# Arguments: $1: Non-negative integer string (number to shift)
#            $2: Non-negative integer string (shift amount)
# Output: Prints the result of ( $1 >> $2 ) to stdout.
# Returns: 0 on success, 1 on bc error or invalid input.
bc_shift_right() {
    local num="$1"
    local shift_amount="$2"
    local result=""

    if ! printf "%s" "$num" | grep -q '^[0-9]\+$' || ! printf "%s" "$shift_amount" | grep -q '^[0-9]\+$'; then
        debug_log "ERROR" "bc_shift_right: Invalid input - requires two non-negative integers. Got '$num', '$shift_amount'."
        return 1
    fi

    debug_log "DEBUG" "bc_shift_right: Calculating $num >> $shift_amount"

    local expression="scale=0; ${num} / (2^${shift_amount})"

    result=$(bc_calc "$expression")
    if [ $? -ne 0 ]; then
        debug_log "ERROR" "bc_shift_right: bc calculation failed."
        return 1
    fi

    printf "%s\n" "$result"
    return 0
}

# Function: dec_segments_to_large_dec
# Description: Converts 8 space-separated decimal IPv6 segments into a single
#              large decimal number string representing the 128-bit value.
# Arguments: $1: Space-separated decimal segments (e.g., "9216 16721 0 0 0 0 0 1")
# Output: Prints the large decimal number string.
# Returns: 0 on success, 1 on invalid input or bc error.
dec_segments_to_large_dec() {
    local dec_segments="$1"
    local large_dec="0"
    local segment=""
    local i=0

    debug_log "DEBUG" "dec_segments_to_large_dec: Input Decimal Segments: $dec_segments"

    local OLD_IFS="$IFS"
    IFS=' '
    set -- $dec_segments
    IFS="$OLD_IFS"

    if [ "$#" -ne 8 ]; then
        debug_log "ERROR" "Invalid input: Expected 8 decimal segments, got $#. Input: $dec_segments"
        return 1
    fi

    local expression="scale=0"
    i=0
    while [ "$i" -lt 8 ]; do
        eval segment=\$$((i + 1))
        if ! printf "%s" "$segment" | grep -q '^[0-9]\+$' || [ "$segment" -lt 0 ] || [ "$segment" -gt 65535 ]; then
             debug_log "ERROR" "Invalid decimal segment '$segment' at index $i. Input: $dec_segments"
             return 1
        fi
        local shift_val=$(( (7 - i) * 16 ))
        expression="${expression} + ${segment} * (2^${shift_val})"
        i=$((i + 1))
    done

    large_dec=$(bc_calc "$expression")
    if [ $? -ne 0 ]; then
        debug_log "ERROR" "bc calculation failed during decimal segments to large decimal conversion."
        return 1
    fi

    debug_log "DEBUG" "dec_segments_to_large_dec: Output Large Decimal: $large_dec"
    printf "%s\n" "$large_dec"
    return 0
}

# Function: ipv6_mask_dec_segments
# Description: Generates an IPv6 network mask based on a prefix length.
# Arguments: $1: Prefix length (0-128)
# Output: Prints the mask as 8 space-separated decimal segments.
# Returns: 0 on success, 1 on invalid prefix length or bc error.
ipv6_mask_dec_segments() {
    local prefixlen="$1"
    local mask_segments=""
    local i=0
    local segment_mask_dec=""

    debug_log "DEBUG" "ipv6_mask_dec_segments: Input Prefix Length: $prefixlen"

    if ! printf "%s" "$prefixlen" | grep -q '^[0-9]\+$' || [ "$prefixlen" -lt 0 ] || [ "$prefixlen" -gt 128 ]; then
        debug_log "ERROR" "Invalid prefix length: '$prefixlen'. Must be between 0 and 128."
        return 1
    fi

    i=0
    while [ "$i" -lt 8 ]; do
        local segment_start_bit=$(( i * 16 ))
        local segment_end_bit=$(( (i + 1) * 16 - 1 ))
        segment_mask_dec="0"

        if [ "$prefixlen" -ge "$((segment_end_bit + 1))" ]; then
            segment_mask_dec="65535"
        elif [ "$prefixlen" -gt "$segment_start_bit" ]; then
            local bits_in_segment=$(( prefixlen - segment_start_bit ))
            local expression="(2^16) - (2^(16 - ${bits_in_segment}))"
            segment_mask_dec=$(bc_calc "$expression")
            if [ $? -ne 0 ]; then
                debug_log "ERROR" "bc calculation failed for partial mask segment $i (prefixlen: $prefixlen)."
                return 1
            fi
        fi

        if [ -z "$mask_segments" ]; then
            mask_segments="$segment_mask_dec"
        else
            mask_segments="$mask_segments $segment_mask_dec"
        fi
        i=$((i + 1))
    done

    debug_log "DEBUG" "ipv6_mask_dec_segments: Output Mask Segments: $mask_segments"
    printf "%s\n" "$mask_segments"
    return 0
}

# Function: ipv6_network_dec_segments
# Description: Calculates the network address for a given IPv6 address and prefix length.
# Arguments: $1: IPv6 address as 8 space-separated decimal segments
#            $2: Prefix length (0-128)
# Output: Prints the network address as 8 space-separated decimal segments.
# Returns: 0 on success, 1 on error (e.g., from called functions).
ipv6_network_dec_segments() {
    local addr_segments="$1"
    local prefixlen="$2"
    local mask_segments=""
    local network_segments=""
    local addr_seg=""
    local mask_seg=""
    local result_seg=""
    local i=1

    debug_log "DEBUG" "ipv6_network_dec_segments: Input Address Segments: $addr_segments, Prefix Length: $prefixlen"

    mask_segments=$(ipv6_mask_dec_segments "$prefixlen")
    if [ $? -ne 0 ]; then
        debug_log "ERROR" "Failed to generate mask for prefix length $prefixlen."
        return 1
    fi

    local OLD_IFS="$IFS"
    IFS=' '
    set -- $addr_segments
    local addr_segs="$@"
    set -- $mask_segments
    local mask_segs="$@"
    IFS="$OLD_IFS"

    IFS=' '
    set -- $addr_segs
    i=1
    for mask_seg in $mask_segs; do
        eval addr_seg=\$$i
        result_seg=$(bc_bitwise_and "$addr_seg" "$mask_seg")
        if [ $? -ne 0 ]; then
            debug_log "ERROR" "bc_bitwise_and failed for segment $i (addr=$addr_seg, mask=$mask_seg)."
            IFS="$OLD_IFS"
            return 1
        fi
        if [ -z "$network_segments" ]; then
            network_segments="$result_seg"
        else
            network_segments="$network_segments $result_seg"
        fi
        i=$((i + 1))
    done
    IFS="$OLD_IFS"

    debug_log "DEBUG" "ipv6_network_dec_segments: Output Network Segments: $network_segments"
    printf "%s\n" "$network_segments"
    return 0
}

# Function: extract_ipv6_bits_dec
# Description: Extracts a sequence of bits from an IPv6 address and returns
#              the result as a decimal number string.
# Arguments: $1: IPv6 address as 8 space-separated decimal segments
#            $2: Start bit position (0-127, from left/most significant bit)
#            $3: Length of bits to extract (1-128)
# Output: Prints the extracted bits as a decimal number string.
# Returns: 0 on success, 1 on invalid input or calculation error.
extract_ipv6_bits_dec() {
    local addr_segments="$1"
    local start_bit="$2"
    local length="$3"
    local large_addr_dec=""
    local shifted_val=""
    local mask_val=""
    local result_dec=""

    debug_log "DEBUG" "extract_ipv6_bits_dec: Input Segments: $addr_segments, Start: $start_bit, Length: $length"

    if ! printf "%s" "$start_bit" | grep -q '^[0-9]\+$' || [ "$start_bit" -lt 0 ] || [ "$start_bit" -gt 127 ]; then
        debug_log "ERROR" "Invalid start bit: '$start_bit'. Must be between 0 and 127."
        return 1
    fi
    if ! printf "%s" "$length" | grep -q '^[1-9][0-9]*$' || [ "$length" -lt 1 ] || [ "$length" -gt 128 ]; then
        debug_log "ERROR" "Invalid length: '$length'. Must be between 1 and 128."
        return 1
    fi
    if [ $((start_bit + length)) -gt 128 ]; then
        debug_log "ERROR" "Invalid range: Start bit ($start_bit) + length ($length) exceeds 128."
        return 1
    fi

    large_addr_dec=$(dec_segments_to_large_dec "$addr_segments")
    if [ $? -ne 0 ]; then debug_log "ERROR" "Failed to convert address segments to large decimal."; return 1; fi

    local shift_right_amount=$(( 128 - start_bit - length ))
    debug_log "DEBUG" "Calculated right shift amount: $shift_right_amount"
    shifted_val=$(bc_shift_right "$large_addr_dec" "$shift_right_amount")
    if [ $? -ne 0 ]; then debug_log "ERROR" "bc_shift_right failed during bit extraction."; return 1; fi
    debug_log "DEBUG" "Value after right shift: $shifted_val"

    local mask_expr="(2^${length}) - 1"
    mask_val=$(bc_calc "$mask_expr")
    if [ $? -ne 0 ]; then debug_log "ERROR" "bc calculation failed creating mask for length $length."; return 1; fi
    debug_log "DEBUG" "Calculated mask for length $length: $mask_val"

    result_dec=$(bc_bitwise_and "$shifted_val" "$mask_val")
    if [ $? -ne 0 ]; then debug_log "ERROR" "bc_bitwise_and failed applying mask during bit extraction."; return 1; fi

    debug_log "DEBUG" "extract_ipv6_bits_dec: Output Result Decimal: $result_dec"
    printf "%s\n" "$result_dec"
    return 0
}

# Function: load_rules
# Description: Initializes and pre-calculates values for defined MAP-E rules.
#              Currently hardcoded for the 'fc2_ocn' rule.
# Arguments: None
# Output: None (sets global rule variables)
# Returns: 0 on success, 1 on error during pre-calculation.
load_rules() {
    local rule_name="fc2_ocn"
    debug_log "DEBUG" "Loading rules... (Currently only '$rule_name')"
    debug_log "DEBUG" "Pre-calculating values for rule: $rule_name"

    RULE_FC2_OCN_IP6PREFIX_SEGS=$(ipv6_to_dec_segments "$RULE_FC2_OCN_IP6PREFIX_STR")
    if [ $? -ne 0 ]; then debug_log "ERROR" "Failed to convert rule prefix '$RULE_FC2_OCN_IP6PREFIX_STR' to decimal segments for rule '$rule_name'."; return 1; fi
    debug_log "DEBUG" "Rule '$rule_name' - IP6PREFIX_SEGS: $RULE_FC2_OCN_IP6PREFIX_SEGS"

    RULE_FC2_OCN_IP6NETWORK_SEGS=$(ipv6_network_dec_segments "$RULE_FC2_OCN_IP6PREFIX_SEGS" "$RULE_FC2_OCN_IP6PREFIXLEN")
     if [ $? -ne 0 ]; then debug_log "ERROR" "Failed to calculate rule network address for rule '$rule_name'."; return 1; fi
    debug_log "DEBUG" "Rule '$rule_name' - IP6NETWORK_SEGS: $RULE_FC2_OCN_IP6NETWORK_SEGS"

    RULE_FC2_OCN_BR_IPV4_DEC=$(ipv4_to_dec "$RULE_FC2_OCN_BR_IPV4_STR")
    if [ $? -ne 0 ]; then debug_log "ERROR" "Failed to convert rule base IPv4 '$RULE_FC2_OCN_BR_IPV4_STR' to decimal for rule '$rule_name'."; return 1; fi
    debug_log "DEBUG" "Rule '$rule_name' - BR_IPV4_DEC: $RULE_FC2_OCN_BR_IPV4_DEC"

    debug_log "DEBUG" "Rules loaded successfully."
    return 0
}

# Function: find_matching_rule
# Description: Finds the MAP-E rule that matches the user's IPv6 address prefix.
# Arguments: $1: User's IPv6 address as 8 space-separated decimal segments
# Output: Prints the name of the matching rule (e.g., "fc2_ocn") if found,
#         otherwise prints nothing.
# Returns: 0 if a match is found, 1 if no match is found or an error occurs.
find_matching_rule() {
    local user_addr_segs="$1"
    local user_network_segs=""
    local matched_rule_name=""

    debug_log "DEBUG" "find_matching_rule: Searching for rule matching user address segments: $user_addr_segs"

    local rule_name="fc2_ocn"
    local rule_prefixlen="$RULE_FC2_OCN_IP6PREFIXLEN"
    local rule_network_segs="$RULE_FC2_OCN_IP6NETWORK_SEGS"

    if [ -z "$rule_network_segs" ]; then
         debug_log "ERROR" "Rule '$rule_name' network address is not loaded. Run load_rules first."
         return 1
    fi

    user_network_segs=$(ipv6_network_dec_segments "$user_addr_segs" "$rule_prefixlen")
    if [ $? -ne 0 ]; then debug_log "ERROR" "Failed to calculate user network address for prefix length $rule_prefixlen."; return 1; fi
    debug_log "DEBUG" "Calculated User Network Segments (for rule '$rule_name'): $user_network_segs"
    debug_log "DEBUG" "Comparing with Rule '$rule_name' Network Segments: $rule_network_segs"

    if [ "$user_network_segs" = "$rule_network_segs" ]; then
        debug_log "INFO" "Found matching rule: $rule_name"
        matched_rule_name="$rule_name"
    fi

    if [ -n "$matched_rule_name" ]; then
        printf "%s\n" "$matched_rule_name"
        return 0
    else
        debug_log "WARN" "No matching MAP-E rule found for the provided IPv6 address."
        return 1
    fi
}

# Function: large_dec_to_dec_segments
# Description: Converts a single large decimal number string (representing a 128-bit value)
#              back into 8 space-separated decimal IPv6 segments.
# Arguments: $1: Large decimal number string
# Output: Prints 8 space-separated decimal segments.
# Returns: 0 on success, 1 on invalid input or bc error.
large_dec_to_dec_segments() {
    local large_dec="$1"
    local dec_segments=""
    local segment=""
    local i=0

    debug_log "DEBUG" "large_dec_to_dec_segments: Input Large Decimal: $large_dec"

    if ! printf "%s" "$large_dec" | grep -q '^[0-9]\+$'; then
        debug_log "ERROR" "Invalid input: '$large_dec' is not a non-negative integer."
        return 1
    fi

    local bc_script="
scale=0;
pow112=2^112; pow96=2^96; pow80=2^80; pow64=2^64;
pow48=2^48; pow32=2^32; pow16=2^16; val=${large_dec};
seg0=val/pow112; rem0=val%pow112; seg1=rem0/pow96; rem1=rem0%pow96;
seg2=rem1/pow80; rem2=rem1%pow80; seg3=rem2/pow64; rem3=rem2%pow64;
seg4=rem3/pow48; rem4=rem3%pow48; seg5=rem4/pow32; rem5=rem4%pow32;
seg6=rem5/pow16; seg7=rem5%pow16;
print seg0,\" \",seg1,\" \",seg2,\" \",seg3,\" \",seg4,\" \",seg5,\" \",seg6,\" \",seg7,\"\\n\";
"
    dec_segments=$(bc_calc "$bc_script")
    if [ $? -ne 0 ] || [ -z "$dec_segments" ]; then
        debug_log "ERROR" "bc calculation failed during large decimal to decimal segments conversion."
        return 1
    fi

    local segment_count=$(($(echo "$dec_segments" | tr -cd ' ' | wc -c) + 0))
    if [ "$segment_count" -ne 7 ]; then
         debug_log "ERROR" "Conversion resulted in unexpected number of segments. bc output: '$dec_segments'"
         dec_segments=$(echo "$dec_segments" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
         segment_count=$(($(echo "$dec_segments" | tr -cd ' ' | wc -c) + 0))
         if [ "$segment_count" -ne 7 ]; then
            debug_log "ERROR" "Still incorrect segment count after cleanup: $segment_count spaces."
            return 1
         fi
    fi

    debug_log "DEBUG" "large_dec_to_dec_segments: Output Decimal Segments: $dec_segments"
    printf "%s\n" "$dec_segments"
    return 0
}

# Function: calculate_mape_params
# Description: Calculates MAP-E parameters based on the user's IPv6 address
#              and the matched rule. Stores results in global MAPE_* variables.
# Arguments: $1: User's IPv6 address as 8 space-separated decimal segments
#            $2: Name of the matching rule (e.g., "fc2_ocn")
# Output: None (sets global MAPE_* variables)
# Returns: 0 on success, 1 on error (unknown rule or calculation failure).
calculate_mape_params() {
    local user_addr_segs="$1"
    local rule_name="$2"

    debug_log "INFO" "Calculating MAP-E parameters for rule: $rule_name"
    MAPE_USER_PREFIX_SEGS="$user_addr_segs"
    MAPE_RULE_NAME="$rule_name"

    if [ "$rule_name" != "fc2_ocn" ]; then
        debug_log "ERROR" "Unsupported rule name: $rule_name"
        return 1
    fi

    local psidlen="$RULE_FC2_OCN_PSIDLEN"
    local offset="$RULE_FC2_OCN_OFFSET"
    local rule_br_ipv4_dec="$RULE_FC2_OCN_BR_IPV4_DEC"
    local rule_ip4mask_dec="$RULE_FC2_OCN_RULE_IP4MASK_DEC"
    local is_rfc="$RULE_FC2_OCN_IS_RFC"
    local rule_ip6prefixlen="$RULE_FC2_OCN_IP6PREFIXLEN"
    local rule_br_ipv6_str="$RULE_FC2_OCN_PEERADDR_STR"

    # --- 1. Calculate PSID ---
    local psid_start_bit=64
    debug_log "DEBUG" "Calculating PSID (Start Bit: $psid_start_bit, Length: $psidlen)"
    MAPE_PSID=$(extract_ipv6_bits_dec "$user_addr_segs" "$psid_start_bit" "$psidlen")
    if [ $? -ne 0 ]; then debug_log "ERROR" "Failed to calculate PSID."; return 1; fi
    debug_log "INFO" "Calculated PSID: $MAPE_PSID"

    # --- 2. Calculate IPv4 Address ---
    debug_log "DEBUG" "Calculating IPv4 Address..."
    local term1 term2 ipv4_dec
    term1=$(bc_bitwise_and "$rule_br_ipv4_dec" "$rule_ip4mask_dec")
    if [ $? -ne 0 ]; then debug_log "ERROR" "IPv4 calc failed at term1 (AND)"; return 1; fi
    debug_log "DEBUG" "IPv4 Term1 (BR_IPv4 & Mask): $term1"
    term2=$(bc_shift_left "$MAPE_PSID" "$offset")
    if [ $? -ne 0 ]; then debug_log "ERROR" "IPv4 calc failed at term2 (Shift)"; return 1; fi
    debug_log "DEBUG" "IPv4 Term2 (PSID << Offset): $term2"
    ipv4_dec=$(bc_bitwise_or "$term1" "$term2")
    if [ $? -ne 0 ]; then debug_log "ERROR" "IPv4 calc failed at final OR"; return 1; fi
    debug_log "DEBUG" "IPv4 Decimal Result: $ipv4_dec"
    MAPE_IPV4=$(dec_to_ipv4 "$ipv4_dec")
    if [ $? -ne 0 ]; then debug_log "ERROR" "Failed to convert calculated decimal '$ipv4_dec' back to IPv4 string."; return 1; fi
    debug_log "INFO" "Calculated IPv4 Address: $MAPE_IPV4"

    # --- 3. Calculate CE IPv6 Address ---
    debug_log "DEBUG" "Calculating CE IPv6 Address (is_rfc=$is_rfc)..."
    if [ "$is_rfc" = "0" ]; then
        local user_large_dec mask_large_dec psid_shift_amount psid_shifted termA termB ce_ipv6_large_dec mask_segs
        user_large_dec=$(dec_segments_to_large_dec "$user_addr_segs")
        if [ $? -ne 0 ]; then debug_log "ERROR" "CE IPv6 calc failed converting user addr"; return 1; fi
        mask_segs=$(ipv6_mask_dec_segments "$rule_ip6prefixlen")
        if [ $? -ne 0 ]; then debug_log "ERROR" "CE IPv6 calc failed generating mask"; return 1; fi
        mask_large_dec=$(dec_segments_to_large_dec "$mask_segs")
        if [ $? -ne 0 ]; then debug_log "ERROR" "CE IPv6 calc failed converting mask"; return 1; fi
        psid_shift_amount=$(( 128 - rule_ip6prefixlen - psidlen ))
        debug_log "DEBUG" "CE IPv6 PSID Shift Amount: $psid_shift_amount"
        termA=$(bc_bitwise_and "$user_large_dec" "$mask_large_dec")
        if [ $? -ne 0 ]; then debug_log "ERROR" "CE IPv6 calc failed at termA (AND)"; return 1; fi
        debug_log "DEBUG" "CE IPv6 TermA (User & Mask): $termA"
        psid_shifted=$(bc_shift_left "$MAPE_PSID" "$psid_shift_amount")
        if [ $? -ne 0 ]; then debug_log "ERROR" "CE IPv6 calc failed shifting PSID"; return 1; fi
        debug_log "DEBUG" "CE IPv6 TermB (PSID << Shift): $psid_shifted"
        termB=$(bc_bitwise_or "$termA" "$psid_shifted")
        if [ $? -ne 0 ]; then debug_log "ERROR" "CE IPv6 calc failed at OR (A|B)"; return 1; fi
        debug_log "DEBUG" "CE IPv6 Result (A | B): $termB"
        ce_ipv6_large_dec=$(bc_bitwise_or "$termB" "1")
        if [ $? -ne 0 ]; then debug_log "ERROR" "CE IPv6 calc failed at final OR with 1"; return 1; fi
        debug_log "DEBUG" "CE IPv6 Large Decimal Result: $ce_ipv6_large_dec"
        MAPE_CE_IPV6_SEGS=$(large_dec_to_dec_segments "$ce_ipv6_large_dec")
        if [ $? -ne 0 ]; then debug_log "ERROR" "Failed to convert calculated CE IPv6 large decimal back to segments."; return 1; fi
    else
        debug_log "WARN" "RFC compliant CE IPv6 calculation is not implemented yet."
        MAPE_CE_IPV6_SEGS="0 0 0 0 0 0 0 0" # Placeholder
    fi
    MAPE_CE_IPV6=$(dec_segments_to_ipv6 "$MAPE_CE_IPV6_SEGS")
    if [ $? -ne 0 ]; then
        debug_log "ERROR" "Failed to format CE IPv6 segments '$MAPE_CE_IPV6_SEGS' to string."
        MAPE_CE_IPV6=""
    fi
    debug_log "INFO" "Calculated CE IPv6 Segments: $MAPE_CE_IPV6_SEGS"
    debug_log "INFO" "Calculated CE IPv6 Address: $MAPE_CE_IPV6"

    # --- 4. Calculate Port Range ---
    debug_log "DEBUG" "Calculating Port Range (psidlen=$psidlen, offset=$offset)..."
    if [ "$psidlen" -le "$offset" ]; then
        MAPE_PORT_RANGE="1024-65535"
    else
        debug_log "WARN" "Standard MAP-E port calculation (psidlen > offset) is not implemented yet."
        MAPE_PORT_RANGE="N/A (Not Implemented)"
    fi
    debug_log "INFO" "Calculated Port Range: $MAPE_PORT_RANGE"

    # --- 5. Set BR IPv6 Address ---
    local br_segs br_ipv6_formatted
    br_segs=$(ipv6_to_dec_segments "$rule_br_ipv6_str")
    if [ $? -eq 0 ]; then
        br_ipv6_formatted=$(dec_segments_to_ipv6 "$br_segs")
         if [ $? -eq 0 ]; then MAPE_BR_IPV6="$br_ipv6_formatted"; else
             debug_log "WARN" "Failed to format BR IPv6 string '$rule_br_ipv6_str'. Using original."
             MAPE_BR_IPV6="$rule_br_ipv6_str"; fi
    else
         debug_log "WARN" "Failed to parse BR IPv6 string '$rule_br_ipv6_str'. Using original."
         MAPE_BR_IPV6="$rule_br_ipv6_str"; fi
    debug_log "INFO" "BR IPv6 Address: $MAPE_BR_IPV6"

    # --- 6. Calculate EA Length (Optional/Derived) ---
    MAPE_EA_LEN=$(( 128 - rule_ip6prefixlen - psidlen ))
    debug_log "INFO" "Derived EA Length: $MAPE_EA_LEN"

    debug_log "INFO" "MAP-E parameter calculation completed successfully."
    return 0
}

# Function: display_results
# Description: Displays the calculated MAP-E parameters stored in global variables.
# Arguments: None
# Output: Prints formatted MAP-E parameters to stdout.
# Returns: 0 on success, 1 if essential parameters are missing.
display_results() {
    debug_log "DEBUG" "Displaying calculated MAP-E parameters."

    if [ -z "$MAPE_RULE_NAME" ] || [ -z "$MAPE_IPV4" ] || [ -z "$MAPE_CE_IPV6" ] || [ -z "$MAPE_PSID" ]; then
        debug_log "ERROR" "Cannot display results: Essential parameters are missing."
        return 1
    fi

    printf "\n--- MAP-E Parameters (Rule: %s) ---\n" "$MAPE_RULE_NAME"
    printf "  User IPv6 Prefix (Dec): %s\n" "$MAPE_USER_PREFIX_SEGS"
    printf "  Rule Matched:           %s\n" "$MAPE_RULE_NAME"
    printf "  PSID (Decimal):         %s\n" "$MAPE_PSID"
    printf "  IPv4 Address:           %s\n" "$MAPE_IPV4"
    printf "  CE IPv6 Address:        %s\n" "$MAPE_CE_IPV6"
    printf "  Port Range:             %s\n" "$MAPE_PORT_RANGE"
    printf "  BR IPv6 Address:        %s\n" "$MAPE_BR_IPV6"
    printf "  EA Length (bits):       %s\n" "$MAPE_EA_LEN"
    printf "-------------------------------------\n\n"

    return 0
}

# Function: main
# Description: Main entry point of the script. Parses arguments or gets WAN IPv6,
#              orchestrates rule loading, calculation, and result display.
# Arguments: $@: Command line arguments (optional: IPv6 address to use)
# Output: Prints results or error messages.
# Returns: 0 on success, non-zero on error.
internet_main() {
    local user_ipv6_str=""
    local user_ipv6_segs=""
    local matched_rule=""
    local NET_IF6=""
    local NET_ADDR6=""
    # script_basename variable is no longer needed

    # --- Get WAN IPv6 Address using OpenWrt functions ---
    debug_log "INFO" "Attempting to fetch IPv6 address from WAN interface..."

    # Ensure network functions are available (basic check)
    if ! type network_find_wan6 > /dev/null 2>&1 || ! type network_get_ipaddr6 > /dev/null 2>&1 ; then
         debug_log "ERROR" "OpenWrt network functions (network_find_wan6, network_get_ipaddr6) not found. Cannot fetch WAN IPv6."
         printf "Error: OpenWrt network functions not available.\n" >&2
         return 1
    fi

    network_flush_cache # Recommended before finding interfaces
    network_find_wan6 NET_IF6 # Find the WAN6 interface logical name
    if [ -z "$NET_IF6" ]; then
        debug_log "ERROR" "Could not find WAN6 interface (network_find_wan6)."
        printf "Error: Could not find WAN6 interface.\n" >&2
        return 1
    fi
    debug_log "DEBUG" "Found WAN6 interface: $NET_IF6"

    network_get_ipaddr6 NET_ADDR6 "${NET_IF6}" # Get the IPv6 address
    if [ -z "$NET_ADDR6" ]; then
        debug_log "ERROR" "Could not get IPv6 address from interface '$NET_IF6' (network_get_ipaddr6)."
        printf "Error: Could not get IPv6 address from interface '%s'.\n" "$NET_IF6" >&2
        return 1
    fi
    # network_get_ipaddr6 might return address with prefix length, remove it if present
    user_ipv6_str=$(echo "$NET_ADDR6" | cut -d'/' -f1)
    debug_log "INFO" "Fetched IPv6 address from WAN ($NET_IF6): $user_ipv6_str"

    # --- Proceed with calculation using fetched IPv6 ---
    debug_log "INFO" "Starting MAP-E calculation for IPv6: $user_ipv6_str"

    # --- Load Rules ---
    if ! load_rules; then
        debug_log "ERROR" "Failed to load MAP-E rules."
        return 1
    fi

    # --- Validate and Convert User IPv6 ---
    user_ipv6_segs=$(ipv6_to_dec_segments "$user_ipv6_str")
    if [ $? -ne 0 ]; then
        debug_log "ERROR" "Invalid IPv6 address format obtained from WAN: $user_ipv6_str"
        printf "Error: Invalid IPv6 address format obtained ('%s').\n" "$user_ipv6_str" >&2
        return 1
    fi
    debug_log "DEBUG" "User IPv6 decimal segments: $user_ipv6_segs"

    # --- Find Matching Rule ---
    matched_rule=$(find_matching_rule "$user_ipv6_segs")
    if [ $? -ne 0 ] || [ -z "$matched_rule" ]; then
        printf "Error: No matching MAP-E rule found for IPv6 address: %s\n" "$user_ipv6_str" >&2
        return 1
    fi

    # --- Calculate Parameters ---
    if ! calculate_mape_params "$user_ipv6_segs" "$matched_rule"; then
        debug_log "ERROR" "Failed to calculate MAP-E parameters."
        printf "Error: Calculation failed for rule '%s'. Check logs for details.\n" "$matched_rule" >&2
        return 1
    fi

    # --- Display Results ---
    if ! display_results; then
         debug_log "ERROR" "Failed to display results (likely due to missing parameters)."
         return 1
    fi

    debug_log "INFO" "Script finished successfully."
    return 0
}

# --- Load Libraries ---
# Load OpenWrt function libraries required by this script
. /lib/functions.sh # Load if specific functions like 'logger' are needed later
. /lib/functions/network.sh # Load if network functions are needed later
# . /lib/netifd/netifd-proto.sh # Keep commented unless explicitly needed


# --- Execute Main Function ---
# Pass all command line arguments to main
internet_main
