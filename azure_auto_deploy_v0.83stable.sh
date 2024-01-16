#!/usr/bin/bash
# Simple script Bicep to dynamically scale AlertLogic resources with a customer's Azure environment.
# When integrated into existing automation tools like Bicep, Terraform, Puppet, etc, deployment tiles will be created in Alert Logic for each Azure subscription input. 
# This allows end users to programmatically scale Alert Logic resources alongside an Azure Cloud Environment. 
# It should be noted that this script does NOT create or deploy IDS or Scanner appliances, nor does it install Alert Logic agents on VM's; It only deploys Alert Logic resources on Alert Logic infrastructure. 
# If a customer needs to automate the creation of Cloud infrastructure, they will beed to use the appropriate dev-ops automation tools for that.
# Author: aaron.celestin@fortra.com
# Copyright Fortra Inc, 2023
function usage () 
{
    local line='==========================================================================================================================================='
echo -e ${YEL}"$line${NC}\n\t${CYA}AlertLogic Azure Auto Deployment Script Version:${YEL} $version\n"${NC}
desc="'This script, when integrated into existing automation tools like Terraform, Puppet, etc, will create deployment tiles for each Azure subscription input. This allows end users to programatically scale Alert Logic resources alongside an Azure Cloud Environment. It should be noted that this script does NOT create or deploy IDS or Scanner appliances, nor does it install Alert Logic agents on VM's. In fact, this script will not deploy anything into any Azure environment, ever. It only deploys Alert Logic resources on Alert Logic infrastructure. If you need to automate the creation of Cloud infrastructure, use the appropriate dev-ops tools for that purpose.'"
fold -w $(( $(tput cols) - 20 )) -s <<< "$desc"
echo -e " Common usage: "
    echo -e "\t>_\$ $0 <<${YEL}AL_Account_Id${NC}>> <<${YEL}New_Deployment_Name${NC}>> <<${YEL}Subscription_Id${NC}>> <<${YEL}Active_Directory_Id${NC}>> <<${YEL}Ad_Client_Id${NC}>> <<${YEL}Client_Secret${NC}>>"${NC}
    echo -e ${YEL}"\n$line\n"${NC}
}

############################################# User Supplied Vars #############################################

declare aims_keyid='< aims auth token id from AlertLogic console >'
declare aims_secret_key='< aims auth token secret key from AlertLogic console >'
declare active_directory_id='< azure active directory id should be same across tenant >'

############################################# Static Variables #############################################
RED=$(tput setaf 1)
GRE=$(tput setaf 2)
YEL=$(tput setaf 3)
WHT=$(tput sgr0)
BLU=$(tput setaf 4)
CYA="\e[96m"
NC=$(tput sgr0)

# Script static variables
ash_dc='defender-us-ashburn'
den_dc='defender-us-denver'
npt_dc='defender-us-ashburn'

declare -i _PROC_ASST=10
declare -i _UUID_LENGTH=36
declare -i _SECRET_LENGTH=40
declare -i _AGENT_KEY_LENGTH=43
declare -i _HOST_KEY_LENGTH=45

declare CloudInsightUrl Head
declare version='0.83s'
declare defender_datacenter
declare UkUrl='https://api.cloudinsight.alertlogic.co.uk'
declare UsUrl='https://api.cloudinsight.alertlogic.com'
declare AzureCredUrl='https://api.cloudinsight.alertlogic.com/azure_explorer/v1/validate_credentials'

############################################# Auth Token Validation #############################################

# Try to set an AIMS auth token, kill the whole script if it fails (can't do anything without a token)
function set_auth_token ()
{
    local aims_key="$1"
    local aims_secret_key="$2"
    local api="https://api.cloudinsight.alertlogic.com/aims/v1/authenticate"
    local auth=$(curl -s -X POST -u "${aims_key}:${aims_secret_key}" "$api" | jq -r ". | .authentication.token")
    if [[ -n $auth ]]; then
        declare -x auth_token=$auth
        echo -e "AuthToken for the current session was set successfully.\nVariable exported to env:\n \$auth_token\n"
    else
        echo -e "AuthToken creation failed."
        exit 1
    fi
}

