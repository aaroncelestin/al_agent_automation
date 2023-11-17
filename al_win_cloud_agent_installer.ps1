# QUICK AND DIRTY VERSION OF THE DATACENTER AGENT INSTALLER SCRIPT FOR AZURE AND AWS CLOUD ENVIRONMENTS
# Powershell Script
Set-ExecutionPolicy Bypass -Scope Process -Force;

#-----------------OPTIONS--------------------
# Path to agent installer, for example if the msi has been downloaded to the local machine already. This will bypass the downloading of the msi.
#$script:msi_path =  "< MSI file path >"
#--------------------------------------------
# if the agent will not be installed to the default installation path, set it here.
#$script:inst_path = "< install file path >"
#--------------------------------------------
# If the agent will be behind a proxy, set this to true and the agent will attempt to use the proxy settings from WinHTTP's built-in settings.
#$proxy = "true"
#--------------------------------------------
# For debugging purposes, set this to true to see the output of the agent installer. Output will be written to the file "agent_install.log" in the same directory as the installer.
$verb_mode = "true"
#--------------------------------------------
# Your system may reboot to complete the installation. The system may reboot if you have previously installed the agent, if you are running a Windows Server 2019 variant, or other reasons.
# If you want to avoid the system reboot, and consequently pause the installation process until you manually reboot, uncomment the following line to suppress the reboot. 
#$supress_reboot = "true"
#----------------------SCRIPT BODY----------------------
function downloadAgent 
{    
    $agent_url = "https://scc.alertlogic.net/software/al_agent-LATEST.msi"
    write-verbose "Downloading agent from $agent_url"
    try 
    {
        $adl_hash = @{
            Uri = $agent_url
            OutFile = $script:p_msi
        }
        Invoke-WebRequest @adl_hash # Download MSI and put it in file destination
        Write-Verbose "Agent MSI downloaded successfully"
    }
    catch [System.Net.WebException],[System.IO.IOException] 
    {
        Write-Host "Error: Unable to download MSI file. Please check your internet connection and try again." 
        exit
    }
    catch [Microsoft.PowerShell.Commands.HttpResponseException]
    {
        Write-Host "Error: (404) Unable to download MSI file. Please check the agent download URL and try again." 
        exit
    }
}
function startAgentService 
{
    $agent_svc_name = "al_agent"
    Write-verbose "Starting agent service..."
    try
    {
        start-service -name $agent_svc_name
        set-service -name $agent_svc_name -startupType automatic
        $al_service = get-service -name $agent_svc_name
        if ($al_service.status -eq "running") {
            Write-Verbose "Agent Service Started Successfully" 
        }
        else {
            Write-Verbose "Agent Service Failed to Start"
        }
    }
    catch {
        Write-Host "Service Error: Unable to start AlertLogic service. Check user permissions and try atgain."
    }
}
function checkOptionalMakePaths
{    # Check if msi_path is valid path set by user, if not, set to default
    Write-Verbose "Checking if non-default install and MSI file paths are set."
    if (Test-Path $msi_path -ErrorAction "Ignore") 
    {
        $script:p_msi = $msi_path
        Write-Verbose "MSI path set by user, using path: $msi_path" 
    }   
    else
    {
        $script:p_msi = "$env:USERPROFILE\Downloads\AlertLogic\al-agent-LATEST.msi"
        New-Item -Path $script:p_msi -ItemType File -Force #create file
        Write-Verbose "MSI path not set by user or folder does not exist, using default path: $script:p_msi" 
    }       
    # Check if inst_path is valid path set by user, if not, set to default
    if (Test-Path $inst_path -ErrorAction "Ignore") 
    {
        $script:p_inst = $inst_path
        $script:cust_inst = "true"
        Write-Verbose "Install path set by user, using path: $inst_path" 
    }   
    else
    {
        Write-Verbose "Install path not set by user or does not exist, using default ${env:ProgramFiles(x86)} path." 
    }
}
function toggleVerboseMode
{ 
    $script:logfilepath = "$env:USERPROFILE\Downloads\AlertLogic\agent_install.log"
    $script:SAVED_GVB_PREF = $global:VerbosePreference  
    if ($script:VerbosePreference -ne "Continue") #if anything but continue, set it to continue (verb mode on)
    {
        $script:VerbosePreference = "Continue"
        Write-Verbose "Script level scope verbose mode was set to ON ($script:VerbosePreference)."
        if (Test-Path $logFilePath) 
        {
            Write-Verbose "Log file path is $logFilePath."
        }
        else
        {
            New-Item -Path $logFilePath -ItemType File -Force #create file if it doesnt exist
            Write-Verbose "Log file path $logFilePath created."
        } 
    }
    elseif ($script:VerbosePreference -eq "Continue") #or if set to continue, turn it off (toggle off)
    {
        $script:VerbosePreference = "SilentlyContinue"
        Write-Verbose "Script level scope verbose mode was set to OFF ($script:VerbosePreference)."
        Write-Verbose "Global level scope verbose mode is set to $global:VerbosePreference."
    }
}   
function checkVerbosePreference
{
    Write-Host "Checking Script and Global verbose mode preferences." 
    Write-Host "Script level pref was set to $script:VerbosePreference"
    Write-Host "Global level pref was set to $global:VerbosePreference"
    if ($global:VerbosePreference -ne $script:SAVED_GVB_PREF) 
    {
        Write-Host "WARNING! POWERSHELL'S VERBOSE MODE PREFS HAVE BEEN MODIFIED!"
        Write-Host "VERBOSE MODE PREFERENCES FAILED TO REVERT TO THE DEFAULT." 
        Write-Verbose "Check your verbose mode preferences by typing `$global:VerboseModePreference on the command line."
        Write-Verbose "Try manually setting your VB Mode preference from the PowerShell command prompt:"
        Write-Verbose "Example: `$VerbosePreference = 'SilentlyContinue'"
    }
    else 
    {
        Write-Host "Global verbose mode preferences were not modified."
    }
}
function installAgent
{
    downloadAgent
    checkOptionalMakePaths
        $script:install_command = "msiexec /i $script:p_msi"
        Write-Verbose "Default install command string $script:install_command"
        if ($cust_inst -eq "true")
        {
            $script:install_command += " -install_path=$script:p_inst"
            Write-Verbose "Install path, $script:p_inst set by user"
        }
        if ($verb_mode -eq "true") 
        {
            $script:install_command += " /l*vx $script:logfilepath"
            Write-Verbose "Verbose mode enabled, logfile is $script:logfilepath"
        }
        else 
        {
            $script:install_command += $default_opts
            Write-Verbose "Default options $default_opts set."
        }
        if ($proxy -eq "true")
        {
            $script:install_command += " -use_proxy=1"
            Write-Verbose "Proxy enabled."
        }
        if ($supress_reboot -eq "true")
        {
            $script:install_command += " -REBOOT=ReallySuppress"
            Write-Verbose "Reboot prompt supressed."
        }
        Write-Verbose "Final install command string: $script:install_command"
        try
        {
            Invoke-Expression -command $script:install_command 
            Write-verbose "Install command executed: $script:install_command"
            Write-Verbose "Agent MSI installed successfully"
        }
        catch [System.Management.Automation.MethodInvocationException]
        {
            Write-Host "Error: Unable to install MSI file. Please check the installation path and try again."
            exit
        }
    startAgentService
}
#----------------------------START SCRIPT PROCESSING-------------------------------
if ($verb_mode -eq "true")
{
    toggleVerboseMode 
    installAgent -verbose *>&1 | Tee-Object -append -encoding "utf8" -FilePath $script:logFilePath
    toggleVerboseMode
    checkVerbosePreference
}
else 
{
    Write-Host "Debug mode not set by user, using default quiet mode." 
    installAgent  
}
# END OF SCRIPT
