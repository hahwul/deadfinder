require "uri"
require "json"
require "yaml"
require "csv"
require "xml"
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
  @@cache_set = {} of String => Bool
  @@mutex = Mutex.new

  def self.output
    @@output
  end

  def self.coverage_data
    @@coverage_data
  end

  def self.cache_set
    @@cache_set
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
      @@cache_set.clear
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
      File.read_lines(filename).map(&.chomp)
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
    urls = parse_sitemap(sitemap_url, options)
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
      headers = HTTP::Headers.new
      headers["User-Agent"] = options.user_agent
      req_path = if HttpClient.proxy_configured?(options) && uri.scheme == "http"
                   HttpClient.absolute_uri(uri)
                 else
                   path = uri.path.presence || "/"
                   uri.query.presence ? "#{path}?#{uri.query}" : path
                 end
      response = client.get(req_path, headers: headers)
      client.close

      doc = XML.parse(response.body)

      # Try with namespace
      doc.xpath_nodes("//xmlns:loc", {"xmlns" => "http://www.sitemaps.org/schemas/sitemap/0.9"}).each do |node|
        urls << node.text.strip unless node.text.strip.empty?
      end

      # Try without namespace if no results
      if urls.empty?
        doc.xpath_nodes("//loc").each do |node|
          urls << node.text.strip unless node.text.strip.empty?
        end
      end

      # Check for sitemap index (recursive sitemaps)
      sitemap_locs = [] of String
      doc.xpath_nodes("//xmlns:sitemap/xmlns:loc", {"xmlns" => "http://www.sitemaps.org/schemas/sitemap/0.9"}).each do |node|
        sitemap_locs << node.text.strip unless node.text.strip.empty?
      end
      if sitemap_locs.empty?
        doc.xpath_nodes("//sitemap/loc").each do |node|
          sitemap_locs << node.text.strip unless node.text.strip.empty?
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
    targets = yield
    targets = targets.first(options.limit) if options.limit > 0
    targets.each do |target|
      run_with_target(target, options, app)
    end
    gen_output(options)
  end

  def self.run_with_target(target : String, options : Options, app : Runner = Runner.new)
    Deadfinder::Logger.target "Fetching #{target}"
    app.run(target, options, @@output, @@coverage_data, @@cache_set, @@mutex)
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
    output_data = @@output
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
                else
                  generate_json(output_data, coverage_info)
                end
      File.write(options.output, content)
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

  private def self.toml_key(key : String) : String
    # TOML keys with special chars need quoting
    if key.matches?(/^[a-zA-Z0-9_-]+$/)
      key
    else
      "\"#{key.gsub("\\", "\\\\").gsub("\"", "\\\"")}\""
    end
  end

  private def self.toml_array(arr : Array(String)) : String
    items = arr.map { |s| "\"#{s.gsub("\\", "\\\\").gsub("\"", "\\\"")}\"" }
    "[#{items.join(", ")}]"
  end
end
