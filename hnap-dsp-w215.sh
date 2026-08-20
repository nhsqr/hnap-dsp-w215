#!/usr/bin/env bash
# hnap-dsp-w215 - Lightweight Bash client for D-Link DSP-W215 smart plug (HNAP)
# Version: 2.0.0
#
# Copyright (C) 2017-2026 Niki (nhsqr)
# Licensed under the GNU General Public License v3.0
#
# Requirements: bash, curl, openssl, xxd (or hexdump fallback)
# Optional: xmllint for nicer XML pretty-printing of schedules

set -euo pipefail

VERSION="2.0.0"
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults – override with -i/-p, environment variables, or edit these two lines
IP="${DSP_W215_IP:-}"
PIN="${DSP_W215_PIN:-}"

JSON_OUTPUT=0
QUIET=0
FORCE=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  cat <<EOF
$SCRIPT_NAME $VERSION – D-Link DSP-W215 HNAP client

Usage:
  $SCRIPT_NAME [OPTIONS] COMMAND [ARGS]

Options:
  -i, --ip IP          Device IP address (or set DSP_W215_IP)
  -p, --pin PIN        Device PIN / password (or set DSP_W215_PIN)
  -j, --json           Output machine-readable JSON
  -q, --quiet          Suppress non-error messages
  -f, --force          Skip confirmation for destructive actions (reboot)
  -h, --help           Show this help
  -v, --version        Show version

Commands:
  state [on|off]       Get or set the socket state
  power                Current power consumption (W)
  temp                 Current temperature (°C)
  total                Total energy for current month (kWh)
  info                 Device information (model, firmware, MAC…)
  schedule             Show schedule settings (raw + recursive)
  reboot               Reboot the device (requires --force)

Environment:
  DSP_W215_IP          Default IP
  DSP_W215_PIN         Default PIN

Examples:
  $SCRIPT_NAME -i 192.168.1.50 -p 123456 state
  $SCRIPT_NAME --ip 192.168.1.50 --pin 123456 --json power
  DSP_W215_IP=192.168.1.50 DSP_W215_PIN=123456 $SCRIPT_NAME temp
  $SCRIPT_NAME -i 192.168.1.50 -p 123456 schedule

Notes:
  • The DSP-W215 is End-of-Life. Firmware is no longer updated.
  • PIN is the 6-digit code printed on the device / setup card.
  • For advanced scheduling (SetScheduleSettings) the protocol is complex;
    this client currently supports reading schedules.
EOF
}

log()  { [[ $QUIET -eq 0 ]] && echo "$*" >&2 || true; }
err()  { echo "Error: $*" >&2; }
die()  { err "$*"; exit 1; }

# Portable XML value extractor (avoids grep -P)
get_value() {
  local tag="$1" xml="$2"
  # Try the most common form first
  local val
  val=$(printf '%s' "$xml" | sed -n "s/.*<${tag}>\([^<]*\)<\/${tag}>.*/\1/p" | head -n1)
  if [[ -z "$val" ]]; then
    # Some firmwares use self-closing or different whitespace
    val=$(printf '%s' "$xml" | sed -n "s/.*<${tag}[^>]*>\([^<]*\)<\/${tag}>.*/\1/p" | head -n1)
  fi
  printf '%s' "$val"
}

xml_escape() {
  local s="$1"
  s=${s//&/&amp;}
  s=${s//</&lt;}
  s=${s//>/&gt;}
  s=${s//\"/&quot;}
  s=${s//\'/&apos;}
  printf '%s' "$s"
}

hash_hmac() {
  local data="$1" key="$2"
  # openssl + xxd is the most portable combination
  printf '%s' "$data" | openssl dgst -md5 -hmac "$key" -binary 2>/dev/null | \
    xxd -p -u 2>/dev/null || \
    printf '%s' "$data" | openssl dgst -md5 -hmac "$key" -binary 2>/dev/null | \
    od -An -tx1 | tr -d ' \n' | tr 'a-f' 'A-F'
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

COMMAND=""
STATE_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--ip)      IP="$2"; shift 2 ;;
    -p|--pin)     PIN="$2"; shift 2 ;;
    -j|--json)    JSON_OUTPUT=1; shift ;;
    -q|--quiet)   QUIET=1; shift ;;
    -f|--force)   FORCE=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    -v|--version) echo "$SCRIPT_NAME $VERSION"; exit 0 ;;
    --) shift; break ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      if [[ -z "$COMMAND" ]]; then
        COMMAND="$1"
      else
        STATE_ARG="$1"
      fi
      shift
      ;;
  esac
