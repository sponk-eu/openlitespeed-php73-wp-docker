#!/bin/bash

SERVER_ROOT=/usr/local/lsws
WORDPRESSPATH=$SERVER_ROOT/wordpress

CSR=example.csr
KEY=example.key
CERT=example.crt

PHPINFOPATH=/usr/local/lsws/lsphp73/etc/php/7.3/litespeed/php.ini

sed_escape_lhs() {
    echo "$@" | sed -e 's/[]\/$*.^|[]/\\&/g'
}

sed_escape_rhs() {
    echo "$@" | sed -e 's/[\/&]/\\&/g'
}

php_escape() {
    php -r 'var_export(('$2') $argv[1]);' -- "$1"
}

function set_config() 
{
    key="$1"
    value="$2"
    php_escaped_value="$(php -r 'var_export($argv[1]);' "$value")"
    sed_escaped_value="$(echo "$php_escaped_value" | sed 's/[\/&]/\\&/g')"

    sed -ri "s/((['\"])$key\2\s*,\s*)(['\"]).*\3/\1$sed_escaped_value/" "$WORDPRESSPATH/wp-config.php"

    # key="$1"
    # value="$2"
    # var_type="${3:-string}"
    # start="(['\"])$(sed_escape_lhs "$key")\2\s*,"
    # end="\);"
    # if [ "${key:0:1}" = '$' ]; then
    #   start="^(\s*)$(sed_escape_lhs "$key")\s*="
    #   end=";"
    # fi

    # echo "$key $value $start $end"
    # echo "sed s/($start\s*).*($end)$/\1$(sed_escape_rhs "$(php_escape "$value" "$var_type")")\3/"
    
    # sed -ri -e "s/($start\s*).*($end)$/\1$(sed_escape_rhs "$(php_escape "$value" "$var_type")")\3/" "$WORDPRESSPATH/wp-config.php"
}


