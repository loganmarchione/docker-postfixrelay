#!/bin/sh -e

printf "#####\n"
printf "# Container starting up!\n"
printf "#####\n"

# Test variables for timezone
if [ -z "$TZ" ]; then
  printf "# ERROR: TZ is undefined, exiting!\n"
else
  printf "# STATE: Setting container timezone to $TZ\n"
  ln -sf /usr/share/zoneinfo/"$TZ" /etc/localtime
  echo "$TZ" > /etc/timezone
fi

# Test variables for relay
if [[ -z "$RELAY_HOST" || -z "$RELAY_PORT" ]]; then
  printf "# ERROR: Either RELAY_HOST or RELAY_PORT are undefined, exiting!\n"
  exit 1
fi

# Create directories
printf "# STATE: Changing permissions\n"
postfix set-permissions

# Set logging
if [[ "$LOG_DISABLE" == "true" ]]; then
  printf "# WARN: Setting Postfix logging to /dev/null\n"
else
  printf "# STATE: Setting Postfix logging to /dev/stdout\n"
  postconf -e "maillog_file = /dev/stdout"
fi

# Configure Postfix
printf "# STATE: Configuring Postfix\n"
postconf -e "inet_interfaces = all"
postconf -e "mydestination ="
postconf -e "mynetworks = ${MYNETWORKS:=0.0.0.0/0}"
postconf -e "relayhost = [$RELAY_HOST]:$RELAY_PORT"

# Set the "from" domain, needed for things like AWS SES
if [[ -z "$MYORIGIN" ]]; then
  printf "# WARN: MYORIGIN is undefined, continuing\n"
else
  printf "# STATE: MYORIGIN is defined as $MYORIGIN\n"
  postconf -e "myorigin = $MYORIGIN"
fi

# Set the "from" address, needed for some SMTP providers
# https://serverfault.com/questions/147921/forcing-the-from-address-when-postfix-relays-over-smtp
if [[ -z "$FROMADDRESS" ]]; then
  printf "# WARN: FROMADDRESS is undefined, continuing\n"
else
  printf "# STATE: FROMADDRESS is defined as $FROMADDRESS\n"
  postconf -e "smtp_header_checks = regexp:/etc/postfix/header_checks"
  echo "/^From:.*/ REPLACE From: $FROMADDRESS" | tee /etc/postfix/header_checks > /dev/null
  postconf -e "sender_canonical_maps = regexp:/etc/postfix/sender_canonical_maps"
  echo "/.+/ $FROMADDRESS" | tee /etc/postfix/sender_canonical_maps > /dev/null
fi

# Set the message_size_limit
if [[ -z "$MSG_SIZE" ]]; then
  printf "# WARN: MSG_SIZE is undefined, continuing\n"
else
  printf "# STATE: MSG_SIZE is defined as $MSG_SIZE\n"
  postconf -e "message_size_limit = $MSG_SIZE"
fi

# Client settings (for sending to the relay)
postconf -e "smtp_tls_security_level = encrypt"
postconf -e "smtp_tls_loglevel = 1"
postconf -e "smtp_tls_note_starttls_offer = yes"
postconf -e "smtp_sasl_auth_enable = yes"
postconf -e "smtp_sasl_security_options = noanonymous"
postconf -e "smtp_sasl_password_maps = lmdb:/etc/postfix/sasl_passwd"
postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"

# Create password file
# Alpine 3.13 dropped support for Berkeley DB, so using lmdb instead
# https://wiki.alpinelinux.org/wiki/Release_Notes_for_Alpine_3.13.0#Deprecation_of_Berkeley_DB_.28BDB.29
echo "[$RELAY_HOST]:$RELAY_PORT   $RELAY_USER:$RELAY_PASS" > /etc/postfix/sasl_passwd
chown root:root /etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd
postmap lmdb:/etc/postfix/sasl_passwd
rm -f /etc/postfix/sasl_passwd
chown root:root /etc/postfix/sasl_passwd.lmdb
chmod 600 /etc/postfix/sasl_passwd.lmdb

# Rebuild the database for the mail aliases file
newaliases

# Send test email
# Test for variable and queue the message now, it will send when Postfix starts
if [[ -z "$TEST_EMAIL" ]]; then
  printf "# WARN: TEST_EMAIL is undefined, continuing without a test email\n"
else
  printf "# STATE: Sending test email\n"
  echo -e "Subject: Postfix relay test \r\nTest of Postfix relay from Docker container startup\nSent on $(date)\n" | sendmail -F "[Alert from Postfix]" "$TEST_EMAIL"
fi

# Enable SUBMISSIONS/TLS
if [[ "$RELAY_SUBMISSIONS" == "true" ]]; then
  postconf -e "smtp_tls_wrappermode = yes"
fi

# Start Postfix
# Nothing else can log after this
printf "# STATE: Starting Postfix\n"
if [[ "$LOG_DISABLE" == "true" ]]; then
  postfix start-fg > /dev/null
else
  postfix start-fg
fi
