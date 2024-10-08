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
  IFS=',' headers="$6"
  for header in $headers; do
    if [ -n "$header" ]; then
      cmd="$cmd -H \"$header\""
    fi
  done
fi

# Execute the command
eval "$cmd"
echo "Command executed: $cmd"

# Check if the output file exists
if [ ! -f /output.json ]; then
  echo "Error: /output.json not found"
  exit 1
fi

# Read the output and set it as a GitHub Action output
out=$(cat /output.json)
encoded_output=$(echo "$out" | jq -R -s '.')

echo "output=$encoded_output" >> $GITHUB_OUTPUT