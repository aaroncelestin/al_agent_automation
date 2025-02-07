#!/usr/bin/bash
# Simple Bash script to dynamically scale AlertLogic resources with a customer's Azure environment.
# When integrated into existing automation tools like Bicep, Terraform, Puppet, etc, deployment tiles will be created in Alert Logic for each Azure subscription input. 
# This allows end users to programmatically scale Alert Logic resources alongside an Azure Cloud Environment. 
# It should be noted that this script does NOT create or deploy IDS or Scanner appliances, nor does it install Alert Logic agents on VM's; It only deploys Alert Logic resources on Alert Logic infrastructure. 
# If a customer needs to automate the creation of Cloud infrastructure, they will beed to use the appropriate dev-ops automation tools for that.
# Author: aaron.celestin@fortra.com
# Copyright Fortra Inc, 2023
declare AzureInteractiveAutoDeployScriptVersion='0.17_20250204'
############################################# Static Variables #############################################
declare -x NC=$(tput sgr0)
declare -x RED=$(tput setaf 1)
declare -x GRE=$(tput setaf 2)
declare -x YEL=$(tput setaf 3)
declare -x CYA=$(tput setaf 6)
declare -x BLU=$(tput setaf 4)
declare -x MAG=$(tput setaf 5)
declare -i _PROC_ASST=10
declare -i _UUID_LENGTH=36
declare -i _SECRET_LENGTH=40
declare -i _AGENT_KEY_LENGTH=43
declare -i _HOST_KEY_LENGTH=45
declare -r _AWS_HOST_KEY_REGEX='+(/aws/*)' # actually glob
declare -r _AZURE_HOST_KEY_REGEX='+(/azure/*)' # actually glob
declare -r _DC_HOST_KEY_REGEX='^(/dc/host/[0-9a-zA-Z]{8}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{12})$'
declare -r _AGENT_KEY_REGEX='^(/agent/[0-9a-zA-Z]{8}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{12})$'
declare -r _APPLIANCE_KEY_REGEX='^(/appliance/[0-9a-zA-Z]{8}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{12})$'
declare -r _NUM_ONLY_REGEX='^[[:digit:]]+$' 
declare -r _UUID_REGEX='[0-9a-zA-Z]{8}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{12}$'
declare -A Key_Regexes=( ['aws_hostkey']=$_AWS_HOST_KEY_REGEX ['azure_hostkey']=$_AZURE_HOST_KEY_REGEX ['dc_hostkey']=$_DC_HOST_KEY_REGEX ['agent_key']=$_AGENT_KEY_REGEX ['appliance_key']=$_APPLIANCE_KEY_REGEX )
declare -A Hostkey_Regexes=( ['aws']=$_AWS_HOST_KEY_REGEX ['azure']=$_AZURE_HOST_KEY_REGEX ['dc']=$_DC_HOST_KEY_REGEX )
declare Cid CloudInsightUrl Head TenantId AppId ALAccessKeyId ALSecretKeyHash AZSecretKeyHash Delimiter InteractiveMode=true Auth_Token UseSubsIds=false UuidType
declare defender_datacenter CidL=false AidL=false TidL=false AlkL=false UpdateMode=false StartConfirmed=false TestRun=false WaitForDisco=false
declare -a Target_List
declare UkUrl='https://api.cloudinsight.alertlogic.co.uk'
declare UsUrl='https://api.cloudinsight.alertlogic.com'
declare AzureCredUrl='https://api.cloudinsight.alertlogic.com/azure_explorer/v1/validate_credentials'

