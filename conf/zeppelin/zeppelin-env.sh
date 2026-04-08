#!/bin/bash

# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements. See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License. You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# ═══════════════════════════════════════════════════════════════
# JAVA — OpenJDK 11
# ═══════════════════════════════════════════════════════════════
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64

# ═══════════════════════════════════════════════════════════════
# HADOOP — 3.3.6
# ═══════════════════════════════════════════════════════════════
export HADOOP_HOME=/opt/hadoop
export HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop

# export USE_HADOOP=true  # Inclure les JARs Hadoop dans le process Zeppelin server

# ═══════════════════════════════════════════════════════════════
# HBASE — 2.6.4
# ═══════════════════════════════════════════════════════════════
export HBASE_HOME=/opt/hbase
export HBASE_CONF_DIR=/opt/hbase/conf

# ═══════════════════════════════════════════════════════════════
# SPARK — désactivé (pas de Spark dans ce cluster)
# ═══════════════════════════════════════════════════════════════
# export SPARK_HOME=/opt/spark
# export SPARK_MASTER=spark://srvmaster01:7077
# export SPARK_SUBMIT_OPTIONS=""

# ═══════════════════════════════════════════════════════════════
# PYTHON — python3 système
# ═══════════════════════════════════════════════════════════════
export PYSPARK_PYTHON=/usr/bin/python3
export PYTHONPATH=/usr/bin/python3

# ═══════════════════════════════════════════════════════════════
# ZEPPELIN — port, mémoire, répertoires
# ═══════════════════════════════════════════════════════════════
export ZEPPELIN_ADDR=0.0.0.0
export ZEPPELIN_PORT=8082

export ZEPPELIN_LOG_DIR=/opt/zeppelin/logs
export ZEPPELIN_PID_DIR=/opt/zeppelin/run
export ZEPPELIN_WAR_TEMPDIR=/tmp/zeppelin-war
export ZEPPELIN_NOTEBOOK_DIR=/opt/zeppelin/notebook
export ZEPPELIN_INTERPRETER_LOCALREPO=/opt/zeppelin/local-repo

# Mémoire JVM Zeppelin server
export ZEPPELIN_MEM="-Xms512m -Xmx1024m -XX:MaxMetaspaceSize=256m"

# Mémoire JVM processus interpréteurs
export ZEPPELIN_INTP_MEM="-Xms256m -Xmx512m -XX:MaxMetaspaceSize=128m"

# ═══════════════════════════════════════════════════════════════
# PATH — toutes les commandes systèmes + Hadoop + HBase
# Doit inclure /bin:/usr/bin pour que hostname, mkdir, sleep, cat
# soient trouvés par zeppelin-daemon.sh
# ═══════════════════════════════════════════════════════════════
export PATH=/bin:/usr/bin:/usr/sbin:/sbin:$JAVA_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$HBASE_HOME/bin:$PATH

