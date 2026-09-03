#!/usr/bin/env ruby
# frozen_string_literal: true

require 'socket'

ROUTES = {
  '/index.html' => {
    status: 200,
    content_type: 'text/html',
    body: <<~HTML
      <!DOCTYPE html>
      <html><body>
      <a href="ok">ok</a>
      <a href="dead">dead</a>
      <a href="redirect">redirect</a>
      </body></html>
    HTML
  },
  '/ok'       => { status: 200, content_type: 'text/plain', body: 'OK' },
  '/dead'     => { status: 404, content_type: 'text/plain', body: 'Not Found' },
  '/redirect' => { status: 301, content_type: 'text/plain', body: '', extra: { 'Location' => '/ok' } }
}.freeze

STATUS_TEXT = { 200 => 'OK', 301 => 'Moved Permanently', 404 => 'Not Found' }.freeze

server = TCPServer.new('127.0.0.1', 0)
puts server.addr[1]
STDOUT.flush

trap('TERM') { exit 0 }
trap('INT')  { exit 0 }

loop do
  client = server.accept
  begin
    request_line = client.gets
    method = request_line&.split(' ')&.dig(0) || 'GET'
    raw_path = request_line&.split(' ')&.dig(1) || '/'
    path = raw_path.split('?').first
    while (line = client.gets) && line.strip != ''; end

    # A HEAD response carries the headers a GET would return but no body
    # (RFC 9110 9.3.2). Sending one anyway would desynchronize any client that
    # keeps the connection alive, which is exactly what deadfinder now does.
    body_allowed = method != 'HEAD'

    route = ROUTES[path]
    if route
      headers = {
        'Content-Type'   => route[:content_type],
        'Content-Length' => route[:body].bytesize.to_s
      }.merge(route[:extra] || {})
      client.print "HTTP/1.1 #{route[:status]} #{STATUS_TEXT[route[:status]] || 'OK'}\r\n"
      headers.each { |k, v| client.print "#{k}: #{v}\r\n" }
      client.print "\r\n"
      client.print route[:body] if body_allowed
    else
      client.print "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
    end
  rescue StandardError
    # swallow: test fixture, keep accepting
  ensure
    client&.close
  end
end
