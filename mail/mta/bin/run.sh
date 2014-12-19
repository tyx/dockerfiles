#!/bin/bash
set -x

# update spamassassin rules
/usr/local/bin/update_spamassassin_rules.sh ${RULES_FILE}

# Set SpamAssassin options
cat > /etc/mail/spamassassin/local.cf <<EOF
rewrite_header Subject **SPAM** (_SCORE_)
report_safe 0
add_header ham HAM-Report _REPORT_
EOF

# for postgresql mapping
sed -i "s/PGSQL_HOST/${PGSQL_HOST}/" /etc/postfix/pgsql/* /etc/dovecot/dovecot-sql.conf
sed -i "s/PGSQL_USER/${PGSQL_USER}/" /etc/postfix/pgsql/* /etc/dovecot/dovecot-sql.conf
sed -i "s/PGSQL_PASSWORD/${PGSQL_PASSWORD}/" /etc/postfix/pgsql/* /etc/dovecot/dovecot-sql.conf
sed -i "s/PGSQL_DBNAME/${PGSQL_DBNAME}/" /etc/postfix/pgsql/* /etc/dovecot/dovecot-sql.conf

# (re-)build postfix queue
for queue in {active,bounce,corrupt,defer,deferred,flush,hold,incoming,private,saved,trace}; do
  install -d -o postfix -g postfix /var/spool/postfix/$queue
  chmod 700 /var/spool/postfix/$queue
done

# ensure proper permissions
chmod 730 /var/spool/postfix/maildrop
chmod 710 /var/spool/postfix/public
chown -R root /etc/postfix
chown -R vmail:vmail /srv/mail
chmod 755 /usr/local/bin/spam_filter.sh
chown root:root /usr/local/bin/spam_filter.sh

# setup grossd
mkdir -p /var/db/gross
chown -R gross: /var/run/gross /var/db/gross
/usr/sbin/grossd -u gross -C 2>/dev/null

# debugging
[ ! -z $DEBUG ] && \
  echo "auth_verbose = yes" | tee -a /etc/dovecot/dovecot.conf && \
  echo "auth_debug = yes" | tee -a /etc/dovecot/dovecot.conf

# mailgun support
[ ! -z $MAILGUN_SMTP_PASSWORD ] && [ ! -z $MAILGUN_SMTP_USERNAME ] && \
  postconf -e \
    smtp_sasl_password_maps="static:$MAILGUN_SMTP_USERNAME:$MAILGUN_SMTP_PASSWORD" \
    relayhost="[smtp.mailgun.org]:587"

# remove SSL config if no certificate or private key found
test -f /etc/ssl/certs/mail.crt   || rm -f /etc/dovecot/conf.d/10-ssl.conf
test -f /etc/ssl/private/mail.key || rm -f /etc/dovecot/conf.d/10-ssl.conf

# build system aliases
/usr/bin/newaliases

exec /usr/bin/supervisord -c /etc/supervisord.conf