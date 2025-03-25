# Bazel BEP Annotate Buildkite Plugin

A Buildkite plugin that creates rich annotations from Bazel Event Protocol (BEP) output files, providing at-a-glance build status, test results, and performance information.

![Build status](https://badge.buildkite.com/d673030645c7f3e7e397affddd97cfe9f93a40547ed17b6dc5.svg)

## Features

- 📊 Parses Bazel Event Protocol (BEP) output files
- ✅ Displays build status with success/failure counts
- ⏱️ Shows test durations and highlights slow tests
- ❌ Provides detailed failure information with error logs
- 🔄 Automatically detects BEP files based on Bazel commands
- 💡 Includes random developer wisdom quotes for inspiration

## Prerequisites

This plugin requires:
- Bash
- jq (for JSON parsing)
- bc (for floating point calculations)

## Options

### `bep_file` (optional)

Path to the Bazel Event Protocol JSON file to parse. If not provided, the plugin will attempt to:
1. Extract it from the `bazel_command` if provided
2. Look for files at common locations (bazel-events.json, bazel-bep.json, bep.json)

### `bazel_command` (optional)

The original Bazel command that was run. This is used for display purposes and can also be used to extract the BEP file path if it contains a `--build_event_json_file` flag.

### `skip_if_no_bep` (optional, boolean)

If set to `true`, the plugin will exit successfully if no BEP file is found, instead of failing the build.
Default: `false`

## Examples

### Basic usage with explicit BEP file

```yaml
steps:
  - label: "🔨 Build with Bazel"
    command: |
      bazel build //... --build_event_json_file=bazel-events.json
    plugins:
      - bazel-bep-annotate#v1.0.0:
          bep_file: bazel-events.json
```

### Automatic BEP detection from Bazel command

```yaml
steps:
  - label: "🔨 Build with Bazel"
    command: |
      bazel build //... --build_event_json_file=bazel-events.json
    plugins:
      - bazel-bep-annotate#v1.0.0:
          bazel_command: "bazel build //... --build_event_json_file=bazel-events.json"
```

### Skip annotations if no BEP file found

```yaml
steps:
  - label: "🔨 Build with Bazel"
    command: |
      # Command might not produce a BEP file
      bazel build //...
    plugins:
      - bazel-bep-annotate#v1.0.0:
          skip_if_no_bep: true
```

## Common Use Cases

### Running tests with annotations

```yaml
steps:
  - label: "🧪 Run Bazel tests"
    command: |
      bazel test //... --build_event_json_file=bazel-test-events.json
    plugins:
      - bazel-bep-annotate#v1.0.0:
          bep_file: bazel-test-events.json
```

### Running builds with annotations in a custom Bazel workspace

```yaml
steps:
  - label: "🔨 Build with Bazel (custom workspace)"
    command: |
      cd my-workspace
      bazel build //... --build_event_json_file=bazel-events.json
    plugins:
      - bazel-bep-annotate#v1.0.0:
          bep_file: my-workspace/bazel-events.json
```

## How It Works

1. After your Bazel command runs, the plugin looks for the BEP file
2. It parses the BEP data to extract build status, test results, and performance metrics
3. It creates a detailed Buildkite annotation with this information
4. The annotation shows success/failure status, test performance, and detailed error logs

## Troubleshooting

### The plugin can't find the BEP file

Make sure:
1. The Bazel command has completed successfully
2. You've specified the `--build_event_json_file` flag in your Bazel command
3. The path to the BEP file is correct and accessible to the build agent

### The annotation doesn't show all targets

The BEP file might not contain complete information. Try running Bazel with additional flags:
```
--experimental_build_event_text_file_path_conversion=true
```

## ⚒ Developing

You can use the [bk cli](https://github.com/buildkite/cli) to run the plugin locally:

```bash
bk local run
```

## 👩‍💻 Contributing

1. Fork the repository
2. Create a feature branch
3. Add your changes, including tests
4. Submit a pull request

## 📜 License

The package is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
