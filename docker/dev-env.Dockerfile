FROM debian:13

ARG INCLUDE_ANDROID=1
ARG PYTHON_VERSION=3.13.5
ARG NODE_VERSION=24.15.0
ARG FLUTTER_VERSION=3.41.7
ARG DART_VERSION=3.11.5
ARG CMAKE_VERSION=3.31.6
ARG CHROMIUM_VERSION=147.0.7727.116
ARG ANDROID_CMDLINE_TOOLS_VERSION=14742923
ARG ANDROID_PROFILES=android-35,android-36
ARG ANDROID_DEFAULT_PROFILE=android-36

ENV DEBIAN_FRONTEND=noninteractive
ENV FLUTTER_HOME=/opt/flutter
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_HOME=/opt/android-sdk
ENV VITYO_ANDROID_PROFILES=${ANDROID_PROFILES}
ENV VITYO_ANDROID_DEFAULT_PROFILE=${ANDROID_DEFAULT_PROFILE}
ENV STYIO_CHROME_PATH=/usr/bin/chromium
ENV CHROME_EXECUTABLE=/usr/bin/chromium
ENV PATH=/opt/Vityo-tools/bin:/opt/nodejs/current/bin:/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:$PATH

COPY toolchain/android-sdk-profiles.csv /tmp/android-sdk-profiles.csv

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        chromium \
        clang-18 \
        cmake \
        curl \
        git \
        libblkid-dev \
        libgtk-3-dev \
        liblzma-dev \
        mesa-utils \
        ninja-build \
        pkg-config \
        python3 \
        python3-pip \
        python3-venv \
        unzip \
        wget \
        xz-utils \
        zip \
    && if [ "$INCLUDE_ANDROID" = "1" ]; then apt-get install -y --no-install-recommends openjdk-21-jdk; fi \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/Vityo-tools \
    && /opt/Vityo-tools/bin/python -m pip install --upgrade pip \
    && /opt/Vityo-tools/bin/python -m pip install "cmake==$CMAKE_VERSION"

RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) node_arch="x64" ;; \
      arm64) node_arch="arm64" ;; \
      *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    archive="node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"; \
    wget -qO "/tmp/${archive}" "https://nodejs.org/dist/v${NODE_VERSION}/${archive}"; \
    mkdir -p /opt/nodejs; \
    tar -xJf "/tmp/${archive}" -C /opt/nodejs; \
    ln -s "/opt/nodejs/node-v${NODE_VERSION}-linux-${node_arch}" /opt/nodejs/current; \
    rm -f "/tmp/${archive}"

RUN wget -qO /tmp/flutter.tar.xz "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm -f /tmp/flutter.tar.xz

RUN if [ "$INCLUDE_ANDROID" = "1" ]; then \
      wget -qO /tmp/android-tools.zip "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip" \
      && mkdir -p /opt/android-sdk/cmdline-tools \
      && unzip -q /tmp/android-tools.zip -d /tmp/android-tools \
      && mv /tmp/android-tools/cmdline-tools /opt/android-sdk/cmdline-tools/latest \
      && yes | /opt/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=/opt/android-sdk --licenses >/dev/null \
      && yes | /opt/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=/opt/android-sdk "platform-tools" >/dev/null \
      && IFS=','; for profile in ${ANDROID_PROFILES}; do \
           line="$(awk -F, -v profile="$profile" 'NR > 1 && $1 == profile {print; exit}' /tmp/android-sdk-profiles.csv)"; \
           [ -n "$line" ] || { echo "unknown Android profile: $profile" >&2; exit 1; }; \
           platform="$(printf '%s\n' "$line" | cut -d, -f2)"; \
           build_tools="$(printf '%s\n' "$line" | cut -d, -f6)"; \
           ndk_version="$(printf '%s\n' "$line" | cut -d, -f7)"; \
           yes | /opt/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=/opt/android-sdk \
             "platforms;${platform}" \
             "build-tools;${build_tools}" \
             "ndk;${ndk_version}" >/dev/null; \
         done \
      && rm -rf /tmp/android-tools /tmp/android-tools.zip; \
    fi

RUN if [ "$INCLUDE_ANDROID" = "1" ]; then \
      flutter config --android-sdk /opt/android-sdk --enable-web --enable-linux-desktop --enable-android; \
      flutter precache --web --linux --android; \
    else \
      flutter config --enable-web --enable-linux-desktop; \
      flutter precache --web --linux; \
    fi

RUN useradd -m -s /bin/bash styio \
    && chown -R styio:styio /opt/flutter /opt/android-sdk /opt/nodejs /opt/Vityo-tools

USER styio
WORKDIR /workspace/vityo-nightly

CMD ["/bin/bash"]
