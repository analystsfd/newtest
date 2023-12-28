#!/bin/bash

# Linting all repositories of a Github organization
#
# Usage:
#   ./lint_repos.sh <organization_name> [--dry_run]
#
# Parameters:
#   organization_name: The name of the organization on GitHub.
#   --dry_run: Optional flag to simulate script execution without making changes.
#
# Description:
#   This script retrieves a list of public repositories in the specified GitHub organization
#   and performs linting using repolinter. For each repository, it creates a directory for the output,
#   runs repolinter, and checks for compliance. If a repository is non-compliant, it creates or updates
#   an issue with linting details.
cd "$(dirname "$0")"

# Static configuration
GLOBAL_CONFIG_URL="https://raw.githubusercontent.com/allianz/ospo/main/config/policies.yaml"
OUTPUT_DIR="../results"

# Clean up previous run
rm -Rf $OUTPUT_DIR

# Check setup
if ! command -v repolinter &> /dev/null || ! command -v gh &> /dev/null; then
    echo "repolinter and gh are required. Please install them before running the script."
    exit 1
fi

# Parse command line parameters
if [ $# -eq 0 ]; then
    echo "Please provide the organization name as a command-line argument."
    exit 1
fi
ORG_NAME=$1
shift
dry_run=false
while [ $# -gt 0 ]; do
    case "$1" in
        --dry_run)
            DRY_RUN=true
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done


# Checks if an issue is open and returns the issue number.
#
# Usage:
#   issue_number <repo> <issue_title>
#
# Returns:
#   The issue number if an open issue with the specified title exists, otherwise, returns empty.
issue_number() {
  local repo="$1"
  local issue_title="$2"

  gh issue list -R "$REPO" --state open --json number,title |  jq -r ".[] | select(.title == \"$$issue_title\") | .number"
}


# Creates a new GitHub issue or skips the creation if one already exists.
#
# Usage:
#   create_issue_if_not_exists <repo> <issue_title> <issue_body>
#
# Dry Run:
#   If --dry_run option is set, the function prints a message about the planned action
#   without actually creating or updating the issue.
create_issue_if_not_exists() {
  local repo="$1"
  local issue_title="$2"
  local issue_body=$(echo -e "$3")

  if [ "$DRY_RUN" = true ]; then
    DRY_RUN_MESSAGES+="Dry run: Would create an issue for repository '$repo'.\n"
  else
    existing_issue_number=$(issue_number "$repo" "$issue_title")
    if [ -z "$existing_issue_number" ]; then
      gh issue create -R "$repo" --title "$issue_title" --body "$issue_body"
    else
      echo "An open issue already exists in the repository '$repo'. Skipping creation."
    fi
  fi
}


# Closes an open GitHub issue with a given title.
#
# Usage:
#   close_issue <repo> <issue_title>
close_issue() {
  local repo="$1"
  local issue_title="$2"
  local issue_number=$(issue_number "$repo" "$issue_title")

  if [ -n "$issue_number" ]; then
    gh issue close -R "$repo" "$issue_number"
    echo "Closed the existing issue in the repository '$repo'."
  fi
}


# Retrieves the repolinter configuration for a GitHub repository to be scanned.
#
# Usage:
#   get_repolinter_config <repo>
#
# Returns:
#   The repolinter configuration for the specified repository.
get_repolinter_config() {
  local repo="$1"
  local local_config_url="https://raw.githubusercontent.com/$repo/main/.github/repolinter.yaml"

  if [ "$(curl -k -s -o /dev/null -w "%{http_code}" "$local_config_url")" -eq 200 ]; then
    echo "Repository '$repo' provides a local repolinter configuration."
    curl -k -s "$local_config_url"
  else
    curl -k -s "$GLOBAL_CONFIG_URL"
  fi
}


# Lint GitHub repositories within a specified organization using repolinter.
#
# Usage:
#   lint_repos <organization_name>
#
lint_repos() {
  local org_name="$1"

  # Loop through each repository and perform linting
  local repos=$(gh repo list "$org_name" --visibility public --no-archived -L 100 | awk '{print $1}')
  for repo in $repos; do
      echo
      echo "Linting the repository '$repo'..."
      
      # Create directory for lint output for each repo
      mkdir -p "$OUTPUT_DIR/$repo"
      
      # Run repolinter on the repository
      repolinter -g "https://github.com/$repo" -f markdown -u <(get_repolinter_config "$repo") > "$OUTPUT_DIR/$repo.md"
      
      # Check the exit code of repolinter
      if [ $? -eq 1 ]; then
          failure="The repository '$repo' is not compliant with Allianz guidelines. Please review https://developer.portal.allianz/docs/default/component/open-source-guide"
          report=$(cat "$OUTPUT_DIR/$repo.md")
          create_issue_if_not_exists "$repo" "Repo lint error" "$failure\n\n$report"
      else
          close_issue "$repo" "Repo lint error" 
      fi
  done
}

# Run the linting process
lint_repos "$ORG_NAME"


# Print dry run results
if [ "$DRY_RUN" = true ]; then
    echo -e "\nFindings:\n$DRY_RUN_MESSAGES" 
fi