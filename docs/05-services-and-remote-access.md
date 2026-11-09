# 5. Servicios del Router, Acceso Remoto e Integraciones

Este documento detalla los servicios de red instalados en el Asus RT-AX52, su configuración y la integración con aplicaciones externas como HomeNexus, clientes móviles y estaciones de trabajo.

---

## 5.1 Paquetes Instalados en el Router (OpenWrt `apk`)

OpenWrt 25.x utiliza el gestor de paquetes de Alpine Linux (`apk`):
```sh
apk update
apk add etherwake luci-app-wol kmod-wireguard wireguard-tools \
        luci-proto-wireguard ddns-scripts ddns-scripts-services \
        luci-app-ddns curl ca-bundle
/etc/init.d/rpcd restart
```

---

## 5.2 Servidor VPN WireGuard (`wg0`)

Permite acceso seguro desde redes móviles (4G/5G) y Wi-Fi externas directamente al corazón de la red doméstica con cifrado en el kernel.

* **Topología (`/etc/config/network`):**
  * Subred del túnel: `10.10.10.0/24`
  * IP Servidor Asus: `10.10.10.1/24`
  * Puerto de escucha: `UDP 51820`
  * Zona Firewall: Asociada a la zona `lan` + regla `Allow-WireGuard` (`wan` -> `UDP 51820` `ACCEPT`).
* **Ventajas del Modo Monopuesto (Sin Doble NAT):**
  Dado que el módem Askey de Movistar opera en modo bridge y el Asus disca la sesión PPPoE directamente (`pppoe-wan`), la IP pública vive directamente en el Asus: **no hace falta abrir puertos ni DMZ en el módem de Movistar**. WireGuard recibe conexiones entrantes de inmediato desde Internet en `UDP 51820`.
* **Cliente Móvil (OnePlus 13):**
  * Aplicación: **WG Tunnel** (reemplaza a la app oficial de WireGuard en Android; usa el mismo protocolo WireGuard por lo que el servidor `wg0` del Asus no cambia, y suma soporte de túneles automáticos según la red Wi-Fi, p. ej. desactivarse al llegar a casa).
  * Peer creado: `OnePlus-13` (`10.10.10.2/32`, `PersistentKeepalive = 25`).
  * Hereda automáticamente el bloqueo de publicidad de **`adblock-fast`** (`dnsmasq` escuchando en `10.10.10.1:53` y `192.168.2.1:53`) y el acceso local a `br-lan` (para encender la PC por Wake-on-LAN o entrar por Escritorio Remoto).
* **Cómo exportar el código QR en LuCI:**
  1. Ir a `Network` -> `Interfaces` -> en `wg0` hacer clic en **Edit** -> pestaña **Peers**.
  2. Hacer clic en **Edit** sobre `OnePlus-13` y bajar hasta **Generate configuration…**.
  3. El campo `Connection endpoint` toma automáticamente la IP pública real (o el dominio DDNS) porque está asignada directo en `pppoe-wan`. Solo hay que escanear el QR desde la app **WG Tunnel** en Android (importar túnel por QR).
* **Verificación por SSH:**
  ```sh
  wg show
  ip addr show wg0
  ```

---

## 5.3 DNS Dinámico (DDNS con DuckDNS)

* **Servicio:** `ddns-scripts` con backend `duckdns.org` configurado en `/etc/config/ddns` (`ddns.duckdns`).
* **Dominio fijo:** `asus-master-race.duckdns.org`
* **Token:** `<TOKEN_DUCKDNS>` (*ver credentials.local.md*)
* **Mecanismo:** Monitorea la interfaz `wan` (`pppoe-wan`) con chequeo cada 5 minutos + evento inmediato de *hotplug* ante reconexiones PPPoE, enviando la actualización cifrada por HTTPS (`use_https='1'`, `ca-certificates.crt`).
* **Panel en LuCI:** `Services` -> `Dynamic DNS`.
* **Diagnóstico:**
  ```sh
  cat /var/log/ddns/duckdns.log
  nslookup asus-master-race.duckdns.org 1.1.1.1
  ```

---

## 5.4 Wake-on-LAN (WoL) e IP Estática (`PC-MASTER_RACE`)

* **Configuración DHCP en el Asus (`/etc/config/dhcp`):**
  * Hostname: `PC-MASTER_RACE`
  * Dirección MAC: `08:bf:b8:1b:b6:78`
  * Dirección IP Fija: `192.168.2.122` (necesaria también para mantener la excepción administrativa hacia `192.168.2.2` en `/etc/firewall.wds-isolate.nft`).
* **Disparo de Magic Packet por SSH:**
  ```sh
  etherwake -D -i br-lan 08:bf:b8:1b:b6:78
  ```
* **Panel LuCI:** `Services` -> `Wake on LAN` -> elegir interfaz `br-lan` y host `PC-MASTER_RACE (08:bf:b8:1b:b6:78)` -> **Wake up host**.
* **Pendiente de Revisión en la PC:**
  Paquetes e IP fija ya listos en el Asus; queda pendiente revisar y probar la configuración en la BIOS/UEFI (`Wake on PCI-E` / desactivar ahorro `ErP`) y en las propiedades de la placa de red en Windows 11 (*Wake on Magic Packet*) para que la PC responda estando apagada o suspendida.

