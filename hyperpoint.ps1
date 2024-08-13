# Gpu-Assigned Checkpoints for Hyper-V 
# Cihan Tuncer cihan[at]cihantuncer.com 

param(
	$do=$null,
    $vm=$null,
    [string[]] $gpu=@(),
	[switch]$s
)

$script:vmName     = $vm								   # User-defined Virtual Machine Name
$script:vmObj      = $null								   # Virtual Machine Object
$script:gpusInput  = $gpu 								   # User-defined Gpu Array
$script:pGpuList   = [System.Collections.ArrayList]::new() # Partitionable Gpu List
$script:udGpuList  = [System.Collections.ArrayList]::new() # Fetched User-defined Gpu List

$script:log = [PSCustomObject]@{
	error   = [System.Collections.ArrayList]::new()
	warning = [System.Collections.ArrayList]::new()
	notice  = [System.Collections.ArrayList]::new()
	info    = [System.Collections.ArrayList]::new()
	success = [System.Collections.ArrayList]::new()
}

Function runAsAdministrator(){

	$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())

	if(-Not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {

		Start-Process -FilePath "powershell"  -ArgumentList "$('-File ""')$(Get-Location)$('\')$($MyInvocation.MyCommand.Name)$('""')" -Verb runAs
	}

}

Function vmCheck{

	if( $null -eq $vmName ){
		"`n[ERROR] No VM Name entered as parameter. Use -VM `"my vm name`" to set target vm.`n "
		Exit
	}

	$_vmObj = GET-VM -VMName $vmName  -ErrorAction SilentlyContinue

	if( $_vmObj ){
		$script:vmObj=$_vmObj
	}
	else{
		"`n[ERROR] No VM found. Check your VM name.`n "
		Exit
	}

}

Function vmStatusCheck{

	$vmStatus = (Get-VM -Name $vmName).State

	if( $vmStatus -eq "running"){
	
		"`n[ERROR] Cannot execute while `"$vmName`" is running. Please shutdown VM first!`n"
		Exit
	}
}

Function log{

	param($msg="",$type="info")

	if($msg){

		$log.($type).Add($msg) | Out-Null

		if(-Not $s){
			write-host "[$($type.ToUpper())] $msg"
		}
		
	}	
	
}

Function disableAutoCheckpoints{

	Set-VM -VMName $vmName -AutomaticCheckpointsEnabled $False
	"`n[NOTICE] Automatic checkpoints disabled for `"$vmName`".`n"
}

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

Function showGpu{

	param($gpu,$writehost=$true)

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

Function getGpuByInput{

	$i=0
	
	foreach($pGpu in $pGpuList){

		foreach($gpuInput in $gpusInput){

			if($gpuInput -match "deviceid:"){
	
				$deviceID=$($gpuInput.Substring(9)).Trim()
	
				if( $deviceID -eq $($pGpu.deviceID) ){
					$udGpuList.Add($pGpu) | out-null
				}
			}
			elseif($gpuInput -match "instanceid:"){
	
				$instanceID=$($gpuInput.Substring(11)).Trim()
	
				if( $instanceID -eq $($pGpu.instanceID) ){

					$udGpuList.Add($pGpu) | out-null
				}
			}
			elseif($gpuInput -match "order:"){

				$order=$($gpuInput.Substring(6)).Trim()
				
				if([int]$order -eq $($i+1)){
				
					$udGpuList.Add($pGpu) | out-null
				}
			}
			else{

				$gpuFName=$gpuInput.Trim()

				if( $pGpu.friendlyName -eq $gpuFName ){
					$udGpuList.Add($pGpu) | out-null
				}
			}
		}
		$i++
	}
}

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

# --- Assigment ---

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
	
				Set-VMGpuPartitionAdapter -VM $vmObj -adapterId $asgGpu.id -MinPartitionVRAM 80000000 -MaxPartitionVRAM 100000000 -OptimalPartitionVRAM 100000000 -MinPartitionEncode 80000000 -MaxPartitionEncode 100000000 -OptimalPartitionEncode 100000000 -MinPartitionDecode 80000000 -MaxPartitionDecode 100000000 -OptimalPartitionDecode 100000000 -MinPartitionCompute 80000000 -MaxPartitionCompute 100000000 -OptimalPartitionCompute 100000000
			}
			else{
				log "GPU Assigment: $($gpu.friendlyName) adapter settings could not configured." "warning"
			}
			log "GPU Assigment: $($gpu.friendlyName) adapter assigned." "success"
		}
	}
	else{
		log "GPU Assigment: Adapter $($gpu.friendlyName) doesn't have instance id. Couldn't assign." "error"
	}

}

