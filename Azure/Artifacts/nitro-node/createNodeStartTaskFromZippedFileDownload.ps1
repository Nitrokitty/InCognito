param(
	[string]
	$ZippedFileURL,
	
	[string]
	$OutDirectoryPath,
	
	[string]
	$HubURL,
	
	[int]
	$HubPort,
	
	[int]
	$NodePort,
	
	[string]
	$UserName,
	
	[string]
	$Password,
	
	[switch]
	$StartGridNow = $false
)

$ErrorActionPreference = "Stop"
$ZippedFileName = "ZippedSetupItems"
$FirewallRuleName = "SeleniumNodePort"


Add-Type -AssemblyName System.IO.Compression.FileSystem

function Unzip
{
    param(
		[string]
		$ZippedFile, 
		
		[string]
		$OutPath
	)

    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZippedFile, $OutPath)
}

function CreateTask
{
	param(

		[string]
		$CommandPath,
			
		[string]
		$TaskName,
		
		[string]
		$TaskDescription,
		
		[string]
		$UserName,
	
		[string]
		$Password
	)

	$action = New-ScheduledTaskAction -Execute $CommandPath
	$trigger = New-ScheduledTaskTrigger -AtStartup
	Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $TaskName -Description $TaskDescription -User $UserName -Password $Password
}
	
if(Test-Path $OutDirectoryPath){
	Write-Host "Cleaning up old installation"
	Remove-Item -path $OutDirectoryPath -recurse	
	$tsk = ((Get-ScheduledTask).TaskName | Where-Object { $_ -like "StartNode" })
	if($tsk) {
		Unregister-ScheduledTask -TaskName $tsk -confirm:$false 
	}
}  else {
	Write-Host "Creating Firewall Exception"		
	$temp = New-NetFirewallRule -localport $NodePort -displayname "${FirewallRuleName}IN" -direction inbound -action allow -protocol tcp -remotePort Any 
	$temp = New-NetFirewallRule -localport $NodePort -displayname "${FirewallRuleName}OUT" -direction outbound -action allow -protocol tcp -remotePort Any 
}


Write-Host "Creating directory: $OutDirectoryPath"
$temp = [system.io.directory]::CreateDirectory($OutDirectoryPath)

Write-Host "Retrieving Zipped File" -NoNewLine
$ZippedFilePath = $OutDirectoryPath + "\\" + $ZippedFileName + ".zip"

Invoke-WebRequest -Uri $ZippedFileURL -OutFile $ZippedFilePath
Write-Host " ....Unzipping" -NoNewLine
Unzip $ZippedFilePath $OutDirectoryPath
Write-Host " ....Deleting Zipped File" 
Remove-Item -path $ZippedFilePath

Write-Host "Retrieving Information:"
Write-Host "`tNode Config File: " -NoNewLine
$configFilePath = [string]($OutDirectoryPath + "\" + ((Get-Item "$OutDirectoryPath\*").Name | Where-Object {$_ -like "*config*"}))
Write-Host "$configFilePath`n`tJar File: " -NoNewLine
$jarFilePath = [string]($OutDirectoryPath + "\" + ((Get-Item "$OutDirectoryPath\*").Name | Where-Object {$_ -like "*selenium-server*"}))
Write-Host "$jarFilePath`n`tJava Path: " -NoNewLine

if(Test-Path "C:\Program Files\Java"){
	$javaPath =  "C:\Program Files\Java\" + ([string](Get-ChildItem -Path "C:\Program Files\Java\").Name) + "\bin\java.exe"
} else {
	$javaPath = [string](Get-Command java).Definition
}

$HubURL = "${hubUrl}:$HubPort/grid/register"
Write-Host "$javaPath`n`tHub URL: $HubURL"
$arguments = '"' + $javaPath +'" -jar -Dfile.encoding=UTF-8 ' + $jarFilePath + ' -role node -hub ' + $HubURL + ' -host %computername% -nodeConfig ' + $configFilePath

Write-Host "`tStart Command: $arguments"

Write-Host "Saving Start Command"
$startCMDPath = "$OutDirectoryPath\node-start.cmd"

Write-Host "Creating Startup Task"
$temp = New-Item $startCMDPath -type file -value $arguments

$temp = CreateTask -CommandPath $startCMDPath -TaskName "StartNode" -TaskDescription "Start Selenium Node Service" -UserName $UserName -Password $Password

if($StartGridNow) {
	Write-Host "Starting Node"
	$temp = "/c $startCMDPath"
	Start-Process cmd.exe -ArgumentList $temp
}

Write-Host "Fin"

