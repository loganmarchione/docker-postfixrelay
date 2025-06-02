#!/bin/bash -e

########################################
# functions
########################################

# shamelessly stolen from here
# https://github.com/docker-library/postgres/blob/cc254e85ed86e1f8c9052f9cbf0e3320324f0421/17/bookworm/docker-entrypoint.sh#L5-L25
#
# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
# this funciton sets $XYZ_DB_PASSWORD to first item that has a value:
#   $XYZ_DB_PASSWORD
#   Contents of the file referenced in the $XYZ_DB_PASSWORD_FILE variable
#   'example' (default value passed)
#
file_env() {
  # Main variable name (e.g., RELAY_PASS)
  local var="$1"
  # Alternative file-based variable (e.g., RELAY_PASS_FILE)
  local fileVar="${var}_FILE"
  # Optional default value if neither is set
  local def="${2:-}"
  # Set value as null first
  local val=""

  # If var is set, set value to var
  if [ "${!var:-}" ]; then
    val="${!var}"
    printf "# STATE: ${var} is defined by ${var}\n"
  # if fileVar set and the file exists, set value to contents of the file
  elif [ "${!fileVar:-}" ] && [ -f "${!fileVar}" ]; then
    val="$(< "${!fileVar}")"
    if [ "${val:-}" ]; then
      printf "# STATE: ${var} is defined by ${fileVar}\n"
    fi
  fi

  # If default passed and value not set, set value to default
  if [ "${def:-}" ] && [ ! "${val:-}" ]; then
    val="$def"
    printf "# STATE: ${var} is defined by default\n"
  fi

  # Report If value not set
  if [ ! "${val:-}" ]; then
    printf "# STATE: ${var} is not defined\n"
  fi

  # Clean up
  export "$var"="$val"
  unset "$fileVar"
}

########################################
# script starts here
########################################

printf "#####\n"
printf "# Container starting up!\n"
printf "#####\n"

# Check for Docker secrets before using
file_env 'RELAY_USER'
file_env 'RELAY_PASS'

# Test variables for timezone
if [ -z "$TZ" ]; then
  printf "# ERROR: TZ is undefined, exiting!\n"
else
  printf "# STATE: Setting container timezone to $TZ\n"
  ln -sf /usr/share/zoneinfo/"$TZ" /etc/localtime
  echo "$TZ" > /etc/timezone
fi

# Test variables for relay
printf "# STATE: RELAY_HOST:RELAY_PORT is defined as ${RELAY_HOST}:${RELAY_PORT}\n"
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
printf "# STATE: MYNETWORKS is defined as ${MYNETWORKS}\n"
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

# Enable SUBMISSIONS/TLS
printf "# STATE: RELAY_SUBMISSIONS is defined as ${RELAY_SUBMISSIONS:=false}\n"
if [[ "$RELAY_SUBMISSIONS" == "true" ]]; then
  postconf -e "smtp_tls_wrappermode = yes"
fi

# Client settings (for sending to the relay)
postconf -e "smtp_tls_security_level = encrypt"
postconf -e "smtp_tls_loglevel = 1"
postconf -e "smtp_tls_note_starttls_offer = yes"
postconf -e "smtp_sasl_security_options = noanonymous"
postconf -e "smtp_sasl_password_maps = lmdb:/etc/postfix/sasl_passwd"
postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"

# Create password file
# Alpine 3.13 dropped support for Berkeley DB, so using lmdb instead
# https://wiki.alpinelinux.org/wiki/Release_Notes_for_Alpine_3.13.0#Deprecation_of_Berkeley_DB_.28BDB.29
# if user and pass are set, echo them to a file and enable SASL auth
if [ -n "$RELAY_USER" ] && [ -n "$RELAY_PASS" ]; then
  echo "[$RELAY_HOST]:$RELAY_PORT   $RELAY_USER:$RELAY_PASS" > /etc/postfix/sasl_passwd
  postconf -e "smtp_sasl_auth_enable = yes"
else
  # if user and pass are not set, just echo the host/port (otherwise if they're not set, we echo an empty user/pass, with a colon : in between)
  # also set SASL auth to no (this is useful for IP-based auth instead of user/pass auth)
  echo "[$RELAY_HOST]:$RELAY_PORT" > /etc/postfix/sasl_passwd
  postconf -e "smtp_sasl_auth_enable = no"
fi
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
  # Use the value of TEST_EMAIL_SUBJECT if set, otherwise use "Postfix relay test"
  EMAIL_SUBJECT="${TEST_EMAIL_SUBJECT:-Postfix relay test}"
  echo -e "Subject: $EMAIL_SUBJECT \r\nTest of Postfix relay from Docker container startup\nSent on $(date)\n" | sendmail -F "[Alert from Postfix]" "$TEST_EMAIL"
fi

# Start Postfix
# Nothing else can log after this
printf "# STATE: Starting Postfix\n"
if [[ "$LOG_DISABLE" == "true" ]]; then
  postfix start-fg > /dev/null
else
  postfix start-fg
fi
