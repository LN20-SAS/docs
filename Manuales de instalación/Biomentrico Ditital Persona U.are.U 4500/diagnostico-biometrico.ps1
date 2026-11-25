<#
.SYNOPSIS
  Diagnostico (SOLO LECTURA) del lector DigitalPersona U.are.U 4500 con driver WBF
  y el HID Authentication Device Client (DPAgent, puerto 52181) para Maria Trazabilidad.

.DESCRIPTION
  No cambia nada del equipo. Revisa el lector, su driver y su cadena USB, la energia USB,
  el servicio de biometria de Windows, el agente local, los puertos, el certificado,
  las politicas, el navegador y los eventos de Windows de los ultimos dias.
  Deja un informe en el Escritorio.

  Con -MonitorMinutes se queda vigilando y anota con hora cada cambio (lector conectado o no,
  agente vivo o no, puerto, servicio de biometria, suspension del equipo). Sirve para cruzar
  con la hora exacta en que el usuario reporta la falla.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\diagnostico-biometrico.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\diagnostico-biometrico.ps1 -MonitorMinutes 480
.NOTES
  Ejecutar como administrador para ver la energia USB (WMI) y todos los eventos.
#>
param(
  [int]$Days = 7,
  [int]$MonitorMinutes = 0,
  [int]$MonitorSeconds = 5,
  [string]$OutDir = [Environment]::GetFolderPath('Desktop')
)

$ErrorActionPreference = 'Continue'
$DP_VID = 'VID_05BA'
$AGENT_PORT = 52181
$since = (Get-Date).AddDays(-$Days)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportFile = Join-Path $OutDir "diagnostico-biometrico-$env:COMPUTERNAME-$stamp.txt"
$findings = New-Object System.Collections.Generic.List[string]

function Add-Finding([string]$level, [string]$text) {
  $findings.Add(('[{0}] {1}' -f $level, $text))
}
function Write-Section([string]$title) {
  Write-Output ''
  Write-Output ('=' * 78)
  Write-Output ("  $title")
  Write-Output ('=' * 78)
}
function Test-Admin {
  $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-DeviceProps([string]$instanceId) {
  $props = @{}
  try {
    Get-PnpDeviceProperty -InstanceId $instanceId -ErrorAction Stop | ForEach-Object { $props[$_.KeyName] = $_.Data }
  } catch { }
  return $props
}
function Test-Listening([int]$port) {
  try {
    $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop
    return @($c)
  } catch { return @() }
}
function Get-AgentConnection {
  # Llama a get_connection como lo hace el SDK del navegador. No imprime usuario ni clave.
  $r = [ordered]@{ ok = $false; http = $null; seconds = $null; host = $null; wsPort = $null; secure = $null; error = $null }
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if (-not $curl) { $r.error = 'curl.exe no existe en este Windows'; return $r }
  $out = & curl.exe -k -s -m 6 -w "`n%{http_code} %{time_total}" "https://127.0.0.1:$AGENT_PORT/get_connection" 2>&1
  $lines = @($out -split "`n")
  $last = $lines[-1].Trim()
  $body = ($lines[0..([Math]::Max(0, $lines.Count - 2))] -join "`n")
  $parts = $last -split ' '
  $r.http = $parts[0]
  if ($parts.Count -gt 1) { $r.seconds = $parts[1] }
  if ($r.http -eq '200') {
    $m = [regex]::Match($body, 'web_sdk_port=(\d+)'); if ($m.Success) { $r.wsPort = [int]$m.Groups[1].Value }
    $m = [regex]::Match($body, 'web_sdk_secure=(\w+)'); if ($m.Success) { $r.secure = $m.Groups[1].Value }
    $m = [regex]::Match($body, '"endpoint"\s*:\s*"https?://([^:/"]+)'); if ($m.Success) { $r.host = $m.Groups[1].Value }
    $r.ok = [bool]$r.wsPort
    if (-not $r.ok) { $r.error = 'Respuesta 200 sin web_sdk_port' }
  } else {
    $r.error = "HTTP $($r.http) (000 = no hubo respuesta)"
  }
  return $r
}
function Get-AgentProcesses {
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '^(DPAgent|DpHost|DPCrStor)' -or ($_.ExecutablePath -and $_.ExecutablePath -match 'HID Global|DigitalPersona|Crossmatch')
  }
}

