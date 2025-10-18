#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 Paul Colby <git@colby.id.au>
# SPDX-License-Identifier: MIT
#
# ShellCheck GitHub workflow scripts
#
# Usage: [SHELLCHECK_OPTS=...] check-workflow-scripts.sh [-d|--define ...] [-h|--help] [-v|--verbose] [<path> [...]]

set -o errexit -o noclobber -o nounset -o pipefail -r
shopt -s inherit_errexit

readonly SCRIPT_VERSION=0.0.1

readonly DEFAULT_SHELLCHECK_OPTS='--check-sourced --enable=all --external-sources --norc'
export SHELLCHECK_OPTS="${SHELLCHECK_OPTS:-${DEFAULT_SHELLCHECK_OPTS}}"

# GitHub's default environment variables. See ./misc/default-environment-variables.gawk and
# https://docs.github.com/en/actions/reference/workflows-and-actions/variables#default-environment-variables
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
  [[ "${OUTPUT_LEVEL:-4}" -ge "$1" ]] || return 0
  [[ ! -t 2 ]] || echo -en "\x1b[$2m" >&2
  printf '%(%F %T)T %s' -1 "${@:3}" >&2
  [[ ! -t 2 ]] || echo -en '\x1b[0m' >&2
  echo >&2
  # \todo Check if this is GitHub, and output to step summary too.
}

function debug { output 5 37 "$*"; } # white
function info  { output 4 32 "$*"; } # green
function note  { output 3 34 "Note: $*"; } # yellow
function warn  { output 2 35 "Warning: $*"; } # magenta
function error { output 1 31 "Error: $*"; } # red

readonly USAGE_TEXT="
Usage: [SHELLCHECK_OPTS=...] ${BASH_SOURCE[0]} <options> [<path> [...]]

Options:
  -d,--debug        Enable debug output.
  -h,--help         Show this help text and exit.
  -s,--set <names>  Set <names> in each extracted script, so ShellCheck treats
                    them as assigned.
  -v,--version      Show the script's version, and exit.
  -                 Treat the remaining arguments as positional.

See ShellCheck manual for SHELLCHECK_OPTS. If not already set, this script
defaults it to: ${DEFAULT_SHELLCHECK_OPTS}
"

declare -a extraVars=()
unset endOfOptions
while [[ "${1:-}" == -* && ! -v endOfOptions ]]; do
  case "${1}" in
    -d|--debug)   OUTPUT_LEVEL=5 ;;
    -h|--help)    echo "${USAGE_TEXT}"; exit ;;
    -s|--set)     mapfile -td, -O "${#extraVars[@]}" extraVars < <(echo -n "${2:?The ${1} option requres an argument.}"); shift ;;
    -v|--version) echo "Version ${SCRIPT_VERSION}"; exit ;;
    -)            endOfOptions=true ;;
    *)            error "Unknown option: ${1}" ; exit 1 ;;
  esac
  shift
done

# Given a workflow JSON (converted from YAML), output the number of `runs` steps that don't specify their `shell`.
function countRunsWithDefaultedShell {
  debug 'Counting steps that run scripts without specifying the shell to use'
  local count
  count=$(jq -r '[.jobs[]?.steps?[]?|select(has("run") and (has("shell")|not))]|length')
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
  jq -rR 'split(" ")|sort|join(" ")' <<< "${!oses[@]}"
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
    [[ -z "${jobShell}" ]] || { echo "${jobShell}"; return; }
    [[ -z "${workflowShell}" ]] || { echo "${workflowShell}"; return; }

    # Otherwise, determine the shell/s from the job's operating system/s (could be more than one, if using a matrix).
    # https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#defaultsrunshell
    local -Ar defaultOsShell=([macos]=bash [ubuntu]=bash [windows]=pwsh)
    for os in $(getJobOs "${jobId}" "${job}"); do
      echo "${defaultOsShell[${os}]}"
    done | jq -rRs 'split("\n")|unique|join(" ")|ltrimstr(" ")'
}

