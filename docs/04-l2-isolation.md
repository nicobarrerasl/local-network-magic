# 4. Aislamiento L2 entre Casas (Bridge Netfilter con nftables)

## 4.1 Objetivo y Requisitos
En esta topología existen dos viviendas comunicadas mediante el puente WDS:
* **Casa Principal (Nico):** Dispositivos personales (OnePlus 13, Mac, PC-MASTER_RACE, Smart TV LG, luces inteligentes WiZ).
* **Casa Repetidor (Mamá):** Dispositivos multimedia (Android TV, celulares).

**Objetivos del aislamiento:**
1. **Evitar descubrimiento mutuo:** Los celulares de una casa no deben ver, controlar ni transmitir por Chromecast/AirPlay/DIAL al Smart TV de la otra casa.
2. **Mantener servicios comunes:** Ambas casas deben compartir la misma salida de fibra simétrica, el servidor DHCP del Asus, los servidores DNS locales y la protección del bloqueador de publicidad **`adblock-fast`**.
3. **Preservar el Cast local interno:** En la casa de mamá, sus dispositivos deben poder transmitir sin problemas hacia su propio Android TV.
4. **Acceso Administrativo Unidireccional:** La estación `PC-MASTER_RACE` (`192.168.2.122`) debe poder acceder al panel de administración web del Archer C60 (`http://192.168.2.2`).

---

## 4.2 Arquitectura de la Solución

OpenWrt 25.x utiliza `nftables` y el subsistema de firewall `fw4`. Para filtrar paquetes a nivel de capa de enlace (L2 / Ethernet) dentro de un bridge Linux (`br-lan`), se instaló el módulo de kernel:
```sh
apk add kmod-nft-bridge
```

### Reglas de Filtrado (`/etc/firewall.wds-isolate.nft`)
El archivo se encuentra referenciado en `/etc/config/firewall` con `position='ruleset-prepend'` y persistido en `/etc/sysupgrade.conf`:

```nft
table bridge wds_isolate
flush table bridge wds_isolate

table bridge wds_isolate {
    chain forward {
        type filter hook forward priority 0; policy accept;

        # 1. Permitir que PC-MASTER_RACE administre el Archer C60
        ether saddr 08:bf:b8:1b:b6:78 ether daddr 3c:84:6a:a9:2e:c9 accept
        ether saddr 3c:84:6a:a9:2e:c9 ether daddr 08:bf:b8:1b:b6:78 accept
        ether saddr 08:bf:b8:1b:b6:78 arp daddr ip 192.168.2.2 accept
        ether saddr 3c:84:6a:a9:2e:c9 arp daddr ip 192.168.2.122 accept

        # 2. Descartar todo el trafico de reenvio entre la interfaz WDS y el resto del bridge
        iifname "phy0-ap0.sta*" counter drop
        oifname "phy0-ap0.sta*" counter drop
    }
}
```

---

## 4.3 Análisis de Flujo de Red

* **Tráfico hacia Internet / Gateway / DNS:**
  Cuando un cliente del Archer C60 solicita una dirección IP por DHCP, resuelve un dominio por DNS o navega a Internet, ese tráfico tiene como destino la dirección IP o MAC del Asus RT-AX52. Por lo tanto, el kernel lo procesa en el hook **`input`** o **`output`** del bridge, nunca en **`forward`**. Este tráfico fluye sin restricciones y pasa por `adblock-fast`.
* **Tráfico Local en Casa del Repetidor:**
  Los paquetes entre el celular de mamá y su Android TV son conmutados internamente por el switch/bridge local de hardware del Archer C60, de modo que nunca atraviesan el aire por `phy0-ap0.sta1`. El Cast local funciona al 100%.
* **Tráfico Cruzado entre Casas:**
  Cualquier paquete de descubrimiento mDNS (`224.0.0.251` / `ff02::fb`), SSDP (`239.255.255.250`), peticiones ARP entre clientes de distintas casas o intentos de conexión TCP/UDP directa ingresan a `br-lan` con destino a otro puerto del bridge. Esto activa el hook `bridge forward` y coincide con la regla de descarte (`drop`), bloqueando completamente la visibilidad cruzada.

---

## 4.4 Comandos de Verificación

Para consultar los contadores de paquetes descartados en tiempo real:
```sh
nft list table bridge wds_isolate
```
Verás incrementarse los contadores asociados a `iifname "phy0-ap0.sta*"` cada vez que se generen anuncios de broadcast/multicast en la red del repetidor.
