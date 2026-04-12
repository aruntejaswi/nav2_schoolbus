# Schoolbus SLAM Startup — Reproducible Steps

**Date verified:** 2026-04-11
**Commit:** `8d1f9f5` on branch `nav2-lifecycle-fix`

---

## Architecture

| Machine | IP | Role |
|---------|----|------|
| **Raspberry Pi** | 192.168.0.3 | Velodyne LiDAR (systemd), BNO085 IMU (systemd), motor controls (systemd), robot_state_publisher (manual) |
| **Laptop** | 192.168.0.22 | pointcloud_to_laserscan, KISS-ICP, EKF, SLAM Toolbox, Nav2 |

Both machines must use `ROS_DOMAIN_ID=99` in **every** terminal.

SSH to Pi: `ssh -i ~/schoolbus_handoff/vm-to-pi-key pi@192.168.0.3`
SSH to Laptop: `ssh dev@192.168.0.22`

---

## What runs on each machine

### Pi — systemd services (need `sudo` to start after power cycle)

| Service | What it launches | Notes |
|---------|-----------------|-------|
| `ractor-sensors.service` | Velodyne driver + transform, BNO085 IMU, rosboard | Auto-starts on boot but often found inactive after power cycle |
| `ractor-controls.service` | control_tower_node, mqtt_wheel_bridge | Motor control; must be running for teleop or Nav2 driving |

### Pi — manual launch (not in any service)

| Launch | What it starts | Why it's needed |
|--------|---------------|-----------------|
| `ros2 launch schoolbus_urdf schoolbus.launch.py` | robot_state_publisher, joint_state_publisher | Publishes URDF TF tree (3d_lidar_link, base_footprint, etc.). Without it, KISS-ICP and SLAM cannot function. |

### Laptop — manual launch

| Launch | What it starts | Notes |
|--------|---------------|-------|
| `ros2 launch nav2_schoolbus bringup_launch.py slam:=True use_localization:=True` | pointcloud_to_laserscan, KISS-ICP, EKF, SLAM Toolbox, Nav2 (25s delayed) | All-in-one. Nav2 activates 25s after launch to give SLAM time to publish map->odom TF. |

### What does NOT need to be launched

- **`schoolbus.launch.py`** — only for single-machine mode. In multi-machine mode, ractor-sensors handles sensors and bringup_launch.py handles odometry/SLAM/Nav2.
- **Manual Velodyne driver** — ractor-sensors handles it. Launching manually creates duplicates.
- **Manual lifecycle activation** — the autostart fix handles SLAM Toolbox and Nav2 activation automatically.

---

## Step-by-step startup

### Step 0 — Preflight check (from VM)

```bash
cd ~/schoolbus_handoff
./scripts/preflight.sh --fix
```

This checks SSH, Velodyne service, clock sync, stale processes, DDS shared memory, SLAM session files, and config drift. Auto-fixes safe issues.

### Step 1 — Start Pi services (needs sudo)

```bash
ssh -i ~/schoolbus_handoff/vm-to-pi-key pi@192.168.0.3
sudo systemctl start ractor-sensors.service ractor-controls.service
```

Verify both are active:
```bash
systemctl is-active ractor-sensors.service ractor-controls.service
# Should print "active" twice
```

### Step 2 — Launch robot_state_publisher on Pi

```bash
# Same SSH session or new one
source /opt/ros/jazzy/setup.bash && source ~/sensor_ws/install/setup.bash && source ~/ros2_ws/install/setup.bash
export ROS_DOMAIN_ID=99
ros2 launch schoolbus_urdf schoolbus.launch.py
```

This stays running. It publishes the URDF TF tree that KISS-ICP and SLAM need.

### Step 3 — Launch SLAM + Nav2 on Laptop

```bash
ssh dev@192.168.0.22
source /opt/ros/jazzy/setup.bash && source ~/ros2_ws/install/setup.bash
export ROS_DOMAIN_ID=99
ros2 launch nav2_schoolbus bringup_launch.py slam:=True use_localization:=True
```

**Important:** Use capital `True`, not lowercase `true`. The PythonExpression conditions require valid Python booleans.

Wait ~35 seconds. You should see in the log:
```
[lifecycle_manager_navigation]: Managed nodes are active
[lifecycle_manager_navigation]: Creating bond timer...
```

### Step 4 — Open RViz2

