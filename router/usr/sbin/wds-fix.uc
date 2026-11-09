#!/usr/bin/ucode
/**
 * wds-fix.uc - Automatic WDS 4-address station VLAN binding daemon
 *
 * Target Hardware: Asus RT-AX52 (MediaTek mt7981 / mt7915e driver)
 * OS: OpenWrt 25.x / Linux Kernel 6.12.x
 *
 * Problem addressed:
 * MediaTek DECAP_OFFLOAD bypasses netlink NL80211_CMD_UNEXPECTED_4ADDR_FRAME,
 * preventing hostapd from automatically instantiating the 4addr AP_VLAN
 * interface for stock Qualcomm Atheros (QCA) stations like TP-Link Archer C60.
 *
 * Strict kernel sequence required by mac80211:
 * 1. NL80211_CMD_NEW_INTERFACE (AP_VLAN with 4addr=1)
 * 2. RTM_SETLINK (up)
 * 3. NL80211_CMD_SET_STATION (bind sta_vlan)
 * 4. Add interface to bridge (br-lan)
 */

import * as nl80211 from "nl80211";
import * as rtnl from "rtnl";
import * as uloop from "uloop";
import { readfile, stat } from "fs";

const TARGET_MAC = "42:84:6a:a9:2e:c9";
const AP_DEV = "phy0-ap0";
const VLAN_DEV = "phy0-ap0.sta1";

function create_vlan() {
    nl80211.request(nl80211.const.NL80211_CMD_DEL_INTERFACE, 0, { dev: VLAN_DEV });
    nl80211.request(nl80211.const.NL80211_CMD_NEW_INTERFACE, nl80211.const.NLM_F_CREATE, {
        dev: AP_DEV,
        ifname: VLAN_DEV,
        iftype: nl80211.const.NL80211_IFTYPE_AP_VLAN,
        "4addr": 1
    });
    rtnl.request(rtnl.const.RTM_SETLINK, 0, { dev: VLAN_DEV, change: 1, flags: 1 });
}

function check_wds() {
    let sta = nl80211.request(nl80211.const.NL80211_CMD_GET_STATION, 0, {
        dev: AP_DEV,
        mac: TARGET_MAC
    });
    if (!sta || !sta.sta_info)
        return;

    let flags = sta.sta_info.sta_flags;
    if (!flags || !(flags[1] & 2))
        return;

    if (!stat(`/sys/class/net/${VLAN_DEV}/ifindex`)) {
        create_vlan();
    }

    let ifidx_str = readfile(`/sys/class/net/${VLAN_DEV}/ifindex`);
    if (!ifidx_str)
        return;

    let ifidx = int(trim(ifidx_str));
    nl80211.error();
    nl80211.request(nl80211.const.NL80211_CMD_SET_STATION, 0, {
        dev: AP_DEV,
        mac: TARGET_MAC,
        sta_vlan: ifidx
    });
    if (nl80211.error()) {
        create_vlan();
        ifidx_str = readfile(`/sys/class/net/${VLAN_DEV}/ifindex`);
        if (!ifidx_str)
            return;
        ifidx = int(trim(ifidx_str));
        nl80211.request(nl80211.const.NL80211_CMD_SET_STATION, 0, {
            dev: AP_DEV,
            mac: TARGET_MAC,
            sta_vlan: ifidx
        });
    }

    if (!stat(`/sys/class/net/br-lan/brif/${VLAN_DEV}`)) {
        system(`brctl addif br-lan ${VLAN_DEV} 2>/dev/null`);
    }
}

uloop.init();
let timer;
function tick() {
    try { check_wds(); } catch (e) {}
    timer.set(2000);
}
timer = uloop.timer(2000, tick);
tick();
uloop.run();
