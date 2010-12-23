def recursive_dump(export_path, page)
  FileUtils.mkdir_p export_path
  unless page.description && page.description.match(/ignore_export/)
    puts "exporting #{page.title}"
    recursive_path = File::join(export_path, page.title.parameterize)
    File.open("#{recursive_path}.yml", 'w') do |out|
      page_hash = page.attributes.reject{|key,value| %w{ layout_id parent_id virtual position delta published_at status_id lock_version updated_by_id created_at updated_at skin_page site_id id created_by_id}.include?(key)}
      page_hash["layout_name"] = page.layout.name if page.layout_id
      out.write(page_hash.to_yaml)
    end
    parts_path =  "#{recursive_path}_parts"
    FileUtils.mkdir_p parts_path

    page.parts.each do |part|
      File.open(File.join(parts_path,"#{part.name.parameterize}.yml"), 'w') do |out|
        part_hash = part.attributes.reject{|key,value| %w{ skin_page_part id page_id content}.include?(key)}
        out.write(part_hash.to_yaml)
      end
      File.open(File.join(parts_path,"#{part.name.parameterize}.#{part.filter.filter_name.nil? ? "html": part.filter.filter_name.downcase}"), 'w') do |out|
        out.write(part.content)
      end
    end
    page.children.each do |child|
      recursive_dump("#{recursive_path}_children", child)
    end
  end
end

