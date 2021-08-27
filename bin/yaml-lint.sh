#!/usr/bin/env bash

if ! command -v yamllint &> /dev/null
then
  pip install --user yamllint
fi


find ./addons -mtime -1 -name '*.yaml' -print0 | 
	while IFS= read -r -d '' line; do
		echo "$line"
		# strip all the {{kurl }} directives out of the yaml before we lint it
		sed -r 's/^\s*\{\{kurl[^\}]*\}\}\s*$//' < "$line" | yamllint - 
	done

