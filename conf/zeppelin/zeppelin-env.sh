#!/bin/bash
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_HOME=/opt/hadoop
export HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop
export HBASE_HOME=/opt/hbase
export PATH=$JAVA_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$HBASE_HOME/bin:/usr/bin:/usr/sbin:/bin:/sbin:$PATH

# Mémoire Zeppelin server
export ZEPPELIN_MEM='-Xms512m -Xmx1024m'

# Interpréteur HDFS
export ZEPPELIN_INTP_MEM='-Xms256m -Xmx512m'
