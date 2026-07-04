<#
.SYNOPSIS
  Synchronise les règles netsh portproxy avec l'IP WSL2 courante.

.DESCRIPTION
  L'IP de l'interface réseau virtuelle WSL2 change à chaque redémarrage de
  Windows ou de WSL, ce qui casse le forwarding vers le backend (port 3000)
  et MinIO (port 9000) utilisé pour tester l'app mobile depuis un émulateur
  Android ou un téléphone physique sur le même réseau (docs/status_v0.md).
  Ce script détecte l'IP WSL courante, supprime les règles portproxy
  existantes pour ces ports puis les recrée en écoutant sur 0.0.0.0 (pour
  être joignable depuis un téléphone physique via l'IP LAN, pas seulement
  l'émulateur).

.NOTES
  À exécuter dans un PowerShell **administrateur**, à chaque session où le
  serveur ne répond plus depuis l'émulateur/téléphone. Ne touche pas au
  pare-feu Windows (règle entrante à créer une seule fois, manuellement,
  pour chaque port si ce n'est pas déjà fait).
#>

param(
    [int[]]$Ports = @(3000, 9000)
)

$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Ce script doit être lancé dans un PowerShell administrateur."
    exit 1
}

$wslIp = (wsl hostname -I 2>$null).Trim().Split(' ')[0]
if ([string]::IsNullOrWhiteSpace($wslIp)) {
    Write-Error "Impossible de récupérer l'IP WSL (wsl hostname -I). WSL est-il démarré ?"
    exit 1
}

Write-Host "IP WSL détectée : $wslIp"

foreach ($port in $Ports) {
    netsh interface portproxy delete v4tov4 listenport=$port listenaddress=0.0.0.0 | Out-Null
    netsh interface portproxy add v4tov4 `
        listenport=$port listenaddress=0.0.0.0 `
        connectport=$port connectaddress=$wslIp
    Write-Host "Port $port -> ${wslIp}:${port}"
}

Write-Host "`nRègles portproxy actuelles :"
netsh interface portproxy show v4tov4
