FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    make \
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

# Set the working directory to the repo
WORKDIR /repo

# Expose HTTP port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python3 -c "import httpx; httpx.get('http://localhost:8000/').raise_for_status()" || exit 1

# Run the server in HTTP mode
CMD ["python3", "mcp_server/mcp_server.py", ".", "--mode", "http", "--host", "0.0.0.0", "--port", "8000"]