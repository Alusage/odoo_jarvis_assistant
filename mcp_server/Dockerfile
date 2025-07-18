FROM python:3.11-slim

# Install system dependencies including Docker CLI
RUN apt-get update && apt-get install -y \
    git \
    make \
    curl \
    ca-certificates \
    lsb-release \
    gnupg \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI for Docker-in-Docker operations
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce-cli docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements and install Python dependencies
COPY mcp_server/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy MCP server
COPY mcp_server/mcp_server.py .

# Copy only necessary parts of the repository (excluding data directories)
COPY config /repo/config
COPY scripts /repo/scripts  
COPY Makefile /repo/Makefile
COPY create_client.sh /repo/create_client.sh

# Accept build arguments for dynamic user/group creation
ARG DOCKER_GID=997
ARG USER_ID=1000

# Create user with same UID/GID as host user to avoid permission issues
RUN groupadd -g ${USER_ID} mcpuser && \
    groupadd -g ${DOCKER_GID} docker && \
    useradd -u ${USER_ID} -g ${USER_ID} -G docker -m -s /bin/bash mcpuser

# Configure Git for the user
RUN git config --global user.email "mcp-server@alusage.com" && \
    git config --global user.name "MCP Server" && \
    git config --global init.defaultBranch main

# Change ownership of working directories
RUN chown -R mcpuser:mcpuser /app /repo

# Set the working directory to the repo
WORKDIR /repo

# Switch to non-root user
USER mcpuser

# Expose HTTP port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python3 -c "import httpx; httpx.get('http://localhost:8000/').raise_for_status()" || exit 1

# Run the server in HTTP mode
CMD ["python3", "mcp_server/mcp_server.py", ".", "--mode", "http", "--host", "0.0.0.0", "--port", "8000"]