#!/usr/bin/env ruby
# Modified by Daniel Choi <dhchoi@gmail.com>
# Modified the RDocRI::Driver class from the original RDoc gem for rdoc_vim gem

gem 'rdoc', '>=3.8'
require 'abbrev'
require 'optparse'
begin
  require 'readline'
rescue LoadError
end
begin
  require 'win32console'
rescue LoadError
end
require 'rdoc/ri'
require 'rdoc/ri/paths'
require 'rdoc/markup'
require 'rdoc/markup/formatter'
require 'rdoc/text'

# For RubyGems backwards compatibility
require 'rdoc/ri/formatter'

class RIVim
  class NotFoundError < StandardError; end

  attr_accessor :stores
  def initialize names
    options = {
      :width => 72,
      :use_cache => true,
      :profile => false,
      :use_system => true,
      :use_site => true,
      :use_home => true,
      :use_gems => true,
      :extra_doc_dirs => []
    }
    @classes = nil
    @formatter_klass = options[:formatter]
    @names = names
    @list = options[:list]
    @doc_dirs = []
    @stores   = []
    RDoc::RI::Paths.each(options[:use_system],
                         options[:use_site],
                         options[:use_home],
                         options[:use_gems],
                         *options[:extra_doc_dirs]) do |path, type|
      if File.exists?(path)
        @doc_dirs << path
        store = RDoc::RI::Store.new path, type
        store.load_cache
        @stores << store
      end
    end
    @list_doc_dirs = false
    @interactive = false
  end

  # Adds paths for undocumented classes +also_in+ to +out+
  def add_also_in out, also_in
    return if also_in.empty?
    out << RDoc::Markup::Rule.new(1)
    out << RDoc::Markup::Paragraph.new("Also found in:")
    paths = RDoc::Markup::Verbatim.new
    also_in.each do |store|
      paths.parts.push store.friendly_path, "\n"
    end
    out << paths
  end

  # Adds a class header to +out+ for class +name+ which is described in
  # +classes+.
  def add_class out, name, classes
    heading = if classes.all? { |klass| klass.module? } then
                name
              else
                superclass = classes.map do |klass|
                  klass.superclass unless klass.module?
                end.compact.shift || 'Object'
                "#{name} < #{superclass}"
              end
    out << RDoc::Markup::Heading.new(1, heading)
    out << RDoc::Markup::BlankLine.new
  end

  # Adds "(from ...)" to +out+ for +store+
  def add_from out, store
    out << RDoc::Markup::Paragraph.new("(from #{store.friendly_path})")
  end

  # Adds +includes+ to +out+
  def add_includes out, includes
    return if includes.empty?
    out << RDoc::Markup::Rule.new(1)
    out << RDoc::Markup::Heading.new(1, "Includes:")
    includes.each do |modules, store|
      if modules.length == 1 then
        include = modules.first
        name = include.name
        path = store.friendly_path
        out << RDoc::Markup::Paragraph.new("#{name} (from #{path})")
        if include.comment then
          out << RDoc::Markup::BlankLine.new
          out << include.comment
        end
      else
        out << RDoc::Markup::Paragraph.new("(from #{store.friendly_path})")
        wout, with = modules.partition { |incl| incl.comment.empty? }
        out << RDoc::Markup::BlankLine.new unless with.empty?
        with.each do |incl|
          out << RDoc::Markup::Paragraph.new(incl.name)
          out << RDoc::Markup::BlankLine.new
          out << incl.comment
        end
        unless wout.empty? then
          verb = RDoc::Markup::Verbatim.new
          wout.each do |incl|
            verb.push incl.name, "\n"
          end
          out << verb
        end
      end
    end
  end

  # Adds a list of +methods+ to +out+ with a heading of +name+
  def add_method_list out, methods, name
    return unless methods && !methods.empty?
    out << RDoc::Markup::Heading.new(1, "#{name}:")
    out << RDoc::Markup::BlankLine.new
    out << RDoc::Markup::IndentedParagraph.new(2, methods.join(', '))
    out << RDoc::Markup::BlankLine.new
  end

  # Returns ancestor classes of +klass+
  def ancestors_of klass
    ancestors = []
    unexamined = [klass]
    seen = []
    loop do
      break if unexamined.empty?
      current = unexamined.shift
      seen << current
      stores = classes[current]
      break unless stores and not stores.empty?
      klasses = stores.map do |store|
        store.ancestors[current]
      end.flatten.uniq
      klasses = klasses - seen
      ancestors.push(*klasses)
      unexamined.push(*klasses)
    end
    ancestors.reverse
  end

  # For RubyGems backwards compatibility
  def class_cache # :nodoc:
  end

  # Hash mapping a known class or module to the stores it can be loaded from
  def classes
    return @classes if @classes
    @classes = {}
    @stores.each do |store|
      store.cache[:modules].each do |mod|
        # using default block causes searched-for modules to be added
        @classes[mod] ||= []
        @classes[mod] << store
      end
    end
    @classes
  end


  # Converts +document+ to text and writes it to the pager
  def display document
    page do |io|
      text = document.accept formatter(io)
      io.write text
    end
  end

  # Outputs formatted RI data for class +name+.  Groups undocumented classes
  def display_class name
    return if name =~ /#|\./
    klasses = []
    includes = []
    found = @stores.map do |store|
      begin
        klass = store.load_class name
        klasses  << klass
        includes << [klass.includes, store] if klass.includes
        [store, klass]
      rescue # Errno::ENOENT
      end
    end.compact
    return if found.empty?
    also_in = []
    includes.reject! do |modules,| modules.empty? end
    out = RDoc::Markup::Document.new
    add_class out, name, klasses
    add_includes out, includes
    found.each do |store, klass|
      comment = klass.comment
      class_methods    = store.class_methods[klass.full_name]
      instance_methods = store.instance_methods[klass.full_name]
      attributes       = store.attributes[klass.full_name]

      if comment.empty? and !(instance_methods or class_methods) then
        also_in << store
        next
      end
      add_from out, store
      unless comment.empty? then
        out << RDoc::Markup::Rule.new(1)
        out << comment
      end
      if class_methods or instance_methods or not klass.constants.empty? then
        out << RDoc::Markup::Rule.new(1)
      end
      unless klass.constants.empty? then
        out << RDoc::Markup::Heading.new(1, "Constants:")
        out << RDoc::Markup::BlankLine.new
        list = RDoc::Markup::List.new :NOTE
        constants = klass.constants.sort_by { |constant| constant.name }
        list.push(*constants.map do |constant|
          parts = constant.comment.parts if constant.comment
          parts << RDoc::Markup::Paragraph.new('[not documented]') if
            parts.empty?
          RDoc::Markup::ListItem.new(constant.name, *parts)
        end)
        out << list
      end
      add_method_list(out,
        (class_methods || []).map {|x| ".#{x}"},
        'Class methods')
      add_method_list(out,
                      (instance_methods || []).map {|x| "#{x}"},
                      'Instance methods')
      add_method_list out, attributes,       'Attributes'
      out << RDoc::Markup::BlankLine.new
    end
    add_also_in out, also_in
    display out
  end


  # Outputs formatted RI data for method +name+
  def display_method name
    found = load_methods_matching name
    raise NotFoundError, name if found.empty?
    filtered = filter_methods found, name
    out = RDoc::Markup::Document.new
    out << RDoc::Markup::Heading.new(1, name)
    out << RDoc::Markup::BlankLine.new
    filtered.each do |store, methods|
      methods.each do |method|
        out << RDoc::Markup::Paragraph.new("(from #{store.friendly_path})")
        unless name =~ /^#{Regexp.escape method.parent_name}/ then
          out << RDoc::Markup::Heading.new(3, "Implementation from #{method.parent_name}")
        end
        out << RDoc::Markup::Rule.new(1)
        if method.arglists then
          arglists = method.arglists.chomp.split "\n"
          arglists = arglists.map { |line| line + "\n" }
          out << RDoc::Markup::Verbatim.new(*arglists)
          out << RDoc::Markup::Rule.new(1)
        end
        out << RDoc::Markup::BlankLine.new
        out << method.comment
        out << RDoc::Markup::BlankLine.new
      end
    end
    display out
  end

  # Outputs formatted RI data for the class or method +name+.
  def display_name name
    return true if display_class name
    #if name =~ /::|#|\./
      display_method name
    #end
    true
  end

  # Use for universal autocomplete
  def display_matches name
    matches = []
    if name =~ /::|#|\./
      matches = list_methods_matching_orig name
      #longest_method = xs.inject("") {|memo, x| x[0].size > memo.size ? x[0] : memo }
      #matches = xs.map {|x| "%-#{longest_method.size}s %s%s" % [x[0], x[1], x[2]] }
    end
    matches = matches.concat classes.select {|k, v| k =~ /^#{name}/ }.map {|k, v| k.to_s }
    puts matches.sort.join("\n")
  end

  def display_method_matches name
    matches = []
    xs = list_methods_matching name
    longest_method = xs.inject("") {|memo, x| x[0].size > memo.size ? x[0] : memo }
    matches = xs.map {|x| "%-#{longest_method.size}s %s%s%s" % [x[0], x[1], x[2], x[0]] }
    puts matches.sort.join("\n")
  end


  def list_methods_matching name
    found = []
    find_methods name do |store, klass, ancestor, types, method|
      if types == :instance or types == :both then
        methods = store.instance_methods[ancestor]
        if methods then
          matches = methods.grep(/^#{Regexp.escape method.to_s}/)
          matches = matches.map do |match|
            [match, klass, '#']
          end
          found.push(*matches)
        end
      end
      if types == :class or types == :both then
        methods = store.class_methods[ancestor]
        next unless methods
        matches = methods.grep(/^#{Regexp.escape method.to_s}/)
        matches = matches.map do |match|
          [match, klass, '::']
        end
        found.push(*matches)
      end
    end
    found.uniq
  end


  # Filters the methods in +found+ trying to find a match for +name+.
  def filter_methods found, name
    regexp = name_regexp name
    filtered = found.find_all do |store, methods|
      methods.any? { |method| method.full_name =~ regexp }
    end
    return filtered unless filtered.empty?
    found
  end

  # Yields items matching +name+ including the store they were found in, the
  # class being searched for, the class they were found in (an ancestor) the
  # types of methods to look up (from #method_type), and the method name being
  # searched for
  def find_methods name
    klass, selector, method = parse_name name
    types = method_type selector
    klasses = nil
    ambiguous = klass.empty?
    if ambiguous then
      klasses = classes.keys
    else
      klasses = ancestors_of klass
      klasses.unshift klass
    end
    methods = []
    klasses.each do |ancestor|
      ancestors = classes[ancestor]
      next unless ancestors
      klass = ancestor if ambiguous
      ancestors.each do |store|
        methods << [store, klass, ancestor, types, method]
      end
    end
    methods = methods.sort_by do |_, k, a, _, m|
      [k, a, m].compact
    end
    methods.each do |item|
      yield(*item) # :yields: store, klass, ancestor, types, method
    end
    self
  end

  # Creates a new RDoc::Markup::Formatter.  If a formatter is given with -f,
  # use it.  If we're outputting to a pager, use bs, otherwise ansi.
  def formatter(io)
    RDoc::Markup::ToRdoc.new
  end

  # Is +file+ in ENV['PATH']?
  def in_path? file
    return true if file =~ %r%\A/% and File.exist? file
    ENV['PATH'].split(File::PATH_SEPARATOR).any? do |path|
      File.exist? File.join(path, file)
    end
  end

  # Lists classes known to ri starting with +names+.  If +names+ is empty all
  # known classes are shown.
  def list_known_classes names = []
    classes = []
    stores.each do |store|
      classes << store.modules
    end
    classes = classes.flatten.uniq.sort
    unless names.empty? then
      filter = Regexp.union names.map { |name| /^#{name}/ }
      classes = classes.grep filter
    end
    puts classes.join("\n")
  end

  # Returns an Array of methods matching +name+
  def list_methods_matching_orig name
    found = []
    find_methods name do |store, klass, ancestor, types, method|
      if types == :instance or types == :both then
        methods = store.instance_methods[ancestor]
        if methods then
          matches = methods.grep(/^#{Regexp.escape method.to_s}/)
          matches = matches.map do |match|
            "#{klass}##{match}"
          end
          found.push(*matches)
        end
      end
      if types == :class or types == :both then
        methods = store.class_methods[ancestor]
        next unless methods
        matches = methods.grep(/^#{Regexp.escape method.to_s}/)
        matches = matches.map do |match|
          "#{klass}::#{match}"
        end
        found.push(*matches)
      end
    end
    found.uniq
  end

  def display_class_symbols name
    return if name =~ /#|\./
    klasses = []
    includes = []
    found = @stores.map do |store|
      begin
        klass = store.load_class name
        klasses  << klass
        includes << [klass.includes, store] if klass.includes
        [store, klass]
      rescue #Errno::ENOENT <-just eat this one?
      end
    end.compact
    return if found.empty?
    includes.reject! do |modules,| modules.empty? end
    found.each do |store, klass|
      comment = klass.comment
      class_methods    = store.class_methods[klass.full_name]
      instance_methods = store.instance_methods[klass.full_name]
      add_to_method_dropdown name, store, class_methods,    'Class methods'
      add_to_method_dropdown name, store, instance_methods, 'Instance methods'
    end
  end

  def add_to_method_dropdown classname, store, methods, name
    return unless methods && !methods.empty?
    methods.each do |method|
      size = nil
      begin
        if name =~ /Class/
          bmethod = method
        else
          bmethod = "##{method}"
        end
        method_obj = store.load_method classname, bmethod
        bsize = method_obj.comment.parts.size
        if bsize > 0
          size = " (#{bsize})"
        end
      rescue #Errno::ENOENT
        puts $!
      end
      if name == 'Class methods'
        method = ".#{method}#{size}"
      else
        method = "##{method}#{size}"
      end
      puts method
    end
  end


  # Loads RI data for method +name+ on +klass+ from +store+.  +type+ and
  # +cache+ indicate if it is a class or instance method.
  def load_method store, cache, klass, type, name
    methods = store.send(cache)[klass]
    return unless methods
    method = methods.find do |method_name|
      method_name == name
    end
    return unless method
    store.load_method klass, "#{type}#{method}"
  end

  # Returns an Array of RI data for methods matching +name+
  def load_methods_matching name
    found = []
    find_methods name do |store, klass, ancestor, types, method|
      methods = []
      methods << load_method(store, :class_methods, ancestor, '::',  method) if
        [:class, :both].include? types
      methods << load_method(store, :instance_methods, ancestor, '#',  method) if
        [:instance, :both].include? types
      found << [store, methods.compact]
    end
    found.reject do |path, methods| methods.empty? end
  end

  # Returns the type of method (:both, :instance, :class) for +selector+
  def method_type selector
    case selector
    when '.', nil then :both
    when '#'      then :instance
    else               :class
    end
  end

  # Returns a regular expression for +name+ that will match an
  # RDoc::AnyMethod's name.
  def name_regexp name
    klass, type, name = parse_name name
    case type
    when '#', '::' then
      /^#{klass}#{type}#{Regexp.escape name}$/
    else
      /^#{klass}(#|::)#{Regexp.escape name}$/
    end
  end
  def page
    yield $stdout
  end

  # Extracts the class, selector and method name parts from +name+ like
  # Foo::Bar#baz.
  #
  # NOTE: Given Foo::Bar, Bar is considered a class even though it may be a
  #       method
  def parse_name(name)
    parts = name.split(/(::|#|\.)/)
    if parts.length == 1 then
      # Daniel Choi fixed this line from the official rdoc
      if parts.first =~ /^[a-z=<|^&*-+\/\[]/ then
        type = '.'
        meth = parts.pop
      else
        type = nil
        meth = nil
      end
    elsif parts.length == 2 or parts.last =~ /::|#|\./ then
      type = parts.pop
      meth = nil
    elsif parts[-2] != '::' or parts.last !~ /^[A-Z]/ then
      meth = parts.pop
      type = parts.pop
    end
    klass = parts.join
    [klass, type, meth]
  end

  def gemdir(gem)
    ENV["GEM_HOME"] + "/gems/#{gem}"
  end

  # TODO
  def open_readme(gem)
    puts gemdir(gem)
    puts `ls #{gemdir(gem)}`
    Dir["#{gemdir(gem)}/README*"].each do |file|
      puts File.read(file)
    end
  end

  class << self
    def run
      ri = self.new ARGV
      if ARGV.first == '-r' # open README for gem
        gem = ARGV[1]
        ri.open_readme gem
      elsif ARGV.first == '-d' # exact match
        ri.display_name ARGV[1]
      elsif ARGV.first == '-m'  # class methods
        ri.display_class_symbols ARGV[1]
      elsif ARGV.first =~ /^[^A-Z]/
        ri.display_method_matches ARGV.first
      else
        ri.display_matches ARGV.first
      end
    rescue NotFoundError
      puts ""
    end
  end
end

if __FILE__ == $0
  RIVim.run
end