---

## 5.5 Integración con HomeNexus (Control de Hogar IoT)

* **Proyecto:** `Personal Projects/homenexus/main.py` (interfaz gráfica en Python + `customtkinter`). Se lanza con `HomeNexus.bat` o el ejecutable `HomeNexus.exe` (instalado en `C:\Users\nicol\HomeNexus\HomeNexus.exe`).
* **Protocolo:** Mensajes UDP al puerto `38899` dentro de `br-lan` (`getPilot` / `setPilot`). Requiere tener **Comunicación local** activada en la app WiZ.
* **Consideración de Red / WSL2:** Los paquetes broadcast de descubrimiento UDP **no llegan desde WSL2** (aunque esté en modo *mirrored*); funciona desde el Python de Windows.
* **Dispositivos WiZ Configurados (2026-11-08):**
  * `wiz_e9fed4` (MAC `44:4f:8e:e9:fe:d4` / `444f8ee9fed4`) -> reserva IP estática `192.168.2.10`
  * `wiz_eade00` (MAC `44:4f:8e:ea:de:00` / `444f8eeade00`) -> reserva IP estática `192.168.2.11`
  * Ambas reservas están **fuera del pool DHCP dinámico** (`start=100`, `limit=150`), igual que el Archer (`.2`). *(Nota histórica: hasta cortarles la luz seguían con las IPs viejas `.182` y `.157`).*
  * **Secciones en `/etc/config/dhcp`:** `dhcp.wiz_e9fed4` y `dhcp.wiz_eade00` (hosts `wiz_<últimos 6 de MAC>`).
  * **Comando para agregar una lámpara nueva:**
    ```sh
    uci set dhcp.<id>=host; uci set dhcp.<id>.name=...; uci set dhcp.<id>.mac=...; uci set dhcp.<id>.ip=...; uci commit dhcp; /etc/init.d/dnsmasq restart
    ```
  * **Importante:** Las lámparas deben estar asociadas al Asus (no al Archer C60), ya que el aislamiento L2 de la sección 4 cortaría el control desde la PC.

---

## 5.6 Streaming Remoto de Baja Latencia y Archivos Locales

### Control Remoto + Gaming Streaming a 120Hz (`Apollo` + `Moonlight`)
* **Causa del ajuste de puerto:** WSL2 en modo *mirrored* reserva rangos efímeros altos (`44620–48715`), bloqueando el puerto RTSP por defecto (`48010`). Se configuró `port = 27989` en `C:\Program Files\Apollo\config\sunshine.conf` (rango `27984–28010`, libre de colisiones con WSL2).
* **Panel Web local en la PC:** `https://localhost:27990` (o desde el acceso directo de Inicio *Apollo*).
* **Cliente Moonlight en el OnePlus 13:**
  * En Wi-Fi local la detecta solo; para dejarla compatible también con **WG Tunnel / WireGuard (4G/5G)**, tocar **`+`** en Moonlight y agregar manualmente: **`192.168.2.122:27989`**.
  * **Ajustes óptimos para la Radeon RX 6800 XT:** Resolución *Nativa (Pantalla completa)*, **120 FPS**, códec **HEVC (H.265)** (y HDR opcional).
  * **Apagar el monitor físico al entrar desde la cama:** Con `Virtual Display` conectado en el celular, presionar una vez `Win + P` en Windows y elegir *"Solo segunda pantalla"*. Windows recuerda el perfil automáticamente al conectar/desconectar el celular.

### Tutorial para Explorar Archivos de Windows 11 desde el OnePlus 13 (`SMB`)
1. **En Windows 11 (`192.168.2.122`):**
   * En *Configuración -> Red e Internet -> Ethernet*, verificar que el perfil sea **Red privada**.
   * Clic derecho en la carpeta o unidad a compartir -> *Propiedades -> Uso compartido -> Uso compartido avanzado* -> tildar *Compartir esta carpeta* -> *Permisos* -> dar permisos al usuario.
   * Habilitar en PowerShell (Administrador) la subred de WireGuard (`10.10.10.0/24`) en el Firewall de Windows para que también funcione desde 4G/5G:
     ```powershell
     Set-NetFirewallRule -Name "FPS-SMB-In-TCP" -RemoteAddress LocalSubnet,10.10.10.0/24
     ```
2. **En el OnePlus 13 (Android):**
   * Instalar **Cx Explorador de archivos** o **Material Files**.
   * Ir a *Red -> `+` Nueva ubicación -> Remoto -> SMB*.
   * **Host:** `192.168.2.122`
   * **Usuario / Contraseña:** Credenciales reales de la cuenta de Windows *(si se usa cuenta Microsoft con PIN, ingresar el correo Microsoft y la contraseña de la cuenta, **no el PIN**)*.
