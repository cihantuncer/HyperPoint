# Driver Installer v1.0.1 for HyperPoint 
# https://github.com/cihantuncer/HyperPoint
# (c) 2024, Cihan Tuncer - cihan@cihantuncer.com
# This code is licensed under MIT license (see LICENSE.md for details)

param(
	$do             = $null, # Script options
	$src            = $null, # Directory that contains driver packages.
	[string[]] $drv = @(),   # Driver package name(s) to install.
	$drvsrc         = $null, # Direct driver directory or zip package.
	[switch]$force,          # Force install (For locked files by other processes)
	[switch]$s               # Silent mode
)

$packPath     = $null
$driverInput  = $drv
$driverPacks  = @()
$fileCount    = 0
$copiedCount  = 0

# Log database
$log = [PSCustomObject]@{
	error   = [System.Collections.ArrayList]::new()
	warning = [System.Collections.ArrayList]::new()
	notice  = [System.Collections.ArrayList]::new()
	info    = [System.Collections.ArrayList]::new()
	success = [System.Collections.ArrayList]::new()
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
				$log.($type).Add($msg) | Out-Null
				; Break
			}
			"warning" {
				$msg = msg "[WARNING] $msg" "yellow"
				$log.($type).Add($msg) | Out-Null
				; Break
			}
			"notice" {
				$msg = msg "[NOTICE] $msg" "blue"
				$log.($type).Add($msg) | Out-Null
				; Break
			}
			"success" {
				$msg = msg "[SUCCESS] $msg" "green"
				$log.($type).Add($msg) | Out-Null
				; Break
			}
			"info" {
				$msg = msg "[INFO] $msg"
				$log.($type).Add($msg) | Out-Null
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

# --- Checks ---

# Checks if the script is running in the Hyper-V virtual machine.
Function isVmCheck{

	$hypervCheck = Get-Service -Name vmicheartbeat -ErrorAction SilentlyContinue

	if (-Not ($hypervCheck.Status -eq "Running")) {

		log "This script must be run in a Hyper-V virtual machine." "error"
		""

		exit
	}
}

# --- Driver Operations ---


Function cacheDriver{

	param(
		[string]$driverPath
	)

	$name     = [System.IO.Path]::GetFileNameWithoutExtension($driverPath)
	$isZip    = $false
	$tempPath = ""

	if (Test-Path $driverPath -PathType Container) {
		$fname    = $name
		$tempPath = $driverPath
		$isZip    = $false

	} elseif ([System.IO.Path]::GetExtension($driverPath) -eq ".zip") {
		$fname    = "$name.zip"
		$tempPath = "$env:TEMP\$name"
		$isZip=$true
	}

	$drvObj = [PSCustomObject]@{
		path      = $driverPath
		tempPath  = $tempPath
		name      = $name
		fname     = $fname
		isZip     = $isZip
		total     = 0
		copied    = 0
		lockedDB = @()
		installed = $false
	}

	return $drvObj
}

# Checks if the existing driver file is locked by other process(es). 
Function isLocked {

    param (
        [string]$FilePath
    )

    try {
        $stream = [System.IO.File]::Open($FilePath, 'Open', 'ReadWrite', 'None')
        $stream.Close()
        return $false
    }
    catch {
        return $true
    }
}

# Returns the processes that are locking the target file as objects. 
Function getFileLockingProcesses{
    param (
        [string]$filePath
    )

    $lockingProcesses = @()

    Get-Process | ForEach-Object {

        $processVar = $_
        try {
            $processVar.Modules | ForEach-Object {
                if ($_.FileName -eq $filePath) {
                    $lockingProcesses += [PSCustomObject]@{
                    	File=$($(Split-Path $filePath -leaf))
                    	FilePath=$filePath
                        ProcessId = $processVar.Id
                        ProcessName = $processVar.Name
                    }
                }
            }
        } catch {
            Write-Output "Could not access modules for process $($processVar.Name) (PID: $($processVar.Id))"
        }
    }

    return $lockingProcesses
}

# Terminates process based on the given process object.
Function terminateProcess{

	param (
        $process
    )

	log "Attempting to terminate $($process.ProcessName) (PID:$($process.ProcessID))"

	Stop-Process -Name $process.ProcessName -Force -ErrorAction SilentlyContinue

	Start-Sleep -Seconds 3

	if( $process.ProcessName -like "*sunshine*"){

		Get-Service -DisplayName "*sunshine*" | Stop-Service -PassThru -Force

		if($?){
			log "Sunshine service stopped."
		}

	}
	elseif( $process.ProcessName -like "*parsec*" ){

		Get-Service -DisplayName "*parsec*" | Stop-Service -PassThru -Force

		if($?){
			log "Parsec service stopped."
		}
	}
	elseif( isLocked $process.FilePath ){

		Get-Service -DisplayName "*$($process.ProcessName)*"  | Stop-Service -PassThru -Force

		if($?){
			log "$($process.ProcessName) service stopped."
		}
	}

	Start-Sleep -Seconds 3

	if(isLocked $process.FilePath){

		log "$($process.FilePath) is still locked by $($process.ProcessName) (PID:$($process.ProcessID))." "warning"
		return $false
	}
	else{

		log "$($process.FilePath) is no longer locked."
		return $true
	}
}

# Terminates processes based on the given process objects array.
Function terminateProcesses {
	
	param (
        $processes
    )

	$terminated=$true

	foreach($process in $processes){

		$terminated=$(terminateProcess $process)
	}

	return $terminated
}

# Checkes locked target files.
Function checkFiles{

	param(
		$driver
	)

	log "Starting to check $($driver.fname) driver files. Please wait."

	Get-ChildItem -Path $driver.tempPath -File -Recurse -ErrorAction SilentlyContinue -Force | ForEach-Object {

		$driver.total = $driver.total + 1
		
		$srcFile  = $_.FullName
		$destFile = $srcFile.replace($driver.tempPath,"C:")

		if(Test-Path $destFile -PathType Leaf){

			if(isLocked $destFile){

				$processes = getFileLockingProcesses $destFile

				$driver.lockedDB += $processes

				foreach($process in $processes){

					log "$($process.FilePath) is locked by $($process.ProcessName) (PID:$($process.ProcessID))" "warning"

				}
			}
		}
	}

	if($driver.lockedDB.count -gt 0){

		if($force){

			if(-Not (terminateProcesses $driver.lockedDB)){

				$logStr ="Some driver files on the system are still locked and cannot be overwritten.`n"
				$logStr+="Stop processes and services above, then re-run this script or manually copy locked files."
				log $logStr "warning"
			}

		}
		else{

			$logStr ="Some driver files on the system are locked and cannot be overwritten.`n"
			$logStr+="Use -FORCE parameter to stop processes and services automatically. Or stop them manually."
			log $logStr "error"
			""

			writeLog
			exit
		}
	}
}

# Copies files source to destination.
Function copyFiles{

	param(
		$driver
	)

	log "Starting to copy $($driver.total) of $($driver.fname) driver files to system. Existing files will be overwritten. Please wait."

	$i=1;
	$len=$driver.total
	$per=100/$len

	Get-ChildItem -Path $driver.tempPath -File -Recurse -ErrorAction SilentlyContinue -Force | ForEach-Object {

		$currPer=[int]($i*$per)
		Write-Progress -Activity "Installing $($driver.name) Driver Files" -Status "$currPer% Copied:" -PercentComplete $currPer
		$i++

		$srcFile  = $_.FullName
		$destFile = $srcFile.replace($driver.tempPath,"C:")
		$destDir  = Split-Path -Path $destFile -Parent

		if (-not (Test-Path -Path $destDir)) {
		    New-Item -Path $destDir -ItemType Directory -Force | Out-Null
		}

		try{
			Copy-Item -Path $srcFile -Destination $destFile -Force -Recurse
			$driver.copied = $driver.copied + 1
		}
		catch{
			log "$fullName could not be copied." "error"
		}
	}
}

# Copies driver package folder contents to the system.
Function installFromFolder{

	param(
		$driver
	)

	checkFiles $driver
	copyFiles  $driver

	$driver.installed=$true
}

# Copies driver zip package contents to the system.
Function installFromZip{

	param(
		$driver
	)

	if(Test-Path -Path $driver.path -PathType leaf){

		if (-not (Test-Path -Path $driver.tempPath)) {
			
		    New-Item -Path $driver.tempPath -ItemType Directory -Force  | Out-Null
		}

		log "Starting to extract driver files to temporary directory. Please wait."

		Start-Sleep 2

		Expand-Archive -Path $driver.path -DestinationPath $driver.tempPath -Force

		if($?){

			log "Extraction completed."

			if(Test-Path -Path $driver.tempPath){

				checkFiles $driver
				 copyFiles $driver

				 $driver.installed=$true
			}
			else{
				log "Unable to access temporary directory: $($driver.tempPath)" "error"
			}
		}
		else{
			log "Unable to extract driver files to temporary directory: $($driver.tempPath)" "error"
		}
	}
}

# Driver installation.
Function installDriverFiles{

	param($driver)

	#$driverLog  = $null
	
	""
	log "Starting to install $($driver.fname)"

	if(-Not $driver.path){

		log "Driver package path value is empty." "error"
		return $null
	}

	if($driver.isZip){

		# zip package
		installFromZip $driver

		#$driverLog="$packPath\$($(Split-Path $driverPath -leaf).replace('.zip','.txt'))"
	}
	else{

		# folder package
		installFromFolder $driver

		#$driverLog="$driverPath.txt"
	}

	if($driver.installed){

		#drvLog $driverLog

		$diff=$driver.total - $driver.copied

		if($diff -gt 0){

			$logStr  = "$($driver.fname) installation completed but $diff driver file(s) cannot be copied."
			$logStr += "Stop processes and services above, then re-run this script or manually copy locked files."

			log $logStr "warning"
		}
		else{
			log "$($driver.fname) installation completed successfully. $($driver.copied) driver files copied from $($driver.fname) to Windows." "success"
		}	
	}
	else{
		log "Errors occured while installing $($driver.fname) driver files from $($driver.path) to Windows." "error"
	}
}

# Reads driver package log file.
Function drvLog{

	param(
		[string]$driverLog
	)

	if( $driverLog -AND (Test-Path -Path $driverLog -PathType leaf) ){

		foreach($line in Get-Content $driverLog) {
			$gpu=$line.Split(",")
			log "$($gpu[0]) driver package gathered for: $($gpu[1])"
		}
		
		log "See driver detection logs for details: $driverLog"
	}	
}

# Determines drivers in the packages directory.
Function getDriverPackagesAuto{

	$folderPacks = Get-ChildItem -Path "$packPath\*" -Directory -Force -ErrorAction SilentlyContinue
	$zipPacks    = Get-ChildItem -Path "$packPath\*" -include *.zip -Force -ErrorAction SilentlyContinue

	$count=0

	if($zipPacks -AND ($zipPacks.count -gt 0)){

		foreach($zipPack in $zipPacks){

			$count++;

			$driver = cacheDriver $zipPack
			$script:driverPacks += $driver

			log "$($driver.fname) package found in $packPath." "info"
		}
	}

	if($folderPacks -AND ($folderPacks.count -gt 0)){

		foreach($folderPack in $folderPacks){

			$foundZip=$false

			foreach($driver in $driverPacks){

				if( $driver.path -eq "$folderPack.zip" ){

					$foundZip=$true
					break
				}
			}

			if($foundZip){
				log "`"$(Split-Path $folderPack -leaf)`" package already exists as zip. Folder package skipped." "notice"
			}
			else{

				$count++;

				$driver = cacheDriver $folderPack

				$script:driverPacks += $driver

				log "$($driver.fname) package folder found in $packPath." "info"
			}		
		}
	}

	if($count -eq 0){
		log "No driver zip or folder package found to install." "error"	
	}
}

# Filters drivers in the packages directory based on the given -DRV parameter. 
Function getDriverPackagesByInput{

	foreach($driverName in $driverInput){

		$pack="$packPath\$driverName"

		if (Test-Path -Path $pack -PathType Leaf) {

			$script:driverPacks += cacheDriver $pack

			log "$driverName package found in $packPath." "info"

		}
		elseif(Test-Path -Path $pack) {

			$script:driverPacks += cacheDriver $pack

			log "$driverName package folder found in $packPath." "info"

		} else {
			log "No $driverName package found to install." "error"
		}
	}
}

# -----------------
# --- Processes ---
# -----------------

# Driver installation main process
Function process_installDrivers{

	""
	# If driver package source is given directly with -DRVSRC parameter.
	if($drvsrc){

		# Install driver.
		if( (Test-Path -Path $drvsrc -PathType Leaf) -or (Test-Path -Path $drvsrc) ){	

			$driver = cacheDriver $drvsrc
			installDriverFiles $driver
		}
		else{
			log "Unable to find driver directory. Please check -DRVSRC parameter." "error"
			""
			exit
		}
	}

	# Determine driver packages directory.
	else{
		
		# If driver package directory is given with -SRC parameter.
		if($src){
		
			if(Test-Path -Path $src){
	
				$packPath=$src
				log "Driver packages will be copied from $packPath" "info"
			}
			else{
				log "Unable to find $packPath driver packages directory. Please check -SRC parameter." "error"
				""

				writeLog
				exit
			}
		}

		# Or use script directory.
		else{
	
			$packPath= "$PSScriptRoot\hostdrivers"

			if (Test-Path -Path $packPath) {
				log "Driver packages will be copied from $packPath" "info"
			}
			else{
				log "Unable to find $packPath driver packages directory." "error"
				""
	
				writeLog
				exit
			}
		}
	
		# Determine drivers in packages directory.
		if($driverInput.Count -eq 0){
			getDriverPackagesAuto
		}else{
			getDriverPackagesByInput
		}

		# Install drivers.
		foreach($driver in $driverPacks){
	
			installDriverFiles $driver
		}

	}

	writeLog
}

# -----------------
# --- Run ---------
# -----------------

# Checks
checkAdministrator
#isVmCheck

# Main
process_InstallDrivers
""

