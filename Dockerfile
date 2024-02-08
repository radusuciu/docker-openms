ARG OPENMS_REPO=https://github.com/OpenMS/OpenMS.git
ARG OPENMS_BRANCH=Release3.1.0
ARG SOURCE_DIR="/tmp/OpenMS"
ARG BUILD_DIR="${SOURCE_DIR}/bld"
ARG INSTALL_DIR="/opt/OpenMS"
ARG CMAKE_VERSION="3.28.1"
ARG CMAKE_INSTALL_DIR="/opt/cmake"
ARG OPENMS_USER=openms
ARG UID=1000
ARG GID=1000
ARG boost_version=1.78
ARG BOOST_LIBS_TO_BUILD=date_time,iostreams,regex,math,random
ARG NUM_BUILD_CORES=20
ARG BOOST_BUILD_CORES=1
ARG MAKEFLAGS="-j${NUM_BUILD_CORES}"
ARG DEBIAN_FRONTEND=noninteractive


################################################################################
# Building only the boost libs that we need and packaging them into debs. 
################################################################################
FROM debian:bullseye-slim as boost-builder
ARG boost_version
ARG DEBIAN_FRONTEND
ARG BOOST_LIBS_TO_BUILD
ARG BOOST_BUILD_CORES

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
	./b2 $(echo $BOOST_LIBS_TO_BUILD | sed 's/,/ --with-/g' | awk '{print "--with-"$0}') link=static,shared -j ${BOOST_BUILD_CORES} --prefix=`pwd`/debian/boost-all/usr/
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
# The minimal runtime dependencies
################################################################################
FROM debian:bullseye-slim AS runtime-base
ARG INSTALL_DIR
ARG DEBIAN_FRONTEND
ARG OPENMS_USER
ARG UID
ARG GID

ENV DEBIAN_FRONTEND=${DEBIAN_FRONTEND}
ENV PATH="${INSTALL_DIR}/bin:${PATH}"

# create new user which will actually run the application
RUN <<-EOF
    addgroup --gid ${GID} ${OPENMS_USER}
    adduser --disabled-password --gecos '' --uid ${UID} --gid ${GID} ${OPENMS_USER}
    chown -R ${OPENMS_USER} /home/${OPENMS_USER}
EOF

COPY --from=boost-builder /tmp/boost_*debs/* /tmp/boost_debs/

RUN dpkg -i /tmp/boost_debs/*.deb && rm -rf /tmp/boost_debs \
  && apt-get update \
  && apt-get install -y --no-install-recommends --no-install-suggests \
    libqt5opengl5 \
    libsvm3 \
    libzip4 \
    zlib1g \
    libbz2-1.0 \
    libgomp1 \
    libqt5svg5 \
    libxerces-c3.2 \
    coinor-libcoinmp1v5 \
  && rm -rf /var/lib/apt/lists/*


################################################################################
# Building the library and tools
################################################################################
FROM runtime-base AS build
ARG OPENMS_REPO
ARG OPENMS_BRANCH
ARG SOURCE_DIR
ARG BUILD_DIR
ARG INSTALL_DIR
ARG CMAKE_VERSION
ARG CMAKE_INSTALL_DIR
ARG MAKEFLAGS

ENV MAKEFLAGS="${MAKEFLAGS}"

# install build dependencies
RUN apt-get -y update \
  && apt-get install -y --no-install-recommends --no-install-suggests \
    # build system dependencies
    g++ \
    make \
    git \
    ca-certificates \
    # OpenMS build dependencies
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
    libeigen3-dev \
    coinor-libcoinmp-dev \
  && rm -rf /var/lib/apt/lists/* \
  && update-ca-certificates

# installing cmake
WORKDIR /tmp
ADD https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.sh cmake.sh
RUN <<-EOF
    set -eux
    mkdir -p /opt/cmake
    sh cmake.sh --skip-license --prefix=${CMAKE_INSTALL_DIR}
    ln -s /opt/cmake/bin/cmake /usr/local/bin/cmake
    ln -s /opt/cmake/bin/ctest /usr/local/bin/ctest
    rm -rf /tmp/*
EOF

RUN git clone --depth=1 --branch=${OPENMS_BRANCH} ${OPENMS_REPO} ${SOURCE_DIR}
WORKDIR ${BUILD_DIR}
RUN cmake \
    -DCMAKE_BUILD_TYPE='Release' \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR} \
    -DBOOST_USE_STATIC=OFF \
    -S ${SOURCE_DIR} \
    -B ${BUILD_DIR}
RUN make all
RUN make install/strip


################################################################################
# The minimal (hopefully) runtime
################################################################################
FROM runtime-base AS runtime
ARG OPENMS_USER
ARG SOURCE_DIR
ARG INSTALL_DIR

COPY --from=build ${INSTALL_DIR}/lib ${INSTALL_DIR}/lib
COPY --from=build ${INSTALL_DIR}/include ${INSTALL_DIR}/include
# copying from SOURCE_DIR instead of INSTALL_DIR due to bug affecting OpenMS 3.1.0
# NOTE: bug was fixed in https://github.com/OpenMS/OpenMS/pull/7337
COPY --from=build ${SOURCE_DIR}/share ${INSTALL_DIR}/share
COPY --from=build ${INSTALL_DIR}/bin ${INSTALL_DIR}/bin

USER ${OPENMS_USER}
WORKDIR /home/${OPENMS_USER}

LABEL org.opencontainers.image.source https://github.com/radusuciu/docker-openms


################################################################################
# Making sure that the built tools and library pass the test suite, alongside
# the runtime dependencies.
################################################################################
FROM runtime AS test
ARG SOURCE_DIR
ARG BUILD_DIR
ARG CMAKE_VERSION
ARG CMAKE_INSTALL_DIR
ARG NUM_BUILD_CORES

ENV PATH="${CMAKE_INSTALL_DIR}/bin:${PATH}"

USER root

RUN apt-get update \ 
    && apt-get install -y --no-install-recommends --no-install-suggests \
    # we need Xvfb to run a small subset of tests (eg. TOPP_INIUpdater)
    xvfb \
    xauth \
    # needed for TSGDialog_test and TOPPView_test
    libqt5test5 \
  && rm -rf /var/lib/apt/lists/*

COPY --from=build ${SOURCE_DIR} ${SOURCE_DIR}
COPY --from=build ${BUILD_DIR} ${BUILD_DIR}
COPY --from=build ${CMAKE_INSTALL_DIR} ${CMAKE_INSTALL_DIR}

WORKDIR ${BUILD_DIR}
RUN xvfb-run -a ctest --output-on-failure -j${NUM_BUILD_CORES}
