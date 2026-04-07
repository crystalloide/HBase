# ============================================================
#  Hadoop Lab – Image unique pour tous les nœuds
#  Java 11 (requis par HBase 2.6.x) | ZK 3.7.0 | Hadoop 3.1.0
#  HBase 2.6.4 | Zeppelin 0.10.1
# ============================================================
FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# ── Paquets système ──────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    openjdk-11-jdk \
    wget curl \
    openssh-server openssh-client \
    netcat net-tools iputils-ping \
    vim nano less \
    sudo procps \
    python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

# ── Java ─────────────────────────────────────────────────────
# NOTE : HBase 2.6.x exige Java ≥ 11.
#        On installe OpenJDK 11. 
# Pour Java 8 strict, utiliser HBase ≤ 2.4.x
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
ENV PATH=$PATH:$JAVA_HOME/bin

# ── Utilisateur hadoop ────────────────────────────────────────
RUN useradd -m -d /home/hadoop -s /bin/bash hadoop \
    && echo "hadoop ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    && echo "hadoop:hadoop" | chpasswd

# ── SSH sans mot de passe entre les nœuds ────────────────────
RUN mkdir -p /home/hadoop/.ssh \
    && ssh-keygen -t rsa -b 4096 -P '' -f /home/hadoop/.ssh/id_rsa \
    && cat /home/hadoop/.ssh/id_rsa.pub >> /home/hadoop/.ssh/authorized_keys \
    && chmod 700 /home/hadoop/.ssh \
    && chmod 600 /home/hadoop/.ssh/authorized_keys \
    && chown -R hadoop:hadoop /home/hadoop/.ssh \
    && mkdir -p /var/run/sshd
RUN echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config \
    && echo "UserKnownHostsFile /dev/null"  >> /etc/ssh/ssh_config

# ── ZooKeeper 3.7.0 ──────────────────────────────────────────
ENV ZK_VERSION=3.7.0
ENV ZOOKEEPER_HOME=/opt/zookeeper
RUN wget -q https://archive.apache.org/dist/zookeeper/zookeeper-${ZK_VERSION}/apache-zookeeper-${ZK_VERSION}-bin.tar.gz \
        -O /tmp/zookeeper.tar.gz \
    && tar -xzf /tmp/zookeeper.tar.gz -C /opt \
    && mv /opt/apache-zookeeper-${ZK_VERSION}-bin /opt/zookeeper \
    && rm /tmp/zookeeper.tar.gz \
    && mkdir -p /opt/zookeeper/data /opt/zookeeper/logs \
    && chown -R hadoop:hadoop /opt/zookeeper
ENV PATH=$PATH:$ZOOKEEPER_HOME/bin

# ── Hadoop 3.1.0 ─────────────────────────────────────────────
ENV HADOOP_VERSION=3.1.0
ENV HADOOP_HOME=/opt/hadoop
ENV HADOOP_MAPRED_HOME=$HADOOP_HOME
ENV HADOOP_COMMON_HOME=$HADOOP_HOME
ENV HADOOP_HDFS_HOME=$HADOOP_HOME
ENV HADOOP_YARN_HOME=$HADOOP_HOME
ENV HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
RUN wget -q https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz \
        -O /tmp/hadoop.tar.gz \
    && tar -xzf /tmp/hadoop.tar.gz -C /opt \
    && mv /opt/hadoop-${HADOOP_VERSION} /opt/hadoop \
    && rm /tmp/hadoop.tar.gz \
    && mkdir -p /opt/hadoop/data/{namenode,datanode,tmp,secondarynamenode} \
    && chown -R hadoop:hadoop /opt/hadoop
ENV PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin

