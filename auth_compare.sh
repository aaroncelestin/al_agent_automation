#!/usr/bin/bash
set -o pipefail
declare AuthScriptVersion=2.10_202502014
declare -x NC=$(tput sgr0)
declare -x RED=$(tput setaf 1)
declare -x GRE=$(tput setaf 2)
declare -x YEL=$(tput setaf 3)
declare -x CYA=$(tput setaf 6)
declare -x BLU=$(tput setaf 4)
declare -x MAG=$(tput setaf 5)
declare ForceRefresh=false RemoveToken=false AimsAuthTokenExpiry SecretKeyHash AccessKeyId InsecureSecretKey 
declare IsTokenSet=false IsTokenValid=false RunMain=true UseNativeJsonParser=false
declare OldSSL=false
declare SigKey=$(openssl rand -hex 8 2>/dev/null)
declare -i Ak_Length_=16
declare -A Auth_Object 
declare -a auth_aliases=( auth_token token AL_TOKEN TOKEN AUTH_TOKEN AIMS_TOKEN AIMS_AUTH_TOKEN )
declare eline='+============================================================================+'
declare sline='------------------------------------------'
############################################################################################
#                 GET AND SETUP YOUR AUTHENTICATION TOKEN FOR API ACCESS
############################################################################################
[[ -z $(which jq 2>/dev/null) ]] && { UseNativeJsonParser=true;  echo -e "${YEL}WARNING${NC} JSON utility \"JQ\" was not found, using \"Native(lol)\" JSON Parser: regex to get and set the token. Extended features like UserName and ExpirationDate are not supported."; }
# NOTE: If you are not concerned with the security of your secret key, you can put your access key and secret key IDs here and the script will run with no more interaction required from you
# AccessKeyId=''
# InsecureSecretKey=''
# check for old versions of OpenSSL that did not have password based key derivation functions
declare -a vss
IFS=. read -ra vss <<< "$(openssl version | grep -Pio '([0-9]?\.[0-9]?\.[0-9]?)+')"
(( ${vss[0]} <= 1 && ${vss[1]} < 1 && ${vss[2]} <= 2 )) && { OldSSL=true; }
# encrypt secretkey using SigKey which is a randomly generated string and stored for decryption later
encrypt_sk () { 
    local in="$*"
    if $OldSSL; then
        openssl enc -e -aes-256-cbc -a -md sha256 -pass pass:"$SigKey" <<< "$in"
    else
        openssl enc -e -des3 -a -pass pass:"$SigKey" -pbkdf2 <<< "$in"
    fi 
} 
# try to decrypt incoming text using Sigkey
decrypt_sk () { 
    local in="$*"
    if $OldSSL; then
        openssl enc -d -aes-256-cbc -a -md sha256 -pass pass:"$SigKey" <<< "$in"
    else
        echo "$in" | openssl enc -d -des3 -a -pass pass:$SigKey -pbkdf2
    fi    
} 
# NOTE: You could probably store these in a separate file or encrypt them by encoding them in Base64 or encrypt with GPG or openssl 
# NOTE: this token expires every 8 hours so you will have to refresh it if you haven't run it in a while
############################################################################################
##################### TEST STUFF ##########################
#test_token='thisisafaketokenUzI1NiIsImprdSI6Imh0dHBzOi8vYXBpLmdsb2JhbC5hbGVydGxvZ2NywiaWF0IjoxNzM3NzQxNjk3LCJpc3MiOiJodHRwczovL2FsZXJ0bG9naWMuY29tLyIsInN1YiI6ImFpbXN8Mjp1c2VyOjNBRDkxMTQ3LTk5MDYtNERCMi04RTg4LTJDQjZDOUQwMUQ1NiIsInZlcnNpb24iOiJ2MyJ9.FcLjE35Y8SQ1Xc4QG788UI4Ff0mUWsLTaNMgRxjVV6HhOkGKUZrRhiNIZzIB84J4YsSMwnGQJqemLYOhdMQ4vBz6y_RGkI0GWlP2KwdXGnUPrmzmE2HeL65VylLmzsMWphfZbC7Sgp_mG2n5lh6khFUNr-CYfCYIHO37tDw_LHv_gRU1vpNoKFbcJTaLaw88yQWutlZZEUJKMqsqCAkYy7SYXKDXaR2vF1ch1r74RC-h3Tu6T7aljmcfElnCJ5G3ooUIj4qkPHQwFdTZnaTgKY_-_O_34cZw-BkNIStDFsZW2O1XtRnJdZ40PZf7TLXKj4Mkk5PihTLuuPHbIhjZUg'
#Auth_Object[name]='Test User'
#Auth_Object[token]=$test_token
#Auth_Object[expiry]=1837985807 # expires 2028
#AimsAuthTokenExpiry="${Auth_Object[expiry]}"
###########################################################
segm () { local -i w=$1; for ((i=0;i<$w;i++)); do echo -en '-'; done; echo; }
auth_script_title () { echo -e "${CYA}$eline\n|${NC}\t    ${YEL}AIMS Authentication Token Generation Shell Script${NC}\t\t     ${CYA}|${NC}"
    echo -e "${CYA}|${NC}\t\t\tVersion: $AuthScriptVersion\t\t\t\t     ${CYA}|${NC}"; echo -e "${CYA}$eline${NC}"; }
