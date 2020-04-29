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
printf "# STATE: Setting Postfix logging to stdout\n"
postconf -e "maillog_file = /dev/stdout"

# Configure Postfix
printf "# STATE: Configuring Postfix\n"
postconf -e "inet_interfaces = all"
postconf -e "mydestination ="
postconf -e "mynetworks = 0.0.0.0/0"
postconf -e "relayhost = [$RELAY_HOST]:$RELAY_PORT"

# Client settings (for sending to the relay)
postconf -e "smtp_tls_security_level = may"
postconf -e "smtp_tls_loglevel = 1"
postconf -e "smtp_sasl_auth_enable = yes"
postconf -e "smtp_sasl_security_options = noanonymous"
postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"

# Create password file
echo "[$RELAY_HOST]:$RELAY_PORT   $RELAY_USER:$RELAY_PASS" > /etc/postfix/sasl_passwd
chown root:root /etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd
rm -f /etc/postfix/sasl_passwd

# Rebuild the database for the mail aliases file
newaliases

# Send test email
# Test for variable and queue the message now, it will send when Postfix starts
if [[ -z "$TEST_EMAIL" ]]; then
  printf "# ERROR: TEST_EMAIL is undefined, continuing without a test email\n"
else
  printf "# STATE: Sending test email\n"
  echo -e "Subject: Postfix relay test \r\nTest of Postfix relay from Docker container startup\nSent on $(date)\n" | sendmail -F "[Alert from Postfix]" "$TEST_EMAIL"
fi

# Start Postfix
# Nothing else can log after this
printf "# STATE: Starting Postfix\n"
postfix start-fg
