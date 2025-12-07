+++
template = "landing.html"

[extra.hero]
title = "Welcome to DeadFinder!"
badge = "v1.9.1"
description = "Find dead-links (broken links) in web pages for better SEO and security"
image = "/images/preview.jpg"
cta_buttons = [
    { text = "Get Started", url = "/get_started/installation", style = "primary" },
    { text = "View on GitHub", url = "https://github.com/hahwul/deadfinder", style = "secondary" },
]

[extra.features_section]
title = "Essential Features"
description = "Discover Deadfinder's essential features for comprehensive attack surface detection and analysis."

[[extra.features]]
title = "Multiple Input Modes"
desc = "Scan single URLs, multiple URLs from files, sitemaps, or pipe URLs from stdin for flexible dead link detection."
icon = "fa-solid fa-list"

[[extra.features]]
title = "GitHub Action Integration"
desc = "Seamlessly integrate dead link detection into your CI/CD pipeline with native GitHub Actions support."
icon = "fa-brands fa-github"

[[extra.features]]
title = "Ruby API"
desc = "Use DeadFinder as a Ruby library in your applications with a simple and intuitive API."
icon = "fa-solid fa-gem"

[[extra.features]]
title = "Concurrent Scanning"
desc = "Fast and efficient scanning with configurable concurrency to check hundreds of links in seconds."
icon = "fa-solid fa-bolt"

[[extra.features]]
title = "Multiple Output Formats"
desc = "Export results in JSON, YAML, or CSV formats to suit your workflow and tooling needs."
icon = "fa-solid fa-file-export"

[[extra.features]]
title = "Coverage Analysis"
desc = "Get detailed statistics about your scans including total tested links, dead links found, and coverage percentage."
icon = "fa-solid fa-chart-pie"

[extra.final_cta_section]
title = "Contributing"
description = "DeadFinder is an open-source project made with ❤️. If you want to contribute to this project, please see CONTRIBUTING.md and submit a pull request!"
button = { text = "View Contributing Guide", url = "https://github.com/hahwul/deadfinder/blob/main/CONTRIBUTING.md" }
+++
