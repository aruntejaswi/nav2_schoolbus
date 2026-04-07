# Schoolbus Robot — Startup Guide

This guide walks you through starting the Schoolbus autonomous robot from scratch.
It is written for students who are new to ROS2 and robotics.

---

## What Is This Robot?

The Schoolbus is an autonomous ground vehicle. It uses a combination of sensors
to understand its environment and navigate through it without a human driver.

Here is what each piece of hardware does:

| Hardware | What It Does |
|---|---|
| **Velodyne VLP-16 LiDAR** | Spins 360° and fires lasers to measure distances to walls, objects, and obstacles. Produces a 3D point cloud 10 times per second. |
| **BNO085 IMU** | Measures the robot's orientation (which way it is tilting/rotating). Runs at ~100 Hz. |
| **Raspberry Pi 4** (`igvcrpi`, 192.168.0.3) | The robot's onboard computer. Reads sensors and computes odometry (where the robot is). |
| **Robot Laptop** (`actor-2`, 192.168.0.22) | A more powerful machine connected by ethernet. Runs SLAM and the full Nav2 navigation stack. |
| **RC Receiver + Joystick** | Lets a human driver take manual control. Safety override. |
| **Motor Controllers** | Four wheels driven by ESCs (Electronic Speed Controllers). Double Ackermann steering. |

---

## Key Concepts

Before running commands, it helps to know what the software is doing.

**ROS2 (Robot Operating System 2)** is a framework where different programs
(called *nodes*) communicate by publishing and subscribing to *topics*.
Think of topics like radio channels — one node broadcasts, others listen.

**TF (Transform Tree)** is how ROS2 tracks where every part of the robot is in
3D space. Every sensor and wheel has a *frame* (a coordinate system attached to
it). ROS2 constantly publishes the relationships between frames. If the TF tree
has a gap, navigation breaks.

```
map  →  odom  →  base_footprint  →  base_link  →  sensors/wheels
 ↑          ↑           ↑
SLAM     KISS-ICP     URDF (robot description)
```

**KISS-ICP** is the odometry engine. It compares consecutive LiDAR scans to
figure out how far the robot has moved. Output: `/kiss/odometry` (~10 Hz).

**EKF (Extended Kalman Filter)** fuses the LiDAR odometry and IMU data into a
smooth, reliable position estimate. Output: `/odometry/local` (~15 Hz).

**SLAM Toolbox** builds a map of the environment while simultaneously figuring
out where the robot is in that map. Output: `/map`.

**Nav2** is the navigation stack. It uses the map and odometry to plan paths and
send velocity commands to the motors.

---

## Hardware Checklist (Before Touching a Computer)

1. Velodyne LiDAR is spinning (you will hear it whirring, see the top unit rotating)
2. Robot battery is connected and powered on
3. E-stop on the joystick is **engaged** (motors disabled) — disengage only when ready to drive
4. Pi and laptop are connected via ethernet cable
5. Your computer is on the same Wi-Fi network as the robot (or connected by ethernet)

---

## Startup Sequence

You need **four terminal windows**. Open them before you start.

### Step 1 — Pi: Start the Velodyne LiDAR

```bash
ssh pi@192.168.0.3
source /opt/ros/jazzy/setup.bash && source ~/sensor_ws/install/setup.bash
ros2 launch velodyne velodyne-all-nodes-VLP16-launch.py
```

**Verify it worked** (in a new Pi terminal):
```bash
source /opt/ros/jazzy/setup.bash && source ~/sensor_ws/install/setup.bash
export ROS_DOMAIN_ID=99
ros2 topic hz /velodyne_points
```
You should see: `average rate: 10.xxx` — the LiDAR publishing 10 scans per second.

---

### Step 2 — Pi: Start Sensors and Odometry

```bash
ssh pi@192.168.0.3
source /opt/ros/jazzy/setup.bash && source ~/ros2_ws/install/setup.bash
export ROS_DOMAIN_ID=99
ros2 launch nav2_schoolbus schoolbus.launch.py nav2:=false odometry:=false
```

