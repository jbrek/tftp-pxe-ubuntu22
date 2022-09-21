 apt install apache2 -y
 apt install tftpd-hpa -y
 apt install isc-dhcp-server -y
 mkdir /images/
 mkdir /images/ubuntu22
 mkdir /ks/
 mkdir /srv/
 mkdir /srv/tftp/
 mkdir /srv/tftp/grub
 #create apache config file
 touch /etc/apache2/sites-available/ks-server.conf
 #copy file contents
sudo sh -c "echo '<VirtualHost 192.168.1.106:80> '>> /etc/apache2/sites-available/ks-server.conf"
sudo sh -c "echo '  DocumentRoot / '>> /etc/apache2/sites-available/ks-server.conf"
sudo sh -c "echo '    <Directory /ks> '>> /etc/apache2/sites-available/ks-server.conf"
sudo sh -c "echo '     Options Indexes MultiViews '>> /etc/apache2/sites-available/ks-server.conf"
sudo sh -c "echo '      AllowOverride All '>> /etc/apache2/sites-available/ks-server.conf"
sudo sh -c "echo '      Require all granted'>> /etc/apache2/sites-available/ks-server.conf"
sudo sh -c "echo '    </Directory> '>> /etc/apache2/sites-available/ks-server.conf"
sudo sh -c "echo '    <Directory /images> '>> /etc/apache2/sites-available/ks-server.conf"
sudo sh -c "echo '       Options Indexes MultiViews '>> /etc/apache2/sites-available/ks-server.conf"
sudo sh -c "echo '       AllowOverride All '>> /etc/apache2/sites-available/ks-server.conf"
sudo sh -c "echo '       Require all granted'>> /etc/apache2/sites-available/ks-server.conf"
sudo sh -c "echo '       </Directory> '>> /etc/apache2/sites-available/ks-server.conf"
sudo sh -c "echo '</VirtualHost> '>> /etc/apache2/sites-available/ks-server.conf"
#dhcp cfg
cd /etc/dhcp/
mv dhcpd.conf dhcpd.conf.orginal
wget https://raw.githubusercontent.com/jbrek/tftp-pxe-ubuntu22/main/dhcpd.conf
#load site
sudo a2ensite ks-server.conf
#set service to auto start
systemctl enable tftpd-hpa --now
systemctl enable apache2 --now
systemctl enable isc-dhcp-server.service --now
systemctl restart apache2
systemctl restart tftpd-hpa
systemctl restart isc-dhcp-server.service --now
cd /ks
wget https://raw.githubusercontent.com/jbrek/tftp-pxe-ubuntu22/main/user-data
touch meta-data
sudo sh -c "echo 'instance-id: ubuntu22-server'>> /ks/meta-data"
cd /images/ubuntu22
wget https://www.releases.ubuntu.com/22.04/ubuntu-22.04.1-live-server-amd64.iso
mkdir mnt
mount ubuntu-22.04.1-live-server-amd64.iso mnt
cp -rvf mnt/casper/{initrd,vmlinuz} /srv/tftp/
umount mnt
cd /tmp
apt-get download shim.signed -y
apt download grub-efi-amd64-signed
apt download grub-common
dpkg-deb --fsys-tarfile /tmp/shim-signed*deb | tar x ./usr/lib/shim/shimx64.efi.signed -O > /srv/tftp/bootx64.efi
dpkg-deb --fsys-tarfile /tmp/grub-efi-amd64-signed*deb | tar x ./usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed -O > /srv/tftp/grubx64.efi
dpkg-deb --fsys-tarfile grub-common*deb | tar x ./usr/share/grub/unicode.pf2 -O > /srv/tftp/unicode.pf2
cd /srv/tftp/grub
wget https://raw.githubusercontent.com/jbrek/tftp-pxe-ubuntu22/main/grub.cfg