# ---------------------------------------------------------------------------
# Modo monitor
# ---------------------------------------------------------------------------
if ($MonitorMinutes -gt 0) {
  $monitorFile = Join-Path $OutDir "monitor-biometrico-$env:COMPUTERNAME-$stamp.txt"
  $end = (Get-Date).AddMinutes($MonitorMinutes)
  $prev = $null
  $prevTick = Get-Date
  $lastBeat = Get-Date
  $i = 0
  $agentCheck = 'sin probar'
  function Log([string]$t) { $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $t; Write-Output $line; Add-Content -Path $monitorFile -Value $line -Encoding UTF8 }
  Log "Inicio del monitor por $MonitorMinutes min, cada $MonitorSeconds s. Archivo: $monitorFile"
  while ((Get-Date) -lt $end) {
    $now = Get-Date
    $gap = ($now - $prevTick).TotalSeconds
    if ($gap -gt [Math]::Max(30, $MonitorSeconds * 4)) { Log ("SALTO de {0:N0} s sin muestras: posible suspension o hibernacion del equipo" -f $gap) }
    $prevTick = $now

    $readers = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match $DP_VID })
    $readerState = if ($readers.Count -eq 0) { 'AUSENTE' } else { ($readers | ForEach-Object { "$($_.Class)/$($_.Status)" }) -join ',' }
    $agents = @(Get-Process -Name DPAgent -ErrorAction SilentlyContinue)
    $agentState = if ($agents.Count -eq 0) { 'NO CORRE' } else { (($agents | ForEach-Object { 'pid {0} puerto {1}' -f $_.Id, ((@(Get-NetTCPConnection -OwningProcess $_.Id -State Listen -ErrorAction SilentlyContinue) | ForEach-Object { $_.LocalPort }) -join '/') }) -join ', ') }
    $portState = if (@(Test-Listening $AGENT_PORT).Count -gt 0) { 'escucha' } else { 'NO ESCUCHA' }
    $wbio = (Get-Service WbioSrvc -ErrorAction SilentlyContinue).Status
    if ($i % 6 -eq 0) {
      $ac = Get-AgentConnection
      if ($ac.ok) {
        $wsListen = if (@(Test-Listening $ac.wsPort).Count -gt 0) { 'escucha' } else { 'NO ESCUCHA' }
        $agentCheck = "get_connection ok, websocket $($ac.wsPort) $wsListen, conexiones del navegador " + @(Get-NetTCPConnection -LocalPort $ac.wsPort -State Established -ErrorAction SilentlyContinue).Count
      } else { $agentCheck = "get_connection FALLA: $($ac.error)" }
    }
    $state = "lector=$readerState | DPAgent=$agentState | 52181=$portState | WbioSrvc=$wbio | $agentCheck"
    if ($state -ne $prev) { Log "CAMBIO  $state"; $prev = $state; $lastBeat = $now }
    elseif (($now - $lastBeat).TotalMinutes -ge 15) { Log "sigue   $state"; $lastBeat = $now }
    $i++
    Start-Sleep -Seconds $MonitorSeconds
  }
  Log 'Fin del monitor'
  return
}

# ---------------------------------------------------------------------------
# Informe
# ---------------------------------------------------------------------------
Start-Transcript -Path $reportFile -Force | Out-Null
$isAdmin = Test-Admin
Write-Output "Diagnostico del biometrico - $env:COMPUTERNAME - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "Administrador: $isAdmin   Eventos desde: $($since.ToString('yyyy-MM-dd HH:mm'))"
if (-not $isAdmin) { Add-Finding 'INFO' 'No se ejecuto como administrador: falta la energia USB por WMI y quiza algunos eventos.' }

