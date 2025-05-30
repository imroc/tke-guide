# 使用软件源加速软件包安装

## 概述

在 TKE 环境中，在容器运行中或构建镜像时，如果需要安装一些软件包，通常会使用基础镜像内自带的包管理工具进行安装，而基础镜像内默认的软件源在国内使用往往会比较慢，造成安装过程非常慢。而腾讯云实际本身提供了各个 linux 发行版的软件源，我们将容器内的软件源替换为腾讯云的软件源即可实现加速。

## 确定 linux 发行版版本

一般容器镜像都是基于某个基础镜像构建而来，通常查看 Dockerfile 就可以直到基础镜像用的哪个 linux 发行版。

也可以直接进入运行中的容器，执行 `cat /etc/os-release` 来检查基础镜像的 linux 发行版版本。

## Ubuntu

先根据 Ubuntu 发新版替换软件源，然后执行 `apt update -y` 更新软件源，最后再使用 `apt install -y xxx` 来安装需要的软件包。

**下面是各发行版的软件源替换方法**

### Ubuntu 24

```bash
cat > /etc/apt/sources.list.d/ubuntu.sources <<'EOF'
Types: deb
#URIs: http://archive.ubuntu.com/ubuntu/
URIs: http://mirrors.tencentyun.com/ubuntu/
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

#Types: deb
#URIs: http://security.ubuntu.com/ubuntu/
#Suites: noble-security
#Components: main restricted universe multiverse
#Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
```

### Ubuntu 22

```bash
cat > /etc/apt/sources.list <<'EOF'
# See http://help.ubuntu.com/community/UpgradeNotes for how to upgrade to
# newer versions of the distribution.
deb http://mirrors.tencentyun.com/ubuntu jammy main restricted
# deb-src http://mirrors.tencentyun.com/ubuntu jammy main restricted
                                                                                                                                                                                                                   
## Major bug fix updates produced after the final release of the
## distribution.
deb http://mirrors.tencentyun.com/ubuntu jammy-updates main restricted
# deb-src http://mirrors.tencentyun.com/ubuntu jammy-updates main restricted
                                                                                                                                                                                                                   
## N.B. software from this repository is ENTIRELY UNSUPPORTED by the Ubuntu
## team. Also, please note that software in universe WILL NOT receive any
## review or updates from the Ubuntu security team.
deb http://mirrors.tencentyun.com/ubuntu jammy universe
# deb-src http://mirrors.tencentyun.com/ubuntu jammy universe
deb http://mirrors.tencentyun.com/ubuntu jammy-updates universe
# deb-src http://mirrors.tencentyun.com/ubuntu jammy-updates universe
                                                                                                                                                                                                                   
## N.B. software from this repository is ENTIRELY UNSUPPORTED by the Ubuntu
## team, and may not be under a free licence. Please satisfy yourself as to
## your rights to use the software. Also, please note that software in
## multiverse WILL NOT receive any review or updates from the Ubuntu
## security team.
deb http://mirrors.tencentyun.com/ubuntu jammy multiverse
# deb-src http://mirrors.tencentyun.com/ubuntu jammy multiverse
deb http://mirrors.tencentyun.com/ubuntu jammy-updates multiverse
# deb-src http://mirrors.tencentyun.com/ubuntu jammy-updates multiverse
                                                                                                                                                                                                                   
## N.B. software from this repository may not have been tested as
## extensively as that contained in the main release, although it includes
## newer versions of some applications which may provide useful features.
## Also, please note that software in backports WILL NOT receive any review
## or updates from the Ubuntu security team.
#deb http://mirrors.tencentyun.com/ubuntu jammy-backports main restricted universe multiverse
# deb-src http://mirrors.tencentyun.com/ubuntu jammy-backports main restricted universe multiverse
                                                                                                                                                                                                                   
deb http://mirrors.tencentyun.com/ubuntu jammy-security main restricted
# deb-src http://mirrors.tencentyun.com/ubuntu jammy-security main restricted
deb http://mirrors.tencentyun.com/ubuntu jammy-security universe
# deb-src http://mirrors.tencentyun.com/ubuntu jammy-security universe
deb http://mirrors.tencentyun.com/ubuntu jammy-security multiverse
# deb-src http://mirrors.tencentyun.com/ubuntu jammy-security multiverse
EOF
```

