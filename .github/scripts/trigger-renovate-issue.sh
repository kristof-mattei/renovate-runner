#!/bin/bash

set -euo pipefail

owner=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --owner)
            owner="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 --owner OWNER [--help]"
            echo "  --owner   Tick the 'run again' checkbox on every open Dependency Dashboard in OWNER's unarchived repositories"
            echo "  --help    Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$owner" ]]; then
    echo "Error: --owner must be specified" >&2
    exit 1
fi

manual_job='<!-- manual job -->'

# $1: JSON array of the open Dependency Dashboard issues of one repository
trigger_repo() {
    local dashboards="$1"
    local full_repo number url body state

    full_repo=$(jq --raw-output '.[0].repository.nameWithOwner' <<< "$dashboards")

    if [[ $(jq 'length' <<< "$dashboards") -gt 1 ]]; then
        echo "[$full_repo] Multiple open 'Dependency Dashboard' issues found: $(jq --raw-output 'map("#\(.number)") | join(" ")' <<< "$dashboards")" >&2
        return 1
    fi

    number=$(jq --raw-output '.[0].number' <<< "$dashboards")
    url=$(jq --raw-output '.[0].url' <<< "$dashboards")
    body=$(jq '.[0].body' <<< "$dashboards")

    state=$(jq --raw-output --arg comment "$manual_job" '
        if contains("- [x] " + $comment) then "ticked"
        elif contains("- [ ] " + $comment) then "unticked"
        else "missing"
        end' <<< "$body")

    case $state in
        ticked)
            echo "[$full_repo] #$number: 'run again' is already ticked."
            return 0
            ;;
        missing)
            echo "[$full_repo] #$number: 'run again' checkbox not found in $url" >&2
            return 1
            ;;
    esac

    echo "[$full_repo] #$number: ticking 'run again'."

    if jq --arg comment "$manual_job" '{body: split("- [ ] " + $comment) | join("- [x] " + $comment)}' <<< "$body" \
        | gh api --silent --method PATCH "repos/$full_repo/issues/$number" --input -; then
        echo "[$full_repo] #$number: updated $url"
    else
        echo "[$full_repo] #$number: failed to update $url" >&2
        return 1
    fi
}

# shellcheck disable=SC2016 # GraphQL variables, not shell expansions
query='query($q: String!, $endCursor: String) {
    search(query: $q, type: ISSUE, first: 100, after: $endCursor) {
        nodes { ... on Issue { number title body url repository { nameWithOwner } } }
        pageInfo { hasNextPage endCursor }
    }
}'

pages=$(gh api graphql --paginate --slurp \
    --raw-field q="user:$owner is:issue is:open archived:false in:title \"Dependency Dashboard\" author:app/renovate" \
    --raw-field query="$query")

# in:title also matches longer titles
mapfile -t repos < <(jq --compact-output '[.[].data.search.nodes[] | select(.title == "Dependency Dashboard")] | group_by(.repository.nameWithOwner)[]' <<< "$pages")

if [[ ${#repos[@]} -eq 0 ]]; then
    echo "No open 'Dependency Dashboard' issues found for owner '$owner'" >&2
    exit 1
fi

failed=0

for dashboards in "${repos[@]}"; do
    if ! trigger_repo "$dashboards"; then
        failed=$((failed + 1))
    fi
done

echo ""
echo "Completed processing ${#repos[@]} repositories, $failed failed."

[[ "$failed" -eq 0 ]]
