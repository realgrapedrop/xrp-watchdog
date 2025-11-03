#!/usr/bin/env bash
# XRPL Validator Health Monitor with Config Management
# Usage: ./rippled-watch.sh [options]

set -uo pipefail

# ============================================================================
# CONFIGURATION MANAGEMENT
# ============================================================================

# Get script directory and name for config file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
CONFIG_FILE="${SCRIPT_DIR}/${SCRIPT_NAME}.conf"

# Default values
DEFAULT_INTERVAL=5
DEFAULT_CONTAINER="rippledvalidator"
DEFAULT_HTTP_PORT=5005
DEFAULT_WS_PORT=6006
DEFAULT_PEER_PORT=51235
DEFAULT_DEPLOYMENT="docker"  # docker or native

# Load or create config
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        return 0
    else
        return 1
    fi
}

save_config() {
    cat > "$CONFIG_FILE" << EOF
# Rippled Watch Configuration
# Generated: $(date)

# Deployment type: docker or native
DEPLOYMENT="$DEPLOYMENT"

# Container name (only used if DEPLOYMENT=docker)
CONTAINER="$CONTAINER"

# Refresh interval (seconds)
INTERVAL=$INTERVAL

# Rippled ports
HTTP_PORT=$HTTP_PORT
WS_PORT=$WS_PORT
PEER_PORT=$PEER_PORT

# Rippled binary path (only used if DEPLOYMENT=native)
RIPPLED_BIN="${RIPPLED_BIN:-}"

# Rippled config path (only used if DEPLOYMENT=native)
RIPPLED_CFG="${RIPPLED_CFG:-}"
EOF
    echo "Configuration saved to: $CONFIG_FILE"
}

check_rippled_local() {
    # Check for Docker containers
    if command -v docker >/dev/null 2>&1; then
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q rippled; then
            return 0
        fi
    fi
    
    # Check for native rippled process
    if pgrep -x rippled >/dev/null 2>&1; then
        return 0
    fi
    
    # Check for rippled binary
    if command -v rippled >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

prompt_config() {
    echo "================================================"
    echo "  XRPL Validator Monitor - First Run Setup"
    echo "================================================"
    echo
    
    # Check if rippled is running locally
    echo "Checking for local rippled installation..."
    if ! check_rippled_local; then
        echo
        echo "${R}ERROR: No rippled instance detected on this system.${RS}"
        echo
        echo "This monitor requires rippled to be running locally (same machine)."
        echo "Please ensure rippled is either:"
        echo "  1. Running in a Docker container, OR"
        echo "  2. Running natively as a system process"
        echo
        echo "Remote rippled monitoring is not currently supported."
        echo
        exit 1
    fi
    
    echo "${G}✓ Local rippled detected${RS}"
    echo
    echo "This will create a config file: $CONFIG_FILE"
    echo
    
    # Ask deployment type
    echo "How is rippled deployed on this system?"
    echo "  1) Docker container (default)"
    echo "  2) Native (installed directly on system)"
    echo
    read -p "Select deployment type [1]: " deploy_choice
    
    case "${deploy_choice:-1}" in
        1)
            DEPLOYMENT="docker"
            echo
            echo "${B}Docker Deployment Configuration${RS}"
            echo "─────────────────────────────────"
            
            # List available containers
            if command -v docker >/dev/null 2>&1; then
                echo
                echo "Available rippled containers:"
                docker ps --filter "name=rippled" --format '  • {{.Names}} ({{.Status}})' 2>/dev/null || echo "  (none found)"
                echo
            fi
            
            read -p "Container name [$DEFAULT_CONTAINER]: " input
            CONTAINER="${input:-$DEFAULT_CONTAINER}"
            ;;
        2)
            DEPLOYMENT="native"
            echo
            echo "${B}Native Deployment Configuration${RS}"
            echo "────────────────────────────────"
            echo
            
            # Try to find rippled binary
            if command -v rippled >/dev/null 2>&1; then
                detected_bin="$(command -v rippled)"
                echo "Detected rippled binary: $detected_bin"
                read -p "Rippled binary path [$detected_bin]: " input
                RIPPLED_BIN="${input:-$detected_bin}"
            else
                read -p "Rippled binary path [/opt/ripple/bin/rippled]: " input
                RIPPLED_BIN="${input:-/opt/ripple/bin/rippled}"
            fi
            
            # Try to find config
            for cfg_path in "/etc/opt/ripple/rippled.cfg" "/opt/ripple/etc/rippled.cfg" "$HOME/.config/ripple/rippled.cfg"; do
                if [ -f "$cfg_path" ]; then
                    detected_cfg="$cfg_path"
                    break
                fi
            done
            
            if [ -n "${detected_cfg:-}" ]; then
                echo "Detected config: $detected_cfg"
                read -p "Rippled config path [$detected_cfg]: " input
                RIPPLED_CFG="${input:-$detected_cfg}"
            else
                read -p "Rippled config path [/etc/opt/ripple/rippled.cfg]: " input
                RIPPLED_CFG="${input:-/etc/opt/ripple/rippled.cfg}"
            fi
            
            CONTAINER=""  # Not used for native
            ;;
        *)
            echo "Invalid choice. Exiting."
            exit 1
            ;;
    esac
    
    echo
    echo "${B}Port Configuration${RS}"
    echo "──────────────────"
    
    read -p "HTTP RPC Port [$DEFAULT_HTTP_PORT]: " input
    HTTP_PORT="${input:-$DEFAULT_HTTP_PORT}"
    
    read -p "WebSocket Port [$DEFAULT_WS_PORT]: " input
    WS_PORT="${input:-$DEFAULT_WS_PORT}"
    
    read -p "Peer Port [$DEFAULT_PEER_PORT]: " input
    PEER_PORT="${input:-$DEFAULT_PEER_PORT}"
    
    read -p "Refresh interval in seconds [$DEFAULT_INTERVAL]: " input
    INTERVAL="${input:-$DEFAULT_INTERVAL}"
    
    echo
    save_config
    echo
    echo "Setup complete! Starting monitor..."
    sleep 2
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Command line flags
NOCLEAR=0
JSONMODE=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --interval, -i N     Seconds between refresh (default: from config or 5)
  --container NAME     Container name (default: from config or 'rippledvalidator')
  --no-clear          Don't clear screen each tick (scrolling log)
  --json              Output JSON lines instead of TUI
  --reconfig          Re-prompt for all configuration values
  --help, -h          Show this help

