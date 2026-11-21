#!/bin/bash
# =====================================================================
#  TALLER EVALUATIVO DE SISTEMAS OPERATIVOS  -  MONTAJE DEL ESCENARIO
#  Tecnologia en Sistematizacion de Datos
#  Uso:   bash montaje.sh <CODIGO-DE-ESTUDIANTE>
#
#  El script comprueba su propio trabajo al final y avisa si algo
#  no quedo montado. Si no termina con "ESCENARIO LISTO", avise al
#  docente antes de continuar.
# =====================================================================
set -u

CODIGO="${1:-}"
if [ -z "$CODIGO" ]; then
  echo "ERROR: falta su codigo de estudiante."
  echo "Uso: bash montaje.sh 1234567"
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: este montaje debe ejecutarse como root."
  exit 1
fi

# ---------- requisitos ----------
FALTAN=""
for cmd in losetup mdadm mkfs.ext4 truncate python3 df dd; do
  command -v "$cmd" >/dev/null 2>&1 || FALTAN="$FALTAN $cmd"
done
if [ -n "$FALTAN" ]; then
  echo "ERROR: faltan herramientas en esta maquina:$FALTAN"
  echo "Avise al docente: el entorno no es el correcto."
  exit 1
fi

BASE=/opt/taller
mkdir -p "$BASE"

