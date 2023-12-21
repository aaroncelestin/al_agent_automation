#!/usr/bin/sh
# Alert Logic Agent Installer $a_version
# Copyright Alert logic, Inc. 2022. All rights reserved.
##########################################################################################################
# ENTER YOUR REGISTRATION KEY HERE. Your key can be found in the Alert Logic console.
# In the console, click the hamburger menu. Click Configure > Deployments. Select the DataCenter deployment
# this agent will reside in. Scroll in the left nav menu to the bottom and click Installation Instructions.
# Copy the Unique Registration Key and paste it below between the double quote marks. Make sure to enable 
# the line by removing the # symbol at the beginning of the line.
#
    # key="YOUR_REGISTRATION_KEY_HERE"
#
##########################################################################################################

usage_text="$(cat <<-EOF 
--------------Alert Logic Agent Installer $a_version----------------

script_usage: "$sn" [-key <key>] | [-help]
    
    -key <key>      The key to provision the agent with.
    -help           Display this help message.
   
This script will check Linux virtual machines' init and pkg manager configurations and then install the appropriate Alert 
Logic Agent. It will also check for SELinux and semanage utilities to allow log traffic. If semanage (python utils) is not
installed, this script will download and install policycoreutils which include semanage using the native software manager 
(yum/apt/zypper). Then it will modify all necessary syslog config files for log forwarding, restart the rsyslog service,
and finally will start/restart the Alert Logic agent service. 

NOTE: In AWS, use SSM to deploy this script to target Linux EC2 VMs.
NOTE: In Azure, use Azure Cloud Shell to deploy this script to the target Linux VMs.
Refer to Alert Logic documentation for more information.
            
For DataCenter deployments, a registration key must be used. There are two ways to supply the key:
    1. Paste the key directly into the script and uncomment the line by removing the #.
    2. Supply the key as an argument to the script. The key its the only argument the script accepts.
    
For cloud based virtual machines (AWS and Azure) no registration key is required.     

Example: >" $sn "-key '1234567890abcdef1234567890aabcdef1234567890abcdef'
Example: > source  "$sn" -key '1234567890abcdef1234567890aabcdef1234567890abcdef'
Example: > ./"$sn" -help

It is strongly advised that this installer be run with sudo privileges to ensure correct installation and configuration 
of the agent.

For any additional help, contact Alert Logic Technical Support.                
EOF
)"

script_usage () 
{
    sn=$(echo "$0" | sed 's/..//')
    echo "$usage_text"   
}
#################################### OPTIONAL CONFIGURATION ##############################################
# If you have set up a proxy, and you want to specify the proxy as a single point of egress for agents to use, uncomment one of
# the lines below and set either the proxy IP address or the hostname.
# NOTE: A TCP or an HTTP proxy may be used in this configuration.
# proxy_ip="192.168.1.1:8080"
# proxy_host="proxy.example.com:1234"

# Syslog configuration options. The script will try to ascertain whether ng-syslog or rsyslog is installed and configure the appropriate file. If that fails, you 
# can specify the file to be used here. If you are collecting syslogs in a non-standard folder set the file path here.
syslogng_conf_file='/etc/syslog-ng/syslog-ng.conf'
syslog_conf_file='/etc/rsyslog.conf'
rsyslogng_text='destination d_alertlogic {tcp("localhost" port(1514));};
log { source(s_sys); destination(d_alertlogic); };'
rsyslog_text='*.* @@127.0.0.1:1514;RSYSLOG_FileFormat'
agent_docs_url='https://docs.alertlogic.com/requirements/agent.htm?tocpath=Requirements%7C_____4'
journ_conf_file='/etc/systemd/journald.conf'
fts_yes='ForwardToSyslog=yes'
semx_none='Port tcp/1514 is not defined'
semx_exists='Port tcp/1514 already defined'
err_no_file='no such file or directory'
err_no_cmd='command not found'
als_no_run='al-agent is NOT running.'
als_is_run='al-agent is running with pid'

# Packages will be linked but only downloaded when the agent is ready to be installed.
deb32='https://scc.alertlogic.net/software/al-agent_LATEST_i386.deb'
deb64='https://scc.alertlogic.net/software/al-agent_LATEST_amd64.deb'
deb64arm='https://scc.alertlogic.net/software/al-agent_LATEST_arm64.deb'
rpm32='https://scc.alertlogic.net/software/al-agent-LATEST-1.i386.rpm'
rpm64='https://scc.alertlogic.net/software/al-agent-LATEST-1.x86_64.rpm'
rpmarm='https://scc.alertlogic.net/software/al-agent-LATEST-1.aarch64.rpm'

