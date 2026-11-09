# AGENTS.md — Manual de Operaciones, Desarrollo y Directivas para Agentes de IA

Bienvenido al repositorio central de control, automatización y desarrollo para el router principal **Asus RT-AX52** con **OpenWrt 25.x** y su entorno de red extendido (enlace WDS con TP-Link Archer C60, módem Askey Movistar en modo bridge, HomeNexus y servicios de conectividad).

Este documento está diseñado como la **fuente de verdad canónica** para agentes autónomos de IA y desarrolladores de software que interactúen con el router, implementen nuevas utilidades o modifiquen su sistema operativo.

---

## 1. Identidad del Sistema y Perfil de Hardware

* **Dispositivo Objetivo:** Asus RT-AX52
* **SoC:** MediaTek Filogic 820 (`mt7981` / `mt7915e` / `mt76`)
* **Arquitectura de CPU:** Dual-core ARM Cortex-A53 @ 1.3 GHz (`aarch64`)
* **Sistema Operativo:** OpenWrt `25.12.5 r33051-f5dae5ece4`
* **Kernel Linux:** `6.12.94`
* **Gestor de Paquetes:** **`apk`** (OpenWrt moderno en versión 25.x utiliza el formato y binario `apk` de Alpine Linux, **no** el comando obsoleto `opkg`).
* **Lenguajes y Runtimes Disponibles:**
  * **Shell:** BusyBox `ash` (POSIX compliant).
  * **Ucode:** `/usr/bin/ucode` (lenguaje rápido y ligero oficial de OpenWrt con sintaxis estilo JavaScript/C y bindings directos a `nl80211`, `rtnl`, `uloop`, `ubus` y `fs`).
* **Supervisión de Procesos:** `procd` (subsistema estándar de inicialización y control con autorestart).
* **Firewall:** `nftables` / `fw4` con soporte para filtrado en bridge (`kmod-nft-bridge`).

---

## 2. Protocolos de Conexión y Ejecución Remota

### 2.1 Puntos de Acceso
* **IP LAN Principal:** `192.168.2.1` (puerto SSH `22`, interfaz LuCI `http://192.168.2.1`)
* **IP WireGuard (Acceso Remoto):** `10.10.10.1`
* **Usuario:** `root`
* **Credenciales:** Almacenadas localmente en `credentials.local.md` (ignorado en `.gitignore`) con plantilla en [`credentials.example.md`](credentials.example.md).

### 2.2 Patrón de Ejecución de Comandos
Al emitir comandos de terminal contra el router desde una máquina host o agente de IA:
1. **Comandos sin bloqueo:**
   ```bash
   ssh root@192.168.2.1 "<comando>"
   ```
2. **Herramienta de despliegue local:**
   Utilizar el script [`scripts/deploy.sh`](scripts/deploy.sh) para tareas estandarizadas:
   ```bash
   ./scripts/deploy.sh status
   ./scripts/deploy.sh sync-all
   ./scripts/deploy.sh logs
   ```
3. **No ejecutar procesos interactivos en background ciego:** Toda llamada de larga duración debe registrarse como un servicio supervisado por `procd` o lanzarse mediante `start-stop-daemon` con salida redirigida a `logger`.

---

## 3. Arquitectura del Sistema Operativo OpenWrt

Para interactuar de forma segura con el Asus RT-AX52, todo agente debe seguir las convenciones de los cuatro subsistemas troncales:

```
+-------------------------------------------------------------------+
|                        OpenWrt 25.x Core                          |
+-------------------------------------------------------------------+
|  UCI (/etc/config/*)  <--->  UBUS (IPC / RPC / Events)            |
|  PROCD (Init & Daemons) <->  NETIFD & FW4 (nftables)              |
|  UCODE (Fast scripting) <->  Linux Kernel 6.12 (mac80211/mt7915e) |
+-------------------------------------------------------------------+
```

### 3.1 UCI (Unified Configuration Interface)
Toda configuración de red, Wi-Fi, DHCP y firewall se gestiona mediante el comando `uci`. Nunca edites archivos en `/etc/config/` con expresiones regulares o sustituciones de texto plano a menos que sea estrictamente necesario.

* **Lectura:**
  ```sh
  uci show wireless
  uci get network.lan.ipaddr
  ```
* **Escritura y Aplicación:**
  ```sh
  uci set wireless.radio0.channel='auto'
  uci commit wireless
  wifi reload
  ```
* **Rollback de Cambios no Confirmados:**
  ```sh
  uci revert wireless
  ```

