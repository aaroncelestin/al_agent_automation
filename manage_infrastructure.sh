#!/bin/bash
# shellcheck disable=SC2155,SC2119,SC2004,SC2053,SC2034,SC2027,SC2086,SC2120,SC2091,SC2294,SC2145
set -o pipefail
declare InfraScriptVersion='0.56_20260129'
declare AppName=$(basename "$0" .sh)
declare Today=$(date +%Y%m%d)
[[ ! -d "$HOME/logs" ]] && mkdir -p "$HOME/logs" && echo '' | tee "$LogPath"
declare LogPath="$HOME/logs/$AppName.$Today.log"
declare -r NC=$(tput sgr0)
declare -r RED=$(tput setaf 1)
declare -r GRE=$(tput setaf 2)
declare -r YEL=$(tput setaf 3)
declare -r BLU=$(tput setaf 4)
declare -r MAG=$(tput setaf 5)
declare -r CYA=$(tput setaf 6)
declare -r PURP=$'\033[0;95m'  
declare -r _UNIV_KEY_REGEX='^\/?(((dc\/host|appliance|agent)\/(?P<uuid>([\w]{8}-[\w]{4}-[\w]{4}-[\w]{4}-[\w]{12})))|(aws\/\w{2}-\w{4,11}-\d\/host\/.*)|(subscriptions\/(?&uuid)\/.*))'
declare -r _DC_HOST_KEY_REGEX='^(/dc/host/[0-9a-zA-Z]{8}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{12})$'
declare -r _DC_VPCKEY_REGEX='^(/dc/network/[\d\w]{8}-[\d\w]{4}-[\d\w]{4}-[\d\w]{4}-[\d\w]{12})$'
declare -r _DC_SUBKEY_REGEX='^(/dc/network/[\d\w]{8}-[\d\w]{4}-[\d\w]{4}-[\d\w]{4}-[\d\w]{12}/subnet/[\d\w]{8}-[\d\w]{4}-[\d\w]{4}-[\d\w]{4}-[\d\w]{12}/)$'
declare -r _AGENT_KEY_REGEX='^(/agent/[0-9a-zA-Z]{8}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{12})$'
declare -r _APPLIANCE_KEY_REGEX='^(/appliance/[0-9a-zA-Z]{8}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{12})$'
declare -r _NUM_ONLY_REGEX='^[[:digit:]]+$' # this is a regex and not an extglob (requires '=~')
declare -r _UUID_REGEX='[0-9a-zA-Z]{8}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{12}$'
# regex does not check the value of the prefix to between 0-32, makes the regex too long, use grep since bash chokes on the word boundaries
declare _CIDR_REGEX='^\b([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\b\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\b\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\b\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\/[0-9]{1,2}$'
declare _IPV4_REGEX='[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'
declare _PATT_REGEX='(([\d]+)\.([\d]*|[\*])\.([\d]*|[\*])\.([\*]))'
declare -r _REGION_REGEX='[a-z]{2}-[a-z]{4,9}-[0-9]'
declare UkUrl='https://api.cloudinsight.alertlogic.co.uk'
declare UsUrl='https://api.cloudinsight.alertlogic.com'
declare CurrentTopology
declare -i scriptid=7
declare -i _Min_Json_Size=45
declare -r Pro_Scope_Policy_uuid='D12D5E67-166C-474F-87AA-6F86FC9FB9BC'
declare _IsTopoCurrent=false
declare -a AddTargetList DetailedList # list of cidrs
declare -a DeleteTargetList # list of uuids
declare Cid CustomerName CloudInsightUrl DeploymentId DeploymentName NetworkName NetworkId NetworkKey Head InputFile AppMode='' Delim=','
declare CidSet=false DepidSet=false FileSet=false CidrSet=false TargetSet=false TestRun=false Debug=false PatternSet=false ModeSet=false ListAllMode=false
declare NetidSet=false NetkeySet=false CidValid=false SpanEnabled=false UseAutoNaming=true segset=false depset=false keyset=false netset=false LargeCidrMode=false
declare -i Segment=24 
###########################################################################################
#                            GENERAL UTILITY FUNCTIONS                                    #
###########################################################################################
# quick function to remove MSDOS-style CR line endings from an input file 
function rmcr () { [[ -f "$1" ]] && { perl -i -pe 's/\r//' "$1"; }; }
# Simple function to mark tstamps in log files and backups in case things get borked, format is RFC5424 compliant
function tstamp () { date +%Y-%m-%d-%a-T%H:%M:%S.%Z; }
# Helper function to replace 'tee' that decolors and strips ANSI escape codes from text before being sent to a log file
# Call this function like this so you still get 'tee' behavior of output text to both stdout and file:
#   > 'some text going to stdout' | tee >(_dee_) 
function _dee_ () { local msg=${@:-$(</dev/stdin)}; echo -e "$(tstamp) - $msg" | sed 's/\x1B[@A-Z\\\]^_]\|\x1B\[[0-9:;<=>?]*[-!"#$%&'"'"'()*+,.\/]*[][\\@A-Z^_`a-z{|}~]//g' >> "$LogPath"; }
# short for {SAN}itize
function san () { local msg="${*:-$(</dev/stdin)}"; echo -e "$msg" | sed 's/\"//g' | sed 's/[][]//g'; }
# debug mode switches for logic functions only
function debug_on () { if $Debug; then set -x; fi }
function debug_off () { if $Debug; then set +x; fi }
###########################################################################################
#                            USAGE AND TUI FUNCTIONS                                      #   
###########################################################################################
declare -i MenuW ScreenW=$(tput cols)
if (( ScreenW < 100 )) && (( ScreenW >= 63 )); then
    echo -e "${YEL}WARNING${NC} Terminal width:[${YEL}$ScreenW${NC}] is smaller than the minimum width (70 columns)! Menus may not render properly!"
    MenuW=$ScreenW
elif (( ScreenW >= 100 )) && (( ScreenW < 140 )); then
    MenuW=100
elif (( ScreenW >= 140 )); then
    MenuW=$(( ScreenW * 2/3 ))
elif (( ScreenW < 63 )); then  
    echo -e "${RED}ERROR${NC} Terminal width:[${YEL}$ScreenW${NC}] is too small (50 columns or less)! Please resize your terminal screen and try again."
    exit 4