# Constants
a_version='1.0.2'
init_agent='/etc/init.d/al-agent'

# Check whether RPM or DEB is installed
get_pkg_mgr () 
{
    if [ -n "$(which dpkg)" ]; then       
        echo "dpkg"
    elif [ -n "$(which rpm)" ]; then        
        echo 'rpm'
    else
        echo 'Unable to determine package manager. Exiting. '
        script_usage      
        exit 1
    fi
}

# Check CPU Architecture
get_arch ()
{
    arch=$(uname -m)
    if [ "$arch" = 'x86_64' ]; then
        echo 'x64'
    elif [ "$arch" = 'i586' ] || [ "$arch" = 'i686' ]; then
        echo 'x32'
    elif  [ "$arch" = 'arm' ] || "$arch" = 'ARM' ]; then
        echo 'ARM'
    else
        echo "Unsupported architecture: $arch"
        script_usage
        exit 1
    fi
}


# Setup and install the agent
install_agent () 
{
    arch_type=$(get_arch)
    pkg_mgr=$(get_pkg_mgr)
    if [ "$pkg_mgr" = 'dpkg' ]; then
        case "$arch_type" in
            'x64' )
                { curl "$deb64" --output al-agent.x64.deb; sudo dpkg -i al-agent.x64.deb; };;
            'x32' )
                { curl "$deb32" --output al-agent.x86.deb; sudo dpkg -i al-agent.x86.deb; };;
            'ARM' )
                { curl "$deb64arm" --output al-agent.arm.deb; sudo dpkg -i al-agent.arm.deb; };;
        esac   
    elif [ "$pkg_mgr" = 'rpm' ]; then
        case "$arch_type" in
            'x64' )
                { curl "$rpm64" --output al-agent.x86_64.rpm; sudo rpm -U al-agent.x86_64.rpm; };;
            'x32' )
                { curl "$rpm32" --output al-agent.i386.rpm; sudo rpm -U al-agent.i386.rpm; };;
            'ARM' )
                { curl "$rpmarm" --output al-agent.arm64.rpm; sudo rpm -U al-agent.arm64.rpm; };;
       esac
    fi        
}

# Configure the agent options
configure_agent () {
    if [ -n "$REG_KEY" ]; then
        sudo "$init_agent" provision --key "$REG_KEY"
    fi
    if [ -n "$proxy_ip" ]; then
        sudo "$init_agent" configure --proxy "$proxy_ip"
        echo "Proxy IP set $proxy_ip"
    
    elif [ -n "$proxy_host" ]; then
        sudo "$init_agent" configure --proxy "$proxy_host"
        echo "Proxy host set $proxy_host"
    fi
}

# helper functions to check if the syslog conf has been modified
_check_rsyslog () { grep "$rsyslog_text" "$syslog_conf_file" 2>/dev/null; }
_check_rsyslog_ng () { grep "$rsyslogng_text" "$syslogng_conf_file" 2>/dev/null; }
_yum_install_rsyslog () { sudo yum install rsyslog -y && sudo systemctl enable rsyslog && sudo systemctl start rsyslog; }

_os_is_aws_linux ()
{
    local nix_id=$(grep -r "\bID\b" /etc/os-release | cut -d= -f2 | sed 's/\"//g' 2>/dev/null)
    local nix_vers=$(grep -r "\bVERSION\b" /etc/os-release | cut -d= -f2 | sed 's/\"//g' 2>/dev/null)
    if [ "$nix_id" = "amzn" ]; then 
        if [ "$nix_vers" = "2022" ] || [ "$nix_vers" = "2023" ] || [ "$nix_vers" = "2" ]; then
            echo true
        fi
    else
        echo false
    fi
}

