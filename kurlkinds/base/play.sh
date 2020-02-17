FILE="copy"

KURL_FLAG=""
#KURL_FLAG="mike"

sed -i "s/{{ HAClusterValue }}/$KURL_FLAG/"  $FILE

#copy file has field:
# HACluster: {{ HAClusterValue }}