# ── HBase 2.6.4 ──────────────────────────────────────────────
ENV HBASE_VERSION=2.6.4
ENV HBASE_HOME=/opt/hbase
RUN wget -q https://archive.apache.org/dist/hbase/${HBASE_VERSION}/hbase-${HBASE_VERSION}-bin.tar.gz \
        -O /tmp/hbase.tar.gz \
    && tar -xzf /tmp/hbase.tar.gz -C /opt \
    && mv /opt/hbase-${HBASE_VERSION} /opt/hbase \
    && rm /tmp/hbase.tar.gz \
    && chown -R hadoop:hadoop /opt/hbase
ENV PATH=$PATH:$HBASE_HOME/bin

# ── Zeppelin 0.10.1 ──────────────────────────────────────────
ENV ZEPPELIN_VERSION=0.10.1
ENV ZEPPELIN_HOME=/opt/zeppelin
RUN wget -q https://archive.apache.org/dist/zeppelin/zeppelin-${ZEPPELIN_VERSION}/zeppelin-${ZEPPELIN_VERSION}-bin-all.tgz \
        -O /tmp/zeppelin.tgz \
    && tar -xzf /tmp/zeppelin.tgz -C /opt \
    && mv /opt/zeppelin-${ZEPPELIN_VERSION}-bin-all /opt/zeppelin \
    && rm /tmp/zeppelin.tgz \
    && chown -R hadoop:hadoop /opt/zeppelin
ENV PATH=$PATH:$ZEPPELIN_HOME/bin

# ── Répertoires de scripts ────────────────────────────────────
RUN mkdir -p /opt/scripts && chown -R hadoop:hadoop /opt/scripts

# ── Copie des configurations ──────────────────────────────────
COPY --chown=hadoop:hadoop conf/hadoop/      $HADOOP_CONF_DIR/
COPY --chown=hadoop:hadoop conf/hbase/       $HBASE_HOME/conf/
COPY --chown=hadoop:hadoop conf/zookeeper/zoo.cfg $ZOOKEEPER_HOME/conf/zoo.cfg
COPY --chown=root:root      scripts/         /opt/scripts/
RUN chmod +x /opt/scripts/*.sh


# Ajout

RUN printf '%s\n' \
    '#!/bin/bash' \
    'export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64' \
    'export HADOOP_HOME=/opt/hadoop' \
    'export HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop' \
    'export HADOOP_MAPRED_HOME=/opt/hadoop' \
    'export HADOOP_COMMON_HOME=/opt/hadoop' \
    'export HADOOP_HDFS_HOME=/opt/hadoop' \
    'export HADOOP_YARN_HOME=/opt/hadoop' \
    'export HBASE_HOME=/opt/hbase' \
    'export ZOOKEEPER_HOME=/opt/zookeeper' \
    'export ZEPPELIN_HOME=/opt/zeppelin' \
    'export PATH=$JAVA_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$HBASE_HOME/bin:$ZOOKEEPER_HOME/bin:$ZEPPELIN_HOME/bin:$PATH' \
    > /etc/profile.d/hadoop-env.sh \
    && chmod +x /etc/profile.d/hadoop-env.sh \
    && echo 'source /etc/profile.d/hadoop-env.sh' >> /home/hadoop/.bashrc \
    && echo 'source /etc/profile.d/hadoop-env.sh' >> /home/hadoop/.bash_profile

# ── Ports exposés ─────────────────────────────────────────────
# ZK: 2181 (client), 2888 (follower), 3888 (election)
# HDFS: 9000 (NN RPC), 9870 (NN UI), 9868 (2NN UI)
# YARN: 8088 (RM UI), 8032 (RM RPC), 8042 (NM UI)
# MR History: 10020, 19888
# HBase: 16000 (Master RPC), 16010 (Master UI), 16020 (RS RPC), 16030 (RS UI)
# Zeppelin: 8080
EXPOSE 22 2181 2888 3888 9000 9870 9868 8088 8032 8042 10020 19888 16000 16010 16020 16030 8080

ENTRYPOINT ["/opt/scripts/entrypoint.sh"]
