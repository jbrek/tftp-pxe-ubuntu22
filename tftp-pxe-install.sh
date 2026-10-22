#!/bin/bash
# PXE (UEFI) autoinstall server: Ubuntu 26.04.1 + 22.04.5 live-server
# Run on an Ubuntu server as root:  sudo bash tftp-pxe-install.sh
set -u
[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }

# ---- settings ----
SERVER_IP=${SERVER_IP:-$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -n1)}
SUBNET=${SUBNET:-192.168.1.0}
NETMASK=${NETMASK:-255.255.255.0}
ROUTER=${ROUTER:-192.168.1.1}
RANGE_START=${RANGE_START:-192.168.1.15}
RANGE_END=${RANGE_END:-192.168.1.20}

ISO26=ubuntu-26.04.1-live-server-amd64.iso
URL26=https://releases.ubuntu.com/26.04/$ISO26
ISO22=ubuntu-22.04.5-live-server-amd64.iso
URL22=https://releases.ubuntu.com/22.04/$ISO22
RAW=https://raw.githubusercontent.com/jbrek/tftp-pxe-ubuntu22/main
# ------------------

echo "Server IP: $SERVER_IP"
[ -n "$SERVER_IP" ] || { echo "could not detect SERVER_IP"; exit 1; }
export DEBIAN_FRONTEND=noninteractive

# tftpd-hpa defaults to ":69" (IPv6) and fails to start when IPv6 is disabled -> force IPv4
mkdir -p /srv/tftp
cat > /etc/default/tftpd-hpa <<'EOT'
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/srv/tftp"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure --ipv4"
EOT
dpkg --configure -a

apt-get update
apt-get install -y apache2 tftpd-hpa isc-dhcp-server wget dpkg-dev \
  || { echo "package install failed - check apt output above (isc-dhcp-server may be missing on newer releases)"; exit 1; }

mkdir -p /images/ubuntu26 /images/ubuntu22 /ks /srv/tftp/grub /srv/tftp/ubuntu26 /srv/tftp/ubuntu22

# ---- apache: serve /ks and /images ----
cat > /etc/apache2/conf-available/ks-server.conf <<'EOF'
Alias /ks /ks
Alias /images /images
<Directory /ks>
    Options Indexes MultiViews
    AllowOverride All
    Require all granted
</Directory>
<Directory /images>
    Options Indexes MultiViews
    AllowOverride All
    Require all granted
</Directory>
EOF
a2enconf ks-server

# ---- dhcp ----
[ -f /etc/dhcp/dhcpd.conf ] && [ ! -f /etc/dhcp/dhcpd.conf.original ] && mv /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.original
cat > /etc/dhcp/dhcpd.conf <<EOF
allow bootp;
allow booting;
max-lease-time 1200;
default-lease-time 900;
log-facility local7;

option ip-forwarding    false;
option mask-supplier    false;

subnet $SUBNET netmask $NETMASK {
    option routers $ROUTER;
    option domain-name-servers 1.1.1.1;
    range $RANGE_START $RANGE_END;
    next-server $SERVER_IP;
    filename "bootx64.efi";
}
EOF
# bind dhcpd to the NIC that holds SERVER_IP
IFACE=$(ip -4 -o addr show | awk -v ip="$SERVER_IP" '$4 ~ "^"ip"/" {print $2}')
sed -i "s/^INTERFACESv4=.*/INTERFACESv4=\"$IFACE\"/" /etc/default/isc-dhcp-server

# ---- autoinstall (cloud-init nocloud) ----
cd /ks || exit 1
wget -q -O user-data "$RAW/user-data" || echo "WARN: user-data download failed, place it in /ks manually"
touch meta-data
echo "instance-id: ubuntu-server" > /ks/meta-data

# ---- ISOs + kernels ----
fetch_iso() { # url iso dir tag
  cd "/images/$3" || return 1
  [ -f "$2" ] || wget -c "$1" || return 1
  mkdir -p /mnt/iso
  mount -o loop,ro "$2" /mnt/iso || return 1
  cp -f /mnt/iso/casper/vmlinuz /mnt/iso/casper/initrd "/srv/tftp/$4/"
  umount /mnt/iso
}
fetch_iso "$URL26" "$ISO26" ubuntu26 ubuntu26 || echo "ERROR: 26.04 ISO/kernels failed"
fetch_iso "$URL22" "$ISO22" ubuntu22 ubuntu22 || echo "ERROR: 22.04 ISO/kernels failed"

# ---- signed shim + grub (secure boot ok) ----
W=$(mktemp -d); cd "$W" || exit 1
apt-get download shim-signed grub-efi-amd64-signed grub-common
for d in shim-signed grub-efi-amd64-signed grub-common; do dpkg-deb -x ${d}_*.deb "x-$d"; done
cp "$(find x-shim-signed -name 'shimx64.efi.signed' | head -n1)" /srv/tftp/bootx64.efi \
  || cp "$(find x-shim-signed -name 'shimx64.efi.signed.latest' | head -n1)" /srv/tftp/bootx64.efi
cp "$(find x-grub-efi-amd64-signed -name 'grubnetx64.efi.signed' | head -n1)" /srv/tftp/grubx64.efi
cp "$(find x-grub-common -name 'unicode.pf2' | head -n1)" /srv/tftp/unicode.pf2
cd / && rm -rf "$W"

# ---- grub.cfg ----
cat > /srv/tftp/grub/grub.cfg <<EOF
set default="0"
set timeout=-30

if loadfont unicode ; then
  set gfxmode=auto
  set locale_dir=\$prefix/locale
  set lang=en_US
fi
terminal_output gfxterm

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray
if background_color 44,0,30; then
  clear
fi

function gfxmode {
        set gfxpayload="\${1}"
        if [ "\${1}" = "keep" ]; then
                set vt_handoff=vt.handoff=7
        else
                set vt_handoff=
        fi
}

set linux_gfx_mode=keep
export linux_gfx_mode

menuentry 'Install Ubuntu 26.04.1 LTS' {
        gfxmode \$linux_gfx_mode
        linux /ubuntu26/vmlinuz ip=dhcp url=http://$SERVER_IP/images/ubuntu26/$ISO26 autoinstall ds=nocloud-net\;s=http://$SERVER_IP/ks/ cloud-config-url=/dev/null fsck.mode=skip
        initrd /ubuntu26/initrd
}
menuentry 'Install Ubuntu 22.04.5 LTS' {
        gfxmode \$linux_gfx_mode
        linux /ubuntu22/vmlinuz ip=dhcp url=http://$SERVER_IP/images/ubuntu22/$ISO22 autoinstall ds=nocloud-net\;s=http://$SERVER_IP/ks/ cloud-config-url=/dev/null fsck.mode=skip
        initrd /ubuntu22/initrd
}
EOF

# ---- services ----
systemctl enable --now tftpd-hpa apache2 isc-dhcp-server
systemctl restart apache2 tftpd-hpa isc-dhcp-server
systemctl --no-pager --lines=3 status tftpd-hpa apache2 isc-dhcp-server | grep -E "●|Active"
echo "Done. ISO: http://$SERVER_IP/images/  Autoinstall: http://$SERVER_IP/ks/"
