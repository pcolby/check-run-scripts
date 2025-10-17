#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 Paul Colby <git@colby.id.au>
# SPDX-License-Identifier: MIT
#
# ShellCheck GitHub workflow scripts
#
# Usage: check-workflow-scripts [<path> [...]]

set -o errexit -o noclobber -o nounset -o pipefail -r
shopt -s inherit_errexit

export SHELLCHECK_OPTS="${SHELLCHECK_OPTS:---check-sourced --enable=all --external-sources --norc}"

# \todo customise args to shellcheck; possibly allowing callers to override.
# \todo Allow caller's to supply additional defines.
# \todo Lots of tests!

# curl -s https://docs.github.com/en/actions/reference/workflows-and-actions/variables |
#   gawk -f default-environment-variables.gawk
readonly -a defaultEnvVars=(
  CI
  GITHUB_ACTION
  GITHUB_ACTION_PATH
  GITHUB_ACTION_REPOSITORY
  GITHUB_ACTIONS
  GITHUB_ACTOR
  GITHUB_ACTOR_ID
  GITHUB_API_URL
  GITHUB_BASE_REF
  GITHUB_ENV
  GITHUB_EVENT_NAME
  GITHUB_EVENT_PATH
  GITHUB_GRAPHQL_URL
  GITHUB_HEAD_REF
  GITHUB_JOB
  GITHUB_OUTPUT
  GITHUB_PATH
  GITHUB_REF
  GITHUB_REF_NAME
  GITHUB_REF_PROTECTED
  GITHUB_REF_TYPE
  GITHUB_REPOSITORY
  GITHUB_REPOSITORY_ID
  GITHUB_REPOSITORY_OWNER
  GITHUB_REPOSITORY_OWNER_ID
  GITHUB_RETENTION_DAYS
  GITHUB_RUN_ATTEMPT
  GITHUB_RUN_ID
  GITHUB_RUN_NUMBER
  GITHUB_SERVER_URL
  GITHUB_SHA
  GITHUB_STEP_SUMMARY
  GITHUB_TRIGGERING_ACTOR
  GITHUB_WORKFLOW
  GITHUB_WORKFLOW_REF
  GITHUB_WORKFLOW_SHA
  GITHUB_WORKSPACE
  RUNNER_ARCH
  RUNNER_DEBUG
  RUNNER_ENVIRONMENT
  RUNNER_NAME
  RUNNER_OS
  RUNNER_TEMP
  RUNNER_TOOL_CACHE
)

function output {
  [[ "${OUTPUT_LEVEL:-5}" -ge "$1" ]] || return 0
  [[ ! -t 2 ]] || echo -en "\x1b[$2m" >&2
  printf '%(%F %T)T ' >&2 # \todo make optional
  echo -n "${@:3}" >&2
  [[ ! -t 2 ]] || echo -en '\x1b[0m' >&2
  echo >&2
  # \todo Check if this is GitHub, and output to step summary too.
}

function debug { output 5 37 "$*"; } # white
function info  { output 4 32 "$*"; } # green
function note  { output 3 34 "Note: $*"; } # yellow
function warn  { output 2 35 "Warning: $*"; } # magenta
function error { output 1 31 "Error: $*"; } # red

# Given a workflow JSON (converted from YAML), output the number of `runs` steps that don't specify their `shell`.
function countRunsWithDefaultedShell {
  debug 'Counting steps that run scripts without specifying the shell to use'
  local count
  count=$(jq -r '[.jobs[].steps[]|select(has("run") and (has("shell")|not))]|length')
  debug "Found ${count} step/s with defaulted shells"
  echo "${count}"
}

# Detect the operating systems used by the given job. If successful, the result will be a string containg one or more
# of: macos, ubuntu, and/or windows. If no operating system could be determined, the function returns non-zero.
function getJobOs {
  local -r jobId=${1}
  local -r jobValue=${2}
  local matrixKey matrixValues remaining runsOn
  local -A matrixKeys=() oses=()
  debug "Detecting OS for job: ${jobId}"

  # First inspect the job's `runs-on` value for any direct OS mentions.
  runsOn=$(jq -r '.["runs-on"]' <<< "${jobValue}")
  debug "  Inspecting runs-on: ${runsOn}"
  unset remaining
  while [[ "${remaining-${runsOn}}" =~ (^|[^0-9a-zA-Z_-])(macos|ubuntu|windows)(.*)$ ]]; do
    debug "    Found: ${BASH_REMATCH[2]}"
    oses["${BASH_REMATCH[2]}"]=true
    remaining=${BASH_REMATCH[3]}
  done

  # Next check the `runs-on` value for an `matrix` key references.
  unset remaining
  while [[ "${remaining-${runsOn}}" =~ (^|[^0-9a-zA-Z_-])matrix\.([0-9a-zA-Z_-]+)(.*)$ ]]; do
    debug "    Found matrix key: ${BASH_REMATCH[2]}"
    matrixKeys["${BASH_REMATCH[2]}"]=true
    remaining=${BASH_REMATCH[3]}
  done

  # Inspect the values for all matrix keys indentified above, for OS mentions.
  for matrixKey in "${!matrixKeys[@]}"; do
    debug "  Inspecting values for: matrix.${matrixKey}"
    matrixValues=$(jq --arg key "${matrixKey}" --raw-output '.strategy.matrix[$key][]' <<< "${jobValue}")
    unset remaining
    while [[ "${remaining-${matrixValues}}" =~ (^|[^0-9a-zA-Z_-])(macos|ubuntu|windows)(.*)$ ]]; do
      debug "    Found matrix OS: ${BASH_REMATCH[2]}"
      oses["${BASH_REMATCH[2]}"]=true
      remaining=${BASH_REMATCH[3]}
    done
  done

  # Also check the `matrix.include` entries for OS mentions via the keys identified above.
  for matrixKey in "${!matrixKeys[@]}"; do
    debug "  Inspecting includes for: matrix.${matrixKey}"
    matrixValues=$(jq --arg key "${matrixKey}" --raw-output '.strategy.matrix.include[]?[$key]//empty' <<< "${jobValue}")
    unset remaining
    while [[ "${remaining-${matrixValues}}" =~ (^|[^0-9a-zA-Z_-])(ubuntu|macos|windows)(.*)$ ]]; do
      debug "    Found matrix.include OS: ${BASH_REMATCH[2]}"
      oses["${BASH_REMATCH[2]}"]=true
      remaining=${BASH_REMATCH[3]}
    done
  done

  # Finally, return the unique list of operating systems found (if any).
  [[ "${#oses[@]}" -gt 0 ]] || { error "  Failed to detect OS for job: ${jobId}"; return 1; }
  debug "  Returning OS list: ${!oses[*]}"
  echo "${!oses[@]}"
}

