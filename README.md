# colcon-action

`colcon-action` is a simple action to build workspace leveraging colcon build tool

## Usage

``` yaml
- uses: tesseract-robotics/colcon-action@v2
  with:
    # Script that runs before anything else in build steps (optional, default: '')
    before-script: ''
    # CCache key prefix component (optional, default: '')
    ccache-prefix: ''
    # Enable/Disable ccache (optional, default: 'true')
    ccache-enabled: 'true'
    # Indicate if rosdep should be used (optional, default: 'true')
    rosdep-enabled: 'true'
    # Indicate if ROS PPA should be added (optional, default: 'false')
    ros-enabled: 'false'
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
```
