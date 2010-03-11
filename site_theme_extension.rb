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
			 admin.resources :skins
		 end
		 map.activate_skin 'admin/skins/activate/:id', :controller => 'admin/skins', :action => 'activate'
		 map.deactivate_skin 'admin/skins/deactivate/:id', :controller => 'admin/skins', :action => 'deactivate'
     map.search 'admin/skins/search', :controller => 'admin/skins', :action => 'search_skins'
   end
  
  def activate
    tab 'Design' do 
      add_item("Theme", "/admin/skins")
    end
    UserActionObserver.instance.send :add_observer!, Skin

    Page.send :include, SiteSkinTags
    Site.class_eval {
      belongs_to :skin
    }
    
    Radiant::AdminUI.class_eval do
      attr_accessor :skins
    end

    admin.skins = load_default_skin_regions
  end

  private

  # Define the regions to be used in the views and partials
  def load_default_skin_regions
    returning OpenStruct.new do |skin|
      skin.index = Radiant::AdminUI::RegionSet.new  do |index|
        index.main.concat %w{skin_list}
        index.sidebar.concat %w{sidebar_boxes}
      end
      skin.search_skins = Radiant::AdminUI::RegionSet.new  do |search_skins|
        search_skins.main.concat %w{skin_list}
        search_skins.sidebar.concat %w{sidebar_boxes}
      end
    end
  end
  
end
