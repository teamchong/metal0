{
  "targets": [{
    "target_name": "lanceql",
    "sources": ["src/binding.cc"],
    "include_dirs": [
      "<!@(node -p \"require('node-addon-api').include\")"
    ],
    "defines": ["NAPI_DISABLE_CPP_EXCEPTIONS"],
    "cflags!": ["-fno-exceptions"],
    "cflags_cc!": ["-fno-exceptions"],
    "cflags_cc": ["-std=c++17"],
    "conditions": [
      ["OS=='mac'", {
        "xcode_settings": {
          "GCC_ENABLE_CPP_EXCEPTIONS": "YES",
          "CLANG_CXX_LIBRARY": "libc++",
          "CLANG_CXX_LANGUAGE_STANDARD": "c++17",
          "MACOSX_DEPLOYMENT_TARGET": "10.15"
        }
      }],
      ["OS=='linux'", {
        "cflags_cc": ["-std=c++17", "-fPIC"],
        "libraries": ["-ldl"]
      }],
      ["OS=='win'", {
        "msvs_settings": {
          "VCCLCompilerTool": {
            "ExceptionHandling": 1,
            "AdditionalOptions": ["/std:c++17"]
          }
        }
      }]
    ]
  }]
}
