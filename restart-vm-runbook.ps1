param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "rg-test-monitoring",
    
    [Parameter(Mandatory=$false)]
    [string]$VMName = "vm-ecommerce-prod",
    
    [Parameter(Mandatory=$false)]
    [object]$WebhookData
)

Write-Output "=========================================="
Write-Output "Iniciando runbook de reinicio de VM"
Write-Output "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "=========================================="

try {
    # Conectar usando Managed Identity
    Write-Output "Conectando a Azure con Managed Identity..."
    Connect-AzAccount -Identity -ErrorAction Stop
    Write-Output "Conexión exitosa"
    
    # Obtener información de la VM
    Write-Output "`nObteniendo estado de la VM..."
    Write-Output "  Resource Group: $ResourceGroupName"
    Write-Output "  VM Name: $VMName"
    
    $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Status -ErrorAction Stop
    
    if ($null -eq $vm) {
        throw "VM no encontrada: $VMName"
    }
    
    $powerState = ($vm.Statuses | Where-Object {$_.Code -like "PowerState/*"}).DisplayStatus
    Write-Output "  Estado actual: $powerState"
    
    # Reiniciar la VM
    if ($powerState -eq "VM running") {
        Write-Output "`nReiniciando VM..."
        Restart-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -NoWait -ErrorAction Stop
        Write-Output " Comando de reinicio enviado exitosamente"
        Write-Output "  La VM se reiniciará en los próximos minutos"
    }
    elseif ($powerState -eq "VM stopped" -or $powerState -eq "VM deallocated") {
        Write-Output "`n VM está detenida. Iniciando VM..."
        Start-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -NoWait -ErrorAction Stop
        Write-Output " Comando de inicio enviado"
    }
    else {
        Write-Output "`n Estado inesperado de VM: $powerState"
        Write-Output "  No se realiza ninguna acción"
    }
    
    Write-Output "`n=========================================="
    Write-Output "Runbook completado exitosamente"
    Write-Output "=========================================="
}
catch {
    Write-Error " Error en el runbook: $($_.Exception.Message)"
    Write-Error "Stack Trace: $($_.Exception.StackTrace)"
    throw
}