Config file: $CONFIG_FILE

On first run, you'll be prompted to configure ports and settings.
Configuration is saved and reused on subsequent runs.
EOF
}

# Parse command line arguments
RECONFIG=0
while [ $# -gt 0 ]; do
    case "$1" in
        --interval|-i)
            INTERVAL="${2:-5}"
            shift
            ;;
        --container)
            CONTAINER="${2:-rippledvalidator}"
            shift
            ;;
        --no-clear)
            NOCLEAR=1
            ;;
        --json)
            JSONMODE=1
            ;;
        --reconfig)
            RECONFIG=1
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

# ============================================================================
# TERMINAL SETUP
# ============================================================================

# Colors (disabled in JSON mode)
if [ "$JSONMODE" -eq 0 ] && command -v tput >/dev/null 2>&1; then
    G=$(tput setaf 2)   # Green
    Y=$(tput setaf 3)   # Yellow
    R=$(tput setaf 1)   # Red
    B=$(tput setaf 4)   # Blue
    DIM=$(tput dim)
    BOLD=$(tput bold)
    RS=$(tput sgr0)     # Reset
else
    G=""; Y=""; R=""; B=""; DIM=""; BOLD=""; RS=""
fi

# Load config or prompt for initial setup
if [ "$RECONFIG" -eq 1 ] || ! load_config; then
    # Set defaults before prompting
    DEPLOYMENT="${DEPLOYMENT:-$DEFAULT_DEPLOYMENT}"
    CONTAINER="${CONTAINER:-$DEFAULT_CONTAINER}"
    INTERVAL="${INTERVAL:-$DEFAULT_INTERVAL}"
    HTTP_PORT="${HTTP_PORT:-$DEFAULT_HTTP_PORT}"
    WS_PORT="${WS_PORT:-$DEFAULT_WS_PORT}"
    PEER_PORT="${PEER_PORT:-$DEFAULT_PEER_PORT}"
    
    prompt_config
