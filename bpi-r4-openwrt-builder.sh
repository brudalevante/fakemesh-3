#!/bin/bash

set -e

echo "==== 1. LIMPIEZA ===="
rm -rf openwrt
rm -rf mtk-openwrt-feeds
rm -rf tmp_comxwrt

echo "==== 2. CLONA REPOS ORIGINALES ===="
git clone --branch openwrt-24.10 https://git.openwrt.org/openwrt/openwrt.git openwrt || true
cd openwrt
git checkout 2a348bdbef52adb99280f01ac285d4415e91f4d6
cd ..
git clone https://git01.mediatek.com/openwrt/feeds/mtk-openwrt-feeds || true
cd mtk-openwrt-feeds
git checkout f737b2f5f33d611f9e96f91ffccd0531700b6282
cd ..

echo "==== ELIMINA TODOS LOS PARCHES CONFLICTIVOS DE cryptsetup ===="
find mtk-openwrt-feeds -type f -name 'cryptsetup-*.patch' -delete

echo "==== 1b. CAMBIA KERNEL A 6.6.98 AUTOMÁTICAMENTE ===="
# Cambia la versión de kernel para mediatek (ajusta si usas otro target)
TARGET_MK="openwrt/target/linux/mediatek/Makefile"
if [ -f "$TARGET_MK" ]; then
    echo "Cambiando LINUX_VERSION a 6.6.98 en $TARGET_MK"
    sed -i 's/^\(LINUX_VERSION:=\).*$/\1 6.6.98/' "$TARGET_MK"
else
    echo "No se encontró $TARGET_MK, revisa la ruta del target"
fi

# Añade el hash en include/kernel-version.mk si no está presente
HASH_LINE="LINUX_KERNEL_HASH-6.6.98 := 296a34c500abc22c434b967d471d75568891f06a98f11fc31c5e79b037f45de5"
KVER_MK="openwrt/include/kernel-version.mk"
if grep -q '^LINUX_KERNEL_HASH-6.6.98' "$KVER_MK"; then
    echo "Hash para kernel 6.6.98 ya existe en $KVER_MK"
else
    echo "Añadiendo hash de kernel 6.6.98 a $KVER_MK"
    echo "$HASH_LINE" >> "$KVER_MK"
fi

echo "==== 3. PREPARA FEEDS Y CONFIGURACIONES BASE ===="
echo "f737b2f" > mtk-openwrt-feeds/autobuild/unified/feed_revision
cp -r configs/dbg_defconfig_crypto mtk-openwrt-feeds/autobuild/unified/filogic/24.10/defconfig

# Desactiva perf
sed -i 's/CONFIG_PACKAGE_perf=y/# CONFIG_PACKAGE_perf is not set/' mtk-openwrt-feeds/autobuild/unified/filogic/24.10/defconfig
sed -i 's/CONFIG_PACKAGE_perf=y/# CONFIG_PACKAGE_perf is not set/' mtk-openwrt-feeds/autobuild/autobuild_5.4_mac80211_release/mt7988_wifi7_mac80211_mlo/.config
sed -i 's/CONFIG_PACKAGE_perf=y/# CONFIG_PACKAGE_perf is not set/' mtk-openwrt-feeds/autobuild/autobuild_5.4_mac80211_release/mt7986_mac80211/.config

cp -r my_files/w-rules mtk-openwrt-feeds/autobuild/unified/filogic/rules
rm -rf mtk-openwrt-feeds/24.10/patches-feeds/108-strongswan-add-uci-support.patch

echo "==== 4. COPIA PARCHES ===="
cp -r my_files/1007-wozi-arch-arm64-dts-mt7988a-add-thermal-zone.patch mtk-openwrt-feeds/24.10/patches-base/
cp -r my_files/200-wozi-libiwinfo-fix_noise_reading_for_radios.patch openwrt/package/network/utils/iwinfo/patches
cp -r my_files/99999_tx_power_check.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/24.10/files/package/kernel/mt76/patches/
cp -r my_files/999-2764-net-phy-sfp-add-some-FS-copper-SFP-fixes.patch openwrt/target/linux/mediatek/patches-6.6/
# Si quieres el de Dan Pawlik, descomenta:
# cp -r my_files/99999_tx_power_check_by_dan_pawlik.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/24.10/files/package/kernel/mt76/patches/

echo "==== 5. COPIA PAQUETES PERSONALIZADOS ===="
# Paquetes de fakemesh y otros desde el repo
git clone --depth=1 --single-branch --branch main https://github.com/brudalevante/fakemesh-6g.git tmp_comxwrt
cp -rv tmp_comxwrt/luci-app-fakemesh openwrt/package/
cp -rv tmp_comxwrt/luci-app-autoreboot openwrt/package/
cp -rv tmp_comxwrt/luci-app-cpu-status openwrt/package/
cp -rv tmp_comxwrt/luci-app-temp-status openwrt/package/
cp -rv tmp_comxwrt/luci-app-dawn openwrt/package/

echo "==== 5b. COPIA ARCHIVOS DE CONFIGURACION DE RED (ETC) ===="
mkdir -p openwrt/files/etc
cp -r my_files/etc/* openwrt/files/etc/

echo "==== 6. ENTRA EN OPENWRT Y ACTUALIZA FEEDS ===="
cd openwrt
cp -r ../configs/rc1_ext_mm_config .config 2>/dev/null || echo "No existe rc1_ext_mm_config, omitiendo"
./scripts/feeds update -a
./scripts/feeds install -a

echo "==== 7. AÑADE PAQUETES PERSONALIZADOS AL .CONFIG ===="
echo "CONFIG_PACKAGE_luci-app-fakemesh=y" >> .config
echo "CONFIG_PACKAGE_luci-app-autoreboot=y" >> .config
echo "CONFIG_PACKAGE_luci-app-cpu-status=y" >> .config
echo "CONFIG_PACKAGE_luci-app-temp-status=y" >> .config
echo "CONFIG_PACKAGE_luci-app-dawn=y" >> .config
make defconfig

echo "==== 8. VERIFICA PAQUETES EN .CONFIG ===="
grep fakemesh .config      || echo "NO aparece fakemesh en .config"
grep autoreboot .config    || echo "NO aparece autoreboot en .config"
grep cpu-status .config    || echo "NO aparece cpu-status en .config"
grep temp-status .config   || echo "NO aparece temp-status en .config"
grep dawn .config          || echo "NO aparece dawn en .config"

echo "==== 9. EJECUTA AUTOBUILD ===="
bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic-mac80211-mt7988_rfb-mt7996 log_file=make

# ==== ELIMINAR EL WARNING EN ROJO DEL MAKEFILE ====
sed -i 's/\($(call ERROR_MESSAGE,WARNING: Applying padding.*\)/#\1/' package/Makefile

echo "==== 10. COMPILA ===="
make -j$(nproc)

echo "==== 11. LIMPIEZA FINAL ===="
cd ..
rm -rf tmp_comxwrt

echo "==== Script finalizado correctamente ===="
