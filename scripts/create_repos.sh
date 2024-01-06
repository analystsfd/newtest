#!/bin/bash
#
# GitHub Management Script
#
# Usage: ./create_repos.sh [--apply] [--debug]
#
# Parameters:
#   --apply: Apply changes to GitHub (default is dry-run mode).
#   --debug: Enable debug mode for additional information.
#
# Description:
#   This Bash script automates GitHub repository and team management based on a YAML configuration file.
#   It uses GitHub CLI (gh) and yq for interaction and configuration parsing, respectively.
#   The script can create, transfer, and synchronize repositories and teams, and it supports dry-run mode.

cd "$(dirname "$0")"
IFS=$'\n' # keep whitespace when iterating with for loops

# Static configuration
YAML_FILE="../config/repos.yaml"

# Install yq and gh (if not already installed)
if ! command -v yq &> /dev/null || ! command -v gh &> /dev/null; then
    echo "yq and gh are required. Please install them before running the script."
    exit 1
fi

# Parse command line parameters
DRY_RUN=true
DEBUG=false
while [ $# -gt 0 ]; do
    case "$1" in
        --apply)
            DRY_RUN=false
            ;;
        --debug)
            DEBUG=true
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done


# Helper function to print debug messages
print_debug() {
    local message="$1"
    if [ "$DEBUG" = true ]; then
        echo "$message"
    fi
}


# Function to validate the structure of the YAML configuration
validate_yaml() {
    for repo_name in $(yq eval '.repositories[].name' "$YAML_FILE"); do
        if [[ ! "$repo_name" =~ ^[a-z0-9.-]+$ ]]; then
            echo "Invalid repository name: '$repo_name'. The name must match the pattern ^[a-z0-9.-]+$.">&2; exit 1
        fi
    done
    for stage in $(yq eval '.repositories[].stage' "$YAML_FILE"); do
        if [[ "$stage" != "allianz" && "$stage" != "allianz-incubator" ]]; then
            echo "Invalid stage: $stage. Only allianz and allianz-incubator allowed.">&2; exit 1
        fi
    done
}


# Function to create a new GitHub repository
create_repo() {
    local name=$1
    local org=$2

    if [ "$DRY_RUN" = true ]; then
        DRY_RUN_MESSAGES+="+ Would create repository: $name in $org.\n"
    else
        gh repo create $org/$name --public --template="allianz-incubator/new-project"

        if [ $? -eq 0 ] && [ "$(echo $response | jq -r '.id')" != "null" ]; then
            echo -e "\e[32m✓\e[0m Repository '$name' successfully created in organization $org."
        else
            echo "Error creating repo '$name' at line $LINENO. $response.">&2; exit 1;
        fi
    fi
}


# Function to transfer a GitHub repository from one organization to another
transfer_repo() {
    local name=$1

    if [ "$DRY_RUN" = true ]; then
        DRY_RUN_MESSAGES+="~ Would transfer repository $name from allianz-incubator to allianz.\n"
    else
        local response=$(gh api \
            --method POST \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            repos/allianz-incubator/$name/transfer \
            -f new_owner=allianz)

        if [ $? -eq 0 ] && [ "$(echo $response | jq -r '.id')" != "null"  ]; then
            echo -e "\e[32m✓\e[0m Repository '$name' successfully transfered to organization allianz."
        else
            echo "Error transfering repo '$name' at line $LINENO. $response.">&2; exit 1;
        fi
    fi
}


