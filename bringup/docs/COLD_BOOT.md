# Schoolbus Cold Boot — From Powered-Off to Driving

This is the one-page procedure for bringing the whole system up after a
power cycle or a fresh clone. Follow it top-to-bottom. If you're debugging
a specific subsystem, see the troubleshooting section at the bottom or
dive into [`SLAM_STARTUP_STEPS.md`](SLAM_STARTUP_STEPS.md) for the longer
reference.

**Last validated:** 2026-04-12 — indoor path following working end-to-end.
**Current tag:** `v2026.04.12-indoor-working`.

---

## Architecture in one picture

```
┌──────────────────────────────┐         ┌──────────────────────────────┐
│   Raspberry Pi (192.168.0.3) │   DDS   │  Robot Laptop (192.168.0.22) │
│   pi@ — hardware side        │◄───────►│  dev@ — nav stack side       │
│                              │         │                              │
│  • Velodyne driver (systemd) │         │  • pointcloud_to_laserscan   │
│  • BNO085 IMU   (systemd)    │         │  • KISS-ICP lidar odometry   │
│  • Motor control (systemd)   │         │  • EKF sensor fusion         │
│  • RC receiver  (systemd)    │         │  • SLAM Toolbox              │
│  • robot_state_publisher     │         │  • Nav2 (SmacPlannerHybrid)  │
│    (systemd)                 │         │                              │
└──────────────────────────────┘         └──────────────────────────────┘
         no nav2_schoolbus                     no hardware drivers
         (nav2 runs on laptop only)            (drivers run on Pi only)
```

Both machines must use **`ROS_DOMAIN_ID=99`** — it's set in each machine's
`.bashrc`, so new shells pick it up automatically.

---

## Prerequisites (first-time setup only)

- SSH key access to both machines. On the VM: `~/.ssh/vm-to-pi-key`.
- Repos cloned via `bootstrap.sh` (see below) — this only needs to happen
  once per machine, not every cold boot.

### First-time Pi bootstrap

```bash
# On the Pi, after installing ROS 2 Jazzy and setting ROS_DOMAIN_ID=99
git clone https://github.com/LTU-Actor/nav2_schoolbus.git ~/nav2_schoolbus
cd ~/nav2_schoolbus/bringup
./bootstrap.sh --target pi
```

### First-time laptop bootstrap

```bash
# On the laptop, after installing ROS 2 Jazzy and setting ROS_DOMAIN_ID=99
git clone https://github.com/LTU-Actor/nav2_schoolbus.git ~/nav2_schoolbus
cd ~/nav2_schoolbus/bringup
./bootstrap.sh --target laptop
```

After either bootstrap, add this line to `~/.bashrc` (one-time):

```bash
source ~/ros2_ws/install/setup.bash
```

---

## Cold-boot sequence (every power cycle)

### Step 0 — Preflight from the VM (30 seconds)

```bash
cd ~/schoolbus_handoff
./scripts/preflight.sh --fix
```

