# Hyperpoint v1.4.0
# Gpu-Assigned Checkpoints for Hyper-V
# https://github.com/cihantuncer/HyperPoint
# (c) 2024, Cihan Tuncer - cihan@cihantuncer.com
# This code is licensed under MIT license (see LICENSE.md for details)

param(
	[string]$vm,         # Virtual machine name
	[string]$do,         # Option name
    [string[]] $gpu=@(), # GPU query array
	[string]$dest,       # Driver installation destination path
	[switch]$zip,        # Driver installation compress option
	[switch]$s           # Silent mode
)

$packPath    = $null                                 # Driver packages path		     
$vmName      = $vm                                   # User-defined virtual machine name
$vmObj       = $null                                 # Virtual machine object
$gpusInput   = $gpu                                  # User-defined GPU array
$pGpuList    = [System.Collections.ArrayList]::new() # Partitionable GPU list
$udGpuList   = [System.Collections.ArrayList]::new() # Fetched user-defined GPU list
$driverList  = [System.Collections.ArrayList]::new() # Fetched driver list

# Log database
$log = [PSCustomObject]@{

	error   = [System.Collections.ArrayList]::new()
	warning = [System.Collections.ArrayList]::new()
	notice  = [System.Collections.ArrayList]::new()
	info    = [System.Collections.ArrayList]::new()
	success = [System.Collections.ArrayList]::new()
}

# Adapter configs
$adapterConfig=[PSCustomObject]@{

	MinPartitionVRAM        = 80000000
	MaxPartitionVRAM        = 100000000
	OptimalPartitionVRAM    = 100000000
	MinPartitionEncode      = 80000000
	MaxPartitionEncode      = 100000000
	OptimalPartitionEncode  = 100000000
	MinPartitionDecode      = 80000000
	MaxPartitionDecode      = 100000000
	OptimalPartitionDecode  = 100000000
	MinPartitionCompute     = 80000000
	MaxPartitionCompute     = 100000000
	OptimalPartitionCompute = 100000000
}

# --- Utils ---

# Forces to run as admin.
# @TODO: Doesn't work properly in all scenarios.
Function runAsAdministrator(){

	$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())

	if(-Not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {

		Start-Process -FilePath "powershell"  -ArgumentList "$('-File ""')$(Get-Location)$('\')$($MyInvocation.MyCommand.Name)$('""')" -Verb runAs
	}

}

# Checks if administrative privileges are granted. If not, exits the script.
Function checkAdministrator(){

	$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())

	if(-Not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {

		log "This script must be executed as Administrator."
		""

		exit
	}

}

# Modifies messages for output and log file.
Function msg{

	param($msg=$null,$fg=(get-host).ui.rawui.ForegroundColor,$bg=(get-host).ui.rawui.BackgroundColor)

	if($msg){

		if(-Not $s){

			write-host $msg -ForegroundColor $fg -BackgroundColor $bg
		}

		$ts=$(Get-Date -Format "dd/MM/yy HH:mm:ss")

		return "$ts`: $msg"
	}


}

# Adds messages to log object.
Function log{

	param($msg="",$type="info")

	if($msg){

		switch ($type)
		{
			"error" {
				$msg = msg "[ERROR] $msg" "red"
				$log.error.Add($msg) | Out-Null
				; Break
			}
			"warning" {
				$msg = msg "[WARNING] $msg" "yellow"
				$log.warning.Add($msg) | Out-Null
				; Break
			}
			"notice" {
				$msg = msg "[NOTICE] $msg" "blue"
				$log.notice.Add($msg) | Out-Null
				; Break
			}
			"success" {
				$msg = msg "[SUCCESS] $msg" "green"
				$log.success.Add($msg) | Out-Null
				; Break
			}
			"info" {
				$msg = msg "[INFO] $msg"
				$log.info.Add($msg) | Out-Null
			}
		}
		
	}	
	
}

# Creates log file in the "script path\log" folder.
Function writeLog{

	$ts      = $(Get-Date -Format "dd-MM-yy_HH-mm-ss")
	$logDir  = "$PSScriptRoot\logs"
	$logFile = "$logDir\log_$ts.txt"
	$logStr  = ""

	if(-Not (Test-Path -Path $logDir) ){
		New-Item -ItemType Directory $logDir | Out-Null
	}

	New-Item $logFile | Out-Null
	
	foreach ($cat in $log.PSObject.Properties)
	{
		foreach($msg in $cat.Value){

			$logStr +="$msg`n"
		}

	}

	$logStr | Out-File -FilePath $logFile

}

