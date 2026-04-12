# Robot Dependencies

System packages the Schoolbus stack needs that `rosdep` doesn't always install
automatically. Install on Ubuntu 24.04 with ROS 2 Jazzy before running
`bringup/bootstrap.sh` or `colcon build`.

## Apt packages

```bash
sudo apt update
sudo apt install -y \
  python3-vcstool \
  python3-rosdep \
  python3-colcon-common-extensions \
  ros-jazzy-nav2-bringup \
  ros-jazzy-slam-toolbox \
  ros-jazzy-robot-localization \
  ros-jazzy-pointcloud-to-laserscan \
  ros-jazzy-imu-filter-madgwick \
  ros-jazzy-velodyne \
  ros-jazzy-velodyne-driver \
  ros-jazzy-velodyne-pointcloud \
  git
```

## rosdep bootstrap (one-time)

```bash
sudo rosdep init  # only if /etc/ros/rosdep/sources.list.d/20-default.list is missing
rosdep update
```

After that, `rosdep install --from-paths src --ignore-src -r -y` from a
workspace root will pull any remaining package-declared dependencies.

## Notes

- **ROS distro:** jazzy (Ubuntu 24.04). Noble and earlier are not supported by
  this stack — the Velodyne, SLAM Toolbox, and Nav2 versions assume jazzy.
- **Pi-specific:** the Pi needs `imu_serial_to_ros_publisher` (listed in
  `schoolbus.repos`) for the BNO085 IMU — this repo must be cloned into
  `src/` on the Pi workspace. `vcs import` handles this automatically.
- **Laptop-specific:** nothing extra — the laptop runs SLAM + Nav2 from the
  same `schoolbus.repos` file as the Pi.
