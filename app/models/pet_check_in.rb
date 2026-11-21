# The "pick some pets, then say what happened" form behind both batch flows:
#
#   kind "location": the chosen pets are now at a location ("Report where")
#   kind "feeding":  the chosen pets were just fed ("Feed")
#
# One form object instead of logic in two controllers, so both flows validate
# and save the same way. Pet ids from another household are ignored.
class PetCheckIn
  include ActiveModel::Model

  KINDS = %w[location feeding].freeze

  attr_accessor :household, :actor, :kind, :location_id, :new_location_name, :comment
  attr_reader :pet_ids

  validates :kind, inclusion: { in: KINDS }
  validates :comment, length: { maximum: LocationReport::COMMENT_MAX }
  validate :some_pets_chosen
  validate :location_chosen, if: :location?

  def pet_ids=(ids)
    @pet_ids = Array(ids).compact_blank.map(&:to_i).uniq
  end

  def pet_ids
    @pet_ids || []
  end

  def location?
    kind == "location"
  end

  def pets
    @pets ||= household.pets.where(id: pet_ids).by_name.to_a
  end

  def location
    return @location if defined?(@location)

    @location = Location.chosen(household, location_id, new_name: new_location_name, created_by: actor)
  end

  def save
    return false unless valid?

    ActiveRecord::Base.transaction do
      location.save! if location? && location.new_record?
      pets.each do |pet|
        if location?
          LocationReport.create!(household: household, subject: pet, location: location, reported_by: actor, comment: comment)
        else
          Feeding.create!(household: household, pet: pet, fed_by: actor, comment: comment)
        end
      end
    end
    notify_subscribers
    true
  end

  # "Rex and Bella are in the Yard." / "Fed Rex."
  def summary
    names = pets.map(&:name).to_sentence
    if location?
      "#{names} #{pets.one? ? 'is' : 'are'} at #{location.name}."
    else
      "Fed #{names}."
    end
  end

  private

  # One notification per follower per check-in ("Sam fed Rex and Bella"),
  # naming only the pets they follow, and none for whoever did it.
  def notify_subscribers
    PetSubscription.where(pet_id: pets.map(&:id)).where.not(user_id: actor&.id).includes(:user)
                   .group_by(&:user).each do |follower, subscriptions|
      followed = pets.select { |pet| subscriptions.any? { |s| s.pet_id == pet.id } }
      names = followed.map(&:name).to_sentence
      body =
        if location?
          "#{actor&.display_name || 'Someone'}: #{names} #{followed.one? ? 'is' : 'are'} at #{location.name}"
        else
          "#{actor&.display_name || 'Someone'} fed #{names}"
        end
      body += " (#{comment})" if comment.present?
      Turbo::StreamsChannel.broadcast_append_to(
        follower, :notifications,
        target: "notifications", partial: "shared/notification",
        locals: { title: household.name, body: body, tag: "pets-#{kind}-#{followed.map(&:id).join('-')}" }
      )
    end
  rescue StandardError => error
    Rails.logger.warn("Pet notifications failed: #{error.class}: #{error.message}")
  end

  def some_pets_chosen
    errors.add(:base, "Pick at least one pet.") if pets.empty?
  end

  def location_chosen
    return errors.add(:base, "Pick where they are.") unless location

    Location.new_location_errors(location).each { |message| errors.add(:base, message) }
  end
end
