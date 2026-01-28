# Qwen3-TTS Docker Image
# Base: NVIDIA CUDA 12.4 + Ubuntu 22.04
# GPU: A100 40GB/80GB

FROM nvidia/cuda:12.4.0-cudnn9-devel-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    CUDA_HOME=/usr/local/cuda \
    PATH=/usr/local/cuda/bin:$PATH \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3.10-dev \
    python3-pip \
    git \
    wget \
    curl \
    ffmpeg \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Set Python 3.10 as default
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1 && \
    update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1

# Upgrade pip
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# Set working directory
WORKDIR /app

# Copy requirements first (for better caching)
COPY requirements.txt .
COPY requirements-video.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Install Flash Attention (A100 optimization)
RUN pip install --no-cache-dir -U flash-attn --no-build-isolation || \
    echo "Flash Attention installation failed, continuing without it"

# Install video dependencies (optional, comment out if not needed)
ARG INSTALL_VIDEO=false
RUN if [ "$INSTALL_VIDEO" = "true" ]; then \
        pip install --no-cache-dir -r requirements-video.txt; \
    fi

# Copy application code
COPY . .

# Create necessary directories
RUN mkdir -p avatars output models

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run server
CMD ["python", "server.py"]
