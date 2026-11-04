FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential clang flex bison g++ gawk gettext git \
    libncurses-dev libssl-dev python3 python3-setuptools python3-distutils rsync \
    unzip zlib1g-dev file wget time libelf-dev zstd libzstd-dev ca-certificates patch \
    && rm -rf /var/lib/apt/lists/*

ARG USER_ID=501
ARG GROUP_ID=20

RUN (groupadd -g ${GROUP_ID} buildgroup 2>/dev/null || true) && \
    (useradd -m -u ${USER_ID} -g ${GROUP_ID} -s /bin/bash builduser 2>/dev/null || \
     useradd -m -u ${USER_ID} -s /bin/bash builduser)

USER builduser
WORKDIR /home/builduser

CMD ["/bin/bash"]
