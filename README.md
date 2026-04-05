# nav2_schoolbus

A comprehensive ROS2 Navigation2 (Nav2) integration package for the Schoolbus autonomous ground vehicle. This package provides a complete navigation stack including SLAM, localization, path planning, and collision avoidance using a Velodyne 3D LiDAR, IMU sensors, and robot-specific configurations.

## Overview

nav2_schoolbus is a launch and configuration package that assembles the Nav2 navigation framework with additional perception and state estimation nodes for the Schoolbus robot. It enables autonomous navigation through:

- **SLAM & Mapping**: Simultaneous Localization and Mapping using SLAM Toolbox with odometry from KISS-ICP (LiDAR-based odometry)
- **Localization**: AMCLs map-based localization when prior maps are available
- **Path Planning**: Nav2 planners and controllers for collision-free trajectory generation
- **Sensor Fusion**: Extended Kalman Filter (EKF) for state estimation combining LiDAR odometry and IMU data
- **Collision Avoidance**: Spatio-Temporal Voxel Layer costmap and collision monitoring
- **Sensor Processing**: PointCloud to LaserScan conversion for 2D cost mapping from 3D LiDAR data

## Requirements

### System Dependencies

- **OS:** Ubuntu 24.04 LTS
- **ROS2:** Jazzy Jalisco
- **Python:** 3.10+

### ROS2 Packages

**Core Navigation:**

- `nav2_bringup`
- `nav2_common`
- `nav2_planner`
- `nav2_controller`
- `nav2_behavior_tree`
- `nav2_smoother`
- `nav2_collision_monitor`
- `nav2_waypoint_follower`

**Perception & SLAM:**

- `slam_toolbox` - Online async SLAM implementation
- `kiss_icp` - LiDAR-inertial odometry (KISS-ICP)
- `direct_lidar_inertial_odometry` (DLIO) - Alternative LiDAR-inertial odometry
- `pointcloud_to_laserscan` - Converts 3D point clouds to 2D laser scans

**Sensor Processing:**

- `imu_filter_madgwick` - IMU filtering using Madgwick algorithm
- `robot_localization` - EKF for fusing odometry and IMU
- `tf2` - Transform management

**Robot Description:**

- `schoolbus_urdf` - Robot URDF and description package

### Installation

```bash
# Source your ROS2 environment
source /opt/ros/jazzy/setup.bash

# Install dependencies
sudo apt-get update
sudo apt-get install ros-jazzy-nav2-* ros-jazzy-slam-toolbox ros-jazzy-kiss-icp \
  ros-jazzy-imu-filter-madgwick ros-jazzy-pointcloud-to-laserscan \
  ros-jazzy-robot-localization ros-jazzy-direct-lidar-inertial-odometry
```

## Folder Structure

```txt
nav2_schoolbus/
├── launch/                 # Launch files for different modules
│   ├── bringup_launch.py            # Main bringup file - starts all navigation
│   ├── schoolbus.launch.py          # Schoolbus-specific setup (description, sensors)
│   ├── slam_launch.py               # SLAM with SLAM Toolbox
│   ├── localization_launch.py       # Map-based localization with AMCL
│   ├── navigation_launch.py         # Nav2 navigation stack (planning & control)
│   ├── dlio.launch.py               # Direct Lidar Inertial Odometry nodes
│   ├── rviz_launch.py               # RViz visualization
│   └── nav2-schoolbus.launch.py     # Combined launch entry point
├── config/                 # Configuration files (parameters)
│   ├── nav2_params.yaml             # Nav2 stack parameters (costmaps, planners, etc.)
│   ├── ekf.yaml                     # Extended Kalman Filter parameters
│   ├── imu_filter_BNO085.yaml       # IMU filter config for BNO085 sensor
│   ├── imu_filter_LSM6DSOX.yaml     # IMU filter config for LSM6DSOX sensor
│   ├── dlio_params.yaml             # DLIO odometry parameters
│   ├── dlio_config.yaml             # DLIO configuration
│   └── dlio.rviz                    # RViz configuration for DLIO
├── maps/                   # Pre-recorded maps for localization mode
│   ├── nav2_map.yaml               # Map metadata (map server config)
│   └── nav2_map.pgm                # Occupancy grid map image
├── resource/               # Package resource files
├── nav2_schoolbus/         # Python package (minimal)
│   └── __init__.py
├── package.xml             # ROS2 package metadata
├── setup.py                # Python package setup
└── README.md               # This file
```

