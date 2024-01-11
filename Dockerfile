ARG DEBIAN_FRONTEND=noninteractive
ARG boost_version=1.78
ARG NUM_BUILD_CORES=20
ARG MAKEFLAGS="-j${NUM_BUILD_CORES}"
ARG OPENMS_TAG=Release3.0.0
ARG OPENMS_REPO=https://github.com/OpenMS/OpenMS.git
ARG CMAKE_VERSION="3.28.1"
ARG BOOST_LIBS_TO_BUILD=date_time,iostreams,regex,math,random


################################################################################
# Building only the boost libs that we need and packaging them into debs. 
################################################################################
FROM debian:bullseye as boost-builder
ARG boost_version
ARG DEBIAN_FRONTEND
ARG BOOST_LIBS_TO_BUILD
ENV BOOST_LIBS_TO_BUILD=${BOOST_LIBS_TO_BUILD}

RUN apt-get update && apt-get install -y \
    build-essential \
    g++ \
    python-dev \
    autotools-dev \
    libicu-dev \
    libbz2-dev \
    wget \
    devscripts \
    debhelper \
    fakeroot \
    cdbs \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/* 

# script modified from
#
# https://github.com/ulikoehler/deb-buildscripts
# authored by Uli Köhler and distributed under CC0 1.0 Universal
#
# I am including it as a heredoc because I want to keep it all in one
# Dockerfile, though I may reconsider in the future.
RUN <<EOF

export MAJORVERSION=$(echo $boost_version | cut -d. -f1)
export MINORVERSION=$(echo $boost_version | cut -d. -f2)
export PATCHVERSION=$(echo $boost_version | cut -d. -f3)
export PATCHVERSION=${PATCHVERSION:-0}
export FULLVERSION=${MAJORVERSION}.${MINORVERSION}.${PATCHVERSION}
export UNDERSCOREVERSION=${MAJORVERSION}_${MINORVERSION}_${PATCHVERSION}
export DEBVERSION=${FULLVERSION}-1

if [ ! -d "boost_${UNDERSCOREVERSION}" ]; then
    # NOTE: URLs here are subject to change. see: https://github.com/boostorg/boost/issues/845
    wget "https://archives.boost.io/release/${FULLVERSION}/source/boost_${UNDERSCOREVERSION}.tar.bz2" -O boost-all_${FULLVERSION}.orig.tar.bz2
    tar xjvf boost-all_${FULLVERSION}.orig.tar.bz2
fi

cd boost_${UNDERSCOREVERSION}
#Build DEB
rm -rf debian
mkdir -p debian
#Use the LICENSE file from nodejs as copying file
touch debian/copying
#Create the changelog (no messages needed)
export DEBEMAIL="none@example.com"
dch --create -v $DEBVERSION --package boost-all ""
#Create copyright file
touch debian
#Create control file
cat > debian/control <<EOF_CONTROL
Source: boost-all
Maintainer: None <none@example.com>
Section: misc
Priority: optional
Standards-Version: 3.9.2
Build-Depends: debhelper (>= 8), cdbs, libbz2-dev, zlib1g-dev

Package: boost-all
Architecture: amd64
Depends: \${shlibs:Depends}, \${misc:Depends}, boost-all (= $DEBVERSION)
Description: Boost library, version $DEBVERSION (shared libraries)

Package: boost-all-dev
Architecture: any
Depends: boost-all (= $DEBVERSION)
Description: Boost library, version $DEBVERSION (development files)

EOF_CONTROL
#Create rules file
cat > debian/rules <<EOF_RULES
#!/usr/bin/make -f
%:
	dh \$@
override_dh_auto_configure:
	./bootstrap.sh
override_dh_auto_build:
	./b2 $(echo $BOOST_LIBS_TO_BUILD | sed 's/,/ --with-/g' | awk '{print "--with-"$0}') link=static,shared -j 1 --prefix=`pwd`/debian/boost-all/usr/
override_dh_auto_test:
override_dh_auto_install:
	mkdir -p debian/boost-all/usr debian/boost-all-dev/usr
	./b2 $(echo $BOOST_LIBS_TO_BUILD | sed 's/,/ --with-/g' | awk '{print "--with-"$0}') link=static,shared --prefix=`pwd`/debian/boost-all/usr/ install
	mv debian/boost-all/usr/include debian/boost-all-dev/usr
EOF_RULES
#Create some misc files
echo "10" > debian/compat
mkdir -p debian/source
echo "3.0 (quilt)" > debian/source/format
#Build the package
debuild -b
cd ..
mkdir -p /tmp/boost_debs /tmp/boost_dev_debs
mv boost-all-dev_${DEBVERSION}*.deb /tmp/boost_dev_debs/
mv boost-all_${DEBVERSION}*.deb /tmp/boost_debs/
EOF


################################################################################
# The build stage for OpenMS
################################################################################
FROM debian:bullseye-slim as openms-build
ARG DEBIAN_FRONTEND
ARG OPENMS_TAG
ARG OPENMS_REPO
ARG CMAKE_VERSION
ARG MAKEFLAGS
ENV MAKEFLAGS="${MAKEFLAGS}"

COPY --from=boost-builder /tmp/boost_*debs/* /tmp/boost_debs/
RUN dpkg -i /tmp/boost_debs/*.deb && rm -rf /tmp/boost_debs \
  && apt-get -y update \
  && apt-get install -y --no-install-recommends --no-install-suggests \
    # build requirements
    g++ \
    build-essential \
    gcc \
    autoconf \
    automake \
    patch \
    libtool \
    make \
    git \
    libssl-dev \
    # advanced dependencies
    libeigen3-dev \
    coinor-libcoinmp-dev \
    libsvm-dev \
    libglpk-dev \
    libzip-dev \
    zlib1g-dev \
    libxerces-c-dev \
    libbz2-dev \
    libomp-dev \
    libhdf5-dev \
    qtbase5-dev \
    libqt5svg5-dev \
    libqt5opengl5-dev \
    # for OpenMS library build
    openjdk-17-jdk

# installing cmake
WORKDIR /tmp
ADD https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.sh cmake.sh
RUN <<-EOF
    mkdir -p /opt/cmake
    sh cmake.sh --skip-license --prefix=/opt/cmake
    ln -s /opt/cmake/bin/cmake /usr/local/bin/cmake
    ln -s /opt/cmake/bin/ctest /usr/local/bin/ctest
    rm -rf /tmp/*
EOF

# build contrib
WORKDIR /
RUN git clone --branch ${OPENMS_TAG} --single-branch https://github.com/OpenMS/contrib.git && rm -rf contrib/.git/
WORKDIR /openms-contrib-build

# compiling OpenMS library
WORKDIR /
RUN git clone --branch ${OPENMS_TAG} --single-branch ${OPENMS_REPO}
WORKDIR /openms-build
RUN /bin/bash -c "cmake -DCMAKE_BUILD_TYPE='Release' -DCMAKE_PREFIX_PATH='/openms-contrib-build/;/usr/;/usr/local' -DBOOST_USE_STATIC=OFF ../OpenMS"
RUN make OpenMS

# grabbing third party deps
WORKDIR /OpenMS
RUN <<-EOF
    mkdir /thirdparty
    git submodule update --init THIRDPARTY
    cp -r THIRDPARTY/All/* /thirdparty
    cp -r THIRDPARTY/Linux/64bit/* /thirdparty
EOF

ENV PATH="/thirdparty/LuciPHOr2:/thirdparty/MSGFPlus:/thirdparty/Sirius:/thirdparty/ThermoRawFileParser:/thirdparty/Comet:/thirdparty/Fido:/thirdparty/MaRaCluster:/thirdparty/Percolator:/thirdparty/SpectraST:/thirdparty/XTandem:${PATH}"

WORKDIR /openms-build
RUN make TOPP && make UTILS && rm -rf src doc CMakeFiles


################################################################################
# Here we copy all of the binaries we need from the previous stage so the final
# image is as small as possible. We also install the runtime dependencies for
# OpenMS.
################################################################################
FROM debian:bullseye-slim AS worker
ARG DEBIAN_FRONTEND
ARG UID=1000
ARG GID=1000
ARG OPENMS_USER=openms
ENV PATH="/openms-build/bin/:/openms-thirdparty/LuciPHOr2:/openms-thirdparty/MSGFPlus:/openms-thirdparty/Sirius:/openms-thirdparty/ThermoRawFileParser:/openms-thirdparty/Comet:/openms-thirdparty/Fido:/openms-thirdparty/MaRaCluster:/openms-thirdparty/MyriMatch:/thirdparty/OMSSA:/thirdparty/Percolator:/thirdparty/SpectraST:/thirdparty/XTandem:/thirdparty/crux:${PATH}"

# create new user which will actually run the application
RUN <<-EOF
    addgroup --gid ${GID} ${OPENMS_USER}
    adduser --disabled-password --gecos '' --uid ${UID} --gid ${GID} ${OPENMS_USER}
    chown -R ${OPENMS_USER} /home/${OPENMS_USER}
EOF

COPY --from=boost-builder /tmp/boost_debs/* /tmp/boost_debs/

# install runtime dependencies
RUN dpkg -i /tmp/boost_debs/*.deb && rm -rf /tmp/boost_debs \
  && apt-get update \
  && apt-get install -y --no-install-recommends --no-install-suggests \
    libqt5opengl5 \
    libsvm3 \
    libzip4 \
    zlib1g \
    libbz2-1.0 \
    libgomp1 \
    libxerces-c3.2 \
  && rm -rf /var/lib/apt/lists/*

# copy openms binaries
COPY --from=openms-build /openms-contrib-build /openms-contrib-build
COPY --from=openms-build /thirdparty /openms-thirdparty
COPY --from=openms-build /openms-build /openms-build
COPY --from=openms-build /OpenMS /OpenMS

USER ${OPENMS_USER}

LABEL org.opencontainers.image.source https://github.com/radusuciu/docker-openms