# Function to create a new GitHub team and set up team synchronization
create_team() {
    local name=$1
    local org=$2
    local giam_name=$name

    # Get Azure AD group required for team sync
    local ad_group=$(gh api -XGET \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -F q="$giam_name" /orgs/$org/team-sync/groups)
    
    if [[ ! "$ad_group" == *'"groups":'* || $(jq '.groups | length' <<< "$ad_group") -ne 1 ]]; then
        echo "Error: No or more than one AD group with name '$giam_name' found.">&2;
        echo $ad_group | jq '.groups[].group_name'
        exit 1
    fi

    # Create the team
    if [ "$DRY_RUN" = true ]; then
        DRY_RUN_MESSAGES+="+ Would create team: '$name' in $org.\n"
    else
        local response=$(gh api \
           --method POST \
           -H "Accept: application/vnd.github+json" \
           -H "X-GitHub-Api-Version: 2022-11-28" \
            /orgs/$org/teams \
           -f name="$name") 
        
        if [ $? -eq 0 ] && [ "$(echo $response | jq -r '.id')" != "null" ]; then
            echo -e "\e[32m✓\e[0m Team '$name' created successfully in organization '$org'."
        else
            echo "Error creating team '$name' at line $LINENO. $response.">&2; exit 1;
        fi
    fi

    # Activate Azure AD team sync by assigning the AD group to the team
    load_teams # Update cache to include new team slug
    local slug_name=$(get_team_slug $name) || exit 1
    if [ "$DRY_RUN" = true ]; then
        DRY_RUN_MESSAGES+="+ Would setup team sync: team '$name' with AD Group '$giam_name'.\n"
    else
        local response=$(echo $ad_group | gh api \
            --method PATCH   \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            /orgs/$org/teams/$slug_name/team-sync/group-mappings \
            --input -)
        
        if [ $? -eq 0 ] && [ $(echo "$response" | jq '.groups | length') -ge 1 ]; then
            echo -e "\e[32m✓\e[0m Team '$name' successfully syncing with AD Group '$giam_name'."
        else
            echo "Error when enabling team sync of '$slug_name' with AD '$giam_name' at line $LINENO. $response.">&2; exit 1;
        fi
    fi
}


# Function to delete a GitHub team
delete_team() {
    local name=$1
    local org=$2
    local slug_name=$(get_team_slug $name) || exit 1

    if [ "$DRY_RUN" = true ]; then
        DRY_RUN_MESSAGES+="- Would delete team: $name in $org.\n"
    else
        local response=$(gh api \
            --method DELETE \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            /orgs/$org/teams/$slug_name) 
        
        if [ $? -eq 0 ] && [ -z "$response" ]; then
            echo -e "\e[32m✓\e[0m Team '$name' deleted successfully in organization '$org'."
        else
            echo "Error deleting team '$slug_name' at line $LINENO. $response.">&2; exit 1;
        fi
    fi
}


# Function to grant permissions to a team on specified repositories
grant_permissions() {
    local name=$1
    local org=$2
    local repos_to_assign=$3
    local slug_name=$(get_team_slug $name) || exit 1

    for repo in $repos_to_assign; do
        if [ "$DRY_RUN" = true ]; then
            DRY_RUN_MESSAGES+="+ Would grant owner permission: team '$name' in $org/$repo.\n"
        else
            local response=$(gh api \
                --method PUT \
                -H "Accept: application/vnd.github+json" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                /orgs/$org/teams/$slug_name/repos/$org/$repo \
                -f permission='push')

            if [ $? -eq 0 ] && [ -z "$response" ]; then
                echo -e "\e[32m✓\e[0m Team '$name' granted owner prermissions in repository '$repo'."
            else
                echo "Error granting permissions for team '$slug_name' to repo '$repo' at line $LINENO. $response">&2; exit 1;
            fi
        fi
    done
}


# Function to revoke permissions from a team on specified repositories
revoke_permissions() {
    local name=$1
    local org=$2
    local repos_to_remove=$3
    local slug_name=$(get_team_slug $name)

    for repo in $repos_to_remove; do
        if [ "$DRY_RUN" = true ]; then
            DRY_RUN_MESSAGES+="- Would remove owner permission: team '$name' in $org/$repo.\n"
        else
            local response=$(gh api \
                --method DELETE \
                -H "Accept: application/vnd.github+json" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                /orgs/$org/teams/$slug_name/repos/$org/$repo)

            if [ $? -eq 0 ] && [ -z "$response" ]; then
                echo -e "\e[32m✓\e[0m Team '$name' removed owner prermissions in repository '$repo'."
            else
                echo "Error removing permissions of team '$slug_name' from repo '$repo' at line $LINENO. $repsonse">&2; exit 1;
            fi
        fi
    done
}


# Function to load existing repositories from GitHub
load_repositories() {
    local org=$1

    local repos=$(gh repo list $org --json name --limit 1000 )|| {
        echo "Error fetching repos for allianz at line $LINENO. $repos." >&2; exit 1; }

    if [ "$repos" = "[]" ]; then
        echo "No repositories found for $org (line $LINENO)." >&2; exit 1
    else
        echo "$repos" | jq -r '.[].name' | sort -u
    fi
}


# Function to load existing teams from GitHub
load_teams() {
    CACHED_ALLIANZ_TEAMS=$(gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" /orgs/allianz/teams) || {
        echo "Error fetching teams for allianz at line $LINENO. $CACHED_ALLIANZ_TEAMS."; exit 1; }

    CACHED_ALLIANZ_INCUBATOR_TEAMS=$(gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" /orgs/allianz-incubator/teams) || {
        echo "Error fetching teams for allianz-incubator at line $LINENO. $CACHED_ALLIANZ_INCUBATOR_TEAMS."; exit 1; }
}