function setup_wordpress
{
    if [ -e "$WORDPRESSPATH/wp-config.php" ] ; then
        echo "WordPress Config is existing."
    else
        if [ -e "$WORDPRESSPATH/wp-config-sample.php" ] ; then
            cp "$WORDPRESSPATH/wp-config-sample.php" "$WORDPRESSPATH/wp-config.php"
            # sed -e "s/database_name_here/$DB_NAME/" -e "s/username_here/$DB_USERNAME/" -e "s/password_here/$DB_PASSWORD/" "$WORDPRESSPATH/wp-config-sample.php" > "$WORDPRESSPATH/wp-config.php"
            if [ -e "$WORDPRESSPATH/wp-config.php" ] ; then
                chown  -R --reference="$WORDPRESSPATH/wp-config-sample.php"   "$WORDPRESSPATH/wp-config.php"
                echo "Finished setting up WordPress."
            else
                echo "WordPress setup failed. You may not have sufficient privileges to access $WORDPRESSPATH/wp-config.php."
            fi
        else
            echo "WordPress setup failed. File $WORDPRESSPATH/wp-config-sample.php does not exist."
        fi
    fi

    UNIQUES=(
        AUTH_KEY
        SECURE_AUTH_KEY
        LOGGED_IN_KEY
        NONCE_KEY
        AUTH_SALT
        SECURE_AUTH_SALT
        LOGGED_IN_SALT
        NONCE_SALT
    )

    for unique in "${UNIQUES[@]}"; do
        uniqVar="\$WORDPRESS_$unique"
        # file_env "$uniqVar"
        if [ "${!uniqVar}" ]; then
            set_config "$unique" "${!uniqVar}"
        else
            # if not specified, let's generate a random value
            # define( 'DB_NAME', 'database_name_here' );
			    	currentVal="$(sed -rn "s/define\(\s*['\"]$unique['\"]\s*,\s*['\"](.*)['\"]\s*\);.*$/\1/p" $WORDPRESSPATH/wp-config.php)"

            if [ "$currentVal" = "put your unique phrase here" ]; then
                set_config "$unique" "$(head -c1m /dev/urandom | sha1sum | cut -d' ' -f1)"
            fi
        fi
    done

    set_config 'DB_HOST' "$DB_HOST"
    set_config 'DB_USER' "$DB_USERNAME"
    set_config 'DB_PASSWORD' "$DB_PASSWORD"
    set_config 'DB_NAME' "$DB_NAME"
    set_config 'WORDPRESS_TABLE_PREFIX' "$WORDPRESS_TABLE_PREFIX"
    set_config 'WORDPRESS_DEBUG' "$WORDPRESS_DEBUG"
    
    sed -e '5,10d;12d' "$WORDPRESSPATH/wp-config.php"

    if [ ! -e .htaccess ]; then
        cat > "$WORDPRESSPATH/.htaccess" <<-'EOF'
            # BEGIN WordPress
            <IfModule mod_rewrite.c>
            RewriteEngine On
            RewriteBase /
            RewriteRule ^index\.php$ - [L]
            RewriteCond %{REQUEST_FILENAME} !-f
            RewriteCond %{REQUEST_FILENAME} !-d
            RewriteRule . /index.php [L]
            </IfModule>
            # END WordPress
EOF

        chown  -R --reference="$WORDPRESSPATH/wp-config-sample.php" "$WORDPRESSPATH/.htaccess"
    fi

    if ! grep -c -q "'WP_HOME'" ${WORDPRESSPATH}/wp-config.php ; then
       echo "define( 'WP_HOME', '${PROTOCOL}${SITE_URL}${SITE_PORT}' );" >> ${WORDPRESSPATH}/wp-config.php
    fi

    if ! grep -c -q "'WP_SITEURL'" ${WORDPRESSPATH}/wp-config.php ; then
        echo "define( 'WP_SITEURL', '${PROTOCOL}${SITE_URL}${SITE_PORT}' );" >> ${WORDPRESSPATH}/wp-config.php
    fi

   OLDURL=`grep "WP_HOME" ${WORDPRESSPATH}/wp-config.php | cut -d \' -f 4`
   if [ "$OLDURL" != "${PROTOCOL}${SITE_URL}${SITE_PORT}" ]; then
       echo "** [wordpress] Modifying wordpress to serve from ${OLDURL} to ${PROTOCOL}${SITE_URL}${SITE_PORT} - Please wait"
       sed -i "s#define( 'WP_HOME'.*#define( 'WP_HOME', '${PROTOCOL}${SITE_URL}${SITE_PORT}' );#g" ${WORDPRESSPATH}/wp-config.php
       sed -i "s#define( 'WP_SITEURL'.*#define( 'WP_SITEURL', '${PROTOCOL}${SITE_URL}${SITE_PORT}' );#g" ${WORDPRESSPATH}/wp-config.php
   fi 

}


function set_ols_password
{
    #setup password
    ENCRYPT_PASS=`"$SERVER_ROOT/admin/fcgi-bin/admin_php" -q "$SERVER_ROOT/admin/misc/htpasswd.php" $SERVER_PASSWORD`
    if [ $? = 0 ] ; then
        echo "$SERVER_LOGIN:$ENCRYPT_PASS" > "$SERVER_ROOT/admin/conf/htpasswd"
        if [ $? = 0 ] ; then
            echo "Finished setting OpenLiteSpeed WebAdmin password to $SERVER_PASSWORD."
            echo "Finished updating server configuration."

        else
            echo "OpenLiteSpeed WebAdmin password not changed."
        fi
    fi

}

function gen_selfsigned_cert
{


# Create the certificate signing request
    openssl req -new -passin pass:password -passout pass:password -out $CSR <<EOF
${SSL_COUNTRY}
${SSL_STATE}
${SSL_LOCALITY}
${SSL_ORG}
${SSL_ORGUNIT}
${SSL_HOSTNAME}
${SSL_EMAIL}
.
.
EOF
    echo ""

    [ -f ${CSR} ] && openssl req -text -noout -in ${CSR}
    echo ""

# Create the Key
    openssl rsa -in privkey.pem -passin pass:password -passout pass:password -out ${KEY}
# Create the Certificate
    openssl x509 -in ${CSR} -out ${CERT} -req -signkey ${KEY} -days 1000

    mv ${KEY}   $SERVER_ROOT/conf/$KEY
    mv ${CERT}  $SERVER_ROOT/conf/$CERT
    chmod 0600 $SERVER_ROOT/conf/$KEY
    chmod 0600 $SERVER_ROOT/conf/$CERT
}


function config_server_wp
{
    if [ -e "$SERVER_ROOT/conf/httpd_config.conf" ] ; then

        cat $SERVER_ROOT/conf/httpd_config.conf | grep "virtualhost wordpress" >/dev/null
        if [ $? != 0 ] ; then
            sed -i -e "s/adminEmails/adminEmails $SERVER_EMAIL\n#adminEmails/" "$SERVER_ROOT/conf/httpd_config.conf"

            VHOSTCONF=$SERVER_ROOT/conf/vhosts/wordpress/vhconf.conf

            cat >> $SERVER_ROOT/conf/httpd_config.conf <<END

virtualhost wordpress {
  vhRoot                  $WORDPRESSPATH
  configFile              $VHOSTCONF
  allowSymbolLink         1
  enableScript            1
  restrained              0
  setUIDMode              2
}

listener wordpress {
  address                 *:$WPPORT
  secure                  0
  map                     wordpress $SITE_URL
}

listener wordpressssl {
  address                 *:$SSLWPPORT
  secure                  1
  map                     wordpress $SITE_URL
  keyFile                 $SERVER_ROOT/conf/$KEY
  certFile                $SERVER_ROOT/conf/$CERT
}


END
            mkdir -p $SERVER_ROOT/conf/vhosts/wordpress/
            cat > $VHOSTCONF <<END
      
docRoot                   \$VH_ROOT/
index  {
  useServer               0
  indexFiles              index.php
}

context / {
  type                    NULL
  location                \$VH_ROOT
  allowBrowse             1
  indexFiles              index.php

  rewrite  {
    enable                1
    inherit               1
    rewriteFile           $WORDPRESSPATH/.htaccess

  }
}

END
            chown -R lsadm:lsadm $SERVER_ROOT/conf/
        fi


    else
        echoR "$SERVER_ROOT/conf/httpd_config.conf is missing. It appears that something went wrong during OpenLiteSpeed installation."
        ALLERRORS=1
    fi
}

function activate_cache
{
    cat > $WORDPRESSPATH/activate_cache.php <<END
<?php
include '$WORDPRESSPATH/wp-load.php';
include_once '$WORDPRESSPATH/wp-admin/includes/plugin.php';
include_once '$WORDPRESSPATH/wp-admin/includes/file.php';
define('WP_ADMIN', true);
activate_plugin('litespeed-cache/litespeed-cache.php', '', false, false);

END
    ls -all $SERVER_ROOT/fcgi-bin/
    $SERVER_ROOT/lsphp73/bin/php7.3 $WORDPRESSPATH/activate_cache.php
    rm $WORDPRESSPATH/activate_cache.php
}

setup_wordpress
set_ols_password
gen_selfsigned_cert
config_server_wp
activate_cache

sed -i "s/^upload_max_filesize\s*=.*/upload_max_filesize=$PHP_UPLOAD_MAX_FILESIZE/" $PHPINFOPATH
sed -i "s/^post_max_size\s*=.*/post_max_size=$PHP_POST_MAX_SIZE/" $PHPINFOPATH
sed -i "s/^max_execution_time\s*=.*/max_execution_time=$PHP_MAX_EXECUTION_TIME/" $PHPINFOPATH
sed -i "s/^memory_limit\s*=.*/memory_limit=$PHP_MEMORY_LIMIT/" $PHPINFOPATH

echo "Starting openlitespeed..."

/usr/local/lsws/bin/lswsctrl start

echo "Tailling. ..."
tail -f /dev/null