Function assignGpuList{

	param($gpuList)

	foreach($gpu in $gpuList){

		assignGpu $gpu

	}

}

# --- Removement ---

Function addGpuByInput{

	foreach($udGpu in $udGpuList){
		assignGpu $udGpu
	}	
}

Function addGpuAll{

	foreach($pGpu in $pGpuList){

		assignGpu $pGpu
	}
		
}

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

Function removeGpu{

	param($gpu)
	
	if($gpu -and $gpu.adapterID){

		Remove-VMGpuPartitionAdapter -VM $vmObj -AdapterId $gpu.adapterID

		if($?){
	
			log "GPU Removement: Adapter removed.`n$(showGpu $gpu $false)`n" "success"
		}
	}

}

Function removeGpuByAdapterId{

	param($adapterID)

	Remove-VMGpuPartitionAdapter -VM $vmObj -AdapterId $adapterID

	if($?){
		log "GPU Removement: Adapter removed. (Adapter ID: $adapterID) " "success"
	}
}

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

	log "GPU Removement: $total assigned GPUs removed.`n" "info"
}

Function removeAllGpus{

	Get-VMGpuPartitionAdapter -VM $vmObj | Remove-VMGpuPartitionAdapter

	log "GPU Removement: All assigned GPUs removed." "success"

}

# --- Processes ---

Function process_ListGpus{

	""
	listGpus $pGpuList "Partitionable"

	$assignedGpus=getAssignedGpus
	listGpus $assignedGpus "Assigned"
	""
}

Function process_ListGpusPartitionable{
	""
	listGpus $pGpuList "Partitionable"
	""
}

Function process_ListGpusAssigned{

	""
	$assignedGpus=getAssignedGpus
	listGpus $assignedGpus "Assigned"
	""
}

function process_Add {

	""
	addGpuByInput
	""
}

function process_AddAll {

	""
	addGpuAll
	""
}

function process_AddAuto {

	""
	addGpuAuto
	""
}

function process_Remove {

	""
	removeGpuByInput
	""
}

function process_RemoveAll {
	""
	removeAllGpus
	""
}

function process_Reset {

	""
	removeAllGpus
	addGpuAuto
	""
}

Function process_Checkpoint{
	""
	$prevGpus=getAssignedGpus
	$prevCount=$prevGpus.count

	removeAllGpus

	Checkpoint-VM -Name $vmName

	if($udGpuList.count -gt 0){

		assignGpuList $udGpuList

		$currGpus=getAssignedGpus
		$currCount=$currGpus.count

		log "$currCount User-defined GPU adapter(s) assigned." "info"
	}
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

}

Function process_Main{

	switch ($do)
	{
		"list-gpus" 		      {process_ListGpus; Break}
		"list-gpus-partitionable" {process_ListGpusPartitionable; Break}
		"list-gpus-assigned"      {process_ListGpusAssigned; Break}
		"add"      				  {process_Add; Break}
		"add-auto"      		  {process_AddAuto; Break}
		"add-all"      		      {process_AddAll; Break}
		"remove"      			  {process_Remove; Break}
		"remove-all"      		  {process_RemoveAll; Break}
		"reset"      			  {process_Reset; Break}
		Default {process_Checkpoint}
	}
}

# --- Run ---

# Checks
runAsAdministrator
vmCheck
vmStatusCheck

# Inits
getPartitionableGpus
getGpuByInput

# Main
process_Main