function getJobShells {
    local -r jobId="${1}"
    local -r job="${2}"
    local -r workflowShell="${3}"
    debug "Looking for shell/s for job: ${jobId}"
    local jobShell
    jobShell=$(jq -r '.defaults.run.shell//empty' <<< "${job}")
    debug "Job default shell: ${jobShell:-<none>}"

    # If either the shell is defaulted at either the job, or the workflow level, return it.
    [[ -z "${jobShell}" ]] || { echo "${jobShell}"; exit; }
    [[ -z "${workflowShell}" ]] || { echo "${workflowShell}"; exit; }

    # Otherwise, determine the shell/s from the job's operating system/s (could be more than one, if using a matrix).
    # https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#defaultsrunshell
    local -Ar defaultOsShell=([macos]=bash [ubuntu]=bash [windows]=pwsh)
    local oses
    oses=($(getJobOs "${jobId}" "${job}"))
    for os in "${oses[@]}"; do
      echo "${defaultOsShell[${os}]}"
    done | sort -u
}

function checkWorkflow {
  local -r fileName=${1}
  info "Checking: ${fileName}"
  workflow=$(yq -oj "${fileName}") # Convert to JSON.

  # See if we need to determine the
  local count needDefaultShells workflowShell=''
  count=$(countRunsWithDefaultedShell <<< "${workflow}")
  unset needDefaultShells
  [[ "${count}" -eq 0 ]] || {
    needDefaultShells=true
    debug 'Looking for workflow shell'
    workflowShell=$(jq -r '.defaults.run.shell//empty' <<< "${workflow}")
    debug "Workflow default shell: ${workflowShell:-<none>}"
  }
  unset count

  # Process each job in the workflow.
  while IFS= read -r job; do
    local jobId
    jobId=$(jq -r '._id' <<< "${job}")
    info "Checking job: ${jobId}"
    unset jobShells
    [[ ! -v needDefaultShells ]] || {
      jobShells=$(getJobShells "${jobId}" "${job}" "${workflowShell}")
      debug "Job shell/s: ${jobShells}"
    }

    while IFS= read -r step; do
      local stepId stepShell script
      stepId=$(jq -r ._id <<< "${step}")
      info "Checking step: ${jobId}[${stepId}]"
      debug 'Looking for step shell'
      stepShell=$(jq -r '.shell//empty' <<< "${step}")
      debug "Step shell: ${stepShell:-<none> - will use job"'"s default/s}"
      for shell in ${stepShell:-${jobShells}}; do
        [[ "${shell}" =~ ^(ba)?sh$ ]] || { note "Skipping check with shell: ${shell}"; continue; }
        debug "Checking with shell: ${shell}"
        {
          echo '# GitHub environment variables'
          printf 'export %s=\n' "${defaultEnvVars[@]}"
          echo '# Workflow environment variables'
          jq -r '.env//{}|keys[]|"export "+.' <<< "${workflow}"
          echo '# Job environment variables'
          jq -r '.env//{}|keys[]|"export "+.' <<< "${job}"
          echo '# Step environment variables'
          jq -r '.env//{}|keys[]|"export "+.' <<< "${step}"
          echo '# Shell script (with ${{ ... }} expressions removed)'
          jq -r '.run' <<< "${step}" | sed -e 's|\${{[^}]\+}}||g'
        } | shellcheck --shell "${shell}" /dev/stdin >&2 ||
          failures+=( "${fileName}::jobs.${jobId}.steps[${stepId}]" )
      done
    done < <(jq -c '.steps//{}|to_entries[]|select(.value.run)|{_id:.key}+.value' <<< "${job}")
  done < <(jq -c '.jobs|to_entries[]|{_id:.key}+.value' <<< "${workflow}")
}

declare -a failures=()
for path in "${@:-.}"; do
  if [[ -d "${path}" ]]; then
    [[ ! -d "${path%/}/.github/workflows" ]] || path="${path%/}/.github/workflows"
    info "Checking directory: ${path}"
    foundFilesCount=0
    while IFS= read -d '' -r fileName; do
      : $((foundFilesCount++))
      checkWorkflow "${fileName}"
    done < <(find "${path}" -maxdepth 1 -type f -name '*.yaml' -print0	|| :)
    [[ "${foundFilesCount}" -gt 0 ]] || { error "Found no workflow files in: ${path}"; exit 1; }
  elif [[ -e "${path}" ]]; then
    checkWorkflow "${path}"
  else
    error "Path does not exist: ${path}"
  fi
done
[[ "${#failures[0]}" -eq 0 ]] || printf 'Checks failed for: %s\n' "${failures[@]}" >&2
[[ "${#failures[0]}" -eq 0 ]]
