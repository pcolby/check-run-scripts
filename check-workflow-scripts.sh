#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 Paul Colby <git@colby.id.au>
# SPDX-License-Identifier: MIT
#
# ShellCheck GitHub workflow scripts
#
# Usage: check-workflow-scripts [<path> [...]]

set -o errexit -o noclobber -o nounset -o pipefail -r
shopt -s inherit_errexit

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
  [[ ! -t 2 ]] || echo -e '\x1b[0m' >&2
  # \todo Check if this is GitHub, and output to step summary too.
}

function debug { output 5 37 "$*"; } # white
function info  { output 4 32 "$*"; } # green
function note  { output 3 34 "Note: $*"; } # yellow
function warn  { output 2 35 "Warning: $*"; } # magenta
function error { output 1 31 "Error: $*"; } # red

# https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#defaultsrunshell
readonly -A defaultRunShell=(
  [macos]=bash
  [ubuntu]=bash
  [windows]=pwsh
)

# Given a workflow JSON (converted from YAML), output the number of `runs` steps don't specify their `shell`.
function countRunsWithDefaultedShell {
  debug 'Counting steps that run scripts without specifying the shell to use'
  local count
  count=$(jq -r '[.jobs[].steps[]|select(has("run") and (has("shell")|not))]|length')
  debug "Found ${count} step/s with defaulted shells"
}

# Detect the operating systems used by the given job. If successful, the result will be a sting containg one or more of
# macos, ubuntu, and/or windows. If no operating system could be determined, the function returns non-zero.
function getJobOs {
  local -r jobId=${1}
  local -r jobValue=${2}
  local matrixKey matrixValues remaining runsOn
  local -A matrixKeys=() oses=()
  info "Detecting OS for job: ${jobId}"

  # First inspect the job's `runs-on` value for any direct OS mentions.
  runsOn=$(jq -r '.["runs-on"]' <<< "${jobValue}")
  echo "  Inspecting runs-on: ${runsOn}" >&2
  unset remaining
  while [[ "${remaining-${runsOn}}" =~ (^|[^0-9a-zA-Z_-])(macos|ubuntu|windows)(.*)$ ]]; do
    echo "    Found: ${BASH_REMATCH[2]}" >&2
    oses["${BASH_REMATCH[2]}"]=true
    remaining=${BASH_REMATCH[3]}
  done

  # Next check the `runs-on` value for an `matrix` key references.
  unset remaining
  while [[ "${remaining-${runsOn}}" =~ (^|[^0-9a-zA-Z_-])matrix\.([0-9a-zA-Z_-]+)(.*)$ ]]; do
    echo "    Found matrix key: ${BASH_REMATCH[2]}" >&2
    matrixKeys["${BASH_REMATCH[2]}"]=true
    remaining=${BASH_REMATCH[3]}
  done

  # Inspect the values for all matrix keys indentified above, for OS mentions.
  for matrixKey in "${!matrixKeys[@]}"; do
    echo "  Inspecting values for: matrix.${matrixKey}" >&2
    matrixValues=$(jq --arg key "${matrixKey}" --raw-output '.strategy.matrix[$key][]' <<< "${jobValue}")
    unset remaining
    while [[ "${remaining-${matrixValues}}" =~ (^|[^0-9a-zA-Z_-])(macos|ubuntu|windows)(.*)$ ]]; do
      echo "    Found matrix OS: ${BASH_REMATCH[2]}" >&2
      oses["${BASH_REMATCH[2]}"]=true
      remaining=${BASH_REMATCH[3]}
    done
  done

  # Also check the `matrix.include` entries for OS mentions via the keys identified above.
  for matrixKey in "${!matrixKeys[@]}"; do
    echo "  Inspecting includes for: matrix.${matrixKey}" >&2
    matrixValues=$(jq --arg key "${matrixKey}" --raw-output '.strategy.matrix.include[]?[$key]//empty' <<< "${jobValue}")
    unset remaining
    while [[ "${remaining-${matrixValues}}" =~ (^|[^0-9a-zA-Z_-])(ubuntu|macos|windows)(.*)$ ]]; do
      echo "    Found matrix.include OS: ${BASH_REMATCH[2]}" >&2
      oses["${BASH_REMATCH[2]}"]=true
      remaining=${BASH_REMATCH[3]}
    done
  done

  # Finally, return the unique list of operating systems found (if any).
  [[ "${#oses[@]}" -gt 0 ]] || { echo "  Failed to detect OS for job: ${jobId}" >&2; return 1; }
  echo "  Returning OS list: ${!oses[*]}" >&2
  echo "${!oses[@]}"
}

