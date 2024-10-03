#!/bin/sh -l

# $1 : commands
# $2 : target
# $3 : timeout
# $4 : concurrency
# $5 : silent
# $6 : headers
# $7 : verbose
# $8 : include30x
# -------------

export df=/usr/local/bundle/gems/deadfinder-*/bin/deadfinder

# Construct the command with additional options
cmd="$df $1 $2 -o /output.json"
[ -n "$3" ] && cmd="$cmd --timeout=$3"
[ -n "$4" ] && cmd="$cmd --concurrency=$4"
[ "$5" = "true" ] && cmd="$cmd --silent"
[ "$7" = "true" ] && cmd="$cmd --verbose"
[ "$8" = "true" ] && cmd="$cmd --include30x"

# Add headers if provided
if [ -n "$6" ]; then
  IFS=',' read -r -a headers_array <<< "$6"
  for header in "${headers_array[@]}"; do
    cmd="$cmd -H \"$header\""
  done
fi

# Execute the command
eval $cmd

# Read the output and set it as a GitHub Action output
out=$(cat /output.json)
echo "output=$out" >> $GITHUB_OUTPUT