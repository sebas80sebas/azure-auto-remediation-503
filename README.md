# Sistema de Monitoreo y Reinicio Automático de VMs en Azure

Sistema automatizado que detecta errores HTTP 503 en un servidor web y reinicia automáticamente una VM de producción utilizando Azure Application Insights, Log Analytics y Automation Accounts.

## 📋 Tabla de Contenidos

- [Arquitectura](#arquitectura)
- [Requisitos Previos](#requisitos-previos)
- [Componentes del Sistema](#componentes-del-sistema)
- [Instalación y Configuración](#instalación-y-configuración)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

## 🏗️ Arquitectura

```
┌─────────────────┐
│  Internet User  │
└────────┬────────┘
         │ HTTP Request
         ▼
┌─────────────────────────┐
│  VM Web Server (Nginx)  │
│  - Python Flask App     │
│  - Simula códigos HTTP  │
└────────┬────────────────┘
         │
         ▼
┌──────────────────────────┐
│ Application Insights     │
│ - Availability Tests     │
│ - Detecta HTTP 503       │
└────────┬─────────────────┘
         │ Alerta
         ▼
┌──────────────────────────┐
│  Azure Monitor           │
│  - Log Query Alert       │
└────────┬─────────────────┘
         │ Trigger
         ▼
┌──────────────────────────┐
│  Action Group            │
└────────┬─────────────────┘
         │ Ejecuta
         ▼
┌──────────────────────────┐
│  Automation Account      │
│  - PowerShell Runbook    │
│  - Managed Identity      │
└────────┬─────────────────┘
         │ Reinicia
         ▼
┌──────────────────────────┐
│  VM Producción           │
│  (vm-ecommerce-prod)     │
└──────────────────────────┘
```

## ✅ Requisitos Previos

- Suscripción activa de Azure
- Permisos de Contributor en el Resource Group
- Cliente SSH (para configurar VMs Linux)
- Azure CLI (opcional, para gestión desde terminal)

## 🔧 Componentes del Sistema

### 1. VM Web Server (vm-webserver-test)
- **SO**: Ubuntu Server 22.04 LTS
- **Tamaño**: Standard_B2s
- **Servicios**: Nginx + Python Flask
- **Propósito**: Simular diferentes códigos HTTP para testing

### 2. VM Producción (vm-ecommerce-prod)
- **SO**: Windows o Ubuntu 22.04
- **Tamaño**: Standard_B2s
- **Propósito**: VM que se reinicia automáticamente ante errores

### 3. Application Insights (appi-monitoring-test)
- **Availability Test**: Monitoreo cada 5 minutos
- **Ubicaciones**: West Europe, North Europe, UK South
- **Endpoint**: `/health`

### 4. Automation Account (aa-vm-restart-automation)
- **Runtime**: PowerShell 7.2
- **Identity**: System-assigned Managed Identity
- **Runbook**: Restart-VMOn503

### 5. Alert Rule
- **Query**: Detecta HTTP 503 en ventanas de 5 minutos
- **Frecuencia**: Evaluación cada 5 minutos
- **Severidad**: Critical (Sev 0)

## 🚀 Instalación y Configuración

### Paso 1: Crear Resource Group

```bash
# Desde Azure Portal
Resource Groups → + Create → rg-test-monitoring
```

### Paso 2: Desplegar VM Web Server

#### 2.1 Crear VM

```
Azure Portal → Virtual Machines → + Create

Configuración:
- Resource Group: rg-test-monitoring
- VM name: vm-webserver-test
- Region: West Europe
- Image: Ubuntu Server 22.04 LTS
- Size: Standard_B2s
- Authentication: SSH public key
- Username: azureuser
- Inbound ports: 80 (HTTP), 22 (SSH)
```

#### 2.2 Configurar SSH Local

```bash
# Crear directorio .ssh si no existe
mkdir -p ~/.ssh

# Mover la clave descargada
mv ~/Downloads/vm-webserver-test_key.pem ~/.ssh/vm-webserver-test_key.pem

# Cambiar permisos (obligatorio para SSH)
chmod 600 ~/.ssh/vm-webserver-test_key.pem

# Conectar a la VM
ssh -i ~/.ssh/vm-webserver-test_key.pem azureuser@<IP-PUBLICA>
```

#### 2.3 Instalar Software en la VM

```bash
# Actualizar sistema
sudo apt update && sudo apt upgrade -y

# Instalar Nginx
sudo apt install nginx -y

# Verificar instalación
curl http://localhost

# Instalar Python y Flask
sudo apt install python3-pip -y
sudo pip3 install flask
```

#### 2.4 Crear Aplicación Flask

```bash
sudo nano /home/azureuser/test-server.py
```

Pegar el contenido del script Python (proporcionado en documentación).

#### 2.5 Crear Servicio Systemd

```bash
sudo nano /etc/systemd/system/test-server.service
```

Pegar la configuración del servicio (proporcionada en documentación).

```bash
# Activar y arrancar el servicio
sudo systemctl daemon-reload
sudo systemctl enable test-server
sudo systemctl start test-server

# Verificar estado
sudo systemctl status test-server
curl http://localhost:5000/health
```

#### 2.6 Configurar Nginx como Proxy Reverso

```bash
sudo nano /etc/nginx/sites-available/default
```

```nginx
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    location / {
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

```bash
# Verificar configuración y reiniciar
sudo nginx -t
sudo systemctl restart nginx
```

#### 2.7 Abrir Puerto 80 en NSG

```
VM → Networking → Add inbound port rule
- Destination port ranges: 80
- Protocol: TCP
- Name: Allow-HTTP
```

### Paso 3: Crear VM de Producción

```
Azure Portal → Virtual Machines → + Create

- Resource Group: rg-test-monitoring
- VM name: vm-ecommerce-prod
- Region: West Europe
- Image: Ubuntu 22.04 / Windows
- Size: Standard_B2s
```

### Paso 4: Configurar Application Insights

```
Portal → Application Insights → + Create

- Resource Group: rg-test-monitoring
- Name: appi-monitoring-test
- Region: West Europe
```

#### 4.1 Crear Availability Test

```
Application Insights → Availability → Add Standard test

- Test name: test-webserver-health
- URL: http://<IP-VM>/health
- Test frequency: 5 minutes
- Test locations: West Europe, North Europe, UK South
- Test timeout: 30 seconds
- Enable retries: No
```

**⏱️ Esperar 5-10 minutos** para que empiecen a llegar datos.

### Paso 5: Configurar Automation Account

#### 5.1 Crear Automation Account

```
Portal → Automation Accounts → + Create

- Name: aa-vm-restart-automation
- Resource Group: rg-test-monitoring
- Region: West Europe
```

#### 5.2 Habilitar Managed Identity

```
Automation Account → Identity → System assigned
- Status: On
- Save
```

**📝 Copiar el Object ID** generado.

#### 5.3 Asignar Permisos

```
Portal → Resource Groups → rg-test-monitoring → Access control (IAM)

Add role assignment:
- Role: Virtual Machine Contributor
- Assign access to: Managed Identity
- Members: aa-vm-restart-automation
- Review + assign
```

#### 5.4 Crear Runbook

```
Automation Account → Runbooks → + Create a runbook

- Name: Restart-VMOn503
- Runbook type: PowerShell
- Runtime version: 7.2
```

Pegar el código PowerShell (proporcionado en documentación).

**💾 Save → Publish → Yes**

#### 5.5 Probar Runbook Manualmente

```
Runbook → Start

Parámetros (opcional):
- ResourceGroupName: rg-test-monitoring
- VMName: vm-ecommerce-prod
```

Verificar en el Output que se ejecuta correctamente.

### Paso 6: Configurar Alertas

#### 6.1 Crear Action Group

```
Monitor → Alerts → Action groups → + Create

Basics:
- Resource Group: rg-test-monitoring
- Action group name: ag-restart-vm-on-503
- Display name: Restart VM

Actions:
- Add → Automation Runbook
- Name: RestartVMAction
- Runbook: Restart-VMOn503
- Run in: aa-vm-restart-automation
- Enable common alert schema: No
```

#### 6.2 Crear Alert Rule

```
Monitor → Alerts → + Create → Alert rule

Scope: appi-monitoring-test
Condition: Custom log search
```

**Query KQL:**

```kusto
availabilityResults
| where timestamp > ago(10m)
| where name == "test-webserver-health"
| where resultCode == "503"
| summarize Count503 = count(), 
            LastFailure = max(timestamp) by bin(timestamp, 5m)
| where Count503 >= 1
```

**Configuración:**

```
Measurement: Count503
Operator: Greater than
Threshold: 0
Aggregation granularity: 5 minutes
Frequency: Every 5 minutes

Actions: ag-restart-vm-on-503
Severity: Critical (Sev 0)
Alert rule name: alert-503-restart-vm
```

## 🧪 Testing

### Test 1: Verificar Monitoreo Normal

```bash
# Verificar estado saludable
curl http://<IP-VM>/health

# Debería retornar: 200 OK
```

Esperar 10 minutos y verificar en:
- **Application Insights → Availability**: Puntos verdes en el gráfico

### Test 2: Simular Error 503

```bash
# Conectar a la VM
ssh -i ~/.ssh/vm-webserver-test_key.pem azureuser@<IP-VM>

# Activar modo error 503
curl http://localhost:5000/set-mode/error503

# Verificar
curl http://localhost/health
# Debería retornar: 503 Service Unavailable
```

**⏱️ Esperar 10-15 minutos** y verificar:

1. **Monitor → Alerts**: Alerta activa con nombre `alert-503-restart-vm`
2. **Automation Account → Jobs**: Job `Restart-VMOn503` en ejecución
3. **VM Producción → Activity log**: Evento "Restart Virtual Machine"

### Test 3: Verificar que 404 NO Reinicia

```bash
# Cambiar a modo 404
curl http://<IP-VM>/set-mode/error404

# Verificar
curl http://<IP-VM>/health
# Debería retornar: 404 Not Found
```

**⏱️ Esperar 10-15 minutos** y verificar:

- ✅ Availability test registra el 404
- ✅ **NO** se dispara ninguna alerta
- ✅ **NO** se reinicia la VM

### Test 4: Restaurar a Normal

```bash
# Volver a modo saludable
curl http://<IP-VM>/set-mode/healthy

# Verificar
curl http://<IP-VM>/health
# Debería retornar: 200 OK
```

## 🔍 Troubleshooting

### Problema: No llegan datos a Application Insights

**Solución:**
```bash
# Verificar que el test está activo
Application Insights → Availability → Verificar test habilitado

# Verificar que la VM es accesible públicamente
curl http://<IP-VM>/health
```

### Problema: La alerta no se dispara

**Solución:**
```kusto
// Ejecutar query manualmente en Log Analytics
availabilityResults
| where timestamp > ago(1h)
| where name == "test-webserver-health"
| summarize count() by resultCode
```

Verificar que hay registros con `resultCode == "503"`.

### Problema: Runbook falla con error de permisos

**Solución:**
```
1. Verificar que Managed Identity está habilitada
2. Verificar rol "Virtual Machine Contributor" en IAM
3. Esperar 5-10 minutos para propagación de permisos
```

### Problema: VM no se reinicia

**Solución:**
```
1. Automation Account → Jobs → Seleccionar último job
2. Ver "Output" y "Errors" para detalles
3. Verificar que los parámetros ResourceGroupName y VMName son correctos
```

## 📊 Endpoints Disponibles

| Endpoint | Descripción | Código HTTP |
|----------|-------------|-------------|
| `/health` | Endpoint de salud (modo actual) | Variable |
| `/set-mode/healthy` | Establecer modo saludable | 200 |
| `/set-mode/error503` | Simular error 503 | 200 |
| `/set-mode/error404` | Simular error 404 | 200 |
| `/status` | Ver modo actual | 200 |

## 📈 Métricas y Logs

### Ver logs del Availability Test

```kusto
availabilityResults
| where timestamp > ago(1h)
| project timestamp, name, location, success, resultCode, duration
| order by timestamp desc
```

### Ver historial de alertas

```kusto
AzureActivity
| where OperationNameValue == "MICROSOFT.INSIGHTS/ALERTRULES/ACTIVATED/ACTION"
| where timestamp > ago(24h)
| project timestamp, Caller, OperationNameValue, ActivityStatusValue
```

### Ver historial de reinicios de VM

```
VM → Activity log → Filter: "Restart Virtual Machine"
```

## 🗑️ Limpieza de Recursos

Para eliminar todos los recursos creados:

```bash
# Desde Azure Portal
Resource Groups → rg-test-monitoring → Delete resource group
```

O desde Azure CLI:

```bash
az group delete --name rg-test-monitoring --yes --no-wait
```

## 📝 Notas Importantes

- **Costos**: Este setup genera costos por VMs, Application Insights y Automation
- **Availability Tests**: Limitado a 100 tests por suscripción
- **Runbook Jobs**: Historial limitado a 30 días
- **Frecuencia mínima**: Los tests de disponibilidad tienen frecuencia mínima de 5 minutos

