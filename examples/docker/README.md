# Docker Size Comparison

Compare Python vs PyAOT Docker image sizes.

## Build Python Image

```bash
cd examples/docker
docker build -f python.Dockerfile -t py-hello ..
docker images py-hello
```

Expected: ~1GB (Python 3.12 slim + runtime)

## Build PyAOT Image

```bash
# First compile binary
cd ../..
pyaot --binary examples/hello_world_simple.py -o examples/docker/app

# Then build image
cd examples/docker
docker build -f pyaot.Dockerfile -t pyaot-hello .
docker images pyaot-hello
```

Expected: <1MB (just binary)

## Compare

```bash
docker images | grep hello
```

You should see:
```
pyaot-hello  latest  524KB
py-hello     latest  1.04GB
```

**Size reduction: ~2000x**

## Run Both

```bash
# Python
docker run --rm py-hello

# PyAOT
docker run --rm pyaot-hello
```

Both produce same output, but PyAOT image is 2000x smaller.
