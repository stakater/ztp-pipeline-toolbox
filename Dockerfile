######################################################### TOOLCHAIN VERSIONING #########################################
ARG UBUNTU_VERSION="22.04"
ARG DOCKER_VERSION="24.0.7"
ARG KUBECTL_VERSION="1.28.2"
ARG OC_CLI_VERSION="4.14.1"
# Using Helm 3.10.1 as the latest Helm version has a null value override issue.
# For additional details, refer to: https://github.com/helm/helm/issues/5184
ARG HELM_VERSION="3.10.1"
ARG TERRAFORM_VERSION="1.6.4"
ARG ANSIBLE_CORE_VERSION="2.15.6"
ARG ANSIBLE_VERSION="8.6.1"
ARG ANSIBLE_LINT="6.22.0"
ARG JINJA_VERSION="3.1.2"
ARG CRICTL_VERSION="1.28.0"
ARG VELERO_VERSION="1.12.1"
ARG ZSH_VERSION="5.8.1"
ARG VAULT_VERSION="1.15.2"

######################################################### BINARY-DOWNLOADER ############################################
FROM alpine as binary_downloader

ARG TARGETARCH
ARG DOCKER_VERSION
ARG KUBECTL_VERSION
ARG OC_CLI_VERSION
ARG HELM_VERSION
ARG TERRAFORM_VERSION
ARG ANSIBLE_VERSION
ARG ANSIBLE_CORE_VERSION
ARG ANSIBLE_LINT
ARG JINJA_VERSION
ARG CRICTL_VERSION
ARG VELERO_VERSION
ARG STERN_VERSION
ARG ZSH_VERSION
ARG VAULT_VERSION

USER root
WORKDIR /root/download

RUN apk --update add \
    curl \
    openssl \
    unzip \
    tar \
    wget

WORKDIR /root/download

RUN mkdir -p /root/download/binaries

#download oc-cli
RUN if [[ ! -z ${OC_CLI_VERSION} ]] ; then \
      mkdir -p oc_cli && \
      curl -SsL --retry 5 -o oc_cli.tar.gz https://mirror.openshift.com/pub/openshift-v4/$TARGETARCH/clients/ocp/$OC_CLI_VERSION/openshift-client-linux-$OC_CLI_VERSION.tar.gz && \
      tar xvf oc_cli.tar.gz -C oc_cli && \
      mv "/root/download/oc_cli/oc" "/root/download/binaries/oc"; \
    fi

#download helm3-cli
RUN if [[ ! -z ${HELM_VERSION} ]] ; then \
      mkdir helm && curl -SsL --retry 5 "https://get.helm.sh/helm-v$HELM_VERSION-linux-$TARGETARCH.tar.gz" | tar xz -C ./helm && \
      mv "/root/download/helm/linux-${TARGETARCH}/helm" "/root/download/binaries/helm"; \
    fi

#download terraform
RUN if [[ ! -z ${TERRAFORM_VERSION} ]] ; then \
      wget -q https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform\_${TERRAFORM_VERSION}\_linux_${TARGETARCH}.zip && \
      unzip ./terraform\_${TERRAFORM_VERSION}\_linux_${TARGETARCH}.zip -d terraform_cli && \
      mv "/root/download/terraform_cli/terraform" "/root/download/binaries/terraform"; \
    fi

