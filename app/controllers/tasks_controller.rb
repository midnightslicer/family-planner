class TasksController < ApplicationController
  RECENTLY_DONE_LIMIT = 20

  before_action :authenticate_user!
  before_action :require_household!
  before_action :set_task, only: [:show, :edit, :update, :destroy, :start, :pause, :complete, :cancel]
  before_action :require_author, only: [:edit, :update, :destroy]

  # GET /tasks: what's in progress, then what's to do, then the most recent
  # finished ones (those pile up, especially recurring ones, so they aren't
  # all listed).
  def index
    tasks = household_tasks.includes(:assigned_to)
    @active_tasks = tasks.where(status: [:in_progress, :planned])
                         .in_order_of(:status, %w[in_progress planned]).order(created_at: :desc)
    # Skipped one-offs first: they can still be restarted.
    @done_tasks = tasks.where(status: [:undone, :completed])
                       .in_order_of(:status, %w[undone completed]).order(updated_at: :desc)
                       .limit(RECENTLY_DONE_LIMIT)
  end

  # GET /tasks/new
  def new
    @task = household_tasks.new(assigned_to: current_user)
  end

  # POST /tasks — "I'm doing this now" (start_now) creates and starts it.
  def create
    @task = household_tasks.new(task_params.merge(created_by: current_user))
    if @task.save
      if params[:start_now]
        @task.start!
        respond_with_task "Started #{@task.title}."
      else
        respond_with_task "Added #{@task.title}."
      end
    else
      render :new, status: :unprocessable_content
    end
  end

  # GET /tasks/:id
  def show
  end

  # GET /tasks/:id/edit
  def edit
  end

  # PATCH/PUT /tasks/:id
  def update
    if @task.update(task_params)
      respond_with_task "Saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # POST /tasks/:id/start: planned (or a skipped one-off) -> in_progress
  def start
    transition(@task.start!, "Started #{@task.title}.")
  end

  # POST /tasks/:id/pause: in_progress -> planned (Start resumes it)
  def pause
    transition(@task.pause!, "Paused #{@task.title}.")
  end

  # POST /tasks/:id/complete: in_progress -> completed (+ recurrence)
  def complete
    transition(@task.complete!, "Done with #{@task.title}.")
  end

  # POST /tasks/:id/cancel: in_progress -> undone (+ recurrence)
  def cancel
    transition(@task.cancel!, "Skipped #{@task.title}.")
  end

  # DELETE /tasks/:id
  def destroy
    @task.destroy
    if turbo_stream_request?
      render turbo_stream: turbo_stream.remove(@task)
    else
      redirect_to tasks_path, notice: "Deleted.", status: :see_other
    end
  end

  private

  def household_tasks
    current_household.tasks
  end

  def set_task
    @task = household_tasks.find_by(id: params[:id])
    head :not_found unless @task
  end

  # Members may edit/delete their own tasks (admins any in the household);
  # anyone in the household can start/pause/complete/cancel.
  def require_author
    head :forbidden unless @task.created_by_id == current_user.id || current_user.admin?
  end

  # A button pressed on a stale page (the task already moved on) reloads the
  # card instead of claiming success.
  def transition(changed, notice)
    if changed
      respond_with_task notice
    else
      @task.reload
      respond_with_task "#{@task.title} is already marked #{helpers.task_status_label(@task)}.", kind: :alert
    end
  end

  # Regular form submissions redirect; same-page Turbo Stream requests get a
  # stream that replaces the task card and adds a flash message.
  def respond_with_task(message, kind: :notice)
    if turbo_stream_request?
      render turbo_stream: [
        turbo_stream.replace(@task, partial: "tasks/task_card", locals: { task: @task }),
        turbo_stream.prepend("flash", helpers.tag.p(message, class: "flash-#{kind}"))
      ]
    else
      redirect_to tasks_path, kind => message, status: :see_other
    end
  end

  def turbo_stream_request?
    request.format.turbo_stream?
  end

  def task_params
    permitted = params.require(:task).permit(:title, :description, :assigned_to_id, :starts_at, :ends_at, :recurrence_interval)
    permitted[:assigned_to_id] = nil if permitted[:assigned_to_id].blank?
    permitted
  end
end