> **Why `odometry:=false`?** KISS-ICP and EKF now run on the laptop to reduce Pi
> CPU load. If you omit this flag, the Pi will also run odometry, creating
> duplicate TF publishers that corrupt the SLAM map.

This starts:
- `imu_serial_to_ros_publisher` — reads the BNO085 IMU from the serial port
- `imu_filter_madgwick` — filters raw IMU data into clean orientation estimates
- `robot_state_publisher` — publishes the robot's physical shape (URDF) to the TF tree

**Verify it worked** (~15 seconds after launch, in a new Pi terminal):
```bash
export ROS_DOMAIN_ID=99
source /opt/ros/jazzy/setup.bash && source ~/ros2_ws/install/setup.bash

ros2 topic hz /imu/BNO085_data       # Should show ~100 Hz
ros2 topic hz /imu/BNO085_filtered   # Should show ~100 Hz
ros2 topic info /tf_static            # Should show Publisher count: 3
```

If `/tf_static` shows `Publisher count: 0`, the robot description failed to load.
If `/imu/BNO085_data` shows no data, the IMU serial port may be disconnected.

**Check Pi CPU load:**
```bash
top -bn1 | head -5
```
With `odometry:=false`, CPU should stay well below 100%. If it's high, check for
stale processes from a previous session: `pgrep -a 'kiss_icp|ekf_node|pointcloud'`
and kill them with `kill -9 <PID>`.

---

### Step 3 — Pi: Start Motor Controls

In a separate Pi terminal:
```bash
ssh pi@192.168.0.3
source /opt/ros/jazzy/setup.bash && source ~/ros2_ws/install/setup.bash
export ROS_DOMAIN_ID=99
ros2 launch ractor_pi_launches controls.launch.py
```

This starts:
- `ibus_reader` — reads the RC joystick receiver (serial port `/dev/ttyAMA0`)
- `control_tower` — translates velocity commands into motor signals
- `mqtt_wheel_bridge` — communication bridge to the motor controllers

**Verify it worked:**
```bash
export ROS_DOMAIN_ID=99
source /opt/ros/jazzy/setup.bash && source ~/ros2_ws/install/setup.bash
ros2 topic list | grep -E "cmd_vel|ibus"
```
You should see `/cmd_vel_teleop`, `/control/cmd_vel`.

Now disengage the e-stop on the joystick — you should hear a click from the ESCs arming.
Move a joystick stick slightly. If the wheels respond, motor control is working.

> **If wheels do not respond:** power cycle the robot (battery off → wait 10 seconds → battery on → re-engage then disengage e-stop).

---

### Step 4 — Laptop: Start SLAM and Nav2

```bash
ssh dev@192.168.0.22
source /opt/ros/jazzy/setup.bash && source ~/ros2_ws/install/setup.bash
export ROS_DOMAIN_ID=99
ros2 launch nav2_schoolbus bringup_launch.py slam:=True use_composition:=False
```

Wait ~40 seconds. You will see a lot of output. Look for:
```
[lifecycle_manager_navigation]: Managed nodes are active
```

**Verify it worked:**
```bash
ssh dev@192.168.0.22
source /opt/ros/jazzy/setup.bash && source ~/ros2_ws/install/setup.bash
export ROS_DOMAIN_ID=99

ros2 topic hz /kiss/odometry         # Should show ~10 Hz (runs on laptop now)
ros2 topic hz /odometry/local        # Should show ~15 Hz (runs on laptop now)
ros2 lifecycle get /slam_toolbox       # Should show: active [3]
ros2 lifecycle get /controller_server  # Should show: active [3]
ros2 lifecycle get /planner_server     # Should show: active [3]
ros2 lifecycle get /bt_navigator       # Should show: active [3]
```

All four lifecycle nodes must show `active [3]`. If any show `inactive [2]` or
`unconfigured [1]`, see the Troubleshooting section below.

**Check for duplicate nodes** (critical — duplicates corrupt SLAM):
```bash
ros2 node list | grep -c ekf_filter_node_odom   # Must be exactly 1
ros2 node list | grep -c kiss                    # Must be exactly 1
```

