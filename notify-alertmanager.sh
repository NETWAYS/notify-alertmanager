#!/usr/bin/env bash

set -euo pipefail

ALERTMANAGER_URL="${ALERTMANAGER_URL:-http://localhost:9093}"
ALERTMANAGER_BASIC_AUTH=${ALERTMANAGER_BASIC_AUTH:-}
TIMEOUT=10
NOTIFICATION_TYPE=""
OBJECT_TYPE=""
HOST_NAME=""
HOST_DISPLAY_NAME=""
HOST_ADDRESS=""
STATE=""
SERVICE_NAME=""
SERVICE_DISPLAY_NAME=""
NOTIFICATION_COMMENT=""
NOTIFICATION_AUTHOR=""
CA_CERT=""
CLIENT_CERT=""
CLIENT_KEY=""
ICINGA_URL=""
EXTRA_LABELS=""
VERBOSE=0

usage() {
    cat <<EOF
Usage: notify-alertmanager.sh [OPTIONS]

Options:
  -t TYPE              Object type: host | service
  -T NOTIFICATION_TYPE Icinga notification type: PROBLEM | RECOVERY | ACKNOWLEDGEMENT | FLAPPINGSTART | FLAPPINGSTOP | DOWNTIMESTART | DOWNTIMEEND
  -H HOST_NAME         Icinga host name
  -u ALERTMANAGER_URL  Alertmanager base URL (env: ALERTMANAGER_URL)
  -U USER:PASSWORD     Basic authentication credentials (env: ALERTMANAGER_BASIC_AUTH)
  -C CERT_FILE         Client certificate file (PEM)
  -K KEY_FILE          Client private key file (PEM)
  -S CA_FILE           CA certificate file (PEM)
  -c COMMENT           Notification comment
  -a AUTHOR            Notification author
  -i ICINGA_URL        Icinga URL for the object (used in annotations)
  -l LABELS            Extra labels as comma-separated key=value pairs
  -s STATE             Object state: UP | DOWN | UNREACHABLE | OK | WARNING | CRITICAL | UNKNOWN
  -v                   Verbose output
  -h                   Show this help

Host options:
  -d DISPLAY_NAME      Host display name (optional)
  -A ADDRESS           Host address (optional)

Service options:
  -n SERVICE_NAME         Service name (required when TYPE is service)
  -N SERVICE_DISPLAY_NAME Service display name (optional)
EOF
  exit 3
}

# Parsing arguments
while getopts ":t:T:H:d:A:n:N:s:u:c:a:i:l:vhU:C:K:S:" opt; do
    case $opt in
        t) OBJECT_TYPE="$OPTARG" ;;
        T) NOTIFICATION_TYPE="$OPTARG" ;;
        H) HOST_NAME="$OPTARG" ;;
        d) HOST_DISPLAY_NAME="$OPTARG" ;;
        A) HOST_ADDRESS="$OPTARG" ;;
        n) SERVICE_NAME="$OPTARG" ;;
        N) SERVICE_DISPLAY_NAME="$OPTARG" ;;
        s) STATE="$OPTARG" ;;
        u) ALERTMANAGER_URL="$OPTARG" ;;
        U) ALERTMANAGER_BASIC_AUTH="$OPTARG" ;;
        C) CLIENT_CERT="$OPTARG" ;;
        K) CLIENT_KEY="$OPTARG" ;;
        S) CA_CERT="$OPTARG" ;;
        c) NOTIFICATION_COMMENT="$OPTARG" ;;
        a) NOTIFICATION_AUTHOR="$OPTARG" ;;
        i) ICINGA_URL="$OPTARG" ;;
        l) EXTRA_LABELS="$OPTARG" ;;
        v) VERBOSE=1 ;;
        h) usage ;;
        :) echo "ERROR: Option -$OPTARG requires an argument." >&2; usage; ;;
        \?) echo "ERROR: Unknown option -$OPTARG" >&2; usage; ;;
    esac
done

die() { echo "ERROR: $*" >&2; usage; }

# Checking for required arguments
[[ -z "$OBJECT_TYPE" ]] && die "Object type (-t) is required."
[[ -z "$NOTIFICATION_TYPE" ]] && die "Notification type (-T) is required."
[[ -z "$HOST_NAME" ]] && die "Host name (-H) is required."
[[ -z "$STATE" ]] && die "State (-s) is required"

OBJECT_TYPE="${OBJECT_TYPE,,}"
[[ "$OBJECT_TYPE" =~ ^(host|service)$ ]] || die "Object type must be 'host' or 'service'."

if [[ "$OBJECT_TYPE" == "service" ]]; then
  [[ -z "$SERVICE_NAME"  ]] && die "Service name (-n) is required for service notifications."

fi

# Determine alert state and severity
if [[ "$OBJECT_TYPE" == "service" ]]; then
  ALERTNAME="IcingaService"
else
  ALERTNAME="IcingaHost"
fi

