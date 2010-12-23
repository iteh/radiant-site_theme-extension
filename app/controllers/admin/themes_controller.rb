require 'fileutils'
class Admin::ThemesController < ApplicationController

  only_allow_access_to :index, :show, :new, :create, :edit, :update, :remove, :destroy, :activate, :deactivate,
    :when => [ :admin ],
    :denied_url => { :controller => 'admin/pages', :action => 'index' },
    :denied_message => 'You must have admin privileges to perform this action.'

	def index
    @skins = Skin.paginate :page => params[:page] || 1, :per_page => 12, :order => 'name ASC'
	end	

  def show
    @skin = Skin.find(params[:id])
  end

  def update
    @skin = Skin.find(params[:id])
    if @skin.update_attributes(params[:skin])
      redirect_to admin_themes_url
    else
      render :action => 'show'
    end
  end

  def create
    @skin = Skin.new(params[:skin])
    @skin.save!
    begin
		  @skin.unzip_and_process_skin
      redirect_to admin_themes_url
    rescue ActiveRecord::RecordNotSaved => invalid
      @skin.delete
      flash[:error] = "A Skin with that name already exists in the system."
      redirect_to admin_themes_url
    rescue Exception => e
      @skin.delete
      logger.info e.message
      logger.info e.backtrace
      flash[:error] = e.message
      redirect_to admin_themes_url      
    end
  end
  
  def destroy
    @skin = Skin.find(params[:id])
    if @skin.created_by == current_user || current_user.admin?
		  File.delete(@skin.archive.path) if File.exist?(@skin.archive.path)
		  File.delete(@skin.image.path) if File.exist?(@skin.image.path)
		  skin_dir = File::join(RAILS_ROOT, "public", "system", "images", @skin.id.to_s)
		  FileUtils.rm_r(skin_dir) if File.exist?(skin_dir)
		  @skin.destroy
      redirect_to admin_themes_url
    else
      flash[:error] = "Only the user who created this Skin may delete it."
      redirect_to :back
    end
    rescue ActiveRecord::RecordNotFound, Errno::ENOENT
      flash[:error] = 'This Skin could not be found or deleted'
      redirect_to '/admin/site_skins'
  end

	def activate
		@skin = Skin.find(params[:id])
    begin
		  @skin.activate_on(current_site, current_user) if current_user.admin? || current_user.site_admin?
    rescue Exception => e
      logger.info e.message
      logger.info e.backtrace
      flash[:error] = e.message
    ensure
		  redirect_to admin_themes_url
    end
	end

	def deactivate
		@skin = Skin.find(params[:id])
    begin
		  @skin.deactivate_on(current_site) if current_user.admin? || current_user.site_admin?
    rescue Exception => e
      logger.info e.message
      logger.info e.backtrace
      flash[:error] = e.message
    ensure		
      redirect_to admin_themes_url
    end
	end

  def search
    @skins = Skin.search(params[:skin][:query], params[:page])
    render :template => "admin/themes/index"
  end

end
