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