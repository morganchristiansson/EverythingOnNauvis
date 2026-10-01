FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
# UTF-8 locale: Factorio and its Lua read bytes as text, and the noise tooling
# reads --dump-data JSON with non-ASCII strings in it. C.UTF-8 keeps both sides
# from tripping over encoding.
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    jq \
    git \
    zip \
    unzip \
    lua5.2 \
    build-essential \
    python3-pil \
    python3-numpy \
    python3-pip \
    python3-rcon \
    ddgr pandoc \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/* && \
    node --version && npm --version

# ── npm global packages ─────────────────────────────────────────────────────
RUN npm install -g @earendil-works/pi-coding-agent@0.87.1 && \
    pi --version


RUN mkdir -p /workspace
USER ubuntu
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable
ENV PATH="/home/ubuntu/.cargo/bin:${PATH}"

RUN pip3 install --no-cache-dir --break-system-packages trafilatura

WORKDIR /workspace
