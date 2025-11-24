# Traditional Python Docker Image
FROM python:3.12-slim

WORKDIR /app

# Copy and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY hello_world_simple.py .

# Run with Python interpreter
CMD ["python", "hello_world_simple.py"]

# Expected size: 900MB-1GB
# Includes: Python runtime, pip packages, system libraries