# 1. Equipo -----------------------------------------------------------------
Write-Section '1. Equipo'
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
Write-Output ("Windows: {0} {1} (build {2})" -f $os.Caption, $os.Version, $os.BuildNumber)
Write-Output ("Equipo: {0} {1}  Tipo: {2}" -f $cs.Manufacturer, $cs.Model, $cs.PCSystemType)
Write-Output ("Encendido desde: {0}" -f $os.LastBootUpTime)
$battery = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
Write-Output ("Bateria: {0}" -f $(if ($battery.Count) { "si (estado $($battery[0].BatteryStatus); 2 = conectado a la corriente)" } else { 'no' }))

# 2. Lector -----------------------------------------------------------------
Write-Section '2. Lector DigitalPersona (VID_05BA)'
$allDp = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match $DP_VID })
$presentDp = @($allDp | Where-Object { $_.Present })
if ($allDp.Count -eq 0) {
  Write-Output 'Windows no conoce ningun lector DigitalPersona (nunca se conecto o se desinstalo).'
  Add-Finding 'ALTO' 'Windows no tiene registrado ningun lector DigitalPersona.'
}
$readerIds = @()
foreach ($d in $allDp) {
  $p = Get-DeviceProps $d.InstanceId
  Write-Output ''
  Write-Output ("Dispositivo: {0}" -f $d.FriendlyName)
  Write-Output ("  Instancia: {0}" -f $d.InstanceId)
  Write-Output ("  Clase: {0}  Estado: {1}  Presente: {2}  Problema: {3}" -f $d.Class, $d.Status, $d.Present, $p['DEVPKEY_Device_ProblemCode'])
  Write-Output ("  Driver: {0} {1} ({2}) inf {3}" -f $p['DEVPKEY_Device_DriverProvider'], $p['DEVPKEY_Device_DriverVersion'], $p['DEVPKEY_Device_DriverDate'], $p['DEVPKEY_Device_DriverInfPath'])
  Write-Output ("  Servicio del driver: {0}" -f $p['DEVPKEY_Device_Service'])
  Write-Output ("  Ultima conexion: {0}   Ultima desconexion: {1}" -f $p['DEVPKEY_Device_LastArrivalDate'], $p['DEVPKEY_Device_LastRemovalDate'])
  if ($d.Present) {
    $readerIds += $d.InstanceId
    if ($d.Status -ne 'OK') { Add-Finding 'ALTO' "El lector esta conectado pero su estado es $($d.Status) (codigo de problema $($p['DEVPKEY_Device_ProblemCode']))." }
    if ($d.Class -ne 'Biometric') { Add-Finding 'MEDIO' "El lector esta en la clase '$($d.Class)', no 'Biometric': probablemente no tiene el driver WBF." }
    # Cadena USB hasta el concentrador raiz
    Write-Output '  Cadena USB (del lector hacia el equipo):'
    $parent = $p['DEVPKEY_Device_Parent']
    $depth = 0
    while ($parent -and $depth -lt 6) {
      $pd = Get-PnpDevice -InstanceId $parent -ErrorAction SilentlyContinue
      $pp = Get-DeviceProps $parent
      $svc = $pp['DEVPKEY_Device_Service']
      Write-Output ("    <- {0} [{1}] servicio {2}" -f $(if ($pd) { $pd.FriendlyName } else { '?' }), $parent, $svc)
      if ($svc -match '^(usbhub|usbhub3)$' -and $parent -notmatch '^USB\\ROOT_HUB') {
        Add-Finding 'MEDIO' "El lector pasa por un concentrador USB ($($pd.FriendlyName)). Si es externo, sin fuente propia, base o monitor: conectarlo directo al equipo."
      }
      if ($parent -match '^USB\\ROOT_HUB' -or $parent -match '^(PCI|ACPI|ROOT)\\') { break }
      $parent = $pp['DEVPKEY_Device_Parent']
      $depth++
    }
  }
}
if ($allDp.Count -gt 0 -and $presentDp.Count -eq 0) { Add-Finding 'ALTO' 'El lector no esta conectado en este momento.' }
if ($presentDp.Count -gt 1) { Add-Finding 'MEDIO' "Hay $($presentDp.Count) dispositivos DigitalPersona presentes." }

