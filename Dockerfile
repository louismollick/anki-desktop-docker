FROM node:24-bookworm-slim AS node
RUN node -e "const [major, minor, patch] = process.versions.node.split('.').map(Number); if (major !== 24 || minor < 22 || (minor === 22 && patch < 1)) process.exit(1)"

FROM lsiobase/kasmvnc:ubuntunoble AS kclient
COPY --from=node /usr/local/ /usr/local/
# Kasm's audio helper contains a native addon tied to Node's module ABI.
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libpulse-dev python3 && \
    cd /kclient && npm rebuild && node -e "require('pulseaudio2')"

FROM lsiobase/kasmvnc:ubuntunoble

# Use pre-launcher Anki version from PyPI (avoids launcher confirmation issues)
# TODO: Switch back to launcher version when deployment is fixed
ARG ANKI_VERSION=25.2.7

# KasmVNC also runs Node. Replace the distro runtime with the patched LTS build.
COPY --from=node /usr/local/bin/node /usr/bin/node
COPY --from=kclient /kclient /kclient
RUN node --version

# Install system dependencies and Qt6/XCB requirements
RUN apt-get update && \
    apt-get install -y \
        curl \
        xdg-utils \
        python3-xdg \
        python3 \
        lame \
        mplayer \
        libatomic1 \
        libxcb-xinerama0 \
        libxcb-cursor0 \
        libxcb-icccm4 \
        libxcb-image0 \
        libxcb-keysyms1 \
        libxcb-randr0 \
        libxcb-render-util0 \
        libxcb-shape0 \
        libxkbcommon-x11-0 \
        libxdamage1 \
        libminizip1t64 \
        libdbus-1-3 \
        libegl1 \
        libfontconfig1 \
        libgl1 \
        libglib2.0-0 \
        libxrender1 \
        xdotool \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install uv globally (Python package manager, much faster than pip)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    mv /config/.local/bin/uv /usr/local/bin/uv

# Install Anki from PyPI using uv (much faster than pip)
RUN uv pip install --system --break-system-packages anki==${ANKI_VERSION} aqt==${ANKI_VERSION}

# Note: Anki data directory created at runtime by setup script
# This ensures proper ownership after volume mount

# Copy setup scripts and install Python dependencies using uv (much faster)
COPY ./scripts /app/scripts
RUN uv pip install --system --break-system-packages -r /app/scripts/requirements.txt && \
    find /app/scripts -name "*.sh" -exec sed -i 's/\r$//' {} \; && \
    chmod +x /app/scripts/*.py /app/scripts/*.sh

# Copy custom entrypoint and fix line endings (Windows to Unix)
COPY ./docker/entrypoint.sh /app/entrypoint.sh
RUN sed -i 's/\r$//' /app/entrypoint.sh && chmod +x /app/entrypoint.sh

COPY ./root /

# Fix line endings in autostart and other default files (Windows to Unix)
RUN find /defaults -type f -exec sed -i 's/\r$//' {} \;

EXPOSE 3000 8765

# Use custom entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]
