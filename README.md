# OpenWrt Network Infrastructure & Router Automation

Infraestructura de red, configuración avanzada, servicios y desarrollo de aplicaciones para el router principal **Asus RT-AX52** con **OpenWrt 25.x**, enlazado de forma inalámbrica mediante puente WDS con un **TP-Link Archer C60** y conectado a Internet a través de un módem de fibra óptica Movistar en modo bridge (monopuesto).

---

## 🚀 Resumen del Entorno

* **Router Principal:** Asus RT-AX52 (MediaTek Filogic 820 ARMv8, OpenWrt 25.12.5, Kernel 6.12.94).
* **Enlace WAN:** Sesión PPPoE directa en el Asus sobre módem Movistar Askey en modo Monopuesto (IP pública directa, sin doble NAT).
* **Repetidor WDS:** TP-Link Archer C60 (firmware de fábrica) enlazado por 2.4 GHz en canal de 40 MHz (`Hidden_2`), entregando Wi-Fi local en 5 GHz.
* **Aislamiento L2:** Reglas `nftables` a nivel de bridge que aíslan el broadcast, mDNS y Cast entre ambas viviendas pero preservan Internet, DHCP, adblock-fast y el acceso administrativo desde la PC principal.
* **Servicios Integrados:**
  * **WireGuard (`wg0`):** Conexión remota cifrada y segura con acceso a LAN y adblock-fast.
  * **DuckDNS:** Monitoreo y actualización periódica de DNS dinámico.
  * **Wake-on-LAN:** Encendido remoto de la estación de trabajo `PC-MASTER_RACE`.
  * **HomeNexus:** Centro de control de iluminación inteligente (bombillas WiZ vía UDP 38899).
  * **Gaming / Streaming 120 FPS:** Moonlight y Apollo optimizados sin colisión de puertos con WSL2.

---

## 📂 Estructura del Repositorio

```
.
├── AGENTS.md                          # Guía operativa y normas de desarrollo para Agentes de IA
├── README.md                          # Este documento de presentación general
├── .gitignore                         # Archivos temporales y claves excluidas
├── credentials.example.md             # Plantilla de credenciales y secretos (copiar a credentials.local.md)
├── docs/                              # Documentación técnica modularizada
│   ├── 01-topology-and-hardware.md    # Topología física, parámetros, IPs y credenciales
│   ├── 02-wds-root-cause.md           # Análisis técnico del kernel mac80211 y DECAP_OFFLOAD
│   ├── 03-rf-tuning-and-site-survey.md # Optimización espectral, canales ACS y estudio de sitios
│   ├── 04-l2-isolation.md             # Aislamiento L2 entre casas mediante nftables bridge
│   ├── 05-services-and-remote-access.md # VPN WireGuard, DDNS, WoL, HomeNexus y Moonlight
│   └── 06-cheat-sheet.md              # Chuleta de comandos SSH y herramientas de diagnóstico
├── router/                            # Código fuente y configuraciones del router
│   ├── etc/
│   │   ├── firewall.wds-isolate.nft   # Reglas nftables para aislamiento de capa de enlace
│   │   ├── init.d/
│   │   │   └── wds-fix                # Script de servicio supervisado por procd
│   │   └── sysupgrade.conf            # Lista de archivos protegidos ante actualizaciones
│   └── usr/
│       └── sbin/
│           └── wds-fix.uc             # Demonio en ucode para enlace WDS 4addr
└── scripts/
    └── deploy.sh                      # Script de automatización SSH para pruebas y sincronización
```

---

## 🛠️ Herramienta de Despliegue (`scripts/deploy.sh`)

Para consultar o actualizar el router desde tu terminal local:

```bash
# Comprobar conectividad ICMP con el router
./scripts/deploy.sh ping

# Consultar estado general, WDS y firewall bridge
./scripts/deploy.sh status

# Sincronizar el servicio WDS Fix (ucode + procd) y reiniciar el demonio
./scripts/deploy.sh sync-wds

# Sincronizar y recargar las reglas de aislamiento en nftables
./scripts/deploy.sh sync-firewall

# Sincronizar todo el repositorio hacia el router
./scripts/deploy.sh sync-all

# Ver los logs recientes del router en vivo
./scripts/deploy.sh logs
```

---

## 🤖 Guía para Agentes de Inteligencia Artificial

Si eres un modelo de lenguaje o asistente autónomo trabajando en este proyecto, consulta de forma prioritaria:
👉 [**`AGENTS.md`**](AGENTS.md)

Allí se detallan las restricciones de seguridad, el uso de `uci`, `ubus`, `apk`, `procd`, la creación de utilidades en `ucode` y las directivas de persistencia ante actualizaciones del firmware.