# ---------- semilla derivada del codigo del estudiante ----------
SEM=$(printf '%s' "$CODIGO" | md5sum | tr -dc '0-9' | cut -c1-9)
SEM=$((10#$SEM))

MEMMB=$(( 140 + (SEM / 7) % 160 ))   # 140 - 299 MB
INODOS=$(( 320 + SEM % 180 ))        # 320 - 499
FALLA=$(( SEM % 3 + 1 ))             # cual disco del arreglo falla

echo "==================================================="
echo " Montando el escenario para el codigo: $CODIGO"
echo " Esto toma alrededor de un minuto. No interrumpa."
echo "==================================================="

# ---------- limpieza de un montaje anterior ----------
pkill -f "$BASE/consumidor.py"  2>/dev/null
pkill -f "$BASE/padre.sh"       2>/dev/null
pkill -f "$BASE/hijo.sh"        2>/dev/null
umount /mnt/datos   2>/dev/null
umount /mnt/arreglo 2>/dev/null
mdadm --stop /dev/md0 2>/dev/null
losetup -D 2>/dev/null
rm -f "$BASE"/*.img
sleep 1

modprobe loop 2>/dev/null || true

# =====================================================================
#  BLOQUE A  -  MEMORIA
# =====================================================================
echo "[A] Preparando el escenario de memoria..."

cat > "$BASE/consumidor.py" <<'PY'
import sys, time
mb = int(sys.argv[1])
bloque = bytearray(1024 * 1024 * mb)
for i in range(0, len(bloque), 4096):
    bloque[i] = 1
time.sleep(14400)
PY

nohup python3 "$BASE/consumidor.py" "$MEMMB" >/dev/null 2>&1 &

# el llenado del cache se dimensiona segun la maquina: sin esto, en un
# equipo grande la memoria libre no baja y el sintoma no aparece
sleep 2
LIBRE_MEM=$(free -m | awk '/^Mem:/ {print $4}')
LIBRE_DISCO=$(df -m "$BASE" | awk 'NR==2 {print $4}')
CACHEMB=$(( LIBRE_MEM * 75 / 100 ))
TOPE_DISCO=$(( LIBRE_DISCO / 3 ))
[ "$CACHEMB" -gt "$TOPE_DISCO" ] && CACHEMB=$TOPE_DISCO
[ "$CACHEMB" -gt 6000 ] && CACHEMB=6000
[ "$CACHEMB" -lt 200 ]  && CACHEMB=200
echo "    (llenando el cache con ${CACHEMB} MB)"
dd if=/dev/zero of="$BASE/relleno.bin" bs=1M count="$CACHEMB" status=none 2>/dev/null
cat "$BASE/relleno.bin" > /dev/null 2>&1
sync

# =====================================================================
#  BLOQUE B  -  PROCESOS
# =====================================================================
echo "[B] Preparando el escenario de procesos..."

cat > "$BASE/hijo.sh" <<'EOF'
#!/bin/bash
sleep 14400
EOF

cat > "$BASE/padre.sh" <<'EOF'
#!/bin/bash
/opt/taller/hijo.sh &
sleep 14400
EOF

chmod +x "$BASE/padre.sh" "$BASE/hijo.sh"
nohup "$BASE/padre.sh" >/dev/null 2>&1 &
sleep 2

# =====================================================================
#  BLOQUE C  -  SISTEMA DE ARCHIVOS
# =====================================================================
echo "[C] Preparando el volumen de datos..."

truncate -s 96M "$BASE/volumen.img"
mkfs.ext4 -q -F -N "$INODOS" "$BASE/volumen.img" 2>/dev/null
mkdir -p /mnt/datos
mount -o loop "$BASE/volumen.img" /mnt/datos 2>/dev/null

if mountpoint -q /mnt/datos; then
  # crear archivos vacios hasta agotar por completo los inodos
  ( cd /mnt/datos && i=1; while : > "reg_$i.dat" 2>/dev/null; do i=$((i+1)); done ) 2>/dev/null
  sync
fi

# =====================================================================
#  BLOQUE D  -  RAID
# =====================================================================
echo "[D] Preparando el arreglo de discos..."

for i in 1 2 3 4; do
  truncate -s 128M "$BASE/disco$i.img"
done

LOOPS=""
for i in 1 2 3; do
  L=$(losetup -f --show "$BASE/disco$i.img" 2>/dev/null)
  LOOPS="$LOOPS $L"
done
REPUESTO=$(losetup -f --show "$BASE/disco4.img" 2>/dev/null)

# shellcheck disable=SC2086
mdadm --create /dev/md0 --auto=yes --level=5 --raid-devices=3 $LOOPS --run >/dev/null 2>&1
sleep 4
mkfs.ext4 -q -F /dev/md0 2>/dev/null
mkdir -p /mnt/arreglo
mount /dev/md0 /mnt/arreglo 2>/dev/null

if mountpoint -q /mnt/arreglo; then
  echo "Registro academico del estudiante $CODIGO" > /mnt/arreglo/datos_criticos.txt
  echo "Generado el $(date)"                      >> /mnt/arreglo/datos_criticos.txt
  sync
fi

DISCO_FALLA=$(echo $LOOPS | cut -d' ' -f"$FALLA")
mdadm --manage /dev/md0 --fail "$DISCO_FALLA" >/dev/null 2>&1
sleep 1

if [ -w /proc/sys/dev/raid/speed_limit_max ]; then
  echo 2000 > /proc/sys/dev/raid/speed_limit_max
fi

# ---------- registro ----------
printf '%s' "$CODIGO" > "$BASE/.codigo"
date +%s > "$BASE/.inicio"
printf '%s' "$REPUESTO" > "$BASE/.repuesto"
chmod 600 "$BASE/.codigo" "$BASE/.inicio" "$BASE/.repuesto" 2>/dev/null

# =====================================================================
#  COMPROBACION DEL PROPIO MONTAJE
# =====================================================================
echo
echo "Comprobando el escenario..."
A=0; B=0; CC=0; D=0
DET_A="no se encontro el proceso consumidor"
DET_B="no se encontraron los procesos padre e hijo"
DET_C="el volumen /mnt/datos no quedo sin inodos"
DET_D="el arreglo /dev/md0 no quedo degradado"

if pgrep -f "$BASE/consumidor.py" >/dev/null 2>&1; then
  M_LIBRE=$(free -m | awk '/^Mem:/ {print $4}')
  M_DISP=$(free -m  | awk '/^Mem:/ {print $7}')
  M_TOT=$(free -m   | awk '/^Mem:/ {print $2}')
  BRECHA=$(( M_DISP - M_LIBRE ))
  PCT_LIBRE=$(( M_LIBRE * 100 / M_TOT ))
  if [ "$BRECHA" -ge 200 ]; then
    A=1
    DET_A="libre ${PCT_LIBRE} %, brecha libre-disponible de ${BRECHA} MB"
  else
    DET_A="la brecha entre libre y disponible es de solo ${BRECHA} MB: el sintoma no se nota"
  fi
fi

if pgrep -f "$BASE/padre.sh" >/dev/null 2>&1 && pgrep -f "$BASE/hijo.sh" >/dev/null 2>&1; then
  B=1; DET_B="padre e hijo en ejecucion"
fi

if mountpoint -q /mnt/datos 2>/dev/null; then
  USO=$(df -i /mnt/datos | awk 'NR==2 {gsub("%","",$5); print $5}')
  TOT=$(df -i /mnt/datos | awk 'NR==2 {print $2}')
  if [ -n "${USO:-}" ] && [ "$USO" -ge 99 ]; then
    CC=1; DET_C="$TOT inodos, todos ocupados"
  else
    DET_C="el volumen quedo con inodos libres (${USO:-?} % usado)"
  fi
fi

if [ -e /proc/mdstat ] && grep -q "^md0" /proc/mdstat 2>/dev/null; then
  if grep -A2 "^md0" /proc/mdstat | grep -qE "\[(_UU|U_U|UU_)\]"; then
    if mountpoint -q /mnt/arreglo 2>/dev/null && [ -r /mnt/arreglo/datos_criticos.txt ]; then
      D=1; DET_D="RAID 5 degradado, fallo $DISCO_FALLA, datos legibles"
    else
      DET_D="el arreglo esta degradado pero no se pudo montar"
    fi
  fi
elif [ ! -e /proc/mdstat ]; then
  DET_D="este nucleo no tiene soporte de RAID por software"
fi

TOTAL=$(( A + B + CC + D ))

echo
echo "==================================================="
printf " A  Memoria ............... %s  (%s)\n" "$([ $A  -eq 1 ] && echo 'LISTO' || echo 'FALLO')" "$DET_A"
printf " B  Procesos .............. %s  (%s)\n" "$([ $B  -eq 1 ] && echo 'LISTO' || echo 'FALLO')" "$DET_B"
printf " C  Sistema de archivos ... %s  (%s)\n" "$([ $CC -eq 1 ] && echo 'LISTO' || echo 'FALLO')" "$DET_C"
printf " D  Arreglo de discos ..... %s  (%s)\n" "$([ $D  -eq 1 ] && echo 'LISTO' || echo 'FALLO')" "$DET_D"
echo "==================================================="

if [ "$TOTAL" -ne 4 ]; then
  echo
  echo " ATENCION: solo $TOTAL de 4 situaciones quedaron montadas."
  echo " NO empiece el taller. Avise al docente ahora mismo e"
  echo " indiquele cual bloque dice FALLO y que mensaje aparece."
  echo
  exit 1
fi

echo
echo " ESCENARIO LISTO  -  codigo $CODIGO"
echo
echo " Hay cuatro situaciones por diagnosticar:"
echo
echo "   A. La memoria del equipo parece estar agotada."
echo "   B. Hay procesos del taller corriendo en /opt/taller."
echo "   C. El volumen montado en /mnt/datos no acepta archivos nuevos."
echo "   D. El arreglo de discos /dev/md0 no esta sano."
echo
echo " Un disco de repuesto quedo disponible en: $REPUESTO"
echo
echo " Siga la guia. Cuando termine, ejecute:   bash verificar.sh"
echo