---

## Visualizing with RViz

Run this on the **laptop** (requires a display):
```bash
source /opt/ros/jazzy/setup.bash && source ~/ros2_ws/install/setup.bash
export ROS_DOMAIN_ID=99
LIBGL_ALWAYS_SOFTWARE=1 rviz2
```

In RViz, configure these displays:

| What to Add | Topic | Important Setting |
|---|---|---|
| **Fixed Frame** | set to `map` | (top of left panel) |
| **Map** | `/map` | Reliability: Best Effort |
| **LaserScan** | `/velodyne_scan` | Reliability: Best Effort, Size: 0.05 |
| **TF** | (no topic) | shows coordinate frames |

You should see a laser scan ring around the robot's position. As you drive, the map fills in.

---

## SLAM Mapping Workflow

SLAM (Simultaneous Localization and Mapping) builds a map while the robot drives.

1. Complete all four startup steps above
2. Open RViz and confirm you see the laser scan
3. Put the joystick in manual/teleop mode
4. **Drive slowly** (~0.5 m/s or less) through the environment
5. Drive a **loop** — come back close to where you started. This lets SLAM "close the loop" and correct accumulated drift
6. When the map looks good, save it immediately:

```bash
ssh dev@192.168.0.22
source /opt/ros/jazzy/setup.bash && source ~/ros2_ws/install/setup.bash
export ROS_DOMAIN_ID=99
ros2 run nav2_map_server map_saver_cli -f ~/my_map
```

This saves `my_map.pgm` (image) and `my_map.yaml` (metadata) in the home directory.

To use this map as the default next time, copy it into the package:
```bash
cp ~/my_map.pgm ~/ros2_ws/src/nav2_schoolbus/maps/nav2_map.pgm
cp ~/my_map.yaml ~/ros2_ws/src/nav2_schoolbus/maps/nav2_map.yaml
sed -i 's|image: my_map.pgm|image: nav2_map.pgm|' \
    ~/ros2_ws/src/nav2_schoolbus/maps/nav2_map.yaml
```

**Tips for a good map:**
- Drive slowly — fast motion causes LiDAR blur
- Complete a full loop back to start
- Save immediately when it looks good — SLAM keeps updating and can distort a good map

---

## Useful Commands Reference

### Check what topics are being published
```bash
ros2 topic list
```

### Check how fast a topic is publishing
```bash
ros2 topic hz /kiss/odometry
```

### Print the latest message on a topic (once)
```bash
ros2 topic echo /odometry/local --once
```

### See the full TF tree
```bash
ros2 run tf2_tools view_frames
# Creates frames.pdf in the current directory
```

### Check lifecycle state of a Nav2 node
```bash
ros2 lifecycle get /controller_server
# active [3] = running normally
# inactive [2] = configured but not started
# unconfigured [1] = not yet configured
```

### Clear the SLAM map (start fresh without restarting Nav2)
```bash
ros2 service call /slam_toolbox/clear_changes slam_toolbox/srv/Clear
```

### List all running ROS2 nodes
```bash
ros2 node list
```

---

## What Each Topic Means

| Topic | Hz | What It Contains |
|---|---|---|
| `/velodyne_points` | 10 | Raw 3D point cloud from LiDAR |
| `/velodyne_scan` | 10-30 | 2D laser scan (converted from 3D) |
| `/imu/BNO085_data` | ~100 | Raw IMU: acceleration + angular velocity |
| `/imu/BNO085_filtered` | ~100 | Filtered IMU with orientation estimate |
| `/kiss/odometry` | ~10 | Robot position estimated from LiDAR |
| `/odometry/local` | ~15 | Fused position (LiDAR + IMU via EKF) |
| `/map` | on change | SLAM-built occupancy grid map |
| `/cmd_vel` | variable | Velocity commands sent to motors |
| `/tf` | continuous | Live coordinate frame relationships |
| `/tf_static` | once | Fixed coordinate frame relationships (robot geometry) |

---

## Troubleshooting

