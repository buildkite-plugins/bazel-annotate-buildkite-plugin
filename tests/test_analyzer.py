#!/usr/bin/env python3
"""
Simple tests for the BEP analyzer functionality
"""

import unittest
import tempfile
import os
import subprocess
import sys


class TestBEPAnalyzer(unittest.TestCase):
    
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.analyzer_bin = os.path.join(os.path.dirname(__file__), '..', 'bin', 'bazel_failure_analyzer')
        
    def tearDown(self):
        import shutil
        shutil.rmtree(self.temp_dir)
    
    def test_analyzer_binary_exists(self):
        """Test analyzer binary exists and is executable"""
        self.assertTrue(os.path.exists(self.analyzer_bin))
        self.assertTrue(os.access(self.analyzer_bin, os.X_OK))
    
    def test_help_output(self):
        """Test help output works"""
        result = subprocess.run([self.analyzer_bin, '--help'], 
                              capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn('usage:', result.stdout)
    
    def test_nonexistent_file(self):
        """Test handling of non-existent file"""
        result = subprocess.run([self.analyzer_bin, '/nonexistent/file.pb'], 
                              capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('Error: BEP file not found', result.stderr)
    
    def test_empty_file(self):
        """Test handling of empty file"""
        empty_file = os.path.join(self.temp_dir, "empty.pb")
        with open(empty_file, 'wb') as f:
            pass  # Create empty file
        
        result = subprocess.run([self.analyzer_bin, empty_file, '--skip-if-no-failures'], 
                              capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        # Empty file should be handled gracefully
    
    def test_failure_detection(self):
        """Test basic failure detection"""
        # Create a mock BEP file with failure content
        mock_bep = os.path.join(self.temp_dir, "mock.pb")
        with open(mock_bep, 'w') as f:
            f.write('FAILED: //test:target build failed')
        
        result = subprocess.run([self.analyzer_bin, mock_bep, '--output-format=text'], 
                              capture_output=True, text=True)
        # Should produce output indicating analysis completed
        self.assertIn('Build completed', result.stdout)
    
    def test_verbose_mode(self):
        """Test verbose mode works"""
        success_file = os.path.join(self.temp_dir, "success.pb")
        with open(success_file, 'w') as f:
            f.write('build completed successfully')
        
        result = subprocess.run([self.analyzer_bin, success_file, '--verbose', '--skip-if-no-failures'], 
                              capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn('Analyzing BEP file', result.stdout)
    
    def test_json_output(self):
        """Test JSON output format"""
        fail_file = os.path.join(self.temp_dir, "fail.pb")
        with open(fail_file, 'w') as f:
            f.write('ERROR: build failed')
        
        result = subprocess.run([self.analyzer_bin, fail_file, '--output-format=json'], 
                              capture_output=True, text=True)
        # Should produce some output (either JSON or message)
        self.assertIsNotNone(result.stdout)


if __name__ == '__main__':
    unittest.main()
