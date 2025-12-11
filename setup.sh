#!/bin/bash

if [[ "$1" != "amd64" && "$1" != "arm64" && "$1" != "armhf" ]]; then
    echo "Invalid arch"
    exit 1
fi

sudo apt-get update && sudo apt-get install -y coreutils

# Needed for chroot
export PATH=$PATH:/usr/sbin

arch=$1
ubuntuVersion="24.04.3"
baseUrl="https://cdimages.ubuntu.com/ubuntu-base/releases/${ubuntuVersion}/release"

ubuntuPublicKey=$(cat <<'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBE+tjmgBEAC7pKK78t89DW7mvMoSgiScLfPNF8/TSF380is0hFRL3dOmcXEf
NsX26jtv8bdvvtkElB1fPwOntmqSAsrLOuURVQ6GSxH7IDU5QFfaTIsudtLR5YTl
C3ZuOTOb1HWEK26fDRXuIWjhFDXJH3KLv+rSrq0+x7ZtH++CHq5XJWk7VUh/wWcG
xZefs7+1HTivymhjXCOwQvqblzZ5MAec9i4QIXxkqX1HY7ryxGVdjj9lApOnoU5E
cSYr08cm7xQEgrdDLAZFQxDYBLDuV6E6jKEfAfwZINSEe4Ocm82vtCF5K0HiwhFU
09ky2yogbMuTTi2f8ibN8SbbhZDJlDPd2ZkkpsKNfIALmOiPhHGvXGmtg6FdzRUO
SGirSm8tcakpS+d0/IElbD453sksxg6s3cTs7Q+PudaccyQ0BqatMnzmfxCVOotT
65kVnmz2P+4Q0gRSQ/Zi9Inz+OrzWxtn6/Tdw+FMUwvBccxW1r88k6uVLz23jW/8
jOuwnUp4JKmZta/U2UZKTyPyrvTYhp/zK332BEnxiRY4ZfQjA4Iwlw00l4pYBDLL
c6TFJtLbDv859UCisXa8MtWYWrlM3YfGFs9k1WemML8u79g2DK8g3VPkD94Q5anq
ufEGm74K/keOmss8cQoBX9VPFMpS1mFCT+2UdGP0UvMlADct0aFnAwtb9QARAQAB
tEFVYnVudHUgQ0QgSW1hZ2UgQXV0b21hdGljIFNpZ25pbmcgS2V5ICgyMDEyKSA8
Y2RpbWFnZUB1YnVudHUuY29tPokCNwQTAQoAIQUCT62OaAIbAwULCQgHAwUVCgkI
CwUWAgMBAAIeAQIXgAAKCRDZSqPw7+IQkkhAEACJjZZXuAabMrC49Z52HywVZipJ
goV5ufMi2LQYMkyGKVQQ/E74lUjccMmbQ4j00ihTYB+F/i29AxfavJnlSpWgmwjP
O4YY5jvooUiXQmVHX10oM1w3+Y9wScmeUY3IhTtwiFaBJr6TZ7RvOTg/pbQ0Gvzx
NlkSobuqFCZ023mcl2Y7OkY1PZgxiLafD6Rx2O/gclQPs4YfHo8bKRA4o10702nE
8YE+dixIgAQw67Txhq5idNxsWpudKq9J1fLgnEz7i9AJUOf12sg9X7ZvpXZ3QvMV
5iOvLA4DRLv9HIxyz70XqeakS+uzfKXuCMzhdUTIb/tNACNB37+reIqdPsyUF3tx
VyWaL1jMkRsv617yKAiYvPNwMDRvrbKiJ4Icnd4tPzmqz5HBFUyULns3JzJNjpgK
CvLGhVq+lVsdpMlpQxEG5/bhzJgB1jrIbkcOSfnQ1y0Gv9CItel+1q0BHMn0dPVW
aNfKYFGsz4igW+uj//C09/gtGMm78PQfjqEoR2j/Tam/tmucxSK331yfm5ag2CQY
GC3bswfII+4EanX9dN/RG3/2dsSyYruWpTIQG6Xa7+AZtYBDEXNYovgdJtXWyUtW
0X7R6vIjh1HYer3dR6ivJ+q/bWGY45zHeNBNU33hlnlxEENif3RZ/j/w3SjGrtSQ
K69maNR6onq492e+6w==
=snmR
-----END PGP PUBLIC KEY BLOCK-----
EOF
)

curl -LO "${baseUrl}/SHA256SUMS"
curl -LO "${baseUrl}/SHA256SUMS.gpg"
curl -LO "${baseUrl}/ubuntu-base-${ubuntuVersion}-base-${arch}.tar.gz"

echo "$ubuntuPublicKey" | gpg \
  --no-default-keyring \
  --keyring ./tempkey.gpg \
  --import

gpg --no-default-keyring --keyring ./tempkey.gpg \
    --verify SHA256SUMS.gpg SHA256SUMS

output=$(sha256sum --check SHA256SUMS 2>&1)

if [[ "$output" != *"ubuntu-base-${ubuntuVersion}-base-${arch}.tar.gz: OK"* ]]; then
    echo "Failed to verify ubuntu-base-${ubuntuVersion}-base-${arch}.tar.gz"
    exit 1
fi

rootfs="ubuntu-base-${ubuntuVersion}-base-${arch}"

mkdir -p "$rootfs"
tar -xzvf "ubuntu-base-${ubuntuVersion}-base-${arch}.tar.gz" -C "$rootfs"

mount -t proc /proc "$rootfs/proc"
mount --bind /sys "$rootfs/sys"
mount --bind /dev "$rootfs/dev"
mount --bind /dev/pts "$rootfs/dev/pts"

cp /etc/resolv.conf "$rootfs/etc/resolv.conf"

export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true

torrc='
SocksPort 9060
ControlPort 9061
'

chroot $rootfs /bin/bash -c "apt-get update && apt-get install -y openjdk-21-jre-headless --fix-missing && apt-get install -y tor && apt-get autoremove --purge -y && apt-get clean && apt-get autoclean && echo '$torrc' > /etc/tor/torrc && rm -rf /var/lib/apt/lists/*"

sudo umount "$rootfs/proc"
sudo umount "$rootfs/sys"
sudo umount "$rootfs/dev/pts"
sudo umount "$rootfs/dev"

case "$arch" in
    amd64)
        tarName="ubuntu-base-x86_64.tar.gz"
        ;;
    arm64)
        tarName="ubuntu-base-arm64-v8a.tar.gz"
        ;;
    armhf)
        tarName="ubuntu-base-armeabi-v7a.tar.gz"
        ;;
    *)
        exit 1
        ;;
esac

tar -C "$rootfs" -czf "$tarName" .
