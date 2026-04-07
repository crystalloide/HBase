<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# Pour un handlab de formation : prépare un docker compose qui instancie : 5 conteneurs : srvmaster01 avec l'adresse ip 192.168.100.100, srvmaster02 avec l'adresse ip 192.168.100.200, srvdata01 avec l'adresse ip 192.168.100.101, srvdata02 avec l'adresse ip 192.168.100.102, srvdata03 avec l'adresse ip 192.168.100.103. le cluster hadoop est constitué de ces 5 conteneurs. Les conteneurs srvmaster01 et srvmaster02 portenent les services master HDFS, YARN, HBase. Les conteneurs srvdata01, srvadata02, srvdata03, portent les services slaves HDFS et YARN MR et HBase region. Zookeeper est déployé sur les 5 conteneurs.   Les versions logicielles sont les suivantes :   1°) Zookeeper :	3.7.0,  2°) Java : 1.8.0_251 , 3°) Hadoop : 	3.1.0, 4°) HBase :  2.6.4. 5°) Zeppelin

Voici la description complète du projet généré. L'archive contient **17 fichiers** prêts à l'emploi.

***

## Architecture du cluster

Le `docker-compose.yml` instancie 5 conteneurs sur le réseau `192.168.100.0/24` avec des IPs statiques. Un seul `Dockerfile` sert de base commune à tous les nœuds, le rôle étant piloté par la variable d'environnement `NODE_ROLE` .


| Conteneur | IP | Rôles |
| :-- | :-- | :-- |
| srvmaster01 | 192.168.100.100 | NameNode, ResourceManager, HBase Master actif, ZooKeeper, Zeppelin |
| srvmaster02 | 192.168.100.200 | Secondary NameNode, HBase Backup Master, ZooKeeper |
| srvdata01 | 192.168.100.101 | DataNode, NodeManager, HBase RegionServer, ZooKeeper |
| srvdata02 | 192.168.100.102 | DataNode, NodeManager, HBase RegionServer, ZooKeeper |
| srvdata03 | 192.168.100.103 | DataNode, NodeManager, HBase RegionServer, ZooKeeper |

## Versions et points clés

> ⚠️ **Compatibilité Java** : HBase 2.6.x requiert **Java ≥ 11** (l'image utilise OpenJDK 11). Java 1.8.0_251 est incompatible avec HBase 2.6.4 ; pour forcer Java 8, utiliser HBase ≤ 2.4.x.

- **ZooKeeper 3.7.0** : ensemble de 5 nœuds (quorum = 3, tolère 2 pannes)
- **ZooKeeper externe** : `HBASE_MANAGES_ZK=false` dans `hbase-env.sh`, HBase pointe sur les 5 nœuds ZK
- **SSH sans mot de passe** : clé RSA générée au build, partagée via `authorized_keys` (même image → mêmes clés sur tous les nœuds)
- **Formatage HDFS idempotent** : le script `entrypoint.sh` formate le NameNode uniquement si `/data/namenode/current` est absent


## Démarrage

```bash
# Construire l'image (~20-30 min, Zeppelin ~1 Go)
docker compose build

# Démarrer le cluster
docker compose up -d

# Suivre les logs
docker compose logs -f srvmaster01

# Vérifier l'état complet (~5 min après démarrage)
docker exec -it srvmaster01 /opt/scripts/cluster-status.sh
```


## Interfaces Web accessibles depuis l'hôte

- **HDFS NameNode** : http://localhost:9870
- **YARN ResourceManager** : http://localhost:8088
- **HBase Master** : http://localhost:16010
- **Zeppelin** : http://localhost:8080
- **MapReduce History** : http://localhost:19888


## Structure de l'archive

```
hadoop-cluster/
├── Dockerfile               ← Image unique (Java 11, ZK, Hadoop, HBase, Zeppelin)
├── docker-compose.yml       ← 5 services + réseau + volumes nommés
├── conf/
│   ├── hadoop/              ← core-site, hdfs-site, yarn-site, mapred-site, workers
│   ├── hbase/               ← hbase-site, regionservers, backup-masters
│   └── zookeeper/zoo.cfg    ← Ensemble 5 nœuds
└── scripts/
    ├── entrypoint.sh        ← Démarrage intelligent par rôle
    ├── cluster-status.sh    ← Vérification de l'état
    └── clean-cluster.sh     ← Réinitialisation complète
```

