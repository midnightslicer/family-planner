# The Schedule: everyone's to-dos and events. One person's at a time
# (`?person=<id>`, yourself by default) or the whole family's day
# (`?person=family`). Every action redirects back to the page it came from,
# which morphs in place (turbo_refreshes_with), so lists stay in order.
class TasksController < ApplicationController
  include HouseholdScoped

  before_action :set_task, only: [:show, :edit, :update, :destroy, :start, :pause, :complete, :cancel]
  before_action :require_editor, only: [:edit, :update, :destroy]

  # GET /tasks
  def index
    current_household.roll_recurring_events!
    @members = current_household.members_by_name.with_attached_avatar.to_a
    if params[:person] == "family"
      @family = @members.index_with { |member| PersonSchedule.new(current_household, member) }
      @statuses = current_household.member_statuses
      @anyone = current_household.tasks.open.where(assigned_to_id: nil).order(:created_at)
    else
      @person = @members.find { |member| member.id.to_s == params[:person].to_s } || current_user
      @schedule = PersonSchedule.new(current_household, @person)
      @task = current_household.tasks.new(assigned_to: @person)
      @where = LocationReport.latest_for(current_household, "User", [@person.id])[@person.id]
      @locations = current_household.locations.in_display_order.with_attached_photo if @person == current_user
    end
  end

  # GET /tasks/new: the full form (the schedule page's quick add is the
  # usual way in).
  def new
    @task = current_household.tasks.new(assigned_to: current_user, on_date: params[:on])
  end

  # POST /tasks: "start_now" adds it and starts it.
  def create
    @task = current_household.tasks.new(task_params.merge(created_by: current_user, schedule_fields: true))
    if @task.save
      @task.start! if params[:start_now]
      redirect_to schedule_path_for(@task), notice: "Added #{@task.title}.", status: :see_other
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
  end

  def edit
    @task.on_date = (@task.starts_at&.to_date || @task.due_on)&.iso8601
    @task.from_time = @task.starts_at&.strftime("%H:%M")
    @task.until_time = @task.ends_at&.strftime("%H:%M")
  end

  def update
    @task.assign_attributes(task_params.merge(schedule_fields: true))
    if @task.save
      redirect_to schedule_path_for(@task), notice: "Saved.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  # POST /tasks/:id/start: "I'm doing this now"
  def start
    transition(@task.start!, "Started #{@task.title}.")
  end

  # POST /tasks/:id/pause: back on the list
  def pause
    transition(@task.pause!, "Paused #{@task.title}.")
  end

  # POST /tasks/:id/complete: ticked off (+ next repeat)
  def complete
    transition(@task.complete!, "Done: #{@task.title}.")
  end

  # POST /tasks/:id/cancel: skipped (+ next repeat)
  def cancel
    transition(@task.cancel!, "Skipped #{@task.title}.")
  end

  def destroy
    @task.destroy
    redirect_back_or_to schedule_path_for(@task), notice: "Deleted #{@task.title}.", status: :see_other, allow_other_host: false
  end

  private

  def set_task
    @task = current_household.tasks.find_by(id: params[:id]) or head :not_found
  end

  # Whoever added it, whoever it's for, or an admin. Anyone in the household
  # can still start, finish or skip it.
  def require_editor
    allowed = [@task.created_by_id, @task.assigned_to_id].include?(current_user.id) || current_user.admin?
    head :forbidden unless allowed
  end

  # A button pressed on a stale page (it already moved on) says so instead
  # of claiming success.
  def transition(changed, notice)
    message = changed ? { notice: notice } : { alert: "#{@task.reload.title} is already #{helpers.task_status_label(@task).downcase}." }
    redirect_back_or_to schedule_path_for(@task), **message, status: :see_other, allow_other_host: false
  end

  def schedule_path_for(task)
    tasks_path(person: (task.assigned_to_id unless task.assigned_to_id == current_user.id))
  end

  def task_params
    permitted = params.require(:task).permit(:title, :description, :assigned_to_id, :on_date, :from_time, :until_time,
                                             :place, :availability, :recurrence_interval)
    permitted[:assigned_to_id] = nil if permitted[:assigned_to_id].blank?
    permitted
  end
end
