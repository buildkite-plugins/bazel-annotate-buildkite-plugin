# Bazel BEP Failure Analyzer Buildkite Plugin [![Build status](https://badge.buildkite.com/522d5a765d9856d57c8ce69162540279b81db9d2852b5f7060.svg?branch=main)](https://buildkite.com/buildkite/plugins-bazel-annotate)

A fast Buildkite plugin that analyzes Bazel Event Protocol (BEP) protobuf files and creates focused annotations for build failures. Prefers native protobuf parsing when available for accuracy and performance, with a safe string-based fallback.

## Features

- ⚡ Fast BEP processing — scales to very large builds
- 🎯 Failure-focused — concise, actionable failure details
- 🔗 GitHub linking — direct links to failing files/lines
- 🔍 Auto-detection — finds BEP files in common locations
- 🧰 Minimal deps — requires Bash and Python 3; protobuf is optional
- 🚨 Clear annotations — designed for Buildkite’s annotation UI
- 🛠️ Bazel-native — understands Bazel BEP failure types
- 🔁 Robust — retries annotation creation on transient errors

## Prerequisites

- Bash
- Python 3
- Bazel (to generate BEP files)
- Optional: Python `protobuf` package (recommended for best parsing)

> Without `protobuf`, the analyzer falls back to string-based parsing.

## Plugin Options

### `bep_file` (optional)
Path to the Bazel Event Protocol protobuf file to parse. If not provided, the plugin looks for common filenames: `bazel-events.pb`, `bazel-bep.pb`, `bep.pb`, `events.pb`.

### `skip_if_no_bep` (optional, boolean)
If `true`, the plugin exits successfully when no BEP file is found.
Default: `false`

## Processing Limits and Behavior

To ensure reliability and prevent memory issues, the analyzer enforces limits (configurable):

- File size: 100MB max BEP file size (`--max-file-size` in MB)
- Failure count: 50 failures max (`--max-failures`)
- Annotation size: 1MB (Buildkite platform limit)

When limits are exceeded, warnings are logged and results are truncated safely. Defaults are defined in [`bin/config.py`](bin/config.py).

## Examples

### Basic usage with explicit BEP file

```yaml
steps:
  - label: "🔨 Build with Bazel"
    command: |
      bazel build //... --build_event_binary_file=bazel-events.pb
    plugins:
      - bazel-annotate#v1.0.0:
          bep_file: bazel-events.pb
```

### Skip annotations if no BEP file found

```yaml
steps:
  - label: "🔨 Build with Bazel"
    command: |
      # Command might not produce a BEP file
      bazel build //...
    plugins:
      - bazel-annotate#v1.0.0:
          skip_if_no_bep: true
```

### Running tests with annotations

```yaml
steps:
  - label: "🧪 Run Bazel tests"
    command: |
      bazel test //... --build_event_binary_file=bazel-test-events.pb
    plugins:
      - bazel-annotate#v1.0.0:
          bep_file: bazel-test-events.pb
```

### Multiple Bazel jobs in a pipeline with separate annotations

```yaml
steps:
  - label: "🔨 Build with Bazel"
    command: |
      bazel build //... --build_event_binary_file=bazel-build-events.pb
    plugins:
      - bazel-annotate#v1.0.0:
          bep_file: bazel-build-events.pb
          
  - label: "🧪 Test with Bazel"
    command: |
      bazel test //... --build_event_binary_file=bazel-test-events.pb
    plugins:
      - bazel-annotate#v1.0.0:
          bep_file: bazel-test-events.pb
          
  - label: "📦 Package with Bazel"
    command: |
      bazel run //:package --build_event_binary_file=bazel-package-events.pb
    plugins:
      - bazel-annotate#v1.0.0:
          bep_file: bazel-package-events.pb
```

## Development

- Run shell tests in Docker:

```bash
docker compose run --rm tests bats tests
```

- Run Python unit tests locally:

```bash
python3 -m unittest -v tests/test_analyzer.py
```

- Linting and Shellcheck are covered in the Buildkite pipeline for the plugin (see `.buildkite/pipeline.yml`).

## Compatibility

| Elastic Stack | Agent Stack K8s | Hosted (Mac) | Hosted (Linux) | Notes |
| :-----------: | :-------------: | :----------: | :------------: | :---- |
| 📝            | 📝              | ✅           | 📝             | Agents on Linux/K8s need Bazel available |

- ✅ Fully supported
- 📝 Agents running on Linux or Kubernetes must provide Bazel

## 👩‍💻 Contributing

1. Fork the repository
2. Create a feature branch
3. Add your changes, including tests
4. Submit a pull request

## 📜 License

The package is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
