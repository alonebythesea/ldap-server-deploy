#!/bin/bash

## Install opanldap
sudo yum install -y openldap openldap-servers openldap-clients
sudo systemctl start slapd
sudo systemctl enable slapd
sudo systemctl status slapd

## Create root password wuth SSHA encrypt
USR="amukhitdzinau"
PASSWD="supasecurepa55wd"
PASSWORD=$(slappasswd -h {SSHA} -s ${PASSWD})

## Add root password schema
cat << EOF > /tmp/ldaprootpasswd.ldif
dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootPW
olcRootPW: ${PASSWORD}
EOF

sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/ldaprootpasswd.ldif


## Add and upload ssh schema
sudo cat > openssh-lpk.ldif <<EOF
dn: cn=openssh-lpk,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: openssh-lpk
olcAttributeTypes: ( 1.3.6.1.4.1.24552.500.1.1.1.13 NAME 'sshPublicKey'
    DESC 'MANDATORY: OpenSSH Public key'
    EQUALITY octetStringMatch
    SYNTAX 1.3.6.1.4.1.1466.115.121.1.40 )
olcObjectClasses: ( 1.3.6.1.4.1.24552.500.1.1.2.0 NAME 'ldapPublicKey' SUP top AUXILIARY
    DESC 'MANDATORY: OpenSSH LPK objectclass'
    MAY ( sshPublicKey $ uid )
    )
EOF

sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/openssh-lpk.ldif

## Update database config
sudo cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
sudo chown -R ldap:ldap /var/lib/ldap/DB_CONFIG
sudo systemctl restart slapd

## Add and upload exists schemas
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif

## Add and upload domain schema
cat << EOF > /tmp/ldapdomain.ldif
dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read by dn.base="cn=Manager,dc=devopslab,dc=com" read by * none

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=devopslab,dc=com

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=Manager,dc=devopslab,dc=com

dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcRootPW
olcRootPW: ${PASSWORD}

dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by dn="cn=Manager,dc=devopslab,dc=com" write by anonymous auth by self write by * none
olcAccess: {1}to dn.base="" by * read
olcAccess: {2}to * by dn="cn=Manager,dc=devopslab,dc=com" write by * read
EOF

sudo ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/ldapdomain.ldif

## Create and config base domain
cat << EOF > /tmp/baseldapdomain.ldif
dn: dc=devopslab,dc=com
objectClass: top
objectClass: dcObject
objectclass: organization
o: devopslab com
dc: devopslab

dn: cn=Manager,dc=devopslab,dc=com
objectClass: organizationalRole
cn: Manager
description: Directory Manager

dn: ou=People,dc=devopslab,dc=com
objectClass: organizationalUnit
ou: People

dn: ou=Group,dc=devopslab,dc=com
objectClass: organizationalUnit
ou: Group
EOF

sudo ldapadd -x -D "cn=Manager,dc=devopslab,dc=com" -w ${PASSWD} -f /tmp/baseldapdomain.ldif

## Create and config group
cat << EOF > /tmp/ldapgroup.ldif
dn: cn=Manager,ou=Group,dc=devopslab,dc=com
objectClass: top
objectClass: posixGroup
gidNumber: 1005
EOF

sudo ldapadd -x -w ${PASSWD} -D "cn=Manager,dc=devopslab,dc=com" -f /tmp/ldapgroup.ldif

## Create and config user
cat << EOF > /tmp/ldapuser.ldif
dn: uid=${USR},ou=People,dc=devopslab,dc=com
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: shadowAccount
cn: ${USR}
uid: ${USR}
uidNumber: 1005
gidNumber: 1005
homeDirectory: /home/${USR}
userPassword: ${PASSWORD}
loginShell: /bin/bash
gecos: ${USR}
shadowLastChange: 0
shadowMax: -1
shadowWarning: 0
EOF

sudo ldapadd -x -w ${PASSWD} -D "cn=Manager,dc=devopslab,dc=com" -f /tmp/ldapuser.ldif

## Install and config phpldapadmin
sudo yum --enablerepo=extras -y install epel-release
sudo yum install -y phpldapadmin
sudo sed -i "s/Require local/Require all granted/"  /etc/httpd/conf.d/phpldapadmin.conf

## Restart services
sudo systemctl restart slapd
sudo systemctl restart httpd
