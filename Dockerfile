# Dockerfile for providing buildozer
FROM python:3.7-slim

ENV USER="user"
ENV HOME_DIR="/home/${USER}"
ENV WORK_DIR="${HOME_DIR}/hostcwd" \
    PATH="${HOME_DIR}/.local/bin:${PATH}"

RUN apt update -qq > /dev/null \
    && DEBIAN_FRONTEND=noninteractive apt install -qq --yes --no-install-recommends \
    locales && \
    locale-gen en_US.UTF-8
ENV LANG="fr_FR.UTF-8" \
    LANGUAGE="fr_FR.UTF-8" \
    LC_ALL="fr_FR.UTF-8"

# Workaround for bug https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=863199#23
RUN mkdir -p /usr/share/man/man1

RUN DEBIAN_FRONTEND=noninteractive  apt install wget gnupg software-properties-common --yes --no-install-recommends

RUN wget -qO - https://adoptopenjdk.jfrog.io/adoptopenjdk/api/gpg/key/public | apt-key add -

RUN add-apt-repository --yes https://adoptopenjdk.jfrog.io/adoptopenjdk/deb/

# system requirements to build most of the recipes
RUN apt update && DEBIAN_FRONTEND=noninteractive apt install --yes --no-install-recommends adoptopenjdk-8-hotspot

RUN DEBIAN_FRONTEND=noninteractive apt install --yes --no-install-recommends \
    autoconf \
    automake \
    build-essential \
    ccache \
    gettext \
    git \
    libc6 \
    libffi-dev \
    libltdl-dev \
    libssl-dev \
    libtool \
    patch \
    pkg-config \
    sudo \
    unzip \
    usbutils \
    zip \
    zlib1g-dev

RUN mkdir -p /opt/cmake-builder/cmake-3.19.2

WORKDIR /opt/cmake-builder/cmake-3.19.2

# install latest cmake
RUN mkdir -p /opt/cmake-builder && \
    cd /opt/cmake-builder && \
    wget https://github.com/Kitware/CMake/releases/download/v3.19.2/cmake-3.19.2.tar.gz && \
    tar -zxvf cmake-3.19.2.tar.gz && \
    cd cmake-3.19.2 && \
    ./bootstrap && \
    make && \
    sudo make install && \
    cmake --version && \
    rm -rf /opt/cmake-builder

RUN cmake --version

#Install du NDK
ENV ANDROID_NDK_HOME /opt/android-ndk
ENV ANDROID_NDK_VERSION r19c

RUN mkdir /opt/android-ndk-tmp && \
    cd /opt/android-ndk-tmp && \
    wget -q https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux-x86_64.zip && \
# uncompress
    unzip -q android-ndk-${ANDROID_NDK_VERSION}-linux-x86_64.zip && \
# move to its final location
    mv ./android-ndk-${ANDROID_NDK_VERSION} ${ANDROID_NDK_HOME} && \
# remove temp dir
    cd ${ANDROID_NDK_HOME} && \
    rm -rf /opt/android-ndk-tmp

# add to PATH
RUN apt-get install -y git make gcc g++ m4 texinfo bison flex curl
RUN mkdir ~/bin
ENV PATH="~/bin/:${PATH}:${ANDROID_NDK_HOME}"

RUN curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
RUN chmod a+x ~/bin/repo

RUN mkdir /opt/ndk-builder/
WORKDIR /opt/ndk-builder/
COPY languages.patch .

RUN ~/bin/repo init -u https://android.googlesource.com/platform/manifest -b gcc && \
    ~/bin/repo sync && \
    ~/bin/repo forall -c git checkout ndk-${ANDROID_NDK_VERSION} || true && \
    cd /opt/ndk-builder/toolchain/gcc && \
    mv /opt/ndk-builder/languages.patch . && \
    patch < languages.patch && \
    rm languages.patch && \
    # builder for arm64-v8a
    ./build.py --toolchain aarch64-linux-android && \
    mkdir -p /opt/android-ndk/toolchains/aarch64-linux-android-4.9/prebuilt/ && \
    mv /opt/ndk-builder/out/dist/gcc-arm64-linux-x86_64.tar.bz2 /opt/android-ndk/toolchains/aarch64-linux-android-4.9/prebuilt/ && \
    cd /opt/android-ndk/toolchains/aarch64-linux-android-4.9/prebuilt/ && \
    tar -xvf gcc-arm64-linux-x86_64.tar.bz2 && \
    mv linux-x86_64 linux-x86_64.bak && \
    mv aarch64-linux-android-4.9 linux-x86_64 && \
    # builder for armeabi-v7a
    cd /opt/ndk-builder/toolchain/gcc && \
    ./build.py --toolchain arm-linux-androideabi && \
    mkdir -p /opt/android-ndk/toolchains/arm-linux-androideabi-4.9/prebuilt/ && \
    mv /opt/ndk-builder/out/dist/gcc-arm-linux-x86_64.tar.bz2 /opt/android-ndk/toolchains/arm-linux-androideabi-4.9//prebuilt/ && \
    cd /opt/android-ndk/toolchains/arm-linux-androideabi-4.9//prebuilt/ && \
    tar -xvf gcc-arm-linux-x86_64.tar.bz2 && \
    mv linux-x86_64 linux-x86_64.bak && \
    mv arm-linux-androideabi-4.9 linux-x86_64 && \
    rm -rf /opt/ndk-builder

#Install de apache ANT
ARG ANT_VERSION=1.9.4
WORKDIR /opt
RUN wget -q http://archive.apache.org/dist/ant/binaries/apache-ant-${ANT_VERSION}-bin.tar.gz && \
    tar xzf apache-ant-*.tar.gz && \
    rm apache-ant-*.tar.gz

#Install du sdk
ARG ANDROID_SDK_VERSION=6609375
ENV ANDROID_SDK_ROOT /opt/android-sdk
RUN mkdir -p ${ANDROID_SDK_ROOT} && \
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_VERSION}_latest.zip && \
    unzip *tools*linux*.zip -d ${ANDROID_SDK_ROOT} && \
    rm *tools*linux*.zip

WORKDIR ${ANDROID_SDK_ROOT}
RUN yes 2>/dev/null | /opt/android-sdk/tools/bin/sdkmanager --sdk_root=/opt/android-sdk --licenses

# Workaround for https://github.com/kivy/buildozer/issues/1144
RUN touch ~/.android/repositories.cfg
RUN /opt/android-sdk/tools/bin/sdkmanager --sdk_root=/opt/android-sdk "tools"
RUN /opt/android-sdk/tools/bin/sdkmanager --sdk_root=/opt/android-sdk "build-tools;30.0.2"
RUN /opt/android-sdk/tools/bin/sdkmanager --sdk_root=/opt/android-sdk "platforms;android-30"
RUN /opt/android-sdk/tools/bin/sdkmanager --sdk_root=/opt/android-sdk "platform-tools"
RUN /opt/android-sdk/tools/bin/sdkmanager --sdk_root=/opt/android-sdk "patcher;v4"
RUN /opt/android-sdk/tools/bin/sdkmanager --sdk_root=/opt/android-sdk "emulator"

# installs buildozer and dependencies
RUN pip3 install --upgrade Cython wheel pip virtualenv toml colorama jinja2 python-for-android kivy
RUN pip3 install https://github.com/germn/buildozer/archive/add_adb_args_option.zip 
ENV PATH="/root/.local/bin:$PATH"

WORKDIR ${WORK_DIR}
RUN rm -rf ~/hostcwd/.buildozer && mkdir -p ~/hostcwd/.buildozer

ENTRYPOINT ["buildozer"]
