# "experimental" ;  only for testing!
# multi-stage dockerfile;  minimal docker version >= 17.05
FROM postgres:14-bullseye as builder

LABEL maintainer="PostGIS Project - https://postgis.net"

WORKDIR /

# apt-get install
RUN set -ex \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
           autoconf \
       curl \
      # build dependency
      autoconf \
      automake \
      autotools-dev \
      bison \
      build-essential \
      ca-certificates \
      cmake \
      g++ \
      git \
      libboost-all-dev \
      libboost-atomic1.74.0 \
      libboost-chrono1.74.0 \
      libboost-date-time1.74.0 \
      libboost-filesystem1.74.0 \
      libboost-program-options1.74.0 \
      libboost-serialization1.74.0 \
      libboost-system1.74.0 \
      libboost-test1.74.0 \
      libboost-thread1.74.0 \
      libboost-timer1.74.0 \
      libcgal-dev \
      libcurl3-gnutls \
      libcurl4-gnutls-dev \
      libexpat1 \
      libgmp-dev \
      libgmp10 \
      libgmpxx4ldbl \
      libjson-c-dev \
      libjson-c5 \
      libmpfr-dev \
      libmpfr6 \
      libpcre3 \
      libpcre3-dev \
      libprotobuf-c-dev \
      libprotobuf-c1 \
      libsqlite3-dev \
      libtiff-dev \
      libtiff5 \
      libtool \
      libxml2 \
      libxml2-dev \
      make \
      osm2pgsql \
      pkg-config \
      postgresql-server-dev-$PG_MAJOR \
      protobuf-c-compiler \
      sqlite3 \
      xsltproc 



# sfcgal
ENV SFCGAL_VERSION master
#current:
#ENV SFCGAL_GIT_HASH 3c252a1b129203055b22b5d964e7fe39b136f014
#reverted for the last working version
ENV SFCGAL_GIT_HASH e1f5cd801f8796ddb442c06c11ce8c30a7eed2c5

RUN set -ex \
    && mkdir -p /usr/src \
    && cd /usr/src \
    && git clone https://gitlab.com/Oslandia/SFCGAL.git \
    && cd SFCGAL \
    && git checkout ${SFCGAL_GIT_HASH} \
    && mkdir cmake-build \
    && cd cmake-build \
    && cmake .. \
    && make -j$(nproc) \
    && make install \
    && cd / 

# proj
ENV PROJ_VERSION master
ENV PROJ_GIT_HASH 7dc8a59217c41c8cfefe7f9d97cb7dae4a8b8fbd

RUN set -ex \
    && cd /usr/src \
    && git clone https://github.com/OSGeo/PROJ.git \
    && cd PROJ \
    && git checkout ${PROJ_GIT_HASH} \
    && ./autogen.sh \
    && ./configure --disable-static \
    && make -j$(nproc) \
    && make install \
    && cd / 


# geos
ENV GEOS_VERSION master
ENV GEOS_GIT_HASH 17eaeb92920fca6183a916914ec3af11b84ae828

RUN set -ex \
    && cd /usr/src \
    && git clone https://github.com/libgeos/geos.git \
    && cd geos \
    && git checkout ${GEOS_GIT_HASH} \
    && mkdir cmake-build \
    && cd cmake-build \
    && cmake -DCMAKE_BUILD_TYPE=Release .. \
    && make -j$(nproc) \
    && make install \
    && cd / 


# gdal
ENV GDAL_VERSION master
ENV GDAL_GIT_HASH 5b5042a388f0be78cdf1469eb6bb1c396aa0ec7f

RUN set -ex \
    && cd /usr/src \
    && git clone https://github.com/OSGeo/gdal.git \
    && cd gdal \
    && git checkout ${GDAL_GIT_HASH} \
    \
    # gdal project directory structure - has been changed !
    && if [ -d "gdal" ] ; then \
        echo "Directory 'gdal' dir exists -> older version!" ; \
        cd gdal ; \
    else \
        echo "Directory 'gdal' does not exists! Newer version! " ; \
    fi \
    \
    && ./autogen.sh \
    && ./configure --disable-static \
    && make -j$(nproc) \
    && make install \
    && cd / 


