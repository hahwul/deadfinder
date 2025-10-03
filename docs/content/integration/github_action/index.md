---
title: "GitHub Action"
weight: 1
---

DeadFinder provides a native GitHub Action for seamless integration into your CI/CD workflows. This allows you to automatically check for dead links in your repository or website.

## Basic Usage

Add the following step to your GitHub Actions workflow:

```yaml
steps:
  - name: Run DeadFinder
    uses: hahwul/deadfinder@1.9.1
    # or uses: hahwul/deadfinder@latest
    id: broken-link
    with:
      command: sitemap
      target: https://www.example.com/sitemap.xml
```

## Configuration

### Required Inputs

| Input | Description |
|-------|-------------|
| `command` | Command to run: `url`, `file`, `sitemap`, or `pipe` |
| `target` | Target URL, file path, or sitemap URL |

### Optional Inputs

| Input | Default | Description |
|-------|---------|-------------|
| `timeout` | 10 | Timeout in seconds for each request |
| `concurrency` | 50 | Number of concurrent workers |
| `silent` | false | Suppress output during scanning |
| `headers` | - | Custom HTTP headers for initial request |
| `worker_headers` | - | Custom HTTP headers for worker requests |
| `include30x` | false | Include 30x redirections as dead links |
| `user_agent` | Mozilla/5.0... | Custom User-Agent string |
| `proxy` | - | Proxy server URL |
| `proxy_auth` | - | Proxy authentication (username:password) |
| `match` | - | Only include URLs matching this pattern |
| `ignore` | - | Ignore URLs matching this pattern |
| `coverage` | true | Enable coverage analysis |
| `visualize` | - | Generate visualization (e.g., report.png) |

### Outputs

| Output | Description |
|--------|-------------|
| `output` | JSON string containing scan results |

## Complete Example

```yaml
name: Dead Link Check

on:
  schedule:
    - cron: '0 0 * * 0'  # Run weekly on Sunday
  workflow_dispatch:  # Allow manual trigger

jobs:
  check-links:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Run DeadFinder
        uses: hahwul/deadfinder@1.9.1
        id: broken-link
        with:
          command: sitemap
          target: https://www.example.com/sitemap.xml
          timeout: 10
          concurrency: 50
          silent: false
          headers: "X-API-Key: ${{ secrets.API_KEY }}"
          worker_headers: "User-Agent: DeadFinder Bot"
          include30x: false
          match: "blog|docs"
          ignore: "static|cdn"
          coverage: true
          visualize: report.png

      - name: Output Results
        run: echo '${{ steps.broken-link.outputs.output }}'

      - name: Upload Visualization
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: deadlink-report
          path: report.png
```

## Scanning Different Sources

### Scan a Single URL

```yaml
- name: Scan Homepage
  uses: hahwul/deadfinder@1.9.1
  with:
    command: url
    target: https://www.example.com
```

### Scan URLs from a File

```yaml
- name: Scan URL List
  uses: hahwul/deadfinder@1.9.1
  with:
    command: file
    target: ./urls.txt
```

### Scan from Sitemap

```yaml
- name: Scan Sitemap
  uses: hahwul/deadfinder@1.9.1
  with:
    command: sitemap
    target: https://www.example.com/sitemap.xml
```

## Automated Issue Creation

You can automatically create GitHub issues when dead links are found. Here's a complete workflow:

```yaml
name: Dead Link Detection

on:
  schedule:
    - cron: '0 0 * * 0'
  workflow_dispatch:

jobs:
  check-links:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Run DeadFinder
        uses: hahwul/deadfinder@1.9.1
        id: broken-link
        with:
          command: sitemap
          target: https://www.example.com/sitemap.xml
          silent: true

      - name: Parse Results
        id: parse
        run: |
          DEAD_LINKS=$(echo '${{ steps.broken-link.outputs.output }}' | jq -r 'to_entries[] | select(.value | length > 0) | "\(.key):\n" + (.value | join("\n"))')
          if [ -n "$DEAD_LINKS" ]; then
            echo "found=true" >> $GITHUB_OUTPUT
            echo "links<<EOF" >> $GITHUB_OUTPUT
            echo "$DEAD_LINKS" >> $GITHUB_OUTPUT
            echo "EOF" >> $GITHUB_OUTPUT
          else
            echo "found=false" >> $GITHUB_OUTPUT
          fi

      - name: Create Issue
        if: steps.parse.outputs.found == 'true'
        uses: actions/github-script@v7
        with:
          script: |
            const deadLinks = `${{ steps.parse.outputs.links }}`;
            const issue = await github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: '🔗 Dead Links Detected',
              body: `## Dead Links Found\n\n\`\`\`\n${deadLinks}\n\`\`\`\n\nPlease review and fix these broken links.`,
              labels: ['bug', 'documentation']
            });
            console.log(`Created issue #${issue.data.number}`);
```

For more details on automated issue creation, see the article: [Automating Dead Link Detection](https://www.hahwul.com/2024/10/20/automating-dead-link-detection/)

## Pull Request Checks

Add dead link checking to your pull request workflow:

```yaml
name: PR Check

on:
  pull_request:
    branches: [main]

jobs:
  check-links:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout PR
        uses: actions/checkout@v4

      - name: Check Dead Links
        uses: hahwul/deadfinder@1.9.1
        id: check
        with:
          command: file
          target: ./urls.txt
          silent: true

      - name: Comment on PR
        if: steps.check.outputs.output != '{}'
        uses: actions/github-script@v7
        with:
          script: |
            const output = JSON.parse('${{ steps.check.outputs.output }}');
            const deadLinksCount = Object.values(output).flat().length;
            if (deadLinksCount > 0) {
              github.rest.issues.createComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: context.issue.number,
                body: `⚠️ Found ${deadLinksCount} dead link(s) in this PR. Please review.`
              });
            }
```

## Multi-Site Monitoring

Monitor multiple sites in a single workflow:

```yaml
name: Multi-Site Check

on:
  schedule:
    - cron: '0 0 * * *'

jobs:
  check-sites:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        site:
          - name: Main Site
            url: https://www.example.com/sitemap.xml
          - name: Blog
            url: https://blog.example.com/sitemap.xml
          - name: Docs
            url: https://docs.example.com/sitemap.xml
    steps:
      - name: Check ${{ matrix.site.name }}
        uses: hahwul/deadfinder@1.9.1
        with:
          command: sitemap
          target: ${{ matrix.site.url }}
          silent: true
```

## Using Docker Image

You can also use the Docker image in your workflow:

```yaml
steps:
  - name: Run DeadFinder with Docker
    run: |
      docker run ghcr.io/hahwul/deadfinder:latest \
        deadfinder sitemap https://www.example.com/sitemap.xml
```

## Tips and Best Practices

1. **Schedule Regular Scans**: Use cron schedules to run checks weekly or daily
2. **Use Silent Mode**: Enable `silent: true` in CI to reduce log noise
3. **Store Results**: Upload results as artifacts for later analysis
4. **Set Appropriate Timeouts**: Adjust timeouts based on your site's response times
5. **Use Filtering**: Apply `match` and `ignore` patterns to focus on relevant links
6. **Monitor Visualization**: Upload visualization images to track trends over time
7. **Secure Secrets**: Use GitHub Secrets for API keys and sensitive headers
