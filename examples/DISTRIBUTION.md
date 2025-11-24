# Distribution Guide

PyAOT produces single-file native binaries. This eliminates Python's distribution challenges.

## Binary Size Comparison

| Format | Size | Notes |
|--------|------|-------|
| Python .pyc | 1-5 KB | Requires 50MB+ Python runtime |
| PyAOT binary | 50-500 KB | Standalone executable |
| Python + deps | 100MB-1GB | Full environment needed |

**Key difference:** PyAOT binaries include only what you use. No interpreter overhead.

## Dependency Hell: Solved

### Python Traditional
```bash
# User must have:
python3.12 --version  # Right Python version
pip install -r requirements.txt  # All dependencies
source venv/bin/activate  # Virtual environment
python app.py  # Finally run
```

**Problems:**
- Version conflicts (pip dependency resolver)
- Platform differences (wheels, compilation)
- Security patches require full environment rebuild

### PyAOT
```bash
./app  # Just run
```

**Benefits:**
- Zero dependencies on target machine
- No pip, virtualenv, or Python required
- Single file to distribute

## Cross-Platform Distribution

### Python
```bash
# Ship source + requirements
tar -czf app.tar.gz app.py requirements.txt
# User must have Python + pip on their platform
```

### PyAOT
```bash
# Build for each platform
pyaot --target x86_64-linux app.py   # Linux
pyaot --target x86_64-macos app.py   # macOS
pyaot --target x86_64-windows app.py # Windows

# Ship binaries directly
# No runtime needed on target
```

## Docker Size Advantage

See `examples/docker/` for working examples.

### Python Image
```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY app.py .
CMD ["python", "app.py"]
```

**Result:** 900MB+ (base image 180MB + packages)

### PyAOT Image
```dockerfile
FROM scratch
COPY app /app
CMD ["/app"]
```

**Result:** <1MB (just your binary)

### Real Measurements

Using `examples/hello_world_simple.py`:

```bash
# Python approach
docker build -f examples/docker/python.Dockerfile -t py-hello .
docker images py-hello
# REPOSITORY   TAG     SIZE
# py-hello     latest  1.04GB

# PyAOT approach
pyaot --binary examples/hello_world_simple.py -o examples/docker/app
docker build -f examples/docker/pyaot.Dockerfile -t pyaot-hello .
docker images pyaot-hello
# REPOSITORY    TAG     SIZE
# pyaot-hello   latest  524KB

# Size reduction: 2000x smaller
```

## Deployment Patterns

### Pattern 1: Static Binary Distribution
```bash
# Build once
pyaot --binary app.py

# Ship to servers
scp app user@server:/usr/local/bin/
ssh user@server '/usr/local/bin/app'
```

### Pattern 2: Container Deployment
```bash
# Minimal container
FROM scratch
COPY app /app
CMD ["/app"]

# Or with minimal libs
FROM alpine:latest
COPY app /app
CMD ["/app"]
# Still <10MB total
```

### Pattern 3: Lambda/Serverless
```bash
# Small cold-start footprint
zip lambda.zip app  # <1MB
aws lambda update-function-code --zip-file fileb://lambda.zip

# vs Python: 50MB+ deployment package
```

## Security Benefits

### Python Distribution
- Ships source code (unless using PyInstaller)
- Requires full Python runtime (larger attack surface)
- Dependencies can have vulnerabilities
- Must update entire environment for patches

### PyAOT Distribution
- Ships compiled binary only
- Minimal attack surface (no interpreter)
- Static linking = no dependency updates needed
- Update once, rebuild binary

## When to Use Each

### Use Python distribution when:
- Rapid prototyping
- Dynamic imports/eval required
- Full Python ecosystem needed

### Use PyAOT distribution when:
- Production deployment
- Container size matters
- Dependency conflicts are issues
- Security/IP protection needed
- Edge deployment (IoT, embedded)

## Next Steps

1. Try building: `pyaot --binary your_app.py`
2. Compare sizes: `ls -lh your_app`
3. Run directly: `./your_app`
4. Ship binary to any compatible system

No pip. No virtualenv. No Python runtime needed.
