# GitHub Actions Setup Guide

This document explains the GitHub Actions CI/CD setup for FasterBASIC.

## Overview

FasterBASIC uses GitHub Actions to automatically build the compiler for multiple platforms and create releases when tags are pushed.

## Automated Builds

Every push to the `main` branch triggers builds for:

- **macOS ARM64** (Apple Silicon M1/M2/M3)
- **macOS x86_64** (Intel Macs)
- **Linux x86_64**

### Build Process

For each platform, the workflow:

1. Checks out the repository
2. Installs required dependencies
3. Runs the build script (`qbe_basic_integrated/build_qbe_basic.sh`)
4. Verifies the build by compiling and running a test program
5. Packages the compiler with runtime files and documentation
6. Uploads the build artifacts (retained for 90 days)

### Viewing Build Status

Check the build status at: https://github.com/albanread/FasterBASIC/actions

The README.md displays a build status badge at the top.

## Creating Releases

### Automatic Release Creation

When you push a version tag (e.g., `v1.0.0`), GitHub Actions will:

1. Build binaries for all supported platforms
2. Run tests to verify each build
3. Create a GitHub Release with all artifacts
4. Generate comprehensive release notes

### Manual Release Process

#### Using the Helper Script (Recommended)

```bash
# Interactive mode
./scripts/create_release.sh

# Direct version specification
./scripts/create_release.sh 1.0.0
```

The script will:
- Validate you're on the right branch with no uncommitted changes
- Check version format (must be X.Y.Z)
- Prompt for release notes
- Create an annotated git tag
- Push the tag to GitHub
- Trigger the automated release workflow

#### Manual Tag Creation

If you prefer to create tags manually:

```bash
# Create annotated tag
git tag -a v1.0.0 -m "Release version 1.0.0

- Feature 1
- Feature 2
- Bug fixes"

# Push tag to GitHub
git push origin v1.0.0
```

### Release Artifacts

Each release includes three platform-specific archives:

1. **fasterbasic-macos-arm64.tar.gz** - Apple Silicon
2. **fasterbasic-macos-x86_64.tar.gz** - Intel Mac
3. **fasterbasic-linux-x86_64.tar.gz** - Linux

Each archive contains:
- `fbc_qbe` - The compiler executable
- `qbe_basic` - Symlink for backward compatibility
- `runtime/` - Runtime library source files
- `README.md` - Project documentation
- `README.txt` - Quick start guide with usage examples
- `LICENSE` - License file (if present)

### Release Notes

The workflow automatically generates release notes including:

- Download links for each platform
- Installation instructions
- Quick start examples
- Links to documentation wiki
- Feature highlights
- System requirements

## Workflow Configuration

### Workflow File

`.github/workflows/build.yml`

### Triggers

The workflow runs on:

- **Push to main branch** - Builds and uploads artifacts
- **Pull requests to main** - Builds to verify changes
- **Tag pushes (v*)** - Creates releases
- **Manual dispatch** - Can be triggered manually from GitHub UI

### Platform-Specific Runners

- **macOS ARM64**: `macos-latest` (Apple Silicon)
- **macOS x86_64**: `macos-13` (Intel)
- **Linux x86_64**: `ubuntu-latest`

### Build Dependencies

The workflow automatically installs:

- **macOS**: Xcode command line tools (included)
- **Linux**: `build-essential`, `clang`

No additional setup is required - dependencies are installed automatically.

## Troubleshooting

### Build Failures

If a build fails:

1. Check the Actions tab: https://github.com/albanread/FasterBASIC/actions
2. Click on the failed workflow run
3. Expand the failed step to see error details
4. Common issues:
   - Missing source files (check paths)
   - Compilation errors (test locally first)
   - Test failures (verify test programs work)

### Testing Locally Before Release

Before creating a release, test the build locally:

```bash
# Clean build
cd qbe_basic_integrated
./build_qbe_basic.sh --clean
./build_qbe_basic.sh

# Run tests
cd ..
./run_tests.sh

# Test a simple program
echo 'PRINT "Hello, World!"' > test.bas
echo 'END' >> test.bas
./qbe_basic_integrated/fbc_qbe test.bas -o test
./test
```

### Deleting a Release

If you need to delete a release:

```bash
# Delete local tag
git tag -d v1.0.0

# Delete remote tag
git push origin :refs/tags/v1.0.0

# Delete the GitHub release
# Go to: https://github.com/albanread/FasterBASIC/releases
# Click on the release, then "Delete" button
```

## Best Practices

### Version Numbers

Follow semantic versioning (X.Y.Z):

- **X (Major)**: Breaking changes, major new features
- **Y (Minor)**: New features, backward compatible
- **Z (Patch)**: Bug fixes, minor improvements

Examples: `v1.0.0`, `v1.1.0`, `v1.1.1`

### Release Frequency

- Create releases for significant milestones
- Don't create releases for every commit
- Consider pre-releases (`v1.0.0-beta.1`) for testing

### Release Notes

Good release notes include:

- **What's New**: New features and improvements
- **Bug Fixes**: Issues resolved
- **Breaking Changes**: Changes requiring user action
- **Known Issues**: Current limitations
- **Documentation**: Links to relevant docs

Example:

```
Release 1.0.0

What's New:
- Full OOP support with classes and inheritance
- HashMap and List collections
- NEON SIMD acceleration on ARM64

Bug Fixes:
- Fixed memory leak in string handling
- Resolved crash in nested exception handlers

Breaking Changes:
- None

Documentation:
- Updated wiki with OOP examples
- Added NEON SIMD guide

Known Issues:
- Graphics integration pending (see Superterminal)
```

### Testing Before Release

Always test before creating a release:

1. Run the full test suite: `./run_tests.sh`
2. Test on target platforms if possible
3. Verify documentation is up to date
4. Check that README.md reflects current features
5. Ensure examples compile and run correctly

## Monitoring Builds

### GitHub Actions Dashboard

View all workflow runs: https://github.com/albanread/FasterBASIC/actions

Features:
- Filter by workflow, branch, or event
- View logs for each step
- Download build artifacts
- Re-run failed workflows

### Notifications

GitHub sends notifications for:
- Failed workflows (if you're the committer)
- Successful releases
- Manual workflow dispatches

Configure notifications in GitHub settings: Settings → Notifications

## Future Improvements

Potential enhancements to the CI/CD pipeline:

- **ARM64 Linux builds**: Add when GitHub provides ARM runners
- **Windows builds**: Add Windows support
- **Automated testing**: Expand test coverage in CI
- **Performance benchmarks**: Track performance across builds
- **Code coverage**: Measure test coverage
- **Deployment**: Automated deployment to package managers

## Additional Resources

- **GitHub Actions Documentation**: https://docs.github.com/en/actions
- **Workflow Syntax**: https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions
- **FasterBASIC Wiki**: https://github.com/albanread/FasterBASIC/wiki
- **Project README**: [../README.md](../README.md)

## Support

For issues with the CI/CD pipeline:

1. Check existing GitHub Issues
2. Review workflow logs
3. Test locally to isolate the problem
4. Create a new issue with details and logs

For general FasterBASIC support, see the main README.md.