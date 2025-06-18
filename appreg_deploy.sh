#!/usr/bin/bash
set -o pipefail
declare Head="x-aims-auth-token: $auth_token"
declare -i CWait=30 # seconds to wait after collector creation
declare VerbMode=false 
declare TestMode=false

function make_payload () {
    local rscid="$1"
    local projname="$2"
    shift 2
    local jsonkey="$*"
    #jsonkey="${jsonkey//\\n/\\\\n}"
    #FROM JSON BELOW: \"secret_key\":\"${jsonkey//\"/\\\"}\",
    jsonkey=$(jq -Rsa '.' <<< "$jsonkey")
    local payload="{\"name\": \"$projname\",
        \"application_id\": \"googlestackdriver\",
        \"parameters\": {
            \"resource_ids\": [
                \"$rscid\"
            ],
            \"secret_key\":${jsonkey},
            \"filter\": [
                \"cloudaudit.googleapis.com%2Factivity\"
            ]
        }
    }"   
    echo "$payload"
}

function make_collector () {
    local projid="$1"
    shift 1
    local jsonkey="$*"
    local projname="GCP Project ${projid}"
    local resrcid="projects/${projid}"
    local response CurlReturnCode HttpResponseCode JsonResponse
    local payload=$(make_payload "$resrcid" "$projname" "$jsonkey")
    local api='https://api.cloudinsight.alertlogic.com/applications/v1/45848/collectors'
    if $TestMode; then
        echo -e "Running in TestMode; no changes will be made."
        echo -e "TEST MODE -    HEAD:[$Head]\nAPI:[$api]\nPAYLOAD:[$payload]"
    elif $VerbMode; then
        echo -e "VERBOSE MODE - HEAD:[$Head]\nAPI:[$api]\nPAYLOAD:[$payload]"
        curl -ivX POST -H "$Head" "$api" -d "$payload" && { echo; for (( i=$CWait; i>=0; i-- )); do { echo -en " \rCreating collector. Please wait: $i" && sleep 1s; } done; echo; }
        echo -e "STATUS: Curl Return Code:[$CurlReturnCode]"
    else
        curl -sX POST -H "$Head" "$api" -d "$payload" && { echo; for (( i=$CWait; i>=0; i-- )); do { echo -en " \rCreating collector. Please wait: $i" && sleep 1s; } done; echo; }
    fi
}

function deploy_collectors () {
    local -a fnames=( "$@" )
    local json
    for filename in "${fnames[@]}"; do
        if [[ -f "$filename" ]]; then
            jq -rc '.' "$filename" 
            if (( $? != 0 )); then # check for valid json
                echo "invalid json:[$json] at file: $filename"
                return 5
            else
                json=$(<"$filename")
                projid=$(jq -rc '.project_id' "$filename")
                make_collector "$projid" "$json" 
            fi
        fi
    done
}   

declare -a filenames=(
    'gcpkey.json'
)
[[ "$1" =~ [-Tt] ]] && { TestMode=true; }
[[ "$1" =~ [-Vv] ]] && { VerbMode=true; }
#read -pr "Enter filename or list of filenames:" filenames
if (( ${#filenames[@]} >= 1 )); then
    deploy_collectors "${filenames[@]}"
fi

