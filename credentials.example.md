# Plantilla de Credenciales y Secretos (Ejemplo)

> [!NOTE]
> Copia este archivo como `credentials.local.md` para almacenar tus credenciales reales localmente.
> El archivo `credentials.local.md` está excluido en `.gitignore` para proteger tus claves en repositorios públicos.

---

## 1. Routers y Dispositivos de Red

| Dispositivo | IP / URL | Usuario | Contraseña / Clave | Notas |
| :--- | :--- | :--- | :--- | :--- |
| **Asus RT-AX52** (Principal) | `192.168.2.1` / `10.10.10.1` | `root` | `<PASSWORD_ASUS_ROOT>` | SSH puerto 22 y LuCI |
| **TP-Link Archer C60** (Repetidor) | `http://192.168.2.2` | `<USER_ARCHER>` | `<PASSWORD_ARCHER>` | Panel Web stock |
| **Módem Movistar Askey** (Bridge) | `http://192.168.1.1/padrao` | `admin` | `<PASSWORD_ETIQUETA_MODEM>` | Menú avanzado |

---

## 2. Enlace WAN Fibra Óptica (Movistar PPPoE)

* **VLAN GPON:** `10`
* **Username PPPoE:** `<USUARIO_PPPOE_SPEEDY>`
* **Password PPPoE:** `<PASSWORD_PPPOE_SPEEDY>`
* **Servidores DNS Upstream Movistar:** `186.130.128.250` / `186.130.129.250`

---

## 3. Servicios y DNS Dinámico

* **DuckDNS:**
  * **Dominio:** `<TU_SUBDOMINIO>.duckdns.org`
  * **Token API:** `<TU_TOKEN_DUCKDNS>`
* **Servidor Apollo / Sunshine:**
  * **Panel Web local:** `https://localhost:27990`
  * **Puerto de Streaming:** `27989`
