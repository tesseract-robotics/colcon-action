# colcon-action

`colcon-action` is a simple action to build workspace leveraging colcon build tool

## Usage

``` yaml
- uses: tesseract-robotics/colcon-action@v11
  with:
    # Script that runs before anything else in build steps (optional, default: '')
    before-script: ''
    # CCache key prefix component (optional, default: '')
    ccache-prefix: ''
    # Enable/Disable ccache (optional, default: 'true')
    ccache-enabled: 'true'
    # Indicate if rosdep should be used (optional, default: 'true')
    rosdep-enabled: 'true'
    # Additional args to pass to rosdep install (optional, default: '-r')
    rosdep-install-args: '-iry'
    # Indicate if ROS PPA should be added (optional, default: 'false').
    # The ROS PPA must be added if the Linux OS on which this action runs does not already contain a ROS distro.
    # The ROS PPA should not be added if the Linux OS already contains a ROS distro (e.g., ROS Docker image)
    add-ros-ppa: 'false'
    # The relative path to the vcs repos file (optional, default: '')
    vcs-file: 'dependencies.repos'
    # Additional args to pass to colcon build for upstream workspace (optional, default: '')
    upstream-args: '--cmake-args -DCMAKE_BUILD_TYPE=Release'
    # Relative path under $GITHUB_WORKSPACE where the repository was placed (optional, default: '')
    target-path: ''
    # Additional args to pass to colcon build for target workspace (optional, default: '')
    target-args: '--cmake-args -DCMAKE_BUILD_TYPE=Debug'
    # Indicate if test should be ran (optional, default: 'true')
    run-tests: 'true'
    # Additional args to pass to colcon test for target workspace (optional, default: '')
    run-tests-args: ''
```