# Converts instance ID to device ID.
Function convertInstanceIdtoDeviceId{
	param(
		$instanceId=$null
	)

	if($null -eq $instanceId){
		return ""
	}

	$pattern = '(?<=\\\\\?\\)(.*?)(?=#{)'
	$match = [regex]::Match($instanceId, $pattern)
	$deviceId=$match.value
	$deviceId=$deviceId -replace '#', '\'

	return $deviceId
}

# Finds the PnP device based on the given device ID.
Function findPnpDevice{

	param(
		$deviceId=$null
	)

	if($null -eq $deviceId){
		return $null
	}

	$pnpDev = Get-PnpDevice | Where-Object {($_.DeviceID -like "*$deviceId*") -and ($_.Status -eq "OK")} -ErrorAction SilentlyContinue

	return $pnpDev
}


# --- Listing ---

# Writes details based on the given GPU object to the output or variable. 
Function showGpu{

	param(
		$gpu,
		$writehost=$true
	)

	$gpuStr=""

	if($gpu.friendlyName){$gpuStr += "$($gpu.friendlyName)`n"}else{"Unknown GPU`n"}
	if($gpu.adapterID)   {$gpuStr += "Adapter ID  : $($gpu.adapterID)`n"}
	if($gpu.deviceID)    {$gpuStr += "Device ID   : $($gpu.deviceID)`n"}
	if($gpu.instanceID)  {$gpuStr += "Instance ID : $($gpu.instanceID)"}

	if($writehost){
		write-host $gpuStr
	}
	else{
		return $gpuStr
	}
}

# Writes details based on the given GPU object list to the output or variable. 
Function listGpus{

	param($gpuList,$label="",$writehost=$true)

	$listStr=""

	if($writehost){$listStr  += "`n$label Gpu Adapters (Total:$($gpuList.Count))"}
	if($writehost){$listStr  += "`n------------------------------------------`n"}

	$i=0
	foreach($gpu in $gpuList){

		$listStr += "`n"
		if($gpu.friendlyName){$listStr += "($($i+1)) $($gpu.friendlyName)`n"}else{"Unknown GPU`n"}
		if($gpu.adapterID)   {$listStr += "Adapter ID  : $($gpu.adapterID)`n"}
		if($gpu.deviceID)    {$listStr += "Device ID   : $($gpu.deviceID)`n"}
		if($gpu.instanceID)  {$listStr += "Instance ID : $($gpu.instanceID)`n"}
		$i++
	}

	if($writehost){
		write-host $listStr
	}
	else{
		return $listStr
	}
		
	
}

# --- Detecting ---

# Checks if the script is running on the host machine.
Function isVmCheck{

	$hypervCheck = Get-Service -Name vmicheartbeat -ErrorAction SilentlyContinue

	if ($hypervCheck.Status -eq "Running") {

		log "This script must be run on the host machine." "error"
		""
		exit

	}
}

# Checks if the script is running on the host machine.

Function vmCheck{

	if( $null -eq $vmName ){
		log "No VM Name entered as parameter. Use -VM `"my vm name`" parameter to set target VM." "error"
		writeLog
		""
		Exit
	}

	$_vmObj = GET-VM -VMName $vmName  -ErrorAction SilentlyContinue

	if( $_vmObj ){
		$script:vmObj=$_vmObj
	}
	else{
		log "No VM found. Check your VM name." "error"
		""
		Exit
	}

}

# Checks if the VM exists and returns true/false.
Function vmGet{

	if( $null -eq $vmName ){
		return $false
	}

	$_vmObj = GET-VM -VMName $vmName  -ErrorAction SilentlyContinue

	if( $_vmObj ){
		$script:vmObj=$_vmObj
		return $true
	}
	else{
		return $false
	}

}

# Checks VM status.
Function vmStatusCheck{

	$vmStatus = (Get-VM -Name $vmName).State

	if( $vmStatus -eq "running"){
	
		log "Cannot execute while `"$vmName`" is running. Please shutdown VM first!" "error"
		""
		Exit
	}
}

