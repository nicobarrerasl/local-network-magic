# 6. Chuleta de Comandos Rápidos de Diagnóstico (Cheat Sheet)

Comandos frecuentes para ejecutar vía SSH en el router principal:
```sh
ssh root@192.168.2.1
```

---

## 6.1 Diagnóstico de Enlace Inalámbrico y WDS

### Consultar estado de la estación repetidora Archer C60
```sh
iw dev phy0-ap0 station get 42:84:6a:a9:2e:c9
```
* **Métricas clave:**
  * `signal avg`:
    * `-45 a -65 dBm`: Rango ideal.
    * `-66 a -73 dBm`: Operativo y aceptable.
    * `<= -75 dBm`: Señal deficiente; reubicar repetidor más cerca.
    * `-10 a -25 dBm`: Saturación de RF por proximidad excesiva.
  * `tx/rx bitrate`: Debe indicar canal de `40MHz` y esquemas `MCS 12` a `MCS 15`.
  * `failed`: Contador de pérdidas de tramas.

### Listar clientes asociados en el AP con hostapd / ubus
```sh
ubus call hostapd.phy0-ap0 get_clients
```

### Comprobar que la sub-interfaz WDS 4addr exista
```sh
iw dev | grep -A 5 "phy0-ap0.sta1"
```
Debe listar:
* `Interface phy0-ap0.sta1`
* `type AP/VLAN`
* `4addr: on`

### Validar inclusión de interfaz en el bridge de red
```sh
ls -la /sys/class/net/br-lan/brif/
# Probar conectividad con el repetidor
ping -c 3 192.168.2.2
```

---

## 6.2 Gestión de Servicios y Procesos

### Verificar el demonio automático `wds-fix`
```sh
# Ver proceso
ps | grep '[w]ds-fix'

# Reiniciar el servicio procd
/etc/init.d/wds-fix restart

# Ver logs de actividad de kernel y hostapd
logread -e wds -e hostapd
```

### Consultar reglas y contadores de firewall bridge
```sh
# Ver reglas de aislamiento L2
nft list table bridge wds_isolate

# Recargar firewall
/etc/init.d/firewall reload
```

---

## 6.3 VPN WireGuard y DDNS

### Estado de la interfaz WireGuard
```sh
wg show
ip -br addr show wg0
```

### Logs de actualización de DuckDNS
```sh
cat /var/log/ddns/duckdns.log
nslookup asus-master-race.duckdns.org 1.1.1.1
```

---

## 6.4 Configuración del Sistema (UCI)

```sh
# Ver configuración Wi-Fi actual
uci show wireless

# Cambiar canal Wi-Fi de forma segura
uci set wireless.radio0.channel='auto'
uci set wireless.radio0.noscan='1'
uci commit wireless
wifi reload

# Ver reservas DHCP
uci show dhcp
```
