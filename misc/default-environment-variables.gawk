# SPDX-FileCopyrightText: 2025 Paul Colby <git@colby.id.au>
# SPDX-License-Identifier: MIT
#
# A simply GAWK script that be use used to build the check-run-scripts.sh script's defaultEnvVars array. See
# https://docs.github.com/en/actions/reference/workflows-and-actions/variables#default-environment-variables
#
# curl -s https://docs.github.com/en/actions/reference/workflows-and-actions/variables |
#   gawk -f default-environment-variables.gawk

BEGIN {
  FS="<tr><td>"
  print "readonly -a defaultEnvVars=("
}

/^<table aria-labelledby="default-environment-variables">/ {
  for (i = 1; i <= NF; ++i)
    if (match($i, /^<code>([A-Z_]+)</, groups))
      print "  "groups[1]
}

END { print ")" }
