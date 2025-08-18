#!/bin/bash
declare -A label_map

label_map["feat"]="feature"
label_map["ci"]="ci"
label_map["docs"]="documentation"
label_map["fix"]="bugfix"

PR_TITLE=${1}
echo "PR_TITLE=$PR_TITLE"

# extract PR_TITLE from colon prefix
PR_TITLE_PREFIX=${PR_TITLE%%:*}
echo "PR_TITLE_PREFIX=$PR_TITLE_PREFIX"

# default PR label to other
PR_LABEL="other"
echo "PR_LABEL=$PR_LABEL"
echo "DEBUG: label_map[\"$PR_TITLE_PREFIX\"]=${label_map[\"$PR_TITLE_PREFIX]\"}"
if [[ -n "${label_map[$PR_TITLE_PREFIX]}" ]]; then
  PR_LABEL="${label_map[$PR_TITLE_PREFIX]}"
fi
echo "PR_LABEL=$PR_LABEL"
# gh pr edit ${{ github.event.pull_request.number }} --repo ${{ github.repository }}  --add-label "${{ PR_LABEL }}"