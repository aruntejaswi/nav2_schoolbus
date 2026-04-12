#!/usr/bin/env bash
# =============================================================================
# Schoolbus Preflight Check
# Validates all prerequisites before SLAM bringup across Pi + Laptop.
#
# Usage:
#   ./preflight.sh              Pre-launch checks only
#   ./preflight.sh --diagnose   Also check running topics, nodes, TF
#   ./preflight.sh --fix        Auto-fix safe issues (clock, SLAM files, stale procs)
#   ./preflight.sh --diagnose --fix   Both
# =============================================================================

set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# SCRIPT_DIR is the bringup/ folder inside the nav2_schoolbus repo.
# NAV2_SCHOOLBUS_DIR is the repo root (one level up).
NAV2_SCHOOLBUS_DIR="$(dirname "$SCRIPT_DIR")"

PI_HOST="pi@192.168.0.3"
PI_KEY="$HOME/.ssh/vm-to-pi-key"
LAPTOP_HOST="dev@192.168.0.22"

SSH_OPTS="-o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no -o LogLevel=ERROR"
PI_SSH="ssh $SSH_OPTS -i $PI_KEY $PI_HOST"
LAPTOP_SSH="ssh $SSH_OPTS $LAPTOP_HOST"

# ROS environment source chains for remote commands
PI_ROS_ENV="source /opt/ros/jazzy/setup.bash && source ~/sensor_ws/install/setup.bash && source ~/ros2_ws/install/setup.bash && export ROS_DOMAIN_ID=99"
LAPTOP_ROS_ENV="source /opt/ros/jazzy/setup.bash && source ~/ros2_ws/install/setup.bash && export ROS_DOMAIN_ID=99"

# Thresholds
CLOCK_DRIFT_WARN_MS=100
CLOCK_DRIFT_FAIL_MS=250
CPU_LOAD_WARN=4.0
CPU_LOAD_FAIL=6.0
VELODYNE_MIN_HZ=5

# Local repo paths (source of truth — this script lives inside the repo itself)
LOCAL_CONFIG_DIR="$NAV2_SCHOOLBUS_DIR/config"
LOCAL_LAUNCH_DIR="$NAV2_SCHOOLBUS_DIR/launch"

# Deployed paths (where the runtime actually reads from on each machine)
# Laptop: install tree is bootstrapped (regular files, NOT symlinks to src).
#         Nav2 resolves launches via get_package_share_directory("nav2_schoolbus"),
#         which points here. The old /home/dev/ros2_ws/{config,launch} paths are
#         dead parallel copies left over from an older layout — do not use them.
LAPTOP_CONFIG_DIR="/home/dev/ros2_ws/install/nav2_schoolbus/share/nav2_schoolbus/config"
LAPTOP_LAUNCH_DIR="/home/dev/ros2_ws/install/nav2_schoolbus/share/nav2_schoolbus"
# Pi: properly built with --symlink-install; src/ files ARE what runs.
PI_CONFIG_DIR="/home/pi/ros2_ws/src/nav2_schoolbus/config"
PI_LAUNCH_DIR="/home/pi/ros2_ws/src/nav2_schoolbus/launch"

# Expected nav2_schoolbus commit: both machines should be checked out at the
# same tag as the VM's copy of nav2_schoolbus. Override with EXPECTED_TAG env
# var when testing a different tag. Default derives from the current repo's
# most recent reachable tag.
EXPECTED_TAG="${EXPECTED_TAG:-}"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
DIAGNOSE=false
AUTOFIX=false
for arg in "$@"; do
    case "$arg" in
        --diagnose) DIAGNOSE=true ;;
        --fix)      AUTOFIX=true ;;
        --help|-h)
            echo "Usage: $0 [--diagnose] [--fix]"
            echo "  --diagnose  Also check running topics, nodes, lifecycle, TF"
            echo "  --fix       Auto-fix safe issues (clock sync, SLAM files, stale procs)"
            exit 0
            ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

pass() {
    echo -e "[${GREEN}PASS${NC}] $1"
    ((PASS_COUNT++))
}

