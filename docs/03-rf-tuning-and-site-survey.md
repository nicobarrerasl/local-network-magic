# 3. Optimización de Radiofrecuencia (RF) y Estudio de Ubicaciones

Durante las pruebas iniciales, el enlace WDS arrojaba velocidades reales de transferencia de solo **30 Mbps**. Mediante optimizaciones a nivel de capa física y espectral, el rendimiento se elevó hasta **116 Mbps** estables.

---

## 3.1 Claves de Optimización de RF

### 1. Forzar Ancho de Canal de 40 MHz (`noscan='1'`)
* **Problema:** En la banda de 2.4 GHz, `hostapd` implementa por defecto el escaneo de coexistencia BSS (802.11n). Si detecta la presencia de cualquier red vecina en canales adyacentes, degrada automáticamente el canal a **20 MHz**, limitando la tasa física a `130–144.4 Mbps` (MCS 15).
* **Solución:** Forzar el canal de 40 MHz mediante UCI:
  ```sh
  uci set wireless.radio0.noscan='1'
  uci commit wireless
  wifi reload
  ```
* **Resultado:** La tasa física se duplicó a **`270–300 Mbps`** y el throughput real aumentó inmediatamente de **30 Mbps a 60 Mbps**.

### 2. Cross-Band Repeating (2.4 GHz para Enlace + 5 GHz para Clientes)
* **Problema:** Si los dispositivos finales se conectan a la radio de 2.4 GHz del Archer C60, la antena debe recibir la trama del Asus y retransmitirla al cliente por la misma frecuencia de radio (*half-duplex*), perdiendo al menos el 50% del ancho de banda útil.
* **Solución:** Encender la radio de **5 GHz en el Archer C60** como punto de acceso local (sin WDS en 5 GHz) y conectar todos los clientes a esta banda.
* **Resultado:** El tráfico entre el Asus y el Archer viaja por 2.4 GHz mientras que el tráfico local del Archer viaja en simultáneo por 5 GHz sin colisiones. La velocidad subió a **80–116 Mbps**.

### 3. Evitar Saturación de RF por Proximidad Extrema
* **Observación:** Al realizar pruebas con ambos routers en el mismo escritorio, la potencia de recepción se situaba en **`-10 dBm`** (con picos de `-9 dBm`).
* **Efecto:** Saturación del Amplificador de Bajo Ruido (LNA) del receptor, provocando una tasa de pérdida de paquetes del **`20.6%` (`tx failed`)**.
* **Rango Óptimo:** La distancia adecuada arrojó señales de **`-45 a -65 dBm`** (en torno a `-49 dBm`), reduciendo las retransmisiones a prácticamente cero y alcanzando **116 Mbps simétricos**.

### 4. Selección Automática de Canal (ACS) Restringida (`channels='1-7'`)
* **Hallazgo:** El Archer C60 persigue de forma autónoma el canal del Asus si este cambia (tarda ~30–35 s en reasociarse).
* **Comportamiento en OpenWrt:** Con canal automático en modo `HE40` / `HT40`, OpenWrt utiliza `ht_capab=[HT40+]` (canal de control + 4 canales arriba). Dado que el código de país `AR` habilita hasta el canal 13, si el algoritmo ACS elegía canal 8 o 9, el canal secundario caía en 12 o 13. Como el firmware stock del Archer solo soporta canales 1 al 11, se caía a 20 MHz.
* **Solución Aplicada:**
  ```sh
  uci set wireless.radio0.channel='auto'
  uci delete wireless.radio0.channels
  uci add_list wireless.radio0.channels='1-7'
  uci commit wireless
  wifi reload
  ```
  Esto permite que el Asus explore dinámicamente el espectro más limpio entre los canales 1 y 11 (desde `1+5` hasta `7+11`), garantizando **40 MHz reales (`243 Mbps MCS 14`)** sin incompatibilidades.

### 5. Selección de Banda para Atravesar Muros
Para atravesar **4 paredes de mampostería maciza**, la banda de **2.4 GHz** demostró ser sustancialmente superior a 5 GHz. Mientras 5 GHz sufre atenuaciones de 10 a 15 dB por pared, 2.4 GHz solo pierde entre 4 y 6 dB, preservando el enlace sin cortes.

---

## 3.2 Estudio Comparativo de Ubicaciones (Site Survey)

| Métrica | Posición A (Detrás de TV) | Posición B (3er Dormitorio) 🏆 | Posición C (Baño Auxiliar) |
| :--- | :---: | :---: | :---: |
| **Señal promedio (`signal avg`)** | `-75 / -76 dBm` | **`-68 / -69 dBm`** | `-65 / -66 dBm` |
| **Señal de retorno (`ack signal`)** | `-72 dBm` | **`-65 dBm`** | `-61 / -62 dBm` |
| **Tasa física TX (Asus → Archer)** | `108 Mbps` (`MCS 11`) | **`243 Mbps` (`MCS 14, 40MHz`)** | `81–108 Mbps` (`MCS 10–11`) |
| **Tasa física RX (Archer → Asus)** | `108 Mbps` (`MCS 5`) | **`162–216 Mbps` (`MCS 12–13`)** | `54–162 Mbps` (`MCS 3–12`) |
| **Throughput estimado por kernel** | `93.5 Mbps` | **`209.6 Mbps`** | `93.5 Mbps` |
| **Latencia Ping (15 paq. 1400 B)** | Prom `14.9 ms` / Máx `129.6 ms` | Prom `11.6 ms` / Máx `34.0 ms` | Prom `3.0 ms` / Máx `9.2 ms` |
| **Diagnóstico Práctico** | La placa metálica de la TV actuaba de jaula atenuadora | **100 Mbps reales de Internet**, seco y pegado al cuarto de la TV | Rebote en cerámicos, espejo y cañerías degrada MIMO + humedad |

* **Conclusión:** La **Posición B** resultó la ganadora indiscutida, logrando saturar el enlace de 100 Mbps de forma consistente.
