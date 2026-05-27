FROM ghcr.io/anomalyco/opencode:latest

RUN apk add --no-cache \
    bash ca-certificates curl git jq openssh-client wget

ARG GH_VERSION=2.67.0
RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
    | tar -xz -C /usr/local --strip-components=1 "gh_${GH_VERSION}_linux_amd64/bin/gh"

ARG DOCKER_VERSION=27.5.1
RUN curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" \
    | tar -xz -C /usr/local/bin --strip-components=1 docker/docker

ARG ACT_VERSION=0.2.75
RUN curl -fsSL "https://github.com/nektos/act/releases/download/v${ACT_VERSION}/act_Linux_x86_64.tar.gz" \
    | tar -xz -C /usr/local/bin act

COPY ssh-setup.sh /ssh-setup.sh
RUN chmod +x /ssh-setup.sh

ENTRYPOINT ["/ssh-setup.sh"]
