# PowerShell script to provision a Windows Server with BuildKite
# This script follows https://buildkite.com/docs/agent/v3/windows.

# Instructions

# VM creation:
# In Google Cloud Platform, create a Compute Engine instance. 
# We recommend machine type n1-highcpu-16 (16 vCPUs, 14.4 GB memory).
# Use a windows boot disk with container support such as 
# "Windows Server version 1803 Datacenter Core for Containers".
# Give it a name, then click "Create".

# VM setup:
# In the Compute Engine menu, select "VM Instances". Click on the VM name you chose before.
# Click "Set Windows Password" to choose a username and password.
# Click RDP to open a remote desktop via browser, using the username and password.
# In the Windows command prompt start an elevated powershell by inputing
# "powershell -Command "Start-Process PowerShell -Verb RunAs" followed by Enter.
# Download and execute this script from GitHub, passing the token (mandatory) and tags (optional) as args:
# ```
# Invoke-WebRequest -Uri https://raw.githubusercontent.com/alexeagle/angular-bazel-example/master/.buildkite/provision-windows-buildkite.ps1 -OutFile provision.ps1
# .\provision.ps1 -token "MY_TOKEN" -tags "windows=true,something_else=true"
# ```
# The VM should restart and be fully configured.

# Creating extra VMs
# You can create an image of the current VM by following the instructions below.
# https://cloud.google.com/compute/docs/instances/windows/creating-windows-os-image
# Then create a new VM and choose "Custom images".


# Script proper.

# Get the token and tags from arguments.
param (
  [Parameter(Mandatory=$true)][string]$token,
  [string]$tags = ""
)

# Allow HTTPS
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

# Helper to add to PATH.
# Will take current PATH so avoid running it after anything to modifies only the powershell session path.
function Add-Path ([string]$newPathItem) {
  $Env:Path+= ";" +  $newPathItem + ";"
  [Environment]::SetEnvironmentVariable("Path",$env:Path, [System.EnvironmentVariableTarget]::Machine)
}

# Install Git for Windows
Write-Host "Installing Git for Windows."
Invoke-WebRequest -Uri https://github.com/git-for-windows/git/releases/download/v2.19.1.windows.1/Git-2.19.1-64-bit.exe -OutFile git.exe
.\git.exe /VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS="icons,ext\reg\shellhere,assoc,assoc_sh" /DIR="C:\git"
Add-Path "C:\git\bin"

# Download NSSM (https://nssm.cc/) to run the BuildKite agent as a service.
Write-Host "Downloading NSSM."
Invoke-WebRequest -Uri https://nssm.cc/ci/nssm-2.24-101-g897c7ad.zip -OutFile nssm.zip
Expand-Archive -Path nssm.zip -DestinationPath C:\nssm
Add-Path "C:\nssm\nssm-2.24-101-g897c7ad\win64"

# Run the BuildKite agent install script
Write-Host "Installing BuildKite agent."
$env:buildkiteAgentToken = $token
$env:buildkiteAgentTags = $tags
Set-ExecutionPolicy Bypass -Scope Process -Force
iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/buildkite/agent/master/install.ps1'))

# Register the BuildKite service using NSSM, so that it persists through restarts and is 
# restarted if the process dies.
Write-Host "Registering BuildKite as a service."
nssm.exe install buildkite-agent "C:\buildkite-agent\bin\buildkite-agent.exe" "start"
nssm.exe set buildkite-agent AppStdout "C:\buildkite-agent\buildkite-agent.log"
nssm.exe set buildkite-agent AppStderr "C:\buildkite-agent\buildkite-agent.log"
nssm.exe status buildkite-agent
nssm.exe start buildkite-agent
nssm.exe status buildkite-agent

# Restart the machine.
Restart-Computer