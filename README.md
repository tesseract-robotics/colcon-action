# colcon-action

`colcon-action` is a simple action to build workspace leveraging colcon build tool

## Usage

``` yaml
- uses: tesseract-robotics/colcon-action@v11
  with:
    # Script that runs before anything else in build steps (optional, default: '')
    before-script: ''
    # CCache key prefix component (optional, default: '').
    # Give each leg of a matrix a distinct value: the action disambiguates the cache key per job,
    # but it cannot see the matrix.
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

## ccache

With `ccache-enabled: 'true'` the action does the whole ccache setup itself. It sets `CCACHE_DIR`
(to `$GITHUB_WORKSPACE/.ccache`, unless the caller already set one), caps it with `CCACHE_MAXSIZE`
(`1G`, unless the caller already set one), caches exactly that directory, and exports
`CMAKE_C_COMPILER_LAUNCHER`/`CMAKE_CXX_COMPILER_LAUNCHER` so the builds pick ccache up.

The launchers go through the environment rather than `--cmake-args` on purpose: colcon's
`--cmake-args` is last-wins, so a launcher the action appends is discarded by the `upstream-args`
or `target-args` that follow it. Both variables stay set for the rest of the job, so a
`ccache -s` step after this action reports on the right directory.
