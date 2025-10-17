#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 Paul Colby <git@colby.id.au>
# SPDX-License-Identifier: MIT

set -o errexit -o noclobber -o nounset -o pipefail
shopt -s inherit_errexit

selfPath=$(realpath -e "${BASH_SOURCE[0]}")
testDir=$(dirname "${selfPath}")
projectDir=$(dirname "${testDir}")
readonly selfPath testDir projectDir

# shellcheck source=../check-workflow-scripts.sh
UNIT_TESTING_ONLY=true . "${projectDir}/check-workflow-scripts.sh"

function runTest {
  local -r fileName="${1}"
  debug "Running test: ${fileName}"
  warn 'runTest not implemented'
}

declare -a failures=()

for testFile in "${@}"; do
  runTest "${testFile}"
done

[[ "${#}" -ge 1 ]] || while IFS= read -d '' -r fileName; do
  runTest "${fileName}"
done < <(find "${testDir}" -name '*.yaml' -type f -print0 || :)

[[ "${#failures[0]}" -eq 0 ]] || printf 'The following tests failed: %s\n' "${failures[@]}" >&2
[[ "${#failures[0]}" -eq 0 ]]
