# Driver Installer for HyperPoint v1.0.0
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
$driverPacks  = [System.Collections.ArrayList]::new()
$lockedDB     = @()
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

		log "$($process.FilePath) is still locked by $($process.ProcessName) (PID:$($process.ProcessID))."
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
		[string]$srcPath,
		[string]$destPath
	)

	$lockedExists=$false

	log "Starting to check driver files. Please wait."

	Get-ChildItem -Path $srcPath -File -Recurse -ErrorAction SilentlyContinue -Force | % {

		$script:fileCount++
		
		$destFile=$($_.FullName).replace($srcPath,$destPath)


		if(Test-Path $destFile -PathType Leaf){

			if(isLocked $destFile){

				$processes = getFileLockingProcesses $destFile

				$script:lockedDB += $processes

				foreach($process in $processes){

					$lockedExists=$true

					log "$($process.FilePath) is locked by $($process.ProcessName) (PID:$($process.ProcessID))" "warning"

				}
			}
		}
	}

	if($lockedExists){

		if($force){

			if(-Not (terminateProcesses $lockedDB)){

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
		[string]$srcPath,
		[string]$destPath
	)

	log "Starting to copy $($script:fileCount) driver files to system. Existing files will be overwritten. Please wait."

	$i=1;
	$len=$script:fileCount
	$per=100/$len

	Get-ChildItem -Path $srcPath -File -Recurse -ErrorAction SilentlyContinue -Force | ForEach-Object {

		$currPer=[int]($i*$per)
		Write-Progress -Activity "Installing Driver Files" -Status "$currPer% Copied:" -PercentComplete $currPer
		$i++

		$fullName=$_.FullName
		$destFile=$fullName.replace($srcPath,$destPath)

		$destDir = Split-Path -Path $destFile -Parent

		if (-not (Test-Path -Path $destDir)) {
		    New-Item -Path $destDir -ItemType Directory -Force
		}

		try{
			Copy-Item -Path $fullName -Destination $destFile -Force -Recurse
			$script:copiedCount++
		}
		catch{
			log "$fullName could not be copied." "error"
		}
	}
}

# Copies driver package folder contents to the system.
Function copyFromFolder{

	param(
		[string]$driverPath
	)

	$tempPath=$driverPath
	$destPath="C:"

	checkFiles $tempPath $destPath
	copyFiles  $tempPath $destPath

	 return $true
}

# Copies driver zip package contents to the system.
Function copyFromZip{

	param(
		[string]$driverPath
	)

	if(Test-Path -Path $driverPath -PathType leaf){

		# zip package

		$drvName=$($(Split-Path $driverPath -leaf)).Replace(".zip", "")
		$tempPath="$env:TEMP\$drvName"
		$destPath="C:"

		if (-not (Test-Path -Path $tempPath)) {
		    New-Item -Path $tempPath -ItemType Directory -Force
		}

		log "Starting to extract driver files to temp directory. Please wait."

		Start-Sleep 2

		Expand-Archive -Path $driverPath -DestinationPath $tempPath -Force

		if($?){

			log "Extraction completed."

			if(Test-Path -Path $tempPath){

				checkFiles $tempPath $destPath
				 copyFiles $tempPath $destPath

				 return $true
			}
			else{

				log "Unable to access temp directory: $tempPath" "error"
			}
		}
		else{
			log "Unable to extract driver files to temp directory: $tempPath" "error"
		}
	}
}

# Driver installation.
Function copyDriverFiles{

	param($driverPath)

	$driverName = "$($(Split-Path $driverPath -leaf).replace('.zip',''))"
	$fin        = $false
	$driverLog  = $null
	

	if(-Not $driverPath){

		log "Driver package value is empty." "error"
		return $null
	}

	if(Test-Path -Path $driverPath -PathType leaf){

		# zip package
		$fin = copyFromZip $driverPath
		#$driverLog="$packPath\$($(Split-Path $driverPath -leaf).replace('.zip','.txt'))"
		
	}
	elseif(Test-Path -Path $driverPath){

		# folder package
		$fin = copyFromFolder $driverPath
		#$driverLog="$driverPath.txt"
	}

	if($fin){

		#drvLog $driverLog

		$diff=$script:fileCount - $script:copiedCount

		if($diff -gt 0){

			$logStr  = "$driverName installation completed but $diff driver file(s) cannot be copied."
			$logStr += "Stop processes and services above, then re-run this script or manually copy locked files."

			log $logStr "warning"
		}
		else{
			log "$driverName installation completed successfully. $($script:copiedCount) driver files copied from $driverPath to Windows." "success"
		}

		
		log "Don't forget to (re)assign GPU(s) to VM." "notice"

		
	}
	else{
		log "Errors occured while installing driver files from $driverPath to C:\windows." "error"
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

	$paths = Get-ChildItem -Path "$packPath\*" -Directory -Force -ErrorAction SilentlyContinue
	$zips  = Get-ChildItem -Path "$packPath\*" -include *.zip -Force -ErrorAction SilentlyContinue

	$count=0

	if($zips -AND ($zips.count -gt 0)){

		foreach($zip in $zips){

			$count++;
			$driverPacks.Add("$zip") | Out-Null
			log "`"$(Split-Path $zip -leaf)`" package found in $packPath." "info"
		}
	}

	if($paths -AND ($paths.count -gt 0)){

		:findPaths foreach($path in $paths){

			$foundZip=$false

			foreach($driver in $driverPacks){

				if( $driver -eq "$path.zip" ){

					$foundZip=$true
					break
				}
			}

			if($foundZip){
				log "`"$(Split-Path $path -leaf)`" package already exists as zip. Folder package skipped." "notice"
			}
			else{

				$count++;
				$driverPacks.Add("$path") | Out-Null
				log "`"$(Split-Path $path -leaf)`" package folder found in $packPath." "info"
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

		$path="$packPath\$driverName"

		if (Test-Path -Path $path -PathType Leaf) {

			$driverPacks.Add("$path") | Out-Null
			log "`"$driverName`" package found in $packPath." "info"

		}
		elseif(Test-Path -Path $path) {

			$driverPacks.Add("$path") | Out-Null
			log "`"$driverName`" package folder found in $packPath." "info"

		} else {
			log "No `"$driverName`" package found to install." "error"
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
			copyDriverFiles $drvsrc
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
		foreach($driverPack in $driverPacks){
	
			copyDriverFiles $driverPack
		}

	}

	writeLog
}

# -----------------
# --- Run ---------
# -----------------

# Checks
checkAdministrator
isVmCheck

# Main
process_InstallDrivers
""

