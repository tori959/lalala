module Jekyll

  class Site
    attr_accessor :config, :layouts, :posts, :collated_posts, :categories, :tags
    attr_accessor :source, :dest, :lsi, :pygments, :pygments_cache, :permalink_style,
                  :sass, :post_defaults

    # Initialize the site
    #   +config+ is a Hash containing site configurations details
    #
    # Returns <Site>
    def initialize(config)
      self.config          = config.clone

      self.source          = config['source']
      self.dest            = config['destination']
      self.lsi             = config['lsi']
      self.pygments        = config['pygments']
      self.pygments_cache  = config['pygments_cache']
      self.permalink_style = config['permalink'].to_sym
      self.post_defaults   = config['post_defaults'] || {}

      self.reset
      self.setup
    end

    def reset
      self.layouts         = {}
      self.posts           = []
      self.collated_posts  = Hash.new {|h,k| h[k] = Hash.new {|h,k| h[k] = Hash.new {|h,k| h[k] = [] } } }
      self.categories      = Hash.new { |hash, key| hash[key] = [] }
      self.tags            = Hash.new { |hash, key| hash[key] = [] }
    end

    def setup
      # Check to see if LSI is enabled.
      require 'classifier' if self.lsi
      
      if self.config['sass']
        begin
          gem 'sass', '~>3.1'
          require 'sass'
          self.sass = true
          puts 'Using Sass for CSS generation'
        rescue LoadError
          puts 'You must have the sass gem installed first'
        end
      end
      
      if self.config['haml']
        begin
          gem 'haml', '~>3.0'
          require 'haml'
          require 'jekyll/haml_helpers'
          helpers = File.join(source, '_helpers.rb')
          require helpers if File.exist?(helpers)
          puts 'Enabled Haml'
        rescue LoadError
          puts $!.inspect
          puts 'You must have the haml gem installed first'
        end
      end
      
      if self.pygments_cache
        require 'fileutils'
        FileUtils.mkdir_p(pygments_cache)
        require 'digest/md5'
      end

      # Set the Markdown interpreter (and Maruku self.config, if necessary)
      case self.config['markdown']
        when 'rdiscount'
          begin
            require 'rdiscount'

            def markdown(content)
              RDiscount.new(content).to_html
            end

            puts 'Using rdiscount for Markdown'
          rescue LoadError
            puts 'You must have the rdiscount gem installed first'
          end
        when 'maruku'
          begin
            require 'maruku'

            def markdown(content)
              Maruku.new(content).to_html
            end

            if self.config['maruku']['use_divs']
              require 'maruku/ext/div'
              puts 'Maruku: Using extended syntax for div elements.'
            end

            if self.config['maruku']['use_tex']
              require 'maruku/ext/math'
              puts "Maruku: Using LaTeX extension. Images in `#{self.config['maruku']['png_dir']}`."

              # Switch off MathML output
              MaRuKu::Globals[:html_math_output_mathml] = false
              MaRuKu::Globals[:html_math_engine] = 'none'

              # Turn on math to PNG support with blahtex
              # Resulting PNGs stored in `images/latex`
              MaRuKu::Globals[:html_math_output_png] = true
              MaRuKu::Globals[:html_png_engine] =  self.config['maruku']['png_engine']
              MaRuKu::Globals[:html_png_dir] = self.config['maruku']['png_dir']
              MaRuKu::Globals[:html_png_url] = self.config['maruku']['png_url']
            end
          rescue LoadError
            puts "The maruku gem is required for markdown support!"
          end
      end
    end

    def textile(content)
      RedCloth.new(content).to_html
    end

    # Do the actual work of processing the site and generating the
    # real deal.
    #
    # Returns nothing
    def process
      self.reset
      self.read_layouts
      self.transform_pages
      self.transform_sass if self.sass
      self.write_posts
    end

    # Read all the files in <source>/_layouts into memory for later use.
    #
    # Returns nothing
    def read_layouts
      base = File.join(self.source, "_layouts")
      entries = []
      Dir.chdir(base) { entries = filter_entries(Dir['*.*']) }

      entries.each do |f|
        name = f.split(".")[0..-2].join(".")
        self.layouts[name] = Layout.new(self, base, f)
      end
    rescue Errno::ENOENT => e
      # ignore missing layout dir
    end

    # Read all the files in <base>/_posts and create a new Post object with each one.
    #
    # Returns nothing
    def read_posts(dir)
      base = File.join(self.source, dir, '_posts')
      entries = []
      Dir.chdir(base) { entries = filter_entries(Dir['**/*']) }

      # first pass processes, but does not yet render post content
      entries.each do |f|
        if Post.valid?(f)
          post = Post.new(self, self.source, dir, f)

          if post.published
            self.posts << post
            post.categories.each { |c| self.categories[c] << post }
            post.tags.each { |c| self.tags[c] << post }
          end
        end
      end

      self.posts.sort!

      # second pass renders each post now that full site payload is available
      self.posts.each do |post|
        post.render(self.layouts, site_payload)
        self.collated_posts[post.date.year][post.date.month][post.date.day].unshift(post)
      end

      self.categories.values.map { |ps| ps.sort! { |a, b| b <=> a} }
      self.tags.values.map { |ps| ps.sort! { |a, b| b <=> a} }
    rescue Errno::ENOENT => e
      # ignore missing layout dir
    end

    # Write each post to <dest>/<year>/<month>/<day>/<slug>
    #
    # Returns nothing
    def write_posts
      self.posts.each do |post|
        post.write(self.dest)
      end
    end

    # Copy all regular files from <source> to <dest>/ ignoring
    # any files/directories that are hidden or backup files (start
    # with "." or "#" or end with "~") or contain site content (start with "_")
    # unless they are "_posts" directories or web server files such as
    # '.htaccess'
    #   The +dir+ String is a relative path used to call this method
    #            recursively as it descends through directories
    #
    # Returns nothing
    def transform_pages(dir = '')
      base = File.join(self.source, dir)
      entries = filter_entries(Dir.entries(base))
      directories = entries.select { |e| File.directory?(File.join(base, e)) }
      files = entries.reject { |e| File.directory?(File.join(base, e)) }

      # we need to make sure to process _posts *first* otherwise they
      # might not be available yet to other templates as {{ site.posts }}
      if directories.include?('_posts')
        directories.delete('_posts')
        read_posts(dir)
      end
      [directories, files].each do |entries|
        entries.each do |f|
          if File.directory?(File.join(base, f))
            next if self.dest.sub(/\/$/, '') == File.join(base, f)
            transform_pages(File.join(dir, f))
          else
            first3 = File.open(File.join(self.source, dir, f)) { |fd| fd.read(3) }

            if first3 == "---"
              # file appears to have a YAML header so process it as a page
              page = Page.new(self, self.source, dir, f)
              page.render(self.layouts, site_payload)
              page.write(self.dest)
            else
              # otherwise copy the file without transforming it
              FileUtils.mkdir_p(File.join(self.dest, dir))
              FileUtils.cp(File.join(self.source, dir, f), File.join(self.dest, dir, f))
            end
          end
        end
      end
    end

    # Transform all *.sass files from <dest> to css with the same name
    # and delete source sass files.
    # Returns nothing
    def transform_sass(dir = '')
      base = File.join(self.source, dir)
      entries = Dir.entries(base)
      entries = entries.reject { |e| ['.', '_'].include?(e[0..0]) }
      directories = entries.select { |e| File.directory?(File.join(base, e)) }
      directories.each { |d| transform_sass(File.join(dir, d)) }
      files = entries.reject { |e| File.directory?(File.join(base, e)) }
      files = files.select { |f| File.extname(File.join(base, f)) == ".sass" }
      files.each do |f|
        input = File.open(File.join(base, f), "r")
        result = Sass::Engine.new(input.read, :style => :compact, :load_paths => Array(base)).render
        FileUtils.mkdir_p(File.join(self.dest, dir))
        output = File.open(File.join(self.dest, dir, f).gsub(/.sass\Z/, ".css"), "w") do |o|
          o.write(result)
        end
        FileUtils.rm(File.join(self.dest, dir, f))
      end
    end

    # Constructs a hash map of Posts indexed by the specified Post attribute
    #
    # Returns {post_attr => [<Post>]}
    def post_attr_hash(post_attr)
      # Build a hash map based on the specified post attribute ( post attr => array of posts )
      # then sort each array in reverse order
      hash = Hash.new { |hash, key| hash[key] = Array.new }
      self.posts.each { |p| p.send(post_attr.to_sym).each { |t| hash[t] << p } }
      hash.values.map { |sortme| sortme.sort! { |a, b| b <=> a} }
      return hash
    end

    # The Hash payload containing site-wide data
    #
    # Returns {"site" => {"time" => <Time>,
    #                     "posts" => [<Post>],
    #                     "categories" => [<Post>],
    #                     "tags" => [<Post>],
    #                     "topics" => [<Post>] }}
    def site_payload
      {"site" => {
        "time" => Time.now,
        "posts" => self.posts.sort { |a,b| b <=> a },
        "categories" => post_attr_hash('categories'),
        "tags" => post_attr_hash('tags'),
        "topics" => post_attr_hash('topics')
      }}
    end

    # Filter out any files/directories that are hidden or backup files (start
    # with "." or "#" or end with "~") or contain site content (start with "_")
    # unless they are "_posts" directories or web server files such as
    # '.htaccess'
    def filter_entries(entries)
      entries = entries.reject do |e|
        unless ['_posts', '.htaccess'].include?(e)
          # Reject backup/hidden
          ['.', '_', '#'].include?(e[0..0]) or e[-1..-1] == '~'
        end
      end
    end

  end
end
