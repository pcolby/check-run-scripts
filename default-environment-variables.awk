BEGIN {
  FS="<tr><td>"
  print "readonly defaultEnvVars=("
}

/^<table aria-labelledby="default-environment-variables">/ {
  for (i = 1; i <= NF; ++i)
    if (match($i, /^<code>([A-Z_]+)</, groups))
      print "  "groups[1]
}

END { print ")" }
