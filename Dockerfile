# Use NVIDIA CUDA runtime image
FROM nvidia/cuda:12.5.1-runtime-ubuntu24.04

# Extended from https://gitlab.com/nvidia/container-images/cuda/-/blob/master/dist/12.5.1/ubuntu2404/runtime/Dockerfile
ENV NV_CUDNN_VERSION=9.3.0.75-1
ENV NV_CUDNN_PACKAGE_NAME="libcudnn9"
ENV NV_CUDA_ADD=cuda-12
ENV NV_CUDNN_PACKAGE="$NV_CUDNN_PACKAGE_NAME-$NV_CUDA_ADD=$NV_CUDNN_VERSION"

LABEL com.nvidia.cudnn.version="${NV_CUDNN_VERSION}"

RUN apt-get update && apt-get install -y --no-install-recommends \
  ${NV_CUDNN_PACKAGE} \
  && apt-mark hold ${NV_CUDNN_PACKAGE_NAME}-${NV_CUDA_ADD}

ARG BASE_DOCKER_FROM=nvidia/cuda:12.5.1-runtime-ubuntu24.04

##### Base Setup

# Install system packages
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y --fix-missing \
  && apt-get install -y \
    apt-utils \
    locales \
    ca-certificates \
    && apt-get upgrade -y \
    && apt-get clean

# UTF-8 locale setup
RUN localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG=en_US.utf8
ENV LC_ALL=C

# Add deadsnakes PPA for Python 3.11
RUN apt-get update -y \
  && apt-get install -y software-properties-common \
  && add-apt-repository -y ppa:deadsnakes/ppa \
  && apt-get update -y

# Install necessary system packages including Python 3.11
RUN apt-get update -y --fix-missing \
  && apt-get upgrade -y \
  && apt-get install -y \
    build-essential \
    python3.11 \
    python3.11-dev \
    python3.11-venv \
    python3.11-distutils \
    unzip \
    wget \
    zip \
    zlib1g \
    zlib1g-dev \
    gnupg \
    rsync \
    git \
    sudo \
    libgl1 \
    libglib2.0-0 \
    ffmpeg \
  && apt-get clean

# Update Python 3 alternatives
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
  && update-alternatives --set python3 /usr/bin/python3.11 \
  && python3 --version

# Install pip for Python 3.11
RUN wget https://bootstrap.pypa.io/get-pip.py -O /tmp/get-pip.py \
  && python3 /tmp/get-pip.py \
  && rm /tmp/get-pip.py

# Store base build details
ENV BUILD_FILE="/etc/image_base.txt"
ARG BASE_DOCKER_FROM
RUN echo "DOCKER_FROM: ${BASE_DOCKER_FROM}" | tee ${BUILD_FILE}
RUN echo "CUDNN: ${NV_CUDNN_PACKAGE_NAME} (${NV_CUDNN_VERSION})" | tee -a ${BUILD_FILE}

ARG BUILD_BASE="unknown"
LABEL comfyui-nvidia-docker-build-from=${BUILD_BASE}
RUN it="/etc/build_base.txt"; echo ${BUILD_BASE} > $it && chmod 555 $it

##### User Setup
ENV COMFYUSER_DIR="/comfy"
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers \
    && useradd -u 1024 -U -d ${COMFYUSER_DIR} -s /bin/bash -m comfy \
    && usermod -G users comfy \
    && adduser comfy sudo \
    && test -d ${COMFYUSER_DIR}
RUN it="/etc/comfyuser_dir"; echo ${COMFYUSER_DIR} > $it && chmod 555 $it

ENV NVIDIA_VISIBLE_DEVICES=all

EXPOSE 8188

USER comfy
WORKDIR ${COMFYUSER_DIR}

# Copy initialization scripts
COPY --chown=comfy:comfy init.bash comfyui-nvidia_init.bash
RUN chmod 555 comfyui-nvidia_init.bash

##### Install Python Packages and SageAttention

RUN pip install --no-cache-dir \
    torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu125 \
    triton==3.0.0

# Clone and install SageAttention
USER root
RUN git clone https://github.com/thu-ml/SageAttention.git /opt/SageAttention \
    && chown -R comfy:comfy /opt/SageAttention
USER comfy
RUN cd /opt/SageAttention && pip install -e .

##### Install ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI \
    && cd /opt/ComfyUI \
    && pip install -r requirements.txt

# Make sure ComfyUI runs with SageAttention
ENV USE_SAGE_ATTENTION=1

ARG BUILD_DATE="unknown"
LABEL comfyui-nvidia-docker-build=${BUILD_DATE}

CMD [ "./comfyui-nvidia_init.bash" ]
