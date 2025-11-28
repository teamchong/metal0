# Docker Size Comparison

Compare Python vs metal0 Docker image sizes.

## Build Python Image

```bash
cd examples/docker
docker build -f python.Dockerfile -t py-hello ..
docker images py-hello
```

Expected: ~1GB (Python 3.12 slim + runtime)

## Build metal0 Image

```bash
# First compile binary
cd ../..
metal0 --binary examples/hello_world_simple.py -o examples/docker/app

# Then build image
cd examples/docker
docker build -f metal0.Dockerfile -t metal0-hello .
docker images metal0-hello
```

Expected: <1MB (just binary)

## Compare

```bash
docker images | grep hello
```

You should see:
```
metal0-hello  latest  524KB
py-hello     latest  1.04GB
```

**Size reduction: ~2000x**

## Run Both

```bash
# Python
docker run --rm py-hello

# metal0
docker run --rm metal0-hello
```

Both produce same output, but metal0 image is 2000x smaller.
