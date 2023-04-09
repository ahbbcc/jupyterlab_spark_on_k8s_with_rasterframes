# jupyterlab_spark_on_k8s_with_rasterframes

## Spark on K8S with JupyterLab 

Two Images:

+ Spark image - used for spinning up Spark executors.
+ JupyterLab image - used for JupyterLab and spark driver.

One YAML for running on K8S

### Build Dockers && Dockerfiles

#### PySpark image

```
wget https://www.apache.org/dyn/closer.lua/spark/spark-3.3.2/spark-3.3.2-bin-hadoop3.tgz
tar xvzf spark-3.3.2-bin-hadoop3.tgz
cd spark-3.3.2-bin-hadoop3
./bin/docker-image-tool.sh -u root -r ahbbcc -t 3.3.2-hadoop-3 -p kubernetes/dockerfiles/spark/bindings/python/Dockerfile build
```

#### Add Jars (For AWS S3)

spark.aws.Dockerfile :

```
FROM ahbbcc/spark-py:3.3.2-hadoop-3
RUN apt-get update && apt install -y wget && rm -rf /var/lib/apt/lists/* && rm -rf /var/cache/apt/*

RUN cd /opt/spark/jars \
&& wget "https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.12.440/aws-java-sdk-bundle-1.12.440.jar"
RUN cd /opt/spark/jars \
&& wget "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.4/hadoop-aws-3.3.4.jar"
```

```
docker build -f spark.aws.Dockerfile -t ahbbcc/spark:3.3.2-hadoop-3-aws .
```

#### JupyterLab Image

jupyterlab_spark.Dockerfile :

```
FROM ahbbcc/spark:3.3.2-hadoop-3-aws

RUN pip install jupyterlab ipynb jupyterlab-sparkmonitor pyspark==3.3.2 ipython

RUN ipython profile create && \ echo "c.InteractiveShellApp.extensions.append('sparkmonitor.kernelextension')" >> $(ipython profile locate default)/ipython_kernel_config.py

VOLUME /home/notebook/
CMD IPYTHONDIR=.ipython jupyter lab --port=8888 --ip=0.0.0.0 --no-browser --allow-root --NotebookApp.token='' --notebook-dir=/home/notebook/
```

```
docker build -f jupyterlab_spark.Dockerfile -t ahbbcc/jupyterlab-spark-3.3.2-hadoop-3:v1 .
```