# Usage and description
declare -i mw=$(( $(tput cols) * 2/3 )) # menu widths
# line segment limited by screen width, default is 100 cols
segm () { local -i w=${1:-120}; for ((i=0;i<$w;i++)); do echo -en '-'; done; echo; }
usage () {
    local -a options=(
        '--cid|-cC|<CID>|Enter your AlertLogic Account ID also known as a CID. You will be prompted to enter one if none is provided here.'
        '--tenant-id|-tT|<tenant ID>|Enter the Azure Tenant/Active Directory ID at the command line instead of being prompted for it.'
        '--app-id|-aA|<application ID>|Enter the Application/Client ID at the command line instead of being prompted for it.'
        '--al-access-key|-lL|<AlertLogic access key>|Enter your AlertLogic access key ID, refer to the SETUP section of this help menu for more info.'
        '--delim|-dD|<delimiter>|Set a custom single-character delimiter for your input lists, only [; - | : .] are supported (default delimiter is the comma).'
        '--file|-fF|<file>|Enter the filepath that contains target information like deployment names, deployment IDs, subscription IDs.'
        '--wait|-wW| |By default after a deployment tile is created we will move on to the next subscription ID in the list, if you want to wait up to 30 minutes for each disco scan, set this flag'
        '--update|-uU| |Update existing (do not create) deployments using given subscription or deployment IDs.'
        '--subsids|-bB| |(UPDATE MODE) When updating existing deployments with an input file,set this flag if the file contains subscription IDs instead of deployment IDs (subsids will be converted to depids).'
        '--testrun|-tT| |Run the script in TestRun Mode, no changes will be made and only fake outputs will be created.'
        '--debug|-gG| |Run this script in debug mode.'
        '--help|-hH| |Display this help message.'
    )
    echo -e "\n" #${GRE}TITLE${NC}:"
    segm $mw
    echo -e "\t\t${CYA}Azure Interactive Auto Deployment Script\n\t\tVersion:${YEL} $AzureInteractiveAutoDeployScriptVersion ${NC}"
    desc="This interactive script will prompt an end user for Azure tenant information and then take a list of Azure Subscription IDs from that tenant ONLY and will then create deployment tiles for each \
Azure subscription input. This allows end users to programatically scale Alert Logic resources alongside an Azure Cloud Environment. It should be noted that this script does NOT create or deploy IDS \
or Scanner appliances, nor does it install Alert Logic agents on VM's. In fact, this script will not deploy anything into any Azure environment, ever. It only deploys Alert Logic resources on Alert \
Logic infrastructure. If you need to automate the creation of Cloud infrastructure, use the appropriate dev-ops tools for that purpose."
    echo -e "\n${GRE}DESCRIPTION${NC}:"
    segm $mw
    fold -w $mw -s <<< "$desc"
    echo -e "\n${GRE}SETUP${NC}:"
    segm $mw
    local setup1="You must get an authentication token to be able to call Alert Logic APIs that will build deployment tiles in the console. To get a token, you need to generate an access key id and a secret key. \
You can create an access key in the Alertlogic console here:"
    fold -w $mw -s <<< "$setup1"
    echo -e "${BLU}https://console.alertlogic.com/#/account/users?aaid=${YEL}< account ID/CID >${BLU}&locid=defender-us-ashburn${NC}"
    local setup2='Enter your CID, also known as your Account ID in the URL above and paste it into your browser. After you login, this will take you to the Users section of the Alert Logic console for your account.'
    fold -w $mw -s <<< "$setup2"
    echo -e "\t${YEL}1.${NC} Click on your name or user with at least Power User privileges and then click on the \"Access Keys\" tab."
    echo -e "\t${YEL}2.${NC} Click \"Generate New Key\""
    echo -e "\t${YEL}3.${NC} Copy and paste the Access Key ID and Secret Key to save them for later. You may also download the key file."
    local setup3='If you are not particularly concerned with the security of your secret key, you can paste your access key id and secret key within in the script itself and it will run with no more interaction required from you.'
    echo -en "${CYA}INFO${NC}: "; fold -w $mw -s <<< "$setup3" 
    local setup4='You CANNOT enter the Secret Key at the command line as a script argument, since there is no way to encrypt or secure it before possibly being sent to a log.'
    echo -en "\n${YEL}NOTE${NC}: "; fold -w $mw -s <<< "$setup4"
    echo -e "\n${GRE}OPTIONS${NC}:"
    segm $mw
    for opt in "${options[@]}"; do
            IFS='|' read -r long short arg desc <<< "$opt"
            printf "${YEL}%15s${NC}|${YEL}%s${NC} ${CYA}%-17s${NC} # %-42s\n" "$long" "$short" "$arg" "$desc"
        done
    echo -e "\n${GRE}EXAMPLES${NC}:"
    segm $mw
    echo -e "  >_localhost\$ ${GRE}$0 -c 123546 ${NC}\t\t\t# default with no options will enter interactive mode."
    echo -e "  >_localhost\$ ${GRE}$0 --cid 123456 --tenant-id '1abc234sad56' ${NC}\t# specify the tenant or active directory id."
    echo -e "  >_localhost\$ ${GRE}$0 --cid 123456 --app-id '1abc234sad56' ${NC}\t# specify the application or client id."
    echo
    exit 0
}

###########################################################################################
#                 GET AND SETUP YOUR AUTHENTICATION TOKEN FOR API ACCESS
############################################################################################
# You can create an access key in the Alertlogic console here:
# https://console.alertlogic.com/#/account/users?aaid=$Cid&locid=defender-us-ashburn
# 1. Click on your name and click the "Access Keys" tab
# 2. Click "Generate New Key"
# 3. Copy and paste the Access Key ID and Secret Key to the fields below.
# NOTE: If you are not concerned with the security of your secret key, you can put your access key and secret key IDs here and the script will run with no more interaction required from you
#ALAccessKeyId=''
#InsecureSecretKey=''
################################### Encryption and Obfuscation Tools #######################################
declare -i Alk_Length_=16
declare SigKey=$(openssl rand -hex 8 2>/dev/null)
encrypt_sk () { local in="$*"; openssl enc -e -des3 -a -pass pass:"$SigKey" -pbkdf2 <<< "$in"; } # encrypt secretkey using SigKey which is a randomly generated string and stored for decryption later
decrypt_sk () { local in="$*"; echo "$in" | openssl enc -d -des3 -a -pass pass:$SigKey -pbkdf2; } # try to decrypt incoming text using Sigkey

