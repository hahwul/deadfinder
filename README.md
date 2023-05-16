# DeadFinder

Dead link (broken link) means a link within a web page that cannot be connected. These links can have a negative impact to SEO and Security. This tool makes it easy to identify and modify.

![](https://user-images.githubusercontent.com/13212227/192243070-0c960680-ae08-4f30-8cf9-0844eca7c5ea.png)

## Installation
### Install with Gem
```
gem install deadfinder
```

### Docker Image
```shell
docker pull ghcr.io/hahwul/deadfinder:latest
```

## Using In
### CLI
```shell
deadfinder sitemap https://www.hahwul.com/sitemap.xml
```

### Github Action
```yml
steps:
- name: Run DeadFinder
  uses: hahwul/deadfinder@1.3.1
  id: broken-link
  with:
    command: sitemap
    target: https://www.hahwul.com/sitemap.xml

- name: Output Handling
  run: echo '${{ steps.broken-link.outputs.output }}'
```

### Ruby Code
```ruby
require 'deadfinder'

app = DeadFinderRunner.new
options = {}
options['concurrency'] = 30

app.run('https://www.hahwul.com/2022/09/30/deadfinder/', options)
puts Output
```

## Usage
```
Commands:
  deadfinder file <FILE>            # Scan the URLs from File. (e.g deadfinder file urls.txt)
  deadfinder help [COMMAND]         # Describe available commands or one specific command
  deadfinder pipe                   # Scan the URLs from STDIN. (e.g cat urls.txt | deadfinder pipe)
  deadfinder sitemap <SITEMAP-URL>  # Scan the URLs from sitemap.
  deadfinder url <URL>              # Scan the Single URL.
  deadfinder version                # Show version.

Options:
  c, [--concurrency=N]          # Number of concurrncy
                                # Default: 20
  t, [--timeout=N]              # Timeout in seconds
                                # Default: 10
  o, [--output=OUTPUT]          # File to write JSON result
  H, [--headers=one two three]  # Custom HTTP headers to send with request
```

## Modes
```shell
# Scan the URLs from STDIN (multiple URLs)
cat urls.txt | deadfinder pipe

# Scan the URLs from File. (multiple URLs)
deadfinder file urls.txt

# Scan the Single URL.
deadfinder url https://www.hahwul.com

# Scan the URLs from sitemap. (multiple URLs)
deadfinder sitemap https://www.hahwul.com/sitemap.xml
```

## JSON Handling
```shell
deadfinder sitemap https://www.hahwul.com/sitemap.xml \
  -o output.json
  
cat output.json | jq
```

```json
{
  "Origin URL": [
    "DeadLink URL",
    "DeadLink URL",
    "DeadLink URL"
  ]
}
```
