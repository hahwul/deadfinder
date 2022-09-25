# deadfinder

![](https://user-images.githubusercontent.com/13212227/192097414-d735ac3e-930a-4c36-9592-dedabac22a19.png)

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