############################################# Auth Token Validation #############################################
# Try to set an AIMS auth token, kill the whole script if it fails (can't do anything without a token)
set_auth_token () {
    # local un='<client id>'
    # local pw='<client key>'
    local authapi="https://api.cloudinsight.alertlogic.com/aims/v1/authenticate"
    Auth=$(curl -s -X POST -u "${ALAccessKeyId}:$(decrypt_sk "$ALSecretKeyHash")" "$authapi" | jq -r ". | .authentication.token")
    # Confirm we got a token
    if [[ -n "$Auth" ]]; then
        Auth_Token=$Auth # set the actual token var we will be using
        echo -e "${GRE}OKAY${NC} Auth_Token for the current session was set successfully Auth_Token (size only):[${YEL}${#Auth_Token}${NC}]."
        echo -e "${CYA}INFO${NC} Variable exported: ${YEL}\$Auth_Token${NC}."
    else
        echo -e "${RED}ERROR${NC} Auth_Token creation FAILED. Check your access key ID:[${YEL}$ALAccessKeyId${NC}] and secret key hash (size only):[${YEL}${#ALSecretKeyHash}${NC}]."
        exit 4
    fi
}
######################################## Helper and Utility Functions ##########################################
# (SAN)itize a string by removing brackets and quote marks
san () { local msg="${@:-$(</dev/stdin)}"; echo -e "$msg" | sed 's/\"//g' | sed 's/[][]//g'; }
# Simple function that squishes and cleans text like a mop does, hence the name.
# Sometimes we get strings in deployment and CID names with spaces and spec of chars (like commas) that have to all be escaped which can be a nightmare if they show up in vars 
# that you have to compare to each other. So, I wrote this function that will more than {SAN}itize a string, it will also squish all whitespace to underscores and remove all 
# spec-chars except underscores, periods, dashes and forward-slashes.
mop () { local msg="${@:-$(</dev/stdin)}"; echo -e "${msg// /_}" | tr -dc '[:alnum:][=_=][=.=][=-=][=/=]'; }
# Quick validation of UUID input parameters 
validate_uuid () { if [[ $(tr -dc '[:alnum:][=-=]' <<< "$1") =~ $_UUID_REGEX ]]; then { echo true; } else { echo false; } fi; } 
# Get CloudInsight api Url based on CID
get_cloudinsight_url () {
    case "$((Cid>>26))" in # use bitshift on the Cid 
        0)      { echo "$UsUrl"; };; # Denver 
        1)      { echo "$UkUrl"; };; # Newport
        2)      { echo "$UsUrl"; };; # Ashburn
    esac
}
########################################## Azure API Wrapper Functions ##########################################
# Validate user-provided credentials 
validate_azure_credentials () {
    local subsid="${1:?"${RED}ERROR${NC} module:[${YEL}validate_azure_credentials${NC}] failed; missing input param"}"
    local api='https://api.cloudinsight.alertlogic.com/azure_explorer/v1/validate_credentials'   
    if $TestRun; then
        local tr_payload="{\"subscription_id\":\""$subsid"\",\"credential\":{\"id\":\"\",\"name\":\"\",\"type\":\"azure_ad_client\",\"azure_ad_client\":{\"active_directory_id\":\""$TenantId"\",\"client_id\":\""$AppId"\",\"client_secret\":"\"$AZSecretKeyHash"\"}}}"
        echo -e "${MAG}TESTRUN MODE${NC} FUNCTION:[validate_azure_credentials] curl -sX POST -H HEAD SIZE:[${YEL}${#Head}${NC}]" 
        echo -e "${MAG}TESTRUN MODE${NC} API:[${YEL}${api}${NC}]"
        echo -e "${MAG}TESTRUN MODE${NC} PAYLOAD:[${YEL}$(jq -cRnr '[inputs] | join("\\n") | fromjson' <<< "$tr_payload")${NC}]"
        echo -e "${MAG}TESTRUN MODE${NC} OUTPUT:[${YEL}JSON${NC}]"
        return 0
    else 
        local payload="{
            \"subscription_id\": \""$subsid"\",
            \"credential\": {
                \"id\": \"\",
                \"name\": \"\",
                \"type\": \"azure_ad_client\",
                \"azure_ad_client\": {
                \"active_directory_id\": \""$TenantId"\",
                \"client_id\": \""$AppId"\",
                \"client_secret\": \""$(decrypt_sk "$AZSecretKeyHash")"\"
                }
            }
        }"
        curl -sX POST -H "$Head" "$api" -d "$payload"
    fi
}
# Load validated credentials to CloudInsight to create deployment tile. Returns JSON that includes credential_id
load_azure_credentials () {
    local depname="${1:?"${RED}ERROR${NC} module:[${YEL}load_azure_credentials${NC}] failed; missing input param"}"
    local api="$CloudInsightUrl/credentials/v2/$Cid/credentials"
    if $TestRun; then
        local tr_payload="{\"name\":\""$depname"\",\"secrets\":{\"type\":\"azure_ad_client\",\"ad_id\":\""$TenantId"\",\"client_id\":\""$AppId"\",\"client_secret\":"\"$AZSecretKeyHash"\"}}"
        echo -e "${MAG}TESTRUN MODE${NC} FUNCTION:[load_azure_credentials] curl -sX POST -H HEAD SIZE:[${YEL}${#Head}${NC}]" 
        echo -e "${MAG}TESTRUN MODE${NC} API:[${YEL}${api}${NC}]"
        echo -e "${MAG}TESTRUN MODE${NC} PAYLOAD TEST:[${YEL}$(jq -cRnr '[inputs] | join("\\n") | fromjson' <<< "$tr_payload")${NC}]"
        echo -e "${MAG}TESTRUN MODE${NC} OUTPUT:[${YEL}${credential_id}${NC}]"
        return 0
    else
        local payload="{
        \"name\": \""$depname"\",
        \"secrets\": {
            \"type\": \"azure_ad_client\",
            \"ad_id\": \""$TenantId"\",
            \"client_id\": \""$AppId"\",
            \"client_secret\": \""$(decrypt_sk "$AZSecretKeyHash")"\"
            }
        }"
        curl -sX POST -H "$Head" "$api" -d "$payload" 
    fi
}
# Create deployment tile, returns JSON
put_deployment () {
    local depname="${1:?"${RED}ERROR${NC} module:[${YEL}put_deployment${NC}] failed; missing input param:[depname]"}"
    local subsid="${2:?"${RED}ERROR${NC} module:[${YEL}put_deployment${NC}] failed; missing input param:[subsid]"}"
    local def_dc credential_id="$3"
    local ash_dc='defender-us-ashburn'
    local den_dc='defender-us-denver'
    local npt_dc='defender-us-ashburn'
    case "$((Cid>>26))" in
        0 )      def_dc="$den_dc";; # Denver
        1 )      def_dc="$npt_dc";; # Newport
        2 )      def_dc="$ash_dc";; # Ashburn
    esac
    local api="$CloudInsightUrl/deployments/v1/$Cid/deployments"
    local payload="{
            \"name\": \""$depname"\",
            \"platform\": {
                \"type\": \"azure\",
                \"id\": \""$subsid"\"
            },
            \"mode\": \"manual\",
            \"enabled\": true,
            \"discover\": true,
            \"scan\": true,
            \"scope\": {
                \"include\": [],
                \"exclude\": []
            },
            \"cloud_defender\": {
                \"enabled\": false,
                \"location_id\": \""$def_dc"\"
            },
            \"credentials\": [
                {
                \"id\": \""$credential_id"\",
                \"purpose\": \"discover\"
                }
            ]
        }"
    if $TestRun; then
        echo -e "${MAG}TESTRUN MODE${NC} FUNCTION:[put_deployment] curl -sX POST -H HEAD SIZE:[${YEL}${#Head}${NC}]" 
        echo -e "${MAG}TESTRUN MODE${NC} API:[${YEL}${api}${NC}]"
        echo -e "${MAG}TESTRUN MODE${NC} PAYLOAD TEST:[${YEL}$(jq -rc '.' <<< "$payload")${NC}]"
        echo -e "${MAG}TESTRUN MODE${NC} OUTPUT:[${YEL}JSON${NC}]"
        return 0
    else
        curl -sX POST -H "$Head" "$api" -d "$payload"
    fi  
}
# Given CId and deployment ID, GET deployment; returns JSON
get_deployment_info () {
    local depid="${1:?"${RED}ERROR${NC} module:[${YEL}get_deployment_info${NC}] failed; missing input param"}"
    local api="$CloudInsightUrl/deployments/v1/$Cid/deployments/$depid"
    curl -sk GET -H "$Head" "$api"
}
make_update_list () {
    local -a output deplist subslist=( "$@" )
    (( ${#subslist[@]} == 0 )) && { echo -e "${RED}ERROR${NC} module:[${YEL}update_deployment${NC}] failed; missing input param"; return 8; }
    local api="$CloudInsightUrl/deployments/v1/$Cid/deployments" 
    readarray -t deplist < <(curl -sX GET -H "$Head" "$api" | jq -rc '.[] | .id') # get a list of existing depids
    for refid in "${subslist[@]}"; do # iterate over list of incoming subsids
        local -a temp
        for depid in "${deplist[@]}"; do # iterate over list of depids
            local src_api="$CloudInsightUrl/sources/v1/$Cid/sources/$depid" 
            local subsid=$(curl -sX GET -H "$Head" "$src_api" | jq -rc '(.source.config.azure.subscription_id)') # get the subsid of the depid
            if [[ "${refid^^}" == "${subsid^^}" ]]; then # if a match was found in the subsid list
                temp+=( "${depid^^},${subsid^^}" ) # add it to the output list
                break # stop and move on to the next item in the deplist list
            fi
        done
        if (( ${#temp[@]} == 2 )); then { echo -e "${RED}ERROR${NC} module:[${YEL}update_deployment${NC}]; duplicate subscription IDs found across two deployments:[${YEL}${temp[@]}${NC}]"; continue; }
        elif (( ${#temp[@]} == 0 )); then { echo -e "${RED}ERROR${NC} module:[${YEL}update_deployment${NC}]; no deployments found for subscription ID:[${YEL}${refid}${NC}]"; continue; }
        else { output+=( "${temp[@]}" ) && unset temp; }
        fi
    done
    printf '%s\n' "${output[@]}"
}
declare -i testruns=0
# Call topology config on assets_query till at least one row (asset) is doscovered
call_topology_config () {
    local depid="${1:?"${RED}ERROR${NC} module:[${YEL}call_topology_config${NC}] failed; missing input param"}"
    local api="$CloudInsightUrl/assets_query/v1/$Cid/deployments/$depid/topology/config"
    if $TestRun && (( testruns < 4 )); then { testruns=$((testruns+1)) && echo false; } # simulate 2 test runs
    elif $TestRun && (( testruns == 4 )); then { echo true; }
    else
        local -i result=$(curl -sk GET -H "$Head" "$api" | jq -r '(.topology.rows)?' 2>/dev/null)
        if (( ${#result} > 10 )); then
            echo true
        else    
            echo false
        fi
    fi 
}

# For idempotentcy, verify the given Azure subscription ID has not already been used to create an AlertLogic deployment 
check_subscription_id () {
    local ref_subs_id="${1:?"${RED}ERROR${NC} module:[${YEL}check_subscription_id${NC}] failed; missing input param"}"
    local -a deployments
    local dep_name dep_id res=false dep_api="$CloudInsightUrl/deployments/v1/$Cid/deployments" 
    readarray -t deployments < <(curl -sX GET -H "$Head" "$dep_api" | jq -rc '.[] | [[(.name)],.id]')
    for deps in "${deployments[@]}"; do
        dep_name=$(echo "${deps%%],*}" | sed 's/[][]//g' | mop)
        dep_id=$(echo "${deps##*],}" | san)
        src_api="$CloudInsightUrl/sources/v1/$Cid/sources/$dep_id" 
        subs_id=$(curl -sX GET -H "$Head" "$src_api" | jq -rc '(.source.config.azure.subscription_id)')
        if [[ "${ref_subs_id^^}" == "${subs_id^^}" ]]; then
	        res=true
            break
        fi
    done
    echo $res
}
confirm_start () {
    local tm_warn="${YEL}WARNING${NC} You are ${YEL}NOT${NC} about to make ANY changes to any Alert Logic deployments because you are in ${MAG}TESTMODE${NC}."
    local warn="${YEL}WARNING${NC} You are about to make changes to a live customer account:[${YEL}${Cid}${NC}]."
    local prompt="Are you SURE you want to continue? Enter [${GRE}Y${NC}es | ${RED}N${NC}o] ${RED}-->>${NC}: "  
    echo -e "\n${CYA}Confirmation Menu${NC}
    Target_List Array Size:[${YEL}${#Target_List[@]}${NC}]
    Update Mode Enabled:[${YEL}${UpdateMode}${NC}]
    Use Subscription IDs:[${YEL}${UseSubsIds}${NC}]
    Wait For Discovery:[${YEL}${WaitForDisco}${NC}]
    Customer Cid:[${YEL}${Cid}${NC}]
    Active Directory/Tenant ID:[${YEL}${TenantId}${NC}]
    Azure Application ID:[${YEL}${AppId}${NC}]
    Input File Path:[${YEL}${InputFile}${NC}]
    Alert Logic Access Key:[${YEL}${ALAccessKeyId}${NC}]
    Azure Secret Key Hash (Encrypted):[${YEL}$(tr -d '\n' <<< "$AZSecretKeyHash")${NC}]"; echo
    echo -e "${RED}PLEASE REVIEW INPUTS ABOVE BEFORE CONTINUUING${NC}"
    local _yrgx='[YyEeSs]'
    if $TestRun; then { echo -e "$tm_warn"; }
    else { echo -e "$warn"; } 
    fi
    read -rp "$(echo -e "$prompt")" confirmed
    if [[ "${confirmed,,}" =~ $_yrgx ]]; then { StartConfirmed=true; } fi
}
wait_for_discovery () {
    local depid="$1"
    local depname="$2"
     # call topology config status until discovery is complete
    while : ; do
        echo -e "${CYA}INFO${NC}: process_config topology for new deployment:[${YEL}${depname}${NC}] is started. Alert Logic deployment id:[${YEL}${depid}${NC}]. Please wait..."
        sleep 5s        
        local finished=$(call_topology_config "$depid")
        if $finished; then
            echo -e "${GRE}SUCCESS${NC} Azure Deployment [${YEL}${depname}${NC}] discovery completed successfully."
            break
        else
            continue
        fi
    done
}
####################################### Process and Control Functions ##########################################
create_azure_deployment () {
    local dep_name="$1"
    local subs_id="$2"
    # Idempotentcy check, ensure deployments with duplicate subscription IDs fail
    local dep_exists=$(check_subscription_id "$subs_id")
    if $dep_exists; then
        echo -e "${RED}ERROR${NC} An existing Alert Logic deployment [${YEL}$dep_name${NC}] was already created using the subscription id [${YEL}$subs_id${NC}]."
        echo -e "Check your settings and try again."
        exit 1
    fi
    # start by validating creds first
    if ! validate_azure_credentials "$subs_id"; then
        echo -e "${RED}ERROR${NC} Azure credential validation failed; empty response or non-zero exit status was returned."
    else
        echo -e "${GRE}SUCCESS${NC} Azure credential validation completed successfully."
        ############## load credentials #################
        if $TestRun; then
            local response='{"key1":"val1","key2":"val2","id":"FAKECRED-FAKE-ABCD-1234-6C9B0F84ABCD"}'
            load_azure_credentials "$dep_name"
            echo -e "${MAG}TESTRUN MODE${NC} FUNC:[create_azure_deployment] MODULE:[load_azure_credentials] OUTPUT:[${YEL}$(jq -rc '.' <<< "$response")${NC}]"
        else
   	        ! response=$(load_azure_credentials "$dep_name") 
        fi
        if (( ${PIPESTATUS[0]} != 0 )) || [[ -z "$response" ]]; then
            echo -e "${RED}ERROR${NC} Azure credential loading failed; empty response or non-zero exit status was returned."
            exit 1
        else
            echo -e "${GRE}SUCCESS${NC} Azure credential was loaded successfully."
            ############# get newly created credential id #################
            
            local cred_id="$(jq -rc '(.id)?' <<< "$response")"
            if $TestRun; then { echo -e "${MAG}TESTRUN MODE${NC} FUNC:[create_azure_deployment] MODULE:[get_cred_id] OUTPUT:[${YEL}${cred_id}${NC}]"; } fi
            local deployment_id
            #################### create deployment ########################
            if $TestRun; then
                local fake_json='{"key1":"val1","key2":"val2","cred_id":"FAKECRED-FAKE-ABCD-1234-6C9B0F84ABCD","id":"ABCD1234-FAKE-DEPD-1234-6C9B0F84ABCD"}'
                put_deployment "$dep_name" "$subs_id" "$cred_id" 
                echo -e "${MAG}TESTRUN MODE${NC} FUNC:[create_azure_deployment] MODULE:[put_deployment] OUTPUT:[${YEL}$(jq -rc '.' <<< "$fake_json")${NC}]"
                ! deployment_id=$(jq -rc '.id' <<< "$fake_json")
            else
    	        ! deployment_id=$(put_deployment "$dep_name" "$subs_id" "$cred_id" | jq -rc '.id')
            fi
            if (( ${PIPESTATUS[0]} != 0 )) || [[ -z "$deployment_id" ]]; then
                echo -e "${RED}ERROR${NC} Deployment creation failed; deployment_id was not found or returned non-zero exit status."
                exit 1
            else
                echo -e "${GRE}SUCCESS${NC} Deployment created successfully."
                # verify deployment creation
                if $TestRun; then
                    response='{"key1":"val1","key2":"val2","cred_id":"FAKECRED-FAKE-ABCD-1234-6C9B0F84ABCD","id":"ABCD1234-FAKE-DEPD-1234-6C9B0F84ABCD"}'
                    echo -e "${MAG}TESTRUN MODE${NC} FUNC:[create_azure_deployment] MODULE:[get_deployment_info] OUTPUT:[${YEL}$(jq -rc '.' <<< "$response")${NC}]"
                else
                    response=$(get_deployment_info "$deployment_id")
                fi
                if [[ -z "$response" ]]; then
                    echo -e "${RED}ERROR${NC} Deployment info call failed; empty response was returned."
                    exit 1
                else
                    if $WaitForDisco; then
                        echo -e "${GRE}SUCCESS${NC} Deployment was successfully created. Waiting for the first discovery process to complete."
                        echo -e "${GRE}INFO${NC} Running topology config. This could take up to 30 minutes!\nPlease wait..."
                        wait_for_discovery "$deployment_id" "$dep_name"
                    else
                        echo -e "${GRE}SUCCESS${NC} Deployment was successfully created. We will not be waiting for the first discovery process to complete."
                        echo -e "${GRE}INFO${NC} Running topology config. Please wait..."
                        sleep 5s
                        call_topology_config "$deployment_id"
                    fi
                fi
            fi          
	    fi
    fi  
}
update_deployment () {
    local depid="${1:?"${RED}ERROR${NC} module:[${YEL}update_deployment${NC}] failed; missing input param"}"
    local subsid="${2:-none}"
    local dep_json=$(get_deployment_info "$depid")
    if [[ -z "$dep_json" ]]; then
        echo -e "${RED}ERROR${NC} No Alert Logic deployment with deployment id:[${YEL}$depid${NC}] could be found in Cid:[${YEL}$Cid${NC}]."
        echo -e "Check your settings and try again."
        return 11
    else
        local depname=$(jq -rc '.[] | (.name)' <<< "$dep_json")
        if [[ "$subsid" == 'none' ]] && [[ -z "$(cut -d, -f2 <<< "$depid")" ]]; then # if no subsid was entered nor was the input a comma-separated depid-subsid pair
            local src_api="$CloudInsightUrl/sources/v1/$Cid/sources/$depid" 
            subsid=$(curl -sX GET -H "$Head" "$src_api" | jq -rc '(.source.config.azure.subscription_id)')
        fi
        # start by validating creds first
        if ! validate_azure_credentials "$subsid"; then
            echo -e "${RED}ERROR${NC} Azure credential validation failed; empty response or non-zero exit status was returned."
            return 12
        else
            echo -e "${GRE}SUCCESS${NC} Azure credential validation completed successfully."
            credential_id=$(load_azure_credentials "$depname" | jq -r '.id') 
            if [[ -z "$credential_id" ]]; then
                echo -e "${RED}ERROR${NC} failed to get a credential_id; and empty credential was returned."
                return 13
            else
                { put_deployment "$depname" "$subsid" "$credential_id" | jq -rc '.id' && {
                    sleep 2s
                    call_topology_config
                    echo "${GRE}SUCCESS${NC} Azure credential validation completed successfully."
                }; } || echo -e "${RED}ERROR${NC} Deployment update module failed; confirm credentials in the console."
            fi
        fi
    fi
}

#################################### Interactive User Functions #################################################
get_secret_from_user () {
    local secret_type="${1:?"${RED}ERROR${NC} module:[${YEL}get_secret_from_user${NC}] failed; missing input param:[${YEL}secret_type${NC}]"}"
    local input output_var=${2:?"${RED}ERROR${NC} module:[${YEL}get_secret_from_user${NC}] failed; missing input param:[${YEL}output_var${NC}]"}
    echo -e "\n${CYA}Secure ${secret_type} Secret Entry Menu${NC}"
    local -i chars=0
    echo -e "${YEL}NOTICE${NC} when pasting your secret here, it will be masked/hidden on the terminal screen.\nThis script does not store any of these values in plain text. All inputs are encrypted immediately."
    local prompt="Please enter or paste the Secret ${secret_type} Key here ${RED}-->>${NC}: "
    stty -echo # turn off echo strict
    while IFS= read -p "$prompt" -srn 1 char; do
        [[ "$char" == $'\0' ]] && { break; } # check for term/ENTER keypress
        if [[ "$char" == $'\177' ]] ; then # check for backspace
            if (( chars > 0 )); then
                chars=$((chars-1)) # backup char count by 1
                prompt=$'\b \b' # backup display prompt
                input="${input%?}" # delete last char from input
            else { prompt=''; } # remove prompt if no chars were found
            fi
        else
            chars=$((chars+1)) # increment chars
            prompt='*' # replace prompt with mask
            input+="$char" # add actual char to input
        fi
    done
    sleep .5s # slow down just in case input buffer is overflowed, which could cause input to appear on stdout
    stty echo; echo # turn echo back on, feed a line
    local secret_hash=$(encrypt_sk "$input") # hide and encrypt secret key
    if [[ -n "$secret_hash" ]] && printf -v $output_var "$secret_hash"; then
        echo -e "${GRE}OKAY${NC} Encrypted ${secret_type} secret var:[${YEL}${output_var}${NC}] of length:[${YEL}${#secret_hash}${NC}] was added."
    else
        echo -e "${RED}ERROR${NC} Encryption failed or the result could not be loaded into the output variable:[${YEL}${output_var}${NC}]."
        exit 1
    fi
}
get_uuid_from_user () {
    local input input_type="${1:?"${RED}ERROR${NC} module:[${YEL}get_uuid_from_user${NC}] failed; missing input param:[${YEL}input_type${NC}]"}"
    local output_var=${1:?"${RED}ERROR${NC} module:[${YEL}get_uuid_from_user${NC}] failed; missing input param:[${YEL}output_var${NC}]"}
    read -rp "Please enter the ${input_type^} ${RED}-->>${NC}: " input
    if [[ -n "$input" ]] && $(validate_uuid "$input"); then # clean and check the input
        input=$(tr -dc '[:alnum:][=-=]' <<< "$input")
        printf -v $output_var "$input" &&  echo -e "${GRE}OKAY${NC} input uuid:[${YEL}${output_var}${NC}] with value:[${YEL}${input^^}${NC}] was loaded"
    else
        echo -e "${RED}ERROR${NC} An invalid uuid:[${YEL}${input}${NC}] was entered."
        usage
    fi
}
get_cid_from_user () {
    local input
    read -rp "Please enter the CID (numbers only): " input
    [[ -n "$input" ]] && input=$(tr -dc '[:digit:]' <<< "$input") # clean the input
    if [[ $input =~ $_NUM_ONLY_REGEX ]]; then
        Cid=$input &&  echo -e "${GRE}OKAY${NC} input CID:[${YEL}${Cid}${NC}] was loaded"
    else
        echo -e "${RED}ERROR${NC} An invalid input:[${YEL}${input}${NC}] was entered."
        usage
    fi
}
get_access_key_from_user () {
    local input
    read -rp "Please enter the AlertLogic AccessKeyId ${RED}-->>${NC}: " input
    [[ -n "$input" ]] && input=$(tr -d '[:alnum:]' <<< "$input") 
    if [[ "$input" -eq $Alk_Length_ ]]; then
        ALAccessKeyId=$(tr -dc '[:alnum:]' <<< "$input") &&  echo -e "${GRE}OKAY${NC} access key:[${YEL}${ALAccessKeyId}${NC}] was added."
    else
        echo -e "${RED}ERROR${NC} Invalid AlertLogic access key:[${YEL}${ALAccessKeyId}${NC}] was entered."
        usage
    fi
}
get_subscription_ids_from_user () {
    local delim="${1:-,}"
    echo -e "\n${CYA}Deployment Name and Subscription ID Manual Input Menu${NC}"
    echo -e "${GRE}INSTRUCTIONS${NC}:"
    echo "Enter a line or multiple lines of a deployment name and a subscription ID, separated by a delimiter (comma is default) and then press Enter. Press CTRL+D when you are finished."
    echo -e "Your entries should look like this:\n\t'${CYA}<Deployment Name>${RED}<Delimiter>${YEL}<Subscription UUID>${NC}'"
    echo -e "\t'${CYA}New Prod Deployment Name${NC}${RED},${YEL}12345678-ABCD-1234-EFGH-IJKL5678ABCD${NC}'\n\t'${CYA}New Staging Deployment Name${NC}${RED},${YEL}87654321-QWER-4321-EFGH-12345678WXYZ${NC}'"
    echo -e "${YEL}NOTE${NC} You must press ENTER, to load into the list, you can then paste more entries and again press ENTER to add to the list."
    echo -e "You ${YEL}MUST${NC} press \"CTRL\" + D when finished loading your list."
    while read -r input; do
        if [[ -n "$input" ]]; then
            IFS=${delim} read -r depname subsid <<< "$input"
            if $(validate_uuid "$subsid") && [[ -n "${depname}" ]]; then 
                subsid=$(tr -dc '[:alnum:][=-=]' <<< "$subsid") # clean the subscription id
                depname=$(tr -d '[=,=][=;=][="=]' <<< "${depname//\'/}") # clean the deployment name of illegal chars
                Target_List+=( "$depname,${subsid^^}" ) && echo -e "${GRE}OKAY${NC} deployment:[${YEL}${depname}${NC}] was added to TargetList:[${YEL}${#Target_List[@]}${NC}]"
            else
                echo -e "${YEL}WARN${NC} invalid UUID:[${YEL}${subsid}${NC}] or deployment name:[${YEL}${depname}${NC}] was entererd."
            fi
        else
            echo -e "${RED}ERROR${NC} No valid lines were entered for processing."
        fi
    done
}
get_many_uuids_from_user () {
    echo -e "\n${CYA}Deployment or Subscription ID Manual Input Menu${NC}"
    local prompt="Enter \"S\" or \"Subs\" for Subscription IDs and \"D\" or \"Deps\" for Deployment IDs ${RED}-->>${NC}: "
    echo -e "${YEL}Will you be entering AlertLogic Deployment IDs or Azure Subscription IDs?${NC}"
    read -rp "$(echo -e "$prompt")" uuid_type
    local _subs_rgx='^[Ss]$|[Ss][Uu][Bb][Ss]$'
    local _deps_rgx='^[Dd]$|[Dd][Ee][Pp][Ss]$'
    if [[ "$uuid_type" =~ $_subs_rgx ]]; then { UuidType='subsids'; }
    elif [[ "$uuid_type" =~ $_deps_rgx ]]; then { UuidType='depids'; }
    else { echo -e "${RED}ERROR${NC} Unrecognized input:[${YEL}${uuid_type}${NC}]. Please try again."; get_many_uuids_from_user; }
    fi
    echo -e "${GRE}INSTRUCTIONS${NC}:"
    echo "Enter a line or multiple lines of a deployment or subscription IDs and then press Enter. Press CTRL+D when you are finished."
    echo -e "${YEL}NOTE${NC} If you chose to enter subscription IDs they will be converted to Deployment IDs before running updates."
    echo -e "Your entries should look like this:\n\t'${YEL}<Subscription/Deployment UUID>${NC}'"
    echo -e "\t'${YEL}12345678-ABCD-1234-EFGH-IJKL5678ABCD${NC}'\n\t'${YEL}87654321-QWER-4321-EFGH-12345678WXYZ${NC}'"
    echo -e "${YEL}NOTE${NC} You must press ENTER, to load into the list, you can then paste more entries and again press ENTER to add to the list."
    echo -e "You ${YEL}MUST${NC} press \"CTRL\" + D when finished loading your list."
    while read -r input; do
        if [[ -n "$input" ]]; then   
            if $(validate_uuid "$input"); then 
                tuuid=$(tr -dc '[:alnum:][=-=]' <<< "$input") # clean the uuid
                Target_List+=( "$tuuid" ) && echo -e "${GRE}OKAY${NC} target uuid:[${YEL}${tuuid}${NC}] was added to TargetList:[${YEL}${#Target_List[@]}${NC}]"
            else
                echo -e "${YEL}WARN${NC} invalid UUID:[${YEL}${input}${NC}] was entererd."
            fi
        else
            echo -e "${RED}ERROR${NC} No valid lines were entered for processing."
        fi
    done
}
build_target_list () {
     if ! $InteractiveMode; then # input must be a file = non-interactive mode
        local -i numlines=$(wc -l < "$InputFile")
        if (( numlines == 0 )); then 
            echo -e "${MAG}FATAL${NC} Inputfile:[${YEL}${InputFile}${NC}] was empty or not accessible."
        elif (( numlines >= 1 )); then
            readarray -t Target_List <<< "$(<"$InputFile")"    
        fi  
    elif $InteractiveMode; then
        if ! $UpdateMode; then # create + interactive mode
            get_subscription_ids_from_user "$Delimiter"
        elif $UpdateMode; then # update + interactive mode
            get_many_uuids_from_user    
        fi
    fi
    if $UseSubsIds || [[ $UuidType == 'subsids' ]]; then { readarray -t Target_List < <(make_update_list "${Target_List[@]}"); } fi
}
###################################### Get User Info and Start Script ###########################################
declare -i postat opterr
declare parsed_opts
[[ $# -eq 0 ]] && { echo -e "${YEL}WARNING${NC} No input parameters [$#] were found on stdin. Running with default settings."; }
getopt -T > /dev/null; opterr=$?  # check for enhanced getopt version
if (( $opterr == 4 )); then  # we got enhanced getopt
    declare Long_Opts=cid:,print,tenant:,tenant-id:,appid:,app-id:,al-access-key:,file:,delimiter:,delim:,update,wait,subscription-ids,subsids,testrun,debug,help 
    declare Opts=c:t:a:l:f:d:wurbgh
    ! parsed_opts=$(getopt --longoptions "$Long_Opts" --options "$Opts" -- "$@") # load and parse options using enhanced getopt
    postat=${PIPESTATUS[0]}
else 
    ! parsed_opts=$(getopt c:t:a:l:f:d:wuprbh "$@") # load and parse ONLY short options using original getopt
    postat=${PIPESTATUS[0]}
fi
if (( $postat != 0 )) || (( $opterr != 4 && $opterr != 0 )); then # check return and pipestatus for errors
    echo -e "${RED}ERROR${NC} invalid option was entered:[${YEL}$*${NC}] or missing required arg."
    usage
else 
    eval set -- "$parsed_opts"  # convert positional params to parsed options ('--' tells shell to ignore args for 'set')
    while true; do 
        case "${1,,}" in
            -c|--cid)                   { [[ $2 =~ $_NUM_ONLY_REGEX ]] && { Cid="$2"; CidL=true; }; shift 2; } ;;
            -t|--tenant|--tenant-id)    { [[ "$2" =~ $_UUID_REGEX ]] && { TenantId="$2"; TidL=true; }; shift 2; } ;;
            -a|--app-id|--appid)        { [[ "$2" =~ $_UUID_REGEX ]] && { AppId="$2"; AidL=true; }; shift 2; } ;;
            -l|--al-access-key)         { ALAccessKeyId="$2"; AlkL=true; shift 2; } ;;
            -d|--delimiter|--delim)     { [[ -n $(tr -d '[=;=][=-=][=|=][=,=][=:=][=.=]' <<< "${2::1}") ]] && { Delimiter="$2"; }; shift 2; } ;;
            -w|--wait)                  { WaitForDisco=true; shift; } ;;
            -f|--file)                  { [[ -f "$2" ]] && { InputFile="$2"; InteractiveMode=false; }; shift 2; } ;;
            -u|--update)                { UpdateMode=true; echo -e "${MAG}INFO${NC} Update mode was enabled"; shift; } ;;
            -b|--subsids|subscription-ids) { UseSubsIds=true; shift; } ;;
            -r|--testrun)               { TestRun=true; echo -e "${MAG}TESTRUN MODE${NC} was enabled"; shift; } ;;
            -g|--debug)                 { set -x; shift; } ;;
            -h|--help)                  { usage; shift; break; } ;;
            --)                         { shift; break; } ;; # end of options
        esac
    done
fi
if { $UseSubsIds && ! $UpdateMode && $InteractiveMode; } || { ! $UpdateMode && $UseSubsIds; }; then 
    echo -e "${MAG}FATAL${NC} incompatible options were selected. The update via \"subsid\" flag is for updating existing deployments via input files only. Please try again."; 
    exit 3
fi
# Get Inputs from User if none found
if ! $CidL && [[ -z $Cid ]]; then { get_cid_from_user; } fi
if ! $TidL && [[ -z "$TenantId" ]]; then { get_uuid_from_user 'Tenant ID' TenantId; } fi
if ! $AidL && [[ -z "$AppId" ]]; then { get_uuid_from_user 'Application ID' AppId; } fi
if ! $AlkL && [[ -z "$ALAccessKeyId" ]]; then { get_access_key_from_user; } fi
if [[ -n $Cid ]] && [[ -n "$TenantId" ]] && [[ -n "$AppId" ]]; then
    echo -e "${GRE}OKAY${NC} ready to create or update deployments in TargetList:[${YEL}${#Target_List[@]}${NC}]"
    if [[ -z "$InsecureSecretKey" ]]; then { get_secret_from_user 'Alert Logic' ALSecretKeyHash; }
    else { ALSecretKeyHash=$(encrypt_sk "$InsecureSecretKey"); }
    fi
    get_secret_from_user 'Azure App' AZSecretKeyHash
    echo -e "\n${CYA}INFO${NC} secret vars were stored securely. Attempting to set up an Alert Logic authentication token. Please wait..."
    [[ -n "$ALSecretKeyHash" ]] && { set_auth_token && Head="x-aims-auth-token: $Auth_Token"; }
    CloudInsightUrl=$(get_cloudinsight_url "$Cid")
    build_target_list
    if (( ${#Target_List[@]} >= 1 )); then
        confirm_start
        printf 'target:[%s]\n' "${Target_List[@]}"
        if $StartConfirmed; then
            if $UpdateMode; then
                for depinfo in "${Target_List[@]}"; do
                    IFS=, read -r depid subsid <<< "$depinfo"
                    update_deployment "$depid" "$subsid"
                done          
            elif ! $UpdateMode; then            
                for deptarget in "${Target_List[@]}"; do
                    IFS=${Delimiter:-,} read -r depname subsid <<< "$deptarget"
                    create_azure_deployment "$depname" "$subsid"
                done
            fi
        else { echo -e "${YEL}WARN${NC} mission was aborted"; }
        fi
    else
        echo -e "${MAG}FATAL${NC} Target list was empty or not accessible:\n\tTarget_List array size:[${YEL}${#Target_List[@]}${NC}]"
    fi
else    
    echo -e "${MAG}FATAL${NC} Necessary input was empty or not accessible:\n\tCid:[${YEL}${Cid}${NC}]\n\tenantId:[${YEL}${TenantId}${NC}]\n\tAppId:[${YEL}${AppId}${NC}]."
fi

    


