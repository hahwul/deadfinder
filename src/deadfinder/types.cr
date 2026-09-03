module Deadfinder
  class Options
    property concurrency : Int32 = 50
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
