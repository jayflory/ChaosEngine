#!/bin/bash
#
# This script will create the required:
#
# 1. Self signed root certificate for a Certificate Authority.
# 2. Certificates for each Etcd node listed in EtcdNodes.txt
#

# Script Variables
CERT_VALID_DAYS=3650
CA_PASSWD="test123"
COUNTRY="US"
DOMAIN="jayflory.net"

# Make sure we are in the script directory.]
# - This will not work on symlinks
SCRIPT_DIR=$(dirname $0)
cd $SCRIPT_DIR

# First get a standard answer file.
# The below config file needs to be modified to work.
#if [ ! -f "$SCRIPT_DIR/openssl.conf" ]; then
#  wget https://raw.githubusercontent.com/kelseyhightower/etcd-production-setup/master/openssl.cnf
#fi

# Create an empty index file
if [ ! -f "$SCRIPT_DIR/files/index.txt" ]; then
  touch "$SCRIPT_DIR/files/index.txt"
fi

# Create a serial file
if [ ! -f "$SCRIPT_DIR/files/serial" ]; then
  echo 00 > "$SCRIPT_DIR/files/serial"
fi

# Build string for subject
SUBJ="/C=${COUNTRY}/CN=${DOMAIN}/O=etcd-ca"

#
# Next build the CA.
#
if [ ! -f "$SCRIPT_DIR/files/ca.crt" ]; then
  echo "Creating CA Certificate"
  openssl req -nodes -config openssl.cnf -new -x509 -days $CERT_VALID_DAYS \
    -subj $SUBJ \
    -extensions v3_ca -keyout $SCRIPT_DIR/files/ca.key \
    -out $SCRIPT_DIR/files/ca.crt 
fi

# Build the cluster certificates
while read -r -u4 line; do
  if [ ! -f "$SCRIPT_DIR/files/${line}.crt" ]; then

    echo "Creating certificate for ${line}."

    IP=$(egrep $line $SCRIPT_DIR/files/hosts | awk '{print $1}')
    export SAN="IP:127.0.0.1, IP:${IP}"

    # Create Subject line
    SUBJ="/C=${COUNTRY}/CN=${line}.${DOMAIN}/O=etcd-ca"

    # Create a certificate request
    openssl req -nodes -config $SCRIPT_DIR/openssl.cnf -new \
      -subj $SUBJ \
      -keyout $SCRIPT_DIR/files/${line}.key -out $SCRIPT_DIR/files/${line}.csr

    # Create the certificate
    openssl ca -batch -config openssl.cnf -extensions etcd_server \
      -keyfile $SCRIPT_DIR/files/ca.key -cert $SCRIPT_DIR/files/ca.crt \
      -out $SCRIPT_DIR/files/${line}.crt \
      -infiles $SCRIPT_DIR/files/${line}.csr 

    # Remove the csr
    rm $SCRIPT_DIR/files/${line}.csr

  fi
done 4< $SCRIPT_DIR/EtcdNodes.txt

# Create a client cert
unset SAN
if [ ! -f "$SCRIPT_DIR/files/etcd-client.crt" ]; then

  echo "Creating a client certificate"

  # Create a signing request.
  SUBJ="/C=${COUNTRY}/CN=client.${DOMAIN}/O=etcd-ca"
  openssl req -config openssl.cnf -new -nodes -keyout $SCRIPT_DIR/files/etcd-client.key \
    -subj $SUBJ -out $SCRIPT_DIR/files/etcd-client.csr

  # Sign the certificate
  openssl ca -batch -config openssl.cnf -extensions etcd_client \
    -keyfile $SCRIPT_DIR/files/ca.key \
    -cert files/ca.crt -out $SCRIPT_DIR/files/etcd-client.crt \
    -infiles $SCRIPT_DIR/files/etcd-client.csr
  rm files/etcd-client.csr 2>&1

fi

rm $SCRIPT_DIR/files/*.pem
