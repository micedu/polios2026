#!/bin/bash
# =====================================================================
#  TALLER EVALUATIVO DE SISTEMAS OPERATIVOS  -  MONTAJE DEL ESCENARIO
#  Tecnologia en Sistematizacion de Datos
#  Uso:   bash montaje.sh <CODIGO-DE-ESTUDIANTE>
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

BASE=/opt/taller
mkdir -p "$BASE"

# ---------- semilla derivada del codigo del estudiante ----------
SEM=$(printf '%s' "$CODIGO" | md5sum | tr -dc '0-9' | cut -c1-9)
SEM=$((10#$SEM))

INODOS=$(( 320 + SEM % 180 ))        # 320 - 499
MEMMB=$(( 140 + (SEM / 7) % 160 ))   # 140 - 299 MB
CACHEMB=$(( 400 + (SEM / 13) % 300 ))
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

# llenar el cache de paginas leyendo un archivo grande
dd if=/dev/zero of="$BASE/relleno.bin" bs=1M count="$CACHEMB" status=none 2>/dev/null
cat "$BASE/relleno.bin" > /dev/null 2>&1

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
sleep 1

# =====================================================================
#  BLOQUE C  -  SISTEMA DE ARCHIVOS
# =====================================================================
echo "[C] Preparando el volumen de datos..."

truncate -s 96M "$BASE/volumen.img"
mkfs.ext4 -q -F -N "$INODOS" "$BASE/volumen.img" 2>/dev/null
mkdir -p /mnt/datos
mount -o loop "$BASE/volumen.img" /mnt/datos 2>/dev/null

if mountpoint -q /mnt/datos; then
  LIBRES=$(df -i /mnt/datos | awk 'NR==2 {print $4}')
  CREAR=$(( LIBRES - 12 ))
  ( cd /mnt/datos && for i in $(seq 1 "$CREAR"); do : > "reg_$i.dat"; done ) 2>/dev/null
else
  echo "    AVISO: no se pudo montar el volumen de datos."
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
sleep 3
mkfs.ext4 -q -F /dev/md0 2>/dev/null
mkdir -p /mnt/arreglo
mount /dev/md0 /mnt/arreglo 2>/dev/null

if mountpoint -q /mnt/arreglo; then
  echo "Registro academico del estudiante $CODIGO" > /mnt/arreglo/datos_criticos.txt
  echo "Generado el $(date)"                      >> /mnt/arreglo/datos_criticos.txt
  sync
fi

# provocar la falla de uno de los tres discos
DISCO_FALLA=$(echo $LOOPS | cut -d' ' -f"$FALLA")
mdadm --manage /dev/md0 --fail "$DISCO_FALLA" >/dev/null 2>&1

# limitar la velocidad de reconstruccion para que se pueda observar
echo 2000 > /proc/sys/dev/raid/speed_limit_max 2>/dev/null

# =====================================================================
#  REGISTRO
# =====================================================================
printf '%s' "$CODIGO" > "$BASE/.codigo"
date +%s > "$BASE/.inicio"
printf '%s' "$REPUESTO" > "$BASE/.repuesto"
chmod 600 "$BASE/.codigo" "$BASE/.inicio" "$BASE/.repuesto" 2>/dev/null

echo
echo "==================================================="
echo " ESCENARIO LISTO  -  codigo $CODIGO"
echo "==================================================="
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
