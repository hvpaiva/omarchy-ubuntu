FROM ubuntu:24.04
ARG GUM_VERSION=0.17.0
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      git sudo ca-certificates curl bsdutils util-linux coreutils pciutils procps kmod udev \
      software-properties-common gnupg zstd apparmor jq libcap2-bin \
    && rm -rf /var/lib/apt/lists/* \
    # docker-clean deletes every .deb after each install: the apt cache
    # volume full.sh mounts would never carry anything to the next run.
    && rm -f /etc/apt/apt.conf.d/docker-clean \
    && curl -fsSL -o /tmp/gum.deb "https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_amd64.deb" \
    && dpkg -i /tmp/gum.deb && rm /tmp/gum.deb \
    && userdel -r ubuntu \
    && useradd -m -u 1000 -s /bin/bash tester \
    && echo 'tester ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/tester \
    && chmod 440 /etc/sudoers.d/tester
USER tester
WORKDIR /home/tester
