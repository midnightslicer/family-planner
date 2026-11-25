# Photos (faces, pets, the house) are for the family: Active Storage's own
# routes, which Rails leaves open to anyone holding a signed link, need a
# signed-in person too. Links are only ever rendered on signed-in pages.
# Photos arrive with the forms that own them, so the direct-upload endpoint,
# which would let anyone store files here, is closed.
Rails.application.config.to_prepare do
  ActiveStorage::BaseController.before_action :authenticate_user!
  ActiveStorage::DirectUploadsController.before_action { head :forbidden }
end
