#!/bin/bash
set -e

# The image entrypoint creates MYSQL_USER and grants it access to MYSQL_DATABASE.
# Grant the same app account access to the other service-owned schemas as well.
mysql --protocol=socket -uroot --password="$MYSQL_ROOT_PASSWORD" <<-EOSQL
    GRANT ALL PRIVILEGES ON slot_db.* TO '${MYSQL_USER}'@'%';
    GRANT ALL PRIVILEGES ON appointment_db.* TO '${MYSQL_USER}'@'%';
    GRANT ALL PRIVILEGES ON notification_db.* TO '${MYSQL_USER}'@'%';
EOSQL
