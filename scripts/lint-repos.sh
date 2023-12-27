#!/bin/bash
cd "$(dirname "$0")"
rm -Rf ../results

# Function to check if an open issue with the same title already exists
issue_exists() {
  REPO=$1
  ISSUE_TITLE=$2
  gh issue list -R "$REPO" --state open --json number,title |  jq -r ".[] | select(.title == \"$ISSUE_TITLE\") | .number"
}

# Function to create an issue if it doesn't already exist
create_issue_if_not_exists() {
  REPO=$1
  ISSUE_TITLE=$2
  ISSUE_BODY=$(echo -e "$3")
  existing_issue_number=$(issue_exists "$REPO" "$ISSUE_TITLE")
  if [ -z "$existing_issue_number" ]; then
    gh issue create -R "$REPO" --title "$ISSUE_TITLE" --body "$ISSUE_BODY"
  else
    echo "An open issue already exists in the repository '$REPO'. Skipping"
  fi
}

# Function to close an issue
close_issue() {
  REPO=$1
  ISSUE_TITLE=$2
  ISSUE_NUMBER=$(issue_exists "$REPO" "$ISSUE_TITLE")
  if [ -n "$ISSUE_NUMBER" ]; then
    gh issue close -R "$REPO" "$ISSUE_NUMBER"
    echo "Closed the existing issue in the repository '$REPO'."
  fi
}

# Function to get the repolinter.yaml content for the repository
get_repolinter_config() {
  REPO=$1
  LOCAL_CONFIG_URL="https://raw.githubusercontent.com/$REPO/main/.github/repolinter.yaml"
  GLOBAL_CONFIG_URL="https://raw.githubusercontent.com/test-user-org/admin/main/.github/repolinter.yaml"
  LOCAL_CONFIG=$(curl -s "$LOCAL_CONFIG_URL")
  if [ "$LOCAL_CONFIG" != "404: Not Found"  ]; then
    echo "$LOCAL_CONFIG"
  else
    curl -s $GLOBAL_CONFIG_URL
  fi
}


# Loop through each repository and create an issue
REPOS=$(gh repo list $ORG_NAME --visibility public -L 100 | awk '{print $1}')
for REPO in $REPOS; do
    echo
    echo "Linting the repository '$REPO'..."
    mkdir -p ../results/$REPO
    repolinter -g https://github.com/$REPO -f markdown -u <(get_repolinter_config "$REPO")  > ../results/$REPO.md
    if [ $? -eq 1 ] ; then
        failure="The repository '$REPO' is not compliant with Allianz guidelines. Please review https://developer.portal.allianz/docs/default/component/open-source-guide"
        report=`cat ../results/$REPO.md`
        create_issue_if_not_exists "$REPO" "Repo lint error" "$failure\n\n$report"
    else
        close_issue "$REPO" "Repo lint error" 
    fi
done