fi

# Ensure DEPLOYMENT is set (for old config files)
DEPLOYMENT="${DEPLOYMENT:-docker}"

# ============================================================================
# DEPENDENCIES CHECK
# ============================================================================

if ! command -v jq >/dev/null 2>&1; then
    echo >&2 "Error: 'jq' is required but not installed."
    echo >&2 "Install with: sudo apt-get install -y jq"
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo >&2 "Error: 'docker' is required but not installed."
    exit 1
fi

# ============================================================================
# SIGNAL HANDLING
# ============================================================================

cleanup() {
    [ "$JSONMODE" -eq 0 ] && echo
    [ "$JSONMODE" -eq 0 ] && echo "${DIM}Exiting... 👋${RS}"
    exit 0
}

trap cleanup INT TERM

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

check_container() {
    if [ "$DEPLOYMENT" = "docker" ]; then
        docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null | grep -Eq 'running|restarting'
    else
        # For native, check if rippled process is running
        pgrep -x rippled >/dev/null 2>&1
    fi
}

rpc_json() {
    local cmd="$1"
    
    if [ "$DEPLOYMENT" = "docker" ]; then
        docker exec -i "$CONTAINER" sh -lc '
            RV=$(command -v rippled || command -v /opt/ripple/bin/rippled || command -v /usr/local/bin/rippled)
            CFG=/opt/ripple/etc/rippled.cfg
            [ -f "$CFG" ] || CFG=/etc/opt/ripple/rippled.cfg
            [ -x "$RV" ] && "$RV" --conf "$CFG" -q '"$cmd"'
        ' 2>/dev/null || true
    else
        # Native deployment
        if [ -n "${RIPPLED_CFG:-}" ] && [ -f "$RIPPLED_CFG" ]; then
            "${RIPPLED_BIN:-rippled}" --conf "$RIPPLED_CFG" -q "$cmd" 2>/dev/null || true
        else
            "${RIPPLED_BIN:-rippled}" -q "$cmd" 2>/dev/null || true
        fi
    fi
}

json_validate_or_empty() {
    local blob="$1"
    if [ -n "$blob" ] && printf '%s' "$blob" | jq -e . >/dev/null 2>&1; then
        printf '%s' "$blob"
    else
        printf ''
    fi
}

jget() {
    local blob="$1" filt="$2" def="${3:-}"
    if [ -n "$blob" ]; then
        local out
        out="$(printf '%s' "$blob" | jq -r "$filt" 2>/dev/null || true)"
        if [ -n "$out" ] && [ "$out" != "null" ]; then
            printf '%s' "$out"
            return
        fi
    fi
    printf '%s' "$def"
}

docker_stats_json() {
    if [ "$DEPLOYMENT" = "docker" ]; then
        docker stats "$CONTAINER" --no-stream --format '{{json .}}' 2>/dev/null || true
    else
        # For native, we'll get process stats differently (implemented in main loop)
        echo ""
    fi
}

classify_health() {
    local state="$1" age="$2" lpm="$3" load="$4" p90="$5" inflight="$6" tosum="$7" peers="$8"
    local status="stable" reason="ok"

    if [ "$state" = "proposing" ] || [ "$state" = "validating" ]; then
        status="stable"
    elif [ "$state" = "full" ] || [ "$state" = "tracking" ] || [ "$state" = "connected" ] || [ "$state" = "syncing" ]; then
        status="watch"
        reason="warming or partial"
    else
        status="trouble"
        reason="offline or unknown"
    fi

    if [ "$age" -gt 20 ]; then
        status="trouble"
        reason="ledger stale"
    fi
    
    if [ "$lpm" -lt 5 ] && [ "$status" = "stable" ]; then
        status="watch"
        reason="low ledgers/min"
    fi

    awk -v x="$load" 'BEGIN{exit !(x>4)}' && {
        status="watch"
        reason="high load"
    } || true

    if [ -n "$p90" ] && [ "$p90" -gt 300 ] && [ "$status" = "stable" ]; then
        status="watch"
        reason="high p90 latency"
    fi
    
    if [ "$peers" -lt 3 ]; then
        status="trouble"
        reason="very low peers"
    fi

    if [ -n "$tosum" ] && [ "$tosum" -gt 100 ] && [ "$status" != "trouble" ]; then
        status="watch"
        reason="recent fetch timeouts"
    fi

    printf "%s|%s" "$status" "$reason"
}

