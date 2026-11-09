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
  * Dirección IP Fija: `192.168.2.122` (puerto físico `lan3` a 1000 Mbps).
* **Configuración LuCI WoL (`/etc/config/luci-wol`):**
  * Target registrado: `PC-MASTER_RACE` (`mac = '08:bf:b8:1b:b6:78'`, `iface = 'br-lan'`, `broadcast = '1'`).
  * Panel Web LuCI: `Services` -> `Wake on LAN` -> botón directo **Wake**.
* **Comando y Script de Disparo Rápido (`/usr/sbin/wake-pc`):**
  * En el router:
    ```sh
    wake-pc
    ```
    *(Invoca `etherwake -D -b -i br-lan 08:bf:b8:1b:b6:78` registrando el evento en `logread -e wol`).*
  * Desde la máquina de desarrollo / terminal:
    ```bash
    ./scripts/deploy.sh wol
    ```
* **Por qué el flag Broadcast (`-b`) es indispensable:**
  Al usar broadcast L2 (`ff:ff:ff:ff:ff:ff`), el switch del router inunda todas las bocas físicas de la LAN sin depender de la tabla CAM/FDB (que olvida la MAC unicast tras 300 segundos de apagada la PC).
* **Persistencia:** Incluido en `/etc/sysupgrade.conf` para no perderse ante actualizaciones de firmware.

### Guía de Configuración Requerida en la PC (Windows 11 + Placa ASUS)

Para que la PC encienda estando suspendida o apagada por completo (S5), se deben cumplir tres ajustes obligatorios:

#### 1. Desactivar Inicio Rápido de Windows 11 (Fast Startup)
Por defecto, Windows 11 apaga el equipo mediante hibernación híbrida del kernel (S4), lo cual desenergiza los buses PCIe y el chip de red, impidiendo responder al Magic Packet.
* **En CMD o PowerShell (como Administrador):**
  ```powershell
  powercfg /h off
  ```
  *(O en Panel de control -> Opciones de energía -> Elegir el comportamiento de los botones de encendido -> Desmarcar "Activar inicio rápido").*

#### 2. Configurar la Tarjeta de Red en Administrador de Dispositivos
1. Abrir `devmgmt.msc` (Administrador de dispositivos) -> expandir **Adaptadores de red**.
2. Clic derecho en el adaptador Ethernet principal (Intel I225-V / Realtek Gaming 2.5GbE) -> **Propiedades**.
3. Pestaña **Administración de energía**:
   * Marcar: *Permitir que este dispositivo reactive el equipo*.
   * Marcar: *Permitir solo un paquete Magic para reactivar el equipo*.
4. Pestaña **Opciones avanzadas**:
   * *Reactivación con paquete Magic* (Wake on Magic Packet) -> **Habilitado**.
   * *Reactivación tras apagar* (Shutdown Wake-Up / Wake on link settings) -> **Habilitado**.
   * *Ethernet de bajo consumo* (Energy Efficient Ethernet / Green Ethernet) -> **Deshabilitado**.

#### 3. Ajustes en la BIOS/UEFI de la Placa Madre ASUS
Al encender la PC, presionar `Supr` o `F2` para entrar al BIOS -> Presionar `F7` (Advanced Mode):
1. Ir a **Advanced** -> **APM Configuration** (Advanced Power Management):
   * **Power On By PCI-E** (o *Power On By PCIE/PCI*): Cambiar a **Enabled**. *(Crítico: ASUS enruta la tarjeta de red integrada por el bus PCIe; si está en Disabled, la placa madre ignora la señal de encendido).*
   * **ErP Ready**: Cambiar a **Disabled**. *(Si está en Enable S4+S5 o S5, la fuente apaga la línea de 5V Standby para ahorrar energía europea, apagando el chip de red).*
2. Guardar cambios con `F10` y reiniciar.
3. **Prueba visual:** Con la PC apagada pero enchufada a la corriente, el LED del conector RJ45 Ethernet detrás del gabinete debe quedar encendido o titilando tenuemente (indicando link en espera de 10/100 Mbps).

### Encendido Remoto desde el Móvil (OnePlus 13 vía WireGuard)
Cuando estés fuera de casa o acostado conectado a la VPN WireGuard (`10.10.10.2`):
1. Abrir el navegador en el teléfono e ingresar a `http://10.10.10.1` (LuCI).
2. Ir a **Services** -> **Wake on LAN**.
3. Tocar el botón **Wake** en la fila de `PC-MASTER_RACE`.
4. En 10-15 segundos la PC estará en Windows lista para conectar por **Moonlight** (`192.168.2.122:27989`) o Escritorio Remoto.

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
