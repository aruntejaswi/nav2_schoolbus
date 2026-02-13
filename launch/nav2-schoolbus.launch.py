import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch_ros.actions import Node


# Schoolbus Description - URDF
def launch_schoolbus_description():
    return IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            os.path.join(get_package_share_directory("schoolbus_urdf"), "schoolbus.launch.py")
        )
    )


# Direct Lidar Inertial Odometry
def launch_direct_lidar_inertial_odometry():
    return IncludeLaunchDescription(
        PythonLaunchDescriptionSource(os.path.join(get_package_share_directory("nav2_schoolbus"), "dlio.launch.py"))
    )


ekf_yaml = os.path.join(get_package_share_directory("nav2_schoolbus"), "config", "ekf.yaml")


# Robot Localization - Local
def launch_robot_localization_local():
    return Node(
        package="robot_localization",
        executable="ekf_node",
        name="ekf_filter_node_odom",
        output="screen",
        parameters=[ekf_yaml],
        remappings=[
            ("odometry/filtered", "odometry/local"),
        ],
    )


# Robot Localization - Global
def launch_robot_localization_global():
    return Node(
        package="robot_localization",
        executable="ekf_node",
        name="ekf_filter_node_map",
        output="screen",
        parameters=[ekf_yaml],
        remappings=[
            ("odometry/filtered", "odometry/global"),
        ],
    )


# Robot Localization - GPS
def launch_robot_localization_gps():
    return Node(
        package="robot_localization",
        executable="navsat_transform_node",
        name="navsat_transform",
        output="screen",
        parameters=[ekf_yaml],
        remappings=[
            ("imu", "navheading"),
            ("gps/fix", "ublox_gps_node/fix"),
            ("odometry/filtered", "odometry/global"),
        ],
    )


# Nav2 Bringup
def launch_nav2_bringup():
    return IncludeLaunchDescription(
        PythonLaunchDescriptionSource(os.path.join(get_package_share_directory("nav2_schoolbus"), "bringup_launch.py"))
    )


def generate_launch_description():
    ld = LaunchDescription()
    ld.add_action(launch_schoolbus_description())
    ld.add_action(launch_direct_lidar_inertial_odometry())
    ld.add_action(launch_robot_localization_local())
    ld.add_action(launch_robot_localization_global())
    ld.add_action(launch_robot_localization_gps())
    ld.add_action(launch_nav2_bringup())
    return ld
