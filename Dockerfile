# -------------------------------------------------------------------
# 1) Base: devel image so we can compile SageAttention with nvcc
# -------------------------------------------------------------------
FROM nvidia/cuda:12.5.1-devel-ubuntu24.04

# -------------------------------------------------------------------
# 2) Minimal environment setup (cudnn, locales, python, etc.)
# -------------------------------------------------------------------
ENV DEBIAN_FRONTEND=noninteractive

ENV NV_CUDNN_VERSION=9.3.0.75-1
ENV NV_CUDNN_PACKAGE_NAME="libcudnn9"
ENV NV_CUDA_ADD=cuda-12
ENV NV_CUDNN_PACKAGE="$NV_CUDNN_PACKAGE_NAME-$NV_CUDA_ADD=$NV_CUDNN_VERSION"

LABEL com.nvidia.cudnn.version="${NV_CUDNN_VERSION}"

# Install cuDNN and mark it 'hold'
RUN apt-get update && \
    apt-get install -y --no-install-recommends ${NV_CUDNN_PACKAGE} && \
    apt-mark hold ${NV_CUDNN_PACKAGE_NAME}-${NV_CUDA_ADD} && \
    apt-get clean

# Install base packages and Python 3.11 from deadsnakes
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

# Set locale
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

# Store base build details
ENV BUILD_FILE="/etc/image_base.txt"
ARG BASE_DOCKER_FROM

# Re-create /etc/image_base.txt
RUN echo "DOCKER_FROM: ${BASE_DOCKER_FROM}" | tee ${BUILD_FILE} && \
    echo "CUDNN: ${NV_CUDNN_PACKAGE_NAME} (${NV_CUDNN_VERSION})" | tee -a ${BUILD_FILE}

# Re-create /etc/comfyuser_dir
RUN it="/etc/comfyuser_dir"; echo ${COMFYUSER_DIR} > $it && chmod 555 $it

ARG BUILD_BASE="unknown"
LABEL comfyui-nvidia-docker-build-from=${BUILD_BASE}

# Re-create /etc/build_base.txt
RUN it="/etc/build_base.txt"; echo ${BUILD_BASE} > $it && chmod 555 $it

# -------------------------------------------------------------------
# 3) Create comfy user
# -------------------------------------------------------------------
ENV COMFYUSER_DIR="/comfy"
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
    useradd -u 1024 -U -d ${COMFYUSER_DIR} -s /bin/bash -m comfy && \
    usermod -G users comfy && \
    adduser comfy sudo

ENV NVIDIA_VISIBLE_DEVICES=all
EXPOSE 8188

# -------------------------------------------------------------------
# 4) Switch to comfy user, set /comfy as WORKDIR
# -------------------------------------------------------------------
USER comfy
WORKDIR ${COMFYUSER_DIR}

# -------------------------------------------------------------------
# 5) Install PyTorch + SageAttention
# -------------------------------------------------------------------
#  - We use Torch's CUDA 12.5 wheels from their extra index URL.
#  - Then we set GPU_ARCHS=8.6 so SageAttention knows which SM to compile for (e.g. 3090).
RUN pip install --no-cache-dir \
    torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu125 \
    triton==3.0.0

ENV GPU_ARCHS=8.6

# Clone & install your forked SageAttention (with the patched setup.py).
RUN git clone https://github.com/reggiekush/SageAttention.git "${COMFYUSER_DIR}/SageAttention" && \
    cd "${COMFYUSER_DIR}/SageAttention" && \
    pip install -e .

# -------------------------------------------------------------------
# 6) Install ComfyUI in /opt/ComfyUI
# -------------------------------------------------------------------
# We keep ComfyUI separate in /opt, but comfy user still owns it.
USER root
RUN mkdir -p /opt/ComfyUI && chown comfy:comfy /opt/ComfyUI
USER comfy

RUN git clone https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI && \
    cd /opt/ComfyUI && \
    pip install -r requirements.txt

# -------------------------------------------------------------------
# 7) Make sure ComfyUI runs with SageAttention
# -------------------------------------------------------------------
ENV USE_SAGE_ATTENTION=1

# -------------------------------------------------------------------
# 8) Copy in your local comfyui-nvidia_init.bash to /comfy
# -------------------------------------------------------------------
USER root
COPY --chown=comfy:comfy comfyui-nvidia_init.bash /comfy/
RUN chmod 555 /comfy/comfyui-nvidia_init.bash
USER comfy
WORKDIR /comfy

# -------------------------------------------------------------------
# 9) Final command
# -------------------------------------------------------------------
CMD ["./comfyui-nvidia_init.bash"]