fi
declare -i Mid=$(( MenuW/2 ))
declare -i Rt=$(( MenuW-Mid ))
# calculate starting print position of single line of text at center of given width
# takes int width and string text
# centerpos version 0.11a_20240114
function centerpos () { local -i width=$1; local str="${2::width}"; echo "$(( $width/2 + ${#str}/2 ))"; }
function san () { tr -dc '[:alnum:][=/=][=.=][=-=][=_=][=:=][=+=]' <<< "$*" ; }
function segm () { local -i w=$1; for ((i=0;i<$w;i++)); do echo -en '-'; done; echo; }
function infra_script_title () {
    local -i menuw=$(($(tput cols)*2/3))
    local title='Infrastructure Management Script' 
    local version="Version: $InfraScriptVersion"
    local -i tsl=$(centerpos $menuw "$title")
    local -i vsl=$(centerpos $menuw "$version")
    echo "+$(segm $((menuw + 1)))+"
    printf "%s %${tsl}s %$((menuw - tsl))s\n" "|" "$title" "|" 
    printf "%s %${vsl}s %$((menuw - vsl))s\n" "|" "$version" "|"
    echo "+$(segm $((menuw + 1)))+"
}
function infra_script_usage () {
    infra_script_title
    local -i exit_code=${1:-0}
    #local -i scrw=$(( $(tput cols) -6 ))
    local -i scrw=$(( MenuW + 4 ))
    local -i col1=$(( MenuW * 4/100))
    local -i col2=$(( MenuW * 16/100))
    local -i col3=$(( MenuW * 11/100))
    local -i col4=$(( MenuW * 69/100)) 
    local s="Short" l="Long" a="Args" d="Description"
    local desc="This interactive script will add or remove large numbers of networks and subnets to a Datacenter Deployment into the AlertLogic console. For input options you can enter CIDRs, a list of CIDRs, a list of subnets or a list of VPCs/VNETs. You can also enter one large CIDR and then specify a segment size (e.g. 24) for subnet creation within that CIDR. For example, a /18 broken up into /24-sized segments will create 64 255-host subnets. The script will read from file or standard-input and process each line accordingly.  The script uses the CloudInsight API to add the networks and subnets to the specified deployment. The script can also remove networks and subnets from a deployment using similar input methods including a pattern-matching feature (192.168.*.*). The script will log all actions taken to a log file located at: $HOME/logs/${GRE}$LogPath${NC}."
    echo -e "\n${YEL}DESCRIPTION${NC}:"
    fold -w $scrw -s <<< "$desc"
    echo -e "\n${YEL}NOTE${NC}: ${CYA}ONLY DATACENTER DEPLOYMENTS ARE SUPPORTED!${NC}"
    local conff="Subnets and VNets require unique names in the AlertLogic console. If you do not supply a list of names, for example, if you enter CIDRs, the script will automatically name the subnets and VNETS by replacing '.'s with '-'s like so: 10.100.50.20/24 becomes Subnet-10-100-50-20/24. If you supply a list of names, the script will use those names instead. Names and CIDR ranges must be unique within the deployment. If a name for two different CIDRs already exists, the script will append a number to the end of the new name to make it unique but existing CIDRs will be skipped altogether."
    local donff="This script is idempotent, which means that even if you run it multiple times with the same parameters, it will not make the same changes twice. As previously discussed, it checks for duplicate names and CIDRs. However, it does not check for overlapping CIDR ranges. The AlertLogic backend Assets service nominally checks for overlapping CIDR ranges and will usually reject any ranges that the script tries to load that overlap with existing networks. This script will log any of these errors given by the AlertLogic backend at run-time to the log file."
    echo -e "\n${YEL}CONFIGURATION LIMITATIONS${NC}:"
    fold -w $scrw -s <<< "$conff"
    fold -w $scrw -s <<< "$donff"
    echo -e "\n${YEL}INPUT FILE FORMAT${NC}:"
    local inff="Input files should contain one entry per-line and each entry may optionally be followed by a name separated by a comma. For names containing spaces, you MUST enclose the name with single or double quotes! Entries should be CIDRs, e.g., 192.168.0.0/18 or subnet names or VPC/VNET names as appropriate. Lines starting with '#' will be ignored as comments. Blank lines will also be ignored. Example file contents:"
    fold -w $scrw -s <<< "$inff"
    echo -e "\t192.168.1.0/24,\"Office Network\"\n\t10.0.0.0/25,\"DataCenter Network\" \n\t10.10.10.0/28,\"My_VPC_Name\" \n\t172.31.10.0/24,\"Another_VNET_Name\" # This is a comment line"
    echo -e "The script will process each line accordingly based on the provided input."
    local bn=$(basename "$0")
    local note5="${YEL}NOTE${NC}: Most special characters entered for filenames or paths will be ignored or removed IMMEDIATELY to avoid issues with script operation. Only alphanumeric letters, digits and the following special characters are allowed:[ / . - _ : + ]"
    echo; echo -e "$note5" | fold -w $scrw
    echo -e "\n${YEL}OPTIONS${NC}:" 
    local -a options=(
        '--cid,-cC,[CID],Specify the Customer ID for the account where the deployment exists.'
        '--deployment-id,-iI,[Deployment ID],Specify the Deployment ID where networks/subnets will be added or removed.'
        '--network-id,-nN,[Network ID],Specify the Network ID (VPC/VNET) where subnets will be added or removed.'
        '--cidr,-rR,[CIDR],Specify a single CIDR range to add or remove.'
        '--segment,-sS,[Segment Size],Specify the segment size for subnet creation within a given CIDR.'
        '--pattern,-pP,[Pattern],Specify a CIDR pattern with wildcards (e.g. 192.168.*.*) to match multiple CIDRs.'
        '--input-file,-fF,[File Path],Specify the path to an input file containing a list of CIDRs; subnet names; or VPC/VNET names.'
        '--make-list,-lL,[csv/table],Generate a table or CSV list of subnets in entire deployment or within a specified network.'
        '--add-networks,-aA, ,Flag to add networks (VPCs/VNETs) to the deployment.'
        '--remove-networks,-uU, ,Flag to remove networks (VPCs/VNETs) from the deployment.'
        '--add-subnets,-mM, ,Flag to add subnets to a specified network (VPC/VNET).'
        '--remove-subnets,-oO, ,Flag to remove subnets from a specified network (VPC/VNET).'
        '--delimiter,-dD,[Delimiter],Specify a custom delimiter for input file parsing (default is comma).'
        '--testrun,-tT, ,Run this script in TestRun Mode; no changes will be made.'
        '--debug,-bB, ,Run this script in debug mode.'
        "--help,-hH, ,Display this help message and exit." )
    if (( $(tput cols) < 80 )); then
        echo -e "ERROR: Terminal width is too narrow to display the help menu. Please increase the width of the terminal."
        exit 1
    elif (( $(tput cols) < 110 )); then
        for opt in "${options[@]}"; do
            IFS=, read -r short long desc <<< "$opt"
            echo -e "[Short]:$short\n[LongOpts]:$long\n[Description]:$desc\n\n"
        done
    else
        echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+$(segm $col4)+\n"
        printf "|%-${col1}s|%-${col2}s|%-${col3}s|%-${col4}s|\n" "${s::$col1}" "${l::$col2}" "${a::$col3}" "${d::$col4}"
        echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+$(segm $col4)+\n"
        for opt in "${options[@]}"; do
            IFS=, read -r long short arg desc <<< "$opt"
            printf "|%-${col1}s|%-${col2}s|%-${col3}s|%-${col4}s|\n"  "${short::$col1}" "${long::$col2}" "${arg::$col3}" "${desc::$col4}"
        done
        echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+$(segm $col4)+\n" 
    fi
    local -a examples=(
        '$_> ./manage_infrastructure.sh --cid 123456 --deployment-id 'WXYZ1234-ABCD-4F04-9E68-123456121A31' --input-file 'cidr_list.csv' --add-networks'
        '$_> ./manage_infrastructure.sh --cid 123456 --deployment-id 'WXYZ1234-ABCD-4F04-9E68-123456121A31' --input-file './vpc_list.txt' --remove-networks'
        '$_> ./manage_infrastructure.sh --cid 123456 -d 'WXYZ1234-ABCD-4F04-9E68-123456121A31' --network-id 'F5A00348-2F11-4F04-9E68-0B6F3C121A31' --cidr '10.12.151.0/18' --segment '24' --add-subnets'
        '$_> ./manage_infrastructure.sh --cid 123456 --deployment-id 'WXYZ1234-ABCD-4F04-9E68-123456121A31' --pattern '192.168.*.*' --network-name 'F5A00348-2F11-4F04-9E68-0B6F3C121A31' --remove-subnets --delimiter ';''
        '$_> ./manage_infrastructure.sh --cid 123456 -d 'WXYZ1234-ABCD-4F04-9E68-123456121A31' --network-id 'F5A00348-2F11-4F04-9E68-0B6F3C121A31' --cidr '10.10.0.0/16' --remove-subnets'
        '$_> ./manage_infrastructure.sh                    # <<--  no options will cause the script to run in interactive mode'
        '$_> ./manage_infrastructure.sh --help'
    )
    echo -e "\n${YEL}EXAMPLES${NC}:"
    for example in "${examples[@]}"; do
        echo -e "\$_> $example" | fold -w $scrw -s
    done
    return $exit_code
}
###########################################################################################
#                            ALERTLOGIC UTILITY FUNCTIONS                                 #
###########################################################################################
# given a Cid, get the CloudInsight API url
function get_cloudinsight_url () {
    debug_on
    local cid="$1"
    case "$((cid>>26))" in # bit shift right 26 bits =)
        0) { CloudInsightUrl="$UsUrl"; };; # Denver
        1) { CloudInsightUrl="$UkUrl"; };; # Newport
        2) { CloudInsightUrl="$UsUrl"; };; # Ashburn
    esac
    debug_off
}
function cid_exists() {
    debug_on
    local cid="$1"
    local api="https://api.global-services.global.alertlogic.com/aims/v1/$cid/account"
    local account_name=$(curl -skX GET -H "$Head" "$api" | jq '[.name]' | sed 's/[][]//g')
    echo -en "${account_name}" | tr -s '[:space:]' | tee >(_dee_)
    debug_off
}
# refresh and update the Current_Topo script var
function refresh_deployment_topology () {
    debug_on
    if [[ "$DeploymentId" =~ $_UUID_REGEX ]]; then
        local api="$CloudInsightUrl/assets_query/v1/$Cid/deployments/${DeploymentId//\"/}/topology/config"
        CurrentTopology=$(curl -sX GET -H "$Head" "$api" | jq -c '.')
    else
        echo -e "${RED}ERROR${NC} refresh_topology failed; deployment id:[${YEL}${DeploymentId}${NC}] was not set or invalid" | tee >(_dee_)
        exit 4
    fi
    debug_off
}
function validate_deployment () {
    debug_on
    local depid=${1:?"${RED}ERROR${NC} validate_deployment failed; missing input."}
    [[ ! "${Cid}" =~ $_NUM_ONLY_REGEX ]] && { echo -e "${RED}ERROR${NC} validate_deployment failed; no CID was set before validation:[${YEL}${Cid}${NC}]." | tee >(_dee_); return 1; }
    local api="$CloudInsightUrl/deployments/v1/$Cid/deployments/$depid"
    curl -sk GET -H "$Head" "$api" | jq -rc '(.name|gsub(","; "-"))'
    debug_off
}
###########################################################################################
#                         INFRASTRUCTURE LIST FUNCTIONS                                   #
###########################################################################################
function list_deployments () {
    debug_on
    local cid=${1:-Cid}
    [[ ! "${cid}" =~ $_NUM_ONLY_REGEX ]] && { echo -e "${RED}ERROR${NC} list_deployments failed; invalid Cid was entered:[${YEL}${cid}${NC}]." | tee >(_dee_); return 1; }
    local api="$CloudInsightUrl/deployments/v1/$cid/deployments"
    curl -sk GET -H "$Head" "$api" | jq -rc '.[] | select(.platform.type=="datacenter") | [(.name|gsub(","; "-")),.id] | @csv' # swap commas with dashes
    debug_off
}
function list_networks () {
    debug_on
    local deployment_uuid="${1//\"/}"
    if [[ ! "$deployment_uuid" =~ $_UUID_REGEX ]]; then echo -e "${RED}ERROR${NC} list_networks failed; bad input: deploymentid[${YEL}$deployment_uuid${NC}]" |tee >(_dee_); return 4; fi
    local api="$CloudInsightUrl/assets_query/v1/$Cid/deployments/$deployment_uuid/assets?asset_types=vpc&topo_chain=false"
    curl -sk GET -H "$Head" "$api" | jq -rc '.assets[][] | [(.name|gsub(","; "-")),.network_uuid,.key] | @csv'
    debug_off
}
function list_subnets_by_vpc_uuid () {
    debug_on
    local deployment_uuid="${1//\"/}"
    local network_uuid="${2//\"/}"
    if [[ ! "$deployment_uuid" =~ $_UUID_REGEX ]]; then echo -e "${RED}ERROR${NC} list_subnets failed; bad input: deploymentid[${YEL}$deployment_uuid${NC}]" |tee >(_dee_); return 4; fi 
    if [[ ! "$network_uuid" =~ $_UUID_REGEX ]]; then echo -e "${RED}ERROR${NC} list_subnets failed; bad input: network_uuid[${YEL}$network_uuid${NC}]" |tee >(_dee_); return 4; fi 
    local api="$CloudInsightUrl/assets_query/v1/${Cid}/deployments/${deployment_uuid}/assets?asset_types=vpc,subnet&vpc.network_uuid=${network_uuid}&topo_chain=false"
    curl -sk GET -H "$Head" "$api" | jq -rc '.assets[][] | select(.type=="subnet" and (.name=="Default Subnet"|not)) | [(.name|gsub(","; "-")),.subnet_uuid,.key,.cidr_block] | @csv'
    debug_off
}
function list_subnets_by_vpc_key () {
    debug_on
    local deployment_uuid="${1//\"/}"
    local network_key="${2//\"/}"
    if [[ ! "$deployment_uuid" =~ $_UUID_REGEX ]]; then echo -e "${RED}ERROR${NC} list_subnets failed; bad input: deploymentid[${YEL}$deployment_uuid${NC}]" |tee >(_dee_); return 4; fi 
    if [[ ! "$network_key" =~ $_DC_VPCKEY_REGEX ]]; then echo -e "${RED}ERROR${NC} list_subnets failed; bad input: network_key[${YEL}$network_key${NC}]" |tee >(_dee_); return 4; fi 
    local api="$CloudInsightUrl/assets_query/v1/${Cid}/deployments/${deployment_uuid}/assets?asset_types=vpc,subnet&vpc.key=${network_key}&topo_chain=false"
    curl -sk GET -H "$Head" "$api" | jq -rc '.assets[][] | select(.type=="subnet" and (.name=="Default Subnet"|not)) | [(.name|gsub(","; "-")),.subnet_uuid,.key,.cidr_block] | @csv'
    debug_off
}
# Given deployment id and vpc name, get the array of cidr ranges defined by the vpc
# returns array 
function list_vpc_cidrs () {
    debug_on
    if ! $_IsTopoCurrent; then { refresh_deployment_topology; } fi
    jq -r '.topology.data[] | select (.type=="vpc")? | .cidr_ranges[]' <<< "$CurrentTopology"
    debug_off
}
###########################################################################################
#                         INFRASTRUCTURE GET FUNCTIONS                                    #
###########################################################################################
# get whether span port is enabled for a given vpc
function is_span_port_enabled () { 
    local vpc_key="${1//\"/}"
    local api="$CloudInsightUrl/otis/v3/$Cid/options"
    curl -sX GET -H "$Head" "$api" | jq -c '.[] | select(.scope.vpc_key=="'"$vpc_key"'") | select(.name=="span_port_enabled")|.value'
}
function get_vpcuuid_by_cidr () {
    debug_on
    local cidr="${1//\"/}"
    if ! $_IsTopoCurrent; then { refresh_deployment_topology; } fi
    jq -r '.topology.data[] | select (.type=="vpc")? | select (.cidr_ranges[]=="'"$cidr"'")? | .network_uuid' <<< "$CurrentTopology"
    debug_off
}
function get_subuuid_by_cidr () {
    debug_on
    local cidr="${1//\"/}"
    if ! $_IsTopoCurrent; then { refresh_deployment_topology; } fi
    jq -r '.topology.data[] | select (.type=="subnet")? | select (.cidr_block=="'"$cidr"'")? | .subnet_uuid' <<< "$CurrentTopology"
    debug_off
}
# given a subnet identifier (name|uuid|cidr|key), try to get parent vnetuuid(s)
# if duplicate subnets exist, will return more than one vnetuuid
function get_subnet_parent_uuid_by_uuid () {
    debug_on
    local deployment_uuid="${1//\"/}"
    local subnet_uuid="$2"
    local vpc_key
    if ! $_IsTopoCurrent; then { refresh_deployment_topology; } fi
    if $(subnet_exists_by_uuid "$deployment_uuid" "$subnet_uuid"); then
        vpc_key=$(jq -r '.topology.data[] | select (.type=="subnet")? | select (.subnet_uuid=="'"$subnet_uuid"'")? | .key' <<< "$CurrentTopology" | cut -d/ -f1-4)
        jq -r '.topology.data[] | select (.type=="vpc")? | select (.key=="'"$vpc_key"'")? | .network_uuid' <<< "$CurrentTopology"
    else
        echo -e "${RED}ERROR${NC} get_subnet_parent_uuid failed; subnet[${YEL}${subnet_name}${NC}] was not found in deployment[${YEL}${deployment_uuid}${NC}]" |tee >(_dee_)
        return 4;
    fi
    debug_off
}
###########################################################################################
#                         INFRASTRUCTURE VALIDATION FUNCTIONS                             #
###########################################################################################
function vpc_exists_by_key () {
    local deployment_uuid="$1"
    local vpc_key="$2"
    local result
    if ! $_IsTopoCurrent; then { refresh_deployment_topology; } fi
    if [[ ! "$deployment_uuid" =~ $_UUID_REGEX ]] || [[ "$vpc_key" =~ $_DC_VPCKEY_REGEX ]]; then 
	    echo -e "${RED}ERROR${NC} vpc_exists_by_key failed; invalid input was given; depid:[${YEL}${deployment_uuid}${NC}] key:[${YEL}${vpc_key}${NC}]" |tee >(_dee_)
	    return 4
    else
        result=$(jq -r '.topology.data[] | select (.type=="vpc")? | select (.key=="'"$vpc_key"'")? | .' <<< "$CurrentTopology" 2>/dev/null)
        if (( ${#result} > 50 )) && [[ -n "$result" ]]; then { echo true; } else { echo false; } fi
    fi
}
function vpc_exists_by_uuid () {
    local deployment_uuid="$1"
    local vpc_uuid="$2"
    local result
    if ! $_IsTopoCurrent; then { refresh_deployment_topology; } fi
    if [[ ! "$deployment_uuid" =~ $_UUID_REGEX ]] || [[ ! "$vpc_uuid" =~ $_UUID_REGEX ]]; then 
	    echo -e "${RED}ERROR${NC} vpc_exists_by_uuid failed; invalid input was given; depid:[${YEL}${deployment_uuid}${NC}] uuid:[${YEL}${vpc_uuid}${NC}]" |tee >(_dee_)
	    return 4
    else
        result=$(jq -r '.topology.data[] | select (.type=="vpc")? | select (.network_uuid=="'"$vpc_uuid"'")? | .' <<< "$CurrentTopology" 2>/dev/null)
        if (( ${#result} > 50 )) && [[ -n "$result" ]]; then { echo true; } else { echo false; } fi
    fi
}
function vpc_exists_by_name () {
    local deployment_uuid="$1"
    local vpc_name="$2"
    local result
    if ! $_IsTopoCurrent; then { refresh_deployment_topology; } fi
    if [[ ! "$deployment_uuid" =~ $_UUID_REGEX ]] || [[ -z "$vpc_name" ]]; then 
	    echo -e "${RED}ERROR${NC} vpc_exists_by_name failed; invalid input was given; depid:[${YEL}${deployment_uuid}${NC}] name:[${YEL}${vpc_name}${NC}]" |tee >(_dee_)
	    return 4
    else
        result=$(jq -r '.topology.data[] | select (.type=="vpc")? | select (.name=="'"$vpc_name"'")? | .' <<< "$CurrentTopology" 2>/dev/null)
        if (( ${#result} > 50 )) && [[ -n "$result" ]]; then { echo true; } else { echo false; } fi
    fi
}
function subnet_exists_by_name () {
    local deployment_uuid="$1"
    local subnet_name="$2"
    local result
    if ! $_IsTopoCurrent; then { refresh_deployment_topology; } fi
    if [[ ! "$deployment_uuid" =~ $_UUID_REGEX ]] || [[ -z "$subnet_name" ]]; then 
	    echo -e "${RED}ERROR${NC} subnet_exists_by_name failed; invalid input was given; depid:[${YEL}${deployment_uuid}${NC}] name:[${YEL}${subnet_name}${NC}]" |tee >(_dee_)
	    return 4
    else
        result=$(jq -rc '.topology.data.[] | select(.name=="'"$subnet_name"'")' <<< "$CurrentTopology" 2>/dev/null)
        if (( ${#result} > 50 )) && [[ -n "$result" ]]; then { echo true; } else { echo false; } fi
    fi
}
function subnet_exists_by_cidr () {
    local deployment_uuid="$1"
    local subnet_cidr="$2"
    local result
    if ! $_IsTopoCurrent; then { refresh_deployment_topology; } fi
    if [[ ! "$deployment_uuid" =~ $_UUID_REGEX ]] || [[ -z $(grep -Pio $_CIDR_REGEX <<< "$subnet_cidr" ) ]]; then 
	    echo -e "${RED}ERROR${NC} subnet_exists_by_cidr failed; invalid input was given; depid:[${YEL}${deployment_uuid}${NC}] cidr:[${YEL}${subnet_cidr}${NC}]" |tee >(_dee_)
	    return 4
    else
        result=$(jq -rc '.topology.data.[] | select(.cidr_block=="'"$subnet_cidr"'")' <<< "$CurrentTopology" 2>/dev/null)
        if (( ${#result} > 50 )) && [[ -n "$result" ]]; then { echo true; } else { echo false; } fi
    fi
}
function subnet_exists_by_uuid () {
    local deployment_uuid="$1"
    local subnet_uuid="$2"
    local result
    if ! $_IsTopoCurrent; then { refresh_deployment_topology; } fi
    if [[ ! "$deployment_uuid" =~ $_UUID_REGEX ]] || [[ ! "$subnet_uuid" =~ $_UUID_REGEX ]]; then 
	    echo -e "${RED}ERROR${NC} subnet_exists_by_uuid failed; invalid input was given; depid:[${YEL}${deployment_uuid}${NC}] id:[${YEL}${subnet_uuid}${NC}]" |tee >(_dee_)
	    return 4
    else
        result=$(jq -rc '.topology.data.[] | select(.subnet_uuid=="'"$subnet_uuid"'")' <<< "$CurrentTopology" 2>/dev/null)
        if (( ${#result} > 50 )) && [[ -n "$result" ]]; then { echo true; } else { echo false; } fi
    fi
}
###########################################################################################
#                         INFRASTRUCTURE MODIFIER FUNCTIONS                               #
###########################################################################################
# create vnet with subnet defined by VCIDR. NO EXISTENCE OR OVERLAP CHECKS ARE DONE HERE
function add_vpc () {
    debug_on
    local deployment_uuid="${1//\"/}"
    local new_vpc_name="${2:-AutoNamed_VPC_$(date +%s)}"
    shift 2
    local -a new_cidr_range=( "$@" )
    if [[ ! "$deployment_uuid" =~ $_UUID_REGEX ]] || (( ${#new_cidr_range[@]} == 0 )); then 
        echo -e "${RED}ERROR${NC} add_vpc failed; bad inputs: deploymentid[${YEL}$deployment_uuid${NC}] or empty list:[${YEL}${#new_cidr_range[*]}${NC}]" |tee >(_dee_)
        return 4
    else
        local cidrlist c # convert array to comma-separated list string
        for cidr in "${new_cidr_range[@]}"; do { cidrlist+="${c}\"${cidr}\""; c=','; } done
        local api="$CloudInsightUrl/assets_manager/v1/$Cid/deployments/$deployment_uuid/networks"
        local payload="{\"network_name\":\"$new_vpc_name\",\"span_port_enabled\":"$SpanEnabled",\"cidr_ranges\":["$cidrlist"]}"
        if $TestRun; then
            echo -e "${MAG}TESTRUN MODE${NC} ADD_VPC TEST url:[${CYA}$api${NC}]" | tee >(_dee_)
            echo -e "${MAG}TESTRUN MODE${NC} ADD_VPC TEST payload:[$(jq -rc '.' <<< $payload)]" | tee >(_dee_)
            return 0
        else
            curl -sX POST -H "$Head" "$api" -d "$payload" | jq -c '.' && _IsTopoCurrent=false
        fi
    fi
    debug_off
}

# Given CIDR and target VNET name, add subnet to it. NO EXISTENCE OR OVERLAP CHECKS ARE DONE HERE
function add_subnet () {
    debug_on
    local deployment_uuid="${1//\"/}"
    local vpc_uuid="${2//\"/}"
    local new_subnet_name="${3:-AutoNamed_Subnet_$(date +%s)}"
    local new_subnet_cidr="$4"
    if [[ ! "$deployment_uuid" =~ $_UUID_REGEX ]] || [[ ! "$vpc_uuid" =~ $_UUID_REGEX ]] || [[ -z $(grep -Pio $_CIDR_REGEX <<< "$new_subnet_cidr" ) ]]; then 
        echo -e "${RED}ERROR${NC} add_subnet failed; bad inputs: deploymentid[${YEL}$deployment_uuid${NC}] vpcid[${YEL}$vpc_uuid${NC}] subnetname[${YEL}$new_subnet_name${NC}] or cidr[${YEL}$new_subnet_cidr${NC}]" |tee >(_dee_)
        return 4
    else
        local payload="{ \"subnet_name\": \"$new_subnet_name\", \"cidr_block\": \"$new_subnet_cidr\" }"
        local api="$CloudInsightUrl/assets_manager/v1/$Cid/deployments/$deployment_uuid/networks/$vpc_uuid/subnets"
        if $TestRun; then
            echo -e "${MAG}TESTRUN MODE${NC} ADD_SUBNET TEST url:[${CYA}$api${NC}]" | tee >(_dee_)
            echo -e "${MAG}TESTRUN MODE${NC} ADD_SUBNET TEST payload:[$(jq -rc '.' <<< $payload)]" | tee >(_dee_)
            return 0
        else
            curl -sX POST -H "$Head" "$api" -d "$payload" | jq -c '.' && _IsTopoCurrent=false
        fi
    fi
    debug_off
}
# Given new name, and target subnetname, change old subnet to new subnetname
function rename_subnet_by_uuid () {
    debug_on
    local deployment_uuid="${1//\"/}"
    local new_subnet_name="${2:?ERROR - rename_subnet_by_key - new subnet name is required}"
    local subnet_uuid="$3"
    if ! $_IsTopoCurrent; then { refresh_deployment_topology; } fi
    if $(subnet_exists_by_uuid "$deployment_uuid" "$subnet_uuid"); then
        local sub_json=$(jq -r '.topology.data[] | select (.type=="subnet")? | select (.subnet_uuid=="'"$subnet_uuid"'")? | .' <<< "$CurrentTopology")
        local vpcuuid=$(get_subnet_parent_uuid_by_uuid "$deployment_uuid" "$subnet_uuid")
        local subnet_cidr=$(jq -r '.cidr_block' <<< "$sub_json")
        local api="$CloudInsightUrl/assets_manager/v1/$Cid/deployments/$deployment_uuid/networks/$vpcuuid/subnets/$subnet_uuid"
        local payload="{\"subnet_name\":\"$new_subnet_name\",\"cidr_block\":"$subnet_cidr"}"
        if $TestRun; then
            echo -e "${MAG}TESTRUN MODE${NC} RENAME_SUBNET TEST url:[${CYA}$api${NC}]" | tee >(_dee_)
            echo -e "${MAG}TESTRUN MODE${NC} RENAME_SUBNET TEST payload:[$(jq -rc '.' <<< $payload)]" | tee >(_dee_)
            return 0
        else
            curl -sX PUT -H "$Head" "$api" -d "$payload" | jq -c '.' && _IsTopoCurrent=false
        fi
    else
        echo -e "${YEL}WARNING${NC} rename_subnet failed; subnet [${YEL}${subnet_cidr}${NC}] was not found in deployment[${YEL}${deployment_uuid}${NC}]" |tee >(_dee_)
        return 4
    fi
    debug_off
}
# Given new name, and target subnetname, change old subnet to new subnetname
function rename_subnet_by_cidr () {
    debug_on
    local deployment_uuid="${1//\"/}"
    local new_subnet_name="${2:?ERROR - rename_subnet_by_cidr - new subnet name is required}"
    local subnet_cidr="$3"
    if ! $_IsTopoCurrent; then { refresh_deployment_topology; } fi
    if $(subnet_exists_by_cidr "$deployment_uuid" "$subnet_cidr"); then
        local sub_json=$(jq -r '.topology.data[] | select (.type=="subnet")? | select (.cidr_block=="'"$subnet_cidr"'")? | .' <<< "$CurrentTopology")
        local subuuid=$(jq -r '.subnet_uuid' <<< "$sub_json")
        local vpcuuid=$(get_subnet_parent_uuid_by_uuid "$deployment_uuid" "$subuuid")
        local api="$CloudInsightUrl/assets_manager/v1/$Cid/deployments/$deployment_uuid/networks/$vpcuuid/subnets/$subuuid"
        local payload="{\"subnet_name\":\"$new_subnet_name\",\"cidr_block\":"$subnet_cidr"}"
        if $TestRun; then
            echo -e "${MAG}TESTRUN MODE${NC} RENAME_SUBNET TEST url:[${CYA}$api${NC}]" | tee >(_dee_)
            echo -e "${MAG}TESTRUN MODE${NC} RENAME_SUBNET TEST payload:[$(jq -rc '.' <<< $payload)]" | tee >(_dee_)
            return 0
        else
            curl -sX PUT -H "$Head" "$api" -d "$payload" | jq -c '.' && _IsTopoCurrent=false
        fi
    else
        echo -e "${YEL}WARNING${NC} rename_subnet failed; subnet [${YEL}${subnet_cidr}${NC}] was not found in deployment[${YEL}${deployment_uuid}${NC}]" |tee >(_dee_)
        return 4
    fi
    debug_off
}
function rename_vpc () {
    debug_on
    local deployment_uuid="$1"
    local vpc_param="$2"
    local new_vpc_name="${3:?ERROR - rename_vpc - new vpc name is required}"
    local vpc_json vpcuuid vpckey
    if ! $_IsTopoCurrent; then { refresh_deployment_topology; } fi
    if [[ "$vpc_param" =~ $_UUID_REGEX ]]; then
        vpcuuid="$vpc_param"
        if $(vpc_exists_by_uuid "$deployment_uuid" "$vpcuuid"); then
            vpc_json=$(jq -r '.topology.data[] | select (.type=="vpc")? | select (.network_uuid=="'"$vpcuuid"'")? | .' <<< "$CurrentTopology")
        else
            echo -e "${YEL}WARNING${NC} rename_vpc failed; param [${YEL}${param}${NC}]not found in deployment[${YEL}${deployment_uuid}${NC}]" |tee >(_dee_)
            return 4
        fi
        vpckey=$(jq -r '.key' <<< "$vpc_json")
    elif [[ "$vpc_param" =~ $_DC_VPCKEY_REGEX ]]; then
        vpckey="$vpc_param"
        if $(vpc_exists_by_key "$deployment_uuid" "$vpckey"); then
            vpc_json=$(jq -r '.topology.data[] | select (.type=="vpc")? | select (.key=="'"$vpckey"'")? | .' <<< "$CurrentTopology")
        else
            echo -e "${YEL}WARNING${NC} rename_vpc failed; param [${YEL}${param}${NC}]not found in deployment[${YEL}${deployment_uuid}${NC}]" |tee >(_dee_)
            return 4
        fi
        vpcuuid=$(jq -r '.network_uuid' <<< "$vpc_json")
    fi
    readarray -t vpccidrs <<< "$(jq -r '.cidr_ranges[]' <<< "$vpc_json")"
    # convert array to comma-separated list string
    local cidrlist c
    for cidr in "${vpccidrs[@]}"; do { cidrlist+="${c}${cidr}"; c=','; } done
    # check Otis to see if span was enabled
    local span_enabled=$(is_span_port_enabled "$vpckey")
    local api="$CloudInsightUrl/assets_manager/v1/$Cid/deployments/$deployment_uuid/networks/$vpcuuid"
    local payload="{ \"network_name\": \"$new_vpc_name\", \"span_port_enabled\":"$span_enabled", \"cidr_ranges\": ["$cidrlist"] }"
    if $TestRun; then
        echo -e "${MAG}TESTRUN MODE${NC} RENAME_VPC TEST url:[${CYA}$api${NC}]" | tee >(_dee_)
        echo -e "${MAG}TESTRUN MODE${NC} RENAME_VPC TEST payload:[$(jq -rc '.' <<< $payload)]" | tee >(_dee_)
        return 0    
    else
        curl -sX PUT -H "$Head" "$api" -d "$payload" | jq -c '.' && _IsTopoCurrent=false
    fi
    debug_off
}
# delete type, scope and key from assets record
function delete_vpc () {
    debug_on
    local cidr="$1"
    local vpc_param="${2//\"/}"
    if ! $_IsTopoCurrent; then { refresh_deployment_topology; } fi
    if [[ "$vpc_param" =~ $_UUID_REGEX ]]; then
        vpcuuid="$vpc_param"
    elif [[ "$vpc_param" =~ $_DC_VPCKEY_REGEX ]]; then
        vpcuuid=$(jq -r '.topology.data[] | select (.type=="vpc")? | select (.key=="'"$vpc_param"'")? | .network_uuid' <<< "$CurrentTopology")
    fi
    local vpcexists=$(vpc_exists_by_uuid "$DeploymentId" "$vpcuuid")
    if $vpcexists; then
        local api="$CloudInsightUrl/assets_manager/v1/$Cid/deployments/$DeploymentId/networks/$vpcuuid"
        if $TestRun; then
            echo -e "${MAG}TESTRUN MODE${NC} DELETE_VPC TEST url:[${CYA}$api${NC}]" | tee >(_dee_)
            return 0
        else
            curl -sX DELETE -H "$Head" "$api" && _IsTopoCurrent=false
        fi
    else
        echo -e "${YEL}WARNING${NC} delete_vpc failed; vpc with cidr:[${YEL}${cidr}${NC}] and vpcexists:[${YEL}${vpcexists}${NC}] was not found in deployment[${YEL}${DeploymentId}${NC}]" |tee >(_dee_)
        return 4
    fi
    debug_off      
}

# delete type, scope and key from assets record
function delete_subnet () {
    debug_on
    local cidr="$1"
    local subnet_param="${2//\"/}"
    if ! $_IsTopoCurrent; then { refresh_deployment_topology; } fi
    if [[ "$subnet_param" =~ $_UUID_REGEX ]]; then
        subnetuuid="$subnet_param"
    else
        subnetuuid=$(jq -r '.topology.data[] | select (.type=="subnet")? | select (.key=="'"$subnet_param"'")? | .network_uuid' <<< "$CurrentTopology")
    fi
    local subexists=$(subnet_exists_by_uuid "$DeploymentId" "$subnetuuid") 
    local vpcexists=$(vpc_exists_by_uuid "$DeploymentId" "$NetworkId")
    if $subexists && $vpcexists; then
        local api="$CloudInsightUrl/assets_manager/v1/$Cid/deployments/$DeploymentId/networks/$NetworkId/subnets/$subnetuuid"
        if $TestRun; then
            echo -e "${MAG}TESTRUN MODE${NC} DELETE_SUBNET TEST url:[${CYA}$api${NC}]" | tee >(_dee_)
            return 0
        else
            curl -sX DELETE -H "$Head" "$api" && _IsTopoCurrent=false
        fi
    else
        echo -e "${YEL}WARNING${NC} delete_subnet failed; subnet with cidr:[${YEL}${cidr}${NC}] and sub exists:[${YEL}${subexists}${NC}] or vpcexists:[${YEL}${vpcexists}${NC}] was not found in deployment[${YEL}${DeploymentId}${NC}]" |tee >(_dee_)
        return 4
    fi
    debug_off 
}
# this is not used currently but might integrate in future
function update_protection_level () {
    debug_on
    local deployment_uuid="$1"
    shift
    local vpclist=( "$@" )
    local existing_dep_json=$(stream_asset_topology "$deployment_uuid")
    local -i depversion=$(jq -rc '.version' <<< "$existing_dep_json")
    local api="https://api.cloudinsight.alertlogic.com/deployments/v1/$Cid/deployments/$deployment_uuid"
    local payload=$(make_protection_payload $depversion 'professional' "${vpclist[@]}")
    curl -sX PUT -H "$Head" "$api" -d "$payload"
    debug_off
}
###########################################################################################
#                          CREATE AND LOAD MULTI FUNCTIONS                                #
###########################################################################################
# creating a VPC with multiple subnets/cidrs is not supported by this operation
function make_vpcs () {
    debug_on
    local deployment_uuid="${1//\"/}"
    shift
    local -a new_cidr_list new_vpc_list=( "$@" )  # load the input list into an array
    local -i vpc_count=0
    refresh_deployment_topology "$deployment_uuid"
    local cidrs new_vpc_name response_json
    if ! $_IsTopoCurrent; then { refresh_deployment_topology; } fi
    if (( ${#new_vpc_list[@]} == 0 )) || [[ ! "$deployment_uuid" =~ $_UUID_REGEX ]]; then
        echo -e "${RED}ERROR${NC} make_vpcs failed; missing or invalid invalid inputs depid:[${YEL}$deployment_uuid${NC}] or inputlist:[${YEL}${#new_vpc_list[@]}${NC}]" |tee >(_dee_)
        return 4
    else
        for line in "${new_vpc_list[@]}"; do    
            if $UseAutoNaming; then # if auto-naming is enabled, make a name for each vpc
                [[ -n $(grep -Pio $_CIDR_REGEX <<< "$line" ) ]] && { new_vpc_name="VPC-${line//./-}"; new_vpc_cidr="$line"; }
            else 
                IFS=$Delim read -r new_vpc_cidr new_vpc_name <<< "$line"
            fi    
            if ! $(subnet_exists_by_cidr "$deployment_uuid" "$new_vpc_cidr"); then   # if subnet does not exist
                response_json=$(add_vpc "$deployment_uuid" "$new_vpc_name" "$new_vpc_cidr" | jq -c '.' 2>/dev/null)  # add vpc and catch response
                if [[ -n "$response_json" ]]; then
                    sleep 1s
                    if $(vpc_exists_by_name "$deployment_uuid" "$new_vpc_name"); then # check if new vpc is in topology config
                        vpc_count=$(($vpc_count+1))     # count the vpc was added
                        echo -e "${GRE}SUCCESS${NC} make_vpcs successfully added vpc[${YEL}${new_vpc_name}${NC}] with cidr(s)[${YEL}${new_vpc_cidr}${NC}]" |tee >(_dee_)
                    else
                        echo -e "${RED}ERROR${NC} make_vpcs -> post-add vpc verification failed; orig:[${RED}${new_vpc_name}${NC}] with cidr(s):[${RED}${new_vpc_cidr}${NC}]" |tee >(_dee_)
                        continue
                    fi
                else        # else if not added, log it and move on to next list item
                    echo -e "${RED}ERROR${NC} make_vpcs->vpc_add response[${RED}${response_json}${NC}] was empty for vpc[${RED}${new_vpc_name}${NC}] with cidr(s)[${RED}${new_vpc_cidr}${NC}]" |tee >(_dee_)
                    continue
                fi
            else       # if vpc exists, skip and move on to next list item
                echo -e "${YEL}WARNING${NC} make_vpcs failed; vpc [${YEL}${new_vpc_name}${NC}] already exists in deployment[${YEL}${deployment_uuid}${NC}]" |tee >(_dee_)
                continue
            fi
        done
    fi
    echo -e "${CYA}INFO${NC} make_vpcs process finished; [${YEL}${vpc_count}${NC}] vpcs were added to deployment [${YEL}${deployment_uuid}${NC}]" |tee >(_dee_)
    debug_off
}
function make_subnets () {
    debug_on
    local deployment_uuid="${1//\"/}"
    local target_vpc_uuid="${2//\"/}"
    shift 2
    local -a new_subnet_list=( "$@" )
    local -i subnet_count=0
    if ! $_IsTopoCurrent; then { refresh_deployment_topology; } fi
    if (( ${#new_subnet_list[@]} == 0 )) || [[ ! "$deployment_uuid" =~ $_UUID_REGEX ]] || [[ ! "$target_vpc_uuid" =~ $_UUID_REGEX ]]; then
        echo -e "${RED}ERROR${NC} make_subnets failed; missing or invalid inputs depid:[${YEL}$deployment_uuid${NC}] vpcid:[${YEL}$target_vpc_uuid${NC}] or inputlist:[${YEL}${#new_subnet_list[@]}${NC}]" |tee >(_dee_)
        return 4
    else
        for line in "${new_subnet_list[@]}"; do
            local new_sub_name new_sub_cidr
            if $UseAutoNaming || [[ -n $(grep -Pio $_CIDR_REGEX <<< "$line" ) ]]; then
                new_sub_cidr="$line"
                new_sub_name="Subnet-${new_sub_cidr//./-}"   
            else
                IFS=, read -r new_sub_cidr new_sub_name <<< "$line"
            fi
            if ! $(subnet_exists_by_cidr "$deployment_uuid" "$new_sub_cidr"); then
                local response_json=$(add_subnet "$deployment_uuid" "$target_vpc_uuid" "$new_sub_name" "$new_sub_cidr" | jq -c '.' 2>/dev/null)
                if [[ -n "$response_json" ]]; then
                    sleep 1s
                    if $(subnet_exists_by_name "$deployment_uuid" "$new_sub_name"); then # check if new subnet is in topology config
                        subnet_count=$(($subnet_count+1))
                        echo -e "${GRE}SUCCESS${NC} make_subnets successfully added subnet[${YEL}${new_sub_name}${NC}] with cidr(s)[${YEL}${new_sub_cidr}${NC}]" |tee >(_dee_)
                    else
                        echo -e "${RED}ERROR${NC} make_subnets operation failed verifying subnet[${RED}${new_sub_name}${NC}] with cidr(s)[${RED}${new_sub_cidr}${NC}]" |tee >(_dee_)
                        continue
                    fi
                else        # else if not added, log it and move on to next list item
                    echo -e "${RED}ERROR${NC} make_subnets->subnet_add response[${RED}${response_json}${NC}] was empty for subnet[${RED}${new_sub_name}${NC}] with cidr(s)[${RED}${new_sub_cidr}${NC}]" |tee >(_dee_)
                    continue
                fi
            else       # if subnet exists, skip and move on to next list item
                echo -e "${YEL}WARNING${NC} make_subnets warning; SKIPPING already existing subnet cidr:[${RED}${new_sub_cidr}${NC}] named:[${YEL}${new_sub_name}${NC}] in deployment:[${YEL}${deployment_uuid}${NC}]" |tee >(_dee_)
                continue
            fi
        done
    fi
    echo -e "${CYA}INFO${NC} make_subnets process finished; [${YEL}${subnet_count}${NC}] subnets were added to deployment[${YEL}${deployment_uuid}${NC}]" |tee >(_dee_)
    debug_off
}
#################################################################################################
#                               IPv4 CONVERSION FUNCTIONS                                       #                   
#################################################################################################
function dec2ip () {
    debug_on 
    local ip delim dec=${*:-$(</dev/stdin)}
    for e in {3..0}; do
        ((octet = dec / (256 ** e) )); 
        ((dec -= octet * 256 ** e)); 
        ip+=$delim$octet; 
        delim=.
    done
    printf '%s\n' "$ip"
    debug_off
}
# awk is way faster than bash at this so we will use this to get our network and broadcast addresses
# output comes out like this <network ipv4 address>:<broadcast ipv4 address>
function awk_get_cidr_boundaries_dec () {
    debug_on
    local cidr="$1"
    gawk -v cidr="$cidr" --non-decimal-data 'BEGIN {
        split(cidr,a,"/")
        cidr_net = a[1]
        cidr_prefix = a[2]
        zeroes = 32 - cidr_prefix                                   # for calculating netmask
        split(cidr_net, cax, ".")
        cidr_ip_dec = ((cax[1]*256+cax[2])*256+cax[3])*256+cax[4]
        nmask=0
        for (i=0; i < zeroes; i++)
            nmask = xor( lshift(nmask,1), 1 )                       # nmask is left shifted by 1 then xor-ed with 1
        net_mask_dec = xor(0xffffffff,nmask)                        # finally, net_mask gets unity xor-ed with nmask
        host_mask_dec = xor(0xffffffff,net_mask_dec)                # get host_mask which is just the inverted net_mask
        net_ip_dec = and(cidr_ip_dec, net_mask_dec)                 # get net ip in decimal format
        bcast_ip_dec = or(host_mask_dec, net_ip_dec)                # broadcast ip
        print net_ip_dec":"bcast_ip_dec
    }'
    debug_off
}
function get_cidr_boundaries () {
    debug_on
    local cidr="$1"
    IFS=: read -r net_dec bcast_dec <<< "$(awk_get_cidr_boundaries_dec "$cidr")"
    echo "$(dec2ip "$net_dec"):$(dec2ip "$bcast_dec")"
    debug_off
}
function int2ip () { local ip=$1; echo "$(( (ip>>24) & 255 )).$(( (ip>>16) & 255 )).$(( (ip>>8) & 255 )).$((ip & 255))"; }
function ip2int () { local -i a b c d; IFS='.' read -r a b c d <<< $1; echo -e $(( (a<<24)+(b<<16)+(c<<8)+d )); } 
function convert_large_cidr_to_subnets () {
    debug_on
    local cidr="$1"
    local -i segsize=$2 
    [[ -z "$(grep -Po $_CIDR_REGEX <<< "$cidr")" ]] && { echo -e "${RED}ERROR${NC} convert_large_cidr_to_subnets failed; invalid CIDR was input:[${YEL}$cidr${NC}]"| tee >(_dee_); return 8; }
    IFS='/' read -r net prefix <<< "$cidr"
    (( prefix < 16 || prefix > 31 )) && { echo -e "${RED}ERROR${NC} convert_large_cidr_to_subnets failed; invalid CIDR prefix was input:[${YEL}$prefix${NC}]\nOnly prefixes [16-31] are supported"| tee >(_dee_); return 8; }
    if (( segsize <= prefix || segsize > 31 )); then
        echo -e "${RED}ERROR${NC} convert_large_cidr_to_subnets failed; invalid segment size was input:[${YEL}$segsize${NC}]\nSegment size must be larger than CIDR prefix and less than or equal to 30."| tee >(_dee_); 
        return 8
    fi
    local -i new_prefix_diff=$(( segsize - prefix ))
    #local -i sub_size=$(( 2 ** new_prefix_diff ))
    local -i sub_size=$(( 1 << (32 - segsize) ))
    IFS=: read -r net_dec bcast_dec <<< "$(awk_get_cidr_boundaries_dec "$cidr")"
    for (( ip=$net_dec; ip<$(( $net_dec + $sub_size * (1 << $new_prefix_diff) )); ip+=$sub_size )); do 
        echo "$(int2ip $ip)/$segsize"
    done
    debug_off
}
function convert_cidr_to_iplist () {
    debug_on
    local cidr="$1"
    [[ -z "$(grep -Po $_CIDR_REGEX <<< "$cidr")" ]] && { echo -e "${RED}ERROR${NC} convert_cidr_to_iplist failed; invalid CIDR was input:[${YEL}$cidr${NC}]"| tee >(_dee_); return 8; }
    IFS='/' read -r net prefix <<< "$cidr"
    (( prefix < 16 || prefix > 32 )) && { echo -e "${RED}ERROR${NC} convert_cidr_to_iplist failed; invalid CIDR prefix was input:[${YEL}$prefix${NC}]\nOnly prefixes [16-32] are supported."| tee >(_dee_); return 8; }
    IFS=: read -r net_ip bcast_ip <<< "$(get_cidr_boundaries "$cidr")"
    IFS=. read -ra ipa <<< "$net_ip"
    IFS=. read -ra ipb <<< "$bcast_ip"
    (( ipa[2] == 0 )) && ipa[2]=1 
    (( ipb[2] == 255 )) && ipb[2]=254
    (( ipa[3] == 0 )) && ipa[3]=1
    (( ipb[3] == 255 )) && ipb[3]=254
    IFS=' ' read -ra iplist <<< "$(eval "echo "${ipa[0]}.${ipa[1]}.{${ipa[2]}..${ipb[2]}}.{${ipa[3]}..${ipb[3]}}"")"
    echo "${iplist[@]}"
    debug_off
}
# validate input by user, right now for delete mode. Later this will be refactored to check ALL user input for all operations
function delete_check () {
    debug_on 
    local matcher="$1"
    shift
    local -a cidrlist=( "$@" )
    local -a exlist matchedlist
    if ! $_IsTopoCurrent; then { refresh_deployment_topology; } fi
    readarray -t exlist < <(list_vpc_cidrs "$DeploymentId")
    if [[ -n $(grep -Pio $_PATT_REGEX <<< "$matcher") ]]; then 
        #echo "exlist size ${#exlist[@]}"
        # check each item to make sure its valid and make lists of targets for operation
        for cidr in "${exlist[@]}"; do                      
            if [[ "${cidr%%\/*}" =~ $matcher ]]; then
                matchedlist+=( "$cidr" )
                [[ "$AppMode" == 'delvpc' ]] && DeleteTargetList+=( "$cidr,$(get_vpcuuid_by_cidr "$cidr")" )  
                [[ "$AppMode" == 'delsub' ]] && DeleteTargetList+=( "$cidr,$(get_subuuid_by_cidr "$cidr")" ) 
            fi
        done
    elif [[ "$matcher" == '-' ]] && (( ${#cidrlist[@]} >= 1 )); then
        readarray -t existing < <(printf '%s\n' "${exlist[@]}" | sort)
        readarray -t input < <(printf '%s\n' "${cidrlist[@]}" | sort)
        readarray -t common < <(comm -12 <(printf '%s\n' "${existing[@]}") <(printf '%s\n' "${input[@]}"))
        if (( ${#common[@]} >= 1 )); then
            for cidr in "${common[@]}"; do
                [[ "$AppMode" == 'delvpc' ]] && DeleteTargetList+=( "$cidr,$(get_vpcuuid_by_cidr "$cidr")" )  
                [[ "$AppMode" == 'delsub' ]] && DeleteTargetList+=( "$cidr,$(get_subuuid_by_cidr "$cidr")" ) 
            done
        else
            echo -e "${YEL}WARNING${NC} delete_check found no matching cidrs between existing vpcs and input list." |tee >(_dee_)
            return 4
        fi    
    else
        echo -e "${RED}ERROR${NC} delete_check failed; invalid matcher was entered:[${YEL}$matcher${NC}]" |tee >(_dee_)
        return 8
    fi
    debug_off
}
#################################################################################################
#                               MENU AND DISPLAY FUNCTIONS                                      #                   
#################################################################################################
# Get input from user by allowing them to select the deployment from a numbered list, if only one deployment exists, it is auto-selected
# width of menu is based on screen width and if lower than 60 cols, a simplified menu with no deployment id is shown
function get_deployment_menu () {
    debug_on
    local -a deplist
    local -i col1=$(( MenuW * 10/100))
    local -i col2=$(( MenuW * 40/100))
    local -i col3=$(( MenuW * 50/100)) 
    if $DepidSet; then
        echo -e "\n${CYA}INFO${NC} Deployment ID:[${YEL}$DeploymentId${NC}] was already set; skipping deployment selection." | tee >(_dee_)
        return 0
    fi
    if ! $CidSet || ! $CidValid || [[ ! $Cid =~ $_NUM_ONLY_REGEX ]]; then
        echo -e "${RED}ERROR${NC} Cannot get deployment list; CID:[${YEL}$Cid${NC}] is not set or invalid. Exiting." | tee >(_dee_)
        clean_exit 2
    fi
    echo -e "\n${CYA}INFO${NC} Fetching deployments for CID:[${YEL}$Cid${NC}]..." 
    readarray -t deplist < <(list_deployments "$Cid")
    if (( ${#deplist[@]} == 0 )); then
        echo -e "${RED}ERROR${NC} No deployments found for CID:[${YEL}$Cid${NC}]. Exiting." | tee >(_dee_)
        clean_exit 2
    elif (( ${#deplist[@]} == 1 )); then
        IFS=, read -r depname depid <<< "${deplist[0]}"
        echo -e "\n${CYA}INFO${NC} Only one deployment found for CID:[${YEL}$Cid${NC}]; selecting deployment:[${YEL}$depname${NC}] with ID:[${YEL}$depid${NC}]." | tee >(_dee_)
        DeploymentId="${depid//\"/}" && DepidSet=true
        DeploymentName="$depname"
        return 0
    else
        debug_off
        local -i index=1
        if (( ScreenW < 60 )); then
            col2=$(( MenuW * 10/100 ))
            col2=$(( MenuW * 90/100 ))
            echo -e "+$(segm $MenuW)-+"
            printf "|${BLU}%${Mid}s${NC}%${Rt}s |\n" "DEPLOYMENT SELECTION MENU" 
            echo -en "+$(segm $col1)+$(segm $col2)+\n"
            printf "|%-${col1}s|%-${col2}s|\n" "Indx" "Deployment Name"
            echo -en "+$(segm $col1)+$(segm $col2)+\n"
            for dep in "${deplist[@]}"; do
                IFS=, read -r depname depid <<< "$dep"
                printf "|%-${col1}s|%-${col2}s|\n"  "${index}" "${depname::$col2}"
                echo -en "+$(segm $col1)+$(segm $col2)+\n"
                (( index++ ))
            done     
        else
            echo -e "+$(segm $MenuW)+"
            printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "DEPLOYMENT SELECTION MENU"
            echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+\n"
            printf "|%-${col1}s|%-${col2}s|%-${col3}s|\n" "Index" "Deployment Name" "Deployment ID"
            echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+\n"
            for dep in "${deplist[@]}"; do
                IFS=, read -r depname depid <<< "$dep"
                printf "|%-${col1}s|%-${col2}s|%-${col3}s|\n"  "${index}" "${depname::$col2}" "${depid::$col3}"
                echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+\n"
                (( index++ ))
            done
        fi
        debug_on
        read -rp $'\n'"Enter the index number of the deployment to add/remove subnets/vpcs to: $(echo -e "${RED}->>${NC} ")" dep_index
        if ! [[ "$dep_index" =~ ^[0-9]+$ ]] || (( dep_index < 1 )) || (( dep_index > ${#deplist[@]} )); then
            echo -e "${RED}ERROR${NC} Invalid deployment index:[${YEL}$dep_index${NC}] entered. Please try again."
            get_deployment_menu
        else
            IFS=, read -r sel_depname sel_depid <<< "${deplist[$((dep_index-1))]}"
            echo -e "\n${CYA}INFO${NC} You selected deployment:[${YEL}$sel_depname${NC}] with ID:[${YEL}$sel_depid${NC}]."
            DeploymentId="${sel_depid//\"/}" && DepidSet=true
            DeploymentName="$sel_depname"
        fi
    fi
    debug_on
}
function get_vpc_menu () {
    debug_on
    local -a netlist
    local -i col1=$(( MenuW * 10/100))
    local -i col2=$(( MenuW * 40/100))
    local -i col3=$(( MenuW * 50/100)) 
    if $NetidSet; then
        echo -e "\n${CYA}INFO${NC} Network ID:[${YEL}$NetworkId${NC}] was already set; skipping network selection." | tee >(_dee_)
        return 0
    fi
    if ! $CidSet || ! $CidValid || [[ ! $Cid =~ $_NUM_ONLY_REGEX ]] || [[ ! $DeploymentId =~ $_UUID_REGEX ]]; then
        echo -e "${RED}ERROR${NC} Cannot get VPC list; CID:[${YEL}$Cid${NC}] or Deployment ID:[${YEL}$DeploymentId${NC}] is not set or invalid. Exiting." | tee >(_dee_)
        clean_exit 2
    fi
    echo -e "\n${CYA}INFO${NC} Fetching networks for Deployment:[${YEL}$DeploymentId${NC}]..."
    readarray -t netlist < <(list_networks "$DeploymentId")
    if (( ${#netlist[@]} == 0 )); then
        echo -e "${RED}ERROR${NC} No networks found for Deployment:[${YEL}$DeploymentId${NC}]. Exiting."| tee >(_dee_)
        clean_exit 2
    elif (( ${#netlist[@]} == 1 )); then
        IFS=, read -r netname netuuid netkey <<< "${netlist[0]}"
        echo -e "\n${CYA}INFO${NC} Only one network found for Deployment:[${YEL}$DeploymentName${NC}]; selecting network:[${YEL}$netname${NC}] with ID:[${YEL}$netuuid${NC}]." | tee >(_dee_)
        NetworkId="${netuuid//\"/}" && NetidSet=true
        NetworkName="$netname"
        NetworkKey="$netkey"
        return 0
    else
        debug_off
        local -i index=1
        if (( ScreenW < 60 )); then
            col2=$(( MenuW * 10/100 ))
            col2=$(( MenuW * 90/100 ))
            echo -e "+-$(segm $MenuW)+"
            printf "| ${BLU}%${Mid}s${NC}%${Rt}s|\n" "VPC/NETWORK SELECTION MENU" 
            echo -en "+$(segm $col1)+$(segm $col2)+\n"
            printf "|%-${col1}s|%-${col2}s|\n" "Indx" "Network Name"
            echo -en "+$(segm $col1)+$(segm $col2)+\n"
            for net in "${netlist[@]}"; do
                IFS=, read -r netname u k <<< "$net"
                printf "|%-${col1}s|%-${col2}s|\n"  "${index}" "${netname::$col2}"
                echo -en "+$(segm $col1)+$(segm $col2)+\n"
                (( index++ ))
            done     
        else
            echo -e "+$(segm $MenuW)+"
            printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "VPC/NETWORK SELECTION MENU"
            echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+\n"
            printf "|%-${col1}s|%-${col2}s|%-${col3}s|\n" "Index" "Network Name" "Network ID"
            echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+\n"
            for net in "${netlist[@]}"; do
                IFS=, read -r netname netid k <<< "$net"
                printf "|%-${col1}s|%-${col2}s|%-${col3}s|\n"  "${index}" "${netname::$col2}" "${netid::$col3}"
                echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+\n"
                (( index++ ))
            done
        fi
        debug_on
        read -rp $'\n'"Enter the index number of the network to add/remove/list subnets to/from: $(echo -e "${RED}->>${NC} ")" net_index
        if ! [[ "$net_index" =~ ^[0-9]+$ ]] || (( net_index < 1 )) || (( net_index > ${#netlist[@]} )); then
            echo -e "${RED}ERROR${NC} Invalid network index:[${YEL}$net_index${NC}] entered. Please try again."
            get_vpc_menu
        else
            IFS=, read -r sel_netname sel_netid sel_netkey <<< "${netlist[$((net_index-1))]}"
            echo -e "\n${CYA}INFO${NC} You selected network:[${YEL}$sel_netname${NC}] with ID:[${YEL}$sel_netid${NC}]." | tee >(_dee_)
            NetworkId="${sel_netid//\"/}" && NetidSet=true
            NetworkName="$sel_netname"
            NetworkKey="$sel_netkey"
        fi
    fi    
    debug_off
}
function get_cid_menu () {
    debug_off
    echo -e "+$(segm $MenuW)+"
    printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "CID INPUT MENU"
    echo -e "+$(segm $MenuW)+"
    debug_on
    read -rp $'\n'"Enter the Alert Logic Customer ID (CID) to to add/remove subnets to/from: $(echo -e "${RED}->>${NC}") " input_cid
    if ! [[ "$input_cid" =~ $_NUM_ONLY_REGEX ]]; then
        echo -e "${RED}ERROR${NC} Invalid CID:[${YEL}$input_cid${NC}] entered. Exiting." | tee >(_dee_)
        clean_exit 2
    else
        CustomerName=$(cid_exists "$input_cid" | tr -d $'\n')
        if [[ -z "$CustomerName" ]]; then
            echo -e "${RED}ERROR${NC} CID:[${YEL}$input_cid${NC}] does not exist or could not be found. Exiting." | tee >(_dee_)
            clean_exit 2
        else
            echo -e "\n${CYA}INFO${NC} You selected CID:[${YEL}$input_cid${NC}] with account name:[${YEL}$CustomerName${NC}]." | tee >(_dee_)
            get_cloudinsight_url "$Cid"
            Cid="$input_cid" && CidSet=true; CidValid=true
        fi
    fi
}
function main_menu () {
    debug_off
    local -i col1=$(( MenuW * 10/100))
    local -i col2=$(( MenuW * 90/100))
    local -a action_options=(
        '1, Add VPCs/Networks to Datacenter deployment'
        '2, Remove VPCs/Networks from Datacenter deployment'
        '3, Add Subnets to a Datacenter VPC/Network'
        '4, Remove Subnets from a Datacenter VPC/Network'
        '5, List all VPCs and Subnets by Datacenter deployment'
        '6, Exit script'
    )
    echo -e "+$(segm $MenuW)+"
    printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "MAIN MENU"
    echo -en "+$(segm $col1)+$(segm $col2)+\n"
    printf "|%-${col1}s|%-${col2}s|\n" "Option" "Description"
    echo -en "+$(segm $col1)+$(segm $col2)+\n"
    for option in "${action_options[@]}"; do
        IFS=, read -r opt desc <<< "$option"
        printf "|%-${col1}s|%-${col2}s|\n" "$opt" "$desc"
        echo -en "+$(segm $col1)+$(segm $col2)+\n"
    done
    read -rp $'\n'"Select an input option (1-6): $(echo -e "${RED}->>${NC} ")" input_option
    if [[ ! "$input_option" =~ $_NUM_ONLY_REGEX ]] || (( input_option < 1 || input_option > 6 )); then
        echo -e "${RED}ERROR${NC} Invalid action option:[${YEL}$input_option${NC}] was selected. Exiting." | tee >(_dee_)
        clean_exit 2
    else
        case "$input_option" in
            1)  { AppMode='addvpc'; } ;;
            2)  { AppMode='delvpc'; } ;;
            3)  { AppMode='addsub'; } ;;
            4)  { AppMode='delsub'; } ;;
            5)  {   echo -e "\nDo you want to see all CIDRs for every VPC in the deployment or just a specific VPC?" 
                    read -rp "Enter '[a]ll' for all or '[v]pc' for a specific network: $(echo -e "${RED}->>${NC} ")" list_choice
                    if [[ -n $(grep -Pio '(^[Aall]+$)' <<< "$list_choice") ]]; then { ListAllMode=true && NetidSet=true; }
                    elif [[ -n $(grep -Pio '(^[vVpc]+$)' <<< "$list_choice") ]]; then { ListAllMode=false; }
                    else
                        echo -e "${RED}ERROR${NC} Invalid list choice:[${YEL}$list_choice${NC}] entered. Exiting." | tee >(_dee_)
                        clean_exit 2
                    fi
                    AppMode='makelist'; 
                } ;;
            6)  { echo -e "\n${MAG}Exiting script and cleaning up artefacts...${NC}" | tee >(_dee_); clean_exit 0; } ;;
        esac
    fi
    debug_on
}
function file_input_submenu () {
    debug_off
    readarray -t files <<< "$(ls -Qp | grep -v '/$')"
    local prompt="Please select an input list file --->>>  "
    if (( $(tput cols) >= 120 )); then
        local -i col1=$(( MenuW * 7/100 ))
        local -i col2=$(( MenuW * 43/100 ))
        local -i col3=$(( MenuW * 7/100 ))
        local -i col4=$(( MenuW * 43/100 ))
        local -i n=0
        echo -e "+$(segm $MenuW)+"
        printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "FILE INPUT MENU"
        echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+$(segm $col4)+\n"
        for (( i=0; i<${#files[@]}; i+=2 )); do
            local -i left=$(( (2*n)+1 )) # odd
            local -i right=$(( 2*(n+1) )) # even
            printf "|%-${col1}s|%-${col2}s|%-${col3}s|%-${col4}s|\n" "$left" "${files[$i]::$col2}" "$right" "${files[$((i+1))]::$col4}"  
            echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+$(segm $col4)+\n"
            n=$((n+1))
        done
    else
        local -i col1=$(( MenuW * 20/100 ))
        local -i col2=$(( MenuW * 80/100 ))
        echo -e "+$(segm $MenuW)+"
        printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "FILE INPUT MENU"
        echo -en "+$(segm $col1)+$(segm $col2)+\n"
        for (( i=0; i<${#files[@]}; i++ )); do
            printf "|%-${col1}s|%-${col2}s|\n" "$((i+1))" "${files[$i]}"   
            echo -en "+$(segm $col1)+$(segm $col2)+\n"
        done
    fi
    read -rp "$prompt " index
    local inputFile="${files[$((index-1))]}"
    local delmode=false 
    inputFile="${inputFile//\"/}"
    echo -e "${CYA}INFO${NC} file path chosen from list:[${YEL}${inputFile}${NC}] at:[${YEL}$index${NC}]"
    rmcr "$inputFile"
    local -a input_list
    if (( $(wc -l < "$inputFile") >= 1 )); then 
        readarray -t Templist <<< "$(<"$inputFile")"
        for line in "${Templist[@]}"; do
            if [[ "$AppMode" =~ 'add' ]]; then
                if [[ -n "$(grep -Po $_CIDR_REGEX <<< "$line")" ]]; then
                    input_list+=( "$line" )
                elif [[ -z "$(grep -Po $_CIDR_REGEX <<< "$line")" ]]; then     # we didnt get a CIDR
                    IFS=$Delim read -r cidr name <<< "$line"                   # lets try to break it up by the delimiter
                    UseAutoNaming=false                                        # either we have a name or we are about to start autonaming so turn it off
                    if [[ -n "$(grep -Po $_CIDR_REGEX <<< "$cidr")" ]] && [[ -n "$name" ]]; then   # if we got a cidr and a name                                                          
                        input_list+=( "$cidr,$name" )
                    elif [[ -n "$(grep -Po $_CIDR_REGEX <<< "$cidr")" ]]; then
                        UseAutoNaming=false                                         
                        input_list+=( "$cidr,${name:-AutoName-${cidr//./-}}" )    
                    else
                        echo -e "${RED}ERROR${NC} Name was entered:[${YEL}$name${NC}] but CIDR was not valid:[${YEL}$line${NC}]." | tee >(_dee_)
                    fi
                fi
            elif [[ "$AppMode" =~ 'del' ]]; then
                delmode=true
                if [[ -n "$(grep -Po $_PATT_REGEX <<< "$line")" ]]; then
                    delete_check "$param_input" 
                elif [[ -n "$(grep -Po $_CIDR_REGEX <<< "$line")" ]]; then
                    input_list+=( "$param_input" )
                fi
            fi
        done
        echo -e "\n${CYA}INFO${NC} Found the following CIDRs in file:" | tee >(_dee_)
        if $delmode; then
            delete_check '-' "${input_list[@]}"
            (( ${#DeleteTargetList[@]} >= 1 )) && echo -e "Deletion list was loaded. [${YEL}${#DeleteTargetList[@]}${NC}] targets were added to list." | tee >(_dee_)
        else
            AddTargetList=( "${input_list[@]}" )
            echo -e "Addition list was loaded. [${YEL}${#AddTargetList[@]}${NC}] targets were added to list." | tee >(_dee_)
            if ! $UseAutoNaming && (( ${#input_list[@]} >= 1 )); then
                display_cidr_param_table "${AddTargetList[@]}"
            elif (( ${#input_list[@]} >= 1 )); then
                display_cidr_table "${AddTargetList[@]}"
            fi
        fi
    else
        echo -e "${RED}ERROR${NC} Input file was empty or not found:[${YEL}$(wc -l < "$inputFile")${NC}]. Exiting." | tee >(_dee_)
        exit 1
    fi 
}
function confirm_menu () {
    debug_off
    local mode_type="$1"
    echo; echo -e "\n\n"
    echo -e "+$(segm $MenuW)+"
    printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "FINAL CONFIRMATION MENU"
    echo -e "+$(segm $MenuW)+"
    echo -e "\n\n"
    if [[  $mode_type =~ 'add'  ]]; then 
        echo -e "${CYA}INFO${NC} You are about to ADD the following VPCs/Networks/Subnets to deployment:[${YEL}$DeploymentName${NC}] with ID:[${YEL}$DeploymentId${NC}]:"
        if ! $UseAutoNaming; then 
            display_cidr_param_table "${AddTargetList[@]}"
        else
            display_cidr_table "${AddTargetList[@]}"
        fi
    elif [[  $mode_type =~ 'del'  ]]; then
        echo -e "${CYA}INFO${NC} You are about to DELETE the following VPCs/Networks from deployment:[${YEL}$DeploymentName${NC}] with ID:[${YEL}$DeploymentId${NC}]:"
        display_cidr_param_table "${DeleteTargetList[@]}"
    fi
    if ! $TestRun; then 
        echo -e "${MAG}WARNING!! YOU ARE ABOUT TO MAKE CHANGES TO A LIVE CUSTOMER'S PROD ACCOUNT!${NC}"
    elif $TestRun; then
        echo -e "${YEL}NOTE${NC} YOU ARE NOT ABOUT TO MAKE ANY CHANGES TO ANY LIVE ACCOUNTS. YOU ARE STILL IN TEST RUN MODE."
    fi
    echo -e "ARE YOU SURE YOU WANT TO CONTINUE?"
    read -rp $'\n'"Type the word $(echo -e ${YEL}CONFIRM${NC}) to continue and then press ENTER (or type \"no\" to cancel): " confirmed  
    if [[ "${confirmed^^}" == "CONFIRM" ]]; then
        echo -e "${CYA}INFO${NC} Confirmation received; proceeding with the operation..." | tee >(_dee_)
        case "$mode_type" in 
            'addvpc' )      { make_vpcs "$DeploymentId" "${AddTargetList[@]}"; } ;;
            'delvpc' )      {
                for line in "${DeleteTargetList[@]}"; do
                    IFS=, read -r cidr vpcuuid <<< "$line"
                    delete_vpc "$cidr" "$vpcuuid" && echo -e "${CYA}INFO${NC} Successfully deleted VPC with CIDR:[${YEL}$cidr${NC}] and UUID:[${YEL}$vpcuuid${NC}] from deployment:[${YEL}$DeploymentName${NC}]." | tee >(_dee_)
                done 
                } ;;
            'addsub' )      { make_subnets "$DeploymentId" "$NetworkId" "${AddTargetList[@]}"; } ;;
            'delsub' )      { 
                for line in "${DeleteTargetList[@]}"; do
                    IFS=, read -r cidr subuuid <<< "$line"
                    delete_subnet "$cidr" "$subuuid" && echo -e "${CYA}INFO${NC} Successfully deleted Subnet with CIDR:[${YEL}$cidr${NC}] and UUID:[${YEL}$subuuid${NC}] from VPC/Network:[${YEL}$NetworkName${NC}] in deployment:[${YEL}$DeploymentName${NC}]." | tee >(_dee_)
                done
                } ;;
            *)  { echo -e "${RED}ERROR${NC} confirm_menu failed; invalid mode_type:[${YEL}$mode_type${NC}] passed to function." | tee >(_dee_); } ;;
        esac
    elif [[ "${confirmed^^}" == 'NO' ]]; then
        echo -e "${YEL}NOTE${NC} Operation cancelled by user; returning to main menu." | tee >(_dee_)
        clean_exit 0
    else
        echo -e "${RED}ERROR${NC} You must type out the word 'confirm' to proceed." | tee >(_dee_)
        confirm_menu "$mode_type"
    fi
    debug_on            
}
function manual_add_cidr_input () {
    debug_on
    echo -e "\n${CYA}INFO${NC} Please enter a list of CIDRs one per line. When you are done, type 'QUIT' or 'Q' on a new line and press ENTER."
    local -a input_list=()
    local cidr_input
    while true; do
        read -rp "> " cidr_input
        if [[ "${cidr_input^^}" == "QUIT" ]] || [[ "${cidr_input^^}" == "Q" ]]; then
            break
        elif ! $UseAutoNaming && [[ -n "$(grep -Po $_CIDR_REGEX <<< "$cidr_input")" ]]; then
            input_list+=( "$cidr_input" )
        elif [[ ! -n "$(grep -Po $_CIDR_REGEX <<< "$cidr_input")" ]]; then
            IFS=, read -r cidr name <<< "$cidr_input"
            if [[ -n "$name" ]] && [[ -n "$(grep -Po $_CIDR_REGEX <<< "$cidr")" ]]; then
                UseAutoNaming=false
                input_list+=( "$cidr_input" )
            else
                echo -e "${RED}ERROR${NC} Name was entered:[${YEL}$name${NC}] but CIDR was not valid:[${YEL}$cidr_input${NC}]." | tee >(_dee_)
                echo -e "${YEL}NOTE${NC} Make sure the CIDR and name are separated by a comma and use enclosing quotes if your name contains spaces.\nFor example: 192.168.0.0/24,\"My Network Name\""
            fi
        else
            echo -e "${RED}ERROR${NC} Invalid CIDR was entered:[${YEL}$cidr_input${NC}]. Please try again." | tee >(_dee_)
        fi
    done
    if (( ${#input_list[@]} == 0 )); then
        echo -e "${RED}ERROR${NC} No CIDRs were entered. Exiting." | tee >(_dee_)
        clean_exit 2
    else
        echo -e "\n${CYA}INFO${NC} Found the following CIDRs:" | tee >(_dee_)
        if ! $UseAutoNaming; then { display_cidr_param_table "${input_list[@]}"; }
        else { display_cidr_table "${input_list[@]}"; }
        fi
        AddTargetList=( "${input_list[@]}" )
    fi
    debug_off
}
function manual_delete_input () {
    debug_on
    echo -e "\n${CYA}INFO${NC} Please enter a list of CIDRs or patterns one per line. When you are done, type 'QUIT' or 'Q' on a new line and press ENTER."
    local -a input_list pattern_list
    local param_input
    while true; do
        read -rp "> " param_input
        if [[ "${param_input^^}" == "QUIT" ]] || [[ "${param_input^^}" == "Q" ]]; then
            break
        elif [[ -n "$(grep -Po $_PATT_REGEX <<< "$param_input")" ]]; then
            delete_check "$param_input" 
        elif [[ -n "$(grep -Po $_CIDR_REGEX <<< "$param_input")" ]]; then
            input_list+=( "$param_input" )
        else
            echo -e "${RED}ERROR${NC} Invalid CIDR or pattern was entered:[${YEL}$param_input${NC}]. Please try again." | tee >(_dee_)
        fi
    done
    if (( ${#input_list[@]} == 0 )) && (( ${#DeleteTargetList[@]} == 0 )); then
        echo -e "${RED}ERROR${NC} No CIDRs or patterns were entered. Exiting." | tee >(_dee_)
        clean_exit 2
    else
        echo -e "\n${CYA}INFO${NC} Found the following CIDRs/patterns:" | tee >(_dee_)
        delete_check '-' "${input_list[@]}"
        (( ${#DeleteTargetList[@]} >= 1 )) && echo -e "Deletion list was loaded. [${YEL}${#DeleteTargetList[@]}${NC} were added to list." | tee >(_dee_)
    fi
    debug_off
}
function single_large_input () {
    debug_off
    read -rp $'\n'"Enter the large (no larger than /16) CIDR range to segment: " large_cidr   
    if [[ -z "$(grep -Po $_CIDR_REGEX <<< "$large_cidr")" ]]; then
        echo -e "${RED}ERROR${NC} Invalid CIDR was entered:[${YEL}$large_cidr${NC}]. Exiting." | tee >(_dee_)
        clean_exit 2
    fi
    read -rp $'\n'"Enter the segment size prefix (e.g., 24  for /24 subnets): " segment_size
    if [[ -z "$(grep -Po '^(1[6-9]|2[0-9]|3[0-2]|[2-9])$' <<< "$segment_size")" ]]; then
        echo -e "${RED}ERROR${NC} Invalid segment size prefix was entered:[${YEL}$segment_size${NC}]. Exiting." | tee >(_dee_)
        clean_exit 2
    fi
    debug_on
    echo -e "\n${CYA}INFO${NC} Generating smaller CIDRs from large CIDR:[${YEL}$large_cidr${NC}] with segment size prefix:[${YEL}/$segment_size${NC}]..." | tee >(_dee_)
    readarray -t generated_cidrs <<< "$(convert_large_cidr_to_subnets "$large_cidr" $segment_size)"
    if (( ${#generated_cidrs[@]} == 0 )); then
        echo -e "${RED}ERROR${NC} No CIDRs were generated from large CIDR:[${YEL}$large_cidr${NC}] with segment size prefix:[${YEL}/$segment_size${NC}]. Exiting." | tee >(_dee_)
        clean_exit 2
    else
        AddTargetList=( "${generated_cidrs[@]}" )
    fi
    debug_off
}
function add_targets_menu () {
    debug_off
    local -i col1=$(( MenuW * 5/100))
    local -i col2=$(( MenuW * 95/100))
    local -a action_options=(
        '1: Enter a list of CIDRs manually at an interactive prompt. Useful for copy/pasting lists less than 255 lines.'
        '2: Enter a list of CIDRs via an input file. Useful for large lists with varying CIDR patterns and complex names.'
        '3: Enter a large CIDR range and a segment-size to auto-generate smaller CIDRs. For example, convert a /20 into multiple /24s, etc.'
        '4: Exit script'
    )
    echo -e "+$(segm $MenuW)+"
    printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "ADD TARGETS MENU"
    echo -en "+$(segm $col1)+$(segm $col2)+\n"
    printf "|%-${col1}s|%-${col2}s|\n" "Option" "Description"
    echo -en "+$(segm $col1)+$(segm $col2)+\n"
    for option in "${action_options[@]}"; do
        IFS=: read -r opt desc <<< "$option"
        printf "|%-${col1}s|%-${col2}s|\n" "$opt" "$desc"
        echo -en "+$(segm $col1)+$(segm $col2)+\n"
    done
    read -rp $'\n'"Select an input option (1-4): $(echo -e "${RED}->>${NC} ")" input_option
    if [[ ! "$input_option" =~ $_NUM_ONLY_REGEX ]] || (( input_option < 1 || input_option > 4 )); then
        echo -e "${RED}ERROR${NC} Invalid action option:[${YEL}$input_option${NC}] was selected. Exiting." | tee >(_dee_)
        clean_exit 2
    else
        case "$input_option" in
            1)  { manual_add_cidr_input; } ;;
            2)  { file_input_submenu; } ;;
            3)  { single_large_input; } ;;
            4)  { echo -e "\n${MAG}Exiting script and cleaning up artefacts...${NC}" | tee >(_dee_); clean_exit 0; } ;;
        esac
    fi
    debug_on
}
function delete_targets_menu () {
    debug_off
    local -i col1=$(( MenuW * 10/100))
    local -i col2=$(( MenuW * 90/100))
    local -a action_options=(
        '1, Enter a list of CIDRs or patterns manually at an interactive prompt. Useful for copy/pasting lists less than 100 lines.'
        '2, Enter a list of CIDRs or patterns via an input file. Useful for large lists with varying CIDR ranges and sizes.'
        '3, Exit script'
    )
    echo -e "+$(segm $MenuW)+"
    printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "DELETE TARGETS MENU"
    echo -en "+$(segm $col1)+$(segm $col2)+\n"
    printf "|%-${col1}s|%-${col2}s|\n" "Option" "Description"
    echo -en "+$(segm $col1)+$(segm $col2)+\n"
    for option in "${action_options[@]}"; do
        IFS=, read -r opt desc <<< "$option"
        printf "|%-${col1}s|%-${col2}s|\n" "$opt" "$desc"
        echo -en "+$(segm $col1)+$(segm $col2)+\n"
    done
    read -rp $'\n'"Select an input option (1-3): $(echo -e "${RED}->>${NC} ")" input_option
    if [[ ! "$input_option" =~ $_NUM_ONLY_REGEX ]] || (( input_option < 1 || input_option > 3 )); then
        echo -e "${RED}ERROR${NC} Invalid action option:[${YEL}$input_option${NC}] was selected. Exiting." | tee >(_dee_)
        clean_exit 2
    else
        case "$input_option" in
            1)  { manual_delete_input; } ;;
            2)  { file_input_submenu; } ;;
            3)  { echo -e "\n${MAG}Exiting script and cleaning up artefacts...${NC}" | tee >(_dee_); clean_exit 0; } ;;
        esac
    fi
    debug_on
}
function make_list_menu () {
    debug_on
    local -a detlist
    local outcsv
    echo -e "\nYou may output the list in a terminal table, CSV in the terminal or CSV output to a file." 
    read -rp "Enter '[t]able', [c]sv or CSV output to '[f]ile': $(echo -e "${RED}->>${NC} ")" list_choice
    if [[ -n $(grep -Pio '(^[tT]+[aAbBlLeE]*$)' <<< "$list_choice") ]]; then { ListMode=table; }
    elif [[ -n $(grep -Pio '(^[fF]+[iIlLeE]*$)' <<< "$list_choice") ]]; then
        outcsv="${Cid}.$(tr -d '\n' <<< "${DeploymentName// /_}").subnets.$(date +%Y%m%d).csv"
        ListMode=file
    elif [[ -n $(grep -Pio '(^[cC]+[sSvV]*$)' <<< "$list_choice") ]]; then { ListMode=csvt; }
    else
        echo -e "${RED}ERROR${NC} Invalid list choice:[${YEL}$list_choice${NC}] entered. Default TABLE setting will be used."
        ListMode=table 
    fi
    echo -e "\n${CYA}INFO${NC} Generating VPC and Subnet list for deployment:[${YEL}$DeploymentName${NC}] with ID:[${YEL}$DeploymentId${NC}]..." | tee >(_dee_)
    if $NetidSet && ! $ListAllMode; then
        local -a sublist
        echo -e "${CYA}INFO${NC} Filtering output for VPC/Network"
        if [[ -n $(grep -Pio $_UUID_REGEX <<< "$NetworkId") ]]; then { readarray -t sublist < <(list_subnets_by_vpc_uuid "$DeploymentId" "$NetworkId"); } fi
        echo -e "\n${CYA}INFO${NC} VPC/Network:[${YEL}$NetworkName${NC}] with ID:[${YEL}$NetworkId${NC}] has [${YEL}${#sublist[@]}${NC}] non-default subnets." | tee >(_dee_)
        for subnet in "${sublist[@]}"; do
            detlist+=( "$NetworkName,$NetworkId,$NetworkKey,$subnet" )
        done
    elif $ListAllMode; then
        local -a netlist
        echo -e "${CYA}INFO${NC} Listing all VPCs/Networks and their subnets for deployment:[${YEL}$DeploymentName${NC}] with ID:[${YEL}$DeploymentId${NC}]..." | tee >(_dee_) 
        readarray -t netlist < <(list_networks "$DeploymentId")
        for net in "${netlist[@]}"; do
            local -a sublist
            IFS=, read -r netname netuuid netkey <<< "$net"
            readarray -t sublist < <(list_subnets_by_vpc_uuid "$DeploymentId" "$netuuid")  
            if (( ${#sublist[@]} == 0 )); then
                echo -e "${YEL}WARNING${NC} No subnets found for VPC/Network:[${YEL}$netname${NC}] with ID:[${YEL}$netuuid${NC}]" | tee >(_dee_)
            else
                echo -e "\n${CYA}INFO${NC} VPC/Network:[${YEL}$netname${NC}] with ID:[${YEL}$netuuid${NC}] has [${YEL}${#sublist[@]}${NC}] non-default subnets." | tee >(_dee_)
                for subnet in "${sublist[@]}"; do
                    detlist+=( "$netname,$netuuid,$netkey,$subnet" )
                done
            fi
        done
    else 
        echo -e "${RED}ERROR${NC} Cannot make list; Network ID:[${YEL}$NetworkId${NC}] is not set or invalid. Exiting." | tee >(_dee_)
        clean_exit 2
    fi
    debug_off
    if [[ "$ListMode" == 'csvt' ]]; then 
        echo -e "VPC Name,VPC ID,VPC Key,Subnet Name,Subnet ID,Subnet Key,CIDR"
        for item in "${detlist[@]}"; do { echo -e "${item}"; } done
    elif [[ "$ListMode" == 'file' ]]; then
        echo -e "VPC Name,VPC ID,VPC Key,Subnet Name,Subnet ID,Subnet Key,CIDR"
        for item in "${detlist[@]}"; do { echo -e "${item}" | tee -a "$outcsv"; } done
        echo "Output CSV file can be found at:[$(realpath $outcsv)]"
    else
        local -i col1=$(( MenuW * 29/100))
        local -i col2=$(( MenuW * 29/100))
        local -i col3=$(( MenuW * 28/100))
        local -i col4=$(( MenuW * 14/100))
        echo -e "+$(segm $MenuW)-+"
        printf "|${BLU}%${Mid}s ${NC}%${Rt}s|\n" "ALL SUBNETS DISPLAY"
        echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+$(segm $col4)+\n"
        for line in "${detlist[@]}"; do
            IFS=, read -r vname vd vk sname sid sk cidr <<< "$line"
            printf "|%-${col1}s|%-${col2}s|%-${col3}s|%-${col4}s|\n" "${vname::$col1}" "${sname::$col2}" "${sid::$col3}" "${cidr::$col4}"  
            echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+$(segm $col4)+\n"
        done
    fi    
}
function display_cidr_table () {
    debug_off
    local -a cidrs=( "$@" )
    local -i col1=$(( MenuW * 25/100))
    local -i col2=$(( MenuW * 25/100))
    local -i col3=$(( MenuW * 25/100))
    local -i col4=$(( MenuW * 25/100))
    if (( ${#cidrs[@]} >= 1 )); then
        echo -e "+$(segm $MenuW)+"
        printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "CIDR TABLE DISPLAY"
        echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+$(segm $col4)+\n"
        for (( i=0; i<${#cidrs[@]}; i+=4 )); do
            printf "|%-${col1}s|%-${col2}s|%-${col3}s|%-${col4}s|\n" "${cidrs[$i]::$col1}" "${cidrs[$((i+1))]::$col2}" "${cidrs[$((i+2))]::$col3}" "${cidrs[$((i+3))]::$col4}"  
            echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+$(segm $col4)+\n"
        done
    else
        return 0
    fi
    debug_on
}
function display_cidr_param_table () {
    debug_off
    local -a cidrs=( "$@" )
    local -i col1=$(( MenuW * 30/100))
    local -i col2=$(( MenuW * 70/100))
    if (( ${#cidrs[@]} >= 1 )); then
        echo -e "+$(segm $MenuW)+"
        printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "CIDR TABLE AND NAME DISPLAY"
        echo -en "+$(segm $col1)+$(segm $col2)+\n"
        for line in "${cidrs[@]}"; do
            IFS=, read -r cidr param <<< "$line"
            printf "|%-${col1}s|%-${col2}s|\n" "${cidr::$col1}" "${param::$col2}"
            echo -en "+$(segm $col1)+$(segm $col2)+\n"
        done
    else
        return 0
    fi
    debug_on
}
###########################################################################################
#                            MENU CONTROL FUNCTIONS                                       #
###########################################################################################
function clean_exit () {
    local -i excode=${1:-0}
    unset Cid CustomerName CloudInsightUrl DeploymentId DeploymentName NetworkName NetworkId NetworkKey Head InputFile AppMode
    unset CidSet DepidSet FileSet CidrSet TargetSet NetidSet TestRun Debug PatternSet Delim CidValid SpanEnabled
    unset AddTargetList DeleteTargetList _IsTopoCurrent CurrentTopology Today dset cset UseAutoNaming segset
    if (( excode != 0 )); then { echo -e "${MAG}FATAL${NC} script exited with abnormal status or fail code:[${YEL}${excode}${NC}]" | tee >(_dee_); exit 1; }
    else  { echo -e "\nCleanup finished.\n${MAG}Goodbye!${NC}"; exit 0; }   
    fi
}
# Get a validated binary T/F input from user and a command to run. If the input was validated, dont run the command
# but if the input was validated by some external function, run the command.
function _runmode_ () {
    local validated="$1"
    shift
    local cmd=$(tr -dc '[:alnum:][=_=][= =]' <<< "$*")
    if [[ -z "$cmd" ]]; then
        echo -e "${RED}ERROR${NC} Function or command:[${YEL}$cmd${NC}] was not found. Exiting." | tee >(_dee_)
        exit 1
    fi
    if [[ $validated == true ]]; then
        echo -e "${YEL}NOTE${NC} Condition was validated; skipping function:[${YEL}$cmd${NC}]" | tee >(_dee_)
    else # if any random crap was input, still run the function
        "$cmd"
    fi
}
###########################################################################################
#                            PARSE COMMAND LINE OPTIONS                                   #
###########################################################################################
declare -i postat opterr
declare parsed_opts dset=false cset=false
[[ $# -eq 0 ]] && { echo -e "WARNING - No input parameters [$#] were found on stdin. Running with default settings." | tee >(_dee_); }
getopt -T > /dev/null; opterr=$?  # check for enhanced getopt version
if (( $opterr == 4 )); then  # we got enhanced getopt
    declare Long_Opts=cid:,cidr:,deployment-id:,network-id:,network-key:,make-list:,list:,segment:,pattern:,add-networks,remove-networks,add-subnets,remove-subnets,delimiter:,input-file:,file:,testrun,debug,help 
    declare Opts=c:i:n:k:r:s:p:f:l:d:aumotbh
    ! parsed_opts=$(getopt --longoptions "$Long_Opts" --options "$Opts" -- "$@") # load and parse options using enhanced getopt
    postat=${PIPESTATUS[0]}
else 
    ! parsed_opts=$(getopt c:i:n:k:r:s:p:f:l:d:aumotbh "$@") # load and parse avail options using original getopt
    postat=${PIPESTATUS[0]}
fi
if (( $postat != 0 )) || (( $opterr != 4 && $opterr != 0 )); then # check return and pipestatus for errors
    echo -e "ERROR - invalid option was entered:[$*] or missing required arg." | tee >(_dee_)
    infra_script_usage
    exit 1 
else 
    eval set -- "$parsed_opts"  # convert positional params to parsed options ('--' tells shell to ignore args for 'set')
    while true; do 
        case "${1,,}" in
            -c|--cid )                  { { [[ -n "$2" ]] && Cid="$2"; cset=true; }; shift 2; } ;;
            -i|--deployment-id )        { { [[ "$2" =~ $_UUID_REGEX ]] && DeploymentId="$2"; depset=true; }; shift 2; } ;;
            -n|--network-id )           { { [[ "$2" =~ $_UUID_REGEX ]] && NetworkId="$2"; netset=true; }; shift 2; } ;;
            -k|--network-key )          { { [[ "$2" =~ $_DC_VPCKEY_REGEX ]] && NetworkKey="$2"; keyset=true; }; shift 2; } ;;
            -r|--cidr )                 { { [[ -n $(grep -Pio $_CIDR_REGEX <<< "$2" ) ]] && Cidr="$2"; CidrSet=true; }; shift 2; } ;;
            -s|--segment )              { { [[ "$2" =~ $_NUM_ONLY_REGEX ]] && Segment="$2" && segset=true; }; shift 2; } ;;
            -p|--pattern )              { { [[ -n "$2" ]] && Pattern="$2"; PatternSet=true; }; shift 2; } ;;
            -f|--input-file )           { { [[ -f "$2" ]] && InputFile=$(realpath "$2"); FileSet=true; }; shift 2; } ;;
            -l|--make-list )            { { [[ -n "$2" ]] && ListMode="$2"; AppMode='makelist' && ModeSet=true; }; shift 2; } ;;
            -d|--deilimiter )           { { [[ -n "$2" ]] && Delim="$2"; }; shift 2; } ;;
            -a|--add-networks )         { AppMode='addvpc' && ModeSet=true; shift; } ;;
            -u|--remove-networks )      { AppMode='delvpc' && ModeSet=true; shift; } ;;
            -m|--add-subnets )          { AppMode='addsub' && ModeSet=true; shift; } ;;
            -o|--remove-subnets )       { AppMode='delsub' && ModeSet=true; shift; } ;;
            -t|--testrun )              { TestRun=true; shift; } ;;
            -b|--debug )                { Debug=true; shift; } ;;
            -h|--help )                 { infra_script_usage; shift && exit 0; } ;;
            --) shift; break ;;  # end of options            
        esac
    done
fi
if $TestRun; then { echo -e "${YEL}NOTE${NC} test run mode enabled; no changes will be made." | tee >(_dee_); } fi
Head="x-aims-auth-token: ${auth_token}"
if $cset && [[ $Cid =~ $_NUM_ONLY_REGEX ]]; then
    CustomerName=$(cid_exists "$Cid" | tr -d $'\n')
    if [[ -n "$CustomerName" ]]; then
        get_cloudinsight_url "$Cid"
        CidSet=true
    else
        echo -e "${YEL}WARNING${NC} the CID entered at the command-line could not be validated.\nYou will be prompted to enter it."| tee >(_dee_)
        CidSet=false
    fi
fi
if $CidSet && $depset; then 
    DeploymentName=$(validate_deployment "$DeploymentId")
    if [[ -n "$DeploymentName" ]]; then
        refresh_deployment_topology && DepidSet=true
    else { DepidSet=false; } 
    fi
fi
if $DepidSet && $netset; then { NetidSet=$(vpc_exists_by_uuid "$DeploymentId" "$NetworkId"); } fi
if $DepidSet && $keyset; then 
    NetworkId=$(jq -r '.topology.data[] | select (.type=="vpc")? | select (.key=="'"$NetworkKey"'")? | .network_uuid' <<< "$CurrentTopology")
    if [[ "$NetworkId" =~ $_UUID_REGEX ]]; then { NetidSet=true; } else { NetidSet=false; } fi
fi
if $segset && $CidrSet; then { LargeCidrMode=true; } fi
if { $CidrSet || $FileSet || $PatternSet || $LargeCidrMode; } then { TargetSet=true; } fi
# NON-INTERACTIVE ADD/REMOVE VPC MODE
if [[ "$AppMode" == 'addvpc' ]] && $DepidSet && $TargetSet; then
    # this is enough info to proceed non-interactively using default Settings to modify VPCs
    echo -e "${CYA}INFO${NC} all required parameters were set to add VPCs (no VPC idenitifier for subnets was entered)." | tee >(_dee_)
    echo -e "Proceeding non-interactively..." 
    if $CidrSet; then { AddTargetList+=( "$Cidr" ); }
    elif $FileSet; then
        rmcr "$InputFile" && readarray -t AddTargetList <<< "$(<"$InputFile")"
    elif $LargeCidrMode; then
        readarray -t AddTargetList <<< "$(convert_large_cidr_to_subnets "$Cidr" $Segment)"
        if (( ${#AddTargetList[@]} == 0 )); then
            echo -e "${RED}ERROR${NC} No CIDRs were generated from large CIDR:[${YEL}$Cidr${NC}] with segment size prefix:[${YEL}/$Segment${NC}]. Exiting." | tee >(_dee_)
            clean_exit 2
        else
            echo -e "\n${CYA}INFO${NC} Generated the following CIDRs from large CIDR:[${YEL}$Cidr${NC}] with segment size prefix:[${YEL}/$Segment${NC}]:" | tee >(_dee_)
            display_cidr_table "${AddTargetList[@]}"
        fi
    fi
    confirm_menu "$AppMode" 
elif [[ "$AppMode" == 'delvpc' ]] && $DepidSet && $TargetSet; then
    echo -e "${CYA}INFO${NC} all required parameters were set to delete VPCs (no VPC idenitifier for subnets was entered)." | tee >(_dee_)
    echo -e "Proceeding non-interactively..." 
    if $CidrSet; then
        delete_check '-' "$Cidr"
    elif $FileSet; then
        rmcr "$InputFile" && readarray -t tmplist <<< "$(<"$InputFile")"
        delete_check '-' "${tmplist[@]}"
    elif $PatternSet; then
        delete_check "$Pattern"
    fi
    confirm_menu "$AppMode"
# NON-INTERACTIVE ADD SUBNET MODE
elif [[ "$AppMode" == 'addsub' ]] && $NetidSet && $TargetSet; then
    # this is enough info to proceed non-interactively using default Settings to modify SUBNETs
    echo -e "${CYA}INFO${NC} all required parameters were set for add/remove SUBNET mode." | tee >(_dee_)
    echo -e "Proceeding non-interactively..."
    if $CidrSet && ! $segset; then { AddTargetList+=( "$Cidr" ); }
    elif $FileSet; then
        rmcr "$InputFile" && readarray -t AddTargetList <<< "$(<"$InputFile")"
    elif $LargeCidrMode; then
        readarray -t AddTargetList <<< "$(convert_large_cidr_to_subnets "$Cidr" $Segment)"
        if (( ${#AddTargetList[@]} == 0 )); then
            echo -e "${RED}ERROR${NC} No CIDRs were generated from large CIDR:[${YEL}$Cidr${NC}] with segment size prefix:[${YEL}/$Segment${NC}]. Exiting." | tee >(_dee_)
            clean_exit 2
        else
            echo -e "\n${CYA}INFO${NC} Generated [${YEL}${#AddTargetList[@]}${NC}] small CIDRs from large CIDR:[${YEL}$Cidr${NC}] with segment size prefix:[${YEL}/$Segment${NC}]:" | tee >(_dee_)
            display_cidr_table "${AddTargetList[@]}"
        fi
    fi   
    confirm_menu "$AppMode"
# NON-INTERACTIVE LIST MODE
elif $CidSet && $DepidSet && [[ "$AppMode" == 'makelist' ]]; then
    echo -e "${CYA}INFO${NC} all required parameters were set for non-interactive LIST mode." | tee >(_dee_)
    if $NetidSet; then { make_list_menu "$NetworkId"; } 
    else { make_list_menu; }
    fi
# INTERACTIVE MODES
else    # proceed with interactive prompts to gather required info
    echo -e "${YEL}WARNING${NC} not all required parameters were set; proceeding with interactive prompts to gather required info..." | tee >(_dee_)
    main_menu
    case "$AppMode" in
        'addvpc') {
            _runmode_ $CidSet get_cid_menu
            _runmode_ $DepidSet get_deployment_menu
            _runmode_ $TargetSet add_targets_menu
            confirm_menu "$AppMode"
        } ;;
        'delvpc') {
            _runmode_ $CidSet get_cid_menu
            _runmode_ $DepidSet get_deployment_menu
            _runmode_ $TargetSet delete_targets_menu
            confirm_menu "$AppMode"
        } ;;
        'addsub') {
            _runmode_ $CidSet get_cid_menu
            _runmode_ $DepidSet get_deployment_menu
            _runmode_ $NetidSet get_vpc_menu
            _runmode_ $TargetSet add_targets_menu
            confirm_menu "$AppMode"
        } ;;
        'delsub') {
            _runmode_ $CidSet get_cid_menu
            _runmode_ $DepidSet get_deployment_menu
            _runmode_ $NetidSet get_vpc_menu
            _runmode_ $TargetSet delete_targets_menu
            confirm_menu "$AppMode"
        } ;;
        'makelist') {
            _runmode_ $CidSet get_cid_menu
            _runmode_ $DepidSet get_deployment_menu
            _runmode_ $NetidSet get_vpc_menu
            make_list_menu
        } ;;
    esac   
fi
