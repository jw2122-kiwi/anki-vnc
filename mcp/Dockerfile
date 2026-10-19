FROM python:3.12-slim

WORKDIR /app

RUN pip install --no-cache-dir "mcp>=1.2,<2.0" "httpx>=0.27,<1.0"

COPY server.py .

# AnkiConnect endpoint inside the compose network
ENV ANKICONNECT_URL=http://anki-connect:8765 \
    MCP_HOST=0.0.0.0 \
    MCP_PORT=8000

EXPOSE 8000

HEALTHCHECK --interval=60s --timeout=5s --retries=3 CMD \
    python3 -c "import socket,sys; socket.create_connection(('127.0.0.1', 8000), timeout=5)"

CMD ["python3", "server.py"]
