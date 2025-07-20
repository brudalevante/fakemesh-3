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

echo "==== 5. PREPARA FEEDS Y CONFIGS BASE ===="
echo cc0de56"" > mtk-openwrt-feeds/autobuild/unified/feed_revision

# Selección de config base por parámetro, por defecto rc1_ext_mm_config
CONFIG_BASENAME=${1:-rc1_ext_mm_config}
cp -r configs/$CONFIG_BASENAME mtk-openwrt-feeds/autobuild/unified/filogic/24.10/defconfig

# Desactiva perf e iperf en todos los defconfigs relevantes de Mediatek
for file in \
    mtk-openwrt-feeds/autobuild/unified/filogic/24.10/defconfig \
    mtk-openwrt-feeds/autobuild/autobuild_5.4_mac80211_release/mt7988_wifi7_mac80211_mlo/.config \
    mtk-openwrt-feeds/autobuild/autobuild_5.4_mac80211_release/mt7986_mac80211/.config; do
  [ -f "$file" ] && sed -i '/^CONFIG_PACKAGE_perf=y/d;/^CONFIG_PACKAGE_iperf=y/d' "$file"
done

cp -r my_files/w-rules mtk-openwrt-feeds/autobuild/unified/filogic/rules
rm -rf mtk-openwrt-feeds/24.10/patches-feeds/108-strongswan-add-uci-support.patch

echo "==== 6. COPIA PARCHES Y ARCHIVOS PERSONALIZADOS ===="
cp -r my_files/1007-wozi-arch-arm64-dts-mt7988a-add-thermal-zone.patch mtk-openwrt-feeds/24.10/patches-base/
cp -r my_files/200-wozi-libiwinfo-fix_noise_reading_for_radios.patch openwrt/package/network/utils/iwinfo/patches
cp -r my_files/99999_tx_power_check.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/24.10/files/package/kernel/mt76/patches/
cp -r my_files/999-2764-net-phy-sfp-add-some-FS-copper-SFP-fixes.patch openwrt/target/linux/mediatek/patches-6.6/
# Si quieres el de Dan Pawlik, descomenta:
# cp -r my_files/99999_tx_power_check_by_dan_pawlik.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/24.10/files/package/kernel/mt76/patches/

echo "==== 7. COPIA PAQUETES PERSONALIZADOS ===="
git clone --depth=1 --single-branch --branch main https://github.com/brudalevante/fakemesh-6g.git tmp_comxwrt
for app in fakemesh autoreboot cpu-status temp-status dawn; do
  cp -rv tmp_comxwrt/luci-app-$app openwrt/package/
done

# Kmods personalizados (si existen)
if [ -d my_files/kmods ]; then
  echo "==== 7b. COPIA KMODS PERSONALIZADOS ===="
  cp -rv my_files/kmods/* openwrt/package/
fi

echo "==== 8. ARCHIVOS ETC PERSONALIZADOS ===="
mkdir -p openwrt/files/etc
if [ -d my_files/etc ]; then
  cp -rv my_files/etc/* openwrt/files/etc/
fi

echo "==== 9. CONFIGURACIÓN Y FEEDS ===="
cd openwrt
cp -r ../configs/$CONFIG_BASENAME .config 2>/dev/null || echo "No existe $CONFIG_BASENAME, omitiendo"
./scripts/feeds update -a
./scripts/feeds install -a

echo "==== 10. ACTIVA PAQUETES PERSONALIZADOS EN .CONFIG ===="
for app in fakemesh autoreboot cpu-status temp-status dawn; do
  echo "CONFIG_PACKAGE_luci-app-$app=y" >> .config
done

# Si tienes más kmods personalizados, añádelos aquí:
# echo "CONFIG_PACKAGE_kmod-xxxx=y" >> .config

make defconfig

echo "==== 11. LIMPIA PAQUETES NO DESEADOS EN .CONFIG FINAL ===="
sed -i '/^CONFIG_PACKAGE_perf=y/d;/^CONFIG_PACKAGE_iperf=y/d' .config

echo "==== 12. CHEQUEA PAQUETES FINALES ===="
for app in fakemesh autoreboot cpu-status temp-status dawn; do
  grep $app .config || echo "NO aparece $app en .config"
done

echo "==== 13. AUTOBUILD ===="
bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic-mac80211-mt7988_rfb-mt7996 log_file=make

# Fix para padding warning (si lo necesitas)
sed -i 's/\($(call ERROR_MESSAGE,WARNING: Applying padding.*\)/#\1/' package/Makefile

echo "==== 14. COMPILA ===="
make -j$(nproc)

echo "==== 15. LIMPIEZA FINAL ===="
cd ..
rm -rf tmp_comxwrt

echo "==== Script finalizado correctamente ===="
