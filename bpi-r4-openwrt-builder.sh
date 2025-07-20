#!/bin/bash
set -e

echo "==== 1. LIMPIEZA ===="
rm -rf openwrt mtk-openwrt-feeds tmp_comxwrt

echo "==== 2. CLONA REPOS DESDE TUS FORKS ===="
git clone --branch openwrt-24.10 https://github.com/brudalevante/openwrt.git openwrt || true
cd openwrt
git checkout bb59922007043c0a0813d62b0d9f6e801caff9df
cd ..
git clone https://github.com/brudalevante/mtk-openwrt-feeds.git || true
cd mtk-openwrt-feeds
git checkout cc0de566eb90309e997d66ed1095579eb3b30751
cd ..

echo "==== 3. LIMPIEZA DE PARCHES CONFLICTIVOS ===="
find mtk-openwrt-feeds -type f -name 'cryptsetup-*.patch' -delete

echo "==== 4. CAMBIA KERNEL A 6.6.98 ===="
TARGET_MK="openwrt/target/linux/mediatek/Makefile"
if [ -f "$TARGET_MK" ]; then
    sed -i 's/^\(LINUX_VERSION:=\).*$/\1 6.6.98/' "$TARGET_MK"
fi
KVER_MK="openwrt/include/kernel-version.mk"
HASH_LINE="LINUX_KERNEL_HASH-6.6.98 := 296a34c500abc22c434b967d471d75568891f06a98f11fc31c5e79b037f45de5"
grep -q '^LINUX_KERNEL_HASH-6.6.98' "$KVER_MK" || echo "$HASH_LINE" >> "$KVER_MK"

echo "==== 5. PREPARA FEEDS Y CONFIGURACIONES BASE ===="
echo cc0de56"" > mtk-openwrt-feeds/autobuild/unified/feed_revision

# Selección de config base por parámetro, por defecto rc1_ext_mm_config
CONFIG_BASENAME=${1:-rc1_ext_mm_config}
cp -r configs/$CONFIG_BASENAME mtk-openwrt-feeds/autobuild/unified/filogic/24.10/defconfig

# Desactiva perf en todos los defconfigs relevantes de Mediatek
for file in \
    mtk-openwrt-feeds/autobuild/unified/filogic/24.10/defconfig \
    mtk-openwrt-feeds/autobuild/autobuild_5.4_mac80211_release/mt7988_wifi7_mac80211_mlo/.config \
    mtk-openwrt-feeds/autobuild/autobuild_5.4_mac80211_release/mt7986_mac80211/.config; do
  [ -f "$file" ] && sed -i '/^CONFIG_PACKAGE_perf=y/d' "$file"
done

cp -r my_files/w-rules mtk-openwrt-feeds/autobuild/unified/filogic/rules
rm -rf mtk-openwrt-feeds/24.10/patches-feeds/108-strongswan-add-uci-support.patch

echo "==== 6. COPIA PARCHES ===="
cp -r my_files/1007-wozi-arch-arm64-dts-mt7988a-add-thermal-zone.patch mtk-openwrt-feeds/24.10/patches-base/
cp -r my_files/200-wozi-libiwinfo-fix_noise_reading_for_radios.patch openwrt/package/network/utils/iwinfo/patches
cp -r my_files/99999_tx_power_check.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/24.10/files/package/kernel/mt76/patches/
cp -r my_files/999-2764-net-phy-sfp-add-some-FS-copper-SFP-fixes.patch openwrt/target/linux/mediatek/patches-6.6/
# Si quieres el de Dan Pawlik, descomenta:
# cp -r my_files/99999_tx_power_check_by_dan_pawlik.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/24.10/files/package/kernel/mt76/patches/

echo "==== 7. COPIA PAQUETES PERSONALIZADOS ===="
git clone --depth=1 --single-branch --branch main https://github.com/brudalevante/fakemesh-6g.git tmp_comxwrt
cp -rv tmp_comxwrt/luci-app-fakemesh openwrt/package/
cp -rv tmp_comxwrt/luci-app-autoreboot openwrt/package/
cp -rv tmp_comxwrt/luci-app-cpu-status openwrt/package/
cp -rv tmp_comxwrt/luci-app-temp-status openwrt/package/
cp -rv tmp_comxwrt/luci-app-dawn openwrt/package/
cp -rv tmp_comxwrt/luci-app-usteer openwrt/package/

