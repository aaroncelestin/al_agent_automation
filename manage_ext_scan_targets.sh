#!/usr/bin/bash
# shellcheck disable=SC2155,SC2119,SC2004,SC2053,SC2027,SC2086,SC2120,SC2091,SC2001,SC2184
# Author: aaron.celestin@fortra.com
declare Version='0.96' 
# updated 20240907, removed crappy menu and rebuilt API logic
# updated 20251101, rebuilt menus, added command line switches, added options to disable validation and skip existence-checks, added list options and CIDR support
declare -r NC=$(tput sgr0)
declare -r RED=$(tput setaf 1)
declare -r GRE=$(tput setaf 2)
declare -r YEL=$(tput setaf 3)
declare -r BLU=$(tput setaf 4)
declare -r MAG=$(tput setaf 5)
declare -r CYA=$(tput setaf 6)
declare -r PURP=$'\033[0;95m'
declare _UUID_REGEX='^[0-9a-zA-Z]{8}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{12}$'
declare _NUM_REGEX='^[0-9]+$'
declare _IPV4_REGEX='^\b([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\b\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\b\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\b\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$'
declare _CIDR_REGEX='^\b([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\b\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\b\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\b\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\/[0-9]{1,2}$'
declare _FILENAME_REGEX='[a-zA-Z0-9_\-. ]+'
declare _DIRNAME_REGEX='^\/?[\w\/\-.+:_]+' 
declare _DNS_REGEX='^([a-zA-Z0-9-_~.]{3,128}.[a-zA-Z]{2,4})$'
declare UkUrl="https://api.cloudinsight.alertlogic.co.uk"
declare UsUrl="https://api.cloudinsight.alertlogic.com"
declare -a IPTargets DNSTargets AllTargets IPList DNSList AllList DeletionTargets
declare Cid CustomerName CloudInsightUrl DeploymentId DeploymentName Head InputFile AppMode=''
declare CidSet=false DepidSet=false FileSet=false CidrSet=false TestRun=false CheckExistence=true SkipValidation=false TargetSet=false Debug=false
###########################################################################################
#                            GENERAL UTILITY FUNCTIONS                                    #
###########################################################################################
# quick function to remove MSDOS-style CR line endings from an input file 
function rmcr () { [[ -f "$1" ]] && { perl -i -pe 's/\r//' "$1"; }; }
# Simple function to mark tstamps in log files and backups in case things get borked, format is RFC5424 compliant
function tstamp () { date +%Y-%m-%d-%a-T%H:%M:%S.%Z; }
# short for {SAN}itize
function san () { local msg="${*:-$(</dev/stdin)}"; echo -e "$msg" | sed 's/\"//g' | sed 's/[][]//g'; }
# debug mode switches for logic functions only
function debug_on () { if $Debug; then set -x; fi }
function debug_off () { if $Debug; then set +x; fi }
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
    echo -en "${account_name}" | tr -s '[:space:]'
    debug_off
}
# given Cid, create array of Cids or csv file, depending on input. CSV output is the default 
# run this command like this for array output:
#   readarray child_cid_list < <(list_child_accounts 123456789 array)
# for CSV output, run this instead:
#   cid_csv_filepath=$(list_child_accounts 123456789 csv)
# output for both options will be:
#   "<child account name>","<child account id>"
# each array item will get a full csv formatted line per index
function list_child_accounts () {
    debug_on
    local cid=$1
    local -a children
    local api="https://api.global.alertlogic.com/aims/v1/$cid/accounts/managed?active=true"
    readarray -t children < <(curl -sk -X GET -H "$Head" "$GLOBAPI" | jq -r '.accounts[] | [.id]')
    if [[ ${#children[@]} -eq 0 ]]; then
        echo ""
    elif [[ -n "$cid" ]] && [[ ${#children[@]} -ge 1 ]]; then
        printf '%s' "${children[@]}"
    fi
    unset children cid
    debug_off
}
# 20250213 changed to let JQ 'gsub' dashes ('-') for any commas found in user-given deployment
# 20231114 Had to rewrite these to handle and discard special chars in the names. Using the mop() function above, we pull the lists
# then replace all special chars and whitespace with underscores and then rebuild the list so callers of these functions will be none 
# the wiser. They will now just get cleaner names for deployments, networks and subnets.
# each line in the output should look like this:
# "<deployment name>","<deployment id>"
function list_deployments () {
    debug_on
    local cid=${1:-Cid}
    [[ ! "${cid}" =~ $_NUM_REGEX ]] && { echo -e "${RED}ERROR${NC} list_deployments failed; invalid Cid was entered:[${YEL}${cid}${NC}]."; return 1; }
    local api="$CloudInsightUrl/deployments/v1/$cid/deployments"
    readarray -t deplist < <(curl -sk GET -H "$Head" "$api" | jq -rc '.[] | [(.name|gsub(","; "-")),.id] | @csv') # swap commas with dashes
    (( ${#deplist[@]} >= 1 )) && printf '%s\n' "${deplist[@]}"
    debug_off
}
function validate_deployment () {
    debug_on
    local depid=${1:?"${RED}ERROR${NC} validate_deployment failed; missing input."}
    [[ ! "${Cid}" =~ $_NUM_REGEX ]] && { echo -e "${RED}ERROR${NC} validate_deployment failed; no CID was set before validation:[${YEL}${Cid}${NC}]."; return 1; }
    local api="$CloudInsightUrl/deployments/v1/$Cid/deployments/$depid"
    curl -sk GET -H "$Head" "$api" | jq -rc '(.name|gsub(","; "-"))'
    debug_off
}
###########################################################################################
#                         EXTERNAL SCAN TARGET API FUNCTIONS                              #
###########################################################################################
# given a cid, build an array with a list of external ip assets for the whole cid
# optiopnally given a deployment_id, limit the list to that deployment only
function list_existing_exts () {
    debug_on
    local deployment_id="${1//\"/}"
    local deployment_name="$2"
    if $CidSet && [[ ! "$deployment_id" =~ $_UUID_REGEX ]]; then
        readarray -t deplist < <(list_deployments $Cid)
        unset ext_api
        for deps in "${deplist[@]}"; do    
            IFS=, read -r dname depid <<< "$deps"
            load_extlist_bydep "$Cid" "$depid" "$dname"
        done    
    elif $CidSet && [[ "$deployment_id" =~ $_UUID_REGEX ]]; then
        deployment_id=$(san "$deployment_id")    
        load_extlist_bydep "$Cid" "$deployment_id" "$deployment_name"
    else
        echo -e "${RED}ERROR${NC} list_existing_exts failed; Cid was not set or CidSet was false:[${YEL}$CidSet${NC}]"
        return 7
    fi
    debug_off
}
# given a cid, deploymentid and deployment name, get a list of external IPs and DNS names and put them in global arrays
function load_extlist_bydep () {
    debug_on
    local cid="$1"
    local depid="${2//\"/}"
    local dname="${3// /_}"
    local -a extips extdns  
    local papi="$CloudInsightUrl/assets_query/v1/$cid/deployments/$depid/assets?asset_types=external-ip"
    readarray -t extips < <(curl -s -H "$Head" "$papi" | jq '.assets[][].ip_address')
    local dapi="$CloudInsightUrl/assets_query/v1/$cid/deployments/$depid/assets?asset_types=external-dns-name"
    readarray -t extdns < <(curl -s -H "$Head" "$dapi" | jq '.assets[][].name')
    for ext in "${extips[@]}"; do
        IPList+=( "${ext},${dname//,/;},${depid}" )
    done
    for ext in "${extdns[@]}"; do
        DNSList+=( "${ext},${dname//,/;},${depid}" )
    done    
    for ext in "${extips[@]}" "${extdns[@]}"; do
        AllList+=( "${ext},${dname//,/;},${depid}" )
    done        
    debug_off
}
# given a cid and, optionally, a deployment_id and file with list of ips, remove external ips
function remove_ext_targets () {
    debug_on
    local -a targetlist=( "$@" )
    for line in "${targetlist[@]}"; do 
        IFS=, read -r targ type dname depid <<< "$line"
        local payload api="$CloudInsightUrl/assets_write/v1/$Cid/deployments/$depid/assets"
        if [[ "$type" == 'ip' ]]; then
            local keytarg="/external-ip/$targ" 
            payload="{\"operation\": \"remove_asset\",\"type\":\"external-ip\",\"scope\":\"config\",\"key\":\"$keytarg\"}"
        elif [[ "$type" == 'dns' ]]; then
            local keytarg="/external-dns-name/$targ"
            payload="{\"operation\": \"remove_asset\",\"type\":\"external-dns-name\",\"scope\":\"config\",\"key\":\"$keytarg\"}"
        fi
        if $TestRun && [[ -n "$payload" ]]; then
            echo -e "${MAG}TEST RUN${NC} TESTRUN is enabled; no changes will be made."
            echo -e "${MAG}TEST RUN${NC} API: $CloudInsightUrl/assets_write/v1/$Cid/deployments/$depid/assets"
            echo -e "${MAG}TEST RUN${NC} HEADER: (size-only)${#Head}"
            echo -e "${MAG}TEST RUN${NC} PAYLOAD: $(jq -rc '.' <<< "$payload")"
        elif $Debug; then
            curl -v -X PUT -H "$Head" -d "$payload" "$api" | jq . && {
                echo -e "${GRE}OKAY${NC} external asset:[${YEL}$targ${NC}] was removed successfully from deployment:[${YEL}$dname${NC}]."
                if ! $SkipValidation; then { is_valid_checklist+=( "$targ,$type,$Cid,$depid" ); } fi
            }
            sleep 1s
        else
            curl -sX PUT -H "$Head" -d "$payload" "$api" | jq . && {
                echo -e "${GRE}OKAY${NC} external asset:[${YEL}$targ${NC}] was removed successfully from deployment:[${YEL}$dname${NC}]."
                if ! $SkipValidation; then { is_valid_checklist+=( "$target,$type,$Cid,$depid" ); } fi
            } 
            sleep 1s    
        fi
    done
    if ! $SkipValidation; then
        validate_ext_targets "${is_valid_checklist[@]}"
    fi
    debug_off
}
# given one single target, type, cid and deployment id, add the single target to the deployment
function add_ext_target () {
    debug_on
    local target="$1"
    local type="$2"
    local cid="$3"
    local deployment_id="${4//\"/}"
    local payload
    if [[ "$type" == 'dns' ]]; then
        payload="{\"operation\":\"declare_asset\",\"type\":\"external-dns-name\",\"key\":\"/external-dns-name/$target\",\"scope\":\"config\",\"properties\":{\"name\":\"$target\",\"dns_name\":\"$target\",\"state\":\"new\"}}"
    elif [[ "$type" == 'ips' ]]; then
        payload="{\"type\":\"external-ip\",\"key\":\"/external-ip/$target\",\"operation\":\"declare_asset\",\"scope\":\"config\",\"properties\":{\"ip_address\":\"$target\",\"name\":\"$target\",\"state\":\"new\"}}"
    else { echo -e "${RED}ERROR${NC} add_ext_target failed; invalid target:[${YEL}$target${NC}] or target type:[${YEL}$type${NC}] was input"; unset payload; return 8; }
    fi
    if $TestRun; then
        echo -e "${MAG}TEST RUN${NC} TESTRUN is enabled; no changes will be made."
        echo -e "${MAG}TEST RUN${NC} API: $CloudInsightUrl/assets_write/v1/$cid/deployments/$deployment_id/assets"
        echo -e "${MAG}TEST RUN${NC} HEADER: (size-only)${#Head}"
        echo -e "${MAG}TEST RUN${NC} PAYLOAD: $(jq -rc '.' <<< "$payload")"
    elif ! $TestRun && $Debug; then
        echo -e "${CYA}INFO${NC} add_ext_target running; attempting to add ext target:[${YEL}$target${NC}] of type:[${YEL}$type${NC}] to deployment:[${YEL}$deployment_id${NC}]."
        curl -vX PUT -H "$Head" -d "$payload" "$CloudInsightUrl/assets_write/v1/$cid/deployments/$deployment_id/assets" && {
            echo -e "${GRE}OKAY${NC} external asset:[${YEL}$target${NC}] was successfully added to deployment:[${YEL}$DeploymentName${NC}]."
        }
    elif ! $TestRun; then
        echo -e "${CYA}INFO${NC} add_ext_target running; attempting to add ext target:[${YEL}$target${NC}] of type:[${YEL}$type${NC}] to deployment:[${YEL}$deployment_id${NC}]."
        curl -sX PUT -H "$Head" -d "$payload" "$CloudInsightUrl/assets_write/v1/$cid/deployments/$deployment_id/assets" && {
            echo -e "${GRE}OKAY${NC} external asset:[${YEL}$target${NC}] was successfully added to deployment:[${YEL}$DeploymentName${NC}]."
        }
    fi
    debug_off
}
# Returns the target object JSON in the external scan target list
# If not found, returns valid but empty JSON object: "{"rows":0,"assets":[]}"
function extscan_target_exists () {
    debug_on
    local target="${1//\"/}"
    local type="${2//\"/}"
    local cid=$3
    local deployment_id="${4//\"/}"
    if [[ "$type" == "dns" ]]; then
        api="$CloudInsightUrl/assets_query/v1/$cid/deployments/$deployment_id/assets?asset_types=external-dns-name&external-dns-name.key=/external-dns-name/$target"
    elif [[ "$type" == "ips" ]]; then
        api="$CloudInsightUrl/assets_query/v1/$cid/deployments/$deployment_id/assets?asset_types=external-ip&external-ip.key=/external-ip/$target"
    fi
    curl -skX GET -H "$Head" "$api" 
    debug_off
}
# Confirm that an external target was added or removed
function validate_ext_targets () {
    debug_on
    local -a list=( "$@" )
    if (( ${#list[@]} == 0 )); then
	    echo -e "${RED}ERROR${NC} validate_ext_target failed; input list was empty"
        exit 1
    else
        for check in "${list[@]}"; do
            local target type depid cid
            IFS=, read -r target type cid depid <<< "$check"
            local obj=$(extscan_target_exists "$target" "$type" "$cid" "$depid" 2>/dev/null)
            if (( ${#obj} > 25 )) && [[ $AppMode == 'add' ]]; then
                echo -e "${GRE}SUCCESS${NC} validation completed; ext target:[${YEL}$target${NC}] of type:[${YEL}$type${NC}] was confirmed added to deployment:[${YEL}$deployment_id${NC}] successfully."
            elif (( ${#obj} < 25 )) && [[ $AppMode == 'delete' ]]; then
                echo -e "${GRE}SUCCESS${NC} validation completed; ext target:[${YEL}$target${NC}] of type:[${YEL}$type${NC}] was confirmed deleted from deployment:[${YEL}$deployment_id${NC}] successfully."        
            fi
        done
    fi
    debug_off
}
# given a type and list and external targets, add those targets to the deployment
function add_ext_targets () {
    debug_on
    local type="$1"
    shift
    local -a is_valid_checklist list=( "$@" )
    local -i astat
    if (( ${#list[@]} == 0 )); then
	    echo -e "${RED}ERROR${NC} add_external_target failed; input list was empty"
        exit 1
    else
        for target in "${list[@]}"; do
            target=$(san "$target")
            if $CheckExistence; then # optional check for idempotency
                local obj=$(extscan_target_exists "$target" "$type" "$Cid" "$DeploymentId")
                if (( ${#obj} > 25 )); then # 
                    echo -e "${YEL}WARNING${NC} ext_scan target:[${YEL}$target${NC}] of type:[${YEL}$type${NC}] already exists; skipping..."
                    continue
                else { add_ext_target "$target" "$type" "$Cid" "$DeploymentId"; astat=$?; }
                fi
            else
                add_ext_target "$target" "$type" "$Cid" "$DeploymentId"; astat=$?
            fi
            if (( $astat == 0 )); then
                echo -e "${CYA}OKAY${NC} ext target:[${YEL}$target${NC}] of type:[${YEL}$type${NC}] add_ext_target completed without error"
                if ! $SkipValidation; then { is_valid_checklist+=( "$target,$type,$Cid,$DeploymentId" ); } fi
            else { echo -e "${RED}ERROR${NC} add_target operation failed; ext target:[${YEL}$target${NC}] of type:[${YEL}$type${NC}] was not added"; }  
            fi
        done        
    fi
    if ! $SkipValidation && (( ${#is_valid_checklist[@]} >= 1 )); then
        echo -e "${CYA}INFO${NC} Please wait for targets to be validated..."
        validate_ext_targets "${is_valid_checklist[@]}"
    elif ! $SkipValidation && (( ${#is_valid_checklist[@]} == 0 )); then # if we are validating and validation list is empty, something went wrong
        echo -e "${RED}ERROR${NC} validation operation failed; is_valid_checklist was empty:[${YEL}${#is_valid_checklist[@]}${NC}]; check if any ext targets were actually added"
        exit 3
    else { echo -e "${YEL}NOTE${NC} skipping validation as per user request."; }
    fi 
    debug_off
}
# given some input, check if its CIDR, IP, or DNS entry and add it to the appropriate array
function check_item_type () {
    debug_on
    local input="${1//\"/}"
    if [[ -n "$(grep -Pio $_CIDR_REGEX <<< "$input")" ]]; then
        echo -e "${CYA}INFO${NC} Converting CIDR:[${YEL}$input${NC}] to IP list..."
        IFS=' ' read -r -a cidr_ips <<< "$(convert_cidr_to_iplist "$input")"
        echo -e "${CYA}INFO${NC} CIDR:[${YEL}$input${NC}] converted to ${YEL}${#cidr_ips[@]}${NC} IPs."
        IPTargets+=( "${cidr_ips[@]}" )
        unset cidr_ips
    elif [[ "$(grep -Po $_IPV4_REGEX <<< "$input")" ]]; then
        IPTargets+=( "$input" )
    elif [[ "$(grep -Po $_DNS_REGEX <<< "$input")" ]]; then # Bashes regex does not support lookaround so we use grep -Po for that
        DNSTargets+=( "$input" )
    fi
    debug_off
}
# validate input by user, right now for delete mode. Later this will be refactored to check ALL user input for all operations
function input_validation () {
    debug_on 
    local matcher="$1"
    shift
    local -a input_list=( "$@" )
    local -a iplist dnslist
    if [[ "$matcher" == '-' ]] && (( ${#input_list[@]} >= 1 )); then # no matcher we are using file or a manually inputted list
        echo -e "${CYA}INFO${NC} Using provided list or manual input to find targets for operation."
        # check each item to make sure its valid and make lists of targets to delete
        for input in "${input_list[@]}"; do
            if [[ -n "$(grep -Pio $_IPV4_REGEX <<< "$input")" ]]; then 
                input=$(tr -dc '[:digit:][=.=]' <<< "$input")
                iplist+=( "${input}:ip" )
            elif [[ -n "$(grep -Pio $_CIDR_REGEX <<< "$input")" ]]; then
                IFS=' ' read -ra tmp <<< "$(convert_cidr_to_iplist "$input")"
                iplist+=( "${tmp[@]/%/:ip}" )
            elif [[ "$(grep -Po $_DNS_REGEX <<< "$input")" ]] && [[ ! "$input" =~ $_IPV4_REGEX ]]; then
                dnslist+=( "${input}:dns" )
            fi
        done
        if (( ${#iplist[@]} >= 1 )) || (( ${#dnslist[@]} >= 1 )); then
            local -a allexts=( "${iplist[@]}" "${dnslist[@]}" )
            for tpair in "${allexts[@]}"; do
                for existing in "${AllList[@]}"; do
                    IFS=, read -r ext dname depid <<< "$existing"
                    IFS=':' read -r target type <<< "$tpair"
                    ext=$(tr -dc '[:alnum:][=.=][=-=][=_=][=~=][=/=]' <<< "$ext")
                    target=$(tr -dc '[:alnum:][=.=][=-=][=_=][=~=][=/=]' <<< "$target")
                    if [[ "$ext" == "$target" ]]; then
                        echo -e "${CYA}INFO${NC} Target selected for operation: [${YEL}$ext${NC}] from deployment:[${YEL}$dname${NC}] (ID: [${YEL}$depid${NC}])"
                        MatchedTargets+=( "$target,$type,$dname,$depid" )
                    fi
                done
            done
        else { echo -e "${RED}ERROR${NC} no valid targets found in provided list or manual input"; return 1; }
        fi  
    elif [[ -n "$matcher" ]]; then
        echo -e "${CYA}INFO${NC} Using matcher pattern:[${YEL}$matcher${NC}] to find targets for operations."
        for ipline in "${IPList[@]}"; do
            IFS=, read -r extip dname depid <<< "$ipline"
            extip=$(tr -dc '[:digit:][=.=]' <<< "$extip") # clean 
            if [[ "$extip" == "$matcher" ]] || [[ -n "$(grep -Pio $matcher <<< "$extip")" ]]; then
                MatchedTargets+=( "$extip,ip,$dname,$depid" )
            fi
        done
        for dnline in "${DNSList[@]}"; do
            IFS=, read -r extdns dname depid <<< "$dnline"
            extdns=$(tr -dc '[:alnum:][=.=][=-=][=_=][=~=][=/=]' <<< "$extdns") # strip forward slashes in case we got a key or a cidr
            if [[ "$extdns" == "$matcher" ]] || [[ -n "$(grep -Pio $matcher <<< "$extdns")" ]]; then
                MatchedTargets+=( "$extdns,dns,$dname,$depid" )
            fi
        done
    fi
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
function convert_cidr_to_iplist () {
    debug_on
    local cidr="$1"
    [[ -z "$(grep -Po $_CIDR_REGEX <<< "$cidr")" ]] && { echo -e "${RED}ERROR${NC} convert_cidr_to_iplist failed; invalid CIDR was input:[${YEL}$cidr${NC}]"; return 8; }
    IFS='/' read -r net prefix <<< "$cidr"
    (( prefix < 16 || prefix > 32 )) && { echo -e "${RED}ERROR${NC} convert_cidr_to_iplist failed; invalid CIDR prefix was input:[${YEL}$prefix${NC}]\nOnly prefixes [16-32] are supported."; return 8; }
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
################################################################################################
#                              INTERACTIVE MENU FUNCTIONS                                      #
################################################################################################
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
function segm () { local -i w=$1; for ((i=0;i<$w;i++)); do echo -en '-'; done; echo; }
function manage_ext_target_usage () {
    local script_name=$(basename "$0")
    local token_note="In later versions this will be included but for now, the token must be set and exported separately."
    local desc1="This script will let you bulk-add or bulk-remove external scan assets to a deployment. You may also see a list of all external assets across a single CID or a single deployment. This script requires an AlertLogic authentication token like this: $(echo -e "${CYA}auth_token${NC}"). $token_note"
    local -a reqs=( 'Bash version > 3.1' 'JQ version > 1.5' 'Terminal-width at least 80 columns' 'AlertLogic XAIMS Auth Token' )
    local targ1="This script accepts lists of host IPs or names, CIDRs, wildcards and regexes. You can add/remove targets from the command line or interactively. You will be prompted for any inputs not entered on the command line."
    local add1="When adding CIDRs or lists of IPs/DNS names, you can enter these at the command-line, interactively, or you can load them from file."
    local del1="When deleting IPs and/or DNS names, you can enter a CIDR or filename at the command-line and interactively. In addition to plain lists, you may also enter CIDRs, regexes or wildcards for both IPs and hostnames interactively. Check the Example section for more info."
    local del2="The existence of each target of all positive pattern matches will be confirmed, so overly greedy regexes or wildcards, i.e.: [8.10.1.*],[8.10.1.[\d]+] or [acme.*.com] will only remove existing IPs anyway. So if you only have [10.10.10.1-20] and you use [10.10.10.*], all 20 of those IPs will be removed and nothing else." 
    local del3="$(echo -e "${BLU}NOTE${NC}"): inputting patterns at the command-line is not supported at this time."
    local gen1="You may optionally enable or disable additional options that govern the script's run-time behavior, post-operation checks or pre-operation existence checks." 
    local gen2="You may skip existence checks before adding external scan targets. This is not supported in delete mode. All deletion targets will be checked before removal."
    local gen3="You may also optionally skip post-action validation for both the add and delete modes, if you would like to instead just check the console to confirm your targets were added or removed."
    local gen4="Finally, you also may run the script in Test-Run mode. This allows you to see what changes will take place before actually running modifying any live customer account."
    local -i col1=$(( MenuW * 4/100))
    local -i col2=$(( MenuW * 16/100))
    local -i col3=$(( MenuW * 11/100))
    local -i col4=$(( MenuW * 69/100)) 
    local s="Short" l="Long" a="Args" d="Description"
    local -a options=(
        '-c,--cid,<CID>,Specify the Alert Logic Customer ID (CID) to manage external scan targets for.'
        '-r,--cidr,<CIDR>,Specify a CIDR range to convert to IP list for adding as external scan targets.'
        '-d,--deployment-id,<deployment id>,Specify the deployment ID to manage external scan targets for.'
        '-f,--file,<filepath>,Specify path to file containing a list of IPs or DNS names to add as external scan targets.'
        '-d,--delete,,Enable delete mode to remove external scan targets instead of adding them.'
        '-l,--list-mode,,List existing external scan targets across either an entire CID or a single deployment.'
        '-s,--skip-validation,,Skip validation of added external scan targets.'
        '-x,--skip-check-existence,,Skip checking for existing targets before adding (may result in duplicates).'
        '-t,--test-run,,Enable test run mode to simulate actions without making changes.'
        '-d,--debug,,Enable debug mode for verbose output.'
        '-h,--help,,Display this help message and exit.'
    )
    local -i h=$((MenuW/2)) 
    local -i r=$((MenuW-h-1))  # -1 for the space between header and version 
    echo -e "+$(segm $MenuW)+"
    printf "|%${h}s %-${r}s|\n" "EXTERNAL SCAN TARGET MANAGEMENT" "Version: $Version"
    echo -e "+$(segm $MenuW)+\n"
    echo -e "${YEL}DESCRIPTION:${NC}"
    fold -w $MenuW -s <<< "$desc1"; echo
    echo -e "${YEL}REQUIREMENTS:${NC}"
    echo -e "Pre-requisites for running this script:"
    for req in "${reqs[@]}"; do { echo -e "    $req"; } done; echo
    echo -e "${YEL}INPUTTING TARGETS:${NC}"
    fold -w $MenuW -s <<< "$targ1"; echo 
    echo -e "${YEL}ADD MODE:${NC}"
    fold -w $MenuW -s <<< "$add1"; echo   
    echo -e "${YEL}DELETE MODE:${NC}"
    fold -w $MenuW -s <<< "$del1 $del2 $del3"; echo   
    echo -e "${YEL}ADDITIONAL OPTIONS:${NC}"
    fold -w $MenuW -s <<< "$gen1 $gen2 $gen3 $gen4"; echo  
    echo -e "${YEL}COMMAND-LINE FLAGS:${NC}"
    echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+$(segm $col4)+\n"
    printf "|%-${col1}s|%-${col2}s|%-${col3}s|%-${col4}s|\n" "${s::$col1}" "${l::$col2}" "${a::$col3}" "${d::$col4}"
    echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+$(segm $col4)+\n"
    for opt in "${options[@]}"; do
        IFS=, read -r short long arg desc <<< "$opt"
        printf "|%-${col1}s|%-${col2}s|%-${col3}s|%-${col4}s|\n"  "${short::$col1}" "${long::$col2}" "${arg::$col3}" "${desc::$col4}"
    done
    echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+$(segm $col4)+\n" 
    echo -e "${YEL}EXAMPLE USAGE:${NC}"
    echo -e "$script_name [${GRE}OPTIONS${NC} <args>]"
    echo -e "$script_name ${GRE}--cid${NC} 66012345 --${GRE}deployment-id${NC} ABCD1234-5678-453D-9783-WXYZ631C1234 ${GRE}--cidr${NC} 8.10.100.128/28 ${GRE}--skip-validation${NC}"
    echo -e "$script_name ${GRE}--cid${NC} 54321 ${GRE}--file${NC} "iplist.txt" ${GRE}--skip-existence ${GRE}--skip-validation${NC}"
    echo -e "$script_name ${GRE}--cid${NC} 134231234 ${GRE}--deployment-id${NC} ABCD1234-5678-453D-9783-WXYZ631C1234 ${GRE}--delete${NC}"
    echo -e "$script_name ${GRE}--delete --skip-validation${NC} ${CYA}# you will be prompted interactively for inputs${NC}"
    echo -e "$script_name ${CYA}# no flags == interactive mode; you will be prompted for all necessary inputs${NC}"
    echo -e "$script_name ${GRE}--cid${NC} 66765432 ${GRE}--deployment-id${NC} ABCD1234-5678-453D-9783-WXYZ631C1234 ${GRE}--cidr${NC} 8.10.100.128/28 ${GRE}--skip-validation${NC}"
    echo -e "$script_name ${GRE}--test-run${NC}"
    echo

}
# Get input from user by allowing them to select the deployment from a numbered list, if only one deployment exists, it is auto-selected
# width of menu is based on screen width and if lower than 60 cols, a simplified menu with no deployment id is shown
function get_deployment_menu () {
    local -a deplist
    local -i col1=$(( MenuW * 10/100))
    local -i col2=$(( MenuW * 40/100))
    local -i col3=$(( MenuW * 50/100)) 
    if $DepidSet; then
        echo -e "\n${CYA}INFO${NC} Deployment ID:[${YEL}$DeploymentId${NC}] was already set; skipping deployment selection."
        return 0
    fi
    if ! $CidSet || ! $CidValid || [[ ! $Cid =~ $_NUM_REGEX ]]; then
        echo -e "${RED}ERROR${NC} Cannot get deployment list; CID:[${YEL}$Cid${NC}] is not set or invalid. Exiting."
        clean_exit 2
    fi
    echo -e "\n${CYA}INFO${NC} Fetching deployments for CID:[${YEL}$Cid${NC}]..."
    readarray -t deplist < <(list_deployments "$Cid")
    if (( ${#deplist[@]} == 0 )); then
        echo -e "${RED}ERROR${NC} No deployments found for CID:[${YEL}$cid${NC}]. Exiting."
        clean_exit 2
    elif (( ${#deplist[@]} == 1 )); then
        IFS=, read -r depname depid <<< "${deplist[0]}"
        echo -e "\n${CYA}INFO${NC} Only one deployment found for CID:[${YEL}$cid${NC}]; selecting deployment:[${YEL}$depname${NC}] with ID:[${YEL}$depid${NC}]."
        DeploymentId="${depid//\"/}" && DepidSet=true
        DeploymentName="$depname"
        return 0
    fi
    local -i index=1
    if (( ScreenW < 60 )); then
        col2=$(( MenuW * 10/100 ))
        col2=$(( MenuW * 90/100 ))
        echo -e "+$(segm $MenuW)+"
        printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "DEPLOYMENT SELECTION MENU" 
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
    read -rp $'\n'"Enter the index number of the deployment to manage external scan targets for: $(echo -e "${RED}->>${NC} ")" dep_index
    if ! [[ "$dep_index" =~ ^[0-9]+$ ]] || (( dep_index < 1 )) || (( dep_index > ${#deplist[@]} )); then
        echo -e "${RED}ERROR${NC} Invalid deployment index:[${YEL}$dep_index${NC}] entered. Please try again."
        get_deployment_menu
    else
        IFS=, read -r sel_depname sel_depid <<< "${deplist[$((dep_index-1))]}"
        echo -e "\n${CYA}INFO${NC} You selected deployment:[${YEL}$sel_depname${NC}] with ID:[${YEL}$sel_depid${NC}]."
        DeploymentId="${sel_depid//\"/}" && DepidSet=true
        DeploymentName="$sel_depname"
    fi
}
function get_cid_menu () {
    echo -e "+$(segm $MenuW)+"
    printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "CID INPUT MENU"
    echo -e "+$(segm $MenuW)+"
    read -rp $'\n'"Enter the Alert Logic Customer ID (CID) to manage external scan targets for: $(echo -e "${RED}->>${NC}") " input_cid
    if ! [[ "$input_cid" =~ $_NUM_REGEX ]]; then
        echo -e "${RED}ERROR${NC} Invalid CID:[${YEL}$input_cid${NC}] entered. Exiting."
        clean_exit 2
    else
        CustomerName=$(cid_exists "$input_cid" | tr -d $'\n')
        if [[ -z "$CustomerName" ]]; then
            echo -e "${RED}ERROR${NC} CID:[${YEL}$input_cid${NC}] does not exist or could not be found. Exiting."
            clean_exit 2
        else
            echo -e "\n${CYA}INFO${NC} You selected CID:[${YEL}$input_cid${NC}] with account name:[${YEL}$CustomerName${NC}]."
            get_cloudinsight_url "$Cid"
            Cid="$input_cid" && CidSet=true; CidValid=true
        fi
    fi
}
function main_menu () {
    local -i col1=$(( MenuW * 10/100))
    local -i col2=$(( MenuW * 90/100))
    local -a action_options=(
        '1, Add external scan targets (IPs or DNS names)'
        '2, Remove external scan targets (IPs or DNS names)'
        '3, List current external scan targets by deployment or CID'
        '4, Exit script'
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
    read -rp $'\n'"Select an input option (1-4): $(echo -e "${RED}->>${NC} ")" input_option
    if [[ ! "$input_option" =~ $_NUM_REGEX ]] || (( input_option < 1 || input_option > 4 )); then
        echo -e "${RED}ERROR${NC} Invalid action option:[${YEL}$input_option${NC}] was selected. Exiting."
        clean_exit 2
    else
        case "$input_option" in
            1)  { AppMode='add'; } ;;
            2)  { AppMode='delete'; } ;;
            3)  { AppMode='list'; } ;;
            4)  { echo -e "\n${MAG}Exiting script and cleaning up artefacts...${NC}"; clean_exit 0; } ;;
        esac
    fi
}
function list_exttargets_menu () {
    local -i col1=$(( MenuW * 10/100))
    local -i col2=$(( MenuW * 90/100))
    local -a action_options=(
        '1, List all external scan targets by deployment.'
        '2, List all external scan targets by CID (all deployments).'
        '3, List external DNS name targets by deployment.'
        '4, List external IP targets by deployment.'
        '5, List external DNS name targets by CID (all deployments).'
        '6, List external IP targets by CID (all deployments).'
        '7, Exit script.'
    )
    echo -e "+$(segm $MenuW)+"
    printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "LIST EXTERNAL SCAN TARGETS MENU"
    echo -en "+$(segm $col1)+$(segm $col2)+\n"
    printf "|%-${col1}s|%-${col2}s|\n" "Option" "Description"
    echo -en "+$(segm $col1)+$(segm $col2)+\n"
    for option in "${action_options[@]}"; do
        IFS=, read -r opt desc <<< "$option"
        printf "|%-${col1}s|%-${col2}s|\n" "$opt" "$desc"
        echo -en "+$(segm $col1)+$(segm $col2)+\n"
    done
    read -rp $'\n'"Select an input option (1-7): $(echo -e "${RED}->>${NC} ")" input_option
    if [[ "$input_option" =~ $_NUM_REGEX ]] && (( input_option >= 1 || input_option <= 7 )); then
        case "$input_option" in
            1) { # List all external scan targets by deployment
                get_deployment_menu "$Cid"
                list_existing_exts "$DeploymentId" "$DeploymentName"
                display_existing_exts "${AllList[@]}"
            } ;;
            2) {  # List all external scan targets by CID (all deployments)
                list_existing_exts
                display_existing_exts "${AllList[@]}"
            } ;;
            3) { # List external DNS name targets by deployment
                get_deployment_menu "$Cid"
                list_existing_exts "$DeploymentId" "$DeploymentName"
                display_existing_exts "${DNSList[@]}"
            } ;;
            4) { # List external IP targets by deployment
                get_deployment_menu "$Cid"
                list_existing_exts "$DeploymentId" "$DeploymentName"
                display_existing_exts "${IPList[@]}"
            } ;;
            5) { # List external DNS name targets by CID (all deployments)
                list_existing_exts "-"
                display_existing_exts "${DNSList[@]}"
            } ;;
            6) { # List external IP targets by CID (all deployments)
                list_existing_exts "-"
                display_existing_exts "${IPList[@]}"
            } ;;
            7)  { echo -e "\n${MAG}Exiting script and cleaning up artefacts...${NC}"; clean_exit 0; } ;;
        esac
    else
        echo -e "${RED}ERROR${NC} Invalid input option:[${YEL}$input_option${NC}] selected. Exiting."
        clean_exit 2
    fi
}
function general_options_menu () {
    local -i col1=$(( MenuW * 20/100))
    local -i col2=$(( MenuW * 90/100))
    local -a action_options=(
        '1, Dont check for confirmation (validation) after adding or deleting external scan targets.'
        '2, Dont check for existing assets before adding (may result in duplicates; not applicable to delete mode).'
        '3, Enable test-run mode to simulate actions without making any changes to any live accounts.'
        '4, Exit script.'
    )
    local opt="Option" des="Description"
    echo -e "+$(segm $MenuW)+"
    printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "GENERAL OPTIONS MENU"
    echo -en "+$(segm $col1)+$(segm $col2)+\n" 
    printf "|%-${col1}s|%-${col2}s|\n" "${opt::$col1}" "${des::$col2}"
    echo -en "+$(segm $col1)+$(segm $col2)+\n"
    for option in "${action_options[@]}"; do
        IFS=, read -r opt desc <<< "$option"
        printf "|%-${col1}s|%-${col2}s|\n" "${opt}" "${desc::$col2}"
        echo -en "+$(segm $col1)+$(segm $col2)+\n"
    done
    read -rp $'\n'"Enter run-time option(s) (1-3) separated by spaces: $(echo -e "${RED}->>${NC} ")" input_options
    [[ -n "$input_options" ]] && IFS=' ' read -ra temp <<< "$input_options"
    if (( ${#temp[@]} == 0 )); then
        echo -e "${YEL}NOTE${NC} No run-time options selected; proceeding with defaults."
        return 0
    else
        for opt in "${temp[@]}"; do
            if ! [[ "$opt" =~ $_NUM_REGEX ]] || (( opt < 1 )) || (( opt > 4 )); then
                echo -e "${RED}ERROR${NC} Invalid input option:[${YEL}$opt${NC}] selected. Exiting."
                clean_exit 2
            elif [[ "$opt" =~ $_NUM_REGEX ]] && (( opt >= 1 && opt <= 4 )); then
                case $opt in
                    1)  { SkipValidation=true; echo -e "${CYA}INFO${NC} Validation skipping was enabled."; } ;;
                    2)  { CheckExistence=false; echo -e "${CYA}INFO${NC} Existence checking was disabled."; } ;;
                    3)  { TestRun=true; echo -e "${CYA}INFO${NC} Testrun mode was enabled."; } ;;    
                    4)  { echo -e "\n${MAG}Exiting script and cleaning up artefacts...${NC}"; clean_exit 0; } ;;
                esac
            fi
        done
    fi
}
function delete_targets_menu () {
    local -a targets
    local -i col1=$(( MenuW * 10/100))
    local -i col2=$(( MenuW * 90/100))
    local -a action_options=(
        '1, Enter a list of IPs, CIDRs or DNS names separated by spaces or newlines.'
        '2, Enter a regex or wildcard pattern to match targets for deletion (BE CAREFUL).'
        '3, Select a text file containing a list of IPs, CIDRs or DNS names.'
        '4, Exit script.'
    )
    echo -e "\n${CYA}INFO${NC} Loading existing external scan targets for CID:[${YEL}$Cid${NC}].\nPlease wait..."
    if $CidSet && $DepidSet; then { list_existing_exts "$DeploymentId" "$DeploymentName"; } 
    elif $CidSet; then { list_existing_exts; }
    else { echo -e "${YEL}NOTE${NC} Cid was not set! Script cannot run without a Cid. Please try again."; exit 1; } 
    fi
    echo -e "\n${YEL}NOTE${NC} Would you like to display the list of existing external scan targets? Enter \"[Y]es\" or \"[N]o\" below."
    read -rp $'\n'"Your choice: $(echo -e "${RED}->>${NC} ")" display_choice
    if [[ "$display_choice" =~ ^[Yy]$ ]]; then
        display_existing_exts "${AllList[@]}"
    else
        echo -e "${YEL}NOTE${NC} Skipping existing external scan targets display as per user request."
    fi
    echo -e "+$(segm $MenuW)+"
    printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "DELETE TARGETS ENTRY MENU"
    echo -en "+$(segm $col1)+$(segm $col2)+\n"
    printf "|%-${col1}s|%-${col2}s|\n" "Option" "Description"
    echo -en "+$(segm $col1)+$(segm $col2)+\n"
    for option in "${action_options[@]}"; do
        IFS=, read -r opt desc <<< "$option"
        printf "|%-${col1}s|%-${col2}s|\n" "$opt" "$desc"
        echo -en "+$(segm $col1)+$(segm $col2)+\n"
    done
    # list_existing_exts "$Cid"
    read -rp $'\n'"Select an input option (1-4): $(echo -e "${RED}->>${NC} ")" input_option
    if [[ "$input_option" =~ $_NUM_REGEX ]] && (( input_option >= 1 || input_option <= 4 )); then
        case $input_option in
            1)  { # Enter a list of IPs, CIDRs or DNS names separated by spaces or newlines.
                echo -e "Enter the target type (CIDRs, ips or DNS names). Press ENTER when finished entering targets."
                while read -r input_list; do
                    if [[ -n "${input_list}" ]]; then #if we get good input, grab the list pointer
                        IFS=' ' read -ra tmp <<< "$input_list"
                        if (( ${#tmp[@]} >= 1 )); then
                            input_list=( "${tmp[@]}" ) # this extra step is probably not necessary, might cut this down to one line later after debugging
                            # echo "SaNITY CHECK : deletionmenu temp list:[${#tmp[@]}] and inputlist contents:[${input_list[@]}]"
                        elif [[ -z "$input_list" ]]; then
                            echo -e "${RED}ERROR${NC} No input was provided. Please try again."
                            continue
                        fi
                    fi
                    deletion_submenu '-' "${input_list[@]}"
                    local del_status=$?
                    if (( del_status == 110 )); then
                        # proceed with deletion
                        break
                    elif (( del_status == 120 )); then
                        # something looks wrong, try again
                        echo -e "\n${YEL}NOTE${NC} Something looks wrong, let's try again."
                        continue
                    fi
                done   
            } ;;
            2)  { # Enter a regex or wildcard pattern to match targets for deletion (BE CAREFUL).
                echo -e "\nEnter the regex or wildcard pattern to match targets for deletion i.e., 10.10.10.* or 192.168.1.[\d]+ (no CIDRS, please): "
                while read -r matcher; do 
                    if [[ -n "${matcher}" ]]; then
                        deletion_submenu "$matcher"
                        local match_status=$?
                        if (( match_status == 110 )); then
                            # proceed with deletion
                            break
                        elif (( match_status == 120 )); then
                            # refine regex/wildcard
                            echo -e "\n${YEL}NOTE${NC} Let's try refining your regex/wildcard pattern."
                            continue
                        fi
                    elif [[ -z "$matcher" ]]; then
                        echo -e "${RED}ERROR${NC} No input was provided. Please try again."
                        continue
                    fi
                done
            } ;;
            3)  { # Select a text file containing a list of IPs, CIDRs or DNS names.
                file_input_submenu
                deletion_submenu '-' "${Templist[@]}"
                local del_status=$?
                if (( del_status == 120 )); then
                    # something looks wrong, try again
                    echo -e "\n${YEL}NOTE${NC} something looks wrong, let's try getting some input again."
                    delete_targets_menu
                fi      
            } ;;
            4)  { echo -e "\n${MAG}Exiting script and cleaning up artefacts...${NC}"; clean_exit 0; } ;;
        esac
    else
        echo -e "${RED}ERROR${NC} Invalid input option:[${YEL}$input_option${NC}] selected. Exiting."
        clean_exit 2
    fi   
}
function deletion_submenu () {
    matcher="$1"
    shift
    input_list=( "$@" )
    local -a action_options
    local prompt
    local -i col1=$(( MenuW * 10/100))
    local -i col2=$(( MenuW * 90/100))
    local -a match_options=(
        '1, Looks good, lets use this list of targets!'
        '2, NO, let me refine my regex/wildcard.'
        '3, Exit script.'
    )
    local -a file_options=(
        '1, Looks good, lets use this list of targets!'
        '2, NO, something looks wrong, let me try again.'
        '3, Exit script.'
    )
    if [[ "$matcher" == '-' ]]; then
        action_options=("${file_options[@]}")
        prompt="matched from file input."
    else
        action_options=("${match_options[@]}")
        prompt="matched your pattern:[${YEL}$matcher${NC}]:"
    fi
    input_validation "$matcher" "${input_list[@]}"
    if (( ${#MatchedTargets[@]} == 0 )); then
        echo -e "${YEL}WARNING${NC} your inputs did not match any existing external scan targets. You can only delete external targets that exist. Check the deployment and list and try again."
        return 120 # continue
    else
        echo -e "${CYA}INFO${NC} The following external scan targets $prompt"
        display_deletion_targets "${MatchedTargets[@]}"
        echo -e "+$(segm $MenuW)+"
        printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "MATCHED LIST CONFIRMATION SUBMENU"
        echo -en "+$(segm $col1)+$(segm $col2)+\n"
        printf "|%-${col1}s|%-${col2}s|\n" "Option" "Description"
        echo -en "+$(segm $col1)+$(segm $col2)+\n"
        for option in "${action_options[@]}"; do
            IFS=, read -r opt desc <<< "$option"
            printf "|%-${col1}s|%-${col2}s|\n" "$opt" "$desc"
            echo -en "+$(segm $col1)+$(segm $col2)+\n"
        done
        read -rp $'\n'"Select an input option (1-3): $(echo -e "${RED}->>${NC} ")" conf_target
        if [[ "$conf_target" =~ $_NUM_REGEX ]] && (( conf_target >= 1 || conf_target <= 3 )); then  
            case $conf_target in
                1)  { # Looks good, lets use this list of targets!
                    DeletionTargets=( "${MatchedTargets[@]}" )
                    return 110 # break
                } ;;
                2)  { # NO, let me refine my regex/wildcard.
                    return 120
                } ;;
                3)  { echo -e "\n${MAG}Exiting script and cleaning up artefacts...${NC}"; clean_exit 0; } ;;
            esac
        else
            echo -e "${RED}ERROR${NC} Invalid input option:[${YEL}$conf_target${NC}] selected. Exiting."
            clean_exit 2
        fi
    fi                          
}
function add_targets_menu () {
    local -a targets
    local -i col1=$(( MenuW * 10/100))
    local -i col2=$(( MenuW * 90/100))
    local -a action_options=(
        '1, Enter a list of IPs, CIDRs or DNS names separated by spaces.'
        '2, Select a text file containing a list of IPs, CIDRs or DNS names.'
        '3, Exit script.'
    )
    echo -e "+$(segm $MenuW)+"
    printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "ADD TARGETS ENTRY MENU"
    echo -en "+$(segm $col1)+$(segm $col2)+\n"
    printf "|%-${col1}s|%-${col2}s|\n" "Option" "Description"
    echo -en "+$(segm $col1)+$(segm $col2)+\n"
    for option in "${action_options[@]}"; do
        IFS=, read -r opt desc <<< "$option"
        printf "|%-${col1}s|%-${col2}s|\n" "$opt" "${desc::$col2}"
        echo -en "+$(segm $col1)+$(segm $col2)+\n"
    done
    read -rp $'\n'"Select an input option (1-3): $(echo -e "${RED}->>${NC} ")" input_option
    if [[ "$input_option" == "1" ]]; then
        echo -e "Enter the target type (CIDRs, ips or DNS names). Press Ctrl+D when finished entering targets."
        while read -r input_list; do
            if [[ -n "${input_list}" ]]; then #if we get good input, grab the list pointer
                IFS=' ' read -ra tmp <<< "$input_list"
                if (( ${#tmp[@]} >= 1 )); then
                    input_list=( "${tmp[@]}" )
                    break
                elif [[ -z "$input_list" ]]; then
                    echo -e "${RED}ERROR${NC} No input was provided. Please try again."
                    continue
                fi
            fi
        done
        for input in "${input_list[@]}"; do { check_item_type "$input"; } done
    elif [[ "$input_option" == "2" ]]; then
        file_input_submenu
        for input in "${Templist[@]}"; do { check_item_type "$input"; } done
    elif [[ "$input_option" == "3" ]]; then
        echo -e "\n${MAG}Exiting script and cleaning up artefacts...${NC}"
        clean_exit 0
    else
        echo -e "${RED}ERROR${NC} Invalid input option:[${YEL}$input_option${NC}] selected. Exiting."
        clean_exit 2
    fi
}
function file_input_submenu () {
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
    InputFile="${files[$((index-1))]}" 
    InputFile="${InputFile//\"/}"
    echo -e "${CYA}INFO${NC} file path chosen from list:[${YEL}${InputFile}${NC}] at:[${YEL}$index${NC}]"
    rmcr "$InputFile"
    if (( $(wc -l < "$InputFile") >= 1 )); then 
        readarray -t Templist <<< "$(<"$InputFile")"
    else
        echo -e "${RED}ERROR${NC} Input file was empty or not found:[${YEL}$(wc -l < "$InputFile")${NC}]. Exiting."
        exit 1
    fi 
}
function confirm_menu () {
    local mode_type="$1"
    if [[ "$mode_type" == 'add' ]]; then
        display_addition_targets "${IPTargets[@]}"
        display_addition_targets "${DNSTargets[@]}"
    elif [[ "$mode_type" == 'delete' ]]; then
        display_deletion_targets "${DeletionTargets[@]}"
    fi
    echo -e "+$(segm $MenuW)+"
    printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "FINAL CONFIRMATION MENU"
    echo -e "+$(segm $MenuW)+"
    if ! $TestRun; then 
        echo -e "${MAG}WARNING!! YOU ARE ABOUT TO MAKE CHANGES TO A LIVE CUSTOMER'S PROD ACCOUNT!${NC}"
    elif $TestRun; then
        echo -e "${YEL}NOTE${NC} YOU ARE NOT ABOUT TO MAKE ANY CHANGES TO ANY LIVE ACCOUNTS. YOU ARE STILL IN TEST RUN MODE."
    fi
    echo -e "ARE YOU SURE YOU WANT TO CONTINUE?"
    read -rp $'\n'"Type the word $(echo -e ${YEL}CONFIRM${NC}) to continue and then press ENTER (or type \"no\" to cancel): " confirmed;  
    if [[ "${confirmed^^}" == "CONFIRM" ]]; then
        echo -e "${CYA}INFO${NC} Confirmation received; proceeding with the operation..."
        if [[ "$mode_type" == 'add' ]]; then
            (( ${#IPTargets} >= 1 )) && add_ext_targets 'ips' "${IPTargets[@]}"
            (( ${#DNSTargets} >= 1 )) && add_ext_targets 'dns' "${DNSTargets[@]}"
        elif [[ "$mode_type" == 'delete' ]]; then
            remove_ext_targets "${DeletionTargets[@]}"
        fi
    elif [[ "${confirmed^^}" == 'NO' ]]; then
        echo -e "${YEL}NOTE${NC} Operation cancelled by user; returning to main menu."
        clean_exit 0
    else
        echo -e "${RED}ERROR${NC} You must type out the word 'confirm' to proceed."
        confirm_menu "$mode_type"
    fi            
}
###########################################################################################
#                               DISPLAY FUNCTIONS                                         #
###########################################################################################
function display_existing_exts () {
    local -a targets=( "$@" )
    local -i col1=$(( MenuW * 20/100))
    local -i col2=$(( MenuW * 40/100))
    local -i col3=$(( MenuW * 40/100))
    echo -e "+$(segm $MenuW)+"
    printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "EXISTING SCAN TARGETS DISPLAY"
    echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+\n"
    printf "|%-${col1}s|%-${col2}s|%-${col3}s|\n" "Asset" "Deployment Name" "Deployment ID"
    echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+\n"
    for target in "${targets[@]}"; do
        IFS=, read -r ext dname depid <<< "$target"
        ext=$(tr -dc '[:alnum:][=.=][=-=][=_=][=~=][=/=]' <<< "$ext")
        printf "|%-${col1}s|%-${col2}s|%-${col3}s|\n" "${ext::$col1}" "${dname::$col2}" "${depid::$col3}"
        echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+\n"
    done
    local -i col4=36
    local -i col5=6
    local -i fcol=$((col4+col5+1))
    echo -en "+$(segm $fcol)+\n"
    printf "|%7s${BLU}%s${NC}%7s|\n" " " "EXISTING SCAN TARGETS SUMMARY" " "
    echo -en "+$(segm $fcol)+\n"
    printf "|%-${col4}s|%${col5}s|\n" "Total IP Targets:" 15 #"${#IPList[@]}"
    printf "|%-${col4}s|%${col5}s|\n" "Total DNS Targets:" 23 #"${#DNSList[@]}"
    echo -en "+$(segm $col4)+$(segm $col5)+\n"
}
function display_deletion_targets () {
    local -a targets=( "$@" )
    local -i col1=$(( MenuW * 20/100))
    local -i col2=$(( MenuW * 40/100))
    local -i col3=$(( MenuW * 40/100))
    echo -e "+$(segm $MenuW)+"
    printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "DELETION SCAN TARGETS LIST DISPLAY"
    echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+\n"
    printf "|%-${col1}s|%-${col2}s|%-${col3}s|\n" "To Delete" "Deployment Name" "Deployment ID"
    echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+\n"
    for target in "${targets[@]}"; do
        IFS=, read -r ext type dname depid <<< "$target" # type wont be shown here
        printf "|${RED}%-${col1}s${NC}|%-${col2}s|%-${col3}s|\n" "${ext::$col1}" "${dname::$col2}" "${depid::$col3}"
        echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+\n"
    done
}
function display_addition_targets () {
    local -a targets=( "$@" )
    local -i col1=$(( MenuW * 25/100))
    local -i col2=$(( MenuW * 25/100))
    local -i col3=$(( MenuW * 25/100))
    local -i col4=$(( MenuW * 25/100))
    if (( ${#targets[@]} >= 1 )); then
        echo -e "+$(segm $MenuW)+"
        printf "|${BLU}%${Mid}s${NC}%${Rt}s|\n" "ADDITION SCAN TARGETS LIST DISPLAY"
        echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+$(segm $col4)+\n"
        for (( i=0; i<${#targets[@]}; i+=4 )); do
            printf "|%-${col1}s|%-${col2}s|%-${col3}s|%-${col4}s|\n" "${targets[$i]::$col1}" "${targets[$((i+1))]::$col2}" "${targets[$((i+2))]::$col3}" "${targets[$((i+3))]::$col4}"  
            echo -en "+$(segm $col1)+$(segm $col2)+$(segm $col3)+$(segm $col4)+\n"
        done
    else
        return 0
    fi
}
###########################################################################################
#                            MENU CONTROL FUNCTIONS                                       #
###########################################################################################
function clean_exit () {
    local -i excode=${1:-0}
    unset Cid CustomerName CloudInsightUrl DeploymentId DeploymentName Head InputFile AppMode
    unset CidSet DepidSet FileSet CidrSet TestRun CheckExistence SkipValidation TargetSet Debug
    unset IPTargets DNSTargets dset cset 
    if (( excode != 0 )); then { echo -e "${MAG}FATAL${NC} script exited with abnormal status or fail code:[${YEL}${excode}${NC}]"; exit 1; }
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
        echo -e "${RED}ERROR${NC} Function or command:[${YEL}$cmd${NC}] was not found. Exiting."
        exit 1
    fi
    if [[ $validated == true ]]; then
        echo -e "${YEL}NOTE${NC} Condition was validated; skipping function:[${YEL}$cmd${NC}]"
    else # if any random crap was input, still run the function
        "$cmd"
    fi
}
###########################################################################################
#                            PARSE COMMAND LINE OPTIONS                                   #
###########################################################################################
#function fortest () {
declare -i postat opterr
declare parsed_opts dset=false cset=false
[[ $# -eq 0 ]] && { echo -e "WARNING - No input parameters [$#] were found on stdin. Running with default settings."; }
getopt -T > /dev/null; opterr=$?  # check for enhanced getopt version
if (( $opterr == 4 )); then  # we got enhanced getopt
    declare Long_Opts=cid:,cidr:,deployment-id:,delete-targets,delete,list-mode,list,skip-exist,skip-existence-check,skip-validation,targets-from-file:,testrun,debug,help 
    declare Opts=c:r:d:xlsvf:tbh
    ! parsed_opts=$(getopt --longoptions "$Long_Opts" --options "$Opts" -- "$@") # load and parse options using enhanced getopt
    postat=${PIPESTATUS[0]}
else 
    ! parsed_opts=$(getopt c:r:d:xlsvf:tbh "$@") # load and parse avail options using original getopt
    postat=${PIPESTATUS[0]}
fi
if (( $postat != 0 )) || (( $opterr != 4 && $opterr != 0 )); then # check return and pipestatus for errors
    echo -e "ERROR - invalid option was entered:[$*] or missing required arg."
    manage_ext_target_usage
    exit 1 
else 
    eval set -- "$parsed_opts"  # convert positional params to parsed options ('--' tells shell to ignore args for 'set')
    while true; do 
        case "${1,,}" in
            -c|--cid )                  { { [[ -n "$2" ]] && Cid=$(san "$2"); cset=true; }; shift 2; } ;;
            -r|--cidr )                 { { [[ "$2" =~ $_CIDR_REGEX ]] && Cidr=$(san "$2"); CidrSet=true; }; shift 2; } ;;
            -d|--deployment-id )        { { [[ -n "$2" ]] && DeploymentId=$(san "$2"); dset=true; }; shift 2; } ;;
            -x|--delete-targets|--delete )  { AppMode='delete'; shift 2; } ;;
            -l|--list|--list-mode)      { AppMode='list'; shift; } ;;
            -s|--skip-existence-check|--skip-exist ) { CheckExistence=false; shift; } ;;
            -v|--skip-validation )      { SkipValidation=true; shift; } ;;
            -f|--targets-from-file)     { { [[ -f "$2" ]] && InputFile=$(realpath "$2"); FileSet=true; }; shift 2; } ;;
            -t|--testrun )              { TestRun=true; shift; } ;;
            -b|--debug )                { Debug=true; shift; } ;;
            -h|--help )                 { manage_ext_target_usage; shift && exit 0; } ;;
            --) shift; break ;;  # end of options            
        esac
    done
fi
if $TestRun; then 
    echo -e "${YEL}NOTE${NC} test run mode enabled; no changes will be made."
    SkipValidation=true
    CheckExistence=false
fi
Head="x-aims-auth-token: ${auth_token}"
if $cset && [[ $Cid =~ $_NUM_REGEX ]]; then
    CustomerName=$(cid_exists "$Cid" | tr -d $'\n')
    if [[ -n "$CustomerName" ]]; then
        get_cloudinsight_url "$Cid"
        CidSet=true
    else
        echo -e "${YEL}WARNING${NC} the CID entered at the command-line could not be validated.\nYou will be prompted to enter it."
        CidSet=false
    fi
fi
if $CidSet && $dset; then
    DeploymentName=$(validate_deployment "$DeploymentId")
    if [[ -n "$DeploymentName" ]]; then
        DepidSet=true
    else
        echo -e "${YEL}WARNING${NC} the deployment ID entered at the command-line could not be validated.\nYou will be prompted to select one."
        DepidSet=false
    fi
fi
if $CidSet && $DepidSet && $TargetSet && [[ -z "$AppMode" ]]; then
    # this is enough info to proceed non-interactively using defaults
    declare -a Templist
    echo -e "${CYA}INFO${NC} all required parameters were set, but the default mode is to ADD the targets you entered via CIDR or file."
    echo -e "${YEL}Are you sure you want to continue? (Y|N)"
    read -rp "Press Y or N: " cont_choice
    if [[ "${cont_choice^^}" == 'Y' ]]; then 
        echo -e "Proceeding non-interactively..."
        if $CidrSet; then 
            check_item_type "$Cidr" 
        elif $FileSet; then
            rmcr "$InputFile" && readarray -t Templist <<< "$(<$InputFile)"
            check_item_type "${Templist[@]}"
        fi
        confirm_menu 'add'
    fi
elif $CidSet && $DepidSet && $TargetSet && [[ "$AppMode" == 'delete' ]]; then
    if $CidrSet; then 
        input_validation  '-' "$Cidr" 
    elif $FileSet; then
        rmcr "$InputFile" && readarray -t Templist <<< "$(<$InputFile)"
        input_validation '-' "${Templist[@]}"
    fi
    confirm_menu 'delete'
else
    # proceed with interactive prompts to gather required info
    echo -e "${YEL}WARNING${NC} not all required parameters were set; proceeding with interactive prompts to gather required info..."
    main_menu
    case "$AppMode" in
        'add') {
            _runmode_ $CidSet get_cid_menu
            _runmode_ $DepidSet get_deployment_menu
            _runmode_ $TargetSet add_targets_menu
            general_options_menu
            confirm_menu 'add'
        } ;;
        'delete') {
            _runmode_ $CidSet get_cid_menu
            _runmode_ $DepidSet get_deployment_menu
            _runmode_ $TargetSet delete_targets_menu
            general_options_menu
            confirm_menu 'delete'
        } ;;
        'list') {
            _runmode_ $CidSet get_cid_menu
            _runmode_ $DepidSet get_deployment_menu
            list_exttargets_menu
        } ;;
    esac   
fi
#}
