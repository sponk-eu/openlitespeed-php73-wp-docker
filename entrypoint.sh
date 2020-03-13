#!/bin/bash

RUN_COMMAND="$@"

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


function set_config_head() 
{
    key="$1"
    value="$2"

    sed -ri "s/((['\"])$key\2\s*,\s*)(['\"]).*\3/\1$value/" "$WORDPRESSPATH/wp-config.php"
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
    set_config_head 'WP_DEBUG' "$WORDPRESS_DEBUG"
    set_config_head 'WP_CACHE' "$WORDPRESS_CACHE"

    # sed -e '5,10d;12d' "$WORDPRESSPATH/wp-config.php"

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

    NEWURL="'$PROTOCOL://' . \$_SERVER['HTTP_HOST'] . '/'"

    if ! grep -c -q "'WP_HOME'" ${WORDPRESSPATH}/wp-config.php ; then
       echo "define( 'WP_HOME', ${NEWURL} );" >> ${WORDPRESSPATH}/wp-config.php
    fi

    if ! grep -c -q "'WP_SITEURL'" ${WORDPRESSPATH}/wp-config.php ; then
        echo "define( 'WP_SITEURL', ${NEWURL} );" >> ${WORDPRESSPATH}/wp-config.php
    fi


    sed -i "s#\$table_prefix.*#\$table_prefix='${WORDPRESS_TABLE_PREFIX}';#g" ${WORDPRESSPATH}/wp-config.php
    sed -i "s#define( 'WP_HOME'.*#define( 'WP_HOME', ${NEWURL} );#g" ${WORDPRESSPATH}/wp-config.php
    sed -i "s#define( 'WP_SITEURL'.*#define( 'WP_SITEURL', ${NEWURL} );#g" ${WORDPRESSPATH}/wp-config.php

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

    echo "Generating selfsigned cert"

    openssl req -new -nodes -newkey rsa:4096 -days 1000 -x509 -subj "/emailAddress=${SSL_EMAIL}/C=${SSL_COUNTRY}/ST=${SSL_STATE}/L=${SSL_LOCALITY}/O=${SSL_ORG}/OU=${SSL_ORGUNIT}/CN=${SSL_HOSTNAME}" -keyout ${KEY} -out ${CERT}
    echo ""

    mv ${KEY}   $SERVER_ROOT/conf/$KEY
    mv ${CERT}  $SERVER_ROOT/conf/$CERT
    chmod 0600 $SERVER_ROOT/conf/$KEY
    chmod 0600 $SERVER_ROOT/conf/$CERT
    echo "Finished selfsigned"

}


function config_server_wp
{
    if [ -e "$SERVER_ROOT/conf/httpd_config.conf" ] ; then

        cat $SERVER_ROOT/conf/httpd_config.conf | grep "virtualhost wordpress" >/dev/null
        if [ $? != 0 ] ; then
            sed -i -e "s/debugLevel/debugLevel $LOG_DEBUG\n#debugLevel/" "$SERVER_ROOT/conf/httpd_config.conf"
            sed -i -e "s/adminEmails/adminEmails $SERVER_EMAIL\n#adminEmails/" "$SERVER_ROOT/conf/httpd_config.conf"
            sed -i -e "s/debugLevel/debugLevel $OLS_DEBUG_LEVEL\n#debugLevel/" "$SERVER_ROOT/conf/httpd_config.conf"
            sed -i -e "s/maxReqBodySize/maxReqBodySize $OLS_MAX_REQ_BODY_SIZE\n#maxReqBodySize/" "$SERVER_ROOT/conf/httpd_config.conf"
            sed -i -e "s/maxDynRespSize/maxDynRespSize $OLS_MAX_DYN_RESP_SIZE\n#maxDynRespSize/" "$SERVER_ROOT/conf/httpd_config.conf"
            sed -i -e "s/initTimeout/initTimeout $OLS_INIT_TIMEOUT\n#initTimeout/" "$SERVER_ROOT/conf/httpd_config.conf"
            sed -i -e "s/procHardLimit/procHardLimit $OLS_PROC_HARD_LIMIT\n#procHardLimit/" "$SERVER_ROOT/conf/httpd_config.conf"
            sed -i -e "s/procSoftLimit/procSoftLimit $OLS_PROC_SOFT_LIMIT\n#procSoftLimit/" "$SERVER_ROOT/conf/httpd_config.conf"

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
  map                     wordpress $DOMAIN_URL
}

listener wordpressssl {
  address                 *:$SSLWPPORT
  secure                  1
  map                     wordpress $DOMAIN_URL
  keyFile                 $SERVER_ROOT/conf/$KEY
  certFile                $SERVER_ROOT/conf/$CERT
  sslProtocol             30
  enableSpdy              12
  enableQuic              1

}


END
            mkdir -p $SERVER_ROOT/conf/vhosts/wordpress/
            cat > $VHOSTCONF <<END
      
docRoot                   \$VH_ROOT/

index  {
  useServer               0
  indexFiles              index.php
}

errorlog $SERVER_ROOT/logs/error.log {
    useServer 1
    logLevel DEBUG
    rollingSize 10M
}

accesslog $SERVER_ROOT/logs/access.log {
    logFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\"
    useServer 0
    rollingSize 10M
    keepDays 30
    compressArchive 0
}

context / {
  type                    NULL
  location                \$VH_ROOT
  allowBrowse             1
  indexFiles              index.php
  extraHeaders            $EXTRA_HEADER

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
sed -i "s/^max_input_time\s*=.*/max_input_time=$PHP_MAX_INPUT_TIME/" $PHPINFOPATH
sed -i "s/^memory_limit\s*=.*/memory_limit=$PHP_MEMORY_LIMIT/" $PHPINFOPATH

echo "Starting openlitespeed..."

/usr/local/lsws/bin/lswsctrl start

echo "Tailling. ..."

$RUN_COMMAND