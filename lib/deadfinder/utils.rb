require 'uri'

def generate_url text, base_url
    node = text.to_s
    begin
        if !node.start_with?("http://", "https://")
            uri = URI(base_url)
            if node.start_with? "//"
                return "#{uri.scheme}:#{node}"
            elsif node.start_with? "/"
                return "#{uri.scheme}://#{uri.host}#{node}"
            else   
                return "#{uri.to_s}#{node}"
            end
        end
    rescue => e
        #puts e
    end
    return node
end