### 3.2 UBUS (Microbus System)
Es el canal IPC de OpenWrt. Permite consultar el estado interno de daemons (`hostapd`, `netifd`, `rpcd`) sin parsear archivos de texto.

* **Consultar interfaces activas:**
  ```sh
  ubus call network.interface dump
  ```
* **Consultar clientes Wi-Fi asociados a la radio:**
  ```sh
  ubus call hostapd.phy0-ap0 get_clients
  ```
* **Recargar subsistema RPC tras instalar plugins de LuCI:**
  ```sh
  /etc/init.d/rpcd restart
  ```

### 3.3 PROCD (Gestor de Procesos y Servicios)
Los servicios no se inician con scripts SysV tradicionales; utilizan `procd`. Un servicio supervisado cuenta con reinicio automático ante caídas (*respawn*).

* **Ubicación:** `/etc/init.d/<nombre-servicio>`
* **Control:**
  ```sh
  /etc/init.d/<servicio> start
  /etc/init.d/<servicio> stop
  /etc/init.d/<servicio> restart
  /etc/init.d/<servicio> enable
  ```

### 3.4 Gestor de Paquetes (`apk`)
En OpenWrt 25.x:
* Actualizar índice de paquetes: `apk update`
* Instalar paquetes: `apk add <paquete1> <paquete2>`
* Buscar paquetes: `apk search <termino>`
* Listar instalados: `apk list -I`

---

## 4. Desarrollo de Aplicaciones Propias para el Router

El router dispone de una CPU ARMv8 dual-core potente (`mt7981`), lo que permite ejecutar aplicaciones personalizadas ligeras directamente en el dispositivo.

### 4.1 Elección de Tecnología según el Caso de Uso

| Tipo de Aplicación | Lenguaje Recomendado | Ubicación en el Router | Ventajas |
| :--- | :--- | :--- | :--- |
| **Monitoreo de red / Automatización Wi-Fi** | **`ucode`** | `/usr/sbin/*.uc` | Cero overhead, event loop (`uloop`) integrado, llamadas directas a netlink (`nl80211`) y `ubus`. |
| **Scripts de arranque / Tareas periódicas** | **POSIX Shell (`/bin/sh`)** | `/etc/init.d/`, `/etc/hotplug.d/` | Compatible con BusyBox, universal. |
| **Reglas de red L2/L3 / Seguridad** | **`nftables`** | `/etc/firewall.*.nft` | Procesamiento en espacio de kernel, mínimo uso de CPU. |
| **Micro-APIs / Agentes complejos** | **C** o **Go** (cross-compilado) | `/usr/bin/` | Máximo rendimiento; compilar con OpenWrt SDK para `aarch64_cortex-a53`. |

> [!IMPORTANT]
> **No instales Python en el router** a menos que sea una necesidad crítica ineludible. La memoria flash del router es limitada. Las aplicaciones pesadas o interfaces gráficas (como `HomeNexus`) deben correr en la PC o servidor local y comunicarse con el router mediante SSH, UBUS over HTTP o UDP.

### 4.2 Plantilla Canónica para un Servicio Propio (`procd`)

Para crear un nuevo servicio supervisado en el router (ejemplo `/etc/init.d/mi-servicio`):

```sh
#!/bin/sh /etc/rc.common

START=99
STOP=10
USE_PROCD=1

PROG=/usr/sbin/mi-servicio.uc

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/ucode "$PROG"
    procd_set_param respawn 3600 5 0   # Reiniciar si cae; limite de 5 caidas en 1 hora
    procd_set_param stdout 1           # Enviar stdout al syslog (logread)
    procd_set_param stderr 1           # Enviar stderr al syslog
    procd_close_instance
}
```

### 4.3 Plantilla Canónica para un Script en `ucode`

Ucode es el estándar moderno en OpenWrt. Ejemplo de estructura con timer y uloop:

```javascript
#!/usr/bin/ucode
import * as uloop from "uloop";
import * as ubus from "ubus";
import { readfile, writefile } from "fs";

uloop.init();

let bus = ubus.connect();
if (!bus) {
    warn("No se pudo conectar a ubus\n");
}

function run_check() {
    // Logica periodica (ej: telemetria, comprobacion de clientes)
}

let timer = uloop.timer(5000, function() {
    try {
        run_check();
    } catch (e) {
        warn("Error en ejecucion: " + e + "\n");
    }
    timer.set(5000); // Repetir cada 5 segundos
});

run_check();
uloop.run();
```

