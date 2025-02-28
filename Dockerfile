# -------------------------------------------------------------------
# 1) Base: devel image so we can compile SageAttention with nvcc
# -------------------------------------------------------------------
FROM nvidia/cuda:12.5.1-devel-ubuntu24.04

# -------------------------------------------------------------------
# 2) Install system libraries and set up environment
# -------------------------------------------------------------------
ENV DEBIAN_FRONTEND=noninteractive

# CUDNN environment (matching the base image tags)
ENV NV_CUDNN_VERSION=9.3.0.75-1
ENV NV_CUDNN_PACKAGE_NAME="libcudnn9"
ENV NV_CUDA_ADD=cuda-12
ENV NV_CUDNN_PACKAGE="$NV_CUDNN_PACKAGE_NAME-$NV_CUDA_ADD=$NV_CUDNN_VERSION"

LABEL com.nvidia.cudnn.version="${NV_CUDNN_VERSION}"

# Install cuDNN, then hold its version
RUN apt-get update && \
    apt-get install -y --no-install-recommends ${NV_CUDNN_PACKAGE} && \
    apt-mark hold ${NV_CUDNN_PACKAGE_NAME}-${NV_CUDA_ADD} && \
    apt-get clean

# Install Ubuntu packages, add deadsnakes for Python 3.11
RUN apt-get update -y --fix-missing && \
    apt-get install -y \
      apt-utils \
      locales \
      ca-certificates \
      software-properties-common && \
    add-apt-repository -y ppa:deadsnakes/ppa && \
    apt-get update -y && \
    apt-get install -y \
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
      ffmpeg && \
    apt-get upgrade -y && \
    apt-get clean

# Set locale to UTF-8
RUN localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG=en_US.utf8
ENV LC_ALL=C

# Install pip for Python 3.11
RUN wget https://bootstrap.pypa.io/get-pip.py -O /tmp/get-pip.py \
    && python3.11 /tmp/get-pip.py \
    && rm /tmp/get-pip.py

# Make python3 -> python3.11 the default
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 && \
    update-alternatives --set python3 /usr/bin/python3.11 && \
    python3 --version

# -------------------------------------------------------------------
# 3) Create comfy user and ensure /opt/ComfyUI is writable
# -------------------------------------------------------------------
ENV COMFYUSER_DIR="/comfy"
RUN useradd -u 1024 -U -d ${COMFYUSER_DIR} -s /bin/bash -m comfy && \
    usermod -G users comfy && \
    # Give comfy user sudo with no password
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
    adduser comfy sudo && \
    # Create /opt/ComfyUI (owned by comfy)
    mkdir -p /opt/ComfyUI && chown comfy:comfy /opt/ComfyUI

# -------------------------------------------------------------------
# 4) Switch to comfy user
# -------------------------------------------------------------------
USER comfy
WORKDIR ${COMFYUSER_DIR}
ENV NVIDIA_VISIBLE_DEVICES=all
EXPOSE 8188

# -------------------------------------------------------------------
# 5) Install PyTorch + SageAttention
# -------------------------------------------------------------------
# Torch + extra index for CUDA 12.5 (PyTorch whl)
RUN pip install --no-cache-dir \
    torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu125 \
    triton==3.0.0

# This environment variable tells the patched SageAttention setup.py which SM to compile for
ENV GPU_ARCHS=8.6

# Clone and install SageAttention from your fork (which has the new setup.py)
RUN git clone https://github.com/reggiekush/SageAttention.git ${COMFYUSER_DIR}/SageAttention && \
    cd ${COMFYUSER_DIR}/SageAttention && \
    pip install -e .

# -------------------------------------------------------------------
# 6) Install ComfyUI in /opt/ComfyUI
# -------------------------------------------------------------------
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI && \
    cd /opt/ComfyUI && \
    pip install -r requirements.txt

# -------------------------------------------------------------------
# 7) Make sure ComfyUI runs with SageAttention
# -------------------------------------------------------------------
ENV USE_SAGE_ATTENTION=1

# -------------------------------------------------------------------
# 8) Final launch command
# -------------------------------------------------------------------
CMD ["./comfyui-nvidia_init.bash"]
