# Contributing to Volumio

First off, thank you for considering contributing to Volumio. It's people like you that make Volumio such a great tool.

Following these guidelines helps to communicate that you respect the time of the developers managing and developing this project. In return, they should reciprocate that respect in addressing your issue, assessing changes, and helping you finalize your pull requests.

## How Can I Contribute?

### Getting Started

To get started with contributing to Volumio, follow these steps:

1. Prepare your development environment and ensure you have installed all the required packages listed in the README.md file.
2. Fork this repository
3. Create a feature branch from the appropriate base branch (see Branch Strategy below)

### Branch Strategy

The `master` branch is protected and represents the production-ready state.

**For external contributors (fork workflow):**
```
your-fork/feature-branch -> PR -> volumio/common (or other feature branch)
```

**For maintainers (release workflow):**
```
volumio/common -> PR -> volumio/master
```

**Important:** PRs from forks cannot target `master` directly. Target a feature branch instead (common, pi, amd64, etc.).

### Pull Requests

The process described here has several goals:

- Maintain Volumio's quality
- Fix problems that are important to users
- Engage the community in working toward the best possible Volumio
- Enable a sustainable system for Volumio's maintainers to review contributions

Please follow these steps to have your contribution considered by the maintainers:

1. Follow all instructions in this guide
2. Ensure your commits follow the commit message format (see below)
3. Before you submit your pull request, test your changes carefully with a full build
4. After you submit your pull request, verify that all status checks are passing

### Small Pull Requests

In order to streamline the review process and make it easier for us to integrate your changes, we prefer small pull requests. This means that each pull request should contain changes related to a single feature or bug fix. If you have made multiple changes, please split them into separate pull requests.

## Commit Message Format

All commits must follow semantic commit format. This is enforced by CI.

### Format

```
type: description
type/ description
type(scope): description
```

Spacing around the separator (`:` or `/`) is flexible.

### Allowed Types

| Type       | Description                                      |
|------------|--------------------------------------------------|
| fix        | Bug fixes                                        |
| feat       | New features                                     |
| docs       | Documentation changes                            |
| chore      | Maintenance, dependencies, cleanup               |
| refactor   | Code restructuring without behavior change       |
| test       | Adding or updating tests                         |
| build      | Build system, recipes, makefiles                 |
| ci         | CI/CD configuration (GitHub Actions, etc.)       |
| perf       | Performance improvements                         |
| revert     | Reverting previous commits                       |
| hotfix     | Critical production fixes (maintainers)          |
| emergency  | Emergency fixes (maintainers)                    |

### Examples

```
fix: resolve plymouth rotation on SPI displays
feat(pi): add support for Waveshare 3.5" display
docs/ update installation instructions
refactor(initramfs): simplify module loading sequence
build: update kernel version for pi recipe
ci: fix shellcheck workflow for PRs
perf: reduce SPI display detection time
revert: undo breaking change in boot sequence
hotfix: critical boot failure on Pi 5
emergency: production boot loop fix
```

### Scopes (Optional)

Scopes provide additional context. Common scopes:

- `pi`, `amd64`, `common` - device/architecture specific
- `initramfs`, `plymouth`, `build` - subsystem specific
- `critical`, `emergency` - for override commits to master

## Code Style

### Shell Scripts

Shell scripts are automatically checked by shellcheck and shfmt. Ensure your scripts pass these checks before submitting.

Run locally:
```bash
shellcheck your-script.sh
shfmt -l your-script.sh
```

## Community

You can chat with the core team on [our community](https://community.volumio.com/)

## Questions?

If you have questions about the contribution process, please open an issue or ask in the community forums.
