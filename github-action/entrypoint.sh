#!/bin/sh -l

# $1 : commands
# $2 : target
# -------------

export df=/usr/local/bundle/gems/deadfinder-*/bin/deadfinder

case $1 in
	'file')
		$df file $2 -o /output.json
		;;
	'url')
		$df url $2 -o /output.json
		;;
	'sitemap')
		$df sitemap $2 -o /output.json
		;;
esac

out=$(cat /output.json)
echo "output=$out" >> $GITHUB_OUTPUT
