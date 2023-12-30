#!/bin/bash
cd "$(dirname "$0")"
IFS=$'\n' # keep whitespace when iterating with for loops


YAML_FILE="../config/repos.yaml"

# Install yq and gh (if not already installed)
if ! command -v yq &> /dev/null || ! command -v gh &> /dev/null; then
    echo "yq and gh are required. Please install them before running the script."
    exit 1
fi

dry_run=true
debug=false
while [ $# -gt 0 ]; do
    case "$1" in
        --apply)
            dry_run=false
            ;;
        --debug)
            debug=true
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
    if [ "$debug" = true ]; then
        echo "$message"
    fi
}


validate_config() {

    # Validate repository names
    for repo_name in $(yq eval '.repositories[].name' "$YAML_FILE"); do
        if [[ ! "$repo_name" =~ ^[a-z0-9.-]+$ ]]; then
            echo "Invalid repository name: '$repo_name'. The name must match the pattern ^[a-z0-9.-]+$."
            exit 1
        fi
    done

    # Validate stages
    for stage in $(yq eval '.repositories[].stage' "$YAML_FILE"); do
        if [[ "$stage" != "allianz" && "$stage" != "allianz-incubator" ]]; then
            echo "Invalid stage: $stage."
            exit 1
        fi
    done
}

create_repo() {
    local name=$1
    local org=$2

    if [ "$dry_run" = true ]; then
        dry_run_messages+="\e[32m+\e[0m Would create repository: $name in $org.\n"
    else
        gh repo create $org/$name --public --template="allianz-incubator/new-project"

        if [ $? -eq 0 ]; then
            echo -e "\e[32m✓\e[0m Repository '$name' successfully created in organization $org."
        else
            echo "Error creating repo. $response."; exit 1;
        fi
    fi
}

transfer_repo() {
    local name=$1

    if [ "$dry_run" = true ]; then
        dry_run_messages+="~ Would transfer repository $name from allianz-incubator to allianz.\n"
    else
        response=$(gh api \
        --method POST \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        repos/allianz-incubator/$name/transfer \
        -f new_owner=allianz)

        if [ $? -eq 0 ]; then
            echo -e "\e[32m✓\e[0m Repository '$name' successfully transfered to organization allianz."
        else
            echo "Error transfering team. $response."; exit 1;
        fi
    fi
}

create_team() {
    local name=$1
    local org=$2
    local giam_name=$name

    # Get AD group for team sync
    ad_group=$(gh api -XGET \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -F q="$giam_name" /orgs/$org/team-sync/groups)
    
    if [[ ! "$ad_group" == *'"groups":'* || $(jq '.groups | length' <<< "$ad_group") -ne 1 ]]; then
        echo "Error: No or more than one AD group with name '$giam_name' found."
        echo $ad_group | jq '.groups[].group_name'
        exit 1
    fi

    # Create team
    if [ "$dry_run" = true ]; then
        dry_run_messages+="\e[32m+\e[0m Would create team: '$name' in $org.\n"
    else
        response=$(gh api \
           --method POST \
           -H "Accept: application/vnd.github+json" \
           -H "X-GitHub-Api-Version: 2022-11-28" \
            /orgs/$org/teams \
           -f name="$name") 
        
        if [ $? -eq 0 ]; then
            echo -e "\e[32m✓\e[0m Team '$name' created successfully in organization '$org'."
        else
            echo "Error creating team. $response."; exit 1;
        fi
    fi

    # Update cache to include new group
    fill_teams_cache

    # Add AD group to team to activate team sync
    if [ "$dry_run" = true ]; then
        dry_run_messages+="\e[32m+\e[0m Would setup team sync: team '$name' with AD Group '$giam_name'.\n"
    else
        response=$(echo $ad_group | gh api \
          --method PATCH   \
          -H "Accept: application/vnd.github+json" \
          -H "X-GitHub-Api-Version: 2022-11-28" \
          /orgs/allianz-incubator/teams/$(get_team_slug $name)/team-sync/group-mappings \
          --input -)
        
        if [ $? -eq 0 ]; then
            echo -e "\e[32m✓\e[0m Team '$name' successfully syncing with AD Group '$giam_name'."
        else
            echo "Error when enabling team sync with AD. $response."; exit 1;
        fi
    fi
}

