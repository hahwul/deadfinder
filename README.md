# DeadFinder

Dead link (broken link) means a link within a web page that cannot be connected. These links can have a negative impact to SEO and Security. This tool makes it easy to identify and modify.

![](https://user-images.githubusercontent.com/13212227/192243070-0c960680-ae08-4f30-8cf9-0844eca7c5ea.png)

## Installation
```
gem install deadfinder
```

## Usage
```
Commands:
  deadfinder file            # Scan the URLs from File. (e.g deadfinder file urls.txt)
  deadfinder help [COMMAND]  # Describe available commands or one specific command
  deadfinder pipe            # Scan the URLs from STDIN. (e.g cat urls.txt | deadfinder pipe)
  deadfinder sitemap         # Scan the URLs from sitemap.
  deadfinder url             # Scan the Single URL.
  deadfinder version         # Show version.

Options:
  c, [--concurrency=N]
                        # Default: 20
  t, [--timeout=N]
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