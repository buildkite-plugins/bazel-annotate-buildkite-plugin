#!/usr/bin/env python3
"""
Generate large BEP protobuf files for performance testing.

This script creates realistic-looking BEP protobuf files with:
- Realistic file paths and line numbers for GitHub linking
- Various error types (compilation, test failures, BUILD errors)
- Multiple programming languages (C++, Python, Java, Go, etc.)
- Proper Bazel target structures

The generated failures include file locations that the analyzer can 
parse to create clickable GitHub links in Buildkite annotations.
"""

import argparse
import struct
import sys
from pathlib import Path
import time


def encode_varint(value):
    """Encode an integer as a varint."""
    result = []
    while value >= 0x80:
        result.append((value & 0x7F) | 0x80)
        value >>= 7
    result.append(value)
    return bytes(result)


def create_build_event_message(target_name: str, success: bool = True, target_index: int = 0) -> bytes:
    """Create a mock BEP message for a build target with realistic error messages."""
    if success:
        content = f"""
{{
  "id": {{
    "targetCompleted": {{
      "label": "{target_name}"
    }}
  }},
  "completed": {{
    "success": true
  }}
}}
"""
    else:
        # Create realistic compilation errors with file paths and line numbers
        pkg_path = target_name.split(':')[0].lstrip('//')
        error_types = [
            f"{pkg_path}/main.cpp:{42 + (target_index % 100)}:{15 + (target_index % 20)}: error: use of undeclared identifier 'undefined_var_{target_index}'",
            f"{pkg_path}/utils.h:{25 + (target_index % 50)}:8: error: 'missing_function' was not declared in this scope",
            f"{pkg_path}/parser.cc:{78 + (target_index % 30)}:12: error: no matching function for call to 'parse_{target_index}'",
            f"BUILD:{10 + (target_index % 20)}:1: name 'undefined_dependency_{target_index}' is not defined",
            f"{pkg_path}/config.py:{33 + (target_index % 40)}:5: SyntaxError: invalid syntax near 'broken_code_{target_index}'",
            f"{pkg_path}/lib.java:{91 + (target_index % 60)}:20: error: cannot find symbol variable missing_var_{target_index}",
        ]
        
        selected_error = error_types[target_index % len(error_types)]
        
        content = f"""
{{
  "id": {{
    "targetCompleted": {{
      "label": "{target_name}"
    }}
  }},
  "completed": {{
    "success": false
  }},
  "aborted": {{
    "reason": "BUILD_FAILED",
    "description": "{selected_error}"
  }}
}}
"""
    return content.encode('utf-8')


def create_test_event_message(target_name: str, success: bool = True, target_index: int = 0) -> bytes:
    """Create a mock BEP message for a test target with realistic test failures."""
    if success:
        content = f"""
{{
  "id": {{
    "testResult": {{
      "label": "{target_name}"
    }}
  }},
  "testResult": {{
    "status": "PASSED"
  }}
}}
"""
    else:
        # Create realistic test failure messages with file paths and line numbers
        pkg_path = target_name.split(':')[0].lstrip('//')
        test_errors = [
            f"{pkg_path}/test_main.py:{45 + (target_index % 80)}:12: AssertionError: Expected {5 + target_index} but got {3 + target_index}",
            f"{pkg_path}/unit_tests.cpp:{67 + (target_index % 60)}:8: EXPECT_EQ failed: expected value_{target_index} == actual_value_{target_index}",
            f"{pkg_path}/integration_test.java:{89 + (target_index % 40)}:15: junit.framework.AssertionFailedError: Test failed at step {target_index}",
            f"{pkg_path}/test_utils.go:{23 + (target_index % 50)}:5: panic: runtime error: index out of range [{target_index}]",
            f"{pkg_path}/spec_test.rb:{56 + (target_index % 70)}:10: RSpec::Expectations::ExpectationNotMetError: expected behavior_{target_index}",
            f"{pkg_path}/test_runner.kt:{34 + (target_index % 90)}:7: kotlin.test.AssertionError: Test {target_index} assertion failed",
        ]
        
        selected_error = test_errors[target_index % len(test_errors)]
        
        content = f"""
{{
  "id": {{
    "testResult": {{
      "label": "{target_name}"
    }}
  }},
  "testResult": {{
    "status": "FAILED",
    "testAttemptDurationMillis": "1000"
  }},
  "testFailureMessage": "{selected_error}"
}}
"""
    return content.encode('utf-8')


