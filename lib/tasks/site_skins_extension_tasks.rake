def recursive_dump(export_path, page)
  FileUtils.mkdir_p export_path
  unless page.description && page.description.match(/ignore_export/)
    puts "exporting #{page.title}"
    recursive_path = File::join(export_path, page.title.parameterize)
    File.open("#{recursive_path}.yml", 'w') do |out|
      YAML.dump(page, out)
    end
    page.parts.each do |part|
      File.open("#{recursive_path}_part_#{part.name.parameterize}.yml", 'w') do |out|
        YAML.dump(part, out)
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
        say "ERROR: you must specify a site_id #{ENV['SITE_ID']}" and exit if !ENV['SITE_ID']

        export_path = ENV['EXPORT_PATH'] ? ENV['EXPORT_PATH'] : File::join(RAILS_ROOT, 'tmp', 'export')
        root_page = Page.find(:first, :conditions => ["site_id = ? AND slug = ?", ENV['SITE_ID'], "/"])
        recursive_dump(export_path, root_page)
      end
    end
  end
end