### Ubuntu 20

```bash
cat > /etc/apt/sources.list <<'EOF'
deb http://mirrors.tencentyun.com/ubuntu/ focal main restricted universe multiverse
deb http://mirrors.tencentyun.com/ubuntu/ focal-security main restricted universe multiverse
deb http://mirrors.tencentyun.com/ubuntu/ focal-updates main restricted universe multiverse
#deb http://mirrors.tencentyun.com/ubuntu/ focal-proposed main restricted universe multiverse
#deb http://mirrors.tencentyun.com/ubuntu/ focal-backports main restricted universe multiverse
deb-src http://mirrors.tencentyun.com/ubuntu/ focal main restricted universe multiverse
deb-src http://mirrors.tencentyun.com/ubuntu/ focal-security main restricted universe multiverse
deb-src http://mirrors.tencentyun.com/ubuntu/ focal-updates main restricted universe multiverse
#deb-src http://mirrors.tencentyun.com/ubuntu/ focal-proposed main restricted universe multiverse
#deb-src http://mirrors.tencentyun.com/ubuntu/ focal-backports main restricted universe multiverse
EOF
```

### Ubuntu 18

```bash
cat > /etc/apt/sources.list <<'EOF'
deb http://mirrors.tencentyun.com/ubuntu/ bionic main restricted universe multiverse
deb http://mirrors.tencentyun.com/ubuntu/ bionic-security main restricted universe multiverse
deb http://mirrors.tencentyun.com/ubuntu/ bionic-updates main restricted universe multiverse
#deb http://mirrors.tencentyun.com/ubuntu/ bionic-proposed main restricted universe multiverse
#deb http://mirrors.tencentyun.com/ubuntu/ bionic-backports main restricted universe multiverse
deb-src http://mirrors.tencentyun.com/ubuntu/ bionic main restricted universe multiverse
deb-src http://mirrors.tencentyun.com/ubuntu/ bionic-security main restricted universe multiverse
deb-src http://mirrors.tencentyun.com/ubuntu/ bionic-updates main restricted universe multiverse
#deb-src http://mirrors.tencentyun.com/ubuntu/ bionic-proposed main restricted universe multiverse
#deb-src http://mirrors.tencentyun.com/ubuntu/ bionic-backports main restricted universe multiverse
EOF
```

### Ubuntu 16

```bash
cat > /etc/apt/sources.list <<'EOF'
deb http://mirrors.tencentyun.com/ubuntu/ xenial main restricted universe multiverse
deb http://mirrors.tencentyun.com/ubuntu/ xenial-security main restricted universe multiverse
deb http://mirrors.tencentyun.com/ubuntu/ xenial-updates main restricted universe multiverse
deb-src http://mirrors.tencentyun.com/ubuntu/ xenial main restricted universe multiverse
deb-src http://mirrors.tencentyun.com/ubuntu/ xenial-security main restricted universe multiverse
deb-src http://mirrors.tencentyun.com/ubuntu/ xenial-updates main restricted universe multiverse
EOF
```

## Debian

先根据 Debian 发新版替换软件源，然后执行 `apt update -y` 更新软件源，最后再使用 `apt install -y xxx` 安装需要的软件包。

**下面是各发行版的软件源替换方法**

### Debian 12

```bash
rm -f /etc/apt/sources.list.d/*
cat > /etc/apt/sources.list <<'EOF'
deb http://mirrors.tencentyun.com/debian bookworm main contrib non-free non-free-firmware
deb http://mirrors.tencentyun.com/debian bookworm-updates main contrib non-free non-free-firmware
deb http://mirrors.tencentyun.com/debian-security/ bookworm-security main contrib non-free-firmware
EOF
```

### Debian 11

