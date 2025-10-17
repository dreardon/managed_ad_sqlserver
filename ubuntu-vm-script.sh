#! /bin/bash
apt-get update
apt-get install -y realmd sssd-ad sssd-tools adcli samba-common-bin

curl https://packages.microsoft.com/keys/microsoft.asc | tee /etc/apt/trusted.gpg.d/microsoft.asc
curl https://packages.microsoft.com/config/ubuntu/22.04/prod.list | tee /etc/apt/sources.list.d/mssql-release.list
apt-get update
printf 'Y' | ACCEPT_EULA=Y apt-get install mssql-tools18 unixodbc-dev
DEBIAN_FRONTEND=noninteractive apt-get install -y krb5-user