delete_team() {
    local name=$1
    local org=$2

    if [ "$dry_run" = true ]; then
        dry_run_messages+="\e[31m-\e[0m Would delete team: $name in $org.\n"
    else
        response=$(gh api \
        --method DELETE \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        /orgs/$org/teams/$(get_team_slug $name)) 
        
        if [ $? -eq 0 ]; then
            echo -e "\e[32m✓\e[0m Team '$name' deleted successfully in organization '$org'."
        else
            echo "Error deleting team. $response."; exit 1;
        fi
    fi
}

add_team_to_repo() {
    local name=$1
    local org=$2
    local repos_to_assign=$3

    for repo in $repos_to_assign; do
        if [ "$dry_run" = true ]; then
            dry_run_messages+="\e[32m+\e[0m Would grant owner permission: team '$name' in $org/$repo.\n"
        else
            response=$(gh api \
            --method PUT \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            /orgs/$org/teams/$(get_team_slug $name)/repos/$org/$repo \
            -f permission='push')

            if [ $? -eq 0 ]; then
                echo -e "\e[32m✓\e[0m Team '$name' granted owner prermissions in repository '$repo'."
            else
                echo "Error granting permissions. $response"; exit 1;
            fi
        fi
    done
}

remove_team_from_repo() {
    local name=$1
    local org=$2
    local repos_to_remove=$3

    for repo in $repos_to_remove; do
        if [ "$dry_run" = true ]; then
            dry_run_messages+="\e[31m-\e[0m Would remove owner permission: team '$name' in $org/$repo.\n"
        else
            response=$(gh api \
            --method DELETE \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            /orgs/$org/teams/$(get_team_slug $name)/repos/$org/$repo)

            if [ $? -eq 0 ]; then
                echo -e "\e[32m✓\e[0m Team '$name' removed owner prermissions in repository '$repo'."
            else
                echo "Error removing permissions. $repsonse"; exit 1;
            fi
        fi
    done
}


process_repos() {
    echo "READING REPOSITORIES..."

    # Status
    existing_incubator_repos=$(gh repo list allianz-incubator --json name --limit 1000 | jq -r '.[].name' | sort)|| {
        echo "Error fetching repos for allianz. $existing_incubator_repos."; exit 1; }
    existing_main_repos=$(gh repo list allianz --json name --limit 1000 | jq -r '.[].name' | sort)|| {
        echo "Error fetching repos for allianz. $existing_main_repos."; exit 1; }
    desired_incubator_repos=$(yq eval '.repositories[] | select(.stage == "allianz-incubator") | .name' "$YAML_FILE" | sort -u)
    desired_main_repos=$(yq eval '.repositories[] | select(.stage == "allianz") | .name' "$YAML_FILE" | sort -u)

    ## changes
    repos_to_add_in_incubator=$(comm -23 <(echo "$desired_incubator_repos") <(echo "$existing_incubator_repos"))
    repos_to_add_in_main=$(comm -23 <(comm -23 <(echo "$desired_main_repos") <(echo "$existing_main_repos")) <(echo "$existing_incubator_repos"))
    repos_to_transfer_to_main=$(comm -12 <(comm -23 <(echo "$desired_main_repos") <(echo "$existing_main_repos")) <(echo "$existing_incubator_repos"))
   
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


    # Iterate over the list of repositories to add in incubator
    for repo in $repos_to_add_in_incubator; do
        create_repo $repo "allianz-incubator"
    done

    # Iterate over the list of repositories to add in main
    for repo in $repos_to_add_in_main; do
        create_repo $repo "allianz"
    done

    # Iterate over the list of repositories to transfer to main
    for repo in $repos_to_transfer_to_main; do
        transfer_repo $repo
    done

    # Warnings
    inconsistent_repos_in_incubator=$(comm -13 <(echo "$desired_incubator_repos") <(echo "$existing_incubator_repos"))
    inconsistent_repos_in_main=$(comm -13 <(echo "$desired_main_repos") <(echo "$existing_main_repos"))
    for repo in $inconsistent_repos_in_main; do
        warning_messages+="> \"$repo\" repository exists in allianz but is missing in config file.\n"
    done
    for repo in $inconsistent_repos_in_incubator; do
        warning_messages+="> \"$repo\" repository exists in allianz-incubator but is missing in config file.\n"
    done
}

fill_teams_cache() {
    CACHED_ALLIANZ_TEAMS=$(gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" /orgs/allianz/teams) || {
        echo "Error fetching teams for allianz. $CACHED_ALLIANZ_TEAMS."; exit 1; }
    echo "Allianz teams: $CACHED_ALLIANZ_TEAMS"
    CACHED_ALLIANZ_INCUBATOR_TEAMS=$(gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" /orgs/allianz-incubator/teams) || {
        echo "Error fetching teams for allianz-incubator. $CACHED_ALLIANZ_INCUBATOR_TEAMS."; exit 1; }
}