done

# Also accept old-style --state / --power for backward compatibility
case "${COMMAND:-}" in
  --state)  COMMAND="state"; [[ -n "${1:-}" ]] && STATE_ARG="$1" ;;
  --power)  COMMAND="power" ;;
  --temp)   COMMAND="temp" ;;
  --total)  COMMAND="total" ;;
esac

[[ -z "$COMMAND" ]] && { usage; exit 1; }
[[ -z "$IP"  ]] && die "IP address required (use -i / --ip or DSP_W215_IP)"
[[ -z "$PIN" ]] && die "PIN required (use -p / --pin or DSP_W215_PIN)"

# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------

CONTENT_TYPE='Content-Type: text/xml; charset=utf-8'
SOAP_LOGIN='SOAPAction: "http://purenetworks.com/HNAP1/Login"'

# Initial login request (Action=request)
LOGIN_REQUEST_XML='<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body><Login xmlns="http://purenetworks.com/HNAP1/"><Action>request</Action><Username>admin</Username><LoginPassword></LoginPassword><Captcha></Captcha></Login></soap:Body></soap:Envelope>'

log "Authenticating to $IP …"

xml_login_data=$(curl -sS --fail --connect-timeout 5 --max-time 15 \
  -X POST \
  -H "$CONTENT_TYPE" \
  -H "$SOAP_LOGIN" \
  --data-binary "$LOGIN_REQUEST_XML" \
  "http://${IP}/HNAP1" 2>/dev/null) || die "Cannot reach device at $IP (network or device offline)"

challenge=$(get_value Challenge "$xml_login_data")
cookie_uid=$(get_value Cookie "$xml_login_data")
public_key=$(get_value PublicKey "$xml_login_data")

[[ -z "$challenge" || -z "$cookie_uid" || -z "$public_key" ]] && \
  die "Unexpected response from device during login challenge"

cookie="Cookie: uid=${cookie_uid}"
publickey="${public_key}${PIN}"
privatekey=$(hash_hmac "$challenge" "$publickey")
password=$(hash_hmac "$challenge" "$privatekey")
timestamp=$(date +%s)

auth_str="${timestamp}\"http://purenetworks.com/HNAP1/Login\""
auth=$(hash_hmac "$auth_str" "$privatekey")
hnap_auth="HNAP_AUTH: ${auth} ${timestamp}"

SOAP_HEAD='<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body>'
SOAP_TAIL='</soap:Body></soap:Envelope>'

login_body="<Login xmlns=\"http://purenetworks.com/HNAP1/\"><Action>login</Action><Username>admin</Username><LoginPassword>${password}</LoginPassword><Captcha/></Login>"
login_payload="${SOAP_HEAD}${login_body}${SOAP_TAIL}"

xml_login=$(curl -sS --fail --connect-timeout 5 --max-time 15 \
  -X POST \
  -H "$CONTENT_TYPE" \
  -H "$SOAP_LOGIN" \
  -H "$hnap_auth" \
  -H "$cookie" \
  --data-binary "$login_payload" \
  "http://${IP}/HNAP1" 2>/dev/null) || die "Login request failed"

login_result=$(get_value LoginResult "$xml_login")
if [[ "$login_result" != "success" ]]; then
  die "Authentication failed (LoginResult=${login_result:-empty}). Check PIN and firmware."
fi

log "Authenticated successfully."

# ---------------------------------------------------------------------------
# SOAP helper – re-uses the session private key + fresh timestamp per call
# ---------------------------------------------------------------------------