# Simple JSON string escaping (handles quotes, backslashes, newlines)
escape_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# Build labels
build_labels_json() {
  local json
  json=$(cat <<LABELS
{
  "alertname": "$(escape_json "$ALERTNAME")",
  "icinga_host": "$(escape_json "$HOST_NAME")"
LABELS
)

  [[ -n "$HOST_ADDRESS" ]] && json+=",\n  \"icinga_host_address\": \"$(escape_json "$HOST_ADDRESS")\""
  [[ -n "$HOST_DISPLAY_NAME" ]] && json+=",\n  \"icinga_host_display_name\": \"$(escape_json "$HOST_DISPLAY_NAME")\""

  if [[ "$OBJECT_TYPE" == "service" ]]; then
    json+=",\n  \"icinga_service\": \"${SERVICE_NAME}\""
    [[ -n "$SERVICE_DISPLAY_NAME" ]] && json+=",\n  \"service_display_name\": \"$(escape_json "$SERVICE_DISPLAY_NAME")\""
  fi

  # Extra labels from -l key=value,key2=value2
  if [[ -n "$EXTRA_LABELS" ]]; then
    IFS=',' read -ra pairs <<< "$EXTRA_LABELS"
    for pair in "${pairs[@]}"; do
      local k v
      k="${pair%%=*}"
      v="${pair#*=}"
      # Basic sanitize: replace spaces with underscores in label names
      k="${k// /_}"
      json+=",\n  \"${k}\": \"${v}\""
    done
  fi

  json+="\n}"
  printf '%b' "$json"
}

build_annotations_json() {
  local summary description

  if [[ "$OBJECT_TYPE" == "service" ]]; then
    summary="${NOTIFICATION_TYPE}: ${SERVICE_DISPLAY_NAME:-$SERVICE_NAME} on ${HOST_DISPLAY_NAME:-$HOST_NAME} is ${STATE}"
    description="Service '${SERVICE_DISPLAY_NAME:-$SERVICE_NAME}' on host '${HOST_DISPLAY_NAME:-$HOST_NAME}' (${HOST_ADDRESS:-}) changed state to ${STATE}."
  else
    summary="${NOTIFICATION_TYPE}: Host ${HOST_DISPLAY_NAME:-$HOST_NAME} is ${STATE}"
    description="Host '${HOST_DISPLAY_NAME:-$HOST_NAME}' (${HOST_ADDRESS:-}) changed state to ${STATE}."
  fi

  local json
  json=$(cat <<ANNOT
{
  "summary": "$(escape_json "$summary")",
  "description": "$(escape_json "$description")"
ANNOT
)

  [[ -n "$NOTIFICATION_AUTHOR" ]] && json+=",\n  \"author\": \"$(escape_json "$NOTIFICATION_AUTHOR")\""
  [[ -n "$NOTIFICATION_COMMENT" ]] && json+=",\n  \"comment\": \"$(escape_json "$NOTIFICATION_COMMENT")\""
  [[ -n "$ICINGA_URL" ]] && json+=",\n  \"runbook_url\": \"$(escape_json "$ICINGA_URL")\""

  json+="\n}"
  printf '%b' "$json"
}

# Assemble the full payload
LABELS_JSON=$(build_labels_json)
ANNOTATIONS_JSON=$(build_annotations_json)

PAYLOAD=$(cat <<PAYLOAD
[{
  "labels": ${LABELS_JSON},
  "annotations": ${ANNOTATIONS_JSON}
PAYLOAD
       )

# Depending on the type we either set the startsAt or endsAt value
# Mapping Icinga notification types to alert status
is_resolved() {
    local state="${1^^}"
    case "$state" in
        PROBLEM|FLAPPINGSTART|DOWNTIMESTART) return 1 ;;
        RECOVERY|FLAPPINGSTOP|DOWNTIMEEND) return 0 ;;
        *) return 1 ;;
    esac
}

NOW_RFC3339=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if is_resolved "${NOTIFICATION_TYPE^^}"; then
    PAYLOAD+=",\"endsAt\": \"$(escape_json "$NOW_RFC3339")\""
else
    PAYLOAD+=",\"startsAt\": \"$(escape_json "$NOW_RFC3339")\""
fi

PAYLOAD+="}]"

ENDPOINT="${ALERTMANAGER_URL%/}/api/v2/alerts"

if [[ "$VERBOSE" -eq 1 ]]; then
  echo "Alertmanager endpoint: $ENDPOINT"
  echo "Notification type: $NOTIFICATION_TYPE"
  echo "Object type: $OBJECT_TYPE"
  echo "Payload:"
  echo "$PAYLOAD"
fi

# Sending the notification
CURL_CMD=(curl \
  --silent \
  --show-error \
  --max-time "$TIMEOUT" \
  --connect-timeout 5 \
  --write-out "\n%{http_code}" \
  --request POST \
  --header "Content-Type: application/json" \
  --data "$PAYLOAD"
)

[[ -n "$ALERTMANAGER_BASIC_AUTH" ]] && CURL_CMD+=(--user "$ALERTMANAGER_BASIC_AUTH")
[[ -n "$CLIENT_CERT" ]] && CURL_CMD+=(--cert "$CLIENT_CERT")
[[ -n "$CLIENT_KEY" ]] && CURL_CMD+=(--key "$CLIENT_KEY")
[[ -n "$CA_CERT" ]] && CURL_CMD+=(--cacert "$CA_CERT")

HTTP_RESPONSE=$("${CURL_CMD[@]}" "$ENDPOINT" 2>&1) || {
    echo "ERROR: Alertmanager unreachable at $ENDPOINT" >&2
    exit 2
}

HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed '$d')
HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n1)

if [[ "$VERBOSE" -eq 1 ]]; then
  echo "HTTP status: $HTTP_CODE"
  echo "Response: $HTTP_BODY"
fi

# Alertmanager returns 200 on success
if [[ "$HTTP_CODE" -ne 200 ]]; then
  echo "ERROR: Alertmanager returned HTTP $HTTP_CODE - $HTTP_BODY" >&2
  exit 2
fi

exit 0
