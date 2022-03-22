<# vRA 8.x ABX action to perform certain in-guest actions post-deploy:
    Windows:
        - auto-update VM tools
    
    ## Action Secrets:
        templatePassWinDomain                   # password for domain account with admin rights to the template (domain-joined deployments)
        templatePassWinWorkgroup                # password for local account with admin rights to the template (standalone deployments)
        vCenterPassword                         # password for vCenter account passed from the cloud template
    
    ## Action Inputs:
    ## Inputs from deployment:
        resourceNames[0]                        # VM name [BOW-DVRT-XXX003]
        customProperties.vCenterUser            # user for connecting to vCenter [lab\vra]
        customProperties.vCenter                # vCenter instance to connect to [vcsa.lab.bowdre.net]
        customProperties.templateUser           # username used for connecting to the VM through vmtools [Administrator] / [root]
#>

function handler($context, $inputs) {
    # Initialize global variables
    $vcUser = $inputs.customProperties.vCenterUser
    $vcPassword = $context.getSecret($inputs."vCenterPassword")
    $vCenter = $inputs.customProperties.vCenter
    
    # Create vmtools connection to the VM 
    $vmName = $inputs.resourceNames[0]
    Connect-ViServer -Server $vCenter -User $vcUser -Password $vcPassword -Force
    $vm = Get-VM -Name $vmName
    Write-Host "Waiting for VM Tools to start..."
    if (-not (Wait-Tools -VM $vm -TimeoutSeconds 180)) {
        Write-Error "Unable to establish connection with VM tools" -ErrorAction Stop
    }
    
    # Wait for VMTools and Detect OS type
    $count = 0
    While (!$osType) {
        Try {
            $osType = ($vm | Get-View).Guest.GuestFamily.ToString()
            $toolsStatus = ($vm | Get-View).Guest.ToolsStatus.ToString()        
        } Catch {
            # 60s timeout
            if ($count -ge 12) {
                Write-Error "Timeout exceeded while waiting for tools." -ErrorAction Stop
                break
            }
            Write-Host "Waiting for tools..."
            $count++
            Sleep 5
        }
    }
    Write-Host "$vmName is a $osType and its tools status is $toolsStatus."
    
    # Update tools on Windows if out of date
    if ($osType.Equals("windowsGuest") -And $toolsStatus.Equals("toolsOld")) {
        Write-Host "Updating VM Tools..."
        Update-Tools $vm
        Write-Host "Waiting for VM Tools to start..."
        if (-not (Wait-Tools -VM $vm -TimeoutSeconds 180)) {
            Write-Error "Unable to establish connection with VM tools" -ErrorAction Stop
        }
    }
    
    # Run OS-specific tasks
    if ($osType.Equals("windowsGuest")) {
        # Initialize Windows variables
        $templateUser = $inputs.customProperties.templateUser
        $templatePassword = $adJoin.Equals("true") ? $context.getSecret($inputs."templatePassWinDomain") : $context.getSecret($inputs."templatePassWinWorkgroup")

        $script = "Get-Host"
        Write-Host "Running Script..."
        $runScript = Invoke-VMScript -VM $vm -ScriptText $script -GuestUser $templateUser -GuestPassword $templatePassword
      
        
    } elseif ($osType.Equals("linuxGuest")) {
        #TODO
        Write-Host "Linux systems not supported by this action... yet"
    }
    # Cleanup connection
    Disconnect-ViServer -Server $vCenter -Force -Confirm:$false

}