get_teams(){
    org="$1"

    if [ "$org" == "allianz" ]; then
        echo "$CACHED_ALLIANZ_TEAMS"
    else
        echo "$CACHED_ALLIANZ_INCUBATOR_TEAMS"
    fi
}

get_team_slug(){
    name="$1"

    # Search for the team in both organizations
    slug_allianz=$(jq -r '.[] | select(.name == "'"$name"'") | .slug' <<< "$CACHED_ALLIANZ_TEAMS")
    slug_incubator=$(jq -r '.[] | select(.name == "'"$name"'") | .slug' <<< "$CACHED_ALLIANZ_INCUBATOR_TEAMS")

    # Return the first non-empty slug found
    if [ -n "$slug_allianz" ]; then
        echo "$slug_allianz"
    elif [ -n "$slug_incubator" ]; then
        echo "$slug_incubator"
    else
        echo "Team slug not found for $name"
        exit 1
    fi
}

process_teams() {
    org_name="$1"
    echo -e "READING $org_name TEAMS..."
    
    # Status
    existing_teams=$(get_teams $org_name | jq -r '.[].name')
    desired_teams=$(yq eval '.repositories[] | select(.stage == "'"$org_name"'") | .teams[].name' "$YAML_FILE" | sort -u)

    # Changes
    teams_to_add=$(comm -23 <(echo "$desired_teams") <(echo "$existing_teams" | sort))
    teams_to_update=$(comm -12 <(echo "$desired_teams" | sort) <(echo "$existing_teams" | sort))
    teams_to_remove=$(comm -13 <(echo "$desired_teams") <(echo "$existing_teams" | sort))

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
        desired_repos_for_team=$(yq eval '.repositories[] | select(.teams[].name == "'"$team"'") | .name' "$YAML_FILE" | sort -u)

        # Debug
        print_debug "  $team"
        print_debug "    repos:"
        print_debug "$desired_repos_for_team" | sed 's/^/      /'

        # Apply
        create_team "$team" $org_name
        add_team_to_repo "$team" $org_name $desired_repos_for_team
    done
    print_debug

    # Iterate over teams to update
    print_debug "Teams to Update for $org_name:"
    for team in $teams_to_update; do

        # Status
        existing_repos_for_team=$(gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "/orgs/allianz-incubator/teams/$team/repos?per_page=100" | jq -c '.[].name' | sed 's/"//g') || {
            echo "Error fetching repositories for teams for allianz. $existing_repos_for_team."; exit 1; }
        desired_repos_for_team=$(yq eval '.repositories[] | select(.teams[].name == "'"$team"'") | .name' ../config/repos.yaml | sort -u)
        
        # Debug
        print_debug "  $team"
        print_debug "    status:"
        print_debug "      existing repo assignments:"
        print_debug "$existing_repos_for_team" | sed 's/^/        /'
        print_debug "      desired repo assignments:"
        print_debug "$desired_repos_for_team" | sed 's/^/        /'

        # Changes
        repos_to_add=$(comm -23 <(echo "$desired_repos_for_team") <(echo "$existing_repos_for_team" | sort))
        repos_to_remove=$(comm -13 <(echo "$desired_repos_for_team") <(echo "$existing_repos_for_team" | sort))
        
        # Debug
        print_debug "    changes:"
        print_debug "      assignments to add:"
        print_debug "$repos_to_add" | sed 's/^/        /'
        print_debug "      assignments to remove:"
        print_debug "$repos_to_remove" | sed 's/^/        /'

        # Apply
        add_team_to_repo $team $org_name $repos_to_add
        remove_team_from_repo $team $org_name $repos_to_remove
    done

    # Iterate over teams to delete
    print_debug "Teams to Delete for $org_name:"
    for team in $teams_to_remove; do
        print_debug "  $team"
        delete_team $team $org_name
    done
}

# Run
validate_config
process_repos
fill_teams_cache
process_teams allianz
process_teams allianz-incubator

# Print warnings
if [ -n "$warning_messages" ]; then
    echo -e "\nWarning Messages:"
    echo -e "$warning_messages" | sed 's/^/  /'
fi

# Print dry run results
if [ "$dry_run" = true ]; then
    echo -e "\nPlanned changes:\n$dry_run_messages" 
fi

