# 📡 DOSSIER TEÓRICO DOCENTE: SEGURIDAD INALÁMBRICA, PROTOCOLOS WPA Y AUDITORÍA 802.11
**Materia:** Seguridad en Redes / Ciberseguridad  
**Material de Apoyo para Clases Magistrales y Diapositivas**  
**Complemento Técnico de la Herramienta:** `Dust_Wifi_V2.sh`  

---

## ÍNDICE DE CONTENIDOS
1. [Evolución de los Protocolos de Seguridad 802.11 (WEP a WPA3)](#1-evolución-de-los-protocolos-de-seguridad-80211)
2. [Cifrados, Primitivas y Modos de Autenticación](#2-cifrados-primitivas-y-modos-de-autenticación)
3. [Anatomía Criptográfica del 4-Way Handshake en WPA2](#3-anatomía-criptográfica-del-4-way-handshake-en-wpa2)
4. [Vulnerabilidades y Vectores de Ataque en Redes Inalámbricas](#4-vulnerabilidades-y-vectores-de-ataque-en-redes-inalámbricas)
5. [Mapeo Técnico: ¿Qué Hace Cada Comando de `Dust_Wifi_V2.sh` por Debajo?](#5-mapeo-técnico-comandos-de-dust_wifi_v2sh)
6. [Mecanismos Defensivos y Hardening Corporativo](#6-mecanismos-defensivos-y-hardening-corporativo)

---

## 1. EVOLUCIÓN DE LOS PROTOCOLOS DE SEGURIDAD 802.11

La seguridad en redes inalámbricas ha evolucionado en respuesta a fallos matemáticos e imperfecciones en el diseño de tramas del estándar IEEE 802.11.

```
1997                  2003                  2004                  2018
 WEP   ──────────────► WPA   ──────────────► WPA2  ──────────────► WPA3
(RC4 / 24-bit IV)     (TKIP / RC4)          (CCMP / AES-128)      (SAE / GCMP-256)
 [Roto por diseño]    [Parche temporal]     [Estándar robusto]    [Resistencia moderna]
```

### 1.1 WEP (Wired Equivalent Privacy - 1997)
* **Objetivo inicial:** Ofrecer en el aire una confidencialidad equivalente a una red cableada.
* **Cifrado:** Cifrador de flujo **RC4** con clave estática compartida (40 o 104 bits) + Vector de Inicialización (**IV**) de apenas 24 bits.
* **Por qué colapsó:**
  * El espacio de IVs ($2^{24} \approx 16.7$ millones) es diminuto; en redes activas los IVs se reutilizan en minutos.
  * Reutilizar una clave de flujo $K$ con el mismo IV permite:
    $$C_1 \oplus C_2 = (P_1 \oplus RC4(IV||K)) \oplus (P_2 \oplus RC4(IV||K)) = P_1 \oplus P_2$$
  * Los ataques **FMS (Fluhrer, Mantin, Shamir)** y **KoreK** demostraron que los primeros bytes del flujo RC4 filtraban información de la clave secreta. WEP puede ser crackeado en menos de 60 segundos capturando paquetes ARP.
  * Integridad basada en **CRC32** (lineal y no criptográfico), lo que permitía la inyección y modificación arbitraria de paquetes sin conocer la clave.

### 1.2 WPA (Wi-Fi Protected Access - 2003 / Borrador IEEE 802.11i)
* **Objetivo:** Solución de emergencia implementable mediante actualización de *firmware* en routers antiguos sin requerir hardware nuevo.
* **Cifrado:** **TKIP** (*Temporal Key Integrity Protocol*), que aún utilizaba RC4 pero agregaba:
  * Mezclador de claves por paquete (evita la debilidad del IV de WEP).
  * IV extendido a 48 bits (elimina la reutilización rápida de IVs).
  * Código de integridad de mensaje (**MIC Michael** de 64 bits).
* **Limitación:** Ataques como **Beck-Tews** y **ChopChop** demostraron que el algoritmo MIC Michael podía descifrarse parcialmente y forzar contramedidas (bloqueo de 60 segundos si se detectaban 2 fallos MIC en 1 minuto).

### 1.3 WPA2 (IEEE 802.11i Final - 2004)
* **Objetivo:** Seguridad de grado gubernamental que reemplazó definitivamente a WEP y TKIP.
* **Cifrado:** **CCMP** (*Counter Mode with Cipher Block Chaining Message Authentication Code Protocol*), basado en **AES-128**.
  * **Confidencialidad:** AES en modo Contador (CTR).
  * **Integridad y Autenticación:** CBC-MAC.
* **Estado actual:** El cifrado en sí mismo (AES) es impenetrable con la tecnología actual. Su debilidad radica en el **protocolo de negociación de claves (4-Way Handshake)** en modo Personal (PSK), donde las contraseñas débiles son vulnerables a ataques de diccionario *offline*.

### 1.4 WPA3 (Wi-Fi Alliance - 2018)
* **Objetivo:** Resolver los ataques de diccionario offline y mitigar la falta de cifrado en redes públicas.
* **Innovaciones clave:**
  * **SAE (Simultaneous Authentication of Equals):** Basado en el protocolo Dragonfly (intercambio Diffie-Hellman sobre curvas elípticas). Ofrece **Forward Secrecy** y resistencia total a ataques de diccionario offline.
  * **Cifrado:** GCMP-128 / GCMP-256 (Galois/Counter Mode).
  * **802.11w (PMF) Obligatorio:** Protege las tramas de gestión contra ataques de desautenticación.
  * **OWE (Opportunistic Wireless Encryption):** Cifrado en redes abiertas sin contraseña (adiós a las redes WiFi públicas en texto plano).

---

## 2. CIFRADOS, PRIMITIVAS Y MODOS DE AUTENTICACIÓN

### 2.1 Tabla Comparativa Criptográfica

| Parámetro | WEP | WPA (TKIP) | WPA2 (CCMP) | WPA3 (SAE) |
| :--- | :--- | :--- | :--- | :--- |
| **Cifrador Base** | RC4 (Flujo) | RC4 (Flujo) | AES (Bloque, 128-bit) | AES-GCM (128 / 256-bit) |
| **Tamaño de Clave** | 40 o 104 bits | 128 bits | 128 bits (192 en Enterprise) | 128 o 256 bits |
| **Vector Inicialización** | 24 bits (en claro) | 48 bits | 48 bits (Packet Number - PN) | 96 bits (Nonce GCM) |
| **Código Integridad (MIC)** | CRC-32 (Lineal) | Michael (64 bits) | CBC-MAC (128 bits) | GMAC (Galois MAC) |
| **Autenticación Clave** | Estática | 4-Way Handshake | 4-Way Handshake | Dragonfly (Zero-Knowledge) |
| **Protección Tramas Gestión** | No | No | Opcional (802.11w) | **Obligatoria (802.11w PMF)** |
| **Resistencia Diccionario** | Nula (Roto) | Vulnerable | **Vulnerable si PSK es débil** | **Inmune** |

### 2.2 Modos de Implementación: Personal vs Enterprise

#### A) Modo Personal (WPA-Personal / PSK)
* **Mecanismo:** Todos los usuarios comparten una misma clave alfanumérica fija (*Pre-Shared Key*).
* **Escenario:** Hogares y pequeñas oficinas (SOHO).
* **Problema de seguridad:** Si un atacante captura el 4-Way Handshake de cualquier usuario y conoce o rompe la clave, puede **descifrar retroactivamente el tráfico de todos los demás clientes** o acceder a la red local.

#### B) Modo Corporativo (WPA-Enterprise / 802.1X)
* **Mecanismo:** Autenticación individual cliente a cliente contra un servidor centralizado (**RADIUS**).
* **Protocolo:** Extensible Authentication Protocol (**EAP**) encapsulado sobre LAN (EAPoL).
  * **EAP-TLS:** Autenticación mutua basada en certificados digitales X.509 en cliente y servidor (máxima seguridad, sin contraseñas).
  * **PEAP-MSCHAPv2:** Servidor presenta certificado; cliente envía usuario y contraseña dentro de un túnel TLS seguro.
* **Ventaja:** Cada dispositivo tiene su propia clave de cifrado temporal; no hay clave compartida que comprometa a la organización si un empleado es desvinculado.

---

## 3. ANATOMÍA CRIPTOGRÁFICA DEL 4-WAY HANDSHAKE EN WPA2

El 4-Way Handshake es el protocolo que permite a un cliente (**Supplicant**) y al Punto de Acceso (**Authenticator**) demostrar que conocen la clave secreta compartida sin revelarla nunca en el canal de radio.

```
       Access Point (Authenticator)                     Estación / Cliente (Supplicant)
                   │                                                  │
   1. EAPoL Frame  │─────────────── Anonce ──────────────────────────►│
                   │                                                  │  [Calcula PTK =
                   │                                                  │   PRF(PMK, Anonce,
                   │                                                  │       Snonce, MACs)]
   2. EAPoL Frame  │◄──────── Snonce + MIC + RSN IE ──────────────────│
  [Verifica MIC y  │                                                  │
   calcula PTK]    │                                                  │
                   │                                                  │
   3. EAPoL Frame  │─────────────── GTK + MIC ───────────────────────►│  [Instala claves
                   │                                                  │   PTK y GTK]
   4. EAPoL Frame  │◄─────────────── ACK ─────────────────────────────│
                   │                                                  │
```

### 3.1 Jerarquía y Derivación de Claves

1. **Passphrase (Frase de paso):** Cadena de texto de 8 a 63 caracteres ASCII ingresada por el usuario.
2. **PMK (Pairwise Master Key):** Se deriva mediante **PBKDF2**:
   $$\text{PMK} = \text{PBKDF2}(\text{HMAC-SHA1}, \text{Passphrase}, \text{SSID}, 4096 \text{ iteraciones}, 256 \text{ bits})$$
   *Nota docente:* El SSID actúa como *Salt* criptográfico. Por eso, dos redes con la misma contraseña pero diferente nombre tienen diferente PMK (lo que previene el uso de Rainbow Tables globales).
3. **PTK (Pairwise Transient Key):** Clave de 512 bits única para cada sesión, calculada mediante una función pseudoaleatoria (PRF):
   $$\text{PTK} = \text{PRF-512}(\text{PMK}, \text{"Pairwise key expansion"}, \text{MAC}_{\text{min}}, \text{MAC}_{\text{max}}, \text{Nonce}_{\text{min}}, \text{Nonce}_{\text{max}})$$
   
   La PTK se divide en 3 subclaves:
   * **KCK (Key Confirmation Key - 128 bits):** Usada para calcular y validar el MIC en los mensajes EAPOL.
   * **KEK (Key Encryption Key - 128 bits):** Usada para cifrar la GTK en el Mensaje 3.
   * **TK (Temporal Key - 128 bits):** La clave que realmente cifra los paquetes de datos con AES-CCMP.
4. **GTK (Group Temporal Key):** Clave compartida para tráfico Multicast/Broadcast (del AP a todos los clientes).

### 3.2 ¿Por qué es Vulnerable al Criptoanálisis Offline?

Un atacante en modo monitor captura de las tramas EAPOL:
* $\text{MAC}_{\text{AP}}$ y $\text{MAC}_{\text{Cliente}}$ (en las cabeceras 802.11).
* $\text{Anonce}$ (en el Mensaje 1).
* $\text{Snonce}$ y el $\text{MIC}_{\text{real}}$ (en el Mensaje 2).

Para cada palabra candidata $W$ de un diccionario:
1. Calcula $\text{PMK}' = \text{PBKDF2}(W, \text{SSID})$.
2. Calcula $\text{PTK}' = \text{PRF}(\text{PMK}', \text{Anonce}, \text{Snonce}, \text{MACs})$.
3. Extrae la subclave $\text{KCK}'$ de $\text{PTK}'$.
4. Calcula $\text{MIC}' = \text{HMAC-SHA1}(\text{KCK}', \text{EAPOL Payload})$.
5. Compara: **¿$\text{MIC}' == \text{MIC}_{\text{real}}$?**
   * Si coincide: **¡Contraseña encontrada!**
   * Si no: prueba la siguiente palabra.

**Punto crítico para los alumnos:** Este proceso ocurre **100% en la máquina del auditor** a velocidades de miles o millones de claves por segundo (usando GPUs con Hashcat o CPUs con Aircrack-ng), sin interactuar con el router.

---

## 4. VULNERABILIDADES Y VECTORES DE ATAQUE EN REDES INALÁMBRICAS

### 4.1 Ataque de Desautenticación (802.11 Deauth Attack)
* **Causa raíz:** En 802.11 original, las tramas de gestión (Tipo `00`, Subtipo `1100` para Deauthentication) **no están cifradas ni autenticadas**.
* **Mecánica:** Un atacante envía tramas falsificando la dirección MAC origen del AP con código de motivo (*Reason Code 7: Class 3 frame received from nonassociated STA*):
  ```
  [Frame 802.11]
  Source MAC:      [MAC del AP]     <-- Spoofeada
  Destination MAC: [MAC del Cliente]
  BSSID:           [MAC del AP]
  Frame Type:      Management -> Deauthentication
  ```
* **Consecuencia:** La tarjeta del cliente desconecta su interfaz de inmediato. Al reconectarse, genera un nuevo 4-Way Handshake que el auditor captura.

### 4.2 Ataque PMKID (Captura sin Clientes Conectados)
* **Descubierto por:** Jens "atom" Steube (creador de Hashcat) en 2018.
* **Mecánica:** Algunos APs con soporte de *roaming* 802.11r / 802.11k incluyen el campo **PMKID** en el primer mensaje de asociación o en el Mensaje 1 de EAPOL:
  $$\text{PMKID} = \text{HMAC-SHA1}(\text{PMK}, \text{"PMK Name"} \parallel \text{MAC}_{\text{AP}} \parallel \text{MAC}_{\text{STA}})$$
* **Impacto:** Permite crackear la contraseña WPA2 atacando directamente al AP **sin que exista ningún cliente conectado a la red**.

### 4.3 KRACK (Key Reinstallation Attack - 2017)
* **Descubierto por:** Mathy Vanhoef.
* **Causa raíz:** Violación de lógica en la máquina de estados de WPA2. En el Mensaje 3 del Handshake, el AP envía la clave temporal y el cliente la instala, reseteando el contador de paquetes (*Packet Number - PN*) y el Nonce a cero.
* **Explotación:** Si el atacante reenvía un Mensaje 3 duplicado, fuerza al cliente a reinstalar la clave y reiniciar el contador a 0. Esto provoca la reutilización del Keystream en AES-CCMP, permitiendo descifrar paquetes y realizar ataques de inyección/replay.

### 4.4 Evil Twin / Rogue AP
* **Concepto:** Clonación idéntica del ESSID, canal y dirección MAC de una red corporativa pero con mayor potencia de transmisión o en una frecuencia vecina.
* **Ataque combinado:** Se desautentica a los clientes de la red legítima para forzarlos a conectarse al AP falso (Evil Twin), capturando credenciales a través de portales cautivos falsificados.

---

## 5. MAPEO TÉCNICO: COMANDOS DE `Dust_Wifi_V2.sh`

Este apartado desglosa qué ocurre en el sistema operativo Linux cuando el estudiante ejecuta cada opción del script:

```
+----------------------------------------------------------------------------------+
|                   SUBSISTEMA DE RED EN LINUX (nl80211 / cfg80211)                 |
|                                                                                  |
|   Espacio de Usuario:      iw / ip / airodump-ng / aireplay-ng / aircrack-ng     |
|                                    │ (Netlink Sockets / AF_PACKET)               |
|   Espacio de Kernel:       mac80211  <───>  Driver (ath9k, mt7601u, rtl8812au)   |
|                                    │                                             |
|   Hardware:                Chipset RF (PHY Layer) ── Antena                      |
+----------------------------------------------------------------------------------+
```

### 5.1 Comandos de Control de Hardware e Interfaz

#### `nmcli dev set <iface> managed no`
* **Qué hace:** Le ordena al daemon `NetworkManager` que ignore la tarjeta inalámbrica.
* **Por qué es crítico:** Si NetworkManager sigue controlando la tarjeta, intentará escanear redes periódicamente o conectarse a redes conocidas, cambiando el canal de radio en pleno ataque o desactivando el modo monitor.

#### `ip link set <iface> down` / `up`
* **Qué hace:** Desactiva y reactiva la interfaz a nivel de capa de enlace en el kernel. Es un requisito obligatorio del subsistema `mac80211` antes de cambiar el tipo de operación de la tarjeta.

#### `iw dev <iface> set type monitor`
* **Qué hace:** Conmuta el firmware y el driver del chip al modo promiscuo IEEE 802.11 (Modo Monitor).
* **Bajo nivel:** La tarjeta desactiva el filtrado de direcciones MAC por hardware. En lugar de descartar paquetes cuyo destino no sea su propia MAC, la tarjeta entrega **todas las tramas RF que circulan por el aire** directamente al kernel encapsuladas con cabeceras `radiotap` (potencia en dBm, modulación MCS, frecuencia en MHz).

#### `iw phy <phy> info`
* **Qué hace:** Consulta las capacidades del dispositivo físico (*Physical Device - PHY*) en el kernel: bandas compatibles (2.4 GHz, 5 GHz, 6 GHz), canales habilitados, potencia máxima de transmisión (TxPower) y modos soportados.

---

### 5.2 Comandos de la Suite Aircrack-ng

#### `airodump-ng --encrypt WPA --output-format csv --write <file> <iface>`
* **Qué hace:** Abre un socket `AF_PACKET` en modo crudo (*raw socket*) sobre la interfaz monitor.
* **Mecánica:**
  * **Channel Hopping:** Salta rápidamente entre los canales 1 al 14 (o 36-165 en 5 GHz) para escuchar Beacons y Probe Responses de todas las redes cercanas.
  * **Filtrado:** Descarta tramas de datos no cifradas o WEP, analizando el *RSN Information Element* (Tag 48) dentro de los Beacons para extraer únicamente redes WPA/WPA2.
  * **Parseo:** Genera el archivo CSV que luego el script procesa con `awk` y `sort` para construir la lista interactiva del **Top 16 por RSSI**.

#### `airodump-ng -c <CANAL> --bssid <BSSID> -w <file> <iface>`
* **Qué hace:**
  1. **Fija el canal de radio:** Detiene el *Channel Hopping* y ancla la tarjeta al canal específico del objetivo (vital para no perder paquetes).
  2. **Filtra por BSSID:** Solo almacena en el archivo `.cap` las tramas emitidas o destinadas al router objetivo.
  3. **Monitorea tramas EAPOL (Tipo 0x888e):** Inspecciona continuamente el tráfico de datos buscando los 4 mensajes del handshake. Al detectar un mensaje 4 válido tras un mensaje 2 o 3, muestra en pantalla: `[ WPA handshake: BSSID ]`.

#### `aireplay-ng -0 <FRAMES> -a <BSSID> [-c <CLIENTE>] <iface>`
* **Flags:**
  * `-0`: Modo de ataque de desautenticación (*Deauthentication*).
  * `<FRAMES>`: Cantidad de ráfagas de tramas a emitir (ej. 5). Si se especifica `0`, envía tramas en bucle continuo hasta recibir `Ctrl+C`.
  * `-a <BSSID>`: Dirección MAC del AP origen (falsificada).
  * `-c <CLIENTE>`: Dirección MAC de la estación víctima. Si se omite, se envía a `FF:FF:FF:FF:FF:FF` (Broadcast).
* **Bajo nivel:** Construye una trama de gestión 802.11 cruda en memoria y la inyecta directamente al aire a través del driver.

#### `aircrack-ng -w <WORDLIST> -b <BSSID> <ARCHIVO.cap>`
* **Qué hace:** Motor de criptoanálisis por fuerza bruta / diccionario offline.
* **Optimización interna:**
  * Lee el archivo `.cap` (formato PCAP de tcpdump/Wireshark).
  * Extrae los Nonces, las MACs y el MIC.
  * Precalcula el bloque inicial de PBKDF2 si es posible o utiliza instrucciones vectoriales de CPU (**AVX2**, **AVX-512** o **NEON**) para computar múltiples candidatos de contraseña en paralelo por cada ciclo de reloj.

---

## 6. MECANISMOS DEFENSIVOS Y HARDENING CORPORATIVO

Para cerrar una clase de teoría con un enfoque constructivo de ingeniería y defensa, los alumnos deben dominar las tres barreras de protección indispensables:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       TRILOGÍA DE PROTECCIÓN INALÁMBRICA                    │
├──────────────────────────────┬─────────────────────────────┬────────────────┤
│      1. PROTOCOLO            │       2. GESTIÓN (PMF)      │ 3. CREDENCIALES│
│      WPA3-Personal (SAE)     │       IEEE 802.11w          │ 802.1X EAP-TLS │
│   Inmune a ataques offline   │   Evita desautenticación    │ Sin clave fija │
└──────────────────────────────┴─────────────────────────────┴────────────────┘
```

### 6.1 Implementación de IEEE 802.11w (Protected Management Frames - PMF)
* **Cómo funciona:** Añade una cabecera criptográfica **BIP** (*Broadcast Integrity Protocol*) con el algoritmo AES-128-CMAC a las tramas de gestión unicast y multicast.
* **Configuraciones en el Access Point:**
  * *Disabled:* Vulnerable a ataques de desautenticación.
  * *Optional / Capable:* Clientes modernos usan PMF; clientes antiguos siguen desprotegidos.
  * *Required:* **Obligatorio.** Si un atacante inyecta una trama de desautenticación falsificada con `aireplay-ng`, el cliente la descarta de inmediato porque no posee la firma criptográfica válida del AP.

### 6.2 Transición Definitiva a WPA3-SAE
* Al usar el protocolo **Dragonfly**, cualquier intento de descifrado offline requeriría interactuar con el router en tiempo real para cada intento. Esto reduce la velocidad de ataque de millones de claves por segundo en una GPU a unos pocos intentos por segundo, permitiendo que el router bloquee temporalmente al atacante mediante *Rate Limiting*.

### 6.3 Políticas de Contraseñas y Entropía en WPA2
Si la organización debe mantener WPA2 por compatibilidad con dispositivos IoT heredados:
* La contraseña debe tener **mínimo 16 a 20 caracteres**, combinando mayúsculas, minúsculas, números y símbolos.
* Una clave con 16 caracteres aleatorios tiene una entropía de:
  $$E = 16 \times \log_2(95) \approx 105 \text{ bits}$$
  Incluso una granja de GPUs de última generación tardaría siglos en recorrer ese espacio de búsqueda.

### 6.4 Segmentación y Aislamiento de Clientes
* **Wireless Client Isolation:** Configuración en el router que prohíbe que dos clientes WiFi se comuniquen directamente entre sí en la Capa 2. Esto mitiga ataques de Man-in-the-Middle (ARP Spoofing) entre alumnos o dispositivos en una misma red.
* **VLANs Dedicadas:** Separar el tráfico administrativo, de empleados y de invitados en subredes independientes con reglas de firewall estrictas.

---
*Dossier Teórico de Seguridad Inalámbrica &copy; 2026 — Diseñado para Clases Universitarias y Talleres Prácticos*