```bash
# On laptop (new terminal)
source /opt/ros/jazzy/setup.bash && source ~/ros2_ws/install/setup.bash
export ROS_DOMAIN_ID=99
rviz2
```

Set **Fixed Frame** to `map`. Add displays:
- **Map** — topic: `/map`
- **LaserScan** — topic: `/velodyne_scan`
- **TF** — verify chain: `map -> odom -> base_footprint`
- **Path** — topic: `/plan` (shows Nav2 planned path)

### Step 5 — Navigate

- Flip **Switch B** on the joystick to **auto** position (CH8=2000)
- Use **2D Goal Pose** in RViz2 to send navigation goals
- Flip Switch B back to **teleop** (CH8=1000) to take manual control at any time

---

## Deploying code changes

After pushing changes to GitHub:

### On the laptop (config and launch files)
```bash
# From VM — deploy directly via preflight
./scripts/preflight.sh --fix
# This syncs all config and launch files from the repo to both machines
```

Or manually:
```bash
scp repos/nav2_schoolbus/config/nav2_params.yaml dev@192.168.0.22:~/ros2_ws/config/
scp repos/nav2_schoolbus/launch/bringup_launch.py dev@192.168.0.22:~/ros2_ws/launch/
scp repos/nav2_schoolbus/launch/slam_launch.py dev@192.168.0.22:~/ros2_ws/launch/
```

### On the Pi (if nav2_params.yaml or schoolbus.launch.py changed)
```bash
ssh pi@192.168.0.3
cd ~/ros2_ws/src/nav2_schoolbus && git pull
cd ~/ros2_ws && source /opt/ros/jazzy/setup.bash && source ~/sensor_ws/install/setup.bash
colcon build --symlink-install --packages-select nav2_schoolbus
```

No rebuild needed for config-only changes when using symlink-install.

---

## Current tuning values (as of 2026-04-11)

| Parameter | Value | Notes |
|-----------|-------|-------|
| robot_radius | 0.35m | Allows close approach to walls indoors |
| inflation_radius | 0.3m | Total clearance: 0.65m from obstacles |
| cost_scaling_factor | 5.0 | Steep falloff — more free space in corridors |
| desired_linear_vel | 0.8 m/s | Must be >0.5 to overcome floor friction |
| min approach/regulated speed | 0.5 m/s | Robot stalls below this |
| lookahead_dist | 1.2m | Longer = smoother path tracking |
| max_angular_accel | 0.8 rad/s^2 | Prevents aggressive steering oscillation |
| xy_goal_tolerance | 0.5m | Ackermann needs generous tolerance |
| yaw_goal_tolerance | 3.14 rad | Accept any heading (can't rotate in place via Nav2) |
| progress checker | 0.2m / 30s | Relaxed to avoid premature abort |
| Nav2 activation delay | 25s | Gives SLAM time to publish map->odom TF |

---

## Troubleshooting

### ractor-sensors inactive after power cycle
```bash
sudo systemctl start ractor-sensors.service
```

### "3d_lidar_link frame does not exist"
robot_state_publisher is not running. Launch it (Step 2).

### "odom frame does not exist" / Nav2 lifecycle fails
KISS-ICP hasn't published yet. Usually because robot_state_publisher wasn't started before bringup. Kill bringup, ensure robot_state_publisher is running, relaunch.

### DDS isolation after service restart
If you restart a Pi service while ROS nodes are running, their DDS contexts break. Fix: restart the service AND relaunch any manual nodes.

**Never clean DDS (`/dev/shm/fastrtps_*`) on the Pi while ractor-sensors is running.** It kills the service's DDS context. Restart the service instead.

### Robot doesn't move in auto mode
1. Check control state: `ros2 topic echo /control/control_state --once` — must be `auto`
2. Check drive mode: `ros2 topic echo /control/drive_mode --once` — should be `ackermann`
3. Flip Switch B on joystick to auto position
4. Verify ractor-controls is active: `systemctl is-active ractor-controls.service`

### "Failed to make progress"
- Robot is too slow to overcome floor friction: increase `desired_linear_vel`
- Collision monitor blocking: check log for "Robot to approach" messages
- Goal too far / path blocked: try a closer goal in open space

### Nav2 lifecycle activation fails repeatedly
Increase `period` in `bringup_launch.py` TimerAction (currently 25.0s). On a heavily loaded Pi, SLAM may need more time.
