FROM ahbbcc/spark-py:3.3.2-java17

RUN apt-get update && apt install -y wget && rm -rf /var/lib/apt/lists/* && rm -rf /var/cache/apt/*

RUN cd /opt/spark/jars \
&& wget "https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.12.440/aws-java-sdk-bundle-1.12.440.jar"
RUN cd /opt/spark/jars \
&& wget "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.4/hadoop-aws-3.3.4.jar"

COPY pyrasterframes-assembly-0.11.1.jar /opt/spark/jars/