#download docker
#credits to https://github.com/docker-library/docker/blob/463595652d2367887b1ffe95ec30caa00179be72/18.09/Dockerfile
#need to stick to uname since docker download link uses "aarch64" instead of "arm64"
RUN if [[ ! -z ${DOCKER_VERSION} ]] ; then \
      mkdir -p /root/download/docker/bin && \
      set -eux && \
      arch="$(uname -m)" && \
      wget -q -O docker.tgz "https://download.docker.com/linux/static/stable/${arch}/docker-${DOCKER_VERSION}.tgz" && \
      tar --extract \
          --file docker.tgz \
          --strip-components 1 \
          --directory /root/download/docker/bin && \
      mv /root/download/docker/bin/* -t "/root/download/binaries/" ; \
    fi

#download kubectl
RUN if [[ ! -z ${KUBECTL_VERSION} ]] ; then \
      wget -q https://storage.googleapis.com/kubernetes-release/release/v$KUBECTL_VERSION/bin/linux/${TARGETARCH}/kubectl -O /root/download/kubectl && \
      mv "/root/download/kubectl" "/root/download/binaries/kubectl"; \
    fi

#download crictl
RUN if [[ ! -z ${CRICTL_VERSION} ]] ; then \
      mkdir -p /root/download/crictl && \
      wget -q "https://github.com/kubernetes-sigs/cri-tools/releases/download/v$CRICTL_VERSION/crictl-v$CRICTL_VERSION-linux-${TARGETARCH}.tar.gz" -O /root/download/crictl.tar.gz && \
      tar zxvf /root/download/crictl.tar.gz -C /root/download/crictl && \
      mv "/root/download/crictl/crictl" "/root/download/binaries/crictl"; \
    fi

#download yq
RUN curl -Lo yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${TARGETARCH} && \
    mv "/root/download/yq" "/root/download/binaries/yq"

#download tcpping
#todo: switch to https://github.com/deajan/tcpping/blob/master/tcpping when ubuntu is supported
RUN wget -q https://raw.githubusercontent.com/deajan/tcpping/original-1.8/tcpping -O /root/download/tcpping && \
    mv "/root/download/tcpping" "/root/download/binaries/tcpping"

#download velero CLI
RUN if [[ ! -z ${VELERO_VERSION} ]] ; then \
      wget -q https://github.com/vmware-tanzu/velero/releases/download/v${VELERO_VERSION}/velero-v${VELERO_VERSION}-linux-${TARGETARCH}.tar.gz && \
      tar -xvf velero-v${VELERO_VERSION}-linux-${TARGETARCH}.tar.gz && \
      mv velero-v${VELERO_VERSION}-linux-${TARGETARCH}/velero /root/download/binaries/velero; \
    fi

#download vault CLI
RUN if [[ ! -z ${VAULT_VERSION} ]] ; then \
      wget -q https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_${TARGETARCH}.zip && \
      unzip ./vault_${VAULT_VERSION}_linux_${TARGETARCH}.zip -d vault_cli && \
      mv "/root/download/vault_cli/vault" "/root/download/binaries/vault"; \
    fi

######################################################### BASE-IMAGE ###################################################
FROM ubuntu:$UBUNTU_VERSION as base-image

ARG TARGETARCH
ARG DOCKER_VERSION
ARG KUBECTL_VERSION
ARG OC_CLI_VERSION
ARG HELM_VERSION
ARG TERRAFORM_VERSION
ARG ANSIBLE_VERSION
ARG ANSIBLE_CORE_VERSION
ARG ANSIBLE_LINT
ARG JINJA_VERSION
ARG CRICTL_VERSION
ARG VELERO_VERSION
ARG ZSH_VERSION
ARG VAULT_VERSION

#use bash during docker build
SHELL ["/bin/bash", "-c"]

#env
ENV DEBIAN_FRONTEND noninteractive

USER root
WORKDIR /root

#https://github.com/waleedka/modern-deep-learning-docker/issues/4#issue-292539892
#bc and tcptraceroute needed for tcping
RUN apt-get update && \
    apt-get dist-upgrade -y && \
    apt-get upgrade -y && \
    apt-get install -y \
    apt-utils \
    apt-transport-https \
    bash-completion \
    bc \
    build-essential \
    ca-certificates \
    curl \
    dnsutils \
    fping \
    git \
    gnupg \
    gnupg2 \
    groff \
    iputils-ping \
    jq \
    less \
    libssl-dev \
    locales \
    lsb-release \
    nano \
    net-tools \
    netcat \
    nmap \
    openssl \
    python3 \
    python3-dev \
    python3-pip \
    software-properties-common \
    sudo \
    telnet \
    tcptraceroute \
    traceroute \
    unzip \
    uuid-runtime \
    vim \
    wget \
    zip \
    zlib1g-dev &&\
    apt-get clean -y && \
    apt-get autoclean -y && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /var/cache/apt/archives/*

#install zsh + configure git
RUN locale-gen en_US.UTF-8
RUN apt-get update && \
    apt-get install -y \
    fonts-powerline \
    powerline \
    zsh
RUN git config --global --add safe.directory '*'

#install common requirements
RUN pip3 install \
    cryptography \
    hvac \
    jmespath \
    openshift \
    pyyaml \
    kubernetes \
    netaddr \
    passlib \
    pbr \
    pip \
    pyOpenSSL \
    pyvmomi \
    setuptools

#install ansible
RUN if [[ ! -z ${ANSIBLE_VERSION} && ! -z ${JINJA_VERSION} ]] ; then \
      pip3 install \
      ansible-core==${ANSIBLE_CORE_VERSION} \
      ansible==${ANSIBLE_VERSION} \
      ansible-lint==${ANSIBLE_LINT} \
      jinja2==${JINJA_VERSION}; \
    fi

#install ansible collection
RUN ansible-galaxy collection install kubernetes.core
RUN ansible-galaxy collection install azure.azcollection --force

RUN pip3 install -r ~/.ansible/collections/ansible_collections/azure/azcollection/requirements.txt -v
RUN pip3 install azure-cli
RUN pip3 install \
    azure-graphrbac==0.61.1 \
    msrestazure==0.6.4 \
    azure-common==1.1.28

ENV TERM xterm
ENV ZSH_THEME agnoster
RUN wget -q https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh -O - | zsh

######################################################### IMAGE ########################################################
FROM base-image

ARG TARGETARCH
ARG DOCKER_VERSION
ARG KUBECTL_VERSION
ARG OC_CLI_VERSION
ARG HELM_VERSION
ARG TERRAFORM_VERSION
ARG ANSIBLE_VERSION
ARG ANSIBLE_CORE_VERSION
ARG ANSIBLE_LINT
ARG JINJA_VERSION
ARG CRICTL_VERSION
ARG VELERO_VERSION
ARG ZSH_VERSION
ARG VAULT_VERSION

#use bash during docker build
SHELL ["/bin/bash", "-c"]

#env
ENV EDITOR nano

#copy binaries
COPY --from=binary_downloader "/root/download/binaries/*" "/usr/local/bin/"

RUN chmod -R +x /usr/local/bin && \
    docker --version && \
    yq --version && \
    tcpping; \
    if [[ ! -z "HELM_VERSION" ]] ; then \
      helm version && \
      helm repo update; \
    fi; \
    if [[ ! -z "KUBECTL_VERSION" ]] ; then \
      kubectl version --client=true; \
    fi; \
    if [[ ! -z "CRICTL_VERSION" ]] ; then \
      crictl --version; \
    fi; \
    if [[ ! -z "OC_CLI_VERSION" ]] ; then \
      oc version --client; \
    fi; \
    if [[ ! -z "TERRAFORM_VERSION" ]] ; then \
      terraform version ; \
    fi; \
    if [[ ! -z "VELERO_VERSION" ]] ; then \
      velero version --client-only; \
    fi

COPY .bashrc /root/.bashrc
COPY .zshrc /root/.zshrc

USER root
WORKDIR /root/project
CMD ["/bin/bash"]
