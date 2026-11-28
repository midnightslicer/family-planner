# The Schedule: everyone's to-dos and events. One person's at a time
# (`?person=<id>`, yourself by default) or the whole family's day
# (`?person=family`). Every action redirects back to the page it came from,
# which morphs in place (turbo_refreshes_with), so lists stay in order.
class TasksController < ApplicationController
  include HouseholdScoped

  before_action :set_task, only: [ :show, :edit, :update, :destroy, :start, :pause, :complete, :cancel, :reopen, :accept, :decline ]
  before_action :require_editor, only: [ :edit, :update, :destroy ]
  before_action :require_doer, only: [ :start, :pause, :complete, :cancel, :reopen ]

  # GET /tasks
  def index
    current_household.roll_recurring_events!
    @members = current_household.board_members
    places = current_household.places
    if params[:person] == "family"
      @family = PersonSchedule.for_family(current_household, @members, viewer: current_user, places: places)
      @statuses = current_household.member_statuses(members: @members, places: places)
      @groups = current_household.by_house(@members, [], places)
      @anyone = current_household.tasks.open.for_anyone.order(:created_at)
                                 .includes(:created_by, :location, :assignments).select { |task| task.visible_to?(current_user) }
    else
      @person = @members.find { |member| member.id.to_s == params[:person].to_s } ||
                @members.find { |member| member == current_user } || current_user
      @schedule = PersonSchedule.new(current_household, @person, viewer: current_user, places: places)
      @task = current_household.tasks.new
      @assignee_ids = [ @person.id ]
      @where = LocationReport.latest_for(current_household, "User", [ @person.id ])[@person.id]
      # Their event's place, unless they've said where they are since it started.
      @at = @schedule.at unless @where&.newer_than?(@schedule.now)
      if @person == current_user
        @locations = places
        @status_set = StatusUpdate.active_for_user(current_user)
      end
    end
  end

  # GET /tasks/new: the full form (the schedule page's quick add is the
  # usual way in).
  def new
    @task = current_household.tasks.new(on_date: params[:on])
    @assignee_ids = [ current_user.id ]
  end

  # POST /tasks: "start_now" adds it and starts it. It goes on the chosen
  # people's schedules (TaskAssigner), and the flash says how that went.
  def create
    @task = current_household.tasks.new(task_params.merge(created_by: current_user, schedule_fields: true))
    @assignee_ids = assignee_ids
    saved = Task.transaction do
      @task.save && (@assigner = TaskAssigner.new(@task, actor: current_user).assign(@assignee_ids))
    end
    if saved
      @task.start! if params[:start_now]
      # The quick add stays on the page it's on, updating its lists in place
      # (a stream, so the box keeps focus and the keyboard stays up); the
      # full form goes to the schedule.
      if params[:stay] && request.format.turbo_stream? && (person = quick_add_person)
        render_quick_add(person)
      elsif params[:stay]
        redirect_back_or_to schedule_path_for(@task), notice: @assigner.summary, status: :see_other, allow_other_host: false
      else
        redirect_to schedule_path_for(@task), notice: @assigner.summary, status: :see_other
      end
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
    @task.place = @task.place_name
    @assignee_ids = @task.active_assignments.map(&:user_id)
  end

  def update
    @task.assign_attributes(task_params.merge(schedule_fields: true))
    @assignee_ids = assignee_ids
    saved = Task.transaction do
      @task.save &&
        (@assigner = TaskAssigner.new(@task, actor: current_user)
                                 .assign(@assignee_ids, retimed: @task.saved_change_to_starts_at? || @task.saved_change_to_ends_at?))
    end
    if saved
      redirect_to schedule_path_for(@task), notice: @assigner.summary, status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  # POST /tasks/:id/accept: yes to something that clashed with your day.
  def accept
    respond_to_invite("accepted", "You're on #{@task.title}.", "accepted")
  end

  # POST /tasks/:id/decline: not for me. Takes it off your schedule; whoever
  # added it hears about it.
  def decline
    respond_to_invite("declined", "Declined #{@task.title}.", "can't make")
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

  # POST /tasks/:id/reopen: ticked off (or skipped) by mistake: back on the list.
  def reopen
    transition(@task.reopen!, "#{@task.title} is back on the list.")
  end

  def destroy
    @task.destroy
    redirect_back_or_to schedule_path_for(@task), notice: "Deleted #{@task.title}.", status: :see_other, allow_other_host: false
  end

  private

  # Whose day the quick add was on (`person`, a member of this household).
  def quick_add_person
    current_household.users.find_by(id: params[:person])
  end

  # The quick add's answer: that day's lists, re-rendered, and the flash.
  def render_quick_add(person)
    places = current_household.places
    schedule = PersonSchedule.new(current_household, person, viewer: current_user, places: places)
    where = LocationReport.latest_for(current_household, "User", [ person.id ])[person.id]
    locals = { s: schedule, person: person, where: where }
    render turbo_stream: [
      turbo_stream.replace("schedule-top", partial: "tasks/schedule_top", locals: locals),
      turbo_stream.replace("schedule-lists", partial: "tasks/schedule_lists", locals: locals),
      turbo_stream.update("flash", helpers.flash_message(@assigner.summary, :notice))
    ]
  end

  def set_task
    @task = current_household.tasks.find_by(id: params[:id])
    not_found unless @task&.visible_to?(current_user)
  end

  # Whoever added it, whoever it's for, or an admin.
  def require_editor
    head :forbidden unless @task.editable_by?(current_user)
  end

  # Only whoever it's for starts, finishes, skips or brings it back
  # (anyone, if it's for anyone): adding it for someone doesn't let you
  # tick it off for them.
  def require_doer
    return if @task.doable_by?(current_user)

    redirect_back_or_to schedule_path_for(@task), alert: "Only the person it's for can do that.", status: :see_other, allow_other_host: false
  end

  def respond_to_invite(status, notice, verb)
    assignment = @task.assignment_for(current_user) or return not_found
    assignment.update!(status: status, responded_at: Time.current, conflict_note: (assignment.conflict_note if status == "pending"))
    creator = @task.created_by
    if creator && creator != current_user
      Notifier.notify(creator, category: "replies", title: "#{current_user.display_name} #{verb} #{@task.title_for(creator)}",
                               path: task_path(@task), household: current_household, tag: "task-#{@task.id}-reply")
    end
    redirect_back_or_to tasks_path, notice: notice, status: :see_other, allow_other_host: false
  end

  # Who it's for, from the "Who" chips (a blank entry marks the field as
  # sent, so ticking nobody means "anyone"). Missing entirely: yourself.
  def assignee_ids
    ids = params.dig(:task, :assignee_ids)
    ids.nil? ? [ current_user.id ] : Array(ids).compact_blank.map(&:to_i)
  end

  # A button pressed on a stale page (it already moved on) says so instead
  # of claiming success.
  def transition(changed, notice)
    message = changed ? { notice: notice } : { alert: "#{@task.reload.title} is already #{helpers.task_status_label(@task).downcase}." }
    redirect_back_or_to schedule_path_for(@task), **message, status: :see_other, allow_other_host: false
  end

  # Back to your own day if it's on it (or it's for anyone), else to the
  # first person's it's for.
  def schedule_path_for(task)
    people = task.assignments.reload.reject(&:declined?).map(&:user_id)
    tasks_path(person: (people.first unless people.empty? || people.include?(current_user.id)))
  end

  def task_params
    params.require(:task).permit(:title, :description, :on_date, :from_time, :until_time,
                                 :place, :place_choice, :place_other, :availability, :recurrence_interval, :private, :follow_up)
  end
end
