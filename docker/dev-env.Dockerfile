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

RUN set -eux; \
    apt_install() { \
      for attempt in 1 2 3 4 5; do \
        rm -rf /var/lib/apt/lists/*; \
        apt-get \
          -o Acquire::Retries=5 \
          -o Acquire::http::Pipeline-Depth=0 \
          -o Acquire::http::No-Cache=true \
          -o Acquire::https::No-Cache=true \
          update; \
        if apt-get \
          -o Acquire::Retries=5 \
          -o Acquire::http::Pipeline-Depth=0 \
          -o Acquire::http::No-Cache=true \
          -o Acquire::https::No-Cache=true \
          install -y --no-install-recommends --fix-missing "$@"; then \
          return 0; \
        fi; \
        apt-get \
          -o Acquire::Retries=5 \
          -o Acquire::http::Pipeline-Depth=0 \
          -o Acquire::http::No-Cache=true \
          -o Acquire::https::No-Cache=true \
          install -y --no-install-recommends --fix-broken || true; \
        dpkg --configure -a || true; \
        apt-get clean; \
        sleep "$((attempt * 5))"; \
      done; \
      return 1; \
    }; \
    apt_install ca-certificates; \
    sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list.d/debian.sources; \
    apt_install \
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
        libwebp-dev \
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
    ; \
    if [ "$INCLUDE_ANDROID" = "1" ]; then apt_install openjdk-21-jdk; fi; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    python3 -m venv /opt/Vityo-tools; \
    pip_install() { \
      for attempt in 1 2 3 4 5; do \
        if /opt/Vityo-tools/bin/python -m pip install \
          --no-cache-dir \
          --retries 10 \
          --timeout 120 \
          "$@"; then \
          return 0; \
        fi; \
        sleep "$((attempt * 5))"; \
      done; \
      return 1; \
    }; \
    pip_install --upgrade pip; \
    pip_install "cmake==$CMAKE_VERSION"

RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) node_arch="x64" ;; \
      arm64) node_arch="arm64" ;; \
      *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    archive="node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"; \
    curl --fail --location --retry 5 --retry-all-errors --connect-timeout 60 --max-time 900 \
      -o "/tmp/${archive}" \
      "https://nodejs.org/dist/v${NODE_VERSION}/${archive}"; \
    mkdir -p /opt/nodejs; \
    tar -xJf "/tmp/${archive}" -C /opt/nodejs; \
    ln -s "/opt/nodejs/node-v${NODE_VERSION}-linux-${node_arch}" /opt/nodejs/current; \
    rm -f "/tmp/${archive}"

RUN set -eux; \
    download_with_resume() { \
      url="$1"; \
      dest="$2"; \
      partial="${dest}.partial"; \
      for attempt in $(seq 1 40); do \
        echo "download attempt ${attempt}: ${url}"; \
        if curl --fail --location --silent --show-error \
          --continue-at - \
          --connect-timeout 60 \
          --max-time 1800 \
          -o "$partial" \
          "$url"; then \
          mv "$partial" "$dest"; \
          return 0; \
        fi; \
        sleep 5; \
      done; \
      return 1; \
    }; \
    download_with_resume \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      /tmp/flutter.tar.xz; \
    tar -xJf /tmp/flutter.tar.xz -C /opt; \
    rm -f /tmp/flutter.tar.xz

RUN if [ "$INCLUDE_ANDROID" = "1" ]; then \
      curl --fail --location --retry 5 --retry-all-errors --connect-timeout 60 --max-time 900 \
        -o /tmp/android-tools.zip \
        "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip" \
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

RUN git config --global --add safe.directory /opt/flutter \
    && if [ "$INCLUDE_ANDROID" = "1" ]; then \
      flutter config --android-sdk /opt/android-sdk --enable-web --enable-linux-desktop --enable-android; \
      flutter precache --web --linux --android; \
    else \
      flutter config --no-enable-android --enable-web --enable-linux-desktop; \
      flutter precache --web --linux; \
    fi

RUN printf '%s\n' \
      'export PATH=/opt/Vityo-tools/bin:/opt/nodejs/current/bin:/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:$PATH' \
      > /etc/profile.d/vityo-dev-env.sh \
    && ln -sf /usr/bin/clang-18 /usr/local/bin/clang \
    && ln -sf /usr/bin/clang++-18 /usr/local/bin/clang++ \
    && mkdir -p /opt/android-sdk \
    && useradd -m -s /bin/bash styio \
    && chown -R styio:styio /opt/flutter /opt/android-sdk /opt/nodejs /opt/Vityo-tools

USER styio
RUN if [ "$INCLUDE_ANDROID" = "1" ]; then \
      flutter config --android-sdk /opt/android-sdk --enable-web --enable-linux-desktop --enable-android; \
    else \
      flutter config --no-enable-android --enable-web --enable-linux-desktop; \
    fi

WORKDIR /workspace/vityo-nightly

CMD ["/bin/bash"]
