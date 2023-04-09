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

### YAML for running on K8S

```
kubectl create serviceaccount spark --namespace={ns}
kubectl create clusterrolebinding spark-role --clusterrole=edit --serviceaccount={ns}:spark --namespace={ns}
kubectl apply -f jupyter_spark/jupyter.yaml -n {ns}
```

### Params

```
from pyspark.sql import SparkSession
from pyspark import SparkConf
from IPython.display import display
import pandas as pd
config = {
    "spark.kubernetes.namespace": "{ns_name}",
    "spark.kubernetes.container.image": "ahbbcc/jupyterlab-spark-3.3.2-hadoop-3:v1",
    "spark.kubernetes.container.image.pullPolicy": "Always",
    "spark.executor.instances": "6",
    "spark.executor.memory": "12g",
    "spark.executor.cores": "8",
    "spark.driver.blockManager.port": "7777",
    "spark.driver.port": "2222",
    "spark.driver.host": "jupyter.{ns_name}",
    "spark.driver.bindAddress": "0.0.0.0",
    # s3 config
    "spark.hadoop.fs.s3a.endpoint": "xxx.xxx.xxx.xxx:9000",
    "spark.hadoop.fs.s3a.connection.ssl.enabled": "false",
    "spark.hadoop.fs.s3a.path.style.access": "true",
    "spark.hadoop.fs.s3a.impl": "org.apache.hadoop.fs.s3a.S3AFileSystem",
    "spark.hadoop.fs.s3a.access.key": "accessKey",
    "spark.hadoop.fs.s3a.secret.key": "secretKey",
    # pvc on k8s for share data between driver & excutors
    'spark.kubernetes.executor.volumes.persistentVolumeClaim.data.options.claimName': "notebook-data-jupyter-0",
    'spark.kubernetes.executor.volumes.persistentVolumeClaim.data.mount.path': "/opt/spark/work-dir",
    'spark.kubernetes.executor.volumes.persistentVolumeClaim.data.mount.readOnly': "false",
}

conf = SparkConf()
conf.setMaster("k8s://https://kubernetes.default.svc.cluster.local")
for key, value in config.items():
    conf.set(key, value)

spark = (SparkSession.builder.appName("RasterFrames").config(conf=conf).getOrCreate())
```

## Add Resterframes to Spark on K8S with JupyterLab

### 遇到的坑们

1. 镜像打包方式，需将 `Rasterframes` 相关包打进，且拷贝 `jars`
2. 如何读取 `S3` 中的 `tif` 等 `raster` 文件的巨坑

### 解决方案

在打包 `aws jars` 的步骤，一并拷贝最新版 `rasterframes` 的 `jar` 0.11.1

