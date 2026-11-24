class LocationReportsController < ApplicationController
  include HouseholdScoped

  # DELETE /location_reports/:id: take back a report made by mistake; the
  # one before it becomes current again.
  def destroy
    report = current_household.location_reports.find_by(id: params[:id]) or return not_found
    return head(:forbidden) unless report.reported_by_id == current_user.id || current_user.admin?

    report.destroy
    fallback = report.subject_type == "Pet" ? pet_path(report.subject_id) : tasks_path
    redirect_back_or_to fallback, notice: "Removed that report.", status: :see_other, allow_other_host: false
  end
end
