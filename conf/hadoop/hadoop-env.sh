# ============================================================
#  hadoop-env.sh – Variables d'environnement Hadoop
# ============================================================

export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_HOME=/opt/hadoop
export HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
export HADOOP_LOG_DIR=${HADOOP_HOME}/logs
export HADOOP_PID_DIR=/tmp

# Mémoire des daemons (adapter selon la RAM disponible)
export HADOOP_HEAPSIZE_MAX=1g
export HADOOP_HEAPSIZE_MIN=256m

# Utilisateur pour les daemons HDFS et YARN (Hadoop 3.x obligatoire)
export HDFS_NAMENODE_USER=hadoop
export HDFS_DATANODE_USER=hadoop
export HDFS_SECONDARYNAMENODE_USER=hadoop
export YARN_RESOURCEMANAGER_USER=hadoop
export YARN_NODEMANAGER_USER=hadoop
export MAPRED_HISTORYSERVER_USER=hadoop

# Options JVM pour les daemons
export HDFS_NAMENODE_OPTS="-XX:+UseParallelGC -Xmx1g"
export HDFS_DATANODE_OPTS="-XX:+UseParallelGC -Xmx512m"
export HDFS_SECONDARYNAMENODE_OPTS="-XX:+UseParallelGC -Xmx512m"
export YARN_RESOURCEMANAGER_OPTS="-Xmx1g"
export YARN_NODEMANAGER_OPTS="-Xmx512m"
