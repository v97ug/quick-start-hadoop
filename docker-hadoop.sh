#!/bin/bash

#####################################################
# 自動でdockerのコンテナをインストールし、hadoopを実行するプログラム
#################################################

##
# ${MASTER_NODE}は、マスターノードのコンテナ名
# ${SLAVE_NODE}は、スレーブノードのコンテナ名
# ${CLIENT}は、クライアントのコンテナ名
##

readonly MASTER_NODE="hadoop-00"
readonly SLAVE_NODE="hadoop-01"
readonly CLIENT="hadoop-cli"


###
# 1. マスターノードの構築
###

# hadoopのイメージのインストールと起動
sudo docker run -itd -p 8088:8088 -p 9000:9000 -p 19888:19888 -p 50070:50070 -p 50030:50030 -h ${MASTER_NODE} --name ${MASTER_NODE} sequenceiq/hadoop-docker /bin/bash --login
sudo docker exec ${MASTER_NODE} service sshd start

# マスターノードに、設定ファイルをコピー
# このとき、ローカルの設定ファイルのhadoop-00をMASTER_NODEに置換
readonly XML_FILES=("core-site.xml" "yarn-site.xml" "hdfs-site.xml" "mapred-site.xml" "slaves")
readonly XML_DIR="xml-setting"
for xml in ${XML_FILES[@]}; do
  sed -e "s/hadoop-00/${MASTER_NODE}/g" ${XML_DIR}/${xml} > converted-xml/${xml}
  sudo docker cp converted-xml/${xml} ${MASTER_NODE}:/usr/local/hadoop/etc/hadoop/
done

# マスタノードの HDFS データを削除
sudo docker exec ${MASTER_NODE} rm -rf /tmp/hadoop-root/dfs/data/current

# マスターノードのデーモンを起動
sudo docker exec ${MASTER_NODE} /usr/local/hadoop/sbin/yarn-daemon.sh start resourcemanager
sudo docker exec ${MASTER_NODE} /usr/local/hadoop/sbin/hadoop-daemon.sh start namenode
sudo docker exec ${MASTER_NODE} sh -c "USER=root /usr/local/hadoop/sbin/mr-jobhistory-daemon.sh start historyserver"

###
# 2. スレーブノードの構築
###

# スレーブノードのイメージを起動
sudo docker run -itd -p 50010:50010 -h ${SLAVE_NODE} --name ${SLAVE_NODE} sequenceiq/hadoop-docker /bin/bash --login
sudo docker exec ${SLAVE_NODE} service sshd start

# マスターノードの/etc/hosts にスレーブノードを追加
sudo docker exec ${MASTER_NODE} sh -c "echo $(sudo docker inspect --format {{.NetworkSettings.IPAddress}} ${SLAVE_NODE}) ${SLAVE_NODE} >> /etc/hosts"
# マスターノードの/usr/local/hadoop/etc/hadoop/slaves にスレーブノードを追加
sudo docker exec ${MASTER_NODE} sh -c "echo ${SLAVE_NODE} >> /usr/local/hadoop/etc/hadoop/slaves"

# スレーブノードの/etc/hostsをマスターノードと同期
sudo docker exec ${MASTER_NODE} scp /etc/hosts ${SLAVE_NODE}:/etc/hosts
# スレーブノードのHadoopの設定をマスターノードと同期
sudo docker exec ${MASTER_NODE} rsync -av /usr/local/hadoop/etc/hadoop/ ${SLAVE_NODE}:/usr/local/hadoop/etc/hadoop/

# スレーブノードのデーモンを起動
sudo docker exec ${SLAVE_NODE} /usr/local/hadoop/sbin/yarn-daemon.sh start nodemanager
sudo docker exec ${SLAVE_NODE} /usr/local/hadoop/sbin/hadoop-daemon.sh start datanode


###
# 3. クライアントの構築
###

# クライアント用のイメージを起動
sudo docker run -itd -h ${CLIENT} --name ${CLIENT} sequenceiq/hadoop-docker /bin/bash --login
# クライアントの/etc/hostsにマスターノードを追加する
sudo docker exec ${CLIENT} sh -c "echo $(sudo docker inspect --format {{.NetworkSettings.IPAddress}} ${MASTER_NODE}) ${MASTER_NODE} >> /etc/hosts"
# クライアントのHadoopの設定をマスターノードと同期
sudo docker exec ${CLIENT} rsync -av ${MASTER_NODE}:/usr/local/hadoop/etc/hadoop/ /usr/local/hadoop/etc/hadoop/


###
# 4. 実行
###

# セーフモードを解除(なぜこれをやるんだろう？)
sudo docker exec ${CLIENT} /usr/local/hadoop/bin/hadoop dfsadmin -safemode leave

# サンプルを実行
sudo docker exec ${CLIENT} /usr/local/hadoop/bin/hdfs dfs -rm -r output
sudo docker exec ${CLIENT} /usr/local/hadoop/bin/hadoop jar /usr/local/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-2.7.0.jar grep input output 'dfs[a-z.]+'

# 結果の表示
sudo docker exec ${CLIENT} /usr/local/hadoop/bin/hdfs dfs -cat output/*