# Function to load permissions of a team on repositories
load_team_permissions(){
    local org_name="$1"
    local team_name="$2"
    local team_slug=$(get_team_slug $team_name) || exit 1   

    repos_for_team=$(gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "/orgs/$org_name/teams/$team_slug/repos?per_page=100") || {
        echo "Error fetching repositories for team '$team_slug' for '$org_name' at line $LINENO. $existing_repos_for_team.">&2; exit 1; }

    echo $repos_for_team | jq -r '.[].name'
}


# Function to get the list of teams for a given organization
get_teams(){
    local org="$1"

    if [ "$org" == "allianz" ]; then
        echo "$CACHED_ALLIANZ_TEAMS"
    else
        echo "$CACHED_ALLIANZ_INCUBATOR_TEAMS"
    fi
}


# Function to get the slug of a team by its name
get_team_slug(){
    local name="$1"

    # Search for the team in both organizations
    local slug_allianz=$(jq -r '.[] | select(.name == "'"$name"'") | .slug' <<< "$CACHED_ALLIANZ_TEAMS") || exit 1
    local slug_incubator=$(jq -r '.[] | select(.name == "'"$name"'") | .slug' <<< "$CACHED_ALLIANZ_INCUBATOR_TEAMS") || exit 1

    # Return the first non-empty slug found
    if [ -n "$slug_allianz" ]; then
        echo "$slug_allianz"
    elif [ -n "$slug_incubator" ]; then
        echo "$slug_incubator"
    else
        echo "Error: team slug not found for $name" >&2; exit 1
    fi
}


# Function to process repositories based on the YAML configuration
#
# This function reads the YAML configuration file to determine the desired state of GitHub repositories
# for both the 'allianz' and 'allianz-incubator' organizations. It then compares this desired state with
# the existing repositories on GitHub and performs the necessary actions to align them.
# Actions include creating new repositories, transferring repositories between organizations, and printing
# warnings for inconsistent repository configurations.
#
process_repos() {
    echo "READING REPOSITORIES..."

    # Status
    local existing_main_repos=$(load_repositories allianz) || exit 1
    local existing_incubator_repos=$(load_repositories allianz-incubator) || exit 1
    local desired_main_repos=$(yq eval '.repositories[] | select(.stage == "allianz") | .name' "$YAML_FILE" | sort -u) || exit 1
    local desired_incubator_repos=$(yq eval '.repositories[] | select(.stage == "allianz-incubator") | .name' "$YAML_FILE" | sort -u) || exit 1

    ## calculate changes
    local repos_to_add_in_incubator=$(comm -23 <(echo "$desired_incubator_repos") <(echo "$existing_incubator_repos")) || exit 1
    local repos_to_add_in_main=$(comm -23 <(comm -23 <(echo "$desired_main_repos") <(echo "$existing_main_repos")) <(echo "$existing_incubator_repos")) || exit 1
    local repos_to_transfer_to_main=$(comm -12 <(comm -23 <(echo "$desired_main_repos") <(echo "$existing_main_repos")) <(echo "$existing_incubator_repos")) || exit 1
   
    # Debug
    print_debug
    print_debug "Existing Repositories in allianz:"
    print_debug "$existing_main_repos" | sed 's/^/  /'
    print_debug
    print_debug "Desired Repositories in allianz:"
    print_debug "$desired_main_repos" | sed 's/^/  /'
    print_debug
    print_debug "Repositories to Add in allianz:"
    print_debug "$repos_to_add_in_main" | sed 's/^/  /'
    print_debug
    print_debug "Repositories to Transfer to allianz:"
    print_debug "$repos_to_transfer_to_main" | sed 's/^/  /'
    print_debug
    print_debug "Existing Repositories in allianz-incubator:"
    print_debug "$existing_incubator_repos" | sed 's/^/  /'
    print_debug
    print_debug "Desired Repositories in allianz-incubator:"
    print_debug "$desired_incubator_repos" | sed 's/^/  /'
    print_debug
    print_debug "Repositories to Add in allianz-incubator:"
    print_debug "$repos_to_add_in_incubator" | sed 's/^/  /'
    print_debug


    # Iterate over changes
    for repo in $repos_to_add_in_incubator; do
        create_repo $repo "allianz-incubator"
    done
    for repo in $repos_to_add_in_main; do
        create_repo $repo "allianz"
    done
    for repo in $repos_to_transfer_to_main; do
        transfer_repo $repo
    done
}

