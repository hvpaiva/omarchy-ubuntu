# The Ubuntu release under test: 24.04, or 26.04 (run.sh and full.sh pass
# UBUNTU). APT_MIRROR, when set, stands in for archive.ubuntu.com and
# security.ubuntu.com, for a host far from them.
ARG UBUNTU=24.04
FROM ubuntu:${UBUNTU}
ARG GUM_VERSION=0.17.0
ARG APT_MIRROR=
ENV DEBIAN_FRONTEND=noninteractive
RUN if [ -n "$APT_MIRROR" ]; then \
      sed -i -E "s#https?://(archive|security)\.ubuntu\.com/ubuntu/?#${APT_MIRROR%/}/#g" /etc/apt/sources.list.d/ubuntu.sources; \
    fi \
    && apt-get update && apt-get install -y --no-install-recommends \
      git sudo ca-certificates curl bsdutils util-linux coreutils pciutils procps kmod udev \
      software-properties-common gnupg zstd apparmor jq libcap2-bin \
    # A release whose minimal install brings sudo-rs (26.04) runs it as its
    # sudo; the image does too, as a real install would.
    && if apt-cache depends ubuntu-minimal 2>/dev/null | grep -qx '  Depends: sudo-rs'; then \
      apt-get install -y --no-install-recommends sudo-rs; \
    fi \
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