# Minimal command line test.
RUN set -ex \
    && ldconfig \
    && cs2cs \
    && gdalinfo --version \
    && geos-config --version \
    && ogr2ogr --version \
    && proj \
    && sfcgal-config --version \
    && pcre-config  --version

#FROM postgres:14-bullseye



COPY --from=builder /usr/local /usr/local



# Minimal command line test.
RUN set -ex \
    && ldconfig \
    && cs2cs \
    && gdalinfo --version \
    && geos-config --version \
    && ogr2ogr --version \
    && proj \
    && sfcgal-config --version

# install postgis
ENV POSTGIS_VERSION master
ENV POSTGIS_GIT_HASH 27f44ecf69ac576c95ff649b2fb23aa3e1cce5c1

 # postgis
 RUN    cd /usr/src/ \
    && git clone https://github.com/postgis/postgis.git \
    && cd postgis \
    && git checkout ${POSTGIS_GIT_HASH} \
    && ./autogen.sh \
# configure options taken from:
# https://anonscm.debian.org/cgit/pkg-grass/postgis.git/tree/debian/rules?h=jessie
    && ./configure \
#       --with-gui \
        --with-pcredir="$(pcre-config --prefix)" \
    && make -j$(nproc) \
    && make install \
# regress check
    && mkdir /tempdb \
    && chown -R postgres:postgres /tempdb \
    && su postgres -c 'pg_ctl -D /tempdb init' \
    && su postgres -c 'pg_ctl -D /tempdb start' \
    && ldconfig \
    && cd regress \
    && make -j$(nproc) check RUNTESTFLAGS=--extension PGUSER=postgres \
    \
    && su postgres -c 'psql    -c "CREATE EXTENSION IF NOT EXISTS postgis;"' \
    && su postgres -c 'psql -t -c "SELECT version();"' >> /_pgis_full_version.txt \
    && su postgres -c 'psql -t -c "SELECT PostGIS_Full_Version();"' >> /_pgis_full_version.txt \
    \
    && su postgres -c 'pg_ctl -D /tempdb --mode=immediate stop' \
    && rm -rf /tempdb \
    && rm -rf /tmp/pgis_reg 

# clean
#    && cd / \
#    && rm -rf /usr/src/postgis \
#    && apt-get purge -y --autoremove \
#      autoconf \
#      automake \
#      autotools-dev \
#      bison \
#      build-essential \
#      ca-certificates \
#      cmake \
#      g++ \
#      git \
#      libboost-all-dev \
#      libcgal-dev \
#      libcurl4-gnutls-dev \
#      libgmp-dev \
#      libjson-c-dev \
#      libmpfr-dev \
#      libpcre3-dev \
#      libprotobuf-c-dev \
#      libsqlite3-dev \
#      libtiff-dev \
#      libtool \
#      libxml2-dev \
#      make \
#      pkg-config \
#      postgresql-server-dev-$PG_MAJOR \
#      protobuf-c-compiler \
#      xsltproc \
#    && apt-get clean \
#    && rm -rf /var/lib/apt/lists/*
#    && rm -fr /usr/src/SFCGAL
#  && rm -fr /usr/src/PROJ
#   && rm -fr /usr/src/geos
#    && rm -fr /usr/src/gdal

#RUN  apt-get install -y  make cmake g++ libboost-dev libboost-system-dev \
#  libboost-filesystem-dev libexpat1-dev zlib1g-dev \
#  libbz2-dev libpq-dev libproj-dev lua5.3 liblua5.3-dev pandoc
#RUN git clone git://github.com/openstreetmap/osm2pgsql.git
#RUN cd osm2pgsql && \
#     mkdir build && \
#     cd build && \
#    cmake ..  && \
#    make && \
#make install


RUN mkdir -p /docker-entrypoint-initdb.d
COPY ./initdb-postgis.sh /docker-entrypoint-initdb.d/10_postgis.sh
COPY ./update-postgis.sh /usr/local/bin
RUN cat /_pgis_full_version.txt



