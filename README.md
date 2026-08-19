# colcon-action

Build and test a [colcon](https://colcon.readthedocs.io) workspace on Linux, macOS and Windows.
The action installs the toolchain and colcon, resolves upstream dependencies from a `.repos`
file, installs system dependencies with `rosdep`, builds, and runs `colcon test`. Compilation is
cached with ccache by default.

One `uses:` covers all three platforms: the action dispatches on `runner.os`, so the caller picks
the platform with `runs-on` and never names a sub-action.

## Usage

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      # The action does not check anything out. Put the repository in the
      # workspace source directory yourself.
      - uses: actions/checkout@v4
        with:
          path: target_ws/src/my_repo

      - uses: tesseract-robotics/colcon-action@v15
        with:
          target-path: target_ws/src
          vcs-file: my_repo/dependencies.repos
          upstream-args: --cmake-args -DCMAKE_BUILD_TYPE=Release
          target-args: --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
          ccache-prefix: ci-linux
```

This builds an upstream workspace from `my_repo/dependencies.repos`, builds `target_ws` against
it, and runs the tests. Every other input keeps its default; see [Inputs](#inputs).

## How it works

1. Installs a toolchain (cmake, curl, git, python3) and colcon, and adds the ROS 2 apt repository
   when `add-ros-ppa` is set.
2. When `vcs-file` is set, imports it into `$GITHUB_WORKSPACE/upstream_ws/src`, installs its
   dependencies with `rosdep`, and builds it with `upstream-args`. An empty `vcs-file` skips the
   upstream workspace entirely.
3. Sources `upstream_ws/install/setup.bash`, installs the target workspace's dependencies with
   `rosdep`, and builds it with `target-args`.
4. When `run-tests` is set, runs `colcon test` and then `colcon test-result --verbose`, failing
   the job on a failing test.

Windows runs no `rosdep` at any of these points and installs no system dependencies at all — see
[Platform differences](#platform-differences).

`target-path` names the workspace's **source** directory, and the workspace built is its parent.
`vcs-file` is resolved relative to `target-path`:

```
$GITHUB_WORKSPACE/
├── upstream_ws/                  created by the action from vcs-file
└── target_ws/                    <- built here: the parent of target-path
    └── src/                      <- target-path; check your repository out into this
        └── my_repo/
            └── dependencies.repos    <- vcs-file, relative to target-path
```

## Inputs

All are optional. The action defines no outputs.

| Input | Default | Description |
| --- | --- | --- |
| `before-script` | `''` | Shell snippet run at the start of each build step. The build steps do not all use the same shell — see [Platform differences](#platform-differences). |
| `ccache-enabled` | `'true'` | Cache compilation with ccache. |
| `ccache-prefix` | `''` | Cache key prefix. Give each leg of a matrix a distinct value: the action disambiguates the key per job, but it cannot see the matrix. |
| `ccache-maxsize` | `'1G'` | Cap on the size of the ccache directory. Read [ccache](#ccache) before raising it. |
| `rosdep-enabled` | `'true'` | Install system dependencies with `rosdep`. |
| `rosdep-install-args` | `'-iry'` | Additional args for `rosdep install`. |
| `add-ros-ppa` | `'true'` | Add the ROS 2 apt repository. Needed unless the image already ships a ROS distro, as a ROS Docker image does. |
| `vcs-file` | `''` | Path to a `.repos` file of upstream dependencies, relative to `target-path`. Empty builds no upstream workspace. |
| `upstream-args` | `''` | Additional args for the upstream `colcon build`. |
| `target-path` | `''` | The workspace source directory, relative to `$GITHUB_WORKSPACE`. The workspace built is its parent. |
| `target-args` | `''` | Additional args for the target `colcon build`. |
| `run-tests` | `'true'` | Run `colcon test` after the build. |
| `run-tests-args` | `''` | Additional args for `colcon test`. |

## Platform differences

All three platforms take the same inputs, but not every input does something on every one of them.
An input that does not apply is accepted and ignored rather than rejected, so a single workflow can
drive all three.

|                                                 | Linux   | macOS    | Windows     |
| ----------------------------------------------- | ------- | -------- | ----------- |
| Workspace dependencies installed by             | apt     | Homebrew | nothing     |
| `rosdep-enabled`, `rosdep-install-args`         | applied | applied  | **ignored** |
| `add-ros-ppa`                                   | applied | ignored  | ignored     |
| Shell the upstream workspace builds in          | bash    | bash     | bash        |
| Shell the target workspace builds and tests in  | bash    | bash     | `cmd`       |

Every platform installs the tooling it needs itself — colcon, vcs and ccache — through apt,
Homebrew, pip or Chocolatey. The first row is about what the *workspace* needs, and Windows
installs none of that: it installs its own tooling and then builds. Whatever else the workspace
needs has to be in place before the action runs — the test workflow in this repository uses vcpkg
for that. `rosdep-enabled: 'true'` on Windows does not fail, it does nothing, so a workspace that
counts on rosdep having run fails later, at configure or link time, pointing at a missing package
rather than at the ignored input.

`add-ros-ppa` adds an apt source, so it has no meaning off Linux.

`before-script` is spliced into the build steps, which do not use the same shell everywhere: on
Windows the upstream workspace is built under bash and the target workspace under `cmd`, so a
`before-script` written for one runs as-is under the other.

## ccache

ccache is **on by default**. The action installs it, points `CCACHE_DIR` at
`$GITHUB_WORKSPACE/.ccache` unless the caller already set one, caps it with `ccache-maxsize`,
exports `CMAKE_C_COMPILER_LAUNCHER` and `CMAKE_CXX_COMPILER_LAUNCHER` so the builds pick it up,
and restores and saves that directory around the build.

### The build has to use Ninja or Make

CMake runs a compiler launcher only under the Makefile generators and the Ninja generator; the
Visual Studio and Xcode generators ignore `<LANG>_COMPILER_LAUNCHER` outright. Under either of
those the cache is still restored and saved around a build that never invokes ccache at all, so
the job pays the transfer both ways.

Linux and macOS default to Unix Makefiles and need nothing. Windows defaults to a Visual Studio
generator and has to ask for another one — `--cmake-args -G "Ninja"` in both `upstream-args` and
`target-args`, as the test workflow in this repository does.

The symptom is not a poor hit rate. It is a `ccache -s` reporting **zero cacheable calls**.

### One prefix per matrix leg

The cache key is `<ccache-prefix>-<runner.os>-ccache-<job id>-<run id>-<attempt>`. The job id
separates jobs, but every leg of a matrix shares it and the action cannot see the matrix, so
**matrix legs need distinct `ccache-prefix` values** or they overwrite one another's cache. The
prefix is a key component only — it does not name a directory, so changing one costs nothing.

### Where a restore can come from

A run reads only the caches its own branch wrote and those the default branch wrote; a cache a
pull request writes is visible to that pull request alone. A workflow triggered solely on
`pull_request` therefore never fills a cache any other run can read, and every pull request
starts cold however well the keys are chosen. Trigger it on pushes to the default branch as well.

### Sizing `ccache-maxsize`

GitHub gives each repository a 10 GB cache budget, shared with every other cache and evicted by
LRU. A run consumes roughly `ccache-maxsize x caching jobs`, so a cap large enough to exceed the
budget within a single run means jobs evict each other before the next run can restore anything.
The `1G` default leaves room for a handful of caching jobs alongside the apt and vcpkg caches;
ccache's own default of 5 GB does not, and 1 GB holds more than it sounds like since ccache
compresses entries with zstd.

Raise it only on evidence: overrunning the cap is silent, and the signal is a `ccache -s` showing
the cache size sitting at the cap together with a real miss count on a run that should have been
almost all hits.

Set it through this input rather than the environment. The action writes the input to
`GITHUB_ENV`, which a `CCACHE_MAXSIZE` in a job or container `env:` map would override, so it
warns whenever the two disagree.

### Reading the numbers

ccache keeps its counters inside `CCACHE_DIR`, so a restored cache would carry the previous run's
misses into this run's totals and a fully cached build would report roughly 50%. The action runs
`ccache -z` after the restore, so a `ccache -s` at the end of a job describes that job alone.
