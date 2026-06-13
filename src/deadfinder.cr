require "uri"
require "json"
require "yaml"
require "csv"
require "xml"
require "sarif"
require "./deadfinder/version"
require "./deadfinder/types"
require "./deadfinder/utils"
require "./deadfinder/logger"
require "./deadfinder/url_pattern_matcher"
require "./deadfinder/http_client"
require "./deadfinder/runner"
require "./deadfinder/visualizer"
require "./deadfinder/completion"

module Deadfinder
  MAX_SITEMAP_DEPTH = 5

  @@output = {} of String => Array(String)
  @@coverage_data = {} of String => TargetCoverage
  # Global URL -> HTTP status code cache. A URL is fetched at most once across
  # the whole run; every page that references it is still attributed the cached
  # status. A value of `Runner::ERROR_STATUS` (-1) records a connection failure.
  @@status_cache = {} of String => Int32
  @@mutex = Mutex.new

  def self.output
    @@output
  end

  def self.coverage_data
    @@coverage_data
  end

  def self.status_cache
    @@status_cache
  end

  def self.mutex
    @@mutex
  end

  # Clears module-level accumulator state so back-to-back runs in the
  # same process (e.g. tests, embedded usage) start from a clean slate.
  def self.reset_state : Nil
    @@mutex.synchronize do
      @@output.clear
      @@coverage_data.clear
      @@status_cache.clear
    end
  end

  def self.run_pipe(options : Options)
    run_with_input(options) do
      lines = [] of String
      while line = STDIN.gets
        lines << line.chomp
      end
      lines
    end
  end

  def self.run_file(filename : String, options : Options)
    run_with_input(options) do
      # The CLI pre-checks existence, but the file can still be unreadable
      # (permissions) or vanish between that check and this read (TOCTOU).
      # Report cleanly and scan nothing rather than crash.
      begin
        File.read_lines(filename).map(&.chomp)
      rescue ex : IO::Error
        Deadfinder::Logger.error "Failed to read input file #{filename}: #{ex.message}"
        [] of String
      end
    end
  end

  def self.run_url(url : String, options : Options)
    Deadfinder::Logger.apply_options(options)
    run_with_target(url, options)
    gen_output(options)
  end

  def self.run_sitemap(sitemap_url : String, options : Options)
    Deadfinder::Logger.apply_options(options)
    app = Runner.new
    urls = parse_sitemap(sitemap_url, options).uniq
    urls = urls.first(options.limit) if options.limit > 0
    Deadfinder::Logger.info "Found #{urls.size} URLs from #{sitemap_url}"
    urls.each do |url|
      turl = generate_url(url, sitemap_url)
      run_with_target(turl, options, app) if turl
    end
    gen_output(options)
  end

  private def self.parse_sitemap(sitemap_url : String, options : Options,
                                 depth : Int32 = 0,
                                 visited : Set(String) = Set(String).new) : Array(String)
    urls = [] of String

    if depth >= MAX_SITEMAP_DEPTH
      Deadfinder::Logger.error "Sitemap depth limit (#{MAX_SITEMAP_DEPTH}) reached at #{sitemap_url}"
      return urls
    end
    if visited.includes?(sitemap_url)
      Deadfinder::Logger.error "Sitemap cycle detected at #{sitemap_url}"
      return urls
    end
    visited << sitemap_url

    begin
      uri = URI.parse(sitemap_url)
      client = HttpClient.create(uri, options)
      begin
        headers = HTTP::Headers.new
        headers["User-Agent"] = options.user_agent
        req_path = if HttpClient.proxy_configured?(options) && uri.scheme == "http"
                     HttpClient.absolute_uri(uri)
                   else
                     path = uri.path.presence || "/"
                     uri.query.presence ? "#{path}?#{uri.query}" : path
                   end
        response = client.get(req_path, headers: headers)

        if response.status_code != 200
          Deadfinder::Logger.error "Failed to fetch sitemap #{sitemap_url}: HTTP #{response.status_code}"
          return urls
        end

        doc = XML.parse(response.body)
      ensure
        client.close
      end

      # Namespace-agnostic extraction via local-name(): handles the standard
      # 0.9 namespace, the legacy Google 0.84 namespace, and namespace-free
      # documents uniformly. Page URLs are scoped under <url> and child
      # sitemaps under <sitemap> so a sitemap-index's <sitemap><loc> entries are
      # NOT mis-collected as page targets (which previously double-fetched them).
      doc.xpath_nodes("//*[local-name()='url']/*[local-name()='loc']").each do |node|
        urls << node.text.strip unless node.text.strip.empty?
      end

      # Check for sitemap index (recursive sitemaps)
      sitemap_locs = [] of String
      doc.xpath_nodes("//*[local-name()='sitemap']/*[local-name()='loc']").each do |node|
        sitemap_locs << node.text.strip unless node.text.strip.empty?
      end

      # Tolerate malformed sitemaps that put <loc> at the top level (no <url>
      # wrapper). Only used when neither a urlset nor a sitemap index matched,
      # so it cannot reintroduce the index double-processing bug.
      if urls.empty? && sitemap_locs.empty?
        doc.xpath_nodes("//*[local-name()='loc']").each do |node|
          urls << node.text.strip unless node.text.strip.empty?
        end
      end

      sitemap_locs.each do |sub_sitemap|
        urls.concat(parse_sitemap(sub_sitemap, options, depth + 1, visited))
      end
    rescue ex
      Deadfinder::Logger.error "Failed to parse sitemap: #{ex.message}"
    end
    urls
  end

  private def self.run_with_input(options : Options, &block : -> Array(String))
    Deadfinder::Logger.apply_options(options)
    Deadfinder::Logger.info "Reading input"
    app = Runner.new
    # Dedupe input targets: scanning the same page twice is wasted work and
    # would double-count it in coverage totals.
    targets = (yield).uniq
    targets = targets.first(options.limit) if options.limit > 0
    targets.each do |target|
      run_with_target(target, options, app)
    end
    gen_output(options)
  end

  def self.run_with_target(target : String, options : Options, app : Runner = Runner.new)
    Deadfinder::Logger.target "Fetching #{target}"
    app.run(target, options, @@output, @@coverage_data, @@status_cache, @@mutex)
  end

  def self.calculate_coverage : CoverageResult
    coverage_summary = {} of String => CoverageTarget
    total_all_tested = 0
    total_all_dead = 0
    overall_status_counts = {} of String => Int32

    @@coverage_data.each do |target, data|
      total = data.total
      dead = data.dead
      status_counts = data.status_counts
      coverage_percentage = total > 0 ? ((dead.to_f / total) * 100).round(2) : 0.0

      coverage_summary[target] = CoverageTarget.new(
        total_tested: total,
        dead_links: dead,
        coverage_percentage: coverage_percentage,
        status_counts: status_counts.dup
      )

      total_all_tested += total
      total_all_dead += dead
      status_counts.each do |code, count|
        overall_status_counts[code] = (overall_status_counts[code]? || 0) + count
      end
    end

    overall_coverage = total_all_tested > 0 ? ((total_all_dead.to_f / total_all_tested) * 100).round(2) : 0.0

    CoverageResult.new(
      targets: coverage_summary,
      summary: CoverageSummary.new(
        total_tested: total_all_tested,
        total_dead: total_all_dead,
        overall_coverage_percentage: overall_coverage,
        overall_status_counts: overall_status_counts
      )
    )
  end

  def self.gen_output(options : Options)
    # Dedupe per-target URLs so a page that references the same link twice
    # (or is scanned more than once) never lists it twice in the report.
    output_data = @@output.transform_values(&.uniq)
    format = options.output_format.downcase

    coverage_info : CoverageResult? = nil
    if options.coverage && !@@coverage_data.empty? && @@coverage_data.values.any? { |v| v.total > 0 }
      coverage_info = calculate_coverage
    end

    unless options.output.empty?
      content = case format
                when "yaml", "yml"
                  generate_yaml(output_data, coverage_info)
                when "csv"
                  generate_csv(output_data, coverage_info)
                when "toml"
                  generate_toml(output_data, coverage_info)
                when "sarif"
                  generate_sarif(output_data, coverage_info)
                else
                  generate_json(output_data, coverage_info)
                end
      # A bad --output path (missing parent dir, no write permission, a path
      # that is actually a directory, …) would otherwise raise after the whole
      # scan has run and crash with a stack trace. Degrade to a clear message.
      begin
        File.write(options.output, content)
      rescue ex : IO::Error
        Deadfinder::Logger.error "Failed to write output file #{options.output}: #{ex.message}"
      end
    end

    if !options.visualize.empty? && coverage_info
      Visualizer.generate(coverage_info, options.visualize)
    end
  end

  private def self.generate_json(output_data : Hash(String, Array(String)), coverage_info : CoverageResult?) : String
    JSON.build(indent: "  ") do |json|
      if coverage_info
        json.object do
          json.field "dead_links" do
            json.object do
              output_data.each do |target, urls|
                json.field target do
                  json.array do
                    urls.each { |url| json.string url }
                  end
                end
              end
            end
          end
          json.field "coverage" do
            coverage_to_json(json, coverage_info)
          end
        end
      else
        json.object do
          output_data.each do |target, urls|
            json.field target do
              json.array do
                urls.each { |url| json.string url }
              end
            end
          end
        end
      end
    end
  end

  private def self.coverage_to_json(json : JSON::Builder, coverage : CoverageResult)
    json.object do
      json.field "targets" do
        json.object do
          coverage.targets.each do |target, data|
            json.field target do
              json.object do
                json.field "total_tested", data.total_tested
                json.field "dead_links", data.dead_links
                json.field "coverage_percentage", data.coverage_percentage
                json.field "status_counts" do
                  json.object do
                    data.status_counts.each do |code, count|
                      json.field code, count
                    end
                  end
                end
              end
            end
          end
        end
      end
      json.field "summary" do
        json.object do
          json.field "total_tested", coverage.summary.total_tested
          json.field "total_dead", coverage.summary.total_dead
          json.field "overall_coverage_percentage", coverage.summary.overall_coverage_percentage
          json.field "overall_status_counts" do
            json.object do
              coverage.summary.overall_status_counts.each do |code, count|
                json.field code, count
              end
            end
          end
        end
      end
    end
  end

  private def self.generate_yaml(output_data : Hash(String, Array(String)), coverage_info : CoverageResult?) : String
    YAML.build do |yaml|
      yaml.mapping do
        if coverage_info
          yaml.scalar "dead_links"
          yaml.mapping do
            output_data.each do |target, urls|
              yaml.scalar target
              yaml.sequence do
                urls.each { |url| yaml.scalar url }
              end
            end
          end
          yaml.scalar "coverage"
          yaml.mapping do
            yaml.scalar "targets"
            yaml.mapping do
              coverage_info.targets.each do |target, data|
                yaml.scalar target
                yaml.mapping do
                  yaml.scalar "total_tested"
                  yaml.scalar data.total_tested
                  yaml.scalar "dead_links"
                  yaml.scalar data.dead_links
                  yaml.scalar "coverage_percentage"
                  yaml.scalar data.coverage_percentage
                  yaml.scalar "status_counts"
                  yaml.mapping do
                    data.status_counts.each do |code, count|
                      yaml.scalar code
                      yaml.scalar count
                    end
                  end
                end
              end
            end
            yaml.scalar "summary"
            yaml.mapping do
              yaml.scalar "total_tested"
              yaml.scalar coverage_info.summary.total_tested
              yaml.scalar "total_dead"
              yaml.scalar coverage_info.summary.total_dead
              yaml.scalar "overall_coverage_percentage"
              yaml.scalar coverage_info.summary.overall_coverage_percentage
              yaml.scalar "overall_status_counts"
              yaml.mapping do
                coverage_info.summary.overall_status_counts.each do |code, count|
                  yaml.scalar code
                  yaml.scalar count
                end
              end
            end
          end
        else
          output_data.each do |target, urls|
            yaml.scalar target
            yaml.sequence do
              urls.each { |url| yaml.scalar url }
            end
          end
        end
      end
    end
  end

  private def self.generate_csv(output_data : Hash(String, Array(String)), coverage_info : CoverageResult?) : String
    CSV.build do |csv|
      csv.row "target", "url"
      output_data.each do |target, urls|
        urls.each { |url| csv.row target, url }
      end

      if coverage_info
        csv.row # Empty row separator
        csv.row "Coverage Report"
        csv.row "target", "total_tested", "dead_links", "coverage_percentage"
        coverage_info.targets.each do |target, data|
          csv.row target, data.total_tested, data.dead_links, "#{data.coverage_percentage}%"
        end
        csv.row # Empty row separator
        csv.row "Overall Summary"
        csv.row "total_tested", "total_dead", "overall_coverage_percentage"
        csv.row coverage_info.summary.total_tested, coverage_info.summary.total_dead, "#{coverage_info.summary.overall_coverage_percentage}%"
      end
    end
  end

  private def self.generate_toml(output_data : Hash(String, Array(String)), coverage_info : CoverageResult?) : String
    lines = [] of String

    if coverage_info
      lines << "[dead_links]"
      output_data.each do |target, urls|
        lines << "#{toml_key(target)} = #{toml_array(urls)}"
      end
      lines << ""
      lines << "[coverage.targets]"
      coverage_info.targets.each do |target, data|
        lines << "[coverage.targets.#{toml_key(target)}]"
        lines << "total_tested = #{data.total_tested}"
        lines << "dead_links = #{data.dead_links}"
        lines << "coverage_percentage = #{data.coverage_percentage}"
        lines << "[coverage.targets.#{toml_key(target)}.status_counts]"
        data.status_counts.each do |code, count|
          lines << "#{toml_key(code)} = #{count}"
        end
      end
      lines << ""
      lines << "[coverage.summary]"
      lines << "total_tested = #{coverage_info.summary.total_tested}"
      lines << "total_dead = #{coverage_info.summary.total_dead}"
      lines << "overall_coverage_percentage = #{coverage_info.summary.overall_coverage_percentage}"
      lines << "[coverage.summary.overall_status_counts]"
      coverage_info.summary.overall_status_counts.each do |code, count|
        lines << "#{toml_key(code)} = #{count}"
      end
    else
      output_data.each do |target, urls|
        lines << "#{toml_key(target)} = #{toml_array(urls)}"
      end
    end

    lines.join("\n") + "\n"
  end

  # Produce a SARIF 2.1.0 report where each dead link is a `Result` with
  # rule id "DEAD_LINK". The scanned target is attached as a related
  # location so downstream tools (GitHub code scanning, editors) can link
  # back to the page on which the broken URL was found.
  private def self.generate_sarif(output_data : Hash(String, Array(String)), coverage_info : CoverageResult?) : String
    log = Sarif::Builder.build do |b|
      b.run("deadfinder", Deadfinder::VERSION) do |r|
        r.information_uri("https://github.com/hahwul/deadfinder")
        r.rule(
          "DEAD_LINK",
          name: "DeadLink",
          short_description: "Broken or unreachable link",
          full_description: "A link on the scanned page returned an HTTP error status or failed to resolve.",
          help_uri: "https://github.com/hahwul/deadfinder",
          level: Sarif::Level::Warning,
        )

        output_data.each do |target, urls|
          urls.each do |url|
            r.result do |rb|
              rb.message("Dead link detected: #{url} (found on #{target})")
              rb.rule_id("DEAD_LINK")
              rb.level(Sarif::Level::Warning)
              rb.location(uri: url)
              rb.related_location(uri: target, message_text: "Referenced from this page")
            end
          end
        end
      end
    end
    log.to_pretty_json
  end

  private def self.toml_key(key : String) : String
    # TOML keys with special chars need quoting
    if key.matches?(/^[a-zA-Z0-9_-]+$/)
      key
    else
      "\"#{toml_escape(key)}\""
    end
  end

  private def self.toml_array(arr : Array(String)) : String
    items = arr.map { |s| "\"#{toml_escape(s)}\"" }
    "[#{items.join(", ")}]"
  end

  # Escape a string for a TOML basic string. In addition to backslash and
  # double-quote, TOML forbids raw control characters (U+0000..U+001F and
  # U+007F) inside basic strings, so they must be emitted as escapes — otherwise
  # a URL containing an embedded newline/CR would produce unparseable TOML.
  private def self.toml_escape(s : String) : String
    String.build do |io|
      s.each_char do |c|
        case c
        when '\\' then io << "\\\\"
        when '"'  then io << "\\\""
        when '\b' then io << "\\b"
        when '\t' then io << "\\t"
        when '\n' then io << "\\n"
        when '\f' then io << "\\f"
        when '\r' then io << "\\r"
        else
          if c.ord < 0x20 || c.ord == 0x7F
            io << "\\u" << c.ord.to_s(16).rjust(4, '0').upcase
          else
            io << c
          end
        end
      end
    end
  end
end
