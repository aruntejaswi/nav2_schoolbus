from launch import LaunchDescription
from launch.substitutions import PathJoinSubstitution
from launch_ros.actions import Node
from launch_ros.substitutions import FindPackageShare


def generate_launch_description():
    nav2_schoolbus_package = FindPackageShare("nav2_schoolbus")

    # Load parameters
    dlio_yaml_path = PathJoinSubstitution([nav2_schoolbus_package, "config", "dlio_params.yaml"])
    dlio_params_yaml_path = PathJoinSubstitution([nav2_schoolbus_package, "config", "dlio_config.yaml"])

    # DLIO Odometry Node
    dlio_odom_node = Node(
        package="direct_lidar_inertial_odometry",
        executable="dlio_odom_node",
        output='screen',
        parameters=[dlio_yaml_path, dlio_params_yaml_path],
        remappings=[
            ("pointcloud", "/velodyne_points"),
            ("imu", "/imu/BMI088_data"),
            ("odom", "dlio/odom"),
            ("pose", "dlio/pose"),
            ("path", "dlio/path"),
            ("kf_pose", "dlio/keyframes"),
            ("kf_cloud", "dlio/pointcloud/keyframe"),
            ("deskewed", "dlio/pointcloud/deskewed"),
        ],
    )

    # DLIO Mapping Node
    dlio_map_node = Node(
        package="direct_lidar_inertial_odometry",
        executable="dlio_map_node",
        output="screen",
        parameters=[dlio_yaml_path, dlio_params_yaml_path],
        remappings=[
            ("map", "dlio/map"),
            ("keyframes", "dlio/pointcloud/keyframe"),
        ],
    )

    return LaunchDescription(
        [
            dlio_odom_node,
            dlio_map_node,
        ]
    )