######################################## Helper and Utility Functions ##########################################

function san () { local msg="${@:-$(</dev/stdin)}"; echo -e "$msg" | sed 's/\"//g' | sed 's/[][]//g'; }
# Sometimes we get strings with spaces and all kinds of chars that have to all be escaped which can be a nightmare if it shows up in vars that you have to compare to each other
# So, I wrote this function that will more than {SAN}itize a string, it will also squish all whitespace to underscores and remove all spec-chars except underscores and periods
# We are squishing and cleaning like a mop does, hence the name
function mop () { local msg="${@:-$(</dev/stdin)}"; echo -e "${msg// /_}" | tr -dc '[:alnum:][=_=][=.=][=-=][=/=]'; }

# Get CloudInsight api Url based on CID
function get_cloudinsight_url ()
{
    local Cid=$(san "$1")
    case "$((Cid>>26))" in 
        0)      { echo "$UsUrl"; };; # Denver 
        1)      { echo "$UkUrl"; };; # Newport
        2)      { echo "$UsUrl"; };; # Ashburn
    esac
}

########################################## Azure API Wrapper Functions ##########################################

# Validate user-provided credentials 
function validate_azure_credentials ()
{
    local subscription_id=$(san "$1")
    local active_directory_id=$(san "$2")
    local ad_client_id=$(san "$3")
    local client_secret=$(san "$4")    
    local payload="{
        \"subscription_id\": \""$subscription_id"\",
        \"credential\": {
            \"id\": \"\",
            \"name\": \"\",
            \"type\": \"azure_ad_client\",
            \"azure_ad_client\": {
            \"active_directory_id\": \""$active_directory_id"\",
            \"client_id\": \""$ad_client_id"\",
            \"client_secret\": \""$client_secret"\"
            }
        }
    }"
    curl -sX POST -H "$Head" "$AzureCredUrl" -d "$payload"
}

# Load validated credentials to CloudInsight to create deployment tile. Returns JSON that includes credential_id
function load_azure_credentials ()
{
    local cid=$(san "$1")
    local active_directory_id=$(san "$2")
    local ad_client_id=$(san "$3")
    local client_secret=$(san "$4") 
    local api="$CloudInsightUrl/credentials/v2/$cid/credentials"
    local payload="{
        \"name\": \""$deployment_name"\",
        \"secrets\": {
            \"type\": \"azure_ad_client\",
            \"ad_id\": \""$active_directory_id"\",
            \"client_id\": \""$ad_client_id"\",
            \"client_secret\": \""$client_secret"\"
            }
        }"
    curl -sX POST -H "$Head" "$api" -d "$payload" 
}

# Create deployment tile, returns JSON
function create_deployment ()
{
    local cid=$(san "$1")
    local deployment_name=$(san "$2")
    local subscription_id=$(san "$3")
    local credential_id=$(san "$4")
    local def_dc
    ash_dc='defender-us-ashburn'
    den_dc='defender-us-denver'
    npt_dc='defender-us-ashburn'
    case "$((Cid>>26))" in
        0 )      def_dc="$den_dc";; # Denver
        1 )      def_dc="$npt_dc";; # Newport
        2 )      def_dc="$ash_dc";; # Ashburn
    esac
    local api="$CloudInsightUrl/deployments/v1/$cid/deployments"
    local payload="{
            \"name\": \""$deployment_name"\",
            \"platform\": {
                \"type\": \"azure\",
                \"id\": \""$subscription_id"\"
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
    curl -sX POST -H "$Head" "$api" -d "$payload"  
}

# GET deployment info after creation, returns JSON
function get_deployment_info ()
{
    local cid=$(san "$1")
    local deployment_id=$(san "$2")
    local api="$CloudInsightUrl/deployments/v1/$cid/deployments/$deployment_id"
    curl -sk GET -H "$Head" "$api"
}


# Call topology config on assets_query till at least one row (asset) is doscovered
function call_topology_config ()
{
    local cid=$(san "$1")
    local deployment_id=$(san "$2")
    local api="$CloudInsightUrl/assets_query/v1/$cid/deployments/$deployment_id/topology/config"
    declare -i result
	result=$(curl -sk GET -H "$Head" "$api" | jq -r '(.topology.rows)?' 2>/dev/null) 
    if [[ -n "$result" ]] && (( $result > 0 )); then
        echo true
    else    
        echo false
    fi
}

