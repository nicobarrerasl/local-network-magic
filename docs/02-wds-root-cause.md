# 2. Diagnóstico y Causa Raíz del Enlace WDS

## 2.1 Síntoma Inicial
El router repetidor TP-Link Archer C60 mostraba en su interfaz web el estado de WDS como **Asociado / Ejecutando** en la banda de 2.4 GHz contra el SSID `Hidden_2` del Asus RT-AX52. Sin embargo:
1. Ningún cliente conectado al Archer C60 recibía dirección IP mediante DHCP.
2. No había comunicación ni ping hacia el router principal `192.168.2.1`.
3. Desde la red principal del Asus, el ping hacia `192.168.2.2` fallaba con 100% de pérdida de paquetes.

---

## 2.2 Explicación Técnica Detallada (Kernel `mac80211` / `mt7915e` / `hostapd`)

El problema radicó en una incompatibilidad arquitectónica entre la derivación de direcciones MAC en el driver Qualcomm Atheros del Archer C60 y la aceleración por hardware del chip MediaTek Filogic en OpenWrt.

### 1. Divergencia de MACs en el TP-Link Archer C60
El firmware de fábrica de TP-Link utiliza el driver propietario Qualcomm Atheros (`qca-wifi`). La interfaz bridge local (`br0`) tiene la MAC base física:
```text
3c:84:6a:a9:2e:c9
```
Para asociarse como cliente repetidor WDS, el driver crea un Punto de Acceso Virtual (VAP tipo estación `ath01`/`sta0`) cuya MAC de capa de radio se calcula mediante la macro de Atheros `ATH_SET_VAP_BSSID`:
```text
((0x3c + (1 << 2)) | 0x02) = 0x42  -->  42:84:6a:a9:2e:c9
```

### 2. Funcionamiento de WDS en OpenWrt (`hostapd` + `mac80211`)
En OpenWrt con `option wds '1'` activo en `/etc/config/wireless` (`wds_sta=1` en `/var/run/hostapd-phy0.conf`), el demonio `hostapd` **no instancia** la sub-interfaz virtual de 4 direcciones (`AP/VLAN`, típicamente `phy0-ap0.sta1` con `4addr: on`) al momento en que la estación se asocia a nivel 802.11.

En su lugar, `hostapd` queda a la espera pasiva de que el subsistema de red inalámbrica del kernel Linux (`mac80211`) le notifique mediante el evento netlink:
```text
NL80211_CMD_UNEXPECTED_4ADDR_FRAME
```
Este evento solo se dispara cuando el stack de red recibe la primera trama de datos con el encabezado 802.11 de 4 direcciones (`ToDS=1, FromDS=1`).

### 3. El Bloqueo Mutuo (*Deadlock*)
1. El driver QCA del Archer C60, al no detectar el *Vendor IE* propietario de Atheros en el Beacon del Asus, envía tramas de datos iniciales con `Addr2 (Transmitter Address) = 42:84:6a:a9:2e:c9` y `Addr3 (Source Address) = 3c:84:6a:a9:2e:c9`.
2. En el Asus RT-AX52, el chip MediaTek Filogic (`mt7915e`) cuenta con **`DECAP_OFFLOAD`** activo por hardware. Al procesar las tramas entrantes, el silicio las desencapsula directamente a tramas Ethernet estándar (`802.3`) antes de entregarlas al subsistema de red del kernel, inyectándolas directo en `phy0-ap0` → `br-lan`.
3. Al ser desencapsuladas por hardware, **nunca se dispara el evento `NL80211_CMD_UNEXPECTED_4ADDR_FRAME`** en el kernel.
4. Por ende, `hostapd` nunca creaba la interfaz `phy0-ap0.sta1` y la salida de `ubus call hostapd.phy0-ap0 get_clients` mostraba la estación `42:84:6a:a9:2e:c9` con `"wds": false`.
5. El bridge Linux `br-lan` del Asus aprendía que la MAC `3c:84:6a:a9:2e:c9` (y todas las MACs de los clientes detrás del Archer) residían en el puerto de radio estándar `phy0-ap0` (modo AP normal de 3 direcciones).
6. Cuando el Asus intentaba responder a cualquier petición (DHCP Offer, ARP Reply, ICMP Echo Reply) con destino unicast a `3c:84:6a:a9:2e:c9`, la interfaz `phy0-ap0` buscaba en su tabla de asociaciones esa MAC. Al no encontrarla (porque la única estación asociada es `42:84:6a:a9:2e:c9`), **descartaba silenciosamente el 100% de las tramas salientes**.

---

## 2.3 Solución Implementada: Secuencia Estricta de Netlink

Para resolver el problema sin requerir parches en el kernel o deshabilitar la aceleración de hardware, se diseñó un demonio en `ucode` (`/usr/sbin/wds-fix.uc`) supervisado por `procd` (`/etc/init.d/wds-fix`).

El kernel Linux `mac80211` impone un orden inmutable de llamadas netlink:
1. **`NL80211_CMD_NEW_INTERFACE`**: Crear `phy0-ap0.sta1` vinculada a `phy0-ap0` con `iftype = NL80211_IFTYPE_AP_VLAN` y `"4addr": 1`.
2. **`RTM_SETLINK` (`ip link set phy0-ap0.sta1 up`)**: Levantar la interfaz **antes** de asociar la estación. Esto ejecuta `ieee80211_do_open()` en el kernel y vincula internamente `vlansdata->bss = sdata->bss`. Si no está activa (`UP`), la posterior asociación falla con error `-EINVAL`.
3. **`NL80211_CMD_SET_STATION`**: Enviar a `dev: "phy0-ap0"` la tupla `mac: "42:84:6a:a9:2e:c9"` y `sta_vlan: <ifindex de phy0-ap0.sta1>`. Esto asigna `vlansdata->u.vlan.sta`, activa `drv_sta_set_4addr(..., true)` en el driver `mt7915e` de MediaTek y es **idempotente** (si ya estaba vinculada, el kernel ejecuta `if (sta->sdata == vlansdata) return 0;`).
4. **Incorporación a `br-lan`**: Al llamarse `phy0-ap0.sta1`, `netifd` la detecta automáticamente y la une a `br-lan` (el script incluye además un respaldo explícito con `brctl addif br-lan phy0-ap0.sta1`).
5. **Idempotencia y Resiliencia ante `wifi reload`**: El script valida el estado cada 2 segundos. Si se produce un `wifi reload` y `phy0-ap0` se recrea con un nuevo `ifindex`, el `SET_STATION` contra el `phy0-ap0.sta1` viejo devuelve error (`-EINVAL`); el script lo detecta con `nl80211.error()`, destruye la interfaz vieja huérfana (`NL80211_CMD_DEL_INTERFACE`) y recrea el enlace limpiamente sobre el nuevo `phy0-ap0`.
