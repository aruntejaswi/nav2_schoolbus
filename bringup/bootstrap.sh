#!/usr/bin/env bash
# =============================================================================
# Schoolbus workspace bootstrap
#
# One-command setup of a ROS 2 workspace for either the Pi or the laptop.
# Takes a fresh machine from "nothing" to a buildable ~/ros2_ws. Run this
# after cloning the nav2_schoolbus repo on a new machine:
#
#   git clone https://github.com/LTU-Actor/nav2_schoolbus.git
#   cd nav2_schoolbus/bringup
#   ./bootstrap.sh --target pi        # on the Raspberry Pi
#   ./bootstrap.sh --target laptop    # on the robot laptop
#
# What it does:
#   1. Installs apt packages the workspace needs (vcstool, rosdep, colcon)
#   2. Creates ~/ros2_ws/src/ if missing
#   3. Runs `vcs import` to clone every repo pinned in schoolbus-<target>.repos
#   4. Runs rosdep install to pull any extra apt deps the repos declare
#   5. Runs colcon build --symlink-install from the workspace root
#
# What it does NOT do:
#   - Source the workspace in your shell (you do that yourself)
#   - Install Nav2 itself (ros-jazzy-nav2-* apt packages) — the laptop needs
#     those; see bringup/ROBOT_DEPS.md
#   - Configure systemd services on the Pi (ractor-sensors, ractor-controls)
#
# Target-specific notes:
#   Pi target clones the 6 hardware-side repos (control_tower_ros2, ibus_reader,
#   mqtt_wheel_bridge, ractor_pi_launches, schoolbus_description,
#   imu_serial_to_ros_publisher). Does NOT clone nav2_schoolbus or kiss-icp.
#
#   Laptop target clones 3 repos (nav2_schoolbus pinned at the indoor-working
#   tag, kiss-icp, schoolbus_description for RViz). Does NOT clone the
#   hardware drivers — those live only on the Pi.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
TARGET=""
WORKSPACE="$HOME/ros2_ws"

usage() {
    cat <<EOF
Usage: $0 --target pi|laptop [--workspace PATH]

Options:
  --target pi         Bootstrap a Raspberry Pi (hardware drivers)
  --target laptop     Bootstrap the robot laptop (Nav2 + SLAM)
  --workspace PATH    Workspace root (default: ~/ros2_ws)
  -h, --help          Show this message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            TARGET="${2:-}"
            shift 2
            ;;
        --workspace)
            WORKSPACE="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ "$TARGET" != "pi" && "$TARGET" != "laptop" ]]; then
    echo "ERROR: --target must be 'pi' or 'laptop'" >&2
    usage >&2
    exit 1
fi

MANIFEST="$SCRIPT_DIR/schoolbus-${TARGET}.repos"
if [[ ! -f "$MANIFEST" ]]; then
    echo "ERROR: manifest not found: $MANIFEST" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Sanity checks before we touch the machine
# ---------------------------------------------------------------------------
if [[ ! -f /opt/ros/jazzy/setup.bash ]]; then
    echo "ERROR: ROS 2 Jazzy is not installed at /opt/ros/jazzy." >&2
    echo "       Install ROS 2 Jazzy first: https://docs.ros.org/en/jazzy/Installation.html" >&2
    exit 1
fi

echo "=============================================================================="
echo " Schoolbus bootstrap"
echo "   Target:    $TARGET"
echo "   Workspace: $WORKSPACE"
echo "   Manifest:  $MANIFEST"
echo "=============================================================================="
echo ""

# ---------------------------------------------------------------------------
# Step 1: apt packages for the bootstrap itself
# ---------------------------------------------------------------------------
echo "--- [1/5] Installing build tooling (vcstool, rosdep, colcon) ---"
sudo apt-get update
sudo apt-get install -y \
    git \
    python3-vcstool \
    python3-rosdep \
    python3-colcon-common-extensions

# ---------------------------------------------------------------------------
# Step 2: create workspace skeleton
# ---------------------------------------------------------------------------
echo ""
echo "--- [2/5] Preparing $WORKSPACE/src ---"
mkdir -p "$WORKSPACE/src"
cd "$WORKSPACE"

# ---------------------------------------------------------------------------
# Step 3: vcs import
# ---------------------------------------------------------------------------
echo ""
echo "--- [3/5] Cloning repos per $MANIFEST ---"
vcs import src < "$MANIFEST"
echo ""
echo "Cloned repos:"
ls src/

# ---------------------------------------------------------------------------
# Step 4: rosdep
# ---------------------------------------------------------------------------
echo ""
echo "--- [4/5] rosdep install ---"
if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
    sudo rosdep init || true
fi
# shellcheck disable=SC1091
source /opt/ros/jazzy/setup.bash
rosdep update
rosdep install --from-paths src --ignore-src -r -y || {
    echo ""
    echo "WARNING: rosdep could not install some packages automatically."
    echo "Review output above. You may need to 'sudo apt install' a few"
    echo "packages by hand, then re-run this script."
    exit 1
}

# ---------------------------------------------------------------------------
# Step 5: colcon build
# ---------------------------------------------------------------------------
echo ""
echo "--- [5/5] colcon build --symlink-install ---"
colcon build --symlink-install

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "=============================================================================="
echo " Bootstrap complete."
echo ""
echo " To use the workspace in your shell, add this line to ~/.bashrc (or source"
echo " it manually each session):"
echo ""
echo "     source $WORKSPACE/install/setup.bash"
echo ""
case "$TARGET" in
    pi)
        echo " Next on the Pi: install and start the systemd services."
        echo ""
        echo " ractor-robot-state.service (URDF TF tree) is shipped in this repo:"
        echo "     sudo install -m 644 $SCRIPT_DIR/systemd/ractor-robot-state.service \\"
        echo "         /etc/systemd/system/ractor-robot-state.service"
        echo "     sudo systemctl daemon-reload"
        echo "     sudo systemctl enable --now ractor-robot-state.service"
        echo ""
        echo " ractor-sensors.service and ractor-controls.service are installed"
        echo " separately (not from this repo):"
        echo "     sudo systemctl enable --now ractor-sensors.service ractor-controls.service"
        ;;
    laptop)
        echo " Next on the laptop: launch the Nav2 + SLAM stack:"
        echo "     ros2 launch nav2_schoolbus bringup_launch.py slam:=True use_localization:=True"
        echo ""
        echo " For the full cold-boot procedure, see bringup/docs/COLD_BOOT.md."
        ;;
esac
echo "=============================================================================="