# Verify subscription does not exist in Azure account
function check_subscription_id ()
{
    local cid=$(san "$1")
    local ref_subs_id=$(san "$2")
    declare -a deployments
    local dep_name dep_id
    dep_api="$CloudInsightUrl/deployments/v1/$cid/deployments" 
    readarray -t deployments < <(curl -sX GET -H "$Head" "$dep_api" | jq -rc '.[] | [[(.name)],.id]')
    for deps in "${deployments[@]}"; do
        dep_name=$(echo "${deps%%],*}" | sed 's/[][]//g' | mop)
        dep_id=$(echo "${deps##*],}" | san)
        src_api="$CloudInsightUrl/sources/v1/$cid/sources/$dep_id" 
        subs_id=$(curl -sX GET -H "$Head" "$src_api" | jq -rc '(.source.config.azure.subscription_id)' | san)
        if [[ "$ref_subs_id" == "$subs_id" ]]; then
	    echo "$dep_name" 
            break
        fi
    done
}

####################################### Process and Control Functions ##########################################

# Main process
function main ()
{
    local cid="$1"
    local deployment_name="$2"
    local subscription_id="$3"
    local active_directory_id="$4"
    local ad_client_id="$5"
    local client_secret="$6"
    if (( $# != 6 )); then
        echo -e ${RED}"ERROR${NC}; main function failed; missing input parameters."
        exit 1
    fi
    if (( ${#subscription_id} != $_UUID_LENGTH )) || (( ${#active_directory_id} != $_UUID_LENGTH )) || (( ${#ad_client_id} != $_UUID_LENGTH )); then
        echo -e ${RED}"ERROR${NC}; main function failed; invalid input was entered."
        exit 1
    fi
    if (( ${#client_secret} != $_SECRET_LENGTH )); then
        echo -e ${RED}"ERROR${NC}; main function failed; invalid client secret was entered."
        exit 1
    fi
    local dep_name=$(check_subscription_id "$cid" "$subscription_id" 2>/dev/null)
    if [[ -n "$dep_name" ]]; then
	echo -e ${RED}"ERROR${NC} An existing Alert Logic deployment [${YEL}$dep_name${NC}] was already created using the subscription id [${YEL}$subscription_id${NC}]."
	echo -e "Check your settings and try again."
	exit 1
    fi
    declare -i _err
    local response credential_id cred_name cred_id
    # set AL script vars
    CloudInsightUrl=$(get_cloudinsight_url "$cid")
    echo -e ${CYA}"INFO${NC} sanity check; verify subscription id [${YEL}${subscription_id}${NC}] was set."
    # validate creds
   response=$(validate_azure_credentials "$subscription_id" "$active_directory_id" "$ad_client_id" "$client_secret"); _err=$?

    if (( $_err != 0 )) || [[ -z "$response" ]]; then
        echo -e ${RED}"ERROR${NC} Azure credential validation failed; empty response or non-zero exit status was returned."
        exit 1
    elif (( $_err == 0 )) && [[ -n "$response" ]]; then
        unset response _err
        echo -e ${GRE}"SUCCESS${NC} Azure credential validation completed successfully."
   	response=$(load_azure_credentials "$cid" "$active_directory_id" "$ad_client_id" "$client_secret"); _err=$?

    fi
    if (( $_err != 0 )) || [[ -z "$response" ]]; then
    	echo -e ${RED}"ERROR${NC} Azure credential loading failed; empty response or non-zero exit status was returned."
	exit 1
    elif (( $_err == 0 )) && [[ -n "$response" ]]; then
        echo -e ${GRE}"SUCCESS${NC} Azure credential loading completed successfully."
	    # get newly created credential id and name
    	local azure_info=$(jq -rc '[[(.name)],.id]?' <<< "$response")
    	cred_name=$(echo "${azure_info%%],*}" | sed 's/[][]//g')
        cred_id=$(echo "${azure_info##*],}" | sed 's/[][]//g')
    	# create deployment
	unset response _err
    	local deployment_id=$(create_deployment "$cid" "$deployment_name" "$subscription_id" "$cred_id" | jq -r '.id'); _err=$?

        if (( $_err != 0 )) || [[ -z "$deployment_id" ]]; then
		    echo -e ${RED}"ERROR${NC} Deployment creation failed; deployment_id was not found or returned non-zero exit status."
		    exit 1
    	elif (( $_err == 0 )) && [[ -n "$deployment_id" ]]; then
		    unset response _err
		    echo -e ${GRE}"SUCCESS${NC} Deployment created successfully."
	        response=$(get_deployment_info "$cid" "$deployment_id"); _err=$?

	        if (( $_err != 0 )) || [[ -z "$response" ]]; then
                echo -e ${RED}"ERROR${NC} Deployment info call failed; empty response or non-zero exit status was returned."
                exit 1
            elif (( $_err == 0 )) || [[ -n "$response" ]]; then
                while [ 1 ]; do
                    echo -e "INFO: process_config topology is started. Alert Logic deployment id [${YEL}${deployment_id}${NC}]. Please wait..."
		    unset response _err
                    sleep 5s
                    finished=$(call_topology_config "$cid" "$deployment_id")
                    if $finished; then
                        break 2
                    else
                        continue
                    fi
                done
                if "$(call_topology_config "$cid" "$deployment_id")"; then
                    echo -e ${GRE}"SUCCESS${NC} Azure Deployment [${YEL}${deployment_name}${NC}] was created successfully."
                else
                    echo -e ${RED}"FAILURE${NC} Azure Deployment [${YEL}${deployment_name}${NC}] was not created."
                    exit 1
                fi
	        fi
	    fi
    fi  
}

###################################### Get User Info and Start Script ###########################################
# Your Alert Logic Account ID
cid="$1"
# Name of the new deployment
deployment_name="$2"
# Azure Subscription ID
subscription_id="$3"
# Active Directory ID
active_directory_id="$4"
# Azure CLient ID or Azure Role ID
ad_client_id="$5"
# Azure Client Secret or Role Secret
client_secret="$6"

# ADDITIONAL INFO NEEDED FOR ALERTLOGIC AUTHENTICATION AND TOKEN GENERATION
# You can find these in the Alert Logic Console. Only one keyid:secretkey needs to be generated because it can be reused 
# by the set_auth_token function above to create an AIMS Authentication token which is what the API uses to authenticate users.
# The AIMS token, once created by the function above, is valid for around 5 hours, at which point a new AIMS token will need to 
# be generated to pass along with the APIs.
aims_keyid='< AL key ID >'
aims_secret_key='< AL secret key >'

# Append a '-d' or '-D' to the end of the command line parameters to enable Bash's debug mode 
if [[ ${7^^} == "-D" ]]; then { set -x; } else { set +x; } fi
# number of mandatory args
declare -i NUMOPTS=6

# If you want to pass a configuration file with all the inputs, put each variable on its own line in the same order as the cmd line
# parameters, and then enter the file name below.
# al_config_file='< path to config file >' 
#readarray -t input_array <<< "$(<"$al_config_file")"

if [[ -z "$auth_token" ]]; then
    set_auth_token "$aims_keyid" "$aims_secret_key"
elif (( $# >= $NUMOPTS )) && [[ -n "$auth_token" ]]; then    
    CloudInsightUrl=$(get_cloudinsight_url "$cid")
    Head="x-aims-auth-token: $auth_token"
    main "$cid" "$deployment_name" "$subscription_id" "$active_directory_id" "$ad_client_id" "$client_secret"
    # Uncomment this for config file parsing
    #main "$(IFS=' '; echo "${input_array[*]}")"
elif (( $# < $NUMOPTS )); then
    echo -e ${RED}"ERROR${NC} Missing parameters; invalid number of parameters were entered."
    usage
    exit 1
else
    echo -e ${RED}"ERROR${NC} Empty API token; check your Alert Logic AIMS auth_token and try again."
    usage
    exit 1
fi