def generate_large_bep_file(output_path: str, num_targets: int, failure_rate: float = 0.05):
    """Generate a large BEP protobuf file with specified number of targets."""
    print(f"🔧 Generating BEP file with {num_targets:,} targets...")
    start_time = time.time()
    
    with open(output_path, 'wb') as f:
        # Write header events
        header_msg = b'{"started": {"uuid": "test-build-id", "startTime": {"seconds": 1642000000}}}'
        f.write(encode_varint(len(header_msg)))
        f.write(header_msg)
        
        # Generate target events
        num_failures = 0
        for i in range(num_targets):
            # Determine if this should be a failure
            is_failure = (i % int(1 / failure_rate)) == 0 if failure_rate > 0 else False
            if is_failure:
                num_failures += 1
            
            # Create target name
            pkg_num = i // 50  # 50 targets per package
            target_name = f"//pkg{pkg_num:04d}:target{i:06d}"
            
            # Alternate between build and test events
            if i % 2 == 0:
                message = create_build_event_message(target_name, not is_failure, i)
            else:
                message = create_test_event_message(target_name, not is_failure, i)
            
            # Write varint-delimited message
            f.write(encode_varint(len(message)))
            f.write(message)
            
            # Progress indicator
            if (i + 1) % 10000 == 0:
                print(f"  Generated {i + 1:,} targets...")
        
        # Write completion event
        completion_msg = f'{{"finished": {{"exitCode": {{"code": {"1" if num_failures > 0 else "0"}}}}}}}'.encode('utf-8')
        f.write(encode_varint(len(completion_msg)))
        f.write(completion_msg)
    
    elapsed = time.time() - start_time
    file_size = Path(output_path).stat().st_size
    
    print(f"✅ Generated {output_path}")
    print(f"   📊 Targets: {num_targets:,}")
    print(f"   ❌ Failures: {num_failures:,} ({failure_rate*100:.1f}%)")
    print(f"   📁 Size: {file_size / 1024 / 1024:.1f} MB")
    print(f"   ⏱️  Time: {elapsed:.2f}s")


def main():
    parser = argparse.ArgumentParser(
        description="Generate large BEP protobuf files for testing",
        epilog="""
Examples:
  # Generate 1000 targets with 5%% failures
  ./generate_large_bep_files.py large-test.pb --targets 1000
  
  # Generate 50000 targets with 10%% failures for stress testing
  ./generate_large_bep_files.py stress-test.pb --targets 50000 --failure-rate 0.10
  
  # Test GitHub linking with realistic errors
  BUILDKITE_REPO="https://github.com/owner/repo.git" BUILDKITE_COMMIT="main" \\
  ./bin/bazel_failure_analyzer large-test.pb --verbose
        """,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("output", help="Output file path")
    parser.add_argument("--targets", type=int, required=True, help="Number of targets to generate")
    parser.add_argument("--failure-rate", type=float, default=0.05, 
                       help="Fraction of targets that should fail (default: 0.05)")
    
    args = parser.parse_args()
    
    if args.failure_rate < 0 or args.failure_rate > 1:
        print("Error: failure-rate must be between 0 and 1", file=sys.stderr)
        return 1
    
    generate_large_bep_file(args.output, args.targets, args.failure_rate)
    return 0


if __name__ == "__main__":
    sys.exit(main())
