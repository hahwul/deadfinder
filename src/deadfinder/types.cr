module Deadfinder
  # Parses the comma-separated status lists accepted by `--accept-status` and
  # `--dead-status`/`--exclude-status`. An entry is either a bare code (`403`)
  # or an inclusive range (`400-499`); surrounding whitespace is ignored so a
  # shell-quoted `"200, 204, 400-499"` behaves the same as the compact form.
  #
  # Codes above the usual 1xx-5xx band are accepted on purpose: real bot-defense
  # responses use them (LinkedIn answers non-browser clients with `999`).
  module StatusList
    MAX_STATUS = 999

    def self.parse(raw : String) : Array(Range(Int32, Int32))
      ranges = [] of Range(Int32, Int32)
      raw.split(',') do |part|
        entry = part.strip
        next if entry.empty?

        low, separator, high = entry.partition('-')
        if separator.empty?
          code = parse_code(entry, entry)
          ranges << (code..code)
        else
          from = parse_code(low.strip, entry)
          to = parse_code(high.strip, entry)
          if from > to
            raise ArgumentError.new("invalid status range #{entry.inspect}: #{from} is greater than #{to}")
          end
          ranges << (from..to)
        end
      end
      ranges
    end

    # True when `status_code` falls in any of `ranges`. An empty list matches
    # nothing, which is what keeps an unset flag from changing the policy.
    def self.includes?(ranges : Array(Range(Int32, Int32)), status_code : Int32) : Bool
      ranges.any? { |range| range.includes?(status_code) }
    end

    private def self.parse_code(text : String, entry : String) : Int32
      code = text.to_i?
      unless code && code >= 0 && code <= MAX_STATUS
        raise ArgumentError.new("invalid status code #{text.inspect} in #{entry.inspect} (expected 0-#{MAX_STATUS})")
      end
      code
    end
  end

  class Options
    property concurrency : Int32 = 50
    # How many targets are scanned at once. This does *not* widen the request
    # budget: `concurrency` stays the global cap on in-flight HTTP requests, and
    # target concurrency only decides how many pages compete for it. Without it
    # `-c` only parallelized the links within a single page, so a 5000-URL
    # sitemap paid 5000 serial round trips before any of that concurrency helped.
    property target_concurrency : Int32 = 10
    property timeout : Int32 = 10
    property output : String = ""
    property output_format : String = "json"
    property headers : Array(String) = [] of String
    property worker_headers : Array(String) = [] of String
    property silent : Bool = false
    property verbose : Bool = false
    property debug : Bool = false
    property include30x : Bool = false
    property proxy : String = ""
    property proxy_auth : String = ""
    property insecure : Bool = false
    property match : String = ""
    property ignore : String = ""
    property user_agent : String = "Mozilla/5.0 (compatible; DeadFinder/#{VERSION};)"
    property coverage : Bool = false
    property visualize : String = ""
    property limit : Int32 = 0
    # Opt-in CI gate. The v1 CLI contract always exits 0, so this stays off by
    # default and only `--fail-on-dead` turns findings into a non-zero exit.
    property fail_on_dead : Bool = false
    # Opt-in: verify that `#fragment` link targets actually exist in the linked
    # document. Off by default because it needs the response body, which the
    # status-only link check never reads.
    property check_anchors : Bool = false
    # HTTP method used for *link status checks* only; documents (the scan target
    # page, a sitemap) are always fetched with GET because their body is the
    # point. See `HttpClient::METHOD_AUTO` for the auto fallback rule.
    property http_method : String = HttpClient::METHOD_AUTO
    # Extra attempts after the first for a *transient* failure (connection
    # error, timeout, 429, 5xx). A 404 is never retried.
    property retries : Int32 = 2
    # Minimum interval, in milliseconds, between two requests to the same host.
    # Per-host on purpose: one slow host must not stall the others.
    property delay : Int32 = 0

    # Raw `--accept-status` / `--dead-status` values are kept for help and error
    # messages; the parsed ranges are what the hot path consults. Both are set
    # once during CLI parsing, before any worker fiber exists, so the workers
    # only ever read them.
    getter accept_status : String = ""
    getter accept_status_ranges = [] of Range(Int32, Int32)
    getter dead_status : String = ""
    getter dead_status_ranges = [] of Range(Int32, Int32)

    def accept_status=(value : String) : String
      @accept_status_ranges = StatusList.parse(value)
      @accept_status = value
    end

    def dead_status=(value : String) : String
      @dead_status_ranges = StatusList.parse(value)
      @dead_status = value
    end
  end

  class TargetCoverage
    property total : Int32 = 0
    property dead : Int32 = 0
    property status_counts : Hash(String, Int32) = {} of String => Int32

    def initialize(@total = 0, @dead = 0, @status_counts = {} of String => Int32)
    end
  end

  struct CoverageTarget
    property total_tested : Int32
    property dead_links : Int32
    # DEPRECATED NAME: this is `dead_links / total_tested * 100`, i.e. the ratio
    # of links that are dead — not how much of the site was covered. A healthy
    # target reports 0.0 here. Read `dead_link_percentage` instead; the old name
    # is kept (in the struct and in every output format) so existing parsers
    # keep working.
    property coverage_percentage : Float64
    property status_counts : Hash(String, Int32)

    def initialize(@total_tested, @dead_links, @coverage_percentage, @status_counts)
    end

    # Correctly named accessor for the value stored as `coverage_percentage`.
    def dead_link_percentage : Float64
      coverage_percentage
    end
  end

  struct CoverageSummary
    property total_tested : Int32
    property total_dead : Int32
    # DEPRECATED NAME: same misnomer as `CoverageTarget#coverage_percentage` —
    # it is the overall dead-link ratio. Read `overall_dead_link_percentage`.
    property overall_coverage_percentage : Float64
    property overall_status_counts : Hash(String, Int32)

    def initialize(@total_tested, @total_dead, @overall_coverage_percentage, @overall_status_counts)
    end

    # Correctly named accessor for the value stored as
    # `overall_coverage_percentage`.
    def overall_dead_link_percentage : Float64
      overall_coverage_percentage
    end
  end

  struct CoverageResult
    property targets : Hash(String, CoverageTarget)
    property summary : CoverageSummary

    def initialize(@targets, @summary)
    end
  end
end