# ============================================================================
# DISPLAY FUNCTIONS
# ============================================================================

# Track if this is first render
FIRST_RENDER=1

banner() {
    [ "$JSONMODE" -eq 1 ] && return
    
    # Only clear screen on first render or if --no-clear is not set and it's a big change
    if [ "$FIRST_RENDER" -eq 1 ]; then
        if [ "$NOCLEAR" -eq 0 ]; then
            command -v clear >/dev/null 2>&1 && clear || true
        fi
        FIRST_RENDER=0
    else
        # Move cursor to home position (top-left) without clearing
        tput home 2>/dev/null || true
    fi
    
    echo "${BOLD}${B}╔══════════════════════════════════════════════════════════════════════════╗${RS}"
    printf "${BOLD}${B}║${RS}%-74s${BOLD}${B}║${RS}\n" "$(printf "%*s" $(((74 + 29) / 2)) "XRPL Validator Health Monitor")"
    printf "${BOLD}${B}║${RS}${DIM}%-74s${RS}${BOLD}${B}║${RS}\n" "$(printf "%*s" $(((74 + 24) / 2)) "$(date '+%F %T %Z')")"
    echo "${BOLD}${B}╚══════════════════════════════════════════════════════════════════════════╝${RS}"
    echo
    if [ "$DEPLOYMENT" = "docker" ]; then
        printf "${DIM}Container: ${RS}%s    ${DIM}Config: ${RS}%s\n" "$CONTAINER" "$CONFIG_FILE"
    else
        printf "${DIM}Deployment: ${RS}Native    ${DIM}Config: ${RS}%s\n" "$CONFIG_FILE"
    fi
    printf "${DIM}Ports: ${RS}HTTP:%s WS:%s Peer:%s    ${DIM}Interval: ${RS}%ss\n" "$HTTP_PORT" "$WS_PORT" "$PEER_PORT" "$INTERVAL"
    echo
}

pretty_line() {
    [ "$JSONMODE" -eq 1 ] && return
    local lbl="$1" val="$2" color="${3:-$RS}"
    printf "  %-20s %s%s%s" "$lbl:" "$color" "$val" "$RS"
    tput el 2>/dev/null || true  # Clear to end of line to remove old content
    printf "\n"
}

clear_to_end() {
    # Clear from cursor to end of screen to remove any old content
    [ "$JSONMODE" -eq 0 ] && tput ed 2>/dev/null || true
}

# ============================================================================
# MAIN MONITORING LOOP
# ============================================================================

prev_seq=""
stuck_ticks=0