---

## 5. Reglas de Seguridad y Restricciones Críticas para Agentes

Todo agente de IA o desarrollador **DEBE acatar rigurosamente las siguientes directivas** para prevenir bloqueos de red o pérdida de acceso al router:

1. **PROHIBIDO tocar la configuración de la interfaz WAN PPPoE sin respaldo:**
   * La interfaz `wan` disca la conexión a Internet mediante PPPoE sobre el módem Askey en modo monopuesto. Si se modifican o invalidan las credenciales PPPoE o la VLAN GPON, el router perderá conexión a Internet.
2. **NUNCA modificar `br-lan` sin mecanismo de salvaguarda:**
   * Cualquier cambio a la interfaz bridge `br-lan` que cause un reinicio de red erróneo cortará el acceso SSH. Si necesitas hacer pruebas de red, programa un rollback automático previo (ej: `sleep 60 && uci revert network && /etc/init.d/network restart &`).
3. **Persistencia Obligatoria en `/etc/sysupgrade.conf`:**
   * Toda aplicación nueva, script propio (`/usr/sbin/*.uc`) o regla de firewall personalizada (`/etc/firewall.*.nft`) **DEBE ser agregada a `/etc/sysupgrade.conf`**. De lo contrario, la próxima actualización de firmware de OpenWrt borrará permanentemente los archivos.
4. **Cuidado con la Memoria Flash (MTD):**
   * El almacenamiento interno de OpenWrt es memoria Flash NAND/NOR con ciclos de escritura finitos. **Nunca escribas logs continuos en archivos de `/etc` o `/root`**. Escribe únicamente en `/tmp` (que reside en RAM / tmpfs) o utiliza el logger del sistema (`logger` -> `logread`).
5. **Validación Sintáctica de Firewall previa:**
   * Antes de cargar o recargar reglas en `nftables`, validar siempre la sintaxis con:
     ```sh
     nft -c -f /ruta/al/archivo.nft
     ```
     Si la validación falla, **no apliques las reglas**.

---

## 6. Mapa del Repositorio y Enlaces a la Documentación

```
.
├── AGENTS.md                          # Este manual de directivas y desarrollo
├── README.md                          # Visión general del proyecto y topología
├── .gitignore                         # Patrones de exclusión para Git
├── docs/
│   ├── 01-topology-and-hardware.md   # Topología, hardware, WAN PPPoE, IPs y MACs
│   ├── 02-wds-root-cause.md          # Diagnóstico del kernel mac80211 y DECAP_OFFLOAD
│   ├── 03-rf-tuning-and-site-survey.md # Ajuste de 40MHz, canales ACS y estudio RF
│   ├── 04-l2-isolation.md            # Aislamiento L2 entre casas mediante nftables bridge
│   ├── 05-services-and-remote-access.md # WireGuard, DDNS, WoL, HomeNexus y Moonlight
│   └── 06-cheat-sheet.md             # Comandos SSH rápidos y chuleta de diagnóstico
├── router/
│   ├── etc/
│   │   ├── firewall.wds-isolate.nft  # Script de reglas bridge nftables
│   │   ├── init.d/
│   │   │   └── wds-fix               # Servicio procd para supervisar el demonio WDS
│   │   └── sysupgrade.conf           # Rutas persistentes ante upgrades de OpenWrt
│   └── usr/
│       └── sbin/
│           └── wds-fix.uc            # Demonio en ucode para asociación WDS 4addr
└── scripts/
    └── deploy.sh                     # Script de despliegue y monitoreo remoto
```

---

## 7. Flujo de Trabajo Recomendado para Agentes

Cuando el usuario solicite implementar una nueva funcionalidad (por ejemplo, una nueva automatización de red, un script de apagado de Wi-Fi nocturno, o un webhook en el router):

1. **Lectura de contexto:** Consultar la sección correspondiente en `docs/` y verificar si interactúa con `br-lan`, `wds` o la subred de `192.168.2.0/24`.
2. **Creación local:** Escribir el script en `router/usr/sbin/` y su servicio en `router/etc/init.d/`.
3. **Persistencia:** Añadir la ruta del nuevo archivo a `router/etc/sysupgrade.conf`.
4. **Verificación:** Desplegar mediante `scripts/deploy.sh` o comandos SSH puntuales sin alterar la infraestructura existente.
5. **Documentación:** Actualizar los documentos en `docs/` y registrar el cambio en un commit de Git claro y estructurado.
