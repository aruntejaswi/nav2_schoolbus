from glob import glob

from setuptools import find_packages, setup

package_name = "nav2_schoolbus"

setup(
    name=package_name,
    version="0.0.1",
    packages=find_packages(exclude=["test"]),
    data_files=[
        ("share/ament_index/resource_index/packages", ["resource/" + package_name]),
        ("share/" + package_name, ["package.xml"]),
        ("share/" + package_name, glob("launch/*.py")),
        ("share/" + package_name + "/config/", glob("config/*")),
    ],
    install_requires=["setuptools"],
    zip_safe=True,
    maintainer="Devson Butani",
    maintainer_email="dbutani@ltu.edu",
    description="Nav2 Schoolbus everything launch package",
    license="MIT",
    tests_require=["pytest"],
    entry_points={
        "console_scripts": [],
    },
)