while true; do
    banner

    # Check if container is running
    if ! check_container; then
        if [ "$JSONMODE" -eq 1 ]; then
            jq -n --arg ts "$(date -Is)" --arg deployment "$DEPLOYMENT" \
                '{timestamp:$ts, deployment:$deployment, rippled_running:false}'
        else
            if [ "$DEPLOYMENT" = "docker" ]; then
                echo "${R}⚠ Container '$CONTAINER' is not running${RS}"
                echo
                echo "${DIM}Available containers:${RS}"
                docker ps --format '  • {{.Names}}\t{{.Status}}' || true
            else
                echo "${R}⚠ Rippled process is not running${RS}"
                echo
                echo "${DIM}Please start rippled service${RS}"
            fi
            echo
            printf "${DIM}Waiting for rippled... (Ctrl+C to quit)${RS}\n"
        fi
        sleep "$INTERVAL"
        continue
    fi

    # Get container/process metadata
    if [ "$DEPLOYMENT" = "docker" ]; then
        status_line=$(docker ps --filter "name=^${CONTAINER}$" --format '{{.Status}}' 2>/dev/null || echo "unknown")
        restarts=$(docker inspect -f '{{.RestartCount}}' "$CONTAINER" 2>/dev/null || echo "?")
        img=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER" 2>/dev/null || echo "?")
    else
        status_line="running (native)"
        restarts="n/a"
        img="native installation"
    fi

    # Fetch rippled data
    srv_json="$(json_validate_or_empty "$(rpc_json server_info)")"
    peers_json="$(json_validate_or_empty "$(rpc_json peers)")"
    cons_json="$(json_validate_or_empty "$(rpc_json consensus_info)")"
    fetch_json="$(json_validate_or_empty "$(rpc_json fetch_info)")"
    dstat="$(docker_stats_json)"

    # Check if RPC is ready
    if [ -z "$srv_json" ]; then
        if [ "$JSONMODE" -eq 1 ]; then
            jq -n --arg ts "$(date -Is)" --arg container "$CONTAINER" --arg status "$status_line" \
                '{timestamp:$ts, container:$container, status:$status, server_state:"initializing", rpc_ready:false}'
        else
            echo "${Y}⏳ Rippled RPC initializing...${RS}"
            echo
            pretty_line "Container Status" "$status_line"
            pretty_line "Image" "$img"
            echo
            printf "${DIM}Waiting for RPC to become ready... (Ctrl+C to quit)${RS}\n"
        fi
        sleep "$INTERVAL"
        continue
    fi

    # Extract rippled metrics
    state="$(jget "$srv_json" '.result.info.server_state // ""' "")"
    seq="$(jget "$srv_json" '.result.info.validated_ledger.seq // 0' 0)"
    age="$(jget "$srv_json" '.result.info.validated_ledger.age // 0' 0)"
    load="$(jget "$srv_json" '.result.info.load_factor // 1' 1)"
    pub="$(jget "$srv_json" '.result.info.pubkey_validator // ""' "")"
    comp="$(jget "$srv_json" '.result.info.complete_ledgers // ""' "")"
    converge_time="$(jget "$srv_json" '.result.info.last_close.converge_time_s // 0' 0)"
    converge_time="$(awk -v x="$converge_time" 'BEGIN{printf "%.0f", (x+0)}')"

    previous_proposers="$(jget "$cons_json" '.result.info.previous_proposers // 0' 0)"
    proposers="$(jget "$cons_json" '.result.info.proposers // 0' 0)"
    proposing="$(jget "$cons_json" '.result.info.proposing // false' false)"
    synched="$(jget "$cons_json" '.result.info.synched // false' false)"
    validating="$(jget "$cons_json" '.result.info.validating // false' false)"

    total_peers="$(jget "$peers_json" '.result.peers | length // 0' 0)"
    inbound_peers="$(jget "$peers_json" '.result.peers | map(select(.inbound==true)) | length // 0' 0)"
    outbound_peers=$((total_peers - inbound_peers))
    p90_rtt="$(jget "$peers_json" '(.result.peers | map(.latency // empty) | sort | if length>0 then .[(length-1)*90/100|floor] else null end)' "")"

    inflight="$(jget "$fetch_json" '((.result.info // {}) | (if type=="object" then (to_entries|map(.value)) else [] end) | map(select(.complete!=true)) | length) // 0' 0)"
    tosum="$(jget "$fetch_json" '((.result.info // {}) | (if type=="object" then (to_entries|map(.value)) else [] end) | map((.timeouts // 0)) | add) // 0' 0)"

    # Calculate ledgers per minute
    lpm=0
    if [ -n "$prev_seq" ] && [[ "$seq" =~ ^[0-9]+$ ]] && [[ "$prev_seq" =~ ^[0-9]+$ ]]; then
        delta=$((seq - prev_seq))
        if [ "$delta" -eq 0 ]; then
            stuck_ticks=$((stuck_ticks + 1))
        else
            stuck_ticks=0
        fi
        lpm=$((delta * 60 / INTERVAL))
    fi
    prev_seq="$seq"

    # Parse docker stats or get native process stats
    ds_cpu=""
    ds_mem=""
    ds_memperc=""
    ds_pids=""
    
    if [ "$DEPLOYMENT" = "docker" ]; then
        if [ -n "$dstat" ] && printf '%s' "$dstat" | jq -e . >/dev/null 2>&1; then
            ds_cpu="$(printf '%s' "$dstat" | jq -r '.CPUPerc // empty')"
            ds_mem="$(printf '%s' "$dstat" | jq -r '.MemUsage // empty')"
            ds_memperc="$(printf '%s' "$dstat" | jq -r '.MemPerc // empty')"
            ds_pids="$(printf '%s' "$dstat" | jq -r '.PIDs // empty')"
        fi
    else
        # Get stats for native rippled process
        rippled_pid=$(pgrep -x rippled | head -1)
        if [ -n "$rippled_pid" ]; then
            if command -v ps >/dev/null 2>&1; then
                # Get CPU and memory percentage
                ds_cpu="$(ps -p "$rippled_pid" -o %cpu= 2>/dev/null | awk '{printf "%.2f%%", $1}')"
                ds_memperc="$(ps -p "$rippled_pid" -o %mem= 2>/dev/null | awk '{printf "%.2f%%", $1}')"
                
                # Get memory in human-readable format
                if [ -f "/proc/$rippled_pid/status" ]; then
                    mem_kb=$(awk '/VmRSS:/ {print $2}' "/proc/$rippled_pid/status" 2>/dev/null || echo "0")
                    if [ "$mem_kb" -gt 0 ]; then
                        mem_mb=$((mem_kb / 1024))
                        if [ "$mem_mb" -gt 1024 ]; then
                            ds_mem="$(awk -v m="$mem_mb" 'BEGIN{printf "%.2fGiB", m/1024}')"
                        else
                            ds_mem="${mem_mb}MiB"
                        fi
                    fi
                fi
                
                # Count threads as "PIDs"
                ds_pids="$(ls /proc/$rippled_pid/task 2>/dev/null | wc -l)"
            fi
        fi
    fi

    # Health classification
    hs="$(classify_health "$state" "$age" "$lpm" "$load" "${p90_rtt:-}" "$inflight" "$tosum" "$total_peers")"
    health="${hs%%|*}"
    reason="${hs#*|}"

    # ========================================================================
    # OUTPUT
    # ========================================================================

    if [ "$JSONMODE" -eq 1 ]; then
        # JSON output mode
        jq -n \
            --arg ts "$(date -Is)" \
            --arg container "$CONTAINER" \
            --arg image "$img" \
            --arg status "$status_line" \
            --arg state "$state" \
            --arg pub "$pub" \
            --arg comp "$comp" \
            --argjson seq "$seq" \
            --argjson age "$age" \
            --argjson lpm "$lpm" \
            --argjson load "$load" \
            --argjson converge_time "$converge_time" \
            --argjson previous_proposers "$previous_proposers" \
            --argjson proposers "$proposers" \
            --argjson proposing "$([ "$proposing" = "true" ] && echo true || echo false)" \
            --argjson synched "$([ "$synched" = "true" ] && echo true || echo false)" \
            --argjson validating "$([ "$validating" = "true" ] && echo true || echo false)" \
            --argjson total_peers "$total_peers" \
            --argjson inbound_peers "$inbound_peers" \
            --argjson outbound_peers "$outbound_peers" \
            --argjson p90_rtt "${p90_rtt:-0}" \
            --argjson inflight "$inflight" \
            --argjson timeouts "$tosum" \
            --arg health "$health" \
            --arg reason "$reason" \
            --arg ds_cpu "$ds_cpu" \
            --arg ds_mem "$ds_mem" \
            --arg ds_memperc "$ds_memperc" \
            --arg ds_pids "$ds_pids" \
            '{
                timestamp:$ts, container:$container, image:$image, status:$status,
                server_state:$state, rpc_ready:true,
                validator_pubkey:$pub, complete_ledgers:$comp,
                ledger_seq:$seq, ledger_age_s:$age, ledgers_per_min:$lpm,
                load_factor:$load, converge_time_s:$converge_time,
                previous_proposers:$previous_proposers, proposers:$proposers,
                proposing:$proposing, synced:$synched, validating:$validating,
                peers:{total:$total_peers, inbound:$inbound_peers, outbound:$outbound_peers, p90_rtt_ms:$p90_rtt},
                fetch:{inflight_ledgers:$inflight, recent_timeouts:$timeouts},
                docker:{cpu:$ds_cpu, mem:$ds_mem, mem_perc:$ds_memperc, pids:$ds_pids},
                health:{status:$health, reason:$reason}
            }'
    else
        # TUI output mode
        printf "─────────────────────────── ${BOLD}Container Info${RS} ───────────────────────────"; tput el 2>/dev/null || true; printf "\n"
        pretty_line "Image" "$img"
        pretty_line "Status" "$status_line"
        pretty_line "Restarts" "$restarts"
        tput el 2>/dev/null || true; printf "\n"

        printf "──────────────────────────── ${BOLD}Ledger Info${RS} ────────────────────────────"; tput el 2>/dev/null || true; printf "\n"
        pretty_line "Sequence" "$seq"
        pretty_line "Age" "${age}s"
        pretty_line "Ledgers/min" "$lpm"
        pretty_line "Complete Ledgers" "$comp"
        tput el 2>/dev/null || true; printf "\n"

        printf "─────────────────────────── ${BOLD}Network Info${RS} ───────────────────────────"; tput el 2>/dev/null || true; printf "\n"
        pretty_line "Server State" "$state"
        pretty_line "Peers" "$total_peers (in:$inbound_peers / out:$outbound_peers)"
        pretty_line "P90 RTT" "${p90_rtt:--} ms"
        tput el 2>/dev/null || true; printf "\n"

        printf "──────────────────────────── ${BOLD}Consensus${RS} ─────────────────────────────"; tput el 2>/dev/null || true; printf "\n"
        pretty_line "Proposing" "$proposing"
        pretty_line "Validating" "$validating"
        pretty_line "Synced" "$synched"
        pretty_line "Proposers" "$proposers"
        pretty_line "Previous Proposers" "$previous_proposers"
        pretty_line "Converge Time" "${converge_time}s"
        tput el 2>/dev/null || true; printf "\n"

        printf "────────────────────────── ${BOLD}Performance${RS} ────────────────────────────"; tput el 2>/dev/null || true; printf "\n"
        pretty_line "Load Factor" "$load"
        pretty_line "Inflight Ledgers" "$inflight"
        pretty_line "Recent Timeouts" "$tosum"
        tput el 2>/dev/null || true; printf "\n"

        printf "──────────────────────────── ${BOLD}Resources${RS} ─────────────────────────────"; tput el 2>/dev/null || true; printf "\n"
        [ -n "$ds_cpu" ] && pretty_line "CPU Usage" "$ds_cpu"
        [ -n "$ds_mem" ] && pretty_line "Memory" "$ds_mem"
        [ -n "$ds_memperc" ] && pretty_line "Memory %" "$ds_memperc"
        [ -n "$ds_pids" ] && pretty_line "PIDs" "$ds_pids"
        tput el 2>/dev/null || true; printf "\n"

        printf "────────────────────────────── ${BOLD}Health${RS} ──────────────────────────────"; tput el 2>/dev/null || true; printf "\n"
        case "$health" in
            stable)
                printf "  %s✅ STABLE%s - %s" "$G" "$RS" "$reason"; tput el 2>/dev/null || true; printf "\n"
                ;;
            watch)
                printf "  %s⚠️  WATCH%s - %s" "$Y" "$RS" "$reason"; tput el 2>/dev/null || true; printf "\n"
                ;;
            trouble)
                printf "  %s❌ TROUBLE%s - %s" "$R" "$RS" "$reason"; tput el 2>/dev/null || true; printf "\n"
                ;;
        esac
        tput el 2>/dev/null || true; printf "\n"

        [ -n "$pub" ] && [ "$pub" != "null" ] && { printf "${DIM}Validator: %s${RS}" "$pub"; tput el 2>/dev/null || true; printf "\n"; }
        tput el 2>/dev/null || true; printf "\n"
        printf "${DIM}Auto-refresh every %ss • Ctrl+C to exit • --help for options${RS}" "$INTERVAL"; tput el 2>/dev/null || true; printf "\n"

        # Clear any remaining content from previous renders
        clear_to_end
    fi

    sleep "$INTERVAL"
done