soap_call() {
  local method="$1"
  local body="$2"
  local ts auth_str auth hnap_auth soap_action payload response

  ts=$(date +%s)
  auth_str="${ts}\"http://purenetworks.com/HNAP1/${method}\""
  auth=$(hash_hmac "$auth_str" "$privatekey")
  hnap_auth="HNAP_AUTH: ${auth} ${ts}"
  soap_action="SOAPAction: \"http://purenetworks.com/HNAP1/${method}\""
  payload="${SOAP_HEAD}${body}${SOAP_TAIL}"

  response=$(curl -sS --fail --connect-timeout 5 --max-time 15 \
    -X POST \
    -H "$CONTENT_TYPE" \
    -H "$soap_action" \
    -H "$hnap_auth" \
    -H "$cookie" \
    --data-binary "$payload" \
    "http://${IP}/HNAP1" 2>/dev/null) || {
      err "SOAP call $method failed"
      return 1
    }
  printf '%s' "$response"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_state() {
  local method="GetSocketSettings"
  local body="<${method} xmlns=\"http://purenetworks.com/HNAP1/\"><ModuleID>1</ModuleID></${method}>"
  local xml state

  xml=$(soap_call "$method" "$body") || return 1
  state=$(get_value OPStatus "$xml")

  if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    if [[ "$state" == "true" ]]; then
      echo '{"state":"on","raw":"true"}'
    elif [[ "$state" == "false" ]]; then
      echo '{"state":"off","raw":"false"}'
    else
      echo "{\"state\":\"unknown\",\"raw\":\"${state}\"}"
    fi
  else
    case "$state" in
      true)  echo "State is ON" ;;
      false) echo "State is OFF" ;;
      *)     echo "State is UNKNOWN ($state)" ;;
    esac
  fi
}

cmd_set_state() {
  local desired="$1"
  local opstatus nickname description method body xml result

  if [[ "$desired" == "on" ]]; then
    opstatus="true"
  elif [[ "$desired" == "off" ]]; then
    opstatus="false"
  else
    die "state argument must be 'on' or 'off'"
  fi

  # Fetch current nickname/description so we do not wipe them
  method="GetSocketSettings"
  body="<${method} xmlns=\"http://purenetworks.com/HNAP1/\"><ModuleID>1</ModuleID></${method}>"
  xml=$(soap_call "$method" "$body") || return 1
  nickname=$(get_value NickName "$xml")
  description=$(get_value Description "$xml")
  nickname=$(xml_escape "${nickname:-Socket 1}")
  description=$(xml_escape "${description:-Socket 1}")

  method="SetSocketSettings"
  body="<${method} xmlns=\"http://purenetworks.com/HNAP1/\"><ModuleID>1</ModuleID><NickName>${nickname}</NickName><Description>${description}</Description><OPStatus>${opstatus}</OPStatus></${method}>"
  xml=$(soap_call "$method" "$body") || return 1
  result=$(get_value SetSocketSettingsResult "$xml")

  if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    echo "{\"result\":\"${result}\",\"state\":\"${desired}\"}"
  else
    echo "Set state result: ${result}"
  fi
}

cmd_power() {
  local method="GetCurrentPowerConsumption"
  local body="<${method} xmlns=\"http://purenetworks.com/HNAP1/\"><ModuleID>2</ModuleID></${method}>"
  local xml power

  xml=$(soap_call "$method" "$body") || return 1
  power=$(get_value CurrentConsumption "$xml")

  if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    echo "{\"power_w\":${power:-null}}"
  else
    echo "Power: ${power} W"
  fi
}

cmd_temp() {
  local method="GetCurrentTemperature"
  local body="<${method} xmlns=\"http://purenetworks.com/HNAP1/\"><ModuleID>3</ModuleID></${method}>"
  local xml temp

  xml=$(soap_call "$method" "$body") || return 1
  temp=$(get_value CurrentTemperature "$xml")

  if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    echo "{\"temperature_c\":${temp:-null}}"
  else
    echo "Temperature: ${temp}°C"
  fi
}