```bash
rm -f /etc/apt/sources.list.d/*
cat > /etc/apt/sources.list <<'EOF'
deb http://mirrors.tencentyun.com/debian bullseye main contrib non-free
#deb-src http://mirrors.tencentyun.com/debian bullseye main contrib non-free
deb http://mirrors.tencentyun.com/debian bullseye-updates main contrib non-free
#deb-src http://mirrors.tencentyun.com/debian bullseye-updates main contrib non-free
deb http://mirrors.tencentyun.com/debian-security bullseye-security main contrib non-free
#deb-src http://mirrors.tencentyun.com/debian-security bullseye-security main contrib non-free
#deb http://mirrors.tencentyun.com/debian bullseye-backports main contrib non-free
#deb-src http://mirrors.tencentyun.com/debian bullseye-backports main contrib non-free
#deb http://mirrors.tencentyun.com/debian bullseye-proposed-updates main contrib non-free
#deb-src http://mirrors.tencentyun.com/debian bullseye-proposed-updates main contrib non-free
EOF
```

### Debian 10
```bash
rm -f /etc/apt/sources.list.d/*
cat > /etc/apt/sources.list <<'EOF'
deb http://mirrors.tencentyun.com/debian buster main contrib non-free
# deb-src http://mirrors.tencentyun.com/debian buster main contrib non-free
deb http://mirrors.tencentyun.com/debian buster-updates main contrib non-free
# deb-src http://mirrors.tencentyun.com/debian buster-updates main contrib non-free
deb http://mirrors.tencentyun.com/debian-security buster/updates main contrib non-free

# deb-src http://mirrors.tencentyun.com/debian-security buster/updates main contrib non-free
# deb http://mirrors.tencentyun.com/debian buster-backports main contrib non-free
# deb-src http://mirrors.tencentyun.com/debian buster-backports main contrib non-free
# deb http://mirrors.tencentyun.com/debian buster-proposed-updates main contrib non-free
# deb-src http://mirrors.tencentyun.com/debian buster-proposed-updates main contrib non-free
EOF
```

### Debian 9

```bash
cat > /etc/apt/sources.list <<'EOF'
deb http://mirrors.tencentyun.com/debian stretch main contrib non-free
deb http://mirrors.tencentyun.com/debian stretch-updates main contrib non-free
deb http://mirrors.tencentyun.com/debian-security stretch/updates main
#deb http://mirrors.tencentyun.com/debian stretch-backports main contrib non-free
#deb http://mirrors.tencentyun.com/debian stretch-proposed-updates main contrib non-free

deb-src http://mirrors.tencentyun.com/debian stretch main contrib non-free
deb-src http://mirrors.tencentyun.com/debian stretch-updates main contrib non-free
deb-src http://mirrors.tencentyun.com/debian-security stretch/updates main
#deb-src http://mirrors.tencentyun.com/debian stretch-backports main contrib non-free
#deb-src http://mirrors.tencentyun.com/debian stretch-proposed-updates main contrib non-free
EOF
```

## CentOS

先删除 CentOS 镜像中所有自带软件源:
```bash
rm -f /etc/yum.repos.d/*
```

再根据 CentOS 发新版替换软件源，然后执行下面命令更新缓存:

```bash
yum clean all
yum makecache
```

最后再使用 `yum install -y xxx` 来安装需要的软件包。

**下面是各发行版的软件源替换方法**

### CentOS 8

