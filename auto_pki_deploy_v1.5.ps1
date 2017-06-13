Add-PSSnapin VMware.VimAutomation.Core
#author : lih-tian.lim@hpe.com
#Version : 1.0
#Auto dbpki deployment for ESXi hosts.
#Sample usage : PowerCLI or Powershell, Run the script without needed Param input from user
# > .\auto_pki_deploy_v1.3.ps1

#0. Make sure connected to vCenter prior Execute this script within powercli
#1. Fill in your esxi hostname and password in ESXi_host.csv
#2. DB rui.key and cer/crt folder reside same location as script

#Version : 1.2
#Changelogs:
#1. Adding Start-ssh and Stop-ssh function. User no longer need to run enable_ssh or disable_ssh script before and after

#Version : 1.3
#Changelogs:
#1. Bug fixing - Checking if Cert folder is existance before proceed

#Version : 1.4(5th Dec 2016)
#Changelogs:
#1. Amend the case of the wording "esxihostname" become "esxiHostName"

#Read Current path
$currentpath = (get-item -path ".\" -Verbose).fullname
##write-host $currentpath

#Read input file
$ESXiFile=$currentpath+"\ESXi_host.csv"
#Plink Command file
$RenameKey = $currentpath+"\RenameKeyCommand.txt"
$PostCommand = $currentpath+"\PostConfCommand.txt"

# Read the input file which is formatted as esxi hostname,username,password with a header row
$csvData = Import-CSV $ESXiFile

#Creating \Certs\HostCertBackup
#Specify the path
$destDir = $currentpath+"\HostCertBackup"
# Check if the folder exist if not create it 
If (!(Test-Path $destDir)) {
   New-Item -Path $destDir -ItemType Directory
}
else { 
   Write-Host "Host cert backup folder already created"
}



Function Start-SSH{

Param(

[String]$vmHost

)

$vmhostobject = get-vmhost |where-object{$_.name -match $vmHost}
write-host $vmhostobject

        write-host "Configuring SSH on host: $($vmhostobject.Name)" -fore Yellow           
    if(($vmhostobject | Get-AdvancedSetting | Where {$_.Name -eq "UserVars.SuppressShellWarning"}).Value -ne "1"){
        Write-Host "Suppress the SSH warning message"
        #orig value is 0
        $vmhostobject | Get-AdvancedSetting | Where {$_.Name -eq "UserVars.SuppressShellWarning"} | Set-AdvancedSetting -Value "1" -Confirm:$false | Out-null
    }  
      sleep 1          
    if(($vmhostobject | Get-AdvancedSetting | Where {$_.Name -eq "UserVars.ESXiShellTimeOut"}).Value -ne "0"){
        Write-Host "Disable the esxi shell time out"
        #orig value is 60
        $vmhostobject | Get-AdvancedSetting | Where {$_.Name -eq "UserVars.ESXiShellTimeOut"} | Set-AdvancedSetting -Value "0" -Confirm:$false | Out-null
    }
    if((Get-VMHostService -VMHost $vmhostobject | where {$_.Key -eq "TSM-SSH"}).Running -ne $true){
        Write-Host "Starting SSH service on $($vmhostobject.Name)"
        Start-VMHostService -HostService (Get-VMHost $vmhostobject | Get-VMHostService | Where { $_.Key -eq "TSM-SSH"}) | Out-null
    }           
}



Function Stop-SSH{

Param(

[String]$vmHost

)

$vmhostobject = get-vmhost |where-object{$_.name -match $vmHost}
write-host $vmhostobject

        write-host "Configuring SSH on host: $($vmhostobject.Name)" -fore Yellow
    if(( $vmhostobject | Get-AdvancedSetting | Where {$_.Name -eq "UserVars.SuppressShellWarning"}).Value -ne "0"){
        Write-Host "Enable the SSH warning message"
        #orig value is 0
        $vmhostobject | Get-AdvancedSetting | Where {$_.Name -eq "UserVars.SuppressShellWarning"} | Set-AdvancedSetting -Value "0" -Confirm:$false | Out-null
    }  
    sleep 1           
    if(($vmhostobject | Get-AdvancedSetting | Where {$_.Name -eq "UserVars.ESXiShellTimeOut"}).Value -eq "0"){
        Write-Host "Enable the esxi shell time out"
        #orig value is 60
        $vmhostobject | Get-AdvancedSetting | Where {$_.Name -eq "UserVars.ESXiShellTimeOut"} | Set-AdvancedSetting -Value "60" -Confirm:$false | Out-null
    }
    if((Get-VMHostService -VMHost $vmhostobject | where {$_.Key -eq "TSM-SSH"}).Running -ne $false){
        Write-Host "Stoping SSH service on $($vmhostobject.Name)"
        Stop-VMHostService -HostService (Get-VMHost $vmhostobject | Get-VMHostService | Where { $_.Key -eq "TSM-SSH"}) -Confirm:$false | Out-null
    }    
    if((Get-VMHostService -VMHost $vmhostobject | where {$_.Key -eq "TSM"}).Running -ne $false){
        Write-Host "Stoping ESXiShell service on $($vmhostobject.Name)"
        Stop-VMHostService -HostService (Get-VMHost $vmhostobject | Get-VMHostService | Where { $_.Key -eq "TSM"}) -Confirm:$false | Out-null
    }               
}

ForEach ($entry in $csvData){
     
	
	#Variables
    $ESXiHostname = $entry.esxiHostName
    [String]$ESXiFullHostname = $ESXiHostname+".yourdomain.com"
    [String]$ESXiPassword = $entry.esxipassword
    $HostCertBakDir = $destDir+"\"+$ESXiHostname
    $SourcePath = "/etc/vmware/ssl"
    #$CertLocation = $currentpath+"\"+$ESXiHostname+".yourdomain.com"
	$CSRLocation = $currentpath+"\CSR_files\"+$ESXiHostname+".yourdomain.com"
	$CRTLocation = $currentpath+"\CRT_files\"
    $PSCPUserName = "root"
	
	#write-output " "
	#Write-output $CSRLocation
	#Write-output $CRTLocation
	#write-output " "
	
	 Write-host 
     Write-host -ForegroundColor Cyan "+++++++++++++++++++"
     Write-host -ForegroundColor Yellow $ESXiHostname
	 Write-host -ForegroundColor Cyan "+++++++++++++++++++"
	
# Check if the folder exist
If (!(Test-Path $CSRLocation)) { 
   Write-host -ForegroundColor Red "Cannot find the" $ESXiFullHostname ".CRT, make sure cert folder is in place" 
   continue
   Sleep 1
}
else { 

#Variables
    $RUIKeyCert = $CSRLocation+"\rui.key"
    #$dbPKICRT = get-childitem -path $CertLocation -filter $ESXiFullHostname*
	$dbPKICRT = $ESXiFullHostname+"_vCenterHost.crt"
    $RUICRT = $CRTLocation+$dbPKICRT
    $RenameCRT = $CSRLocation+"\rui.crt"
    Copy-Item $RUICRT $RenameCRT
    $NewRUICRT = $RenameCRT
	
	#write-output " "
	#write-output $dbPKICRT
	#write-output $RUICRT
	write-output $RenameCRT
	#write-output " "
   
#Host cert backup to vCenter server
#####################################################################################################
Start-SSH $ESXiFullHostname

New-Item -Path $HostCertBakDir -ItemType Directory -Force | out-null

#operator $() to "help" PowerShell correctly expand variable references in a string.
Write-host -ForegroundColor Yellow "Downloading rui.key and rui.crt from esxi to local as backup"
Write-output "Y" | .\pscp -pw $ESXiPassword -l $PSCPUserName -r -p "$($ESXiHostname):$SourcePath" "$HostCertBakDir"

plink.exe -ssh -l $PSCPUserName -pw $ESXiPassword $ESXiHostname -m $RenameKey
Write-host -ForegroundColor Yellow "Entering maintenance mode........."

#evacuate switch will fail if Admission control set to enable
#set-cluster -cluster $ESXiCluster -HAAdmissionControlEnabled:$false -confirm:$false
set-vmhost -vmhost $ESXiFullHostname -state maintenance -evacuate | out-null

Write-host -ForegroundColor Green "Entered maintenance mode"
Write-host -ForegroundColor Yellow "Uploading cert file to esxi"
Write-output $($ESXiPassword) | .\pscp "$RUIKeyCert" "$NewRUICRT" root"@"$($ESXiHostname):$SourcePath
Write-output $($ESXiPassword) | .\pscp "$RUIKeyCert" "$NewRUICRT" root"@"$($ESXiHostname):$SourcePath
#####################################################################################################

#Restart esxi services with services.sh restart
#Exit esxi from maintanence mode
#####################################################################################################
Write-host -ForegroundColor Yellow "Restaring services and Exit maintenance mode"
plink.exe -ssh -l $PSCPUserName -pw $ESXiPassword $ESXiHostname -m $PostCommand

#Write-host -foreGroundcolor Cyan "Restarting all ESXi services"
	for ($a=120; $a -gt 1; $a--){
		Write-Progress -Activity "Restarting all ESXi Services" -SecondsRemaining $a -CurrentOperation "$a% remaining"
		Start-Sleep 1
	}

	Stop-SSH $ESXiFullHostname

	set-vmhost -vmhost $ESXiFullHostname -state disconnected -confirm:$false | out-null

	Write-host "Exiting maintanence" $ESXiFullHostname
	set-vmhost -vmhost $ESXiFullHostname -state connected -confirm:$false| out-null

Sleep 1

	if(get-vmhost -name $ESXiFullHostname | where-object{$_.ConnectionState -ne "Connected"})
		{
			set-vmhost -vmhost $ESXiFullHostname -state connected -confirm:$false| out-null
			get-vmhost -name $ESXiFullHostname | select name,ConnectionState | format-list
		}
	Else{
			get-vmhost -name $ESXiFullHostname | select name,ConnectionState | format-list
		}
	}
}

#End Script
