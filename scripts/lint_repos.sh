#!/bin/bash
#
# Linting all repositories of a Github organization
#
# Usage:
#   ./lint_repos.sh --org <organization_name> [--dry-run]
#
# Parameters:
#   --org: The name of the organization on GitHub.
#   --dry-run: Optional flag to simulate script execution without making changes.
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

# Check setup
if ! command -v repolinter &> /dev/null || ! command -v gh &> /dev/null; then
    echo "repolinter and gh are required. Please install them before running the script."
    exit 1
fi

# Parse command line parameters
ORG_NAME=""
DRY_RUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        --org)
            shift
            ORG_NAME=$1
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

# Check if organization name is provided
if [ -z "$ORG_NAME" ]; then
    echo "Please provide the organization name using --org option."
    exit 1
fi


# Checks if an issue is open and returns the issue number.
issue_number() {
  local repo="$1"
  local issue_title="$2"

  gh issue list -R "$repo" --state open --json number,title |  jq -r ".[] | select(.title == \"$issue_title\") | .number"
}


# Creates a new GitHub issue or skips the creation if one already exists.
create_issue_if_not_exists() {
  local repo="$1"
  local issue_title="$2"
  local issue_body=$(echo -e "$3")

  existing_issue_number=$(issue_number "$repo" "$issue_title")
  if [ -z "$existing_issue_number" ]; then
      if [ "$DRY_RUN" = true ]; then
        DRY_RUN_MESSAGES+="Dry run: Would create an issue for repository '$repo'.\n"
      else
        gh issue create -R "$repo" --title "$issue_title" --body "$issue_body"
      fi
  else
    echo "An open issue already exists in the repository '$repo'. Skipping creation."
  fi
}


# Closes an open GitHub issue with a given title.
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
# Description:
#   This function fetches the repolinter configuration for a given GitHub repository. It first
#   checks if the repository provides a local configuration file at
#   "https://raw.githubusercontent.com/<repository>/main/.github/repolinter.yaml." If found,
#   this local configuration is retrieved. If no local configuration exists, the function falls
#   back to the global configuration specified by GLOBAL_CONFIG_URL.
#
#   The purpose of this function is to allow repositories to have custom linting configurations,
#   providing flexibility for different projects while ensuring a consistent global standard for linting.
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
# Description:
#   This function performs linting on all public repositories within the specified GitHub organization
#   using repolinter. It iterates over each repository, runs repolinter, checks for compliance with 
#   guidelines and creates a report in the output results.
#
#   The linting process involves the following steps:
#     1. Retrieve the list of public repositories in the organization.
#     2. For each repository, run repolinter with the provided configuration and output the results
#        to a markdown file in the results directory.
#     3. Check the exit code of repolinter. If non-compliant, create an issue in the repository
#        with linting details.
#
lint_repos() {
  local org_name="$1"
  rm -Rf $OUTPUT_DIR/$org_name
  mkdir -p "$OUTPUT_DIR/$org_name"

  # Loop through each repository and perform linting
  local repos=$(gh repo list "$org_name" --visibility public --no-archived -L 100 | awk '{print $1}')
  for repo in $repos; do
      echo
      echo "Linting the repository '$repo'..."
          
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