function getStepScript {
  local -r step="${1}"
  echo '# Step environment variables'
  jq -r '.env//{}|keys[]|"export "+.' <<< "${step}"
  echo '# Extra variables'
  [[ "${#extraVars[@]}" -eq 0 ]] || printf 'export %s=\n' "${extraVars[@]}"
  # shellcheck disable=SC2016 # The GitHub Actions expression is not meant to me expanded.
  echo '# Shell script (with ${{ ... }} expressions removed)'
  jq -r '.run' <<< "${step}" | sed -e 's|\${{[^}]\+}}||g'
}

function checkAction {
  info "Checking action: ${fileName}"
  action=$(yq -oj "${fileName}") # Convert to JSON.
  while IFS= read -r step; do
    local stepId stepShell
    stepId=$(jq -r '.id//._id' <<< "${step}")
    info "Checking step: runs.steps[${stepId}]"
    debug 'Looking for step shell'
    stepShell=$(jq -r '.shell//empty' <<< "${step}")
    [[ -n "${stepShell}" ]] || { error "Missing shell on step: ${stepId}"; exit 3; }
    [[ "${stepShell}" =~ ^(ba)?sh$ ]] || { note "Skipping check with shell: ${stepShell}"; continue; }
    debug "Checking with shell: ${stepShell}"
    {
      echo '# GitHub environment variables'
      printf 'export %s=\n' "${defaultEnvVars[@]}"
      # shellcheck disable=SC2310 # Don't mind that errexit is inactive.
      getStepScript "${step}"
    } | shellcheck --shell "${stepShell}" - >&2 ||
      failures+=( "${fileName}::jobs.${jobId}.steps[${stepId}]" )
  done < <(jq -c '.runs.steps//{}|to_entries[]|select(.value.run)|{_id:.key}+.value' <<< "${action}" || :)
}

function checkWorkflow {
  info "Checking workflow: ${fileName}"
  workflow=$(yq -oj "${fileName}") # Convert to JSON.

  # See if we need to determine the default shell for the OS.
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
    jobId=$(jq -r '.id//._id' <<< "${job}")
    info "Checking job: ${jobId}"
    unset jobShells
    [[ ! -v needDefaultShells ]] || {
      jobShells=$(getJobShells "${jobId}" "${job}" "${workflowShell}")
      debug "Job shell/s: ${jobShells}"
    }

    while IFS= read -r step; do
      local stepId stepShell
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
          # shellcheck disable=SC2310 # Don't mind that errexit is inactive.
          getStepScript "${step}"
        } | shellcheck --shell "${shell}" - >&2 ||
          failures+=( "${fileName}::jobs.${jobId}.steps[${stepId}]" )
      done
    done < <(jq -c '.steps//{}|to_entries[]|select(.value.run)|{_id:.key}+.value' <<< "${job}" || :)
  done < <(jq -c '.jobs|to_entries[]|{_id:.key}+.value' <<< "${workflow}" || :)
}

function checkFile {
  local -r fileName="${1}"
  info "Checking file: ${fileName}"
  if [[ "$(yq '.jobs|length' "${fileName}" || :)" != '0' ]]; then
    checkWorkflow "${fileName}"
  elif [[ "$(yq '.runs.using' "${fileName}" || :)" == 'composite' ]]; then
    checkAction "${fileName}"
  else
    error "File is not a valid workflow, nor a valid composite action: ${fileName}"
    exit 2
  fi
}

[[ ! -v UNIT_TESTING_ONLY ]] || return 0
declare -a failures=()
for path in "${@:-.}"; do
  if [[ -d "${path}" ]]; then
    [[ ! -d "${path%/}/.github/workflows" ]] || path="${path%/}/.github/workflows"
    info "Checking directory: ${path}"
    foundFilesCount=0
    while IFS= read -d '' -r fileName; do
      : $((foundFilesCount++))
      checkFile "${fileName}"
    done < <(find "${path}" -maxdepth 1 -type f -name '*.yaml' -print0	|| :)
    [[ "${foundFilesCount}" -gt 0 ]] || { error "Found no workflow files in: ${path}"; exit 1; }
  elif [[ -e "${path}" ]]; then
    checkFile "${path}"
  else
    error "Path does not exist: ${path}"
  fi
done
[[ "${#failures[0]}" -eq 0 ]] || printf 'Checks failed for: %s\n' "${failures[@]}" >&2
[[ "${#failures[0]}" -eq 0 ]]
