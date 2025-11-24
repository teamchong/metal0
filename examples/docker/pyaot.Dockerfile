# PyAOT Docker Image - FROM SCRATCH
FROM scratch

# Copy pre-compiled binary (no runtime needed)
COPY app /app

# Run binary directly
CMD ["/app"]

# Expected size: <1MB
# Includes: Just your compiled application
# No Python, no pip, no dependencies