# Disables automatic checkpoints for the VM.
Function disableAutoCheckpoints{

	Set-VM -VMName $vmName -AutomaticCheckpointsEnabled $False
	log "Automatic checkpoints disabled for `"$vmName`"." "notice"
}

# Gets GPU(s) from partitionable GPUs list based on the given GPU query array. 
Function getGpuByInput{

	$i=0
	
	foreach($pGpu in $pGpuList){

		foreach($gpuInput in $gpusInput){

			if($gpuInput -match "deviceid:"){
	
				$deviceID=$($gpuInput.Substring(9)).Trim()
	
				if( $deviceID -eq $($pGpu.deviceID) ){
					$udGpuList.Add($pGpu) | out-null
				}
				else{
					log "No GPU found with given device ID: $gpuInput" "warning"
				}
			}
			elseif($gpuInput -match "instanceid:"){
	
				$instanceID=$($gpuInput.Substring(11)).Trim()
	
				if( $instanceID -eq $($pGpu.instanceID) ){

					$udGpuList.Add($pGpu) | out-null
				}
				else{
					log "No GPU found with given instance ID: $gpuInput" "warning"
				}
			}
			elseif($gpuInput -match "order:"){

				$order=$($gpuInput.Substring(6)).Trim()
				
				if([int]$order -eq $($i+1)){
				
					$udGpuList.Add($pGpu) | out-null
				}
				else{
					log "No GPU found with given order: $gpuInput" "warning"
				}
			}
			else{

				$gpuFName=$gpuInput.Trim()

				if( $pGpu.friendlyName -eq $gpuFName ){
					$udGpuList.Add($pGpu) | out-null
				}
				else{
					log "No GPU found with given name: $gpuInput" "warning"
				}
			}
		}
		$i++
	}
}

# Gets the list of GPUs assigned to the VM.
Function getAssignedGpus{

	$gpuList = [System.Collections.ArrayList]::new() 

	foreach($aGpuObj in $(Get-VMGpuPartitionAdapter -VM $vmObj)){

		$deviceId     = convertInstanceIdtoDeviceId $aGpuObj.InstancePath
		$gpuPnpDevice = if($deviceId){$(findPnpDevice $deviceId)}else{ $null}

		if($gpuPnpDevice){

			$thisGpu = [PSCustomObject]@{
				friendlyName = $gpuPnpDevice.FriendlyName
				adapterID    = $($aGpuObj.id)
				deviceID     = $gpuPnpDevice.deviceID
				instanceID   = $aGpuObj.InstancePath
				assignable   = $true
			}
		}
		else{

			$thisGpu = [PSCustomObject]@{
				friendlyName = "Unknown GPU"
				adapterID    = $($aGpuObj.id)
				deviceID     = $deviceId
				instanceID   = $aGpuObj.InstancePath
				assignable   = $false
			}
		}

		$gpuList.Add($thisGpu) | out-null
	}

	return ,$gpuList

}

# --- Assignment ---

# Changes the adapter config values based on the given config file. 
Function setAdapterVals{

	param(
		[string]$configFile
	)

	Get-Content $configFile | Foreach-Object {

		$varLine = $_.Split('=')

		if( $varLine[0] -AND $varLine[1] ){

			$var = $varLine[0].Trim()

			if( [bool]($adapterConfig.PSobject.Properties.name -match $var) ){
				 $adapterConfig.$var=[int]$varLine[1].Trim()
			}
		}
	}
}

# Changes the default or specified adapter config values based on the config file in the script directory.
Function setAdapterConfig{

	param(
		[string]$gpu # gpu friendly name
	)

	$defConf  = "$PSScriptRoot\adapter.config"
	$gpuConf1 = "$PSScriptRoot\$gpu.config"
	$gpuConf2 = "$PSScriptRoot\$($gpu -replace '\s','-').config"
	$gpuConf3 = "$PSScriptRoot\$($gpu -replace '\s','_').config"
	$gpuConf4 = "$PSScriptRoot\$($gpu -replace '\s','').config"

	    if( Test-Path -Path $gpuConf1 ){ setAdapterVals $gpuConf1; log "Adapter configuration applied from $gpuConf1"; return }
	elseif( Test-Path -Path $gpuConf2 ){ setAdapterVals $gpuConf2; log "Adapter configuration applied from $gpuConf2"; return }
	elseif( Test-Path -Path $gpuConf3 ){ setAdapterVals $gpuConf3; log "Adapter configuration applied from $gpuConf3"; return }
	elseif( Test-Path -Path $gpuConf4 ){ setAdapterVals $gpuConf4; log "Adapter configuration applied from $gpuConf4"; return }
	elseif( Test-Path -Path $defConf  ){ setAdapterVals $defConf ; log "Default adapter configuration applied from $defConf"  }
}

# Adds all partitionable GPUs on the host machine to the "Partitionable GPUs List".
Function getPartitionableGpus{

	$pGpuObjs = Get-WmiObject -Class "Msvm_PartitionableGpu" -ComputerName $env:COMPUTERNAME -Namespace "ROOT\virtualization\v2"

	foreach($pGpuObj in $pGpuObjs){

		$deviceId  = convertInstanceIdtoDeviceId $pGpuObj.Name
		$gpuPnpDevice = findPnpDevice $deviceId

		if($gpuPnpDevice){

			$thisGpu = [PSCustomObject]@{
				friendlyName = $gpuPnpDevice.FriendlyName
				deviceID     = $gpuPnpDevice.deviceID
				instanceID   = $pGpuObj.Name
				assignable   = $true
			}
		}
		else{

			$thisGpu = [PSCustomObject]@{
				friendlyName = "Unknown GPU"
				deviceID     = ""
				instanceID   = $pGpuObj.Name
				assignable   = $false
			}

		}

		$pGpuList.Add($thisGpu) | out-null

	}
}

# Assigns a GPU object to the VM.
Function assignGpu{
	
	param($gpu)

	if($gpu -and $gpu.instanceID){

		Add-VMGpuPartitionAdapter -VM $vmObj -InstancePath $gpu.instanceID

		if($?){

			Set-VM -GuestControlledCacheTypes $true -VMName $vmName
			Set-VM -LowMemoryMappedIoSpace 1Gb -VMName $vmName
			Set-VM -HighMemoryMappedIoSpace 32GB -VMName $vmName

			$asgGpu=Get-VMGpuPartitionAdapter -VM $vmObj | Where-Object {($_.InstancePath -like "*$($gpu.instanceID)*")}  | Select-Object -First 1

			if($asgGpu){
	
				setAdapterConfig $gpu.friendlyName

				Set-VMGpuPartitionAdapter `
				-VM $vmObj `
				-adapterId $asgGpu.id `
				-MinPartitionVRAM $adapterConfig.MinPartitionVRAM `
				-MaxPartitionVRAM $adapterConfig.MaxPartitionVRAM `
				-OptimalPartitionVRAM $adapterConfig.OptimalPartitionVRAM `
				-MinPartitionEncode $adapterConfig.MinPartitionEncode `
				-MaxPartitionEncode $adapterConfig.MaxPartitionEncode `
				-OptimalPartitionEncode $adapterConfig.OptimalPartitionEncode `
				-MinPartitionDecode $adapterConfig.MinPartitionDecode `
				-MaxPartitionDecode $adapterConfig.MaxPartitionDecode `
				-OptimalPartitionDecode $adapterConfig.OptimalPartitionDecode `
				-MinPartitionCompute $adapterConfig.MinPartitionCompute `
				-MaxPartitionCompute $adapterConfig.MaxPartitionCompute `
				-OptimalPartitionCompute $adapterConfig.OptimalPartitionCompute
			}
			else{
				log "$($gpu.friendlyName) adapter settings could not configured." "warning"
			}
			log "$($gpu.friendlyName) adapter assigned." "success"
		}
	}
	else{
		log "GPU Assignment: Adapter $($gpu.friendlyName) doesn't have instance id. Couldn't assign." "error"
	}

}

# Assigns all GPU objects in the given GPU list to the VM.
Function assignGpuList{

	param($gpuList)

	foreach($gpu in $gpuList){

		assignGpu $gpu

	}

}

# Assigns all GPU objects in the "User-defined GPUs List".
Function addGpuByInput{

	foreach($udGpu in $udGpuList){
		assignGpu $udGpu
	}	
}

# Assigns all GPU objects in the "Partitionable GPUs List".
Function addGpuAll{

	foreach($pGpu in $pGpuList){

		assignGpu $pGpu
	}
		
}

# Assigns all GPU objects in the "User-defined GPUs List" if it's not empty
# or first GPU object in the "Partitionable GPUs List".
Function addGpuAuto{

	if($udGpuList.count -eq 0 -and $pGpuList.count -gt 0){
		assignGpu $pGpuList[0]
	}
	else{
		foreach($udGpu in $udGpuList){
			assignGpu $udGpu
		}
	}
}

# --- Removement ---

# Removes a assigned GPU from the VM based on the given GPU object.
Function removeGpu{

	param($gpu)
	
	if($gpu -and $gpu.adapterID){

		Remove-VMGpuPartitionAdapter -VM $vmObj -AdapterId $gpu.adapterID

		if($?){
	
			log "Adapter removed.`n$(showGpu $gpu $false)`n" "success"
		}
	}

}

# Removes a assigned GPU from the VM based on the given adapter ID.
Function removeGpuByAdapterId{

	param($adapterID)

	Remove-VMGpuPartitionAdapter -VM $vmObj -AdapterId $adapterID

	if($?){
		log "Adapter removed. (Adapter ID: $adapterID) " "success"
	}
}

# Removes assigned GPUs from the VM based on the "User-defined GPUs List".
Function removeGpuByInput{

	$aGpuList=getAssignedGpus

	$i=0
	$total=0
	foreach($aGpu in $aGpuList){

		foreach($gpuInput in $gpusInput){

			if($gpuInput -match "adapterid:"){
	
				$adapterID=$($gpuInput.Substring(10)).Trim()
	
				if( $adapterID -eq $($aGpu.adapterID) ){
					removeGpu $aGpu
					$total++
				}

			}
			elseif($gpuInput -match "deviceid:"){
	
				$deviceID=$($gpuInput.Substring(9)).Trim()
	
				if( $deviceID -eq $($aGpu.deviceID) ){
					removeGpu $aGpu
					$total++
				}

			}
			elseif($gpuInput -match "instanceid:"){
	
				$instanceID=$($gpuInput.Substring(11)).Trim()
	
				if( $instanceID -eq $($aGpu.instanceID) ){
					removeGpu $aGpu
					$total++
				}
			}
			elseif($gpuInput -match "order:"){

				$order=$($gpuInput.Substring(6)).Trim()

				if([int]$order -eq $($i+1)){
					removeGpu $aGpu
					$total++
				}
			}
			else{

				$gpuFName=$gpuInput.Trim()

				if( $aGpu.friendlyName -eq $gpuFName ){
					removeGpu $aGpu
					$total++
				}
			}
		}
		$i++
	}

	log "$total assigned GPUs removed.`n" "info"
}

