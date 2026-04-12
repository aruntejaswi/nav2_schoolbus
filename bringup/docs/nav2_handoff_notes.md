
ROS2 NAV2 SCHOOLBUS SYSTEM HANDOFF DOCUMENT
Generated: 2026-04-04 15:16:04.647949

===============================
SYSTEM OVERVIEW
===============================
Platform: Raspberry Pi (ARM64)
OS: Ubuntu 24.04 (Noble)
ROS2 Distribution: Jazzy

Workspace:
~/ros2_ws

Packages in workspace:
- nav2_schoolbus
- ractor_pi_launches
- kiss_icp
- imu_serial_to_ros_publisher
- mqtt_wheel_bridge
- control_tower_ros2
- ibus_reader

Sensor workspace:
~/sensor_ws (Velodyne, GNSS, etc)

===============================
NETWORK / ENVIRONMENT
===============================
Hostname: igvcrpi
User: pi
ROS_DOMAIN_ID: default (not explicitly set)

Common ROS setup:
source /opt/ros/jazzy/setup.bash
source ~/ros2_ws/install/setup.bash

===============================
CURRENT SYSTEM STATUS
===============================

WORKING COMPONENTS:
- Velodyne LiDAR publishing (~7–9 Hz)
- PointCloud → LaserScan conversion (/velodyne_scan)
- KISS-ICP odometry working (~7–8 Hz)
- TF: odom → base_footprint working
- SLAM Toolbox running and publishing /map
- map → odom transform confirmed (startup delay exists)
- Robot movement verified via teleop

PARTIALLY WORKING:
- IMU pipeline:
  /imu/data_raw exists but imu_filter sometimes reports no data
  Output: /imu/data

NOT WORKING (CURRENT BLOCKERS):
- Nav2 lifecycle activation failing
- global_costmap activation failure due to TF timing
- planner_server, controller_server stuck inactive

===============================
KEY DEBUG FINDINGS
===============================

1. Missing plugin issue (RESOLVED)
Original config used:
- spatio_temporal_voxel_layer

Not installed → caused costmap failure

Fix:
Replaced plugins with:
- obstacle_layer
- inflation_layer
- static_layer (global)

2. TF dependency issue (CURRENT BLOCKER)

Error:
"transform from base_footprint to map did not become available"

Root cause:
Nav2 activates before SLAM publishes map TF

3. Lifecycle behavior
States observed:
- unconfigured → FIXED
- inactive → CURRENT
- active → target

4. IMU mismatch
imu_filter subscribes to:
- /imu/data_raw

Publisher:
- imu_serial_publisher (verified)

But warnings still appear → intermittent issue

===============================
CURRENT TF TREE
===============================
map → odom (from SLAM)
odom → base_footprint (from KISS-ICP)
base_footprint → robot links (URDF)

===============================
TOPICS OF INTEREST
===============================

/velodyne_points      (PointCloud2)
/velodyne_scan        (LaserScan)
/kiss/odometry        (Odometry)
/odom                 (TF)
/map                  (OccupancyGrid)
/tf, /tf_static

===============================
LAUNCH FILES
===============================
~/ros2_ws/src/nav2_schoolbus/launch/

Key files:
- schoolbus.launch.py (main)
- slam_launch.py
- navigation_launch.py
- dlio.launch.py

===============================
CONFIG FILES
===============================
~/ros2_ws/src/nav2_schoolbus/config/nav2_params.yaml

Important frames:
- map
- odom
- base_footprint

===============================
RECOVERY PROCEDURE
===============================

1. Source environment
source /opt/ros/jazzy/setup.bash
source ~/ros2_ws/install/setup.bash

2. Launch system
ros2 launch nav2_schoolbus schoolbus.launch.py

3. Wait for:
- /velodyne_points active
- /kiss/odometry active
- TF odom → base_footprint valid
- TF map → odom valid

4. Verify TF:
ros2 run tf2_ros tf2_echo map odom
ros2 run tf2_ros tf2_echo odom base_footprint

5. Activate Nav2:
ros2 lifecycle set /global_costmap/global_costmap activate
ros2 lifecycle set /local_costmap/local_costmap activate
ros2 lifecycle set /planner_server activate
ros2 lifecycle set /controller_server activate

===============================
KNOWN ISSUES
===============================

- SLAM startup delay causing Nav2 activation failure
- Lifecycle manager manage_nodes call returns success=False
- IMU filter intermittent warning

===============================
RECOMMENDED NEXT STEPS
===============================

1. Add activation delay for Nav2 until SLAM TF exists
2. Verify imu_filter remapping
3. Re-enable voxel layers once stable
4. Add lifecycle debug logging

===============================
REPOSITORIES (EXPECTED)
===============================
- nav2 (Navigation2): https://github.com/ros-planning/navigation2
- slam_toolbox: https://github.com/SteveMacenski/slam_toolbox
- kiss-icp: https://github.com/PRBonn/kiss-icp

===============================
SUMMARY
===============================

System is ~90% operational.

Core stack working:
✔ Sensors
✔ Odometry
✔ SLAM
✔ TF tree

Remaining issue:
❌ Nav2 activation timing + lifecycle sequencing

This is a systems integration timing issue, not a fundamental failure.

