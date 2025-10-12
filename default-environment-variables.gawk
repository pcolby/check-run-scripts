# SPDX-FileCopyrightText: 2025 Paul Colby <git@colby.id.au>
# SPDX-License-Identifier: MIT

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
