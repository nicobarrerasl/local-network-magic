# 1. Topología de Red y Especificaciones de Hardware

## 1.1 Resumen de Dispositivos y Parámetros

| Parámetro | Router Principal (AP WDS) | Repetidor (Cliente WDS + AP) |
| :--- | :--- | :--- |
| **Modelo** | **Asus RT-AX52** | **TP-Link Archer C60** |
| **SoC / Driver Wi-Fi** | MediaTek Filogic 820 (`mt7981` / `mt7915e` / `mt76`) | Qualcomm Atheros (`qca-wifi` propietario) |
| **Arquitectura CPU** | Dual-Core ARM Cortex-A53 @ 1.3 GHz (`aarch64`) | Single-Core MIPS / Qualcomm |
| **Firmware** | OpenWrt `25.12.5 r33051-f5dae5ece4` (Kernel `6.12.94`) | TP-Link Stock Firmware |
| **IP en LAN (`br-lan`)** | `192.168.2.1/24` (Servidor DHCP activo) | `192.168.2.2/24` (Servidor DHCP desactivado) |
| **Acceso Administrativo** | SSH y LuCI: `root@192.168.2.1` (*ver credentials.local.md*) | Web: `http://192.168.2.2` (*ver credentials.local.md*) |
| **MAC LAN / Bridge** | `60:cf:84:f1:e9:2e` (`br-lan`) | `3c:84:6a:a9:2e:c9` (`br0`) |
| **MAC Wi-Fi 2.4 GHz** | `62:cf:84:f1:e9:2f` (AP `phy0-ap0`, SSID: `Hidden_2`) | `42:84:6a:a9:2e:c9` (Interfaz virtual cliente WDS) |
| **MAC Wi-Fi 5 GHz** | `60:cf:84:f1:e9:2e` (AP `phy1-ap0`, SSID: `Hidden_5`) | Usada como AP local para los clientes del repetidor |

---

## 1.2 Módem Fibra Movistar (Upstream WAN del Asus en Modo Monopuesto / Bridge)

* **Modo de Operación:** **Modo Monopuesto (Bridge)** configurado desde la interfaz web básica (`http://192.168.1.1`). El módem Askey encapsula/desencapsula `VLAN 10` de forma transparente hacia la boca LAN, entregando la sesión PPPoE sin etiquetar (*untagged*) a la boca `wan` del router Asus (`MAC: 60:cf:84:f1:e9:2e`).
* **IP LAN del Módem Askey (Acceso de rescate por cable directo):** `http://192.168.1.1` (Panel avanzado: `http://192.168.1.1/padrao`).
* **Credenciales Menú Avanzado:** Usuario **`admin`** / Contraseña: la misma contraseña del módem presente en la etiqueta física del equipo.
* **Credenciales PPPoE Fibra Movistar (Configuración en `/etc/config/network` del Asus):**
  * **Tipo:** `PPPoE` (`pppoe-wan` sobre interfaz física `wan`).
  * **IPv6:** `wan6` con `device='@wan'`, recibiendo prefijo delegado `/56` nativo (`Dual Stack`, `Addressing Type: SLAAC`).
  * **VLAN ID en red GPON:** `10` (manejada directamente en el lado fibra por el Askey, prioridad `0`).
  * **Username:** `<USUARIO_PPPOE>` (*ver credentials.local.md*)
  * **Password:** `<PASSWORD_PPPOE>` (*ver credentials.local.md*)
  * **DNS Movistar (Referencia upstream):** `186.130.128.250` / `186.130.129.250` *(En el Asus se fuerzan los resolutores `1.1.1.1` y `1.0.0.1` mediante `peerdns='0'`)*.

---

## 1.3 Asignación de Subredes y Rangos de Direcciones

* **Subred Principal (`br-lan`):** `192.168.2.0/24`
  * Gateway / DNS: `192.168.2.1`
  * Repetidor Archer C60: `192.168.2.2`
  * Reservas IOT (Luces WiZ): `192.168.2.10`, `192.168.2.11`
  * Reserva PC Principal (`PC-MASTER_RACE`): `192.168.2.122`
  * Pool dinámico DHCP: `192.168.2.100` – `192.168.2.250`
* **Subred WireGuard (`wg0`):** `10.10.10.0/24`
  * Servidor Asus RT-AX52: `10.10.10.1`
  * Cliente OnePlus 13: `10.10.10.2`