# Kmods personalizados (si existen)
if [ -d my_files/kmods ]; then
  echo "==== 7b. COPIA KMODS PERSONALIZADOS ===="
  cp -rv my_files/kmods/* openwrt/package/
fi

echo "==== 8. COPIA ARCHIVOS DE CONFIGURACION DE RED (ETC) ===="
mkdir -p openwrt/files/etc
if [ -d my_files/etc ]; then
  cp -rv my_files/etc/* openwrt/files/etc/
fi

echo "==== 9. ENTRA EN OPENWRT Y PREPARA FEEDS ===="
cd openwrt

echo "==== LIMPIANDO feeds.conf.default y feeds/ previos ===="
rm -f feeds.conf.default
rm -rf feeds/

echo "==== ESCRIBIENDO feeds.conf.default SOLO CON TUS FEEDS ===="
cat > feeds.conf.default <<EOF
src-git packages https://github.com/brudalevante/packages.git
src-git luci https://github.com/brudalevante/luci.git
src-git routing https://github.com/brudalevante/routing.git
src-git telephony https://github.com/brudalevante/telephony.git
EOF

echo "==== CHEQUEO: REMOTO Y RAMA ===="
git remote -v
git rev-parse --abbrev-ref HEAD
echo "==== CHEQUEO: feeds.conf.default ===="
cat feeds.conf.default

cp -r ../configs/$CONFIG_BASENAME .config 2>/dev/null || echo "No existe $CONFIG_BASENAME, omitiendo"

# Limpia perf ANTES de actualizar feeds y defconfig
sed -i '/^CONFIG_PACKAGE_perf=y/d' .config
sed -i '/^# CONFIG_PACKAGE_perf is not set/d' .config
echo "# CONFIG_PACKAGE_perf is not set" >> .config

./scripts/feeds update -a
./scripts/feeds install -a

echo "==== 10. AÑADE PAQUETES PERSONALIZADOS AL .CONFIG ===="
echo "CONFIG_PACKAGE_luci-app-fakemesh=y" >> .config
echo "CONFIG_PACKAGE_luci-app-autoreboot=y" >> .config
echo "CONFIG_PACKAGE_luci-app-cpu-status=y" >> .config
echo "CONFIG_PACKAGE_luci-app-temp-status=y" >> .config
echo "CONFIG_PACKAGE_luci-app-dawn=y" >> .config
echo "CONFIG_PACKAGE_luci-app-usteer=y" >> .config

# Limpia perf OTRA VEZ antes de make defconfig
sed -i '/^CONFIG_PACKAGE_perf=y/d' .config
sed -i '/^# CONFIG_PACKAGE_perf is not set/d' .config
echo "# CONFIG_PACKAGE_perf is not set" >> .config

make defconfig

# Limpia perf DESPUÉS de make defconfig (por si acaso)
sed -i '/^CONFIG_PACKAGE_perf=y/d' .config
sed -i '/^# CONFIG_PACKAGE_perf is not set/d' .config
echo "# CONFIG_PACKAGE_perf is not set" >> .config

echo "==== VERIFICACIÓN PERF FINAL ===="
grep perf .config || echo "perf NO está en .config"

echo "==== 11. VERIFICA PAQUETES EN .CONFIG ===="
grep fakemesh .config      || echo "NO aparece fakemesh en .config"
grep autoreboot .config    || echo "NO aparece autoreboot en .config"
grep cpu-status .config    || echo "NO aparece cpu-status en .config"
grep temp-status .config   || echo "NO aparece temp-status en .config"
grep dawn .config          || echo "NO aparece dawn en .config"
grep usteer .config        || echo "NO aparece usteer en .config"

echo "==== 12. SEGURIDAD EXTRA: DESACTIVA PERF EN EL .CONFIG FINAL (por si acaso) ===="
sed -i '/^CONFIG_PACKAGE_perf=y/d' .config
sed -i '/^# CONFIG_PACKAGE_perf is not set/d' .config
echo "# CONFIG_PACKAGE_perf is not set" >> .config

echo "==== 13. EJECUTA AUTOBUILD ===="
bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic-mac80211-mt7988_rfb-mt7996 log_file=make

# ==== ELIMINAR EL WARNING EN ROJO DEL MAKEFILE ====
sed -i 's/\($(call ERROR_MESSAGE,WARNING: Applying padding.*\)/#\1/' package/Makefile

echo "==== 14. COMPILA ===="
make -j$(nproc)

echo "==== 15. LIMPIEZA FINAL ===="
cd ..
rm -rf tmp_comxwrt

echo "==== Script finalizado correctamente ===="
