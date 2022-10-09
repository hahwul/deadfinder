# DeadFinder

Dead link (broken link) means a link within a web page that cannot be connected. These links can have a negative impact to SEO and Security. This tool makes it easy to identify and modify.

![](https://user-images.githubusercontent.com/13212227/192243070-0c960680-ae08-4f30-8cf9-0844eca7c5ea.png)

## Installation
Install with Gem
```
gem install deadfinder
```

Docker Image
```shell
docker pull ghcr.io/hahwul/deadfinder:latest
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
  c, [--concurrency=N]  # Set Concurrncy
                        # Default: 20
  t, [--timeout=N]      # Set HTTP Timeout
                        # Default: 10
  o, [--output=OUTPUT]  # Save JSON Result
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