function checkWorkflow {
  local -r fileName=${1}
  info "Checking: ${fileName}"
  workflow=$(yq -oj "${fileName}") # Convert to JSON.

  unset needDefaultShells
  local count
  count=$(countRunsWithDefaultedShell <<< "${workflow}")
  [[ "${count}" -eq 0 ]] || needDefaultShells=true
  unset count
  return

  local workflowShell jobShell stepShell
  workflowShell=$(yq '.defaults.run.shell // ""' "${fileName}")
  while IFS= read -r job; do
    local jobId jobValue jobShell jobOses
    jobId=$(jq -r .key <<< "${job}")
    jobValue=$(jq -c .value <<< "${job}")
    jobShell=$(jq -c '.defaults.run.shell//empty' <<< "${jobValue}")
    local defaultShells=${jobShell}
    [[ -n "${defaultShells}" ]] || defaultShells="${workflowShell}"
    [[ -n "${defaultShells}" ]] || {
      jobOses=($(getJobOs "${jobId}" "${jobValue}"))
      for jobOs in "${jobOses[@]}"; do
        echo "XXX ${defaultRunShell[${jobOs}]}"
      done | sort -u
    }
    #for defaultShell in ${defaultShells}; do
    #continue
      #echo "Checking as OS: ${jobOs}" >&2
      #while IFS= read -r step; do
      #  stepId=$(jq -r .key <<< "${step}")
      #  script=$(jq -r .value.run <<< "${step}")
      #  echo "Checking: ${jobId}[${stepId}]" >&2
      #  {
      #    echo '# GitHub environment variables'
      #    printf 'export %s=\n' "${defaultEnvVars[@]}"
      #    echo '# Workflow environment variables'
      #    yq '.env // {}|keys[]|"export "+.' "${fileName}"
      #    echo '# Job environment variables'
      #    jq '.env//{}|keys[]|"export "+.' <<< "${job}"
      #    echo '# Step environment variables'
      #    jq -r '.value.env//{}|keys[]|"export "+.' <<< "${step}"
      #    echo '# Shell script (with ${{ ... }} expressions removed)'
      #    sed -e 's|\${{[^}]\+}}||g' <<< "${script}"
      #  } | shellcheck --shell bash /dev/stdin || failures+=( "${fileName}::jobs.${jobId}.steps[${stepId}]" )
      #done
    #done < <(jq -c '.value.steps//{}|to_entries[]|select(.value.run)' <<< "${job}")
  done < <(yq -I 0 -o json '.jobs|to_entries[]' "${fileName}")
}

declare -a failures=()
for path in "${@:-.}"; do
  if [[ -d "${path}" ]]; then
    [[ ! -d "${path%/}/.github/workflows" ]] || path="${path%/}/.github/workflows"
    echo "Checking directory: ${path}" >&2
    foundFilesCount=0
    while IFS= read -d '' -r fileName; do
      : $((foundFilesCount++))
      checkWorkflow "${fileName}"
    done < <(find "${path}" -maxdepth 1 -type f -name '*.yaml' -print0	|| :)
    [[ "${foundFilesCount}" -gt 0 ]] || { echo "Found no workflow files in: ${path}"; exit 1; }
  elif [[ -e "${path}" ]]; then
    checkWorkflow "${path}"
  else
    echo "Path does not exist: ${path}" >&2
  fi
done
[[ "${#failures[0]}" -eq 0 ]] || printf 'Checks failed for: %s\n' "${failures[@]}" >&2
[[ "${#failures[0]}" -eq 0 ]]