## Launch Files & Workflows

### Main Entry Point: `bringup_launch.py`

The primary launch file that orchestrates the entire navigation stack. Supports multiple operational modes through launch arguments:

```bash
ros2 launch nav2_schoolbus bringup_launch.py \
  slam:=true \
  use_localization:=true \
  autostart:=true \
  use_sim_time:=false
```

**Launch Arguments:**

- `namespace` (default: "") - ROS namespace for all navigation nodes
- `use_namespace` (default: "false") - Apply namespace to stack
- `slam` (default: "true") - Enable SLAM mapping
- `use_localization` (default: "true") - Enable localization
- `use_sim_time` (default: "false") - Use simulation clock (for Gazebo)
- `map` (default: nav2_map.yaml path) - Pre-recorded map file for localization mode
- `params_file` (default: nav2_params.yaml) - Nav2 parameters YAML
- `autostart` (default: "true") - Auto-start lifecycle nodes
- `use_composition` (default: "true") - Use component composition for efficiency
- `use_respawn` (default: "false") - Respawn crashed nodes
- `log_level` (default: "info") - ROS logging level

### Operational Modes

#### Mode 1: SLAM (Mapping)

```bash
ros2 launch nav2_schoolbus bringup_launch.py slam:=true use_localization:=true
```

- Creates new maps while navigating
- Uses SLAM Toolbox for online mapping
- KISS-ICP provides LiDAR odometry
- Builds real-time cost maps for obstacle avoidance

#### Mode 2: Localization (Navigation with Pre-recorded Map)

```bash
ros2 launch nav2_schoolbus bringup_launch.py slam:=false use_localization:=true map:=/path/to/map.yaml
```

- Loads a pre-recorded map
- Uses AMCL for probabilistic localization
- Nav2 plans paths within known environment
- Lower computational overhead than SLAM

#### Mode 3: Schoolbus Hardware Specific

```bash
ros2 launch nav2_schoolbus schoolbus.launch.py visualize_kiss:=true
```

- Launches robot description (URDF)
- Starts sensor processing pipeline
- Pointcloud to LaserScan conversion (Velodyne 3D → 2D)
- IMU filtering for Madgwick-based orientation estimation
- KISS-ICP LiDAR odometry
- Optional visualization of KISS-ICP features

## System Architecture

```txt
Sensor Inputs
├── Velodyne 3D LiDAR (/velodyne_points)
│   └─→ PointCloud2LaserScan → /velodyne_scan (2D LaserScan)
│       └─→ KISS-ICP Odometry → /kiss/odometry
│
├── IMU Sensors (BNO085 or LSM6DSOX)
│   └─→ IMU Filter Madgwick → Filtered IMU orientation
│
└── Robot Description (URDF from schoolbus_urdf package)
    └─→ TF tree initialization

      ↓ (Sensor Fusion)
      
Extended Kalman Filter (robot_localization)
└─→ /integrated/odometry + odom → base_footprint TF

      ↓ (Navigation Select)
      
├─→ SLAM Path (slam:=true)
│   └─→ SLAM Toolbox → Map updates + Map Server
│       └─→ Local/Global Costmaps (from map + lidar)
│
└─→ Localization Path (slam:=false)
    └─→ AMCL + Map Server
        └─→ Local/Global Costmaps

           ↓ (Planning & Control)

Nav2 Stack
├─→ Global Planner (generates paths)
├─→ Local Controller (velocity commands)
├─→ Collision Monitor (emergency stops)
├─→ Behavior Server (recovery actions)
└─→ BT Navigator (behavior tree execution)

           ↓

Robot Control
└─→ Velocity Commands to Motor Controller
```

