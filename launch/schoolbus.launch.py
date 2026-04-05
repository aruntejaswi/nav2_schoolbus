import os

from ament_index_python.packages import get_package_share_directory, PackageNotFoundError
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription, LogInfo
from launch.conditions import IfCondition
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node

nav2_arg = DeclareLaunchArgument("visualize_kiss", default_value="false")
nav2_enable_arg = DeclareLaunchArgument(
    "nav2", default_value="true",
    description="Set false to run sensors/odometry only (Pi-side in multi-machine mode)"
)


# Schoolbus Description - URDF
def launch_schoolbus_description():
    return IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            os.path.join(get_package_share_directory("schoolbus_urdf"), "schoolbus.launch.py")
        )
    )


    
def launch_pointcloud_to_scan():
    return Node(
        package='pointcloud_to_laserscan',
        executable='pointcloud_to_laserscan_node',
        name='pointcloud_to_laserscan',
        remappings=[
            ('cloud_in', '/velodyne_points'),
            ('scan', '/velodyne_scan'),
        ],
        parameters=[{
            'target_frame': '3d_lidar_link',  # Usually use base link or footprint frame
            'transform_tolerance': 0.2,
            'min_height': -1.0,
            'max_height': 1.0,
            'angle_min': -3.14159,    # -90 degrees
            'angle_max': 3.14159,     # 90 degrees
            'angle_increment': 0.0175,  # about 1 degree
            'scan_time': 0.05,
            'range_min': 0.45,
            'range_max': 10.0,
            'use_inf': True,
            'inf_epsilon': 1.0
        }],
        arguments=['--ros-args', '--log-level', 'warn'],
        output='screen'
    )

# Direct Lidar Inertial Odometry
def launch_kiss_lidar_odometry():
    return IncludeLaunchDescription(
        PythonLaunchDescriptionSource(os.path.join(get_package_share_directory("kiss_icp"), "launch/odometry.launch.py")),
        launch_arguments={
            'visualize': LaunchConfiguration("visualize_kiss"),
            'topic': '/velodyne_points',
            'lidar_odom_frame': 'odom',
            'base_frame': 'base_footprint',
            'publish_odom_tf': 'false',  # EKF publishes odom->base_footprint; KISS-ICP inverts it causing TF loop
        }.items()
    )

def imu_filter_madgwick_BNO085():
    imu_filter_yaml = os.path.join(get_package_share_directory("nav2_schoolbus"), "config", "imu_filter_BNO085.yaml")
    return Node(
        package="imu_filter_madgwick",
        executable="imu_filter_madgwick_node",
        name="imu_filter_madgwick",
        output="screen",
        parameters=[imu_filter_yaml],
        remappings=[
            ("imu/data_raw", "/imu/BNO085_data"),
            ("imu/data", "/imu/BNO085_filtered"),
        ],
    )

def imu_filter_madgwick_LSM6DSOX():
    imu_filter_yaml = os.path.join(get_package_share_directory("nav2_schoolbus"), "config", "imu_filter_LSM6DSOX.yaml")
    return Node(
        package="imu_filter_madgwick",
        executable="imu_filter_madgwick_node",
        name="imu_filter",
        output="screen",
        parameters=[imu_filter_yaml],
        remappings=[
            ("imu/data_raw", "/imu/LSM6DSOX_data"),
            ("imu/data", "/imu/LSM6DSOX_filtered"),
        ],
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
        PythonLaunchDescriptionSource(os.path.join(get_package_share_directory("nav2_schoolbus"), "bringup_launch.py")),
        condition=IfCondition(LaunchConfiguration("nav2"))
    )

def launch_masker():
    return IncludeLaunchDescription(
        PythonLaunchDescriptionSource(os.path.join(get_package_share_directory("image_hsv_masker"), "launch/hsv_masker.launch.py"))
    )

# Blob Lane Following
def launch_blob():
    return IncludeLaunchDescription(
        PythonLaunchDescriptionSource(os.path.join(get_package_share_directory("blob_follow_ros2"), "launch/blob.launch.py"))
    )
    

# LiDAR PointCloud Regions
def launch_cloud_regions():
    return IncludeLaunchDescription(
        PythonLaunchDescriptionSource(os.path.join(get_package_share_directory("cloud_regions_cpp"), "launch/regions.launch.py"))
    )
    
def launch_yolo_detector():
    return IncludeLaunchDescription(
        PythonLaunchDescriptionSource(os.path.join(get_package_share_directory("route_yolo_ros2"), "launch/detector.launch.py"))
    )
    
# EZRospy
def launch_ezrospy():
    return IncludeLaunchDescription(
        PythonLaunchDescriptionSource(os.path.join(get_package_share_directory("ezrospy"), "ezrospy.launch.py"))
    )
    
def pothole():
    return IncludeLaunchDescription(
        PythonLaunchDescriptionSource(os.path.join(get_package_share_directory("pothole_detector"), "launch/pothole.launch.py"))
    )
    
def routecam():
    return IncludeLaunchDescription(
        PythonLaunchDescriptionSource(os.path.join(get_package_share_directory("routecam_ros2"), "routecam.launch.py")))
        
def routecam_nav2():
    try:
        pkg = get_package_share_directory("routecam_nav2")
    except PackageNotFoundError:
        return LogInfo(msg="routecam_nav2 not installed, skipping")
    return IncludeLaunchDescription(
        PythonLaunchDescriptionSource(os.path.join(pkg, "routecam.launch.py")),
        condition=IfCondition(LaunchConfiguration("nav2")))
    


def generate_launch_description():
    ld = LaunchDescription([
        nav2_arg,
        nav2_enable_arg,
        launch_pointcloud_to_scan(),
        launch_schoolbus_description(),
        imu_filter_madgwick_LSM6DSOX(),
        launch_kiss_lidar_odometry(),
        launch_robot_localization_local(),
        # launch_robot_localization_global(),
        # launch_robot_localization_gps(),
        launch_nav2_bringup(),
        # launch_masker(),
        # launch_blob(),
        # launch_cloud_regions(),
        # launch_yolo_detector(),
        # launch_ezrospy(),
        # pothole(),
        # routecam(),
        routecam_nav2(),
        ])
    return ld
