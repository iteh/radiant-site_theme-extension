require 'zip/zip'
require 'zip/zipfilesystem'
require 'fileutils'
require 'hpricot'

class Skin < ActiveRecord::Base

  DIRECTORY_SEPARATOR = "-__-"
  PUBLIC_THEMES_ROOT = Rails.public_path, "system", "themes"

  has_attached_file :image, :styles => {:thumb => "100x100", :small => "200x200", :medium => "300x300", :large => "500x500"}
  has_attached_file :archive, :path => ":rails_root/lib/:class/:attachment/:id/:basename.:extension", :url => ":rails_root/lib/:class/:attachment/:id/:basename.:extension"

  belongs_to :created_by, :class_name => 'User'
  belongs_to :updated_by, :class_name => 'User'
  has_many :sites

  validates_uniqueness_of :name

  def unzip_and_process_skin
    #archive_name = self.archive_file_name.delete('.zip')
    archive_name = self.archive_file_name.chomp(File.extname(self.archive_file_name))
    archive = Zip::ZipFile.open(self.archive.path, Zip::ZipFile::CREATE)

    begin
      archive.get_entry("#{archive_name}/#{archive_name}.yml")
    rescue Errno::ENOENT => e
      raise "The file you tried to upload appears invalid. Please check it, and try again."
    end

    conf = YAML::parse(archive.read("#{archive_name}/#{archive_name}.yml"))

    if Skin.exists?(:name => conf.select("/name")[0].value)
      self.delete
      raise ActiveRecord::RecordNotSaved
    else
      # Open a copy of the skin shot and "paperclip" it to our skin model
      skin_shot_path = File::join RAILS_ROOT, "public", "images", "admin", "skin_shots"
      Dir.mkdir(skin_shot_path) unless File.directory?(skin_shot_path)
      img = File.new("#{skin_shot_path}/#{archive_name}.png", "w+")
      img << archive.read("#{archive_name}/#{archive_name}.png")
      self.image = img
      self.name = conf.select("/name")[0].value
      self.description = conf.select("/description")[0].value
      self.skin_type = conf.select("/type")[0].value
      self.price = conf.select("/price")[0].value
      self.save!
      File.delete(img.path)
    end
  end

  def fix_image_source(src, skin_root, public_theme_path)
    match = src.match(/(\.\.\/)*(images\/)?(.*)/)
    image_without_img_prefix = match[3]
    img = Image.find_by_title(image_without_img_prefix.gsub(/\//, DIRECTORY_SEPARATOR))
    new_src = nil
    if img && img.asset then
      new_src = img.asset.url(:original, false)
    elsif File.exist?(File.join(skin_root, "public", "images", image_without_img_prefix))
      new_src = File.join(public_theme_path.gsub(Rails.public_path, ''), 'images', image_without_img_prefix)
    end
    (new_src) ? new_src : src
  end

  def calc_public_theme_path(site, skin_name)
    public_theme_path = File::join PUBLIC_THEMES_ROOT, site.id.to_s, skin_name
    public_theme_path
  end

  # Activate Skin on user's site.
  #----------------------------------------------------------------------------
  def activate_on(site, user)

    # Determine if this site already has an active skin. If it does raise an error and 
    # tell the user to deactivate their current skin before activating a new one.
    if site.skin
      raise "You already have an active skin: <strong>#{site.skin.name}</strong>. Deactive your current skin, before activating a new skin."
    end

    deactivate_on(site)
    skin_name = self.archive_file_name.chomp(File.extname(self.archive_file_name))
    skin_zip = Zip::ZipFile.open(self.archive.path, Zip::ZipFile::CREATE)

    # Extract skin zip contents. We will remove this folder when were done.
    extract_point = File::join RAILS_ROOT, "tmp", "skins", "extracts"
    skin_root = File::join extract_point, site.id.to_s, skin_name

    # Make sure this skin hasn't already been extracted. If it has delete it.
    FileUtils.rm_rf(File.join(extract_point, site.id.to_s)) if File.exist?(File.join(extract_point, site.id.to_s))

    # Create a new folder in tmp/skins/extracts and dump the contents of the skin zip in there.
    skin_zip.each { |e|
      fpath = File.join(extract_point, site.id.to_s, e.name)
      FileUtils.mkdir_p(File.dirname(fpath))
      skin_zip.extract(e, fpath)
    }

    # create a new folder for public assets

    public_theme_path = calc_public_theme_path(site, skin_name)
    FileUtils.mkdir_p(File.dirname(public_theme_path))

    # copy public stuff to public themes folder

    FileUtils.cp_r File.join(skin_root, "public/."), public_theme_path if File.directory?(File.join(skin_root, "public"))

    # Add Skin images to assets
    Dir.glob("#{skin_root}/images/**/**/*.{jpg,png,gif}").each do |image|
      img_name = ((image.gsub(/^(.*)#{skin_name}\/images\//, '')).gsub(/\//, DIRECTORY_SEPARATOR))
      new_filename =  File.join(File.dirname(image), img_name)
      FileUtils.mv image, new_filename if image != new_filename
      img = File.open(new_filename, "r")
      asset = Image.new
      asset.asset = img
      asset.title = img_name
      asset.created_by_id = user.id if asset.respond_to? :created_by_id
      asset.site_id = site.id
      asset.skin_image = true
      asset.save!
    end

    Dir.glob("#{skin_root}/javascripts/**/*").each do |file_name|
      js_name = ((file_name.gsub(/^(.*)#{skin_name}\/javascripts\//, '')).gsub(/\//, DIRECTORY_SEPARATOR))
      js_content = File.read(file_name)
      js = Javascript.find_or_initialize_by_name(
              :name => js_name,
              :content => js_content,
              :site_id => site.id,
              :created_by_id => user.id,
              :skin => true
      )
      js.save!
    end

    Dir.glob("#{skin_root}/stylesheets/**/*").each do |file_name|
      style_name = ((file_name.gsub(/^(.*)#{skin_name}\/stylesheets\//, '')).gsub(/\//, DIRECTORY_SEPARATOR))
      style_content = File.read(file_name)

      # url(blue-glossy/background-2.jpg)
      # 3 =>  blue-glossy/background-2.jpg
      # url(../images/background-2.jpg)
      # 3 =>  background-2.jpg

#      style_content = style_content.gsub(/url\(['"]?([\w\.\/-]*)['"]?\)/) { |match|
#        "url(#{fix_image_source($1, skin_root, public_theme_path)})"
#      }
      style = Stylesheet.find_or_initialize_by_name(
              :name => style_name,
              :content => style_content,
              :site_id => site.id,
              :created_by_id => user.id,
              :skin => true
      )
      style.save!
    end

    # Create a default skin-homepage
#    homepage = Page.new


    Dir.glob("#{skin_root}/layouts/**/*.{yml}").each do |file_name|
      #layout_name = ((file_name.gsub(/^(.*)#{skin_name}\/layouts\//, '')).gsub(/\//, DIRECTORY_SEPARATOR)).split('.').first
      layout_config = YAML::load_file(file_name)
      layout_content = File.read(file_name.gsub(".yml",""))

      layout = Layout.find_or_initialize_by_name(
              :name => layout_config["name"],
              :content => layout_content,
              :site_id => site.id,
              :created_by_id => user.id,
              :content_type => layout_config["content_type"],
              :skin_layout => true
      )

#FIXXME: this is hardcoded for the moment
# FIXXXXMEEEE : move this to a converter to unclutter the themes import
#      doc = Hpricot(layout_content)
#
#      all_js = Array.new
#      doc.search('script').each do |js|
#        if js.attributes['src'] then
#          tag = js.attributes['src']
#          tag = tag.gsub("js/", '')
#          javascript = Javascript.find_by_name("#{skin_name}-#{tag}")
#          js.attributes["src"] = javascript.url if javascript
#          all_js << javascript if javascript
#        end unless js.attributes['ignore'] && js.attributes['ignore'].match(/true/)
#      end
#
#      js = Javascript.find_or_initialize_by_name(
#              :name => "#{skin_name}-all-js-#{layout_name}",
#              :content => (all_js.map { |js| "<r:javascript name=\"#{js.name}\" as=\"content\" />" }).join("\n"),
#              :site_id => site.id,
#              :created_by_id => user.id,
#              :skin => true
#      )
#      js.save!
#
#      doc = Hpricot(doc.to_s)
#      all_css = Array.new
#      doc.search('link').each do |css|
#        if css.attributes['href'] && css.attributes['rel'].match(/stylesheet/) then
#          tag = css.attributes['href']
#          tag = tag.gsub("css/", '')
#          tag = tag.gsub("styles/", "styles#{DIRECTORY_SEPARATOR}")
#          stylesheet = Stylesheet.find_by_name("#{skin_name}-#{tag}")
#          css.attributes["href"] = stylesheet.url if stylesheet
#          all_css << stylesheet if stylesheet
#        end
#      end
#
#      style = Stylesheet.find_or_initialize_by_name(
#              :name => "#{skin_name}-all-css-#{layout_name}",
#              :content => (all_css.map { |css| "<r:stylesheet name=\"#{css.name}\" as=\"content\" />" }).join("\n"),
#              :site_id => site.id,
#              :created_by_id => user.id,
#              :skin => true
#      )
#      style.save!


#      doc = Hpricot(doc.to_s)
#      doc.search('img').each do |image|
#        if image.attributes['src'] then
#          image.attributes["src"] = fix_image_source(image.attributes['src'], skin_root, public_theme_path)
#        end
#      end

#      layout.content = doc.to_s
      layout.save!

      #set root page to standard layout
#      root_page.layout = Layout.find_by_name("#{skin_name}-standard")
#      root_page.save!

#      page = Page.find_or_initialize_by_slug(
#              :title => "Layout #{layout_name} Examples",
#              :layout_id => layout.id,
#              :slug => layout_name,
#              :breadcrumb => layout_name,
#              :description => 'ignore_export',
#              :keywords => '',
#              :created_by_id => user.id,
#              :status_id => 100,
#              :site_id => site.id,
#              :parent_id => homepage.id,
#              :skin_page => true
#      )
#      page.save!
#
#      part = PagePart.new(
#              :name => "body",
#              :content => "Example text",
#              :page_id => page.id,
#              :skin_page_part =>  true
#      )
#      part.save!

    end

#    root_page_config_file = Dir.glob("#{skin_root}/pages/*.{yml}").first
#    root_page_config = YAML::load_file(root_page_config_file)
#    page_class = (root_page_config["class_name"] && !root_page_config["class_name"].empty?) ?  root_page_config["class_name"] : "Page"
#    root_layout = Layout.find_by_name(root_page_config.delete("layout_name")) if root_page_config["layout_name"]
#    root_page = page_class.constantize.find_or_initialize_by_slug(root_page_config)
#    root_page.update_attributes(root_page_config)
#    root_page.layout = root_layout if root_layout
#    root_page.save!

#    child_path =  "#{skin_root}/pages/#{File.basename(root_page_config_file,".yml")}_children"
    recursive_page_import("#{skin_root}/pages",nil,site,user)


    Dir.glob("#{skin_root}/forms/*.{yml}").each do |form_config_file|
      form_config = YAML::load_file(form_config_file)
      form_parts_path = File.join(File.dirname(form_config_file),File.basename(form_config_file,".yml"))

      %w{body content config}.each do |part|
        File.exist?(File.join(form_parts_path,part.to_s)) ? form_config[part] = File.read(part_file = File.join(form_parts_path,part.to_s)) : "no inputfile #{part_file}"
      end

      form = Form.find_or_initialize_by_title(
              :title => form_config["title"] || "No Title given #{self.id}" ,
              :action => form_config["action"],
              :redirect_to => form_config["redirect_to"],
              :config => form_config["config"],
              :body => form_config["body"],
              :content => form_config["content"],
              :site_id => site.id,
              :skin =>  true
      )

      form.save!

    end

#
#
#
#    # Create a default homepage and stylesheet
#    homepage = Page.new
#    stylesheet = Page.new
#
#    homepage.title = 'Home'
#    homepage.layout_id = layout.id
#    homepage.slug = '/'
#    homepage.breadcrumb = "Home"
#    homepage.description = ''
#    homepage.keywords = ''
#    homepage.created_by_id = user.id
#    homepage.status_id = 100
#    homepage.site_id = site.id
#    homepage.skin_page = true
#    homepage.save!
#


    # Create page snippets
    Dir.glob("#{skin_root}/snippets/**/*").each do  |file|
        filter_extensions_regexp = (TextFilter.descendants.map{|filter| filter.filter_name.downcase} << "html").join('|')
        snippet = Snippet.find_or_initialize_by_name(
                :name => File.basename(file).gsub(/\.(#{filter_extensions_regexp})/,"").strip,
                :content => File.read(file),
                :site_id => site.id,
                :created_by_id => user.id,
                :skin_snippet => true
        )
        snippet.save!

    end
#
#    # Create default pages.
#    Dir.foreach("#{extract_point}/#{site.id.to_s}/#{skin_name}/pages") { |page|
#      next if page == '.'
#      next if page == '..'
#
#      File.open("#{extract_point}/#{site.id.to_s}/#{skin_name}/pages/#{page}", "r") do |file|
#        contents = ""
#        while line = file.gets
#          if line =~ /(<r:assets:.+\/>)/
#            line = insert_asset_url(line, site.id)
#          end
#          line.gsub!(/\{site_id\}/, site.id.to_s)
#          contents << line
#        end
#
#        cpage = Page.new
#        cpage.title = page
#        cpage.layout_id = layout.id
#        cpage.slug = page
#        cpage.breadcrumb = page
#        cpage.description = ''
#        cpage.keywords = ''
#        cpage.created_by_id = user.id
#        cpage.status_id = 100
#        cpage.site_id = site.id
#        cpage.parent_id = homepage.id
#        cpage.skin_page = true
#        cpage.save!
#
#        part = PagePart.new(
#                :name => 'body',
#                :content => contents,
#                :page_id => cpage.id,
#                :skin_page_part => true
#        )
#        part.save!
#
#      end
#
#
#    }


    # Remove skin zip content
    FileUtils.rm_r("#{extract_point}/#{site.id.to_s}/#{skin_name}")

    # Tell the site what skin we're using
    self.sites << site
  end

  # Deactive Skin on current site.  
  #----------------------------------------------------------------------------
  def deactivate_on(site)
    #Layout.delete_all(["site_id = ? AND name = ?", site.id, "#{self.name.downcase}"])
    #Layout.delete_all(["site_id = ? AND name = ?", site.id, "stylesheet"])

    pages = Page.find(:all, :conditions => ["site_id = ? AND skin_page = ?", site.id, true])
    pages.each { |page|
      page.parts.each { |part|
        PagePart.delete(part.id)
      }
      Page.delete(page.id)
    }

    #snippets = Snippet.find(:all, :conditions => ["site_id = ? AND skin_snippet = ?", site.id, true])
    #snippets.each { |snippet|
    #  Snippet.destroy(snippet.id)
    #}

    assets = Image.find(:all, :conditions => ["site_id = ? AND skin_image = ?", site.id, true])
    assets.each { |asset|
      Image.destroy(asset.id)
    }

    FileUtils.rm_rf(calc_public_theme_path(site, self.name)) if File.exist?(calc_public_theme_path(site, self.name))


    Layout.delete_all(["site_id = ? AND skin_layout = ?", site.id, true])

    Snippet.delete_all(["site_id = ? AND skin_snippet = ?", site.id, true])
    TextAsset.delete_all(["site_id = ? AND skin = ?", site.id, true])
    Form.delete_all(["site_id = ? AND skin = ?", site.id, true])

    # Site no longer has this skin.
    self.sites.delete(site)
  end

  # Simple Search  
  #----------------------------------------------------------------------------
  def self.search(search, page)
    paginate :per_page => 12, :page => page,
             :conditions => ['name like ? || description like ?', "%#{search}%", "%#{search}%"], :order => 'name'
  end


  # Parse radius tags.
  #----------------------------------------------------------------------------
  def insert_asset_url(line, site_id)
    original_line = line
    matches = []
    doc = Hpricot(line).search('img').each do |img|
      r_tag = img.attributes['src']
      r_tag.gsub(/(["'])(?:\\\1|.)*?\1/) { |match|
        matches.push(match)
      }
    end

    asset_title = matches[0][1..-2]
    asset_size = matches[1][1..-2]
    asset = Image.first(:conditions => {:title => asset_title, :site_id => site_id})
    if asset_size != nil
      original_line.gsub!(/(<r:assets:url.+\/>)(?=")/, "/assets/#{asset.id}/#{asset_title}_#{asset_size}#{File.extname(asset.asset_file_name)}")
    else
      original_line.gsub!(/(<r:assets:url.+\/>)(?=")/, "/assets/#{asset.id}/#{asset_title}#{File.extname(asset.asset_file_name)}")
    end
  end

  def trim(str)
    str.chop!
    str.slice!(1, str.length)
  end

  def recursive_page_import(path,parent,site,user)
    Dir.glob("#{path}/*.{yml}").each do |page_config_file|
      page_config = YAML::load_file(page_config_file)
      layout = Layout.find_by_name(page_config.delete("layout_name")) if page_config["layout_name"]
      page_class = (page_config["class_name"] && !page_config["class_name"].empty?) ?  page_config["class_name"] : "Page"
      page = page_class.constantize.find_or_initialize_by_slug(page_config)
      page.layout = layout if layout
      page.parent = parent if parent
      page.site_id = site.id
      page.status = Status[:published] unless page_config["status_id"]
      page.published_at = Time.now unless page_config["published_at"]
      page.created_by_id = user.id
      page.save!
      base_name =  File.basename(page_config_file,".yml")

      Dir.glob("#{path}/#{base_name}_parts/*.yml").each do |part_config_file|
        part_config = YAML::load_file(part_config_file)
        part_config["page_id"] = page.id
        page_part = PagePart.find_or_initialize_by_page_id_and_name(part_config)
        part_content_file_extension = part_config["filter_id"].empty? ? "html" : part_config["filter_id"].downcase
        part_content_file = File.basename(part_config_file,"yml")+part_content_file_extension
        page_part.content = File.read(File.join(File.dirname(part_config_file),part_content_file))
        page_part.save!
      end
      images_path = "#{path}/#{base_name}_attachments"
      if File.directory?(images_path)
        all_attachments = Dir.glob("#{images_path}/*").reject{|x| x.match(/yml$/)}.map{|file| File.basename(file)}
        images = YAML.load_file(File.join(images_path,"attachments.yml"))
        images.each do |image|
          attachment = PageAttachment.new
          attachment.uploaded_data = ActionController::TestUploadedFile.new(File.join(images_path,image["file"]),image["mime_type"])
          attachment.site_id = site.id
          attachment.title = image["file"]
          attachment.description = image["description"]
          attachment.save!
          all_attachments.delete_if{|element| element["file"] == image["file"]}
          page.attachments <<  attachment
        end
        all_attachments.each do |image|
          attachment = PageAttachment.new
          attachment_file = File.join(images_path,image)
          attachment_mime_type = `file -ib #{attachment_file}`.gsub(/\n/,"").split(';').first
          attachment.uploaded_data = ActionController::TestUploadedFile.new(attachment_file,attachment_mime_type)
          attachment.site_id = site.id
          attachment.title = image
          attachment.save!
          page.attachments <<  attachment
        end
      end
      page.save!

      recursive_page_import("#{path}/#{base_name}_children",page,site,user) if File.directory?("#{path}/#{base_name}_children")
    end
  end
end
