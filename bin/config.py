#!/usr/bin/env python3
"""
Configuration and constants for the Bazel Failure Analyzer.
"""

# Default limits and thresholds
MAX_FILE_SIZE_MB_DEFAULT = 100  # Default max BEP file size in MB
MAX_FAILURES_DEFAULT = 50       # Maximum number of failures to collect
MAX_MESSAGE_SIZE = 5000         # Maximum size of individual failure messages (chars)
MAX_ERROR_LINES = 10            # Maximum lines per error message
MAX_STRINGS_PER_EVENT = 20      # Maximum strings to extract per protobuf event
MAX_VARINT_BYTES = 10           # Maximum bytes for protobuf varint

# Annotation
BUILDKITE_ANNOTATION_STYLE = "error"
BUILDKITE_ANNOTATION_CONTEXT_FALLBACK = "bazel-failures"

# Retry policy for Buildkite annotation creation
ANNOTATION_RETRY_ATTEMPTS = 3
ANNOTATION_RETRY_BASE_DELAY_SECONDS = 1.0  # exponential backoff base
