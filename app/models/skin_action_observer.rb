class SkinActionObserver < ActiveRecord::Observer
  observe Skin
  
  cattr_accessor :current_user
  
  def before_create(model)
    model.created_by = @@current_user
  end

  def before_update(model)
    model.updated_by = @@current_user
  end

end
