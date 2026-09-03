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

  # `deadfinder file -` reads the list from STDIN, matching the convention of
  # other CLI tools.
  STDIN_FILENAME = "-"

  # `deadfinder ... -o -` streams the report to STDOUT instead of creating a
  # file literally named `-` in the cwd, so `deadfinder url X -f json -o - | jq`
  # works. Same spelling as STDIN_FILENAME but the opposite direction, hence a
  # separate name.
  STDOUT_FILENAME = "-"

  # Exit status for "the scan itself ran fine, but dead links/targets were
  # found". Deliberately distinct from 1, which stays reserved for usage and
  # I/O errors. Only emitted when `--fail-on-dead` is given: the v1 CLI
  # contract is that a scan always exits 0.
  EXIT_DEAD_FOUND = 2

  # How many individually invalid input lines are reported before switching to
  # a single summary line.
  MAX_INVALID_TARGET_REPORTS = 10

  @@output = {} of String => Array(String)
  @@coverage_data = {} of String => TargetCoverage
  # Global URL -> HTTP status code cache. A URL is fetched at most once across
  # the whole run; every page that references it is still attributed the cached
  # status. A value of `Runner::ERROR_STATUS` (-1) records a connection failure.
  @@status_cache = {} of String => Int32
  # Scan targets that are themselves broken, mapped to the same status
  # vocabulary coverage `status_counts` uses: the numeric HTTP code, or
  # "error" when the target could not be reached at all.
  @@dead_targets = {} of String => String
  # Where `-o -` streams the report. Mirrors `Logger.sink`: the two are the
  # opposite halves of the same split (report on STDOUT, logs on STDERR), and
  # both are swappable so an embedded caller — or a test — can collect them.
  @@report_sink : IO = STDOUT
  # The targets that were dispatched, in the order the user supplied them.
  # Targets finish out of order once several are scanned at once, so the report
  # would otherwise be keyed in whatever order results happened to land in;
  # this restores the requested order at serialization time.
  @@target_order = [] of String
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

  def self.dead_targets
    @@dead_targets
  end

  def self.report_sink : IO
    @@mutex.synchronize { @@report_sink }
  end

  def self.report_sink=(io : IO)
    @@mutex.synchronize { @@report_sink = io }
  end

  def self.reset_report_sink
    self.report_sink = STDOUT
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
      @@dead_targets.clear
      @@target_order.clear
    end
    Runner.reset_shared_state
  end

  # Records a scan target that is itself dead. `Runner#run` only ever collects
  # the links *found on* a page, so before this a URL list whose entries all
  # 404 or refuse connections (the advertised
  # `deadfinder file <(subfinder | httpx)` workflow) reported nothing at all.
  # The dead/alive rule matches `Runner#record_status` so `--include30x`
  # governs targets and links identically.
  def self.record_dead_target(target : String, status : Int32, options : Options) : Nil
    connection_error = status == Runner::ERROR_STATUS
    return unless connection_error || status >= 400 || (status >= 300 && options.include30x)
    label = connection_error ? "error" : status.to_s
    @@mutex.synchronize { @@dead_targets[target] = label }
  end

  # True when the run recorded anything dead — a broken link on a page, or a
  # target that was itself broken. Drives the `--fail-on-dead` exit code.
  def self.dead_findings? : Bool
    @@mutex.synchronize do
      !@@dead_targets.empty? || @@output.any? { |_, urls| !urls.empty? }
    end
  end

  def self.run_pipe(options : Options)
    run_with_input(options) { read_targets(STDIN, options.limit) }
  end

  def self.run_file(filename : String, options : Options)
    run_with_input(options) do
      # The CLI pre-checks existence, but the file can still be unreadable
      # (permissions) or vanish between that check and this read (TOCTOU).
      # Report cleanly and scan nothing rather than crash.
      begin
        if filename == STDIN_FILENAME
          read_targets(STDIN, options.limit)
        else
          File.open(filename) { |file| read_targets(file, options.limit) }
        end
      rescue ex : IO::Error
        Deadfinder::Logger.error "Failed to read input file #{filename}: #{ex.message}"
        [] of String
      end
    end
  end

  # Reads scan targets from `io`, one per line, applying the input rules shared
  # by the `pipe` and `file` commands:
  #
  #   * a leading UTF-8 BOM is dropped, so a list exported from Windows/Excel
  #     doesn't lose its first URL
  #   * surrounding whitespace is trimmed, so a padded line doesn't become a
  #     distinct target (and a distinct key) in the report
  #   * blank lines and `#` comments are skipped instead of being fetched —
  #     neither can be a valid target, and both previously logged an error
  #   * duplicates are dropped, keeping first-seen order
  #   * lines that aren't absolute http(s) URLs are reported and skipped rather
  #     than handed to the fetcher to fail on
  #   * reading stops once `limit` targets are collected, so `--limit` no longer
  #     drains a huge list (or a live stream) first — and, because only real
  #     targets are counted, blank/comment lines can't eat into the limit
  def self.read_targets(io : IO, limit : Int32) : Array(String)
    targets = [] of String
    seen = Set(String).new
    invalid = 0
    first_line = true

    io.each_line(chomp: true) do |raw|
      line = raw
      if first_line
        line = line.lchop(UTF8_BOM)
        first_line = false
      end
      line = line.strip
      next if line.empty? || line.starts_with?('#')

      unless valid_target?(line)
        invalid += 1
        # Cap the per-line reports: a list of bare domains would otherwise
        # bury everything else under one error per line.
        if invalid <= MAX_INVALID_TARGET_REPORTS
          Deadfinder::Logger.error "Skipping invalid target (expected an absolute http:// or https:// URL): #{line}"
        end
        next
      end

      next unless seen.add?(line)
      targets << line
      break if limit > 0 && targets.size >= limit
    end

    if invalid > MAX_INVALID_TARGET_REPORTS
      Deadfinder::Logger.error "Skipped #{invalid} invalid targets in total"
    end

    targets
  end

  def self.run_url(url : String, options : Options)
    Deadfinder::Logger.apply_options(options)
    if reason = http_target_error(url)
      Deadfinder::Logger.error "Cannot scan target: #{reason}"
      return
    end
    run_with_target(url.strip, options)
    gen_output(options)
  end

  def self.run_sitemap(sitemap_url : String, options : Options)
    Deadfinder::Logger.apply_options(options)
    if reason = http_target_error(sitemap_url)
      Deadfinder::Logger.error "Cannot fetch sitemap: #{reason}"
      return
    end

    app = Runner.new
    collector = SitemapCollector.new(options.limit)
    parse_sitemap(sitemap_url.strip, options, collector)
    urls = collector.urls

    if collector.truncated?
      Deadfinder::Logger.info "Found #{urls.size} URLs from #{sitemap_url} (stopped early at --limit #{options.limit})"
    else
      Deadfinder::Logger.info "Found #{urls.size} URLs from #{sitemap_url}"
    end

    run_targets(urls, options, app)
    gen_output(options)
  end

  # Accumulates state across the recursive sitemap walk: the ordered, unique
  # page URLs found so far, the sitemap documents already fetched (cycle
  # guard), and the `--limit` cutoff. Threading the limit through the walk lets
  # a huge sitemap index stop downloading children as soon as enough URLs are
  # in hand, instead of fetching every child and throwing the surplus away.
  private class SitemapCollector
    getter urls = [] of String
    getter? truncated : Bool = false

    def initialize(@limit : Int32 = 0)
      @seen = Set(String).new
      @visited = Set(String).new
    end

    def add(url : String) : Nil
      return if @seen.includes?(url)
      if full?
        @truncated = true
        return
      end
      @seen << url
      @urls << url
    end

    def full? : Bool
      @limit > 0 && @urls.size >= @limit
    end

    def mark_truncated : Nil
      @truncated = true
    end

    # Returns false when this sitemap document has already been fetched.
    def visit(sitemap_url : String) : Bool
      @visited.add?(sitemap_url)
    end
  end

  private def self.parse_sitemap(sitemap_url : String, options : Options,
                                 collector : SitemapCollector,
                                 depth : Int32 = 0) : Nil
    if collector.full?
      collector.mark_truncated
      return
    end
    if depth >= MAX_SITEMAP_DEPTH
      Deadfinder::Logger.error "Sitemap depth limit (#{MAX_SITEMAP_DEPTH}) reached at #{sitemap_url}"
      return
    end
    unless collector.visit(sitemap_url)
      Deadfinder::Logger.error "Sitemap cycle detected at #{sitemap_url}"
      return
    end

    begin
      uri = URI.parse(sitemap_url)
      headers = HttpClient.build_headers(options.headers, options.user_agent)
      # Sitemaps very commonly sit behind a redirect (http -> https, apex -> www,
      # /sitemap.xml -> /sitemap_index.xml). Follow it instead of reporting the
      # 30x itself as a fetch failure.
      response, final_uri = HttpClient.fetch(uri, options, headers, HttpClient::MAX_REDIRECTS)

      unless response.status.success?
        Deadfinder::Logger.error "Failed to fetch sitemap #{sitemap_url}: HTTP #{response.status_code}"
        return
      end

      # Relative <loc> values (and relative child-sitemap references) resolve
      # against the document's final location, not the address originally
      # requested.
      base = final_uri.to_s
      doc = XML.parse(HttpClient.decompress_if_gzip(response.body))

      # Namespace-agnostic extraction via local-name(): handles the standard
      # 0.9 namespace, the legacy Google 0.84 namespace, and namespace-free
      # documents uniformly. Page URLs are scoped under <url> and child
      # sitemaps under <sitemap> so a sitemap-index's <sitemap><loc> entries are
      # NOT mis-collected as page targets (which previously double-fetched them).
      found_before = collector.urls.size
      doc.xpath_nodes("//*[local-name()='url']/*[local-name()='loc']").each do |node|
        collect_sitemap_url(collector, node.text, base, sitemap_url)
      end

      # Check for sitemap index (recursive sitemaps)
      sitemap_locs = [] of String
      doc.xpath_nodes("//*[local-name()='sitemap']/*[local-name()='loc']").each do |node|
        text = node.text.strip
        sitemap_locs << text unless text.empty?
      end

      # Tolerate malformed sitemaps that put <loc> at the top level (no <url>
      # wrapper). Only used when *this document* matched neither a urlset nor a
      # sitemap index, so it cannot reintroduce the index double-processing bug.
      if collector.urls.size == found_before && sitemap_locs.empty?
        doc.xpath_nodes("//*[local-name()='loc']").each do |node|
          collect_sitemap_url(collector, node.text, base, sitemap_url)
        end
      end

      sitemap_locs.each do |loc|
        if collector.full?
          collector.mark_truncated
          break
        end
        sub_sitemap = generate_url(loc, base)
        unless sub_sitemap
          Deadfinder::Logger.error "Skipping unusable child sitemap #{loc.inspect} in #{sitemap_url}"
          next
        end
        parse_sitemap(sub_sitemap, options, collector, depth + 1)
      end
    rescue ex
      Deadfinder::Logger.error "Failed to parse sitemap #{sitemap_url}: #{ex.message}"
    end
  end

  private def self.collect_sitemap_url(collector : SitemapCollector, raw : String,
                                       base : String, sitemap_url : String) : Nil
    text = raw.strip
    return if text.empty?
    if url = generate_url(text, base)
      collector.add(url)
    else
      Deadfinder::Logger.debug "Skipping unusable sitemap entry #{text.inspect} in #{sitemap_url}"
    end
  end

  private def self.run_with_input(options : Options, &block : -> Array(String))
    Deadfinder::Logger.apply_options(options)
    Deadfinder::Logger.info "Reading input"
    # `read_targets` has already trimmed, deduped and limited the list.
    targets = yield
    if targets.empty?
      Deadfinder::Logger.info "No URLs to scan"
    else
      run_targets(targets, options, Runner.new)
    end
    gen_output(options)
  end

  # Scans `targets`, up to `options.target_concurrency` of them at a time.
  #
  # This is what makes `file`, `pipe` and `sitemap` scale: `-c` only ever
  # parallelized the links *within* one page, so pages themselves were fetched
  # strictly one after another and a 5000-URL sitemap paid 5000 serial round
  # trips first. Total network pressure is unchanged — `Runner` hands out a
  # global budget of `-c` in-flight requests however many targets are running.
  private def self.run_targets(targets : Array(String), options : Options, app : Runner) : Nil
    @@mutex.synchronize { @@target_order.concat(targets) }

    concurrency = options.target_concurrency
    concurrency = 1 if concurrency < 1
    concurrency = targets.size if targets.size < concurrency

    # One target in flight: run it inline and leave the log stream alone, so
    # output is byte-for-byte what it has always been and still streams line by
    # line instead of arriving in one burst at the end.
    if concurrency <= 1
      targets.each { |target| run_with_target(target, options, app) }
      return
    end

    jobs = Channel(String).new(concurrency)
    done = Channel(Nil).new(concurrency)

    concurrency.times do
      spawn do
        loop do
          target = jobs.receive? || break
          begin
            # Buffer this target's lines and flush them as one block, so
            # concurrent targets don't shred each other's output.
            Deadfinder::Logger.buffered { run_with_target(target, options, app) }
          rescue ex
            # `Runner#run` already reports its own failures; this is the
            # last-resort net. A fiber that dies here would stop draining the
            # queue, and the run would then block forever waiting for targets
            # nobody is left to pick up.
            Deadfinder::Logger.error "[#{ex}] #{target}"
          end
        end
        done.send(nil)
      end
    end

    # A feeder fiber rather than a channel big enough for every target: a
    # sitemap can carry hundreds of thousands of URLs.
    spawn do
      targets.each { |target| jobs.send(target) }
      jobs.close
    end

    concurrency.times { done.receive }
  end

  # Re-keys a per-target hash into the order the targets were requested in.
  # Anything not dispatched through `run_targets` (a single `url` scan) keeps
  # its existing position at the end.
  private def self.in_target_order(data : Hash(String, V)) : Hash(String, V) forall V
    order = @@mutex.synchronize { @@target_order.dup }
    return data if order.size < 2 || data.size < 2

    ordered = {} of String => V
    order.each do |target|
      next if ordered.has_key?(target)
      if value = data[target]?
        ordered[target] = value
      end
    end
    data.each { |key, value| ordered[key] = value unless ordered.has_key?(key) }
    ordered
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

    # A target that is itself dead is folded in as one tested-and-dead unit
    # under its own key. Without this a scan whose every target 404s reported
    # "0 tested" coverage even though every single thing it looked at failed.
    merged = {} of String => TargetCoverage
    @@coverage_data.each do |target, data|
      merged[target] = TargetCoverage.new(data.total, data.dead, data.status_counts.dup)
    end
    @@dead_targets.each do |target, status|
      entry = (merged[target] ||= TargetCoverage.new)
      entry.total += 1
      entry.dead += 1
      entry.status_counts[status] = (entry.status_counts[status]? || 0) + 1
    end

    in_target_order(merged).each do |target, data|
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
    output_data = in_target_order(@@output.transform_values(&.uniq))
    # Snapshot so the emitters see one consistent view, and so the `dead_targets`
    # key can be skipped entirely when empty — existing golden files and
    # existing consumers must be byte-identical on a run with no dead targets.
    dead_targets = in_target_order(@@dead_targets.dup)
    format = options.output_format.downcase

    coverage_info : CoverageResult? = nil
    if options.coverage && (@@coverage_data.values.any? { |v| v.total > 0 } || !dead_targets.empty?)
      coverage_info = calculate_coverage
    end

    unless options.output.empty?
      content = case format
                when "yaml", "yml"
                  generate_yaml(output_data, dead_targets, coverage_info)
                when "csv"
                  generate_csv(output_data, dead_targets, coverage_info)
                when "toml"
                  generate_toml(output_data, dead_targets, coverage_info)
                when "sarif"
                  generate_sarif(output_data, dead_targets, coverage_info)
                else
                  generate_json(output_data, dead_targets, coverage_info)
                end
      if options.output == STDOUT_FILENAME
        write_report_to_stdout(content)
      else
        # A bad --output path (missing parent dir, no write permission, a path
        # that is actually a directory, …) would otherwise raise after the whole
        # scan has run and crash with a stack trace. Degrade to a clear message.
        begin
          File.write(options.output, content)
        rescue ex : IO::Error
          Deadfinder::Logger.error "Failed to write output file #{options.output}: #{ex.message}"
        end
      end
    end

    if !options.visualize.empty? && coverage_info
      Visualizer.generate(coverage_info, options.visualize)
    end
  end

  # `-o -` streams the report on STDOUT. Logs have already been moved to STDERR
  # (see `Logger.apply_options`) so the two never interleave. The trailing
  # newline is added when the format didn't supply one so the stream ends on a
  # line boundary for `jq`/`yq`. A broken pipe (`... -o - | head`) is swallowed
  # for the same reason the logger swallows it: it must not crash the run.
  private def self.write_report_to_stdout(content : String) : Nil
    io = report_sink
    begin
      io.print content
      io.print '\n' unless content.ends_with?('\n')
      io.flush
    rescue IO::Error
    end
  end

  private def self.generate_json(output_data : Hash(String, Array(String)),
                                 dead_targets : Hash(String, String),
                                 coverage_info : CoverageResult?) : String
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
          dead_targets_to_json(json, dead_targets)
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
          # Sits alongside the per-target keys, which are always absolute
          # http(s) URLs and so can never collide with this literal name.
          dead_targets_to_json(json, dead_targets)
        end
      end
    end
  end

  # Emitted only when there is something to report, so a run without dead
  # targets produces exactly the bytes it produced before this key existed.
  private def self.dead_targets_to_json(json : JSON::Builder, dead_targets : Hash(String, String))
    return if dead_targets.empty?
    json.field "dead_targets" do
      json.object do
        dead_targets.each do |target, status|
          json.field target, status
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
                json.field "dead_link_percentage", data.dead_link_percentage
                # Deprecated alias of dead_link_percentage; kept so existing
                # parsers keep working. See CoverageTarget in types.cr.
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
          json.field "overall_dead_link_percentage", coverage.summary.overall_dead_link_percentage
          # Deprecated alias of overall_dead_link_percentage.
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

  private def self.generate_yaml(output_data : Hash(String, Array(String)),
                                 dead_targets : Hash(String, String),
                                 coverage_info : CoverageResult?) : String
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
          dead_targets_to_yaml(yaml, dead_targets)
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
                  yaml.scalar "dead_link_percentage"
                  yaml.scalar data.dead_link_percentage
                  # Deprecated alias of dead_link_percentage.
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
              yaml.scalar "overall_dead_link_percentage"
              yaml.scalar coverage_info.summary.overall_dead_link_percentage
              # Deprecated alias of overall_dead_link_percentage.
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
          dead_targets_to_yaml(yaml, dead_targets)
        end
      end
    end
  end

  # See `dead_targets_to_json`: skipped entirely when empty.
  private def self.dead_targets_to_yaml(yaml : YAML::Builder, dead_targets : Hash(String, String))
    return if dead_targets.empty?
    yaml.scalar "dead_targets"
    yaml.mapping do
      dead_targets.each do |target, status|
        yaml.scalar target
        # Quote explicitly: a plain `404` would be loaded as an integer while
        # `error` stays a string, giving the same field two types depending on
        # the value. Every other format emits this as a string.
        yaml.scalar status, style: YAML::ScalarStyle::DOUBLE_QUOTED
      end
    end
  end

  private def self.generate_csv(output_data : Hash(String, Array(String)),
                                dead_targets : Hash(String, String),
                                coverage_info : CoverageResult?) : String
    CSV.build do |csv|
      csv.row "target", "url"
      output_data.each do |target, urls|
        urls.each { |url| csv.row target, url }
      end

      # Its own section rather than a `target,url` row: the target *is* the
      # finding here, there is no link to put in the second column. Omitted
      # entirely when empty so a clean run's CSV is unchanged.
      unless dead_targets.empty?
        csv.row # Empty row separator
        csv.row "Dead Targets"
        csv.row "target", "status"
        dead_targets.each do |target, status|
          csv.row target, status
        end
      end

      if coverage_info
        csv.row # Empty row separator
        csv.row "Coverage Report"
        # The correctly named columns are appended rather than inserted so
        # positional readers of the existing four columns keep working.
        csv.row "target", "total_tested", "dead_links", "coverage_percentage", "dead_link_percentage"
        coverage_info.targets.each do |target, data|
          csv.row target, data.total_tested, data.dead_links, "#{data.coverage_percentage}%", "#{data.dead_link_percentage}%"
        end
        csv.row # Empty row separator
        csv.row "Overall Summary"
        csv.row "total_tested", "total_dead", "overall_coverage_percentage", "overall_dead_link_percentage"
        csv.row coverage_info.summary.total_tested, coverage_info.summary.total_dead, "#{coverage_info.summary.overall_coverage_percentage}%", "#{coverage_info.summary.overall_dead_link_percentage}%"
      end
    end
  end

  private def self.generate_toml(output_data : Hash(String, Array(String)),
                                 dead_targets : Hash(String, String),
                                 coverage_info : CoverageResult?) : String
    lines = [] of String

    if coverage_info
      lines << "[dead_links]"
      output_data.each do |target, urls|
        lines << "#{toml_key(target)} = #{toml_array(urls)}"
      end
      append_toml_dead_targets(lines, dead_targets)
      lines << ""
      lines << "[coverage.targets]"
      coverage_info.targets.each do |target, data|
        lines << "[coverage.targets.#{toml_key(target)}]"
        lines << "total_tested = #{data.total_tested}"
        lines << "dead_links = #{data.dead_links}"
        lines << "dead_link_percentage = #{data.dead_link_percentage}"
        # Deprecated alias of dead_link_percentage.
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
      lines << "overall_dead_link_percentage = #{coverage_info.summary.overall_dead_link_percentage}"
      # Deprecated alias of overall_dead_link_percentage.
      lines << "overall_coverage_percentage = #{coverage_info.summary.overall_coverage_percentage}"
      lines << "[coverage.summary.overall_status_counts]"
      coverage_info.summary.overall_status_counts.each do |code, count|
        lines << "#{toml_key(code)} = #{count}"
      end
    else
      output_data.each do |target, urls|
        lines << "#{toml_key(target)} = #{toml_array(urls)}"
      end
      # Must come after the bare top-level pairs: everything following a TOML
      # table header belongs to that table.
      append_toml_dead_targets(lines, dead_targets)
    end

    lines.join("\n") + "\n"
  end

  # See `dead_targets_to_json`: no table header at all when there is nothing
  # to report.
  private def self.append_toml_dead_targets(lines : Array(String), dead_targets : Hash(String, String)) : Nil
    return if dead_targets.empty?
    lines << "" unless lines.empty?
    lines << "[dead_targets]"
    dead_targets.each do |target, status|
      lines << "#{toml_key(target)} = \"#{toml_escape(status)}\""
    end
  end

  # Produce a SARIF 2.1.0 report where each dead link is a `Result` with
  # rule id "DEAD_LINK". The scanned target is attached as a related
  # location so downstream tools (GitHub code scanning, editors) can link
  # back to the page on which the broken URL was found.
  private def self.generate_sarif(output_data : Hash(String, Array(String)),
                                  dead_targets : Hash(String, String),
                                  coverage_info : CoverageResult?) : String
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

        # A dead scan target is a different finding from a dead link on a live
        # page, so it gets its own rule id. Declared only when there is at
        # least one, to keep a clean run's SARIF unchanged.
        unless dead_targets.empty?
          r.rule(
            "DEAD_TARGET",
            name: "DeadTarget",
            short_description: "Scan target is itself broken or unreachable",
            full_description: "A URL given to deadfinder as a scan target returned an HTTP error status or could not be reached at all.",
            help_uri: "https://github.com/hahwul/deadfinder",
            level: Sarif::Level::Error,
          )

          dead_targets.each do |target, status|
            r.result do |rb|
              rb.message("Dead target: #{target} (#{status})")
              rb.rule_id("DEAD_TARGET")
              rb.level(Sarif::Level::Error)
              rb.location(uri: target)
            end
          end
        end

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
