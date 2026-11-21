# A photo attachment that the browser has already cropped and shrunk
# (photo_upload_controller.js), so the server never processes images: it only
# checks that what arrived is a small raster image. No SVG: it can carry
# script.
#
#   small_photo :avatar
#
# gives `avatar` (has_one_attached), `avatar_saved?`, and a `remove_avatar`
# flag for the form's "Remove photo" box (a newly chosen photo wins over it).
module SmallPhoto
  extend ActiveSupport::Concern

  TYPES = %w[image/jpeg image/png image/webp].freeze
  MAX_BYTES = 2.megabytes

  class_methods do
    def small_photo(name)
      has_one_attached name

      attr_reader :"remove_#{name}"
      define_method(:"remove_#{name}=") do |value|
        instance_variable_set(:"@remove_#{name}", ActiveModel::Type::Boolean.new.cast(value))
      end

      # A stored photo, ignoring one that's attached but failed validation.
      define_method(:"#{name}_saved?") do
        attachment = public_send(name)
        attachment.attached? && attachment.blob.persisted?
      end

      before_validation do
        public_send(:"#{name}=", nil) if public_send(:"remove_#{name}") && !attachment_changes[name.to_s]
      end

      validate { small_photo_is_valid(name) }
    end
  end

  private

  def small_photo_is_valid(name)
    attachment = public_send(name)
    return unless attachment_changes[name.to_s] && attachment.attached?

    errors.add(name, "must be a JPEG, PNG or WebP image") unless TYPES.include?(attachment.blob.content_type)
    errors.add(name, "must be smaller than #{MAX_BYTES / 1.megabyte} MB") if attachment.blob.byte_size > MAX_BYTES
  end
end
