FROM mcr.microsoft.com/dotnet/sdk:6.0.428-1-focal@sha256:525ce79a6f545131df515ce34f7ee086eb18e4d707eff9676b2678f2f23b6d9e

# The pinned Tizen installer requires Python 3.8, available natively on focal.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 python3.8 libpython3.8 git curl unzip zip xz-utils file make \
    clang cmake ninja-build pkg-config pciutils libncurses5 libglib2.0-0 binutils \
    libsm6 libxrender1 libxi6 libxtst6 libxrandr2 libkf5itemmodels5 \
    libkf5kiowidgets5 libkchart2 dbus-x11 gnome-keyring libsecret-tools \
    && rm -rf /var/lib/apt/lists/*
ARG BUILDER_UID=1000
ARG BUILDER_GID=1000
RUN (getent group "$BUILDER_GID" || groupadd --gid "$BUILDER_GID" builder) \
    && useradd --create-home --uid "$BUILDER_UID" --gid "$BUILDER_GID" builder
USER builder
ENV HOME=/home/builder \
    FLUTTER_TIZEN_ROOT=/home/builder/flutter-tizen \
    TIZEN_SDK=/home/builder/tizen-studio
WORKDIR /work
CMD ["bash"]
