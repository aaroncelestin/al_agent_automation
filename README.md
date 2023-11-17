# al-automation-tools


```
   $$$$$$\  $$\                      $$\           $$\                          $$\           
  $$  __$$\ $$ |                     $$ |          $$ |                         \__|          
# $$ /  $$ |$$ | $$$$$$\   $$$$$$\ $$$$$$\         $$ |      $$$$$$\   $$$$$$\  $$\  $$$$$$$\ 
# $$$$$$$$ |$$ |$$  __$$\ $$  __$$\\_$$  _|        $$ |     $$  __$$\ $$  __$$\ $$ |$$  _____|
# $$  __$$ |$$ |$$$$$$$$ |$$ |  \__| $$ |          $$ |     $$ /  $$ |$$ /  $$ |$$ |$$ /      
# $$ |  $$ |$$ |$$   ____|$$ |       $$ |$$\       $$ |     $$ |  $$ |$$ |  $$ |$$ |$$ |      
# $$ |  $$ |$$ |\$$$$$$$\ $$ |       \$$$$  |      $$$$$$$$\\$$$$$$  |\$$$$$$$ |$$ |\$$$$$$$\ 
# \__|  \__|\__| \_______|\__|        \____/       \________|\______/  \____$$ |\__| \_______|
                                                                    $$\   $$ |              
                                                                    \$$$$$$  |              
                                                                     \______/               
```




## OVERVIEW
These scripts will automate the download, installation and log configuration of the agents on Windows and Linux hosts. They will also attempt to start all
agent services. These scripts, once started, are meant to be run completely unattended on multiple hosts. It should be noted that this kind of automation 
is not necessary on AWS or Azure since they have bult-in tools like SSM for AWS and Azure Cloud Shell. So, these tools will be of most use to customers with 
DataCenter deployments. Nonetheless, these scripts can still be run on SSM and ACS with very little manual modifications, e.g. registration keys are not 
required in cloud environments so that will have to be manually disabled in the scripts before deployment.



## FOR LINUX VMs IN DATACENTER DEPLOYMENTS
This shell script can be run with two switches <-key | -help> and an argument (keystring), will download and install the appropriate agent (RPM/DEB/x86/64/ARM),
check proper log configuration (syslog/syslog-ng), modify the config file for forwarding, check init type (systemd/initv), and start the agent service. You can 
set the reg key in the script itself before running it or you can pass it as an argument. You can aslo set SOME options by uncommenting the lines at the top of
the script. These will “pass-through” to Alert Logic’s built-in agent switch upon install, provision for the key and configure for some of the options.

A registration key is required to be included either on the command line when the script is called or set in the script comments section. When the key is set in
comments, no other command line arguments can be provided else they will override any uncommented options, possibly resulting in unexpected behavior. All other
switches defined in the comments are strictly optional.


## FOR WINDOWS VMs IN DATACENTER DEPLOYMENTS
The Windows PowerShell will download, install, and configure the agent before attempting to start the agent service. It must be run with elevated privileges to
install the MSI file and start Windows services. The script cannot yet be run with switches or arguments as of version 1.0.1. The only way to configure the agent
installation for now is to manually modify the script before deploying it. Uncomment the lines at the top to change configurations such as a customer agent URL,
a path to a previously downloaded agent MSI file, appliance settings, debug logs, etc. Any misconfigured options will fall back to the default configurations as
a failsafe. The registration key is the only required part of the script. It must be pasted in before running the script or it is written to fail right away.
