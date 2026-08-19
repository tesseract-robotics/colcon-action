#!/usr/bin/env bash
# Shared by the linux, macos and windows actions, which differ only in how they install ccache.
#
# Inputs arrive as environment variables, so no workflow value is ever spliced into shell source.
# They keep the INPUT_ prefix because ccache itself reads both CCACHE_PREFIX and CCACHE_MAXSIZE.
set -euo pipefail

# A caller that already set CCACHE_DIR keeps it: what matters is that ccache and the cache step
# name one directory, not which one. Ask ccache which one rather than reading the variable here —
# ccache applies its own $VAR expansion to config values, so a shell-level read can name a
# different directory than the compiler writes to.
export CCACHE_DIR="${CCACHE_DIR:-$GITHUB_WORKSPACE/.ccache}"
# A CCACHE_DIR naming a variable that is not set makes ccache exit non-zero rather than report a
# path. That is a caller mistake, not a reason to fail the build, so it degrades the same way as the
# unusable shapes below. The condition keeps set -e from aborting here; ccache has already printed
# its own error to the step log.
if ! dir="$(ccache --get-config cache_dir)"; then
  echo "::warning::ccache rejected CCACHE_DIR=$CCACHE_DIR (its error is above). Continuing without ccache - set CCACHE_DIR to a plain path, or drop it and let the action choose one."
  exit 0
fi
# Git bash reports Windows paths with backslashes, which bash treats as literal characters.
dir="${dir//\\//}"

# Two shapes cannot be used, and both end the same way: leave the dir output unset. The restore
# and save steps are guarded on it, so they become no-ops and the build simply runs uncached.
case "$dir" in
  *'$'*)
    # ccache resolved the value but a literal $ survived, so writing it back as CCACHE_DIR below
    # would fail the next ccache call with "environment variable not set", even though it works here.
    echo "::warning::CCACHE_DIR resolves to $dir, which still contains a '$' that ccache would expand again. Continuing without ccache - set CCACHE_DIR to a plain path, or drop it and let the action choose one."
    exit 0 ;;
  /* | [A-Za-z]:/*) ;;
  *)
    # ccache resolves a relative cache_dir against the compiler's working directory, which colcon
    # changes per package, so nothing would land where the cache step looks.
    echo "::warning::CCACHE_DIR resolves to the relative path $dir, so ccache would scatter it per package. Continuing without ccache - remove CCACHE_DIR from the workflow and let the action set it."
    exit 0 ;;
esac
mkdir -p "$dir"

# GITHUB_RUN_ID is shared by every job of a run, so the job id has to be in the key too or two jobs
# collide on it and the second save is dropped with a warning. Matrix legs share the job id as
# well — those still need distinct ccache-prefix values.
restore_key="$INPUT_CCACHE_PREFIX-$RUNNER_OS-ccache-$GITHUB_JOB-"
{
  echo "dir=$dir"
  echo "restore_key=$restore_key"
  echo "key=$restore_key$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
} >> "$GITHUB_OUTPUT"

# A container env: map would beat the GITHUB_ENV write below, a value an earlier step exported
# would lose to it, and the two are indistinguishable from here — so say so rather than pick.
if [ -n "${CCACHE_MAXSIZE:-}" ] && [ "$CCACHE_MAXSIZE" != "$INPUT_CCACHE_MAXSIZE" ]; then
  echo "::warning::CCACHE_MAXSIZE=$CCACHE_MAXSIZE in the environment differs from the ccache-maxsize input ($INPUT_CCACHE_MAXSIZE), which is where it should be set."
fi

{
  echo "CCACHE_DIR=$dir"
  echo "CCACHE_MAXSIZE=$INPUT_CCACHE_MAXSIZE"
  # CMake picks the launchers up from the environment (3.17+). Passing them as -D flags does not
  # work here: colcon's --cmake-args is last-wins, so the caller's own --cmake-args drops them.
  echo "CMAKE_C_COMPILER_LAUNCHER=ccache"
  echo "CMAKE_CXX_COMPILER_LAUNCHER=ccache"
} >> "$GITHUB_ENV"