auth_script_usage () {
    local -i exit_code=${1:-0}
    local -i scrw=$(( $(tput cols) * 2/3 ))
    echo
    echo -e "${GRE}DESCRIPTION${NC}:\n$sline"
    local ins1="This script will take your AlertLogic credentials (access_key and secret_key) and generate an authentication token so you can make API calls using an AIMS authentication token. You have several options to get the access key \
and secret key into this script: you can enter them from the command line when you source the script or you can run the script and it will prompt you for your access_key and secret ID, or you can hard-code them in the script itself.  Using the \
prompt is the most secure way, since the secret key is encrypted immediately with a randomly-generated key that is internal only to the script itself. THis is also the most inconvenient since the credentials will have to be added on every run. \
After entering your access and secret keys and a token is generated, the token is then stored in a variable which can subsequently be exported to the shell. Please note that, in order to export environment variables to the shell, you must \"source\" \
this script when you run it. Check the \"EXAMPLES\" section for suggested usage syntax."
    fold -w $scrw -s <<< "$ins1"
    echo -e "\n${GRE}INSTRUCTIONS${NC}:\n$sline"
    echo -e "${MAG}Step 1${NC} - ${YEL}Create an Access Key and Secret Key${NC}:"
    echo -e "\tTo get API creds, modify the link below by adding your Parent Account CID, then copy-and-paste it into your browser. This will take you to the Users Section of the Alertlogic console:"
    echo -e "\t    ${BLU}https://console.alertlogic.com/#/account/users?aaid=${MAG}<CID>${BLU}&locid=defender-us-ashburn${NC}"
    echo -e "\t    1. Click on your name and click the \"Access Keys\" tab"
    echo -e "\t    2. Click \"Generate New Key\""
    echo -e "\t    3. Copy the Access Key and Secret Key or download the key file"
    echo -e "${MAG}Step 2${NC} - ${YEL}Enter the Access Key and Secret Key Into the Script (Choose A Method Below)${NC}:"
    echo -e "\t${YEL}Opt A${NC}: Enter Creds at Interactive Prompts (default):"
    echo -e "\t    If you just run the script with no options, you will be prompted to enter your access and secret key. This is the default and the most secure option. "
    echo -e "\t${YEL}Opt B${NC}: Hard-Code Creds In The Script Itself:"
    echo -e "\t    1. Copy and paste the Access Key ID and Secret Key into this script near the top, under the section that says: "
    echo -e "\t\t\"GET AND SETUP YOUR AUTHENTICATION TOKEN FOR API ACCESS\""
    echo -e "\t    2. Save the script"
    echo -e "\t${YEL}Opt C${NC}: Enter Creds As Script Arguments:"
    echo -e "\t    When running the script at the command line, you can enter your access and secret key with option switches. Check the OPTIONS section below for more information."
    echo -e "${MAG}Step 3${NC} - ${YEL}Source the Script${NC}:"
    echo -e "\tRun (source) the script using the flags below in the OPTIONS section."
    echo -e "\tIf you encrypted your secret key, you must encode it in base64. Currently, only the DES3 cipher with PBKDF2 key derivation is supported. Will add more ciphers if requested."
    echo -e "${RED}NOTE${NC}: if no access or secret key is hard-coded and none is input on the command line (see OPTIONS below), then you WILL be prompted to enter the keys manually."
    echo -e "\n${GRE}OPTIONS${NC}:\n$sline" 
    local -a options=(
        '--refresh,-rR, ,Force refresh AIMS authentication token even if the existing token is not yet expired.'
        '--encrypted,-eE,<encryption key>,Optionally encrypt the secret key input on stdin and enter the key here.'
        '--access_key,-aA,<access key>,Enter the access key from AlertLogic console.'
        '--secret_key,-sS,<secret key>,Enter the secret key from AlertLogic console.'
        '--remove,-cC, ,Unset and remove all exported AIMS authentication token environment variables.'
        '--debug,-dD, ,Run this script in debug mode.'
        '--help,-hH, ,Display this help message.'
    )
    for opt in "${options[@]}"; do
        IFS=, read -r long short arg desc <<< "$opt"
        printf "${YEL}%15s${NC}|${YEL}%s${NC} ${CYA}%-17s${NC} # %-42s\n" "$long" "$short" "$arg" "$desc"
    done
    echo -e "\n${GRE}EXAMPLES${NC}:\n$sline\n    >_localhost\$ ${GRE}source auth_v2.sh${NC}\t\t\t# default with no options"
    echo -e "    >_localhost\$ ${GRE}source auth_v2.sh --refresh${NC}\t\t# force refresh auth token${NC}"
    echo -e "    >_localhost\$ ${GRE}source auth_v2.sh --access_key abc1234def --secret_key qwertyuipopsdajklhfaks ${NC}\t# manually input access key and secret key${NC}"
    echo -e "    >_localhost\$ ${GRE}source auth_v2.sh -a abc1234def -s la96re13whg32mnetrkbnh2 -e 'password1234' ${NC}\t# same as above but the secret key is encrypted${NC}"
    echo -e "$sline"
    echo -e "${YEL}NOTE${NC}: this token expires every 8 hours so you will have to refresh it if you haven't used it in a while."
    echo
    return $exit_code
}
get_access_key_from_user () {
    local input
    read -rp "Please enter the AccessKeyId: " input
    if [[ -n "$input" && ${#input} -eq $Ak_Length_ ]]; then
        AccessKeyId=$(tr -dc '[:alnum:]' <<< "$input") &&  echo -e "${GRE}OKAY${NC} access key:[${YEL}${AccessKeyId}${NC}] was added."
    else
        echo -e "${RED}ERROR${NC} Invalid access key:[${YEL}${AccessKeyId}${NC}] was entered."
        auth_script_usage 2
    fi
}
check_for_embedded_auth_info () {
    if [[ -z "$AccessKeyId" ]]; then
        echo -e "${YEL}WARN${NC} AccessKeyId was not found in the script nor was it entered as an input parameter. Please enter AccessKeyId manually."
        get_access_key_from_user
    elif [[ -n "$AccessKeyId" ]]; then
        echo -e "${CYA}INFO${NC} AccessKeyId was found."
    fi
    if [[ -z "$InsecureSecretKey" ]] && [[ -z "$SecretKeyHash" ]]; then 
        echo -e "${YEL}WARN${NC} No SecretKeys (raw or encrypted) were found in the script nor as an input parameter. Please enter the SecretKey manually."
        get_secret_key_from_user
    elif [[ -n "$InsecureSecretKey" ]]; then
        echo -e "${CYA}INFO${NC} Auth info was found."
        SecretKeyHash=$(encrypt_sk "$InsecureSecretKey")
    fi
}
get_secret_key_from_user () {
    local input
    local -i chars=0
    echo -e "${YEL}NOTICE${NC} when pasting your secret key here, it will be hidden on the terminal screen."
    local prompt="Please enter the secret key: "
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
    SecretKeyHash=$(encrypt_sk "$input") # hide and encrypt secret key
    if [[ -n "$SecretKeyHash" ]]; then
        echo -e "${GRE}OKAY${NC} Encrypted secret key of length:[${YEL}${#SecretKeyHash}${NC}] was added."
    else
        echo -e "${RED}ERROR${NC} Invalid or empty secret key of length:[${YEL}${#input}${NC}] was entered."
        auth_script_usage 3
    fi
}
check_shell_session_vars () {
    local exists=false # set default flag
    for var in "${auth_aliases[@]}"; do # iterate
        [[ "$(bash -c "echo \$${var}")" ]] && { exists=true; break; } # if exported var is found, set the flag and stop the loop
    done
    echo $exists # echo the result
}
check_token_expiration () {
    if [[ "$(bash -c 'echo ${AimsAuthTokenExpiry}')" ]] && (( ${AimsAuthTokenExpiry} > $(date +%s) )); then
        echo true
    else { echo false; }
    fi
}
authenticate_token () {
    local authapi="https://api.cloudinsight.alertlogic.com/aims/v1/authenticate"
    if $UseNativeJsonParser; then
        echo -e "${YEL}WARNING${NC} JSON utility \"JQ\" was not found, using \"Native(lol)\" JSON Parser: regex to get and set the token."
        ! local authjson=$(curl -s -X POST -u "${AccessKeyId}:$(decrypt_sk "$SecretKeyHash")" "$authapi")
        local -i error_=${PIPESTATUS[0]}
        if (( ${#authjson} > 100 )) && (( $error_ == 0 )); then
            Auth=$(grep -Pio '(?>token":")(.*)["],' <<< "$authjson" | cut -d: -f2)
            Auth=$(sed 's/\"//g' <<< "${Auth%,}")
            for alias in "${auth_aliases[@]}"; do
                export $alias="$Auth"
                echo -e " \$$alias"
            done
        else
            echo -e "${RED}ERROR${NC} AuthToken creation failed; AIMS API request failed with error:[${YEL}$error_${NC}] or did not return a JSON object of correct size:[${YEL}${#authjson}${NC}]"
            auth_script_usage 1
        fi
    else
        ! local authjson=$(curl -s -X POST -u "${AccessKeyId}:$(decrypt_sk "$SecretKeyHash")" "$authapi" | jq -rc)
        local -i error_=${PIPESTATUS[0]}
        if (( ${#authjson} > 100 )) && (( $error_ == 0 )); then
            Auth_Object[name]=$(jq -rc '.authentication.user.name' <<< "$authjson")
            Auth_Object[token]=$(jq -rc '.authentication.token' <<< "$authjson")
            Auth_Object[expiry]=$(jq -cr '.authentication.token_expiration' <<< "$authjson")
            echo -e "${CYA}INFO${NC} Variables exported:"
            export AimsAuthUser="${Auth_Object[name]}" && echo -e " \$AimsAuthUser with name:[$AimsAuthUser]"
            export AimsAuthTokenExpiry="${Auth_Object[expiry]}" && echo -e " \$AimsAuthTokenExpiry with date:[$AimsAuthTokenExpiry]"
            for alias in "${auth_aliases[@]}"; do
                export $alias="${Auth_Object[token]}"
                echo -e " \$$alias"
            done
            echo -e "${GRE}OKAY${NC} AuthToken for user:[${YEL}${Auth_Object[name]}${NC}] was set successfully.\nExpiration date of token:[${YEL}$(date -d @${AimsAuthTokenExpiry})${NC}]"
        else
            echo -e "${RED}ERROR${NC} AuthToken creation failed; AIMS API request failed with error:[${YEL}$error_${NC}] or did not return a JSON object of correct size:[${YEL}${#authjson}${NC}]"
            auth_script_usage 1
        fi
    fi
}
unset_token_info () {
    unset Auth_Object AimsAuthUser AimsAuthTokenExpiry
    for alias in "${auth_aliases[@]}"; do
        unset $alias
    done
    local rem=$(check_shell_session_vars)
    if ! $rem; then { echo -e "${GRE}OKAY${NC} All token variables were removed or unset"; }
    else { echo -e "${RED}ERROR${NC} Not all token variables could be removed."; }
    fi
}
process_main () {
    echo -e "${CYA}INFO${NC} Script started. Checking for existing auth tokens...\nPlease wait..."
    if $RemoveToken; then { unset_token_info; }
    elif $ForceRefresh; then
        echo -e "${CYA}INFO${NC} Forced refresh was enabled."
        check_for_embedded_auth_info
        authenticate_token
    elif ! $ForceRefresh; then
        IsTokenSet=$(check_shell_session_vars)
        if ! $IsTokenSet; then
            echo -e "${CYA}INFO${NC} No existing exported auth  tokens were found in this shell session."
            echo -e "${CYA}INFO${NC} Attempting to create a new auth token.\nPlease wait..."
            check_for_embedded_auth_info 
            authenticate_token
        elif $IsTokenSet && ! $UseNativeJsonParser; then
            IsTokenValid=$(check_token_expiration)
            if $IsTokenValid; then
                echo -e "${CYA}INFO${NC} AuthToken env var was found for user:[${YEL}${AimsAuthUser}${NC}] and it has not yet expired."
                echo -e "${CYA}INFO${NC} Todays date time:\t\t[${YEL}$(date)${NC}]"
                echo -e "${CYA}INFO${NC} Expiration date of token:\t[${GRE}$(date -d @$AimsAuthTokenExpiry)${NC}]"
                echo -e "To force refresh this token, source this script again with the --refresh option."
            elif ! $IsTokenValid; then
                echo -e "${CYA}INFO${NC} A valid auth token was found but is expired." 
                echo -e "${CYA}WARNING${NC} AuthToken for user:[${YEL}${AimsAuthUser}${NC}] has expired.\n${CYA}INFO${NC} Expiration date of token:[${RED}$(date -d @$AimsAuthTokenExpiry)${NC}]"
                check_for_embedded_auth_info
                authenticate_token
            fi
        elif $IsTokenSet && $UseNativeJsonParser; then
            echo -e "${YEL}WARNING${NC} Expiration date/time cannot be checked when using the \"Native\" JSON Parser, refreshing token..."
            check_for_embedded_auth_info
            authenticate_token
        fi
    else # this should be unreachable
        echo -e "${RED}ERROR${NC} Something went wrong. Some auth_token:[${CYA}${#auth_token}${NC}] was found but could not be validated."
    fi
}

# We can use this helper function to simulate the nameref feature introduced in Bash 4.3 for indirection, which allows us to explicitly create a pointer var. 
# The end result is that we can have two arrays as input parameters into another function and the end user is none the wiser! NOTE this function uses eval
# and some user input is passed to it which necessitates the cleaning using tr. No spaces, special chars (except underscores) or tokens are allowed in variable names, anyway. 
# USAGE: 
# Easiest most basic way is to call this function with just the name of the array variable without tokens or quotes: 
#   nameref mylist
# For variable array names, use the $var syntax, but leave ii unquoted:
#   nameref $var_array      
# That will spit out the contents of the array and you can catch the array for further manipulation like this:
#   declare -a output_array=( $(nameref $var_array) ) -- note the lack of double quotes
# For new-line separated arrays, you can catch the output array with 'readarray' like this:
#   readarray -t output_array < <(nameref $var_array)
# nameref version 0.19a_20250218
function nameref () { local aref=$(tr -dc '[:alnum:][=_=]' <<< "$1");  eval 'declare -a _output=( "${'"$aref"'[@]}" )'; for elem in "${_output[@]}"; do { echo "$elem"; } done; }


# Start Script
auth_script_title
declare -i postat opterr
declare parsed_opts
[[ $# -eq 0 ]] && { echo -e "${YEL}WARNING${NC} No input parameters [$#] were found on stdin. Running with default settings."; }
getopt -T > /dev/null; opterr=$?  # check for enhanced getopt version
if (( $opterr == 4 )); then  # we got enhanced getopt
    declare Long_Opts=refresh,access_key:,secret_key:,encrypted:,remove,debug,help 
    declare Opts=ra:s:e:cdh
    ! parsed_opts=$(getopt --longoptions "$Long_Opts" --options "$Opts" -- "$@") # load and parse options using enhanced getopt
    postat=${PIPESTATUS[0]}
else 
    ! parsed_opts=$(getopt ra:s:e:cd "$@") # load and parse avail options using original getopt
    postat=${PIPESTATUS[0]}
fi
if (( $postat != 0 )) || (( $opterr != 4 && $opterr != 0 )); then # check return and pipestatus for errors
    echo -e "${RED}ERROR${NC} invalid option was entered:[${YEL}$*${NC}] or missing required arg."
    auth_script_usage
else 
    eval set -- "$parsed_opts"  # convert positional params to parsed options ('--' tells shell to ignore args for 'set')
    while true; do 
        case "${1,,}" in
            -c|--remove)        { unset_token_info; RunMain=false; break; } ;;
            -r|--refresh)       { ForceRefresh=true; shift; } ;;
            -e|--encrypted)     { ExternalKey="${2}"; shift 2; } ;;
            -a|--access_key)    { AccessKeyId="${2}"; shift 2; } ;;
            -s|--secret_key)    { SecretKeyHash=$(encrypt_sk "${2}"); shift 2; } ;;
            -d|--debug)         { set -x; shift; } ;;
            -h|--help)          { auth_script_usage; RunMain=false; shift; break; } ;;
            --)                 { shift; break; } ;; # end of options
        esac
    done
fi
if $RunMain; then { process_main; } fi
set +x
