class TasksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_household
  before_action :set_task, only: [:show, :edit, :update, :destroy, :start, :complete, :cancel]
  before_action :require_author, only: [:edit, :update, :destroy]

  # GET /tasks
  def index
    @tasks = household_tasks.order(created_at: :desc)
  end

  # GET /tasks/new
  def new
    @task = household_tasks.new(assigned_to: current_user, starts_at: Time.current.change(sec: 0))
  end

  # POST /tasks
  def create
    @task = household_tasks.new(task_params.merge(created_by: current_user))
    if @task.save
      respond_with_task :created, "Task created."
    else
      render :new, status: :unprocessable_entity
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
      respond_with_task :updated, "Task updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # POST /tasks/:id/start — planned → in_progress
  def start
    @task.start!
    respond_with_task :started, "Started #{@task.title}."
  end

  # POST /tasks/:id/complete — in_progress → completed (+ recurrence)
  def complete
    @task.complete!
    respond_with_task :completed, "Completed #{@task.title}."
  end

  # DELETE /tasks/:id
  def destroy
    task_id = @task.id
    @task.destroy
    if turbo_stream_request?
      render turbo_stream: turbo_stream.remove(Task.new(id: task_id))
    else
      redirect_to tasks_path, notice: "Task deleted.", status: :see_other
    end
  end

  # POST /tasks/:id/cancel — in_progress → undone (+ recurrence)
  def cancel
    @task.cancel!
    respond_with_task :cancelled, "Cancelled #{@task.title}."
  end

  private

  def set_household
    head :not_found unless current_household
  end

  def household_tasks
    current_household.tasks
  end

  def set_task
    @task = household_tasks.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # Members may edit/delete only their own tasks; anyone in the household
  # can start/complete/cancel.
  def require_author
    head :forbidden unless @task.created_by_id == current_user.id
  end

  # Regular form submissions redirect; same-page Turbo Stream requests get a
  # stream that replaces the task card and refreshes the list page.
  def respond_with_task(kind, notice)
    if turbo_stream_request?
      render turbo_stream: [
        turbo_stream.replace(@task, partial: "tasks/task_card", locals: { task: @task }),
        turbo_stream.prepend("flash", "<p class=\"flash-notice\">#{notice}</p>".html_safe)
      ]
    else
      redirect_to tasks_path, notice: notice, status: :see_other
    end
  end

  def turbo_stream_request?
    request.headers["Accept"].to_s.include?("text/vnd.turbo-stream.html")
  end

  def task_params
    permitted = params.require(:task).permit(:title, :description, :assigned_to_id, :starts_at, :ends_at, :recurrence_interval)
    permitted[:assigned_to_id] = nil if permitted[:assigned_to_id].blank?
    permitted
  end
end