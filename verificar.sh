#!/bin/bash
# =====================================================================
#  TALLER EVALUATIVO DE SISTEMAS OPERATIVOS  -  VERIFICACION
#  Uso:   bash verificar.sh
# =====================================================================
set -u

BASE=/opt/taller
SAL="so2026tsd"

if [ ! -f "$BASE/.codigo" ]; then
  echo "ERROR: no encuentro el escenario. Ejecute primero el montaje."
  exit 1
fi

CODIGO=$(cat "$BASE/.codigo")
INICIO=$(cat "$BASE/.inicio")
AHORA=$(date +%s)
MIN=$(( (AHORA - INICIO) / 60 ))

# ---------- B: el padre fue terminado y el hijo sobrevivio ----------
B=0
if ! pgrep -f "$BASE/padre.sh" >/dev/null 2>&1; then
  if pgrep -f "$BASE/hijo.sh" >/dev/null 2>&1; then
    B=1
  fi
fi

# ---------- C: se liberaron inodos en /mnt/datos ----------
C=0
if mountpoint -q /mnt/datos 2>/dev/null; then
  USO=$(df -i /mnt/datos | awk 'NR==2 {gsub("%","",$5); print $5}')
  if [ -n "$USO" ] && [ "$USO" -lt 60 ]; then
    C=1
  fi
fi

# ---------- D: el arreglo quedo con sus tres discos sanos ----------
D=0
if grep -q "md0" /proc/mdstat 2>/dev/null; then
  if grep -A2 "^md0" /proc/mdstat | grep -q "\[UUU\]"; then
    D=1
  fi
fi

TOTAL=$(( B + C + D ))
FIRMA=$(printf '%s' "$CODIGO$B$C$D$MIN$SAL" | md5sum | cut -c1-8)
CODIGO_FINAL="TSD-$CODIGO-$B$C$D-${MIN}m-$FIRMA"

echo
echo "==================================================="
echo " VERIFICACION DEL TALLER  -  codigo $CODIGO"
echo "==================================================="
echo
printf " Bloque B  Procesos ............ %s\n" "$([ $B -eq 1 ] && echo 'CUMPLIDO' || echo 'pendiente')"
printf " Bloque C  Sistema de archivos . %s\n" "$([ $C -eq 1 ] && echo 'CUMPLIDO' || echo 'pendiente')"
printf " Bloque D  Arreglo de discos ... %s\n" "$([ $D -eq 1 ] && echo 'CUMPLIDO' || echo 'pendiente')"
echo
printf " Objetivos tecnicos alcanzados: %s de 3\n" "$TOTAL"
printf " Tiempo transcurrido desde el montaje: %s minutos\n" "$MIN"
echo
echo " El bloque A es de observacion: no se verifica aqui,"
echo " se evalua en su informe."
echo
echo "---------------------------------------------------"
echo " COPIE ESTE CODIGO EN SU INFORME:"
echo
echo "   $CODIGO_FINAL"
echo
echo "---------------------------------------------------"
echo