# 3. Otros sensores biometricos ---------------------------------------------
Write-Section '3. Otros sensores biometricos (huella del portatil, camaras Windows Hello)'
$otherBio = @(Get-PnpDevice -Class Biometric -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -notmatch $DP_VID })
if ($otherBio.Count -eq 0) { Write-Output 'Ninguno.' }
foreach ($b in $otherBio) {
  Write-Output ("{0}  [{1}]  {2}" -f $b.FriendlyName, $b.InstanceId, $b.Status)
}
# Las camaras de Windows Hello no son lectores de huella; los sensores de huella del portatil si
$otherFinger = @($otherBio | Where-Object { $_.FriendlyName -notmatch 'Facial|Face|Rostro|IR Camera' })
if ($otherFinger.Count -gt 0) {
  Add-Finding 'ALTO' "Hay otro sensor de huella WBF en el equipo ($(($otherFinger | ForEach-Object { $_.FriendlyName }) -join ', ')). El agente puede listarlo como lector: Maria lo veria 'conectado' sin el U.are.U y podria capturar del sensor equivocado. Probar deshabilitandolo en el Administrador de dispositivos."
}

# 4. Energia USB --------------------------------------------------------------
Write-Section '4. Energia USB'
foreach ($id in $readerIds) {
  $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$id\Device Parameters"
  if (Test-Path -LiteralPath $regPath) {
    $rp = Get-ItemProperty -LiteralPath $regPath -ErrorAction SilentlyContinue
    foreach ($n in 'EnhancedPowerManagementEnabled', 'SelectiveSuspendEnabled', 'AllowIdleIrpInD3', 'DeviceSelectiveSuspended', 'IdleInWorkingState') {
      if ($null -ne $rp.$n) { Write-Output ("  {0} = {1}" -f $n, $rp.$n) }
    }
  }
}
if ($isAdmin) {
  $pm = @(Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable -ErrorAction SilentlyContinue)
  $ids = @($readerIds)
  foreach ($id in $readerIds) {
    $pp = Get-DeviceProps $id
    $par = $pp['DEVPKEY_Device_Parent']
    $k = 0
    while ($par -and $k -lt 6) { $ids += $par; if ($par -match '^USB\\ROOT_HUB') { break }; $par = (Get-DeviceProps $par)['DEVPKEY_Device_Parent']; $k++ }
  }
  foreach ($id in $ids) {
    $e = $pm | Where-Object { $_.InstanceName -like "$id*" } | Select-Object -First 1
    if ($e) {
      Write-Output ("  'Permitir que el equipo apague este dispositivo' = {0}  [{1}]" -f $e.Enable, $id)
      if ($e.Enable) { Add-Finding 'MEDIO' "Windows puede apagar para ahorrar energia: $id (Administrador de dispositivos > Propiedades > Administracion de energia)." }
    }
  }
}
Write-Output ''
Write-Output 'Plan de energia - Suspension selectiva de USB (0 = deshabilitada, 1 = habilitada):'
$usbSs = & powercfg /query SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 2>&1
$usbSs | Select-Object -Last 3 | ForEach-Object { Write-Output "  $_" }
if (($usbSs | Select-Object -Last 3) -match '0x00000001') { Add-Finding 'MEDIO' 'La suspension selectiva de USB esta habilitada en el plan de energia actual (con corriente o con bateria).' }

# 5. Servicios y agente --------------------------------------------------------
Write-Section '5. Servicio de biometria de Windows y agente de DigitalPersona'
$wbio = Get-Service WbioSrvc -ErrorAction SilentlyContinue
if ($wbio) {
  Write-Output ("WbioSrvc (Biometria de Windows): {0}, inicio {1}" -f $wbio.Status, $wbio.StartType)
  if ($wbio.StartType -eq 'Disabled') { Add-Finding 'ALTO' 'El servicio de biometria de Windows (WbioSrvc) esta deshabilitado: el driver WBF no funciona sin el.' }
  elseif ($wbio.Status -ne 'Running') { Add-Finding 'MEDIO' 'El servicio de biometria de Windows no esta corriendo en este momento.' }
}
Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'DigitalPersona|Crossmatch|Authentication Device|HID Global' -or $_.Name -match '^DP' } |
  ForEach-Object { Write-Output ("Servicio {0} ({1}): {2}, inicio {3}" -f $_.DisplayName, $_.Name, $_.Status, $_.StartType) }
