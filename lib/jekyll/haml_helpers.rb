require 'cgi'

module Jekyll
  module HamlHelpers
    
    def h(text)
      CGI.escapeHTML(text)
    end
    
    def link_to(text, url, attributes = {})
      attributes = { :href => url }.merge(attributes)
      attributes = attributes.map {|key, value| %{#{key}="#{h value}"} }.join(" ")
      "<a #{attributes}>#{text}</a>"
    end
    
  end
end