_configure_journald () 
{
    if [ -f "$journ_conf_file" ]; then 
        ftsline=$(grep -n 'ForwardToSyslog' "$journ_conf_file")                             # returns 35:#ForwardToSyslog=no
        [ -n "$ftsline" ] && { line_num=$(echo "$ftsline" | cut -d: -f1); }                 # returns 35 (line number)
        [ -n "$line_num" ] && { set_fts=$(echo "$ftsline" | cut -d: -f2 | cut -d= -f2); }   # returns no|yes
        if [ "$set_fts" = 'yes' ]; then                                                     
            sudo sed -i "${line_num} s/^##*//" "$journ_conf_file"                                # just uncomment line if set_fts was 'yes'
        elif [ "$set_fts" = 'no' ] && [ -n "$line_num" ]; then
            sudo sed -i "${line_num} s/.*/${fts_yes}/" "$journ_conf_file"                        # if set_fts was 'no' replace line with fts_yes 
        else
            echo "ERROR: failed to update journald config file, no matching rsyslog forwarding rules were found in $journ_conf_file"
            return 13
        fi
    else
        echo "ERROR: journald config file $journ_conf_file was not found"
        return 14
    fi
}

# Configure SYSLOG Collection
make_syslog_config () {
    if [ -f "$syslogng_conf_file" ]; then
        if [ -z "$(_check_rsyslog_ng)" ]; then    # if rsyslog-ng.conf was not modified
            echo "$rsyslogng_text" | sudo tee -a "$syslogng_conf_file"              # add the necessary lines
            if [ -n "$(_check_rsyslog_ng)" ]; then                                  # confirm it was added
                sudo systemctl restart syslog-ng                                    # restart syslog-ng service
                echo "SUCCESS rsyslog-ng config file $syslogng_conf_file was successfully modified."
            else
                echo "ERROR: rsyslog-ng config file could not be updated."; exit 1
            fi
        elif [ -n "$(_check_rsyslog_ng)" ]; then
            echo "WARNING: rsyslog-ng was already configured. No changes were made to $syslogng_conf_file"
        fi
    elif [ -f "$syslog_conf_file" ]; then  
        if [ -z "$(_check_rsyslog)" ]; then   # if rsyslog.conf was not modified
            echo "$rsyslog_text" | sudo tee -a "$syslog_conf_file"              # add the necessary line
            if [ -n "$(_check_rsyslog)" ]; then                                 # confirm it was added
                sudo systemctl restart rsyslog                                  # restart syslog service
                echo "SUCCESS: rsyslog config file $syslog_conf_file was successfully modified."
            else
                echo "ERROR: rsyslog config file could not be updated."; exit 1
            fi
        elif [ -n "$(_check_rsyslog)" ]; then
            echo "WARNING: rsyslog was already configured. No changes were made to $syslog_conf_file"
        fi
    elif $(_os_is_aws_linux) && [ ! -f "$syslog_conf_file" ] && [ ! -f "$syslogng_conf_file" ]; then
        echo "INFO: Host is Amazon Linux $(grep -r "\bVERSION\b" /etc/os-release | cut -d= -f2 | sed 's/\"//g' 2>/dev/null)"
        echo "INFO: Installing rsyslog from Centos/RHEL repos..."
        sleep 2s
        if _yum_install_rsyslog ; then
            echo "INFO: Modifying journald to forward logs to rsyslog. Please wait..."
            sleep 2s
            if _configure_journald ; then 
                echo "Configuring rsyslog to forward all logs to AlertLogic agent..."
                sleep 2s
                make_syslog_config # recurse once to config rsyslog after its been installed
            else
                echo "ERROR: journald configuration failed"
                return 15
            fi
        else
            echo "ERROR: rsyslog installation failed"
            return 16
        fi    
    else
        echo 'ERROR: Linux Distro could not be determined and rsyslog configuration file was not found.'
        echo "Check to ensure this distro is supported by AlertLogic Agent here: $agent_docs_url"
        echo 'If this distro is supported, then you may have to configure rsyslog manually.'
        exit 1
    fi
}

