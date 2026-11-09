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

* **Topología:**
  * Subred del túnel: `10.10.10.0/24`
  * IP Servidor Asus: `10.10.10.1`
  * Puerto de escucha: `UDP 51820`
  * Zona Firewall: Asociada a la zona `lan` con regla en `wan` permitiendo `UDP 51820`.
* **Ventajas del Modo Monopuesto:**
  Dado que el módem Askey de Movistar opera en modo bridge y el Asus disca la sesión PPPoE directamente (`pppoe-wan`), el Asus cuenta con una **IP pública real sin NAT intermedio ni CGNAT**. Las conexiones WireGuard entrantes no requieren apertura de puertos previa en el módem de Movistar.
* **Cliente Móvil (OnePlus 13):**
  * Aplicación: **WG Tunnel** (cliente avanzado para Android con soporte de túnel automático según SSID).
  * Asignación: `10.10.10.2/32`, `PersistentKeepalive = 25`.
  * Hereda automáticamente los resolutores DNS con bloqueo de anuncios de **`adblock-fast`** (`10.10.10.1:53`).
* **Verificación por SSH:**
  ```sh
  wg show
  ip addr show wg0
  ```

---

## 5.3 DNS Dinámico (DDNS con DuckDNS)

* **Servicio:** `ddns-scripts` con backend `duckdns.org` configurado en `/etc/config/ddns`.
* **Dominio:** `asus-master-race.duckdns.org`
* **Token:** `<TOKEN_DUCKDNS>` (*ver credentials.local.md*)
* **Mecanismo:** Monitorea la interfaz `pppoe-wan` con chequeo cada 5 minutos e invocación inmediata mediante script de hotplug ante eventos de reconexión de WAN. Las actualizaciones viajan cifradas por HTTPS (`ca-certificates.crt`).
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
  * Dirección IP Fija: `192.168.2.122`
* **Disparo de Magic Packet por SSH:**
  ```sh
  etherwake -D -i br-lan 08:bf:b8:1b:b6:78
  ```
* **Panel LuCI:** `Services` -> `Wake on LAN` -> Interfaz `br-lan` -> Host `PC-MASTER_RACE`.
* **Tareas Pendientes en la PC:**
  Asegurar en la BIOS/UEFI de la placa madre la activación de `Wake on PCI-E` / desactivar estados agresivos de ahorro `ErP` y habilitar en Windows 11 en las propiedades avanzadas del controlador de red Ethernet: *Wake on Magic Packet = Habilitado*.

---

## 5.5 Integración con HomeNexus (Control de Hogar IoT)

* **Proyecto:** `Personal Projects/homenexus/main.py` (interfaz gráfica en Python + CustomTkinter).
* **Protocolo:** Mensajes UDP al puerto `38899` dentro de `br-lan` (`getPilot` / `setPilot`).
* **Consideración de Red / WSL2:** Los paquetes de broadcast de descubrimiento UDP no atraviesan la interfaz virtual de WSL2 (incluso con networking en modo *mirrored*); por ende, la aplicación debe ejecutarse directamente en el entorno de Windows (`HomeNexus.bat` o `HomeNexus.exe`).
* **Dispositivos WiZ Configurados:**
  * `wiz_e9fed4` (MAC `44:4f:8e:e9:fe:d4`) -> IP estática `192.168.2.10`
  * `wiz_eade00` (MAC `44:4f:8e:ea:de:00`) -> IP estática `192.168.2.11`
  * Ambas IPs están reservadas fuera del rango DHCP dinámico (`100-250`).
  * **Importante:** Las bombillas deben estar asociadas exclusivamente al punto de acceso del Asus, nunca al Archer C60, ya que el aislamiento L2 impediría la comunicación con la PC.

---

## 5.6 Streaming Remoto de Baja Latencia y Archivos Locales

### Streaming a 120 FPS (`Apollo` + `Moonlight`)
* **Servidor en PC:** Apollo / Sunshine escuchando en el puerto base `port = 27989` (configurado en `C:\Program Files\Apollo\config\sunshine.conf`). Este puerto se eligió específicamente para evitar los rangos dinámicos reservados por WSL2 (`44620–48715`).
* **Cliente Moonlight en OnePlus 13:**
  * Dirección fija: `192.168.2.122:27989` (accesible tanto en Wi-Fi local como a través de WireGuard VPN en 4G/5G).
  * Perfil de streaming: 120 FPS, resolución nativa y códec HEVC.
  * Monitor virtual: Al conectar desde la cama se conmuta con `Win + P` a "Solo segunda pantalla", permitiendo apagar el monitor físico.

### Compartición de Archivos (SMB)
* Desde Windows 11 se comparte la carpeta en red privada con regla de firewall:
  ```powershell
  Set-NetFirewallRule -Name "FPS-SMB-In-TCP" -RemoteAddress LocalSubnet,10.10.10.0/24
  ```
* Accesible desde Android con clientes SMB (Cx Explorador de archivos / Material Files) conectando a `192.168.2.122`.
