# Uncomment this if you reference any of your controllers in activate
require_dependency 'application_controller'

# Going to need this to add regions to the extension interface
require 'ostruct'

class SiteThemeExtension < Radiant::Extension
  version "1.0"
  description "Custom themes for Radiant Sites"
  url ""
  
   define_routes do |map|
     map.namespace :admin, :member => { :remove => :get } do |admin|
			 admin.resources :themes, :member => {:activate => :get, :deactivate => :put}, :collection => {:search => :get}
		 end
   end
  
  def activate
    tab 'Design' do 
      add_item("Themes", "/admin/themes")
    end
    UserActionObserver.instance.send :add_observer!, Skin

    Page.send :include, SiteSkinTags
    Site.class_eval {
      belongs_to :skin
    }
    
    Radiant::AdminUI.class_eval do
      attr_accessor :themes
    end

    admin.themes = load_default_themes_regions
  end

  private

  # Define the regions to be used in the views and partials
  def load_default_themes_regions
    returning OpenStruct.new do |themes|
      themes.index = Radiant::AdminUI::RegionSet.new  do |index|
        index.main.concat %w{theme_list}
        index.sidebar.concat %w{sidebar_boxes}
      end
      themes.search_themes = Radiant::AdminUI::RegionSet.new  do |search_themes|
        search_themes.main.concat %w{theme_list}
        search_themes.sidebar.concat %w{sidebar_boxes}
      end
    end
  end
  
end