## Usage Examples

### 1. Launch Complete System with SLAM

```bash
source /opt/ros/jazzy/setup.bash
source ~/ros2_ws/install/setup.bash

# Start navigation with SLAM enabled
ros2 launch nav2_schoolbus bringup_launch.py

# In another terminal, set navigation goals
ros2 action send_goal /navigate_to_pose nav2_msgs/action/NavigateToPose \
  "{pose: {header: {frame_id: 'map'}, pose: {position: {x: 5.0, y: 3.0}, orientation: {w: 1.0}}}}}"

# View in RViz (optional)
ros2 launch nav2_schoolbus rviz_launch.py
```

### 2. Navigate with Pre-recorded Map

```bash
# Ensure map files exist in maps/ directory
ros2 launch nav2_schoolbus bringup_launch.py \
  slam:=false \
  map:=/path/to/nav2_map.yaml
```

### 3. View Sensor Data and Odometry

```bash
# Terminal 1: Start navigation
ros2 launch nav2_schoolbus schoolbus.launch.py

# Terminal 2: Visualize with RViz
ros2 launch nav2_schoolbus rviz_launch.py

# Terminal 3: Monitor odometry
ros2 topic echo /kiss/odometry
ros2 topic echo /integrated/odometry
```

### 4. Test Path Planning

```bash
# Launch navigation
ros2 launch nav2_schoolbus bringup_launch.py

# Use Nav2 CLI tools
ros2 run nav2_bringup $START_NAVIGATION_COMMAND

# Or via Python action client
python3 -c "
import rclpy
from nav2_simple_commander.robot_navigator import BasicNavigator

rclpy.init()
nav = BasicNavigator()
nav.waitUntilNav2Active()

goal = nav.getPoseStamped([5.0, 3.0], 0.0)  # x, y, yaw
nav.goToPose(goal)
"
```

---

## Quick Start: Multi-Machine Setup (Validated Configuration)

This section documents the working configuration as of April 2026. The robot Pi is too resource-constrained to run SLAM + Nav2 + sensors simultaneously, so the stack is split across two machines over wired ethernet.

### Hardware

| Machine | Role | IP | User |
|---------|------|----|------|
| Raspberry Pi (`igvcrpi`) | Velodyne LiDAR + odometry | 192.168.0.3 | pi |
| Robot laptop (`actor-2`) | SLAM Toolbox + Nav2 | 192.168.0.22 | dev |

**Prerequisites:**
- Velodyne VLP-16 spinning and connected to Pi via ethernet
- Pi and laptop connected by wired ethernet (on same 192.168.0.x subnet)
- `ROS_DOMAIN_ID=99` set in Pi's `~/.bashrc` (already configured)
- Both machines sourced: `/opt/ros/jazzy/setup.bash` + `~/ros2_ws/install/setup.bash`

---

### Startup Sequence

#### Step 1 — Pi: Velodyne sensor (`sensor_ws`)
```bash
ssh pi@192.168.0.3
source /opt/ros/jazzy/setup.bash && source ~/sensor_ws/install/setup.bash
ros2 launch velodyne velodyne-all-nodes-VLP16-launch.py
```
Verify: `ros2 topic hz /velodyne_points` → ~10 Hz

#### Step 2 — Pi: Odometry stack (`ros2_ws`)
```bash
ssh pi@192.168.0.3
source /opt/ros/jazzy/setup.bash && source ~/ros2_ws/install/setup.bash
export ROS_DOMAIN_ID=99
ros2 launch nav2_schoolbus schoolbus.launch.py nav2:=false
```
Verify after ~12s:
- `ros2 topic hz /kiss/odometry` → ~10 Hz
- `ros2 topic hz /odometry/local` → ~15 Hz

