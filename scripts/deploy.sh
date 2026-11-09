#!/usr/bin/env bash
# deploy.sh - Utility script to sync files and check router status
set -euo pipefail

ROUTER_IP="${ROUTER_IP:-192.168.2.1}"
ROUTER_USER="${ROUTER_USER:-root}"

echo "============================================="
echo " OpenWrt Router Management & Deployment Tool "
echo " Target: ${ROUTER_USER}@${ROUTER_IP}"
echo "============================================="

usage() {
    echo "Uso: $0 [ping|status|sync-wds|sync-firewall|sync-all|logs]"
    echo ""
    echo "Comandos:"
    echo "  ping           Comprueba si el router responde a ICMP"
    echo "  status         Muestra estado de interfaces, WDS y firewall"
    echo "  sync-wds       Copia wds-fix.uc e init.d/wds-fix al router"
    echo "  sync-firewall  Copia /etc/firewall.wds-isolate.nft y recarga firewall"
    echo "  sync-all       Sincroniza todos los archivos locales hacia el router"
    echo "  logs           Lee los ultimos logs del router (logread)"
    exit 1
}

CMD="${1:-}"

case "$CMD" in
    ping)
        ping -c 3 "$ROUTER_IP"
        ;;
    status)
        echo "[+] Consultando estado general del router..."
        ssh "${ROUTER_USER}@${ROUTER_IP}" "
            echo '--- UPTIME & CARGA ---'
            uptime
            echo '--- ESTACION WDS (Archer C60) ---'
            iw dev phy0-ap0 station get 42:84:6a:a9:2e:c9 2>/dev/null || echo 'Estacion no conectada'
            echo '--- ESTADO SERVICIO WDS-FIX ---'
            ps | grep '[w]ds-fix' || echo 'wds-fix no esta corriendo'
            echo '--- TABLA BRIDGE WDS_ISOLATE ---'
            nft list table bridge wds_isolate 2>/dev/null || echo 'Tabla wds_isolate no cargada'
        "
        ;;
    sync-wds)
        echo "[+] Sincronizando servicio wds-fix..."
        scp router/usr/sbin/wds-fix.uc "${ROUTER_USER}@${ROUTER_IP}:/usr/sbin/wds-fix.uc"
        scp router/etc/init.d/wds-fix "${ROUTER_USER}@${ROUTER_IP}:/etc/init.d/wds-fix"
        ssh "${ROUTER_USER}@${ROUTER_IP}" "
            chmod +x /usr/sbin/wds-fix.uc /etc/init.d/wds-fix
            /etc/init.d/wds-fix restart
            echo '[+] wds-fix reiniciado correctamente.'
        "
        ;;
    sync-firewall)
        echo "[+] Sincronizando reglas de aislamiento L2..."
        scp router/etc/firewall.wds-isolate.nft "${ROUTER_USER}@${ROUTER_IP}:/etc/firewall.wds-isolate.nft"
        ssh "${ROUTER_USER}@${ROUTER_IP}" "
            nft -f /etc/firewall.wds-isolate.nft
            /etc/init.d/firewall reload
            echo '[+] Reglas de firewall aplicadas.'
        "
        ;;
    sync-all)
        echo "[+] Sincronizando todos los archivos y configuraciones..."
        scp router/usr/sbin/wds-fix.uc "${ROUTER_USER}@${ROUTER_IP}:/usr/sbin/wds-fix.uc"
        scp router/etc/init.d/wds-fix "${ROUTER_USER}@${ROUTER_IP}:/etc/init.d/wds-fix"
        scp router/etc/firewall.wds-isolate.nft "${ROUTER_USER}@${ROUTER_IP}:/etc/firewall.wds-isolate.nft"
        ssh "${ROUTER_USER}@${ROUTER_IP}" "
            chmod +x /usr/sbin/wds-fix.uc /etc/init.d/wds-fix
            /etc/init.d/wds-fix restart
            nft -f /etc/firewall.wds-isolate.nft
            /etc/init.d/firewall reload
            echo '[+] Todo sincronizado y reiniciado exitosamente.'
        "
        ;;
    logs)
        ssh "${ROUTER_USER}@${ROUTER_IP}" "logread -e wds -e hostapd"
        ;;
    *)
        usage
        ;;
esac
