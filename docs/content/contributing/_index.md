---
title: "Contributing"
weight: 3
---

We welcome contributions from everyone! Whether you want to report a bug, suggest a feature, or submit code changes, we appreciate your help.

## Getting Started

### Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork locally:

```bash
git clone https://github.com/YOUR_USERNAME/deadfinder.git
cd deadfinder
```

3. Add the upstream repository:

```bash
git remote add upstream https://github.com/hahwul/deadfinder.git
```

### Development Setup

1. Install Ruby 3.4+ (officially supported, but 3.2+ works)
2. Install dependencies:

```bash
bundle install
```

3. Run tests to verify setup:

```bash
bundle exec rspec
```

4. Run linter:

```bash
bundle exec rubocop
```

## Making Changes

### Create a Branch

Create a new branch for your feature or bug fix:

```bash
git checkout -b feature/awesome-feature
# or
git checkout -b bugfix/annoying-bug
```

### Code Style

DeadFinder follows Ruby community conventions:

- Use 2 spaces for indentation
- Follow the [Ruby Style Guide](https://rubystyle.guide/)
- Run RuboCop before committing:

```bash
bundle exec rubocop
```

Fix auto-correctable issues:

```bash
bundle exec rubocop -a
```

### Writing Tests

All new features and bug fixes should include tests:

```ruby
# spec/deadfinder/my_feature_spec.rb
require 'spec_helper'

RSpec.describe DeadFinder::MyFeature do
  describe '#method_name' do
    it 'does something' do
      expect(result).to eq(expected)
    end
  end
end
```

Run tests:

```bash
bundle exec rspec
```

Run specific test file:

```bash
bundle exec rspec spec/deadfinder/my_feature_spec.rb
```

### Commit Guidelines

Write clear, concise commit messages:

```
Add feature: description of feature

More detailed explanation if needed.
- Bullet points for specific changes
- Another change

Fixes #123
```

## Pull Request Process

### Before Submitting

1. **Update your branch** with the latest changes:

```bash
git fetch upstream
git rebase upstream/main
```

2. **Run all tests**:

```bash
bundle exec rspec
```

3. **Run the linter**:

```bash
bundle exec rubocop
```

4. **Test your changes manually**:

```bash
bundle exec ruby -I lib bin/deadfinder url https://example.com
```

### Submit Pull Request

1. Push your branch to your fork:

```bash
git push origin feature/awesome-feature
```

2. Open a Pull Request on GitHub
3. Fill out the PR template with:
   - Description of changes
   - Related issues (if any)
   - Testing performed

### PR Review

- We'll review your PR as soon as possible
- Address any feedback or requested changes
- Once approved, we'll merge your PR

## Reporting Bugs

When reporting bugs, please include:

1. **Description**: Clear description of the bug
2. **Steps to reproduce**: How to reproduce the issue
3. **Expected behavior**: What you expected to happen
4. **Actual behavior**: What actually happened
5. **Environment**:
   - Ruby version
   - DeadFinder version
   - Operating system

Example:

```markdown
### Description
DeadFinder crashes when scanning URLs with special characters

### Steps to Reproduce
1. Run `deadfinder url "https://example.com/path?query=value&other=123"`
2. Observe the error

### Expected Behavior
Should scan the URL successfully

### Actual Behavior
Crashes with error: ...

### Environment
- Ruby 3.4.0
- DeadFinder 1.9.1
- macOS 14.0
```

## Feature Requests

When suggesting features, please include:

1. **Use case**: What problem does this solve?
2. **Proposed solution**: How should it work?
3. **Alternatives**: Other approaches you considered
4. **Examples**: Example usage or mockups

## Documentation

Help improve documentation:

1. Fix typos or unclear explanations
2. Add examples
3. Improve API documentation
4. Add missing documentation

Documentation is located in:
- `README.md` - Main documentation
- `docs/` - Zola-based website
- Inline code comments for RubyDoc

## Code of Conduct

Please be respectful and inclusive in all interactions. We follow these principles:

- Be welcoming and friendly
- Be patient and understanding
- Be respectful of differing viewpoints
- Accept constructive criticism gracefully
- Focus on what's best for the community

## Development Workflow

### Running DeadFinder in Development

```bash
# Run from source
bundle exec ruby -I lib bin/deadfinder --help

# Test specific commands
bundle exec ruby -I lib bin/deadfinder version
bundle exec ruby -I lib bin/deadfinder url https://example.com
```

### Testing Changes

```bash
# Run all tests
bundle exec rspec

# Run with coverage
bundle exec rspec --format documentation

# Run specific tests
bundle exec rspec spec/deadfinder/runner_spec.rb
```

### Debugging

Use `pry` for debugging:

```ruby
require 'pry'

def my_method
  binding.pry  # Execution will stop here
  # ... rest of code
end
```

### Building the Gem

```bash
# Build the gem
gem build deadfinder.gemspec

# Install locally
gem install deadfinder-1.9.1.gem
```

## Project Structure

```
deadfinder/
├── bin/
│   ├── console          # IRB console with DeadFinder loaded
│   ├── deadfinder       # Main CLI executable
│   └── setup            # Setup script
├── lib/
│   ├── deadfinder.rb              # Main module
│   └── deadfinder/
│       ├── cli.rb                 # CLI interface
│       ├── runner.rb              # Core logic
│       ├── logger.rb              # Logging
│       ├── utils.rb               # Utilities
│       ├── version.rb             # Version
│       ├── http_client.rb         # HTTP client
│       ├── url_pattern_matcher.rb # Pattern matching
│       └── completion.rb          # Shell completion
├── spec/                # RSpec tests
├── examples/            # Usage examples
├── github-action/       # GitHub Action
├── docs/                # Documentation website
└── README.md           # Main documentation
```

## Additional Resources

- [Ruby Style Guide](https://rubystyle.guide/)
- [RSpec Documentation](https://rspec.info/)
- [Thor Documentation](http://whatisthor.com/) (CLI framework)
- [GitHub Flow](https://guides.github.com/introduction/flow/)

## Getting Help

If you need help:

- Open an issue on GitHub
- Check existing issues and discussions
- Review the documentation
- Look at the examples directory

## Recognition

Contributors are recognized in:
- `CONTRIBUTORS.svg` - Auto-generated contributor list
- GitHub repository contributors page

Thank you for contributing to DeadFinder! 🎉
