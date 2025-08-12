# Bazel BEP Failure Analyzer Buildkite Plugin [![Build status](https://badge.buildkite.com/522d5a765d9856d57c8ce69162540279b81db9d2852b5f7060.svg?branch=main)](https://buildkite.com/buildkite/plugins-bazel-annotate)

A **fast** Buildkite plugin that analyzes Bazel Event Protocol (BEP) protobuf files and creates focused annotations for build failures. Uses native protobuf parsing for maximum performance.

## Features

- ⚡ **Fast protobuf parsing** - Handles 100k+ targets in seconds
- 🎯 **Failure-focused** - Only shows what developers need to see  
- 🔗 **GitHub linking** - Links directly to failing source code lines
- 🔍 **Auto-detection** - Automatically finds BEP protobuf files
- 📦 **Zero dependencies** - Self-contained Python binary
- 🚨 **Clear annotations** - Clean, actionable failure information
- 🛠️ **Bazel-native** - Uses Bazel's native protobuf BEP format

## Prerequisites

This plugin requires:
- Bash
- Python 3
- Bazel (for generating BEP files)

## Options

### `bep_file` (optional)

Path to the Bazel Event Protocol protobuf file to parse. If not provided, the plugin will look for files at common locations (bazel-events.pb, bazel-bep.pb, bep.pb, events.pb).

### `skip_if_no_bep` (optional, boolean)

If set to `true`, the plugin will exit successfully if no BEP file is found, instead of failing the build.
Default: `false`

## Processing Limits

To ensure reliable performance and prevent memory issues, the plugin enforces these limits:

- **File size**: 100MB maximum BEP file size (configurable with `--max-file-size`)
- **Failure count**: 50 failures maximum per build (configurable with `--max-failures`)
- **Annotation size**: 1MB maximum per annotation (Buildkite's platform limit)

When limits are exceeded, the plugin will display clear warnings and continue with truncated results.

## Examples

### Basic usage with explicit BEP file

```yaml
steps:
  - label: "🔨 Build with Bazel"
    command: |
      bazel build //... --build_event_binary_file=bazel-events.pb
    plugins:
      - bazel-annotate#v0.1.2:
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
      - bazel-annotate#v0.1.2:
          skip_if_no_bep: true
```

## Common Use Cases

### Running tests with annotations

```yaml
steps:
  - label: "🧪 Run Bazel tests"
    command: |
      bazel test //... --build_event_binary_file=bazel-test-events.pb
    plugins:
      - bazel-annotate#v0.1.2:
          bep_file: bazel-test-events.pb
```

### Running builds with annotations in a custom Bazel workspace

```yaml
steps:
  - label: "🔨 Build with Bazel (custom workspace)"
    command: |
      cd my-workspace
      bazel build //... --build_event_binary_file=bazel-events.pb
    plugins:
      - bazel-annotate#v0.1.2:
          bep_file: my-workspace/bazel-events.pb
```

### Multiple Bazel jobs in a pipeline with consolidated annotations

```yaml
steps:
  - label: "🔨 Build with Bazel"
    command: |
      bazel build //... --build_event_binary_file=bazel-build-events.pb
    plugins:
      - bazel-annotate#v0.1.2:
          bep_file: bazel-build-events.pb
          
  - label: "🧪 Test with Bazel"
    command: |
      bazel test //... --build_event_binary_file=bazel-test-events.pb
    plugins:
      - bazel-annotate#v0.1.2:
          bep_file: bazel-test-events.pb
          
  - label: "📦 Package with Bazel"
    command: |
      bazel run //:package --build_event_binary_file=bazel-package-events.pb
    plugins:
      - bazel-annotate#v0.1.2:
          bep_file: bazel-package-events.pb
```

## Compatibility

| Elastic Stack | Agent Stack K8s | Hosted (Mac) | Hosted (Linux) | Notes |
| :-----------: | :-------------: | :----: | :----: |:---- |
| 📝 | 📝 | ✅ | 📝 | See below|

- ✅ Full supported
- 📝 Agents running on Linux or Kubernetes will need to have Bazel made available via installation

## 👩‍💻 Contributing

1. Fork the repository
2. Create a feature branch
3. Add your changes, including tests
4. Submit a pull request

## 📜 License

The package is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