$agents = @(Get-AgentProcesses)
if ($agents.Count -eq 0) {
  Write-Output 'No hay procesos del agente (DPAgent) corriendo.'
  Add-Finding 'ALTO' 'El agente local (DPAgent / Local Agent) no esta corriendo.'
}
foreach ($a in $agents) {
  $ver = $null
  if ($a.ExecutablePath) { $ver = (Get-Item -LiteralPath $a.ExecutablePath -ErrorAction SilentlyContinue).VersionInfo.FileVersion }
  Write-Output ("Proceso {0} pid {1} sesion {2} desde {3} version {4}" -f $a.Name, $a.ProcessId, $a.SessionId, $a.CreationDate, $ver)
  Write-Output ("  {0}" -f $a.ExecutablePath)
}
$lite = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\DigitalPersona\Products\Lite Client' -ErrorAction SilentlyContinue
$wbfDrv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Crossmatch\Products\URU Driver WBF' -ErrorAction SilentlyContinue
$dpHost = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\DigitalPersona\DPHOST' -ErrorAction SilentlyContinue
Write-Output ("HID Authentication Device Client: {0}   Driver WBF instalado: {1}   DPHOST WBFDevice={2}" -f $lite.Version, $wbfDrv.Version, $dpHost.WBFDevice)
$dpAgents = @($agents | Where-Object { $_.Name -match '^DPAgent' })
if ($dpAgents.Count -gt 1) { Add-Finding 'MEDIO' "Hay $($dpAgents.Count) procesos DPAgent (varias sesiones de Windows o un agente duplicado)." }
$runKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
foreach ($rk in $runKeys) {
  $v = Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue
  if ($v) { $v.PSObject.Properties | Where-Object { "$($_.Value)" -match 'DPAgent|HID Global|DigitalPersona' } | ForEach-Object { Write-Output ("Arranque automatico: {0} -> {1}" -f $rk, $_.Value) } }
}