warn() {
    echo -e "[${YELLOW}WARN${NC}] $1"
    if [[ -n "${2:-}" ]]; then
        echo -e "       ${BOLD}Fix:${NC} $2"
    fi
    ((WARN_COUNT++))
}

fail() {
    echo -e "[${RED}FAIL${NC}] $1"
    if [[ -n "${2:-}" ]]; then
        echo -e "       ${BOLD}Fix:${NC} $2"
    fi
    ((FAIL_COUNT++))
}

info() {
    echo -e "       $1"
}

# ---------------------------------------------------------------------------
# Check functions — Connectivity
# ---------------------------------------------------------------------------
check_ssh_pi() {
    if $PI_SSH "echo ok" &>/dev/null; then
        pass "Pi SSH connectivity (192.168.0.3)"
        return 0
    else
        fail "Pi SSH unreachable (192.168.0.3)" \
             "Check Pi power, network, or run: ssh -i $PI_KEY $PI_HOST"
        return 1
    fi
}

check_ssh_laptop() {
    if $LAPTOP_SSH "echo ok" &>/dev/null; then
        pass "Laptop SSH connectivity (192.168.0.22)"
        return 0
    else
        fail "Laptop SSH unreachable (192.168.0.22)" \
             "Check laptop power, network, or run: ssh $LAPTOP_HOST"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Check functions — Pi Health
# ---------------------------------------------------------------------------
VELODYNE_SERVICE_OK=false

check_velodyne_service() {
    local status
    status=$($PI_SSH "systemctl is-active ractor-sensors.service" 2>/dev/null) || true
    if [[ "$status" == "active" ]]; then
        pass "Velodyne systemd service (ractor-sensors) active"
        VELODYNE_SERVICE_OK=true
    else
        fail "Velodyne systemd service is '$status'" \
             "ssh $PI_HOST 'sudo systemctl start ractor-sensors.service'"
    fi
}

check_velodyne_topic() {
    if ! $VELODYNE_SERVICE_OK; then
        info "Skipping Velodyne topic check (service not active)"
        return
    fi

    local hz_output
    hz_output=$(timeout 20 $PI_SSH "bash -c '$PI_ROS_ENV && timeout 15 ros2 topic hz /velodyne_points --window 3 2>&1'" 2>/dev/null) || true

    local rate
    rate=$(echo "$hz_output" | grep -oP 'average rate: \K[0-9.]+' | tail -1 || echo "0")
    [[ -z "$rate" ]] && rate="0"

    if (( $(echo "$rate > $VELODYNE_MIN_HZ" | bc -l 2>/dev/null || echo 0) )); then
        pass "Velodyne /velodyne_points publishing at ${rate} Hz"
    elif [[ "$rate" == "0" ]]; then
        fail "Velodyne /velodyne_points not publishing (no data in 10s)" \
             "ssh $PI_HOST 'sudo systemctl restart ractor-sensors.service'"
    else
        warn "Velodyne /velodyne_points low rate: ${rate} Hz (expected >$VELODYNE_MIN_HZ)"
    fi
}

check_stale_processes() {
    local procs
    procs=$($PI_SSH "pgrep -a 'imu_publisher_node|kiss_icp|ekf_node|pointcloud_to_laserscan|madgwick'" 2>/dev/null) || true

    if [[ -z "$procs" ]]; then
        pass "No stale ROS processes on Pi"
    else
        local pids
        pids=$(echo "$procs" | awk '{print $1}' | tr '\n' ' ')
        local fix_cmd="ssh -i $PI_KEY $PI_HOST 'kill -9 $pids'"

        if $AUTOFIX; then
            $PI_SSH "kill -9 $pids" 2>/dev/null || true
            pass "Killed stale processes on Pi (was: $pids)"
        else
            warn "Stale ROS processes on Pi:" "$fix_cmd"
            echo "$procs" | while read -r line; do
                info "  $line"
            done
        fi
    fi
}

check_clock_drift() {
    # Use chrony's own measurements — far more accurate than SSH round-trip estimation.
    # Both machines run chrony syncing to NTP. We check each machine's offset from NTP.
    local pi_offset laptop_offset

    laptop_offset=$($LAPTOP_SSH "chronyc tracking 2>/dev/null | grep 'System time' | grep -oP '[0-9]+\.[0-9]+'" 2>/dev/null) || laptop_offset=""
    pi_offset=$($PI_SSH "chronyc tracking 2>/dev/null | grep 'System time' | grep -oP '[0-9]+\.[0-9]+'" 2>/dev/null) || pi_offset=""

    if [[ -z "$laptop_offset" || -z "$pi_offset" ]]; then
        # Fallback: check if chrony is running at all
        local laptop_chrony pi_chrony
        laptop_chrony=$($LAPTOP_SSH "systemctl is-active chrony" 2>/dev/null) || laptop_chrony="unknown"
        pi_chrony=$($PI_SSH "systemctl is-active chrony" 2>/dev/null) || pi_chrony="unknown"

        if [[ "$laptop_chrony" != "active" || "$pi_chrony" != "active" ]]; then
            fail "Chrony not active (laptop: $laptop_chrony, Pi: $pi_chrony)" \
                 "Install and enable chrony on both machines"
        else
            warn "Could not read chrony offset (chrony may still be syncing)"
        fi
        return
    fi

    # Both offsets are relative to NTP — worst case drift is their sum
    local max_offset_ms
    max_offset_ms=$(echo "($laptop_offset + $pi_offset) * 1000" | bc -l | cut -d. -f1)
    [[ -z "$max_offset_ms" ]] && max_offset_ms=0

    local fix_cmd="sudo chronyc makestep (on both machines)"

    if (( max_offset_ms < CLOCK_DRIFT_WARN_MS )); then
        pass "Clock sync: laptop ${laptop_offset}s, Pi ${pi_offset}s from NTP (combined: ${max_offset_ms}ms)"
    elif (( max_offset_ms < CLOCK_DRIFT_FAIL_MS )); then
        warn "Clock sync: combined offset ${max_offset_ms}ms (laptop: ${laptop_offset}s, Pi: ${pi_offset}s)" "$fix_cmd"
    else
        fail "Clock sync: combined offset ${max_offset_ms}ms (laptop: ${laptop_offset}s, Pi: ${pi_offset}s)" "$fix_cmd"
    fi
}

check_imu_device() {
    if $PI_SSH "test -e /dev/tty_BNO085" 2>/dev/null; then
        pass "IMU device /dev/tty_BNO085 present"
    else
        fail "IMU device /dev/tty_BNO085 not found" \
             "Check IMU USB connection on Pi"
    fi
}

check_pi_cpu() {
    local loadavg
    loadavg=$($PI_SSH "cat /proc/loadavg" 2>/dev/null) || { fail "Could not read Pi CPU load"; return; }

    local load1
    load1=$(echo "$loadavg" | awk '{print $1}')

    if (( $(echo "$load1 < $CPU_LOAD_WARN" | bc -l) )); then
        pass "Pi CPU load: $load1 (1-min avg, max: $CPU_LOAD_WARN)"
    elif (( $(echo "$load1 < $CPU_LOAD_FAIL" | bc -l) )); then
        warn "Pi CPU load: $load1 (1-min avg, threshold: $CPU_LOAD_WARN)" \
             "Check for runaway processes: ssh -i $PI_KEY $PI_HOST 'top -bn1 | head -15'"
    else
        fail "Pi CPU load: $load1 (1-min avg, critical threshold: $CPU_LOAD_FAIL)" \
             "ssh -i $PI_KEY $PI_HOST 'top -bn1 | head -15'"
    fi
}

check_rc_receiver() {
    local hz_output
    hz_output=$(timeout 20 $PI_SSH "bash -c '$PI_ROS_ENV && timeout 15 ros2 topic hz /control/ch1 --window 3 2>&1'" 2>/dev/null) || true

    local rate
    rate=$(echo "$hz_output" | grep -oP 'average rate: \K[0-9.]+' | tail -1 || echo "0")
    [[ -z "$rate" ]] && rate="0"

    if (( $(echo "$rate > 0" | bc -l 2>/dev/null || echo 0) )); then
        pass "RC receiver publishing /control/ch1 at ${rate} Hz"
    else
        warn "RC receiver not publishing /control/ch1 (teleop won't work)" \
             "Power cycle the robot to reset the RC receiver"
    fi
}

# ---------------------------------------------------------------------------
# Check functions — Laptop Health
# ---------------------------------------------------------------------------
check_dds_shm() {
    local shm_files
    shm_files=$($LAPTOP_SSH "ls /dev/shm/fastrtps_* /dev/shm/Fast* 2>/dev/null" 2>/dev/null) || true

    if [[ -z "$shm_files" ]]; then
        pass "No stale DDS shared memory on laptop"
    else
        local count
        count=$(echo "$shm_files" | wc -l)
        local fix_cmd="ssh $LAPTOP_HOST 'rm -rf /dev/shm/fastrtps_* /dev/shm/Fast*'"

        if $AUTOFIX; then
            $LAPTOP_SSH "rm -rf /dev/shm/fastrtps_* /dev/shm/Fast*" 2>/dev/null || true
            pass "Cleared $count stale DDS shared memory files on laptop"
        else
            warn "$count stale DDS shared memory files on laptop (causes startup errors)" "$fix_cmd"
        fi
    fi
}

check_slam_session_files() {
    local files
    files=$($LAPTOP_SSH "ls /tmp/slam_toolbox_*.posegraph /tmp/slam_toolbox_*.data 2>/dev/null" 2>/dev/null) || true

    # Also check the maps directory
    local map_files
    map_files=$($LAPTOP_SSH "ls ~/ros2_ws/src/nav2_schoolbus/maps/slam_session.posegraph ~/ros2_ws/src/nav2_schoolbus/maps/slam_session.data 2>/dev/null" 2>/dev/null) || true

    local all_files="${files}${map_files}"

    if [[ -z "$all_files" ]]; then
        pass "No stale SLAM session files"
    else
        local fix_cmd="ssh $LAPTOP_HOST 'rm -f /tmp/slam_toolbox_*.posegraph /tmp/slam_toolbox_*.data ~/ros2_ws/src/nav2_schoolbus/maps/slam_session.posegraph ~/ros2_ws/src/nav2_schoolbus/maps/slam_session.data'"

        if $AUTOFIX; then
            $LAPTOP_SSH "rm -f /tmp/slam_toolbox_*.posegraph /tmp/slam_toolbox_*.data ~/ros2_ws/src/nav2_schoolbus/maps/slam_session.posegraph ~/ros2_ws/src/nav2_schoolbus/maps/slam_session.data" 2>/dev/null || true
            pass "Cleared stale SLAM session files"
        else
            warn "SLAM session files found (will reload old map on launch):" "$fix_cmd"
            echo "$all_files" | while read -r f; do
                [[ -n "$f" ]] && info "  $f"
            done
        fi
    fi
}

check_ros_domain_id() {
    local pi_ok=false laptop_ok=false

    if $PI_SSH "grep -q 'ROS_DOMAIN_ID=99' ~/.bashrc" 2>/dev/null; then
        pi_ok=true
    fi
    if $LAPTOP_SSH "grep -q 'ROS_DOMAIN_ID=99' ~/.bashrc" 2>/dev/null; then
        laptop_ok=true
    fi

    if $pi_ok && $laptop_ok; then
        pass "ROS_DOMAIN_ID=99 in .bashrc on both machines"
    else
        local missing=""
        $pi_ok || missing="Pi"
        $laptop_ok || missing="${missing:+$missing + }Laptop"
        fail "ROS_DOMAIN_ID=99 missing from .bashrc on: $missing" \
             "echo 'export ROS_DOMAIN_ID=99' >> ~/.bashrc (on each missing machine)"
    fi
}

# Verify the packages that bringup_launch.py resolves at launch time are actually
# discoverable in the laptop's ROS environment. This catches the 2026-04-12 failure
# mode where kiss_icp was missing from ~/ros2_ws/install/ because the workspace is
# bootstrapped rather than built — bringup would crash with PackageNotFoundError.
check_laptop_launch_packages() {
    # Packages the laptop's bringup actually resolves at launch time:
    #   - nav2_schoolbus, kiss_icp, slam_toolbox: via get_package_share_directory() in
    #     bringup_launch.py/slam_launch.py
    #   - nav2_smac_planner, nav2_controller, nav2_planner: loaded by pluginlib from YAML
    # schoolbus_urdf is NOT in this list — it's a Pi-only dep (robot_state_publisher).
    local required=(kiss_icp nav2_schoolbus slam_toolbox nav2_smac_planner nav2_controller nav2_planner)
    local missing=()
    local ok=()

    for pkg in "${required[@]}"; do
        if $LAPTOP_SSH "bash -c '$LAPTOP_ROS_ENV && ros2 pkg prefix $pkg &>/dev/null'" 2>/dev/null; then
            ok+=("$pkg")
        else
            missing+=("$pkg")
        fi
    done

    if (( ${#missing[@]} == 0 )); then
        pass "Laptop launch-time packages resolvable: ${ok[*]}"
    else
        # kiss_icp has a specific recovery via backup workspace copy
        local fix_hint="See feedback_laptop_kiss_icp_gotcha memory. Quick fix for kiss_icp:"
        fix_hint="$fix_hint ssh $LAPTOP_HOST 'cp -r \"/home/dev/Documents/ros2_ws WORKING/install/kiss_icp\" /home/dev/ros2_ws/install/kiss_icp'"
        fail "Laptop missing packages bringup needs: ${missing[*]}" "$fix_hint"
    fi
}

# Warn if the legacy /home/dev/ros2_ws/config and /launch dirs exist and drift from
# the runtime-authoritative install paths. Those parallel copies are dead — scping
# to them used to be the preflight --fix behavior, which silently deployed to the
# wrong location. Flag so nobody is confused by which file is "current".
check_laptop_legacy_config_dirs() {
    local legacy_config_count
    legacy_config_count=$($LAPTOP_SSH "ls /home/dev/ros2_ws/config/*.yaml 2>/dev/null | wc -l" 2>/dev/null || echo "0")
    [[ -z "$legacy_config_count" ]] && legacy_config_count=0

    if (( legacy_config_count == 0 )); then
        pass "No legacy /home/dev/ros2_ws/config dir (clean workspace)"
    else
        warn "Legacy /home/dev/ros2_ws/config dir has $legacy_config_count yaml files — NOT used by runtime" \
             "These are dead copies. The authoritative path is $LAPTOP_CONFIG_DIR. Consider removing: ssh $LAPTOP_HOST 'rm -rf /home/dev/ros2_ws/config /home/dev/ros2_ws/launch'"
    fi
}

# ---------------------------------------------------------------------------
# Check functions — Commit Drift (nav2_schoolbus git state on each machine)
#
# Replaces the old md5-based config/launch file drift check and its scp-deploy
# --fix path. Both machines should be checked out at the same nav2_schoolbus
# tag, symlink-built via colcon. If not, --fix runs `git fetch + git checkout
# + colcon build --symlink-install --packages-select nav2_schoolbus` on the
# drifted machine. Git is the deploy mechanism; scp no longer touches code.
# ---------------------------------------------------------------------------
check_commit_drift() {
    # Resolve the expected tag. Precedence:
    #   1. EXPECTED_TAG env var (explicit override)
    #   2. Latest 'v*' tag in the VM's copy of nav2_schoolbus, sorted by version
    # We intentionally do not use `git describe` — the VM's HEAD is typically on
    # an editing branch ahead of the latest release tag, so describe wouldn't
    # find anything. Picking the max v* tag gives the right answer regardless
    # of what branch the VM is on.
    local expected_tag="$EXPECTED_TAG"
    if [[ -z "$expected_tag" ]]; then
        expected_tag=$(cd "$NAV2_SCHOOLBUS_DIR" && git tag -l 'v*' | sort -V | tail -1 || true)
    fi

    if [[ -z "$expected_tag" ]]; then
        warn "No expected tag resolvable" \
             "Create a tag on $NAV2_SCHOOLBUS_DIR (e.g. git tag vYYYY.MM.DD-scenario) or set EXPECTED_TAG=<name>"
        return
    fi

    local expected_sha
    expected_sha=$(cd "$NAV2_SCHOOLBUS_DIR" && git rev-parse "$expected_tag^{commit}" 2>/dev/null || true)
    if [[ -z "$expected_sha" ]]; then
        warn "Expected tag $expected_tag not resolvable to a commit in $NAV2_SCHOOLBUS_DIR"
        return
    fi

    info "Expected: $expected_tag ($(cd "$NAV2_SCHOOLBUS_DIR" && git log -1 --format='%h %s' "$expected_sha"))"

    # nav2_schoolbus runs ONLY on the laptop. The Pi should not have it at all —
    # see check_pi_has_no_nav2_schoolbus. So this check only inspects the laptop.
    local laptop_sha
    laptop_sha=$($LAPTOP_SSH "cd ~/ros2_ws/src/nav2_schoolbus && git rev-parse HEAD 2>/dev/null" 2>/dev/null || true)

    if [[ -z "$laptop_sha" ]]; then
        warn "Laptop: cannot read git HEAD in ~/ros2_ws/src/nav2_schoolbus" \
             "Workspace may be missing or broken. See bringup/docs/COLD_BOOT.md to rebuild."
        return
    fi

    if [[ "$laptop_sha" == "$expected_sha" ]]; then
        pass "Laptop at $expected_tag"
        return
    fi

    local laptop_desc
    laptop_desc=$($LAPTOP_SSH "cd ~/ros2_ws/src/nav2_schoolbus && git log -1 --format='%h %s' 2>/dev/null" 2>/dev/null || echo "$laptop_sha")

    if $AUTOFIX; then
        info "Syncing laptop to $expected_tag..."
        # Fetch, checkout, and rebuild nav2_schoolbus only.
        # Any local uncommitted changes will block the checkout — we
        # deliberately do not stash/discard; that's a manual decision.
        if $LAPTOP_SSH "
            set -e
            cd ~/ros2_ws/src/nav2_schoolbus
            git fetch --tags origin 2>&1 | tail -5
            git checkout '$expected_tag' 2>&1
            cd ~/ros2_ws
            source /opt/ros/jazzy/setup.bash
            colcon build --symlink-install --packages-select nav2_schoolbus 2>&1 | tail -5
        " 2>&1 | sed "s/^/  [laptop] /"; then
            pass "Laptop synced to $expected_tag"
        else
            warn "Failed to sync laptop" \
                 "Check for local uncommitted changes blocking checkout"
        fi
    else
        local fix_cmd="$SCRIPT_DIR/preflight.sh --fix  (fetches $expected_tag and rebuilds nav2_schoolbus on the laptop)"
        warn "Laptop commit drift: at $laptop_desc, expected $expected_tag" "$fix_cmd"
    fi
}

# ---------------------------------------------------------------------------
# Pi cleanliness check — nav2_schoolbus should NOT be on the Pi.
#
# Nav2 and SLAM run on the laptop. The Pi only runs sensor drivers + motor
# control via ractor_pi_launches. Having nav2_schoolbus on the Pi is dead
# weight from the pre-split-machine era. Flag it so it can be removed.
# ---------------------------------------------------------------------------
check_pi_has_no_nav2_schoolbus() {
    local present
    present=$($PI_SSH "test -d ~/ros2_ws/src/nav2_schoolbus && echo yes || echo no" 2>/dev/null)

    if [[ "$present" == "no" ]]; then
        pass "Pi does not have nav2_schoolbus (correct — laptop-only package)"
    elif [[ "$present" == "yes" ]]; then
        warn "Pi has nav2_schoolbus in ~/ros2_ws/src/ — dead weight, should be removed" \
             "The Pi does not run Nav2. Remove with: ssh $PI_HOST 'rm -rf ~/ros2_ws/src/nav2_schoolbus ~/ros2_ws/build/nav2_schoolbus ~/ros2_ws/install/nav2_schoolbus'"
    else
        warn "Pi: could not determine whether nav2_schoolbus is present" \
             "Manually run: ssh $PI_HOST 'ls ~/ros2_ws/src/nav2_schoolbus'"
    fi
}

# ---------------------------------------------------------------------------
# Install-tree sanity check — catches manual scp regressions on the laptop.
#
# If someone drops a file directly into install/nav2_schoolbus/... instead of
# editing src/ and rebuilding, the install-tree symlink will point somewhere
# outside src/. Flag it immediately — that's the exact failure mode that got
# the laptop workspace into its previous broken state. Laptop only: the Pi
# doesn't have nav2_schoolbus (see check_pi_has_no_nav2_schoolbus).
# ---------------------------------------------------------------------------
check_install_tree_symlinks() {
    local marker_file="share/nav2_schoolbus/config/nav2_params.yaml"
    local laptop_resolved
    laptop_resolved=$($LAPTOP_SSH "readlink -f /home/dev/ros2_ws/install/nav2_schoolbus/$marker_file 2>/dev/null" 2>/dev/null || true)

    if [[ -z "$laptop_resolved" ]]; then
        warn "Cannot read laptop install tree marker file" \
             "Is /home/dev/ros2_ws/install/nav2_schoolbus/$marker_file missing? Rebuild with colcon."
    elif [[ "$laptop_resolved" != /home/dev/ros2_ws/src/* ]]; then
        warn "Laptop install tree is NOT a real symlink-install — $marker_file resolves to $laptop_resolved" \
             "Someone scp'd a file into install/. Rebuild from scratch: see bringup/docs/COLD_BOOT.md"
    else
        pass "Laptop install tree resolves to src/ (real symlink build)"
    fi
}

# ---------------------------------------------------------------------------
# Diagnose-mode checks — Running System
# ---------------------------------------------------------------------------
check_topic_rate() {
    local topic="$1" expected_hz="$2" machine="$3"
    local ssh_cmd ros_env

    if [[ "$machine" == "pi" ]]; then
        ssh_cmd="$PI_SSH"
        ros_env="$PI_ROS_ENV"
    else
        ssh_cmd="$LAPTOP_SSH"
        ros_env="$LAPTOP_ROS_ENV"
    fi

    local hz_output
    hz_output=$(timeout 25 $ssh_cmd "bash -c '$ros_env && timeout 20 ros2 topic hz $topic --window 3 2>&1'" 2>/dev/null) || true

    local rate
    rate=$(echo "$hz_output" | grep -oP 'average rate: \K[0-9.]+' | tail -1 || echo "0")
    [[ -z "$rate" ]] && rate="0"

    local min_hz
    min_hz=$(echo "$expected_hz * 0.5" | bc -l)

    if [[ "$rate" == "0" ]]; then
        fail "$topic not publishing"
    elif (( $(echo "$rate < $min_hz" | bc -l) )); then
        warn "$topic at ${rate} Hz (expected ~${expected_hz} Hz)"
    else
        pass "$topic at ${rate} Hz (expected ~${expected_hz} Hz)"
    fi
}

check_duplicate_nodes() {
    local node_list
    node_list=$(timeout 20 $LAPTOP_SSH "bash -c '$LAPTOP_ROS_ENV && ros2 node list 2>/dev/null'" 2>/dev/null) || true

    if [[ -z "$node_list" ]]; then
        fail "No ROS nodes visible on laptop (is the stack running?)"
        return
    fi

    local all_ok=true
    for pattern in ekf_filter_node kiss pointcloud_to_laserscan; do
        local count
        count=$(echo "$node_list" | grep -c "$pattern" || echo "0")
        if (( count == 0 )); then
            warn "Node '$pattern' not found (expected 1)"
            all_ok=false
        elif (( count > 1 )); then
            fail "Duplicate node '$pattern' — found $count instances" \
                 "Kill duplicates and relaunch"
            all_ok=false
        fi
    done

    if $all_ok; then
        pass "No duplicate nodes (ekf, kiss, pointcloud_to_laserscan: 1 each)"
    fi
}

check_lifecycle_states() {
    local all_ok=true
    for node in /slam_toolbox /controller_server; do
        local state
        state=$(timeout 10 $LAPTOP_SSH "bash -c '$LAPTOP_ROS_ENV && ros2 lifecycle get $node 2>/dev/null'" 2>/dev/null) || true

        if echo "$state" | grep -q "active \[3\]"; then
            : # good
        elif [[ -z "$state" ]]; then
            fail "Lifecycle node $node not found"
            all_ok=false
        else
            warn "Lifecycle node $node is: $state (expected: active [3])"
            all_ok=false
        fi
    done

    if $all_ok; then
        pass "Lifecycle nodes active (slam_toolbox, controller_server)"
    fi
}

check_tf_chain() {
    local tf_output
    tf_output=$(timeout 10 $LAPTOP_SSH "bash -c '$LAPTOP_ROS_ENV && timeout 5 ros2 run tf2_ros tf2_echo map base_footprint 2>&1 | head -5'" 2>/dev/null) || true

    if echo "$tf_output" | grep -q "Translation\|Transform"; then
        pass "TF chain: map -> base_footprint connected"
    else
        fail "TF chain: map -> base_footprint not available" \
             "Check SLAM Toolbox and KISS-ICP are running"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}=== Schoolbus Preflight Check ===${NC}"
echo -e "    $(date '+%Y-%m-%d %H:%M:%S')"
if $DIAGNOSE; then echo -e "    Mode: pre-launch + diagnostics"; fi
if $AUTOFIX; then echo -e "    Auto-fix: enabled"; fi
echo ""

# --- Connectivity (fail-fast: skip remaining Pi/Laptop checks if unreachable) ---
echo -e "${BOLD}--- Connectivity ---${NC}"
pi_reachable=true
laptop_reachable=true
check_ssh_pi || pi_reachable=false
check_ssh_laptop || laptop_reachable=false
echo ""

# --- Pi Health ---
if $pi_reachable; then
    echo -e "${BOLD}--- Pi Health ---${NC}"
    check_velodyne_service
    check_velodyne_topic
    check_stale_processes
    check_imu_device
    check_pi_cpu
    check_rc_receiver
    echo ""
else
    echo -e "${BOLD}--- Pi Health ---${NC}"
    info "Skipped (Pi unreachable)"
    echo ""
fi

# --- Cross-machine ---
if $pi_reachable && $laptop_reachable; then
    echo -e "${BOLD}--- Cross-machine ---${NC}"
    check_clock_drift
    check_ros_domain_id
    echo ""
fi

# --- Laptop Health ---
if $laptop_reachable; then
    echo -e "${BOLD}--- Laptop Health ---${NC}"
    check_dds_shm
    check_slam_session_files
    check_laptop_launch_packages
    check_laptop_legacy_config_dirs
    echo ""
fi

# --- Commit Drift + Pi Cleanliness ---
if $pi_reachable && $laptop_reachable; then
    echo -e "${BOLD}--- Commit Drift (nav2_schoolbus tag) ---${NC}"
    check_commit_drift
    check_pi_has_no_nav2_schoolbus
    echo ""
fi

# --- Install-tree sanity ---
if $pi_reachable && $laptop_reachable; then
    echo -e "${BOLD}--- Install tree sanity ---${NC}"
    check_install_tree_symlinks
    echo ""
fi

# --- Diagnose mode ---
if $DIAGNOSE && $laptop_reachable; then
    echo -e "${BOLD}--- Running System Diagnostics ---${NC}"
    check_topic_rate "/velodyne_scan" 10 laptop
    check_topic_rate "/kiss/odometry" 10 laptop
    check_topic_rate "/odometry/local" 15 laptop
    check_duplicate_nodes
    check_lifecycle_states
    check_tf_chain
    echo ""
fi

# --- Summary ---
echo -e "${BOLD}=== Results ===${NC}"
echo -e "    ${GREEN}$PASS_COUNT PASS${NC}, ${YELLOW}$WARN_COUNT WARN${NC}, ${RED}$FAIL_COUNT FAIL${NC}"
echo ""

if (( FAIL_COUNT > 0 )); then
    echo -e "    ${RED}Fix failures before launching.${NC}"
    exit 2
elif (( WARN_COUNT > 0 )); then
    echo -e "    ${YELLOW}Warnings present — review before launching.${NC}"
    exit 1
else
    echo -e "    ${GREEN}All checks passed. Ready to launch.${NC}"
    exit 0
fi