# Function to process teams based on the YAML configuration and existing teams
# 
# This function manages GitHub teams for either the 'allianz' and 'allianz-incubator' organizations,
# aligning them with the desired state specified in the YAML configuration file.
# It reads the configuration to determine the desired teams, their associated repositories,
# and the necessary actions to synchronize them with the existing teams on GitHub.
#
# The function identifies teams to be added, updated, or deleted based on the configuration.
# For teams to be added, it creates the team and grants appropriate permissions on the associated repositories.
# For existing teams, it updates team memberships and permissions according to the YAML configuration.
# Teams marked for deletion are removed from GitHub.
#
process_teams() {
    local org_name="$1"
    echo -e "READING $org_name TEAMS..."
    
    # Status
    local existing_teams=$(get_teams $org_name | jq -r '.[].name' | sort) || exit 1
    local desired_teams=$(yq eval '.repositories[] | select(.stage == "'"$org_name"'") | .teams[].name' "$YAML_FILE" | sort -u) || exit 1

    # Calculate changes
    local teams_to_add=$(comm -23 <(echo "$desired_teams") <(echo "$existing_teams")) || exit 1
    local teams_to_update=$(comm -12 <(echo "$desired_teams") <(echo "$existing_teams")) || exit 1
    local teams_to_remove=$(comm -13 <(echo "$desired_teams") <(echo "$existing_teams" )) || exit 1

    # Debug
    print_debug
    print_debug "Existing Teams in $org_name:"
    print_debug "$existing_teams" | sed 's/^/  /'
    print_debug
    print_debug "Desired Teams for $org_name:"
    print_debug "$desired_teams" | sed 's/^/  /'
    print_debug   

    # Iterate over teams to add
    print_debug "Teams to Add for $org_name:"
    for team in $teams_to_add; do
    
        # Status
        local desired_repos_for_team=$(yq eval '.repositories[] | select(.teams[].name == "'"$team"'") | .name' "$YAML_FILE" | sort -u) || exit 1

        # Debug
        print_debug "  $team"
        print_debug "    repos:"
        print_debug "$desired_repos_for_team" | sed 's/^/      /'

        # Apply
        create_team "$team" $org_name
        grant_permissions "$team" $org_name $desired_repos_for_team
    done
    print_debug

    # Iterate over teams to update
    print_debug "Teams to Update for $org_name:"
    for team in $teams_to_update; do

        # Status
        local existing_repos_for_team=$(load_team_permissions $org_name $team | sort) || exit 1
        local desired_repos_for_team=$(yq eval '.repositories[] | select(.teams[].name == "'"$team"'") | .name' ../config/repos.yaml | sort -u) || exit 1
        
        # Debug
        print_debug "  $team"
        print_debug "    status:"
        print_debug "      existing repo assignments:"
        print_debug "$existing_repos_for_team" | sed 's/^/        /'
        print_debug "      desired repo assignments:"
        print_debug "$desired_repos_for_team" | sed 's/^/        /'

        # Calculate changes
        local repos_to_add=$(comm -23 <(echo "$desired_repos_for_team") <(echo "$existing_repos_for_team")) || exit 1
        local repos_to_remove=$(comm -13 <(echo "$desired_repos_for_team") <(echo "$existing_repos_for_team")) || exit 1
        
        # Debug
        print_debug "    changes:"
        print_debug "      assignments to add:"
        print_debug "$repos_to_add" | sed 's/^/        /'
        print_debug "      assignments to remove:"
        print_debug "$repos_to_remove" | sed 's/^/        /'

        # Apply
        grant_permissions $team $org_name $repos_to_add
        revoke_permissions $team $org_name $repos_to_remove
    done

    # Iterate over teams to delete
    print_debug "Teams to Delete for $org_name:"
    for team in $teams_to_remove; do
        print_debug "  $team"
        delete_team $team $org_name
    done
}

# Run
validate_yaml
process_repos
load_teams
process_teams allianz
process_teams allianz-incubator

# Print warnings
if [ -n "$warning_messages" ]; then
    echo -e "\nWarning Messages:"
    echo -e "$warning_messages" | sed 's/^/  /'
fi

# Print dry run results
if [ "$DRY_RUN" = true ]; then
    echo -e "\nPlanned changes:\n$DRY_RUN_MESSAGES" 
fi