# 6. Puertos y conexion como la hace el navegador ----------------------------
Write-Section "6. Puerto $AGENT_PORT y conexion del SDK"
$l = @(Test-Listening $AGENT_PORT)
if ($l.Count -eq 0) {
  Write-Output "Nadie escucha en $AGENT_PORT."
  Add-Finding 'ALTO' "Nadie escucha en el puerto ${AGENT_PORT}: el navegador no puede hablar con el agente."
} else {
  $l | ForEach-Object { Write-Output ("Escucha {0}:{1} proceso {2} ({3})" -f $_.LocalAddress, $_.LocalPort, $_.OwningProcess, (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName) }
}
$ac = Get-AgentConnection
Write-Output ("get_connection: HTTP {0} en {1} s; host {2}; puerto websocket {3}; seguro {4} {5}" -f $ac.http, $ac.seconds, $ac.host, $ac.wsPort, $ac.secure, $ac.error)
if (-not $ac.ok) { Add-Finding 'ALTO' "get_connection falla ($($ac.error))." }
elseif ([double]$ac.seconds -gt 2) { Add-Finding 'MEDIO' "get_connection tarda $($ac.seconds) s." }
if ($ac.wsPort) {
  $lw = @(Test-Listening $ac.wsPort)
  Write-Output ("Puerto websocket {0}: {1}" -f $ac.wsPort, $(if ($lw.Count) { 'escucha' } else { 'NO escucha' }))
  if ($lw.Count -eq 0) { Add-Finding 'ALTO' "El agente anuncia el websocket en $($ac.wsPort) pero nadie escucha ahi (DPAgent caido: el servicio DpHost sigue anunciando el puerto viejo)." }
}
foreach ($a in $dpAgents) {
  $agentPorts = @(Get-NetTCPConnection -OwningProcess $a.ProcessId -State Listen -ErrorAction SilentlyContinue | ForEach-Object { $_.LocalPort })
  Write-Output ("DPAgent pid {0} escucha en: {1}" -f $a.ProcessId, ($agentPorts -join ', '))
  if ($ac.wsPort -and $agentPorts.Count -gt 0 -and $agentPorts -notcontains $ac.wsPort) { Add-Finding 'ALTO' "DPAgent escucha en $($agentPorts -join ',') pero get_connection anuncia $($ac.wsPort)." }
}
if ($ac.wsPort) {
  $est = @(Get-NetTCPConnection -LocalPort $ac.wsPort -State Established -ErrorAction SilentlyContinue)
  Write-Output ("Conexiones abiertas de navegadores al agente (websocket {0}): {1}" -f $ac.wsPort, $est.Count)
  if ($est.Count -gt 3) { Add-Finding 'MEDIO' "Hay $($est.Count) conexiones abiertas al agente. Maria abre una por pestana solo mientras la ventana de huellas esta abierta. Si hay mas, hay pestanas con una version de Maria anterior al 2026-11-25 (dejaba una conexion viva cada vez que se abria y cerraba esa ventana; recargarlas las cierra) u otro programa conectado al agente." }
}
Write-Output 'Nota: cada vez que DPAgent se reinicia cambia de puerto. Maria lo vuelve a pedir al pulsar Reconectar o al volver a la pestana; una version anterior al 2026-11-25 se quedaba con el puerto viejo incluso tras F5, y habia que abrir otra pestana.'

# 7. Certificado del agente ---------------------------------------------------
Write-Section '7. Certificados de 127.0.0.1 / localhost / DigitalPersona'
$certs = @()
foreach ($store in 'Cert:\LocalMachine\Root', 'Cert:\CurrentUser\Root', 'Cert:\LocalMachine\My', 'Cert:\CurrentUser\My') {
  $certs += @(Get-ChildItem $store -ErrorAction SilentlyContinue | Where-Object { $_.Subject -match '127\.0\.0\.1|localhost|DigitalPersona|Crossmatch|HID Global' -or $_.Issuer -match 'DigitalPersona|Crossmatch|HID Global' } |
    Select-Object @{ n = 'Store'; e = { $store } }, Subject, Issuer, NotAfter, Thumbprint)
}
if ($certs.Count -eq 0) { Write-Output 'No se encontraron.' }
$certs | ForEach-Object {
  Write-Output ("{0}  {1}  vence {2}  {3}" -f $_.Store, $_.Subject, $_.NotAfter, $_.Thumbprint)
  if ($_.NotAfter -lt (Get-Date) -and $_.Subject -match '127\.0\.0\.1|localhost') { Add-Finding 'MEDIO' "Certificado vencido: $($_.Subject) en $($_.Store) (vencio $($_.NotAfter))." }
}

# 8. Politicas de biometria y seguridad de inicio de sesion -------------------
Write-Section '8. Politicas de biometria y seguridad de inicio de sesion mejorada'
$regs = @(
  'HKLM:\SOFTWARE\Policies\Microsoft\Biometrics',
  'HKLM:\SOFTWARE\Policies\Microsoft\Biometrics\Credential Provider',
  'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\SecureBiometrics',
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WinBio',
  'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization'
)
foreach ($r in $regs) {
  if (Test-Path -LiteralPath $r) {
    $v = Get-ItemProperty -LiteralPath $r -ErrorAction SilentlyContinue
    $vals = $v.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { "$($_.Name)=$($_.Value)" }
    Write-Output ("{0}: {1}" -f $r, ($vals -join '; '))
  } else { Write-Output ("{0}: (no existe)" -f $r) }
}
$bioPol = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Biometrics' -ErrorAction SilentlyContinue
if ($bioPol -and $bioPol.Enabled -eq 0) { Add-Finding 'ALTO' 'Una politica deshabilita la biometria de Windows (Policies\Microsoft\Biometrics Enabled=0).' }
$ess = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\SecureBiometrics' -ErrorAction SilentlyContinue
if ($ess -and $ess.Enabled -eq 1) { Add-Finding 'ALTO' 'Parece activa la seguridad de inicio de sesion mejorada (SecureBiometrics Enabled=1): bloquea los lectores externos. Revisar en Configuracion > Cuentas > Opciones de inicio de sesion.' }
$winbio = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WinBio' -ErrorAction SilentlyContinue
if ($winbio -and $winbio.NonEssSensorsBlocked -eq 1) { Add-Finding 'ALTO' 'Windows bloquea los sensores que no son ESS (WinBio NonEssSensorsBlocked=1): el U.are.U por WBF queda bloqueado. Apagar la seguridad de inicio de sesion mejorada.' }
$virt = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization' -ErrorAction SilentlyContinue
if ($virt -and $null -ne $virt.EnableEnhancedSessionMode) { Add-Finding 'INFO' 'Existe EnableEnhancedSessionMode (la guia lo pide): es de Hyper-V, no de la seguridad de inicio de sesion; no influye en el lector.' }

# 9. Navegadores ---------------------------------------------------------------
Write-Section '9. Navegadores y acceso a 127.0.0.1 (Local Network Access)'
$browsers = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
  "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
)
foreach ($b in $browsers) {
  if (Test-Path -LiteralPath $b) { Write-Output ("{0}  {1}" -f (Get-Item -LiteralPath $b).VersionInfo.ProductVersion, $b) }
}
$polRoots = 'HKLM:\SOFTWARE\Policies\Google\Chrome', 'HKCU:\SOFTWARE\Policies\Google\Chrome', 'HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'HKCU:\SOFTWARE\Policies\Microsoft\Edge'
$lnaPolicy = $false
foreach ($pr in $polRoots) {
  if (-not (Test-Path -LiteralPath $pr)) { continue }
  $v = Get-ItemProperty -LiteralPath $pr -ErrorAction SilentlyContinue
  $v.PSObject.Properties | Where-Object { $_.Name -match 'Loopback|LocalNetwork' } | ForEach-Object { Write-Output ("{0}: {1}={2}" -f $pr, $_.Name, $_.Value); $lnaPolicy = $true }
  Get-ChildItem -LiteralPath $pr -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match 'Loopback|LocalNetwork' } | ForEach-Object {
    $lv = Get-ItemProperty -LiteralPath $_.PSPath
    $items = $lv.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { $_.Value }
    Write-Output ("{0}\{1}: {2}" -f $pr, $_.PSChildName, ($items -join ', '))
    $lnaPolicy = $true
  }
}
if (-not $lnaPolicy) {
  Write-Output 'Sin politicas LoopbackNetworkAllowedForUrls / LocalNetworkAccessAllowedForUrls.'
  Add-Finding 'INFO' 'Chrome 142+ pide permiso para que una pagina publica hable con 127.0.0.1 (desde Chrome 147 tambien por websocket). Revisar en el candado de mariatrazabilidad.com.co que "Apps en el dispositivo" / "Acceso a la red local" este en Permitir.'
}

