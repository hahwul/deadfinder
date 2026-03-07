module Deadfinder
  module Completion
    def self.bash : String
      <<-BASH
      _deadfinder_completions()
      {
        local cur prev opts
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        opts="--include30x --concurrency --timeout --output --output_format --headers --worker_headers --user_agent --proxy --proxy_auth --match --ignore --silent --verbose --debug --limit --coverage --visualize"

        COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
        return 0
      }
      complete -F _deadfinder_completions deadfinder
      BASH
    end

    def self.zsh : String
      <<-ZSH
      #compdef deadfinder

      _arguments \\
        '--include30x[Include 30x redirections]' \\
        '--concurrency[Number of concurrency]:number' \\
        '--timeout[Timeout in seconds]:number' \\
        '--output[File to write result]:file' \\
        '--output_format[Output format]:string' \\
        '--headers[Custom HTTP headers]:array' \\
        '--worker_headers[Custom HTTP headers for workers]:array' \\
        '--user_agent[User-Agent string]:string' \\
        '--proxy[Proxy server]:string' \\
        '--proxy_auth[Proxy server authentication]:string' \\
        '--match[Match URL pattern]:string' \\
        '--ignore[Ignore URL pattern]:string' \\
        '--silent[Silent mode]' \\
        '--verbose[Verbose mode]' \\
        '--debug[Debug mode]' \\
        '--limit[Limit number of URLs to scan]:number' \\
        '--coverage[Enable coverage tracking]' \\
        '--visualize[Generate visualization PNG]:file'
      ZSH
    end

    def self.fish : String
      <<-FISH
      complete -c deadfinder -l include30x -d 'Include 30x redirections'
      complete -c deadfinder -l concurrency -d 'Number of concurrency' -a '(seq 1 100)'
      complete -c deadfinder -l timeout -d 'Timeout in seconds' -a '(seq 1 60)'
      complete -c deadfinder -l output -d 'File to write result' -r
      complete -c deadfinder -l output_format -d 'Output format' -r
      complete -c deadfinder -l headers -d 'Custom HTTP headers' -r
      complete -c deadfinder -l worker_headers -d 'Custom HTTP headers for workers' -r
      complete -c deadfinder -l user_agent -d 'User-Agent string' -r
      complete -c deadfinder -l proxy -d 'Proxy server' -r
      complete -c deadfinder -l proxy_auth -d 'Proxy server authentication' -r
      complete -c deadfinder -l match -d 'Match URL pattern' -r
      complete -c deadfinder -l ignore -d 'Ignore URL pattern' -r
      complete -c deadfinder -l silent -d 'Silent mode'
      complete -c deadfinder -l verbose -d 'Verbose mode'
      complete -c deadfinder -l debug -d 'Debug mode'
      complete -c deadfinder -l limit -d 'Limit number of URLs to scan' -r
      complete -c deadfinder -l coverage -d 'Enable coverage tracking'
      complete -c deadfinder -l visualize -d 'Generate visualization PNG' -r
      FISH
    end
  end
end
