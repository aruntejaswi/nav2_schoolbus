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

## Maintainer and License

**License:** MIT  
**Maintainer:** Devson Butani (<dbutani@ltu.edu>)