check_enforce () {
    if [ -z "$(which getenforce 2>&1)" ]; then
        echo "INFO: SELinux is not enabled. Semanage utils will not be installed."
    elif [ -n "$(which getenforce 2>&1)" ]; then
        if [ "$(getenforce 2>&1)" = 'Disabled' ] || [ "$(getenforce 2>&1)" = 'Permissive' ]; then
            echo "INFO: SELinux is enabled but is Disabled or Permissive. Semanage utils will not be installed."
        elif [ "$(getenforce 2>&1)" = 'Enforcing' ]; then
            if [ -z "$(which semanage 2>&1)" ]; then
                echo "WARNING: SELinux is enforcing but semanage tools are not available. Semanage tools must be installed for port configuration."
                echo "INFO: Installing semanage with policycoreutils python utils package..."       
                if [ -n "$(command -v apt 2>&1)" ]; then
                    echo "INFO: using apt to install policycoreutils..."
                    sudo apt install policycoreutils-python-utils -y
                elif [ -n "$(command -v zypper 2>&1)" ]; then
                    echo "INFO: using zypper to install policycoreutils..."
                    sudo zypper install --no-confirm policycoreutils-python-utils
                elif [ -n "$(command -v yum 2>&1)" ]; then
                    echo "INFO: using yum to install policycoreutils..."
                    sudo yum install policycoreutils-python-utils -y
                fi
                check_enforce # run this function again after semanage tools install
            elif [ -n "$(which semanage 2>&1)" ]; then
                echo "INFO: SELinux is enabled and in enforcing mode and semanage tools are available."
                echo "INFO: Checking if port exclusion rule has already been added..."
                sleep 1s
                semx_stat=$(sudo semanage port -a -t syslogd_port_t -p tcp 1514 2>&1)
                if [ -n "$(echo "$semx_stat" | grep -F "$semx_exists")" ]; then
                    echo "INFO: port exclusion rule for tcp 1514 was found in semanage configuration." 
                elif [ -n "$(echo "$semx_stat" | grep -F "$semx_none")" ]; then
                    echo "INFO: port exclusion rule was not yet added to semanage configuration."
                    echo "INFO: creating port exclusion rule using semanage, please wait..."
                    sudo semanage port -a -t syslogd_port_t -p tcp 1514
                else
                    echo "ERROR: semanage port status returned unexpected data: $semx_stat"
                fi
            fi
        else
            echo "ERROR: SELinux is enabled but semanage status could not be determined. Contact your administrator."
            exit 1
        fi
    fi
}

# Install the agent and configure it
run_install () {
    install_agent
    check_enforce
    configure_agent
    make_syslog_config
    agent_svc_stat=$(sudo "$init_agent" status 2>&1)
    if [ -n "$(echo "$agent_svc_stat" | grep -F "$als_no_run")" ]; then
        sudo "$init_agent" start
        if [ -n "$(pgrep al-agent)" ]; then
            echo "INFO: Agent service was started. Install complete."
        fi    
    elif [ -n "$(echo "$agent_svc_stat" | grep -F "$als_is_run")" ]; then
        echo "INFO: Agent service already running. Restarting..."
        sudo "$init_agent" restart     
        if [ -n "$(pgrep al-agent)" ]; then
            echo "Agent service was restarted. Install complete."
        fi    
    elif [ -n "$(echo "$agent_svc_stat" | grep -F "$err_no_file")" ]; then
        echo "ERROR: Agent service file was not found at $init_agent. Verify package was installed"
        exit 1
    elif [ -n "$(echo "$agent_svc_stat" | grep -F "$als_no_cmd")" ]; then
        echo "ERROR: Agent service command was not found. Check your permissions to the init folder $init_agent"
        exit 1
    fi
}

_to_upper () { echo "${@}" | sed 's/.*/\U&/g'; }

# Get command line args and Start script processing
if [ "$(_to_upper "$1")" = '-KEY' ] || [ "$(_to_upper "$1")" = '--KEY' ] || [ "$(_to_upper "$1")" = "-K" ]; then
    if [ -z "$2" ]; then
        echo "Key switch (-k|--key) set but no registration key was provided. Exiting."
        script_usage
        exit 1
    else
        REG_KEY="$2"
        printf '%s\n' " REG KEY is $REG_KEY" " Running install." " Please wait..."
        sleep 2s
        run_install
    fi
elif [ "$1" = "-help" ]; then
    script_usage
    exit 0
elif [ $# = 0 ] && [ -n "$REG_KEY" ]; then
    echo  "REG KEY was retrieved from script section: $REG_KEY"
    run_install
elif [ $# = 0 ] && [ -z "$REG_KEY" ]; then
    echo "No registration key provided. Check if agent script is in Cloud Environment (AWS, Azure)."
    echo "Installation proceeding without a key. If agent is installed in a Datacenter environment, it will not provision without a key!"
    run_install
else
    echo  "Invalid option(s): $*. Exiting."
    script_usage
    exit 1
fi
#END SCRIPT