```bash
cat > /etc/yum.repos.d/CentOS-Base.repo <<'EOF'
# Qcloud-Base.repo

[BaseOS]
name=Qcloud-$releasever - BaseOS
baseurl=http://mirrors.tencentyun.com/centos/$releasever/BaseOS/$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Qcloud-8
EOF

cat > /etc/yum.repos.d/CentOS-Epel.repo <<'EOF'
[epel]
name=EPEL for redhat/centos $releasever - $basearch
baseurl=http://mirrors.tencentyun.com/epel/$releasever/Everything/$basearch
failovermethod=priority
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-8
EOF

cat > /etc/yum.repos.d/CentOS-centosplus.repo <<'EOF'
# Qcloud-centosplus.repo

[centosplus]
name=Qcloud-$releasever - Plus
baseurl=http://mirrors.tencentyun.com/centos/$releasever/centosplus/$basearch/os/
gpgcheck=1
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Qcloud-8
EOF

cat > /etc/yum.repos.d/Qcloud-Extras.repo <<'EOF'
# Qcloud-Extras.repo

[extras]
name=Qcloud-$releasever - Extras
baseurl=http://mirrors.tencentyun.com/centos/$releasever/extras/$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Qcloud-8
EOF

cat > /etc/yum.repos.d/Qcloud-Devel.repo <<'EOF'
# Qcloud-Devel.repo

[Devel]
name=Qcloud-$releasever - Devel WARNING! FOR BUILDROOT USE ONLY!
baseurl=http://mirrors.tencentyun.com/$contentdir/$releasever/Devel/$basearch/os/
gpgcheck=1
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Qcloud-8
EOF

cat > /etc/yum.repos.d/Qcloud-AppStream.repo <<'EOF'
# Qcloud-AppStream.repo

[AppStream]
name=Qcloud-$releasever - AppStream
baseurl=http://mirrors.tencentyun.com/centos/$releasever/AppStream/$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Qcloud-8
EOF

cat > /etc/yum.repos.d/Qcloud-PowerTools.repo <<'EOF'
# Qcloud-PowerTools.repo

[PowerTools]
name=Qcloud-$releasever - PowerTools
baseurl=http://mirrors.tencentyun.com/centos/$releasever/PowerTools/$basearch/os/
gpgcheck=1
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Qcloud-8
EOF

cat > /etc/yum.repos.d/Qcloud-HA.repo <<'EOF'
# Qcloud-HA.repo

[HighAvailability]
name=Qcloud-$releasever - HA
baseurl=http://mirrors.tencentyun.com/$contentdir/$releasever/HighAvailability/$basearch/os/
gpgcheck=1
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Qcloud-8
EOF
```


### CenOS 7

```bash
cat > /etc/yum.repos.d/CentOS-Base.repo <<'EOF'
[extras]
gpgcheck=1
gpgkey=http://mirrors.tencentyun.com/centos/RPM-GPG-KEY-CentOS-7
enabled=1
baseurl=http://mirrors.tencentyun.com/centos/$releasever/extras/$basearch/
name=Qcloud centos extras - $basearch
[os]
gpgcheck=1
gpgkey=http://mirrors.tencentyun.com/centos/RPM-GPG-KEY-CentOS-7
enabled=1
baseurl=http://mirrors.tencentyun.com/centos/$releasever/os/$basearch/
name=Qcloud centos os - $basearch
[updates]
gpgcheck=1
gpgkey=http://mirrors.tencentyun.com/centos/RPM-GPG-KEY-CentOS-7
enabled=1
baseurl=http://mirrors.tencentyun.com/centos/$releasever/updates/$basearch/
name=Qcloud centos updates - $basearch
EOF

cat > /etc/yum.repos.d/CentOS-Epel.repo <<'EOF'
[epel]
name=EPEL for redhat/centos $releasever - $basearch
failovermethod=priority
gpgcheck=1
gpgkey=http://mirrors.tencentyun.com/epel/RPM-GPG-KEY-EPEL-7
enabled=1
baseurl=http://mirrors.tencentyun.com/epel/$releasever/$basearch/
EOF
```

### CentOS 6

```bash
cat > /etc/yum.repos.d/CentOS-Base.repo <<'EOF'
[extras]
gpgcheck=1
gpgkey=http://mirrors.tencentyun.com/centos/RPM-GPG-KEY-CentOS-6
enabled=1
baseurl=http://mirrors.tencentyun.com/centos/$releasever/extras/$basearch/
name=Qcloud centos extras - $basearch
[os]
gpgcheck=1
gpgkey=http://mirrors.tencentyun.com/centos/RPM-GPG-KEY-CentOS-6
enabled=1
baseurl=http://mirrors.tencentyun.com/centos/$releasever/os/$basearch/
name=Qcloud centos os - $basearch
[updates]
gpgcheck=1
gpgkey=http://mirrors.tencentyun.com/centos/RPM-GPG-KEY-CentOS-6
enabled=1
baseurl=http://mirrors.tencentyun.com/centos/$releasever/updates/$basearch/
name=Qcloud centos updates - $basearch
EOF

cat > /etc/yum.repos.d/CentOS-Epel.repo <<'EOF'
[epel]
name=epel for redhat/centos $releasever - $basearch
failovermethod=priority
gpgcheck=1
gpgkey=http://mirrors.tencentyun.com/epel/RPM-GPG-KEY-EPEL-6
enabled=1
baseurl=http://mirrors.tencentyun.com/epel/$releasever/$basearch/
EOF
```