# 10. Antivirus -----------------------------------------------------------------
Write-Section '10. Antivirus'
Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue |
  ForEach-Object { Write-Output ("{0} (estado {1})" -f $_.displayName, $_.productState) }

# 11. Eventos -------------------------------------------------------------------
Write-Section "11. Eventos de Windows desde $($since.ToString('yyyy-MM-dd'))"
function Show-Events([string]$title, [hashtable]$filter, [string]$messageMatch, [int]$max = 40) {
  # Imprime con Write-Host: lo que devuelve la funcion son solo los eventos
  Write-Host ''
  Write-Host "-- $title"
  try {
    $ev = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop)
  } catch {
    if ($_.Exception.Message -match 'No events|No se encontr') { Write-Host '   (sin eventos)' } else { Write-Host "   (no se pudo leer: $($_.Exception.Message))" }
    return
  }
  if ($messageMatch) { $ev = @($ev | Where-Object { $_.Message -match $messageMatch }) }
  if ($ev.Count -eq 0) { Write-Host '   (sin eventos)'; return }
  $ev | Group-Object Id | Sort-Object Count -Descending | ForEach-Object { Write-Host ("   Id {0}: {1} veces" -f $_.Name, $_.Count) }
  $ev | Select-Object -First $max | ForEach-Object {
    $msg = ($_.Message -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 2) -join ' / '
    Write-Host ("   {0}  {1,-5} {2,-12} {3}" -f $_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), $_.Id, $_.LevelDisplayName, $msg)
  }
  return $ev
}
$bioEv = @(Show-Events 'Biometria (Microsoft-Windows-Biometrics/Operational), advertencias y errores' @{ LogName = 'Microsoft-Windows-Biometrics/Operational'; StartTime = $since; Level = 1, 2, 3 } $null)
$pnpEv = @(Show-Events 'Conexion y desconexion del lector (Kernel-PnP/Configuration)' @{ LogName = 'Microsoft-Windows-Kernel-PnP/Configuration'; StartTime = $since } $DP_VID)
$sysPnp = @(Show-Events 'Sistema: PnP y drivers de modo usuario del lector' @{ LogName = 'System'; StartTime = $since; ProviderName = 'Microsoft-Windows-Kernel-PnP', 'Microsoft-Windows-UserPnp', 'Microsoft-Windows-DriverFrameworks-UserMode' } $DP_VID)
$usbErr = @(Show-Events 'Sistema: errores de USB y concentradores' @{ LogName = 'System'; StartTime = $since; Level = 1, 2, 3 } 'USB|concentrador|hub' 20)
$svcEv = @(Show-Events 'Sistema: servicios de biometria o DigitalPersona detenidos o caidos' @{ LogName = 'System'; StartTime = $since; ProviderName = 'Service Control Manager' } 'Biometr|DigitalPersona|Authentication Device|HID Global|WbioSrvc')
$appEv = @(Show-Events 'Aplicacion: cierres inesperados del agente o del driver' @{ LogName = 'Application'; StartTime = $since; Id = 1000, 1001, 1002, 1026 } 'DPAgent|DpHost|WUDFHost|WinBio|WbioSrvc|DigitalPersona|dpfp')
$sleepEv = @(Show-Events 'Suspension y reanudacion del equipo' @{ LogName = 'System'; StartTime = $since; Id = 42, 107, 1, 506, 507 } 'sleep|suspen|resum|reanud|Modern Standby|standby|baja energ|low power' 15)