根据文档，`Rasterframes` 提供了两种读取 `s3` 中 `raster` 文件的方案：通过 `GDAL` 、通过 `HadoopGEOTiff(GeoTrellis)`，其中通过 `GeoTrellis` 读取 `s3a://` 开头文件有bug至今未close：[https://github.com/locationtech/rasterframes/issues/314](https://github.com/locationtech/rasterframes/issues/314)，因此只能选择通过 `GDAL`

此处存在两个问题：1. 在 `pyrasterframes` 中识别到 `GDAL` ，2. 将 `s3` 相关 `config` 传递给 `excutor` 节点的 `GDAL` 。

问题1：无论以何种方式安装 `GDAL` (如果版本大于3.1)，必须将 `libgdal.so` 文件通过软链复制为 `/usr/lib/libgdal.so.27` ，并在打包镜像的安装 `pyrasterframes` 步骤前，添加环境变量 `LD_LIBRARY_PATH` ，使其包含全部 `python` 包和 `/usr/lib/libgdal.so.27`

问题2：`GDAL` 可以通过环境变量读取 `config`，从3.3版本开始提供读取 `configure file` 的方式，因此对于通过 `k8s` 调度的自动创建 `excutor` 的 `spark`，需要在 `driver` 和 `excutor` 中安装 `GDAL 3.3` 或以上版本；打包镜像时设置软链：`ln -s /opt/spark/work-dir/gdalrc /root/.gdal/gdalrc`；在使用时，启动 `spark` 集群前，在 `jupyterlab` 工作目录中创建 `gdalrc` 文件，写入 `s3` 相关配置，由于 `pvc` 为共享挂载，因此各 `excutor` 在创建后也可获得此参数。

### Build Dockers && Dockerfiles

#### Spark Image

选择使用 `ubuntu 22.04` 作为基础镜像打包 `spark` 和 `pyspark` ，便于后续安装 `GDAL3.4.1`

```
./bin/docker-image-tool.sh -u root -r ahbbcc -t 3.3.2-java17 -f kubernetes/dockerfiles/spark/Spark.Dockerfile.java17 -p kubernetes/dockerfiles/spark/bindings/python/Dockerfile build
```

#### Add Jars (For AWS S3 && Rasterframes Jar)

spark.aws.Dockerfile :

```
FROM ahbbcc/spark-py:3.3.2-java17

RUN apt-get update && apt install -y wget && rm -rf /var/lib/apt/lists/* && rm -rf /var/cache/apt/*

RUN cd /opt/spark/jars \
&& wget "https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.12.440/aws-java-sdk-bundle-1.12.440.jar"
RUN cd /opt/spark/jars \
&& wget "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.4/hadoop-aws-3.3.4.jar"
COPY pyrasterframes-assembly-0.11.1.jar /opt/spark/jars/
```

```
docker build -f spark.aws.Dockerfile -t ahbbcc/spark:3.3.2-java17-aws .
```

### JupyterLab Image with GDAL3.4.1 && Rasterframes

jupyterlab.Dockerfile

```
FROM ahbbcc/spark-py:3.3.2-java17-aws

RUN apt-get update && apt install -y python3 python3-pip nano && pip3 install --upgrade pip setuptools
RUN apt install libpq-dev gdal-bin libgdal-dev -y

RUN apt-get update && apt install -y python3 python3-pip nano && pip3 install --upgrade pip setuptools
RUN pip install gdal==3.4.1

RUN ln -s /usr/lib/libgdal.so.30 /usr/lib/libgdal.so.27

RUN pip install jupyterlab ipynb jupyterlab-sparkmonitor pyspark==3.3.2 \
textblob numpy pandas shapely folium geopandas descartes pyarrow ipython rtree

RUN pip install rasterio[s3]

ENV LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/lib/python3/dist-packages/:/usr/local/lib/python3.10/:/usr/local/lib/:/usr/lib"

RUN pip install pyrasterframes==0.11.1

RUN ipython profile create && \
echo "c.InteractiveShellApp.extensions.append('sparkmonitor.kernelextension')" >> $(ipython profile locate default)/ipython_kernel_config.py

COPY gdalrc /opt/spark/work-dir
RUN mkdir /root/.gdal && ln -s /opt/spark/work-dir/gdalrc /root/.gdal/gdalrc

VOLUME /home/notebook/
CMD IPYTHONDIR=.ipython jupyter lab --port=8888 --ip=0.0.0.0 --no-browser --allow-root --NotebookApp.token='' --notebook-dir=/home/notebook/
```

```
docker build -f jupyterlab.Dockerfile -t ahbbcc/jupyterlab-spark-3.3.2-hadoop-3:v4-17-rf .
```

jupyterlab.worker.Dockerfile

```
FROM ahbbcc/spark-py:3.3.2-java17-aws

RUN apt-get update && apt install -y python3 python3-pip nano && pip3 install --upgrade pip setuptools
RUN apt install libpq-dev gdal-bin libgdal-dev -y

RUN apt-get update && apt install -y python3 python3-pip nano && pip3 install --upgrade pip setuptools
RUN pip install gdal==3.4.1

RUN ln -s /usr/lib/libgdal.so.30 /usr/lib/libgdal.so.27

RUN pip install jupyterlab ipynb jupyterlab-sparkmonitor pyspark==3.3.2 \
textblob numpy pandas shapely folium geopandas descartes pyarrow ipython rtree

RUN pip install rasterio[s3]

ENV LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/lib/python3/dist-packages/:/usr/local/lib/python3.10/:/usr/local/lib/:/usr/lib"

RUN pip install pyrasterframes==0.11.1

RUN ipython profile create && \
echo "c.InteractiveShellApp.extensions.append('sparkmonitor.kernelextension')" >> $(ipython profile locate default)/ipython_kernel_config.py

COPY gdalrc /opt/spark/work-dir
RUN mkdir /root/.gdal && ln -s /opt/spark/work-dir/gdalrc /root/.gdal/gdalrc
```

```
docker build -f jupyterlab.worker.Dockerfile -t ahbbcc/jupyterlab-spark-3.3.2-hadoop-3:v4-17-rf-worker .
```

### YAML for running on K8S

jupyter.yaml

```
......
    containers:
      - name: jupyter
        image: "10.170.154.105/cstcloud/jupyterlab-spark-3.3.2-hadoop-3:v4-17-rf"
......
```


## Params

gdalrc

```
[configoptions]
AWS_HTTPS=NO
GDAL_DISABLE_READDIR_ON_OPEN=YES
AWS_VIRTUAL_HOSTING=FALSE
AWS_S3_ENDPOINT=xxx.xxx.xxx.xxx:9000
AWS_SECRET_ACCESS_KEY=secretKey
AWS_ACCESS_KEY_ID=accessKey
```

```
from pyrasterframes import *
from pyrasterframes.rasterfunctions import *
from pyrasterframes.utils import create_rf_spark_session
from pyspark.sql import SparkSession
from pyspark import SparkConf
import pyrasterframes.rf_ipython
from IPython.display import display
import pandas as pd

config = {
    "spark.kubernetes.namespace": "{ns_name}",
    "spark.kubernetes.container.image": "ahbbcc/jupyterlab-spark-3.3.2-hadoop-3:v4-17-rf-worker",
    "spark.kubernetes.container.image.pullPolicy": "Always",
    "spark.executor.instances": "6",
    "spark.executor.memory": "12g",
    "spark.executor.cores": "8",
    "spark.driver.blockManager.port": "7777",
    "spark.driver.port": "2222",
    "spark.driver.host": "jupyter.{ns_name}",
    "spark.driver.bindAddress": "0.0.0.0",
    # s3 config
    "spark.hadoop.fs.s3a.endpoint": "xxx.xxx.xxx.xxx:9000",
    "spark.hadoop.fs.s3a.connection.ssl.enabled": "false",
    "spark.hadoop.fs.s3a.path.style.access": "true",
    "spark.hadoop.fs.s3a.impl": "org.apache.hadoop.fs.s3a.S3AFileSystem",
    "spark.hadoop.fs.s3a.access.key": "accessKey",
    "spark.hadoop.fs.s3a.secret.key": "secretKey",
    # pvc on k8s for share data between driver & excutors
    'spark.kubernetes.executor.volumes.persistentVolumeClaim.data.options.claimName': "notebook-data-jupyter-0",
    'spark.kubernetes.executor.volumes.persistentVolumeClaim.data.mount.path': "/opt/spark/work-dir",
    'spark.kubernetes.executor.volumes.persistentVolumeClaim.data.mount.readOnly': "false",
    # rasterframes config
    "spark.serializer": "org.apache.spark.serializer.KryoSerializer",
    "spark.kryo.registrator": "org.locationtech.rasterframes.util.RFKryoRegistrator",
    "spark.executorEnv.LD_LIBRARY_PATH": "/usr/lib/python3/dist-packages/:/usr/local/lib/python3.10/:/usr/local/lib/:/usr/lib",
    "spark.kubernetes.driverEnv.LD_LIBRARY_PATH": "/usr/lib/python3/dist-packages/:/usr/local/lib/python3.10/:/usr/local/lib/:/usr/lib"
}

conf = SparkConf()
conf.setMaster("k8s://https://kubernetes.default.svc.cluster.local")
for key, value in config.items():
    conf.set(key, value)

spark = (SparkSession.builder.appName("RasterFrames").config(conf=conf).withKryoSerialization().getOrCreate()).withRasterFrames()
```

验证GDAL

```
from pyrasterframes.utils import gdal_version
print(gdal_version())
```

读取TIF
```
test_ra = spark.read.raster('gdal://vsis3/daskdata/MOD13A3.A2017121.h32v09.006_1-km-monthly-ndvi_LST_TVDI.tiff')
test_ra.printSchema()
crs = test_ra.select(rf_crs("proj_raster").alias("value")).first()
print("CRS", crs.value.crsProj4)
```
