ARG OPENMS_REPO=https://github.com/OpenMS/OpenMS.git
ARG OPENMS_BRANCH=release/3.4.1
ARG SOURCE_DIR="/tmp/OpenMS"
ARG BUILD_DIR="${SOURCE_DIR}/bld"
ARG INSTALL_DIR="/opt/OpenMS"
ARG CMAKE_VERSION="3.28.1"
ARG CMAKE_INSTALL_DIR="/opt/cmake"
ARG OPENMS_USER=openms
ARG UID=1000
ARG GID=1000
ARG NUM_BUILD_CORES=20
ARG MAKEFLAGS="-j${NUM_BUILD_CORES}"
ARG DEBIAN_FRONTEND=noninteractive


################################################################################
# The minimal runtime dependencies
################################################################################
FROM debian:bookworm-slim AS runtime-base
ARG INSTALL_DIR
ARG DEBIAN_FRONTEND
ARG OPENMS_USER
ARG UID
ARG GID

ENV PATH="${INSTALL_DIR}/bin:${PATH}"

# create new user which will actually run the application
RUN <<-EOF
    addgroup --gid ${GID} ${OPENMS_USER}
    adduser --disabled-password --gecos '' --uid ${UID} --gid ${GID} ${OPENMS_USER}
    chown -R ${OPENMS_USER} /home/${OPENMS_USER}
EOF

# NOTE: cmake asks for boost iostreams, date_time and regex (see find_boost in
#       cmake/cmake_findExternalLibs.cmake), but only regex actually ends up as a
#       NEEDED entry - OpenMS only uses the header-only parts of the other two.
#       The `test` stage is what guards this: it runs ctest against the runtime
#       dependency set, so if that ever stops being true it fails there.
#       libicu is pulled in by libboost-regex, but xerces/Qt already require it.
RUN apt-get update \
  && apt-get install -y --no-install-recommends --no-install-suggests \
    libqt6opengl6 \
    libsvm3 \
    libzip4 \
    zlib1g \
    libbz2-1.0 \
    libgomp1 \
    libqt6svg6 \
    libxerces-c3.2 \
    coinor-libcoinmp1v5 \
    libqt6network6 \
    libboost-regex1.74.0 \
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
    qt6-base-dev \
    libqt6svg6-dev \
    libeigen3-dev \
    coinor-libcoinmp-dev \
    # boost: bookworm ships 1.74, which is exactly the minimum OpenMS asks for
    # and the same version upstream builds release/3.4.1 against
    libboost-date-time-dev \
    libboost-iostreams-dev \
    libboost-regex-dev \
    libboost-math-dev \
    libboost-random-dev \
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
# NOTE: BOOST_USE_STATIC has to be OFF with distro boost - Debian's libboost_*.a
#       are not built with -fPIC, so they cannot be linked into libOpenMS.so.
#       This matches what upstream does for release/3.4.1.
RUN cmake \
    -DCMAKE_BUILD_TYPE='Release' \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR} \
    -DBOOST_USE_STATIC=OFF \
    -DHAS_XSERVER=OFF \
    -DENABLE_DOCS=OFF \
    -DWITH_GUI=OFF \
    -S ${SOURCE_DIR} \
    -B ${BUILD_DIR}
RUN make all
RUN make install/strip


################################################################################
# The minimal (hopefully) runtime
################################################################################
FROM build AS share-without-examples
ARG INSTALL_DIR

COPY --from=build ${INSTALL_DIR}/share ${INSTALL_DIR}/share
RUN rm -r ${INSTALL_DIR}/share/OpenMS/examples


FROM runtime-base AS runtime
ARG OPENMS_USER
ARG SOURCE_DIR
ARG INSTALL_DIR

COPY --from=build ${INSTALL_DIR}/lib ${INSTALL_DIR}/lib
COPY --from=build ${INSTALL_DIR}/include ${INSTALL_DIR}/include
COPY --from=build ${INSTALL_DIR}/bin ${INSTALL_DIR}/bin
COPY --from=share-without-examples ${INSTALL_DIR}/share ${INSTALL_DIR}/share

USER ${OPENMS_USER}
WORKDIR /home/${OPENMS_USER}

LABEL org.opencontainers.image.source=https://github.com/radusuciu/docker-openms


################################################################################
# The whole test suit is being run, but not everything is built in the build
# stage.. so this is just to prevent those tests from failing (eg. because some 
# tests depend on docs being built). 
################################################################################
FROM build AS test-build
ARG SOURCE_DIR
ARG BUILD_DIR
ARG NUM_BUILD_CORES

WORKDIR ${BUILD_DIR}
RUN cmake -DENABLE_DOCS=ON -S${SOURCE_DIR} -B${BUILD_DIR}
RUN make all


################################################################################
# Making sure that the built tools and library pass the test suite, alongside
# the runtime dependencies
#
# NOTE: the installed/stripped binaries are not actually tested - this is more
#       of a sanity check to make sure that the runtime dependencies meet the
#       requirements of the built executables and library.
################################################################################
FROM runtime AS test
ARG SOURCE_DIR
ARG BUILD_DIR
ARG INSTALL_DIR
ARG CMAKE_INSTALL_DIR
ARG NUM_BUILD_CORES

ENV PATH="${CMAKE_INSTALL_DIR}/bin:${PATH}"

USER root

COPY --from=test-build ${CMAKE_INSTALL_DIR} ${CMAKE_INSTALL_DIR}
COPY --from=test-build ${SOURCE_DIR} ${SOURCE_DIR}
COPY --from=test-build ${BUILD_DIR} ${BUILD_DIR}
# as above, patched to use share from source instead of install
# can remove for releases post 3.1.0
COPY --from=test-build ${SOURCE_DIR}/share ${INSTALL_DIR}/share

WORKDIR ${BUILD_DIR}
RUN ctest --output-on-failure -j${NUM_BUILD_CORES}
