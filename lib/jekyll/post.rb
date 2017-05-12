module Jekyll

  class Post
    include Comparable
    include Convertible

    class << self
      attr_accessor :lsi
    end

    MATCHER = /^(.+\/)*(\d+-\d+-\d+(?:_\d+-\d+)?)-(.*)(\.[^.]+)$/

    # Post name validator. Post filenames must be like:
    #   2008-11-05-my-awesome-post.textile
    # or:
    #   2008-11-05_12-45-my-awesome-post.textile
    #
    # Returns <Bool>
    def self.valid?(name)
      name =~ MATCHER
    end

    attr_accessor :site, :date, :slug, :ext, :topics, :tags, :published, :data, :content, :output
    attr_writer :categories
    
    def categories
      @categories ||= []
    end

    # Initialize this Post instance.
    #   +site+ is the Site
    #   +base+ is the String path to the dir containing the post file
    #   +name+ is the String filename of the post file
    #   +categories+ is an Array of Strings for the categories for this post
    #   +tags+ is an Array of Strings for the tags for this post
    #
    # Returns <Post>
    def initialize(site, source, dir, name)
      @site = site
      @base = File.join(source, dir, '_posts')
      @name = name

      self.categories = dir.split('/').reject { |x| x.empty? }

      parts = name.split('/')
      self.topics = parts.size > 1 ? parts[0..-2] : []

      self.process(name)
      self.data = self.site.post_defaults.dup
      self.read_yaml(@base, name)

      extract_title_from_first_header_or_slug

      if self.data.has_key?('published') && self.data['published'] == false
        self.published = false
      else
        self.published = true
      end

      if self.categories.empty?
        if self.data.has_key?('category')
          self.categories << self.data['category']
        elsif self.data.has_key?('categories')
          # Look for categories in the YAML-header, either specified as
          # an array or a string.
          if self.data['categories'].kind_of? String
            self.categories = self.data['categories'].split
          else
            self.categories = self.data['categories']
          end
        end
      end

      self.tags = self.data['tags'] || []
    end

    # Spaceship is based on Post#date
    #
    # Returns -1, 0, 1
    def <=>(other)
      self.date <=> other.date
    end

    # Extract information from the post filename
    #   +name+ is the String filename of the post file
    #
    # Returns nothing
    def process(name)
      m, cats, date, slug, ext = *name.match(MATCHER)
      date = date.sub(/_(\d+)-(\d+)\Z/, ' \1:\2')  # Make optional time part parsable.
      self.date = Time.parse(date)
      self.slug = slug
      self.ext = ext
    end

    # The generated directory into which the post will be placed
    # upon generation. This is derived from the permalink or, if
    # permalink is absent, set to the default date
    # e.g. "/2008/11/05/" if the permalink style is :date, otherwise nothing
    #
    # Returns <String>
    def dir
      File.dirname(generated_path)
    end

    # The full path and filename of the post.
    # Defined in the YAML of the post body
    # (Optional)
    #
    # Returns <String>
    def permalink
      self.data && self.data['permalink']
    end

    def template
      case self.site.permalink_style
      when :pretty
        "/:categories/:year/:month/:day/:title"
      when :none
        "/:categories/:title.html"
      when :date
        "/:categories/:year/:month/:day/:title.html"
      else
        self.site.permalink_style.to_s
      end
    end

    # The generated relative path of this post
    # e.g. /2008/11/05/my-awesome-post.html
    #
    # Returns <String>
    def generated_path
      return permalink if permalink

      @generated_path ||= {
        "year"       => date.strftime("%Y"),
        "month"      => date.strftime("%m"),
        "day"        => date.strftime("%d"),
        "title"      => slug,
        "categories" => categories.sort.join('/')
      }.inject(template) { |result, token|
        result.gsub(/:#{token.first}/, token.last)
      }.gsub("//", "/")
    end
    
    # The generated relative url of this post
    # e.g. /2008/11/05/my-awesome-post
    #
    # Returns <String>
    def url
      site.config['multiviews'] ? generated_path.sub(/\.html$/, '') : generated_path
    end

    # The UID for this post (useful in feeds)
    # e.g. /2008/11/05/my-awesome-post
    #
    # Returns <String>
    def id
      File.join(self.dir, self.slug)
    end
    
    # The post title
    #
    # Returns <String>
    def title
      self.data && self.data["title"]
    end
    
    # The post date and time
    #
    # Returns <Time>
    def date
      @date_with_time ||= begin
        if self.data && self.data.key?("time")
          time = Time.parse(self.data["time"])
          Time.mktime(@date.year, @date.month, @date.day, time.hour, time.min)
        else
          @date
        end
      end
    end
    
    # The path to the post file.
    #
    # Returns <String>
    def path
      File.expand_path(File.join(@base, @name))
    end

    # Calculate related posts.
    #
    # Returns [<Post>]
    def related_posts(posts)
      return [] unless posts.size > 1

      if self.site.lsi
        self.class.lsi ||= begin
          puts "Running the classifier... this could take a while."
          lsi = Classifier::LSI.new
          posts.each { |x| $stdout.print(".");$stdout.flush;lsi.add_item(x) }
          puts ""
          lsi
        end

        related = self.class.lsi.find_related(self.content, 11)
        related - [self]
      else
        (posts - [self])[0..9]
      end
    end

    # Add any necessary layouts to this post
    #   +layouts+ is a Hash of {"name" => "layout"}
    #   +site_payload+ is the site payload hash
    #
    # Returns nothing
    def render(layouts, site_payload)
      # construct payload
      payload =
      {
        "site" => { "related_posts" => related_posts(site_payload["site"]["posts"]) },
        "page" => self.to_liquid
      }
      payload = payload.deep_merge(site_payload)

      do_layout(payload, layouts)
    end

    # Write the generated post file to the destination directory.
    #   +dest+ is the String path to the destination dir
    #
    # Returns nothing
    def write(dest)
      FileUtils.mkdir_p(File.join(dest, dir))

      path = File.join(dest, self.generated_path)

      if template[/\.html$/].nil?
        FileUtils.mkdir_p(path)
        path = File.join(path, "index.html")
      end

      File.open(path, 'w') do |f|
        f.write(self.output)
      end
    end
    
    # Attempt to extract title from topmost header or slug.
    #
    # Returns <String>
    def extract_title_from_first_header_or_slug
      # Done before the transformation to HTML, or it won't go into <title>s.
      self.data["title"] ||=
        case content_type
        when 'textile'
          self.content[/\A\s*h\d\.\s*(.+)/, 1]               # h1. Header
        when 'markdown'
          self.content[/\A\s*#+\s*(.+)\s*#*$/, 1] ||         # "# Header"
          self.content[/\A\s*(\S.*)\r?\n\s*(-+|=+)\s*$/, 1]  # "Header\n====="
        end
      self.data["title"] ||= self.slug.split('-').select {|w| w.capitalize! || w }.join(' ')
    end

    # Convert this post into a Hash for use in Liquid templates.
    #
    # Returns <Hash>
    def to_liquid
      { "title" => self.title,
        "url" => self.url,
        "date" => self.date,
        "id" => self.id,
        "path" => self.path,
        "topics" => self.topics,
        "categories" => self.categories,
        "tags" => self.tags,
        "next" => self.next,
        "previous" => self.previous,
        "content" => self.content }.deep_merge(self.data)
    end

    def inspect
      "<Post: #{self.id}>"
    end

    def next
      pos = self.site.posts.index(self)

      if pos && pos < self.site.posts.length-1
        self.site.posts[pos+1]
      else
        nil
      end
    end

    def previous
      pos = self.site.posts.index(self)
      if pos && pos > 0
        self.site.posts[pos-1]
      else
        nil
      end
    end
  end

end
