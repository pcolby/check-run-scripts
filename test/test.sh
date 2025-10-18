#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 Paul Colby <git@colby.id.au>
# SPDX-License-Identifier: MIT

set -o errexit -o noclobber -o nounset -o pipefail
shopt -s inherit_errexit

selfPath=$(realpath -e "${BASH_SOURCE[0]}")
testDir=$(dirname "${selfPath}")
projectDir=$(dirname "${testDir}")
readonly selfPath testDir projectDir

# shellcheck source=../check-run-scripts.sh
UNIT_TESTING_ONLY=true . "${projectDir}/check-run-scripts.sh"

function runTest {
  local -r test="${1}"
  local -r fileName="${2}"
  local -r testIndex="${3}"
  debug "Running test: ${test}"
  local name func input args expected actual
  IFS=$'\x1F' read -d '' -r name func input expected < <(jq -r \
    '[ .name, .function, (.input|tojson), .expected ]|join("\u001F")+"\u0000"' <<< "${test}" || :)
  info "Running test: ${fileName##*/}[${testIndex}] ${name@Q}"
  [[ "${input}" != 'null' ]] || input=
  mapfile -t args < <(jq -cr '.args[]?' <<< "${test}" || :)
  debug "Invoking ${func} with ${#args[@]} arguments and ${#input} chars of input"
  actual=$("${func}" "${args[@]}" <<< "${input}" || :)
  [[ "${actual}" == "${expected}" ]] || {
    error "Test failed: ${fileName##*/}[${testIndex}] ${name@Q}"
    error "  Expected: ${expected@Q}"
    error "  Actual:   ${actual@Q}"
    failures+=( "${fileName}[${testIndex}] ${name@Q}" )
  }
}

function runTests {
  local -r fileName="${1}"
  debug "Running test: ${fileName}"
  while IFS= read -r test; do
    testIndex=$(jq -r .index <<< "${test}")
    debug "Running test: ${fileName}[${testIndex}]"
    runTest "${test}" "${fileName}" "${testIndex}"
  done < <(yq -I0 -oj "${fileName}" | jq -cs 'to_entries[]|{index:.key}+.value' || :)
}

declare -a failures=()

for testFile in "${@}"; do
  runTests "${testFile}"
done

[[ "${#}" -ge 1 ]] || while IFS= read -d '' -r fileName; do
  runTests "${fileName}"
done < <(find "${testDir}" -name '*.yaml' -type f -print0 || :)

[[ "${#failures[0]}" -eq 0 ]] || printf 'Test failed: %s\n' "${failures[@]}" >&2
[[ "${#failures[0]}" -eq 0 ]]