if ($bioEv.Count -gt 0) { Add-Finding 'MEDIO' "Hay $($bioEv.Count) advertencias o errores de biometria de Windows en $Days dias (ver seccion 11)." }
if ($appEv.Count -gt 0) { Add-Finding 'ALTO' "El agente o el driver se cerraron inesperadamente $($appEv.Count) veces en $Days dias (ver seccion 11)." }
$crashSvc = @($svcEv | Where-Object { $_.Id -in 7031, 7034, 7023, 7024 })
if ($crashSvc.Count -gt 0) { Add-Finding 'ALTO' "Un servicio de biometria o de DigitalPersona termino con error $($crashSvc.Count) veces." }
$arrivals = @($pnpEv | Where-Object { $_.Id -in 400, 410 })
if ($arrivals.Count -gt ($Days * 4)) { Add-Finding 'MEDIO' "El lector se reconecto $($arrivals.Count) veces en $Days dias: cable, puerto, concentrador o ahorro de energia." }

# 12. Resumen -------------------------------------------------------------------
Write-Section '12. Resumen'
if ($findings.Count -eq 0) { Write-Output 'Sin hallazgos.' }
$order = @{ 'ALTO' = 0; 'MEDIO' = 1; 'INFO' = 2 }
$findings | Sort-Object { $order[($_ -replace '^\[(\w+)\].*', '$1')] } | ForEach-Object { Write-Output $_ }
Write-Output ''
Write-Output "Informe: $reportFile"
Stop-Transcript | Out-Null
