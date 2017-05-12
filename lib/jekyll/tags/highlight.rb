module Jekyll

  class HighlightBlock < Liquid::Block
    include Liquid::StandardFilters

    # we need a language, but the linenos argument is optional.
    SYNTAX = /(\w+)\s?(:?linenos)?\s?/

    def initialize(tag_name, markup, tokens)
      super
      if markup =~ SYNTAX
        @lang = $1
        if defined? $2
          # additional options to pass to Albino.
          @options = { 'O' => 'linenos=inline' }
        else
          @options = {}
        end
      else
        raise SyntaxError.new("Syntax Error in 'highlight' - Valid syntax: highlight <lang> [linenos]")
      end
    end

    def render(context)
      if context.registers[:site].pygments
        render_pygments(context, super.to_s)
      else
        render_codehighlighter(context, super.to_s)
      end
    end

    def render_pygments(context, code)
      if cache_dir = context.registers[:site].pygments_cache
        path = File.join(cache_dir, "#{@lang}-#{Digest::MD5.hexdigest(code)}.html")
        if File.exist?(path)
          highlighted_code = File.read(path)
        else
          highlighted_code = Albino.new(code, @lang).to_s(@options)
          File.open(path, 'w') {|f| f.print(highlighted_code) }
        end
      else
        highlighted_code = Albino.new(code, @lang).to_s(@options)
      end
        
      if context["content_type"] == :markdown
        return "\n" + highlighted_code + "\n"
      elsif context["content_type"] == :textile
        return "<notextile>" + highlighted_code + "</notextile>"
      else
        return highlighted_code
      end
    end

    def render_codehighlighter(context, code)
    #The div is required because RDiscount blows ass
      <<-HTML
<div>
  <pre>
    <code class='#{@lang}'>#{h(code).strip}</code>
  </pre>
</div>
      HTML
    end
  end

end

Liquid::Template.register_tag('highlight', Jekyll::HighlightBlock)