cmd_total() {
  local method="GetPMWarningThreshold"
  local body="<${method} xmlns=\"http://purenetworks.com/HNAP1/\"><ModuleID>2</ModuleID></${method}>"
  local xml total

  xml=$(soap_call "$method" "$body") || return 1
  total=$(get_value TotalConsumption "$xml")

  if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    echo "{\"total_kwh\":${total:-null}}"
  else
    echo "Total: ${total} kWh"
  fi
}

cmd_info() {
  local method="GetDeviceSettings"
  local body="<${method} xmlns=\"http://purenetworks.com/HNAP1/\"></${method}>"
  local xml

  xml=$(soap_call "$method" "$body") || return 1

  if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    # Minimal JSON extraction of the most useful fields
    local model fw hw mac name
    model=$(get_value ModelName "$xml")
    fw=$(get_value FirmwareVersion "$xml")
    hw=$(get_value HardwareVersion "$xml")
    mac=$(get_value DeviceMacId "$xml")
    name=$(get_value DeviceName "$xml")
    cat <<EOF
{"model":"${model}","firmware":"${fw}","hardware":"${hw}","mac":"${mac}","name":"${name}"}
EOF
  else
    echo "Device information:"
    echo "  Name     : $(get_value DeviceName "$xml")"
    echo "  Model    : $(get_value ModelName "$xml")"
    echo "  Firmware : $(get_value FirmwareVersion "$xml")"
    echo "  Hardware : $(get_value HardwareVersion "$xml")"
    echo "  MAC      : $(get_value DeviceMacId "$xml")"
    echo "  Vendor   : $(get_value VendorName "$xml")"
  fi
}

cmd_schedule() {
  local xml1 xml2

  xml1=$(soap_call "GetScheduleSettings" '<GetScheduleSettings xmlns="http://purenetworks.com/HNAP1/"></GetScheduleSettings>') || true
  xml2=$(soap_call "GetRecursiveSchedule" '<GetRecursiveSchedule xmlns="http://purenetworks.com/HNAP1/"></GetRecursiveSchedule>') || true

  if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    # Return raw XML inside JSON strings (escaped)
    # For a real structured parser a higher-level language is better
    local esc1 esc2
    esc1=$(printf '%s' "$xml1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n')
    esc2=$(printf '%s' "$xml2" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n')
    echo "{\"GetScheduleSettings\":\"${esc1}\",\"GetRecursiveSchedule\":\"${esc2}\"}"
  else
    echo "=== GetScheduleSettings ==="
    if command -v xmllint >/dev/null 2>&1; then
      printf '%s' "$xml1" | xmllint --format - 2>/dev/null || printf '%s\n' "$xml1"
    else
      printf '%s\n' "$xml1"
    fi
    echo
    echo "=== GetRecursiveSchedule ==="
    if command -v xmllint >/dev/null 2>&1; then
      printf '%s' "$xml2" | xmllint --format - 2>/dev/null || printf '%s\n' "$xml2"
    else
      printf '%s\n' "$xml2"
    fi
  fi
}

cmd_reboot() {
  if [[ "$FORCE" -ne 1 ]]; then
    die "Reboot is destructive. Re-run with --force to confirm."
  fi
  local method="Reboot"
  local body="<${method} xmlns=\"http://purenetworks.com/HNAP1/\"></${method}>"
  local xml result

  xml=$(soap_call "$method" "$body") || return 1
  result=$(get_value RebootResult "$xml")

  if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    echo "{\"result\":\"${result}\"}"
  else
    echo "Reboot result: ${result}"
  fi
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "$COMMAND" in
  state)
    if [[ -z "$STATE_ARG" ]]; then
      cmd_state
    else
      cmd_set_state "$STATE_ARG"
    fi
    ;;
  power)    cmd_power ;;
  temp)     cmd_temp ;;
  total)    cmd_total ;;
  info)     cmd_info ;;
  schedule) cmd_schedule ;;
  reboot)   cmd_reboot ;;
  *)
    die "Unknown command: $COMMAND (try --help)"
    ;;
esac