What it checks:
- SSH to both machines
- Velodyne publishing at ~10 Hz
- Clock sync (laptop serves NTP to Pi)
- Stale DDS shared memory files (auto-cleans)
- Stale SLAM session files (auto-deletes)
- **Commit drift**: both machines are at the expected nav2_schoolbus tag
- **Install tree sanity**: laptop install tree resolves to `src/` (not scp'd-over)
- **Pi cleanliness**: Pi does NOT have nav2_schoolbus (it shouldn't)

Fix anything red before moving on. Yellow (WARN) is usually OK to proceed;
red (FAIL) is a blocker.

Cold-boot procedure is now only **4 steps** (preflight, Pi services,
laptop bringup, RViz + drive) — robot_state_publisher is a systemd
service, no manual launch needed.

### Step 1 — Start Pi hardware services

```bash
ssh pi@192.168.0.3 'sudo systemctl restart ractor-sensors.service ractor-controls.service ractor-robot-state.service'
```

These are sometimes `inactive` after a power cycle even though they're
enabled — the restart forces them up.

Verify:

```bash
ssh pi@192.168.0.3 'systemctl is-active ractor-sensors.service ractor-controls.service ractor-robot-state.service'
# expect: active\nactive\nactive
```

### Step 2 — Launch SLAM + Nav2 on the laptop

Open a new terminal (or SSH from the VM to the laptop):

```bash
ssh dev@192.168.0.22
ros2 launch nav2_schoolbus bringup_launch.py slam:=True use_localization:=True
```

**Important:** Capital `True`, not lowercase. The launch conditions require
valid Python booleans.

Wait ~35 seconds. You'll see a progression through Nav2 lifecycle activation,
ending with:

```
[lifecycle_manager_navigation]: Managed nodes are active
```

That line means the stack is up. If you don't see it within 60 seconds,
something is wrong — see troubleshooting below.

### Step 3 — Open RViz2

```bash
# On the laptop (or VM with X forwarding)
rviz2
```

- Set **Fixed Frame** to `map`
- Add displays: `Map` (topic `/map`), `LaserScan` (topic `/velodyne_scan`),
  `TF`, `Path` (topic `/plan`), `RobotModel` (via `/robot_description`)
- The map will start empty and grow as SLAM builds it from the Velodyne
  scans

### Step 4 — Drive

1. Flip **Switch B** on the physical joystick to the **auto** position.
2. Click the **Nav2 Goal** button in RViz and place a goal in front of
   the robot.
3. The planner (SmacPlannerHybrid, Hybrid A\* with Dubins primitives)
   will emit a curved Ackermann-feasible path. The RPP controller follows it.
4. Flip Switch B back to **teleop** at any time to take manual control.

---

## Validation checklist (how to know it's really working)

```bash
# On the laptop, after Step 3

# Sensors flowing
ros2 topic hz /velodyne_scan    # expect ~10 Hz
ros2 topic hz /kiss/odometry    # expect ~10 Hz
ros2 topic hz /odometry/local   # expect ~10 Hz

# TF chain intact
ros2 run tf2_ros tf2_echo map odom           # should print Translation
ros2 run tf2_ros tf2_echo odom base_footprint # should print Translation

# Lifecycle state
ros2 lifecycle get /bt_navigator
# expect: active [3]
```

---

## Common failures and first-try fixes

### "ractor-sensors inactive" after power cycle

```bash
ssh pi@192.168.0.3 'sudo systemctl restart ractor-sensors.service'
```

### "3d_lidar_link frame does not exist"

`ractor-robot-state.service` isn't running on the Pi. Restart it:

```bash
ssh pi@192.168.0.3 'sudo systemctl restart ractor-robot-state.service'
```

### Nav2 lifecycle never activates / bringup hangs after 25 seconds

SLAM Toolbox didn't come up in time. Kill the bringup and try again — usually
transient. If it persists, `/map` may not be publishing: check SLAM Toolbox
logs inside the bringup output.

### Map "jumps" around during movement

Stale DDS shared memory files. Run `preflight.sh --fix` which cleans
`/dev/shm/fastrtps_*` on the laptop. **Do not** clean DDS on the Pi while
`ractor-sensors` is running — it will kill the service's DDS context.
Restart the service instead.

### Robot doesn't move in auto mode

1. `ros2 topic echo /control/control_state --once` — must be `auto`
2. `ros2 topic echo /control/drive_mode --once` — should be `ackermann`
3. Flip Switch B to the auto position (it's easy to leave it mid-position)
4. `ssh pi@192.168.0.3 'systemctl is-active ractor-controls.service'`

### Robot drives past the goal or creeps after stopping

This should NOT happen at the current tag — the `cmd_vel` feedback loop
fix in commit `55b8f46` eliminated it. If you see it, you may be running
an older build: check `preflight.sh` commit-drift output, and run
`preflight.sh --fix` to sync to the latest tag.

### "Failed to meet update rate" from EKF

Occasional ~200ms latency spikes are benign and have been observed even
on an idle 32-core laptop. If they become continuous, check CPU load
(`top`) and whether multiple ROS processes have been accidentally started.

---

## Deploying a new tag

When `v2026.MM.DD-<scenario>` has been validated working and pushed to
`LTU-Actor/nav2_schoolbus`:

```bash
# From the VM
cd ~/schoolbus_handoff/repos/nav2_schoolbus
git fetch origin
git tag -l 'v*' | sort -V | tail -1    # confirm the new tag is present

# Sync both machines to the new tag
./scripts/preflight.sh --fix
# The commit-drift check sees the new tag, the Pi has nav2_schoolbus
# removed so it's skipped, and the laptop is checked out + rebuilt
# automatically.
```

No scp, no manual file copying. Git is the deploy mechanism.
