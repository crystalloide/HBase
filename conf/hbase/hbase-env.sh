# ============================================================
#  hbase-env.sh – Variables d'environnement HBase
# ============================================================

export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HBASE_HOME=/opt/hbase
export HADOOP_HOME=/opt/hadoop
export HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop

# ZooKeeper géré séparément (ZK 3.7.0 externe)
export HBASE_MANAGES_ZK=false

# Logs
export HBASE_LOG_DIR=${HBASE_HOME}/logs
export HBASE_PID_DIR=/tmp

# Mémoire
export HBASE_HEAPSIZE=1G
export HBASE_MASTER_OPTS="-Xmx1g -XX:+UseG1GC"
export HBASE_REGIONSERVER_OPTS="-Xmx1g -XX:+UseG1GC"

# Compatibilité classpath avec Hadoop
export HBASE_DISABLE_HADOOP_CLASSPATH_LOOKUP=false