# Removes all assigned GPUs from the VM.
Function removeAllGpus{

	Get-VMGpuPartitionAdapter -VM $vmObj | Remove-VMGpuPartitionAdapter

	log "All assigned GPUs removed." "success"

}

# --- Driver Operations ---

# Sets packages directory for driver files.
function setPackPath{

	if($dest){
		$script:packPath = $dest
	}
	else{
		$script:packPath = "$($PSScriptRoot)\hostdrivers"
	}

	if (-Not (Test-Path -Path $script:packPath)) {
		New-Item -ItemType Directory $script:packPath -ErrorAction SilentlyContinue | Out-Null
	}

	if (Test-Path -Path $script:packPath) {
		log "Driver files will be copied to $script:packPath" 
	}
	else{
		log "Unable to create or find $script:packPath. Please check parameters and destination directory permissions." "error"
		exit
	}

}

# Gathers driver files for the given GPU object from the host system.
function gatherDriverFiles{

	param($gpu)

	if(-Not $packPath){

		log "$packPath directory doesn't exist." "error"
		return $null
	}

	if(-Not $gpu){

		log "GPU variable doesn't exist." "error"
		return $null
	}
	
	$pnpDevice = Get-PnpDevice | Where-Object {$_.DeviceId -eq $gpu.deviceID} -ErrorAction SilentlyContinue

	if ($null -eq $pnpDevice) {

		log "Device not found: $($gpu.friendlyName)" "error"
		return $null
	}

	$drvInfs     = Get-WmiObject Win32_PNPSignedDriver | where-object {$_.DeviceID -eq "$($pnpDevice.DeviceID)"} 
	$drvProvider = $($drvInfs.DriverProviderName)
	$drvDate     = $($drvInfs.DriverDate).Substring(0,8)
	$driverName  = "$drvProvider`_$drvDate"
	$driverPath  = "$packPath\$driverName"

	log "Starting to copy $drvProvider driver files. Please wait." "info"

	if( -Not $driverList.Contains($driverName)){

		Remove-Item -Path $driverPath -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
		New-Item -ItemType Directory $driverPath -ErrorAction SilentlyContinue | Out-Null

		if (Test-Path -Path $driverPath) {

			# Adapted from Easy-GPU-PV
			# https://github.com/jamesstringerparsec/Easy-GPU-PV/blob/main/Add-VMGpuPartitionAdapterFiles.psm1
	
			foreach ($drvInf in $drvInfs) {
			
				$drvFiles         = @()
				$ModifiedDeviceID = $drvInf.DeviceID -replace "\\", "\\"
				$Antecedent       = "\\" + $ENV:COMPUTERNAME + "\ROOT\cimv2:Win32_PNPSignedDriver.DeviceID=""$ModifiedDeviceID"""
				$drvFiles += Get-WmiObject Win32_PNPSignedDriverCIMDataFile | Where-Object {$_.Antecedent -eq $Antecedent}
		
				$i=1;
				$len=$drvFiles.count
				$per=100/$len
	
				foreach ($drv in $drvFiles) {
						
					$path    = $drv.Dependent.Split("=")[1] -replace '\\\\', '\'
					$path    = $path.Substring(1,$path.Length-2)
					$infItem = Get-Item -Path $path
		
					$destFilePath   = $path.Replace("c:", "$driverPath")
					$destFolderPath = $destFilePath.Substring(0, $destFilePath.LastIndexOf('\'))
		
					if ($destFolderPath -like "$driverPath\windows\system32\driverstore\*") {
						$destFolderPath = $destFolderPath.Replace("driverstore","HostDriverStore")
					}
	
					if (-Not (Test-Path -Path $destFolderPath)) {
	
						New-Item -ItemType Directory -Path $destFolderPath -Force | Out-Null
					}
		
					Copy-Item $infItem -Destination $destFolderPath -Force
					
					$currPer=[int]($i*$per)
	
					Write-Progress -Activity "Copying Driver Files" -Status "$currPer% Copied:" -PercentComplete $currPer
	
					if($i -eq $len){

						if($zip){

							log "Starting to create $driverName.zip package. Please wait." "info"

							Compress-Archive -Path "$driverPath\*" -DestinationPath "$packPath\$driverName.zip" -Force

							if($?){
								log "$driverPath.zip created." "success"
								Remove-Item -Path $driverPath -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
							}
						}
						else{
							log "Driver files for $($gpu.friendlyName) have been copied to $driverPath" "success"
						}
					}
					$i++
				}		
			}
		}
		else{
			log "Unable to create the $driverName driver package directory in $packPath" "error"
		}

		$driverList.Add($driverName) | Out-Null

		#$txtFile = "$driverPath.txt"
		#$txt     = "$driverName,$($gpu.friendlyName),$($gpu.deviceID),$($gpu.instanceID)"

		#if(-Not (Test-Path -Path $txtFile)){
		#	New-Item $txtFile | Out-Null
		#}
	
		#$txt | Out-File -FilePath $txtFile
	}
	else{

		log "$driverName driver package for $($gpu.friendlyName) have already been copied to $driverPath" "notice"

		#$txtFile = "$driverPath.txt"
		#$txt     = "$driverName,$($gpu.friendlyName),$($gpu.deviceID),$($gpu.instanceID)"

		#if(-Not (Test-Path -Path $txtFile)){
		#	New-Item $txtFile | Out-Null
		#}
	
		#$txt | Out-File -Append -FilePath $txtFile

	}

	log "Don't forget to remove assigned GPUs before installing drivers to VM." "notice"
}

# Gathers driver files used by assigned GPUs from the host system.
function gatherAssignedGpusDriverFiles{

	setPackPath

	$gpus = getAssignedGpus

	if($gpus.count -eq 0){
		log "Assigned GPU(s) not found. Please assign a GPU to VM or define GPU via -GPU parameter first (See readme.md)." "warning"
		""
		writeLog
		Exit
	}

	foreach($gpu in $gpus){
		gatherDriverFiles $gpu
	}
}

# Gathers driver files based on the "User-defined GPUs List" from the host system.
function gatherGpuDriverFilesByInput{

	setPackPath

	foreach($udGpu in $udGpuList){
		gatherDriverFiles $udGpu
	}
}

# -----------------
# --- Processes ---
# -----------------

# Lists partitionable and assigned GPUs.
Function process_ListGpus{

	""
	listGpus $pGpuList "Partitionable"

	$vmGot=vmGet

	if($vmGot){
		$assignedGpus=getAssignedGpus
		listGpus $assignedGpus "Assigned"
	}
	""
}

# Lists partitionable GPUs.
Function process_ListGpusPartitionable{

	""
	listGpus $pGpuList "Partitionable"
	""
}

# Lists assigned GPUs.
Function process_ListGpusAssigned{

	""
	vmCheck
	$assignedGpus=getAssignedGpus
	listGpus $assignedGpus "Assigned"
	""
}

# Assigns GPU by parameter to the VM.
Function process_Add {

	""
	vmCheck
	vmStatusCheck
	disableAutoCheckpoints
	addGpuByInput
	""

	writeLog
}

# Assigns all partitionable GPUs to the VM.
Function process_AddAll {

	""
	vmCheck
	vmStatusCheck
	disableAutoCheckpoints
	addGpuAll
	""

	writeLog
}

# Assigns user-defined GPUs if exist or first suitable partitionable GPU to the VM.
Function process_AddAuto {

	""
	vmCheck
	vmStatusCheck
	disableAutoCheckpoints
	addGpuAuto
	""

	writeLog
}

# Removes GPU(s) from the VM based on the -GPU parameter.
Function process_Remove {

	""
	vmCheck
	vmStatusCheck
	disableAutoCheckpoints
	removeGpuByInput
	""

	writeLog
}

# Removes all assigned GPU(s) from the VM.
Function process_RemoveAll {

	""
	vmCheck
	vmStatusCheck
	disableAutoCheckpoints
	removeAllGpus
	""

	writeLog
}

# Removes assigned GPU(s) from the VM.
# Then assigns user-defined GPUs if exist or first suitable partitionable GPU to the VM.
Function process_Reset {

	""
	vmCheck
	vmStatusCheck
	disableAutoCheckpoints
	removeAllGpus
	addGpuAuto
	""
	
	writeLog
}

# Creates checkpoint.
Function process_Checkpoint{

	""
	vmCheck
	vmStatusCheck
	disableAutoCheckpoints
	
	# Cache previusly assigned GPUs.
	$prevGpus=getAssignedGpus
	$prevCount=$prevGpus.count

	# Remove all assigned GPUs.
	removeAllGpus

	# Create checkpoint
	Checkpoint-VM -Name $vmName

	if($?){
		log "Checkpoint created." "success"
	}
	else{
		log "Unable to create checkpoint." "error"
	}

	# Assign user-defined GPU(s) if exists, ignore previously assigned GPUs.
	if($udGpuList.count -gt 0){

		assignGpuList $udGpuList

		$currGpus=getAssignedGpus
		$currCount=$currGpus.count

		log "$currCount User-defined GPU adapter(s) assigned." "info"
	}
	# Reassign previously assigned GPUs.
	else{

		assignGpuList $prevGpus

		$currGpus=getAssignedGpus
		$currCount=$currGpus.count
	
		if( $prevCount -gt $currCount ){
	
			$msg = "Some of the previously assigned GPU adapters could not be reassigned.`n"+
				   "This issue may be due to some of them not having instance ID values."
	
			log $msg "notice"
		}
	
		log "$currCount GPU adapter(s) reassigned." "info"
	}
	""

	writeLog
}

# Retrieves user-defined GPUs drivers if exist or assigned GPUs automatically.
Function process_GetDrivers{

	""
	if($gpusInput.count -gt 0){

		if($udGpuList.count -gt 0){

			gatherGpuDriverFilesByInput
		}
		else{
	
			log "No GPU(s) found. Please check -GPU arguments." "error"
			""

			exit
		}

	}
	else{
		vmCheck
		gatherAssignedGpusDriverFiles
	}
	""

	writeLog
}

# Script options
Function process_Main{

	switch ($do)
	{
		"list-gpus"               {process_ListGpus; Break}
		"list-gpus-partitionable" {process_ListGpusPartitionable; Break}
		"list-gpus-assigned"      {process_ListGpusAssigned; Break}
		"add"                     {process_Add; Break}
		"add-auto"                {process_AddAuto; Break}
		"add-all"                 {process_AddAll; Break}
		"remove"                  {process_Remove; Break}
		"remove-all"              {process_RemoveAll; Break}
		"reset"                   {process_Reset; Break}
		"get-drivers"             {process_GetDrivers; Break}
		Default                   {process_Checkpoint}
	}
}

# -----------------
# --- Run ---------
# -----------------

# Checks
checkAdministrator
isVMCheck

# Inits
getPartitionableGpus
getGpuByInput

## Main
process_Main
