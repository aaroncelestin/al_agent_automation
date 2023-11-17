#!/bin/bash 
# Date: 2022-11-21
# AWS Shell Script Wrapper for Alert Logic Agent Configurator     
 sudo tee -a al_conf_gen.sh > /dev/null <<"EOT"
    #!/bin/bash 
    # Date: 2022-11-26
    # SSM Agent Configurator v1.2
    # Packages will be linked but only downloaded when the agent is ready to be installed.
    deb32="https://scc.alertlogic.net/software/al-agent_LATEST_i386.deb"
    deb64="https://scc.alertlogic.net/software/al-agent_LATEST_amd64.deb"
    deb64arm="https://scc.alertlogic.net/software/al-agent_LATEST_arm64.deb"
    rpm32="https://scc.alertlogic.net/software/al-agent-LATEST-1.i386.rpm"
    rpm64="https://scc.alertlogic.net/software/al-agent-LATEST-1.x86_64.rpm"
    rpmarm="https://scc.alertlogic.net/software/al-agent-LATEST-1.aarch64.rpm"
function get_pkg_mgr () {
    pkg_mgr=""
    if [[ -f /usr/bin/dpkg ]]; then       
        pkg_mgr="dpkg"
    elif [[ -f /usr/bin/rpm ]]; then        
        pkg_mgr="rpm"
    elif [[ -n "$(rpm --version)" ]]; then  # additional checks to verify which pkgmgr is installed in subshell     
        pkg_mgr="rpm"
    elif [[ -n "$(dpkg --version)" ]]; then  # the conditional checks are necessary because some distros have both rpm and  
        pkg_mgr="dpkg"                       # dpkg installed        
    else
        echo "Unable to determine package manager. Exiting."
        usage      
        exit 1
    fi
    echo "Package manager is $pkg_mgr"
}
# Check CPU Architecture
function get_arch () {
    thisarch=""
    arch=$(uname -i)
    if [[ $arch = "x86_64" ]]; then
        thisarch="x64"
    elif [[ $arch = "i*86" ]] || [[ $arch = i686 ]]; then
        thisarch="386"
    elif  [[ $arch = "arm*" ]]; then
        thisarch="ARM"
    else
        echo "Unsupported architecture: $arch"
        usage
        exit 1
    fi
    echo "Detected architecture is $arch"
}
# Setup and install the agent
function install_agent () {
    get_arch
    get_pkg_mgr
    if [[ $pkg_mgr = "dpkg" ]]; then
        case $thisarch in
            "x64" )
                curl $deb64 --output al-agent.x64.deb
                sudo dpkg -i al-agent.x64.deb
                ;;
            "386" )
                curl $deb32 --output al-agent.x86.deb
                sudo dpkg -i al-agent.x86.deb
                ;;
            "ARM" )
                curl $deb64arm --output al-agent.arm.deb
                sudo dpkg -i al-agent.arm.deb
                ;;
        esac   
    elif [[ $pkg_mgr = "rpm" ]]; then
        case $thisarch in
            "x64" )
                curl $rpm64 --output al-agent.x86_64.rpm
                sudo rpm -U al-agent.x86_64.rpm
                ;;
            "386" )
                curl $rpm32 --output al-agent.i386.rpm
                sudo rpm -U al-agent.i386.rpm
                ;;
            "ARM" )
                curl $rpmarm --output al-agent.arm64.rpm
                sudo rpm -U al-agent.arm64.rpm
                ;;
       esac
    fi        
}
# Get init configuration information
function get_init_config () {
    init_type=""
    if [[ $(ps --noheaders -o comm 1) = "systemd" ]]; then
        init_type="systemd"
    elif [[ $(ps --noheaders -o comm 1) = "init" ]]; then
        init_type="init"
    else
        echo "Unknown init configuration. Exiting."
        usage
        exit 1
    fi
    echo "Detected init type is $init_type"
}
# Configure the agent options
function configure_agent () {
    get_init_config
    if [[ -n "$REG_KEY" ]]; then
        sudo /etc/init.d/al-agent provision --key $REG_KEY
    fi
    if [[ -n "$proxy_ip" ]]; then
        sudo /etc/init.d/al-agent configure --proxy $proxy_ip
        echo "Proxy IP set $proxy_ip"
    
    elif [[ -n "$proxy_host" ]]; then
        sudo /etc/init.d/al-agent configure --proxy $proxy_host
        echo "Proxy host set $proxy_host"
    fi
}
# Configure SYSLOG Collection
function make_syslog_config () {
    syslogng="/etc/syslog-ng/syslog-ng.conf"
    syslog="/etc/rsyslog.conf"
    if [[ -f "$syslogng" ]] && [[ -z $( (grep -F "log { source(s_sys); destination(d_alertlogic); };" "$syslogng") 2>&1) ]]; then
        echo "destination d_alertlogic {tcp("localhost" port(1514));};" | sudo tee -a $syslogng
        echo "log { source(s_sys); destination(d_alertlogic); };" | sudo tee -a $syslogng
        if [[ $( tail -n 1 "$syslogng") = "log { source(s_sys); destination(d_alertlogic); };" ]]; then
            sudo systemctl restart syslog-ng
            echo "Agent rsyslogng config file $syslogng was successfully modified."
        fi
    elif [[ -f "$syslog" ]] && [[ -z $( (grep -F "*.* @@127.0.0.1:1514;RSYSLOG_FileFormat" "$syslog" ) 2>&1) ]]; then
        echo "*.* @@127.0.0.1:1514;RSYSLOG_FileFormat" | sudo tee -a $syslog
        if [[ $( tail -n 1 "$syslog") = "*.* @@127.0.0.1:1514;RSYSLOG_FileFormat" ]]; then
            sudo systemctl restart rsyslog
            echo "Agent rsyslog config file $syslog was successfully modified."
        fi
    elif [[ $(grep -F "*.* @@127.0.0.1:1514;RSYSLOG_FileFormat" "$syslog") ]]; then
        echo "rsyslog was already configured. No changes were made to $syslog"
        return
    elif [[ $(grep -F "log { source(s_sys); destination(d_alertlogic); };" "$syslogng") ]]; then
        echo "rsyslogng was already configured. No changes were made to $syslogng"
        return
    else
        echo "No syslog configuration file was found. Please configure rsyslog manually."
    fi
}
# Check for SELinux and then for tools to modify config files, if not there, install the tools and then do the config
function set_enforce () {
    if [[ $( getenforce 2>&1) == "command not found" ]]; then
        echo "SELinux is not enabled. Semanage utils will not be installed."
        return
    elif [[ $( getenforce 2>&1) == "Disabled" ]]; then
        echo "SELinux is enabled but getenforce is disabled. Semanage utils do not need to be installed."
        return
    elif [[ $( getenforce 2>&1) == "Permissive" ]]; then  
        echo "getenforce reported Permissive SELinux configuration."
        check_enforce
        return
    elif [[ $(getenforce 2>&1) == "Enforcing" ]]; then
        echo "getenforce reported Enforcing SELinux configuration."
        check_enforce
        return
    else
       echo "SELinux is enabled but semanage status could not be determined. Contact your administrator"    
       exit 1
    fi
}
#Check if semanage is available
function check_enforce
{
    setport="sudo semanage port -a -t syslogd_port_t -p tcp 1514"
    porterr="ValueError: Port tcp/1514 already defined"
    echo "Checking for SELinux semanage utilities."
    if [[ -n $(command -v semanage 2>/dev/null) ]]; then # if semanage is not zero (installed)
        echo "semanage is installed, setting SElinux configuration..."
        if [[ $( ($setport) 2>&1 ) == "$porterr" ]]; then
            echo "SELinux is enabled and semanage is installed but syslogd tcp port 1514 has already been set"
            echo "by semanage. Continuing syslog configuration script..."
            return
        elif [[ -n $($setport 2>&1) ]]; then # redirect any other errors to stdin
            echo "SELinux is in Permissive mode but the log forwarding port could not be configured."
            echo "$?"
            echo "Please check your SELinux configuration and try again."
            exit 1
        else
            "$setport"
            return
        fi
    elif [[ -z $(command -v semanage 2>&1) ]]; then # semanage is zero (not installed)
            echo "SELinux is enabled but semanage is not available."
            echo "Installing semanage with policycoreutils python utils package..."
            get_semanage
            "$setport"
    fi
}
#Check software manager and install semanage with policycoreutils
function get_semanage () 
{                  
    if [[ -n $(command -v apt 2>&1) ]]; then
        echo "using apt to install policycoreutils..."
        sudo apt install policycoreutils-python-utils -y
        return
    elif [[ -n $(command -v zypper 2>&1) ]]; then
        echo "using zypper to install policycoreutils..."
        sudo zypper install --no-confirm policycoreutils-python-utils
        return
    elif [[ -n $(command -v yum 2>&1) ]]; then
        echo "using yum to install policycoreutils..."
        sudo yum install policycoreutils-python-utils -y
        return    
    else
        echo "semanage tool could not be installed, contact your system administrator."
        exit 1    
    fi
    
}
# Install the agent and configure it
function run_install {
    if [[ -f /etc/init.d/al-agent ]]; then
        echo "Looks like the agent is already installed on this host. Checking al-agent service status..."
        if [[ $( (sudo /etc/init.d/al-agent status) 2>&1) =~ "al-agent is running" ]]; then
            echo "Agent service already running. Restarting..."
            sudo /etc/init.d/al-agent restart
            if [[ -n "$(pgrep al-agent)" ]]; then
                echo "Agent service was restarted."
            fi    
        elif [[ $( (sudo /etc/init.d/al-agent status) 2>&1) =~ "al-agent is NOT running" ]]; then
            echo "Agent service is not running. Attempting to start service..."    
            sudo /etc/init.d/al-agent restart
            if [[ -n "$(pgrep al-agent)" ]]; then
                echo "Agent service was started."
            fi
        fi    
        check_enforce
        make_syslog_config
        echo "Agent configuration was successful."
        return
    elif [[ $( (sudo /etc/init.d/al-agent status) 2>&1) =~ "command not found" ]] || [[ $( (sudo /etc/init.d/al-agent status) 2>&1) =~ "No such file or directory" ]]; then
        install_agent
        if [[ $( (sudo /etc/init.d/al-agent status) 2>&1) =~ "al-agent is running" ]]; then
            if [[ -n "$(pgrep al-agent)" ]]; then
                echo "Agent installation was completed."
                return
            fi    
        elif [[ $( (sudo /etc/init.d/al-agent status) 2>&1) =~ "al-agent is NOT running" ]]; then
            sudo /etc/init.d/al-agent start
            if [[ -n "$(pgrep al-agent)" ]]; then
                echo "Agent installation was completed. Service was started."
                return
            fi
        fi
        check_enforce
        make_syslog_config
        echo "Agent installation and configuration completed successfully."   
    else 
        echo "Agent was installed but the service failed to start. Please check your system init and try again."
        exit 1
    fi
}
run_install
EOT
sudo chmod +x al_conf_gen.sh
./al_conf_gen.sh
