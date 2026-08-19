# colcon-action

`colcon-action` is a simple action to build workspace leveraging colcon build tool

## Usage

``` yaml
- uses: tesseract-robotics/colcon-action@v15
  with:
    # Script that runs before anything else in build steps (optional, default: '')
    before-script: ''
    # CCache key prefix component (optional, default: '').
    # Give each leg of a matrix a distinct value: the action disambiguates the cache key per job,
    # but it cannot see the matrix.
    ccache-prefix: ''
    # Enable/Disable ccache (optional, default: 'true')
    ccache-enabled: 'true'
    # Cap on the size of the ccache directory (optional, default: '1G').
    # Read the ccache section below before raising it.
    ccache-maxsize: '1G'
    # Indicate if rosdep should be used (optional, default: 'true')
    rosdep-enabled: 'true'
    # Additional args to pass to rosdep install (optional, default: '-iry')
    rosdep-install-args: '-iry'
    # Indicate if ROS PPA should be added (optional, default: 'true').
    # The ROS PPA must be added if the Linux OS on which this action runs does not already contain a ROS distro.
    # The ROS PPA should not be added if the Linux OS already contains a ROS distro (e.g., ROS Docker image)
    add-ros-ppa: 'true'
    # The relative path to the vcs repos file (optional, default: '')
    vcs-file: ''
    # Additional args to pass to colcon build for upstream workspace (optional, default: '')
    upstream-args: ''
    # Relative path under $GITHUB_WORKSPACE where the repository was placed (optional, default: '')
    target-path: ''
    # Additional args to pass to colcon build for target workspace (optional, default: '')
    target-args: ''
    # Indicate if test should be ran (optional, default: 'true')
    run-tests: 'true'
    # Additional args to pass to colcon test for target workspace (optional, default: '')
    run-tests-args: ''
```

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

With `ccache-enabled: 'true'` the action does the whole ccache setup itself. It sets `CCACHE_DIR`
(to `$GITHUB_WORKSPACE/.ccache`, unless the caller already set one), caps it with `CCACHE_MAXSIZE`,
caches exactly that directory, and exports
`CMAKE_C_COMPILER_LAUNCHER`/`CMAKE_CXX_COMPILER_LAUNCHER` so the builds pick ccache up.

A caller-set `CCACHE_DIR` is honoured because what matters is that ccache and the cache step name
one directory, not which one — so an existing workaround degrades to a no-op instead of breaking.
The directory is whatever `ccache --get-config cache_dir` reports, so the two cannot disagree even
where ccache resolves the value differently than a shell would — as it does for a
`CCACHE_DIR: $GITHUB_WORKSPACE/.ccache` in a container `env:` block, which GitHub never runs a shell
over.

A value that is still relative, or still carries an unexpanded `$`, cannot be cached at all: ccache
resolves a relative cache directory against the compiler's working directory, which colcon changes
per package. The action warns, and the fix is to delete `CCACHE_DIR` from the workflow.

The launchers go through the environment rather than `--cmake-args` on purpose: colcon's
`--cmake-args` is last-wins, so a launcher the action appends is discarded by the `upstream-args`
or `target-args` that follow it. Everything the action exports — both launchers, `CCACHE_DIR` and
`CCACHE_MAXSIZE` — stays set for the rest of the job, so a later `ccache -s` step reads the same
directory the build wrote to.

### The build has to use Ninja or Make

CMake runs a compiler launcher only under the Makefile generators and the Ninja generator; the
Visual Studio and Xcode generators ignore `<LANG>_COMPILER_LAUNCHER` outright. Under either of
those, ccache is never invoked, and nothing says so: the cache is still restored and saved around a
build that cannot use it, so the job pays the transfer both ways and the log reads as though caching
were working.

Linux and macOS default to Unix Makefiles and so need nothing. Windows defaults to a Visual Studio
generator and so has to ask for another one — `--cmake-args -G "Ninja"` in both `upstream-args` and
`target-args`, as the test workflow in this repository does.

The symptom of getting this wrong is not a poor hit rate. It is a `ccache -s` reporting zero
cacheable calls, because the compiler was never reached through ccache at all.

### One prefix per matrix leg

The cache key is `<ccache-prefix>-<runner.os>-ccache-<job id>-<run id>-<attempt>`. `ccache-prefix`
is a key component only; it does not name a directory, so changing one purely to disambiguate a key
costs nothing. The job id separates jobs, but every leg of a matrix shares it and the action cannot
see the matrix, so **matrix legs need distinct `ccache-prefix` values** or they overwrite one
another's cache.

### Where a restore can come from

GitHub scopes caches by branch. A run can read the caches its own branch wrote and the caches the
repository's default branch wrote, and nothing else; a cache written by a pull request is visible to
that pull request alone.

A workflow that triggers only on `pull_request` therefore never writes a cache any other run can
read, and every pull request starts cold however well the keys are chosen. Trigger it on pushes to
the default branch as well — that run is what fills the cache each later pull request restores from.

### Sizing `ccache-maxsize`

Every caching job of every run stores a fresh entry, against a budget of 10 GB per repository that
GitHub evicts from by LRU. Consumption per run is roughly `cap x caching jobs`, so the cap decides
how many generations that budget holds — and a cap big enough to exceed it within a single run
means jobs evict each other before the next run can restore anything. The `1G` default keeps a
repository with a handful of caching jobs to about two generations and leaves room for the apt and
vcpkg caches sharing the same budget; ccache's own default of 5 GB does neither. 1 GB also holds
more than it sounds like, since ccache compresses entries with zstd by default.

Raise it only on evidence, because overrunning the cap is silent — it evicts, and the hit rate
drops. The signal is a `ccache -s` reporting a cache size sitting at the cap together with a real
miss count on a run that should have been almost all hits.

Set it through this input and nowhere else. ccache reads `CCACHE_MAXSIZE` on its own, so the value
can also arrive from the environment, and which one wins depends on how it got there: the action
writes the input to `GITHUB_ENV`, which beats a value an earlier step exported, but loses to a
`CCACHE_MAXSIZE` in a job or container `env:` map — those beat any `GITHUB_ENV` write. The action
cannot tell the two apart, so it warns whenever the environment disagrees with the input rather than
letting either value disappear without a trace.

### Reading the numbers

ccache keeps its counters inside `CCACHE_DIR`. A restored cache would therefore carry the previous
run's misses into this run's totals, and a fully cached build would report roughly 50%. The action
runs `ccache -z` after the restore, so a `ccache -s` at the end of a job describes that job alone.
