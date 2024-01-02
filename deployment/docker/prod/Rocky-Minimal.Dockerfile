# ansible-semaphore production image
FROM golang:1.20-alpine3.18 as builder

COPY ./ /go/src/github.com/ansible-semaphore/semaphore
WORKDIR /go/src/github.com/ansible-semaphore/semaphore

RUN apk add --no-cache -U libc-dev curl nodejs npm git gcc g++ && \
  ./deployment/docker/prod/bin/install

FROM rockylinux:9.3-minimal as runner
LABEL maintainer="Jarmo Haaranen <jarmo@uccs.fi>"

# Install packages and enable epel repo
RUN microdnf install -y epel-release && \
    microdnf update -y && microdnf clean all && \
    microdnf install -y sshpass \
      git-core \
      ansible-core \
      mysql \
      postgresql \
      openssh-clients \
      tini \
      python3 \
      python3-pip \
      python3-aiohttp \
      golang-bin \
      curl && \
    microdnf clean all

# Create semaphore user
RUN groupadd -g 1001 semaphore && \
    useradd -u 1001 -g 1001 -d /home/semaphore semaphore

# Create semaphore folders
RUN mkdir -p /tmp/semaphore && \
    mkdir -p /etc/semaphore && \
    mkdir -p /var/lib/semaphore && \
    chown -R semaphore:semaphore /tmp/semaphore && \
    chown -R semaphore:semaphore /etc/semaphore && \
    chown -R semaphore:semaphore /var/lib/semaphore

COPY --from=builder /usr/local/bin/semaphore-wrapper /usr/local/bin/
COPY --from=builder /usr/local/bin/semaphore /usr/local/bin/

RUN chown -R semaphore:semaphore /usr/local/bin/semaphore-wrapper &&\
    chown -R semaphore:semaphore /usr/local/bin/semaphore

WORKDIR /home/semaphore
USER 1001

# Set ansible bin to path
ENV PATH="/home/semaphore/.local/bin:$PATH"

# See https://github.com/pypa/pip/issues/10151
ENV _PIP_LOCATIONS_NO_WARN_ON_MISMATCH=1

RUN python3 -m pip install pywinrm && \
    python3 -m pip install pyvmomi && \
    python3 -m pip install netaddr && \
    ansible-galaxy collection install azure.azcollection && \
    python3 -m pip install -r ~/.ansible/collections/ansible_collections/azure/azcollection/requirements-azure.txt && \
    ansible-galaxy collection install ansible.utils && \
    python3 -m pip install -r ~/.ansible/collections/ansible_collections/ansible/utils/requirements.txt && \
    ansible-galaxy collection install community.docker && \
    ansible-galaxy collection install community.general

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/semaphore-wrapper", "/usr/local/bin/semaphore", "server", "--config", "/etc/semaphore/config.json"]