The `nav2:=false` argument runs sensors and odometry only (no Nav2). This is the Pi-side role in the split configuration.

#### Step 3 — Laptop: SLAM + Nav2
```bash
ssh dev@192.168.0.22
source /opt/ros/jazzy/setup.bash && source ~/ros2_ws/install/setup.bash
export ROS_DOMAIN_ID=99
ros2 launch nav2_schoolbus bringup_launch.py slam:=True
```
Wait ~25 seconds for:
```
[lifecycle_manager_navigation]: Managed nodes are active
```

**Note:** Use `slam:=True` (capital T) — Python launch files evaluate booleans as Python literals.

---

### SLAM Mapping Workflow

1. Complete the startup sequence above
2. Open RViz on the laptop:
   ```bash
   LIBGL_ALWAYS_SOFTWARE=1 rviz2
   ```
3. In RViz:
   - Add **LaserScan** → `/velodyne_scan` → set Reliability to **Best Effort**, Size: `0.05`
   - Add **Map** → `/map` → set Reliability to **Best Effort**
   - Set **Fixed Frame** to `map`
4. Drive the robot slowly through the environment using the RC joystick
5. Drive a **loop** back to the start — this lets SLAM close the loop and correct drift
6. Save the map immediately when it looks good:
   ```bash
   source /opt/ros/jazzy/setup.bash && source ~/ros2_ws/install/setup.bash
   export ROS_DOMAIN_ID=99
   ros2 run nav2_map_server map_saver_cli -f ~/my_map
   ```
   This produces `my_map.pgm` and `my_map.yaml`.

**Tips:**
- Drive slowly (~0.5 m/s or less)
- Save immediately when the map looks good — SLAM keeps running and can distort the map if left idle
- KISS-ICP works best outdoors or in corridors with clear wall features. Open rooms with few features cause drift.

#### KISS-ICP Indoor Tuning

For indoor use, copy `config/kiss_icp_indoor.yaml` over the default KISS-ICP config on the Pi:
```bash
cp ~/ros2_ws/src/nav2_schoolbus/config/kiss_icp_indoor.yaml \
   ~/ros2_ws/src/kiss-icp/ros/config/config.yaml
```
This sets `max_range: 10m`, `min_range: 0.5m`, `voxel_size: 0.1m` — critical for stable indoor odometry. Without this, KISS-ICP uses 1m voxels (designed for outdoor 100m range) and produces unusable odometry indoors.

---

### Known Issues and Fixes Applied

| Issue | Fix | File |
|-------|-----|------|
| Nav2 activates before KISS-ICP publishes odom TF → 60s timeout | `TimerAction(15s)` delay before navigation_launch.py | `launch/bringup_launch.py` |
| `bt_navigator` looking for `/odometry/global` (global EKF not running) | Changed `odom_topic` to `/odometry/local` | `config/nav2_params.yaml` |
| `inflation_radius` ERROR (0.45 < inscribed radius 0.647) | Raised to 0.70 in local + global costmaps | `config/nav2_params.yaml` |
| `collision_monitor` source name mismatch (`scan` vs `pointcloud`) | Renamed source block to match `observation_sources` | `config/nav2_params.yaml` |
| EKF rate failures at 30Hz on overloaded Pi | Reduced frequency to 15Hz | `config/ekf.yaml` |
| KISS-ICP publishes inverted TF (`base_footprint→odom`) conflicting with EKF | Added `publish_odom_tf: false` to KISS-ICP launch args | `launch/schoolbus.launch.py` |
| RViz `/velodyne_scan` invisible | Set Reliability to **Best Effort** in RViz display settings | (RViz config) |

---

## Maintainer and License

**License:** MIT  
**Maintainer:** Devson Butani (<dbutani@ltu.edu>)
