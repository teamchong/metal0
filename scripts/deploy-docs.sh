#!/bin/bash
# Deploy docs to Cloudflare Pages
# Usage: ./scripts/deploy-docs.sh

set -e

echo "Deploying metal0 docs to Cloudflare Pages..."

# Upload LanceQL assets to R2 first (one-time or when updated)
upload_lanceql_assets() {
    echo "Uploading LanceQL assets to R2..."
    aws s3 cp ../lanceql/packages/browser/dist/lanceql.wasm s3://metal0-data/lanceql/lanceql.wasm \
        --profile r2 \
        --endpoint-url https://36498dc359676cbbcf8c3616e6c07e94.r2.cloudflarestorage.com \
        --content-type application/wasm

    aws s3 cp ../lanceql/packages/browser/dist/lanceql.esm.js s3://metal0-data/lanceql/lanceql.esm.js \
        --profile r2 \
        --endpoint-url https://36498dc359676cbbcf8c3616e6c07e94.r2.cloudflarestorage.com \
        --content-type application/javascript
}

# Deploy docs to Pages
deploy_pages() {
    wrangler pages deploy docs --project-name=metal0
}

case "${1:-deploy}" in
    assets)
        upload_lanceql_assets
        ;;
    deploy)
        deploy_pages
        ;;
    all)
        upload_lanceql_assets
        deploy_pages
        ;;
    *)
        echo "Usage: $0 [assets|deploy|all]"
        exit 1
        ;;
esac
