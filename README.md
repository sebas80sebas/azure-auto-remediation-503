# Automated VM Monitoring and Restart System in Azure

Automated system that detects HTTP 503 errors on a web server and automatically restarts a production VM using Azure Application Insights, Log Analytics, and Automation Accounts.

## Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [System Components](#system-components)
- [Installation and Configuration](#installation-and-configuration)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

## Architecture

```
┌─────────────────┐
│  Internet User  │
└────────┬────────┘
         │ HTTP Request
         ▼
┌─────────────────────────┐
│  VM Web Server (Nginx)  │
│  - Python Flask App     │
│  - Simulates HTTP codes │
└────────┬────────────────┘
         │
         ▼
┌──────────────────────────┐
│ Application Insights     │
│ - Availability Tests     │
│ - Detects HTTP 503       │
└────────┬─────────────────┘
         │ Alert
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
         │ Execute
         ▼
┌──────────────────────────┐
│  Automation Account      │
│  - PowerShell Runbook    │
│  - Managed Identity      │
└────────┬─────────────────┘
         │ Restart
         ▼
┌──────────────────────────┐
│  Production VM           │
│  (vm-ecommerce-prod)     │
└──────────────────────────┘
```

## Prerequisites

- Active Azure subscription
- Contributor permissions on the Resource Group
- SSH client (for configuring Linux VMs)
- Azure CLI (optional, for terminal management)

## System Components

### 1. VM Web Server (vm-webserver-test)
- **OS**: Ubuntu Server 22.04 LTS
- **Size**: Standard_B2s
- **Services**: Nginx + Python Flask
- **Purpose**: Simulate different HTTP codes for testing

### 2. Production VM (vm-ecommerce-prod)
- **OS**: Windows or Ubuntu 22.04
- **Size**: Standard_B2s
- **Purpose**: VM that restarts automatically on errors

### 3. Application Insights (appi-monitoring-test)
- **Availability Test**: Monitoring every 5 minutes
- **Locations**: West Europe, North Europe, UK South
- **Endpoint**: `/health`

### 4. Automation Account (aa-vm-restart-automation)
- **Runtime**: PowerShell 7.2
- **Identity**: System-assigned Managed Identity
- **Runbook**: Restart-VMOn503

### 5. Alert Rule
- **Query**: Detects HTTP 503 in 5-minute windows
- **Frequency**: Evaluation every 5 minutes
- **Severity**: Critical (Sev 0)

## Installation and Configuration

### Step 1: Create Resource Group

```bash
# From Azure Portal
Resource Groups → + Create → rg-test-monitoring
```

### Step 2: Deploy VM Web Server

#### 2.1 Create VM

```
Azure Portal → Virtual Machines → + Create

Configuration:
- Resource Group: rg-test-monitoring
- VM name: vm-webserver-test
- Region: West Europe
- Image: Ubuntu Server 22.04 LTS
- Size: Standard_B2s
- Authentication: SSH public key
- Username: azureuser
- Inbound ports: 80 (HTTP), 22 (SSH)
```

#### 2.2 Configure Local SSH

```bash
# Create .ssh directory if it doesn't exist
mkdir -p ~/.ssh

# Move the downloaded key
mv ~/Downloads/vm-webserver-test_key.pem ~/.ssh/vm-webserver-test_key.pem

# Change permissions (mandatory for SSH)
chmod 600 ~/.ssh/vm-webserver-test_key.pem

# Connect to the VM
ssh -i ~/.ssh/vm-webserver-test_key.pem azureuser@<PUBLIC-IP>
```

#### 2.3 Install Software on the VM

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Nginx
sudo apt install nginx -y

# Verify installation
curl http://localhost

# Install Python and Flask
sudo apt install python3-pip -y
sudo pip3 install flask
```

#### 2.4 Create Flask Application

```bash
sudo nano /home/azureuser/test-server.py
```

Paste the Python script content (provided in documentation).

#### 2.5 Create Systemd Service

```bash
sudo nano /etc/systemd/system/test-server.service
```

Paste the service configuration (provided in documentation).

```bash
# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable test-server
sudo systemctl start test-server

# Verify status
sudo systemctl status test-server
curl http://localhost:5000/health
```

#### 2.6 Configure Nginx as Reverse Proxy

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
# Verify configuration and restart
sudo nginx -t
sudo systemctl restart nginx
```

#### 2.7 Open Port 80 in NSG

```
VM → Networking → Add inbound port rule
- Destination port ranges: 80
- Protocol: TCP
- Name: Allow-HTTP
```

### Step 3: Create Production VM

```
Azure Portal → Virtual Machines → + Create

- Resource Group: rg-test-monitoring
- VM name: vm-ecommerce-prod
- Region: West Europe
- Image: Ubuntu 22.04 / Windows
- Size: Standard_B2s
```

### Step 4: Configure Application Insights

```
Portal → Application Insights → + Create

- Resource Group: rg-test-monitoring
- Name: appi-monitoring-test
- Region: West Europe
```

#### 4.1 Create Availability Test

```
Application Insights → Availability → Add Standard test

- Test name: test-webserver-health
- URL: http://<VM-IP>/health
- Test frequency: 5 minutes
- Test locations: West Europe, North Europe, UK South
- Test timeout: 30 seconds
- Enable retries: No
```

**Wait 5-10 minutes** for data to start arriving.

### Step 5: Configure Automation Account

#### 5.1 Create Automation Account

```
Portal → Automation Accounts → + Create

- Name: aa-vm-restart-automation
- Resource Group: rg-test-monitoring
- Region: West Europe
```

#### 5.2 Enable Managed Identity

```
Automation Account → Identity → System assigned
- Status: On
- Save
```

**Copy the generated Object ID**.

#### 5.3 Assign Permissions

```
Portal → Resource Groups → rg-test-monitoring → Access control (IAM)

Add role assignment:
- Role: Virtual Machine Contributor
- Assign access to: Managed Identity
- Members: aa-vm-restart-automation
- Review + assign
```

#### 5.4 Create Runbook

```
Automation Account → Runbooks → + Create a runbook

- Name: Restart-VMOn503
- Runbook type: PowerShell
- Runtime version: 7.2
```

Paste the PowerShell code (provided in documentation).

**Save → Publish → Yes**

#### 5.5 Test Runbook Manually

```
Runbook → Start

Parameters (optional):
- ResourceGroupName: rg-test-monitoring
- VMName: vm-ecommerce-prod
```

Verify in the Output that it executes correctly.

### Step 6: Configure Alerts

#### 6.1 Create Action Group

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

#### 6.2 Create Alert Rule

```
Monitor → Alerts → + Create → Alert rule

Scope: appi-monitoring-test
Condition: Custom log search
```

**KQL Query:**

```kusto
availabilityResults
| where timestamp > ago(10m)
| where name == "test-webserver-health"
| where resultCode == "503"
| summarize Count503 = count(), 
            LastFailure = max(timestamp) by bin(timestamp, 5m)
| where Count503 >= 1
```

**Configuration:**

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

## Testing

### Test 1: Verify Normal Monitoring

```bash
# Verify healthy status
curl http://<VM-IP>/health

# Should return: 200 OK
```

Wait 10 minutes and verify in:
- **Application Insights → Availability**: Green dots on the chart

### Test 2: Simulate 503 Error

```bash
# Connect to the VM
ssh -i ~/.ssh/vm-webserver-test_key.pem azureuser@<VM-IP>

# Activate error 503 mode
curl http://localhost:5000/set-mode/error503

# Verify
curl http://localhost/health
# Should return: 503 Service Unavailable
```

**Wait 10-15 minutes** and verify:

1. **Monitor → Alerts**: Active alert named `alert-503-restart-vm`
2. **Automation Account → Jobs**: Job `Restart-VMOn503` running
3. **Production VM → Activity log**: Event "Restart Virtual Machine"

### Test 3: Verify that 404 Does NOT Restart

```bash
# Change to 404 mode
curl http://<VM-IP>/set-mode/error404

# Verify
curl http://<VM-IP>/health
# Should return: 404 Not Found
```

**Wait 10-15 minutes** and verify:

- Availability test records the 404
- **NO** alert is triggered
- **NO** VM restart occurs

### Test 4: Restore to Normal

```bash
# Return to healthy mode
curl http://<VM-IP>/set-mode/healthy

# Verify
curl http://<VM-IP>/health
# Should return: 200 OK
```

## Troubleshooting

### Problem: No data arriving at Application Insights

**Solution:**
```bash
# Verify that the test is active
Application Insights → Availability → Verify test enabled

# Verify that the VM is publicly accessible
curl http://<VM-IP>/health
```

### Problem: Alert is not triggered

**Solution:**
```kusto
// Execute query manually in Log Analytics
availabilityResults
| where timestamp > ago(1h)
| where name == "test-webserver-health"
| summarize count() by resultCode
```

Verify that there are records with `resultCode == "503"`.

### Problem: Runbook fails with permissions error

**Solution:**
```
1. Verify that Managed Identity is enabled
2. Verify "Virtual Machine Contributor" role in IAM
3. Wait 5-10 minutes for permission propagation
```

### Problem: VM does not restart

**Solution:**
```
1. Automation Account → Jobs → Select last job
2. View "Output" and "Errors" for details
3. Verify that ResourceGroupName and VMName parameters are correct
```

## Available Endpoints

| Endpoint | Description | HTTP Code |
|----------|-------------|-----------|
| `/health` | Health endpoint (current mode) | Variable |
| `/set-mode/healthy` | Set healthy mode | 200 |
| `/set-mode/error503` | Simulate 503 error | 200 |
| `/set-mode/error404` | Simulate 404 error | 200 |
| `/status` | View current mode | 200 |

## Metrics and Logs

### View Availability Test logs

```kusto
availabilityResults
| where timestamp > ago(1h)
| project timestamp, name, location, success, resultCode, duration
| order by timestamp desc
```

### View alert history

```kusto
AzureActivity
| where OperationNameValue == "MICROSOFT.INSIGHTS/ALERTRULES/ACTIVATED/ACTION"
| where timestamp > ago(24h)
| project timestamp, Caller, OperationNameValue, ActivityStatusValue
```

### View VM restart history

```
VM → Activity log → Filter: "Restart Virtual Machine"
```

## Resource Cleanup

To delete all created resources:

```bash
# From Azure Portal
Resource Groups → rg-test-monitoring → Delete resource group
```

Or from Azure CLI:

```bash
az group delete --name rg-test-monitoring --yes --no-wait
```

## Important Notes

- **Costs**: This setup generates costs for VMs, Application Insights, and Automation
- **Availability Tests**: Limited to 100 tests per subscription
- **Runbook Jobs**: History limited to 30 days
- **Minimum frequency**: Availability tests have a minimum frequency of 5 minutes