### Nav2 nodes not active after launch
The lifecycle manager sometimes loses a race condition on startup. Check states:
```bash
ros2 lifecycle get /controller_server
```
If `inactive [2]`, kill everything and re-run Step 4. Make sure Steps 1–3 completed first.

```bash
# Kill all Nav2 on laptop
pkill -9 -f 'component_container|lifecycle_manager|controller_server|planner_server|slam_toolbox|bt_navigator'
# Wait 3 seconds, then re-run Step 4
```

### `/tf_static` has 0 publishers
The robot description (URDF) failed to load. Restart Step 2. Check for errors in the launch output related to `robot_state_publisher`.

### Robot wheels not responding to joystick
1. Check the e-stop is disengaged on the joystick (listen for ESC click)
2. Check that Step 3 (controls launch) is running
3. If still nothing: power cycle the robot hardware (battery off → 10s → battery on)

### KISS-ICP odometry is erratic or slow
KISS-ICP and EKF now run on the **laptop** (Step 4), not the Pi. If you see them
on the Pi, you launched Step 2 without `odometry:=false`. Kill stale processes:
```bash
ssh pi@192.168.0.3
pgrep -a 'kiss_icp|ekf_node|pointcloud_to_laserscan'
kill -9 <PID>   # Kill any that appear
top              # Verify CPU is back to normal
```
Then restart Step 2 with `odometry:=false`.

### Pi CPU load is high
With `odometry:=false`, the Pi should be well under 100% CPU. If it's high:
```bash
ssh pi@192.168.0.3
top -bn1 | head -15    # Check what's using CPU
ps aux --sort=-%cpu | head -10
```
Kill any stale ROS processes from previous sessions, then restart cleanly.

### IMU shows "free fall" warning
```
[WARN] [imu_filter_madgwick]: The IMU seems to be in free fall
```
This is usually harmless at startup while the IMU warms up. If it persists, check the BNO085 USB cable is connected (`ls /dev/tty_BNO085`).

### Map looks like scattered dots instead of walls
Three common causes:
1. **Odometry drift** — drive more slowly and complete a loop
2. **Pi overloaded** — check `top` for duplicate processes and kill them
3. **SLAM params wrong** — verify `max_laser_range: 10.0` and `resolution: 0.05` in `config/nav2_params.yaml`

---

## System Architecture Summary

```
Raspberry Pi (192.168.0.3)          — sensors + motor control only
├── Velodyne LiDAR  →  /velodyne_points (3D)
├── BNO085 IMU      →  /imu/BNO085_data  →  /imu/BNO085_filtered
├── robot_state_publisher  →  TF: base_footprint→base_link→sensors
└── control_tower   ←  /cmd_vel  (drives the motors)

Robot Laptop (192.168.0.22)         — odometry + SLAM + navigation
├── pointcloud_to_laserscan  →  /velodyne_scan (2D)
├── KISS-ICP        →  /kiss/odometry
├── EKF             →  /odometry/local  +  TF: odom→base_footprint
├── SLAM Toolbox    →  /map  +  TF: map→odom
└── Nav2 Stack
    ├── planner_server    (plans a path to the goal)
    ├── controller_server (follows the path, outputs /cmd_vel)
    ├── bt_navigator      (coordinates the whole behavior)
    └── collision_monitor (emergency stops)
```

---

## What to Try Next

Once the robot is mapping successfully, here are some things to explore:

- **Send a navigation goal in RViz**: use the "2D Nav Goal" button (arrow tool) and click on the map. Nav2 will plan a path and drive there autonomously.
- **Try localization mode** (no SLAM, use a saved map): `ros2 launch nav2_schoolbus bringup_launch.py slam:=False use_localization:=True`
- **Inspect the TF tree**: `ros2 run tf2_tools view_frames` — open `frames.pdf` to see the full coordinate frame hierarchy
- **Echo odometry**: `ros2 topic echo /odometry/local --once` — see the robot's estimated position and velocity
- **Watch costmaps in RViz**: add `Map` → `/local_costmap/costmap` to see how Nav2 represents obstacles near the robot