namespace :radiant do
  namespace :extensions do
    namespace :site_theme do

      desc "Runs the migration of the Site Theme extension"
      task :migrate => :environment do
        require 'radiant/extension_migrator'
        if ENV["VERSION"]
          SiteThemeExtension.migrator.migrate(ENV["VERSION"].to_i)
        else
          SiteThemeExtension.migrator.migrate
        end
      end

      desc "Copies public assets of the Site Theme to the instance public/ directory."
      task :update => :environment do
        is_svn_or_dir = proc { |path| path =~ /\.svn/ || File.directory?(path) }
        puts "Copying assets from SiteThemeExtension"
        Dir[SiteThemeExtension.root + "/public/**/*"].reject(&is_svn_or_dir).each do |file|
          path = file.sub(SiteThemeExtension.root, '')
          directory = File.dirname(path)
          mkdir_p RAILS_ROOT + directory, :verbose => false
          cp file, RAILS_ROOT + path, :verbose => false
        end
      end

      desc "export pages to path, use SITE_ID and EXPORT_PATH to specify options"
      task :export_pages => :environment do
        require 'highline/import'
        say "ERROR: you must specify a SITE_ID #{ENV['SITE_ID']}" and exit if !ENV['SITE_ID']

        export_path = build_export_path('pages')
        root_page = Page.find(:first, :conditions => ["site_id = ? AND slug = ?", ENV['SITE_ID'], "/"])
        recursive_dump(export_path, root_page)
      end

      desc "export snippets to path, use SITE_ID and EXPORT_PATH to specify options"
      task :export_snippets => :environment do
        require 'highline/import'
        say "ERROR: you must specify a SITE_ID #{ENV['SITE_ID']}" and exit if !ENV['SITE_ID']

        export_path = build_export_path('snippets')
        FileUtils.mkdir_p export_path
        Snippet.find(:all,:conditions => ["site_id = ? ", ENV['SITE_ID']]).each do |snippet|
          puts "exporting #{snippet.name}"
          extension = snippet.filter.filter_name.nil? ? "html" : snippet.filter.filter_name.downcase
          path = File::join(export_path, "#{snippet.name.strip}.#{extension}")
          File.open("#{path}", 'w') do |out|
            out.write(snippet.content)
          end
        end
      end

      desc "export stylesheets to path, use SITE_ID and EXPORT_PATH to specify options"
      task :export_stylesheets => :environment do
        require 'highline/import'
        say "ERROR: you must specify a SITE_ID #{ENV['SITE_ID']}" and exit if !ENV['SITE_ID']

        export_path = build_export_path('stylesheets')
        FileUtils.mkdir_p export_path
        Stylesheet.find(:all,:conditions => ["site_id = ? ", ENV['SITE_ID']]).each do |stylesheet|
          puts "exporting #{stylesheet.name}"
          path = File::join(export_path, stylesheet.name)
          File.open("#{path}", 'w') do |out|
            out.write(stylesheet.content)
          end
        end
      end

      desc "export javascripts to path, use SITE_ID and EXPORT_PATH to specify options"
      task :export_javascripts => :environment do
        require 'highline/import'
        say "ERROR: you must specify a SITE_ID #{ENV['SITE_ID']}" and exit if !ENV['SITE_ID']

        export_path = build_export_path('javascripts')
        FileUtils.mkdir_p export_path
        Javascript.find(:all,:conditions => ["site_id = ? ", ENV['SITE_ID']]).each do |javascript|
          puts "exporting #{javascript.name}"
          path = File::join(export_path, javascript.name)
          File.open("#{path}", 'w') do |out|
            out.write(javascript.content)
          end
        end
      end


      desc "export forms to path, use SITE_ID and EXPORT_PATH to specify options"
      task :export_forms => :environment do
        require 'highline/import'
        say "ERROR: you must specify a SITE_ID #{ENV['SITE_ID']}" and exit if !ENV['SITE_ID']

        export_path = build_export_path('forms')
        FileUtils.mkdir_p export_path
        Form.find(:all,:conditions => ["site_id = ? ", ENV['SITE_ID']]).each do |form|
          puts "exporting #{form.title}"
          path = File::join(export_path, form.title.parameterize)
          File.open("#{path}.yml", 'w') do |out|
            out.write(form.attributes.reject{|key,value| %w{body config content updated_by_id created_at updated_at skin site_id id created_by_id}.include?(key)}.to_yaml)
          end
          FileUtils.mkdir_p path
          %w{body content config}.each do |part|
            File.open(File.join(path,part), 'w') do |out|
              out.write(form.send(part))
            end
          end

        end
      end

      desc "export layouts to path, use SITE_ID and EXPORT_PATH to specify options"
      task :export_layouts => :environment do
        require 'highline/import'
        say "ERROR: you must specify a SITE_ID #{ENV['SITE_ID']}" and exit if !ENV['SITE_ID']

        export_path = build_export_path('layouts')
        FileUtils.mkdir_p export_path
        Layout.find(:all,:conditions => ["site_id = ? ", ENV['SITE_ID']]).each do |layout|
          puts "exporting #{layout.name}"
          path = File::join(export_path, layout.name)
          File.open("#{path}.yml", 'w') do |out|
            out.write(layout.attributes.reject{|key,value| %w{ content lock_version updated_by_id created_at updated_at skin_layout site_id id created_by_id}.include?(key)}.to_yaml)
          end
          File.open(path, 'w') do |out|
              out.write(layout.content)
          end
        end
      end

      desc "export site, use SITE_ID and EXPORT_PATH to specify options"
      task :export_site => :environment do
        Rake::Task['radiant:extensions:site_theme:export_stylesheets'].execute
        Rake::Task['radiant:extensions:site_theme:export_javascripts'].execute
        Rake::Task['radiant:extensions:site_theme:export_layouts'].execute
        Rake::Task['radiant:extensions:site_theme:export_pages'].execute
        Rake::Task['radiant:extensions:site_theme:export_forms'].execute
        Rake::Task['radiant:extensions:site_theme:export_snippets'].execute
      end
    end
  end

  def build_export_path(path)
    result_path = File::join(RAILS_ROOT, 'tmp', 'export',path)
    if ENV['EXPORT_PATH']
      export_path = Pathname.new(ENV['EXPORT_PATH'])
      if export_path.absolute?
        result_path = File::join(export_path,path)
      else
        result_path =  File::join(RAILS_ROOT, export_path,path)
      end
    else
      result_path =  File::join(RAILS_ROOT, 'tmp', 'export',path)
    end
    result_path
  end
end
