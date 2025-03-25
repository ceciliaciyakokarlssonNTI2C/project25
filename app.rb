require 'sinatra'
require 'slim'
require 'sqlite3'
require 'sinatra/reloader'
require 'bcrypt'
require 'sinatra/flash'


enable :sessions


before do
  if session[:user_id]
    db = SQLite3::Database.new('db/study_planner.db')
    db.results_as_hash = true
    @current_user = db.execute("SELECT * FROM users WHERE id = ?", [session[:user_id]]).first
  end
end

helpers do
  def admin?
    @current_user && @current_user["rank"] == "admin"
  end

  def protected!
    halt 403, "Not authorized\n" unless admin?
  end
end

get('/admin/users') do
  protected!
  db = SQLite3::Database.new('db/study_planner.db')
  db.results_as_hash = true
  users = db.execute("SELECT * FROM users")
  slim(:'admin/users', locals: { users: users })
end

get('/admin/user_projects') do
  protected!
  db = SQLite3::Database.new('db/study_planner.db')
  db.results_as_hash = true
  projects = db.execute("SELECT * FROM projects")
  slim(:'admin/user_projects', locals: { projects: projects })
end

get('/admin/users/:id/projects') do
  protected!
  user_id = params[:id].to_i
  db = SQLite3::Database.new('db/study_planner.db')
  db.results_as_hash = true
  projects = db.execute("SELECT * FROM projects WHERE user_id = ?", [user_id])
  slim(:'admin/user_projects', locals: { projects: projects, user_id: user_id })
end

post('/admin/users/:id/delete') do
  protected!
  user_id = params[:id].to_i
  db = SQLite3::Database.new('db/study_planner.db')
  db.results_as_hash = true
  db.execute("DELETE FROM users WHERE id = ?", [user_id])
  db.execute("DELETE FROM projects WHERE user_id = ?", [user_id])
  flash[:success] = "Användaren och deras projekt har tagits bort."
  redirect('/admin/users')
end

post('/admin/projects/:id/delete') do
  protected!
  project_id = params[:id].to_i
  db = SQLite3::Database.new('db/study_planner.db')
  db.results_as_hash = true
  db.execute("DELETE FROM projects WHERE id = ?", [project_id])
  flash[:success] = "Projektet har tagits bort."
  redirect request.referer || '/admin/users'
end

get('/admin/users/:id/edit') do
  protected!
  user_id = params[:id].to_i
  db = SQLite3::Database.new('db/study_planner.db')
  db.results_as_hash = true
  user = db.execute("SELECT * FROM users WHERE id = ?", [user_id]).first
  slim(:'admin/edit_user', locals: { user: user })
end

post('/admin/users/:id/update') do
  protected!
  user_id = params[:id].to_i
  username = params[:username]
  rank = params[:rank]
  p "rank is #{rank},username is #{username}, user_id is #{user_id}"
  db = SQLite3::Database.new('db/study_planner.db')
  db.results_as_hash = true
  db.execute("UPDATE users SET username = ?, rank = ? WHERE id = ?", [username, rank, user_id])
  flash[:success] = "Användaren har uppdaterats."
  redirect('/admin/users')
end


# Start (förstasida)
get('/') do
  slim(:start)
end

# Registreringssida
get('/register') do
  slim(:register)
end

# Hantera registrering
post('/register') do
  username = params[:username]
  password = params[:password]
  password_digest = BCrypt::Password.create(password) # Hash the password
  db = SQLite3::Database.new('db/study_planner.db')
  db.results_as_hash = true
  db.execute("INSERT INTO users (username, password) VALUES (?, ?)", [username, password_digest])
  redirect('/login')
end


# Logga in-sida
get('/login') do
  slim(:login)
end

# Hantera inloggning
post('/login') do
    username = params[:username]
    password = params[:password]
  
    db = SQLite3::Database.new('db/study_planner.db')
    db.results_as_hash = true
  
    # Fetch user by username
    result = db.execute("SELECT * FROM users WHERE username = ?", [username]).first
  
    if result.nil?
      @error = "Användarnamn hittades inte"
      return slim(:login) # Render the login form again with an error message
    end
  
    pwdigest = result["password"]
    id = result["id"]
  
    # Check the password
    if BCrypt::Password.new(pwdigest) == password
      session[:user_id] = id
      redirect('/projects')
    else
      @error = "FEL LÖSENORD"
      return slim(:login) # Render the login form again with an error message
    end
  end

# Visa alla projekt för en användare
get('/projects') do
  redirect('/login') unless session[:user_id]
  db = SQLite3::Database.new('db/study_planner.db')
  db.results_as_hash = true
  projects = db.execute("SELECT * FROM projects WHERE user_id = ?", [session[:user_id]])
  slim(:"projects/index", locals: { projects: projects })
end

get('/admin') do
  protected!
  slim(:"admin/admin")
end

# Nytt projekt
get('/projects/new') do
  redirect('/login') unless session[:user_id]
  slim(:"projects/new")
end

# Skapa projekt
post('/projects/new') do
  name = params[:name]
  db = SQLite3::Database.new('db/study_planner.db')
  db.results_as_hash = true
  db.execute("INSERT INTO projects (name, user_id) VALUES (?, ?)", [name, session[:user_id]])
  redirect('/projects')
end

# Visa uppgifter för ett projekt
get('/projects/:id/tasks') do
  project_id = params[:id].to_i
  db = SQLite3::Database.new('db/study_planner.db')
  db.results_as_hash = true
  tasks = db.execute("SELECT * FROM tasks WHERE project_id = ?", [project_id])
  slim(:"tasks/index", locals: { tasks: tasks, project_id: project_id })
end

# Ny uppgift
get('/projects/:id/tasks/new') do
  project_id = params[:id].to_i
  slim(:"tasks/new", locals: { project_id: project_id })
end

post('/tasks/:id/update') do
  db = SQLite3::Database.new('db/study_planner.db')
  db.results_as_hash = true
  task_id = params[:id].to_i
  title = params[:title]
  deadline = params[:deadline]
  project_id = params[:project_id] || db.execute("SELECT project_id FROM tasks WHERE id = ?", [task_id]).first['project_id']

  db.execute("UPDATE tasks SET title = ?, deadline = ? WHERE id = ?", [title, deadline, task_id])

  redirect("/projects/#{project_id}/tasks")
end


get('/deadlines') do
  db = SQLite3::Database.new('db/study_planner.db')
  db.results_as_hash = true
  user_id = session[:user_id]

  @tasks = db.execute("SELECT tasks.* FROM tasks JOIN projects ON tasks.project_id = projects.id WHERE projects.user_id = ?", [user_id])
  @tasks = @tasks.sort_by { |task| task['deadline'] ? Date.parse(task['deadline']) : Date.new(9999, 12, 31) }

  slim(:"deadlines")
end


# Skapa uppgift
post('/projects/:id/tasks/new') do
  title = params[:title]
  deadline = params[:deadline]
  project_id = params[:id].to_i
  days_left = (Date.parse(deadline) - Date.today).to_i

  if days_left <= 3
    status = 3
  elsif days_left < 5
    status = 2
  else
    status = 1
  end

  db = SQLite3::Database.new('db/study_planner.db')
  db.results_as_hash = true
  db.execute("INSERT INTO tasks (title, deadline, project_id, status) VALUES (?, ?, ?, ?)", [title, deadline, project_id, status])
  redirect("/projects/#{project_id}/tasks")
end

# Redigera uppgift
get('/tasks/:id/edit') do
  task_id = params[:id].to_i
  db = SQLite3::Database.new('db/study_planner.db')
  db.results_as_hash = true
  task = db.execute("SELECT * FROM tasks WHERE id = ?", [task_id]).first
  slim(:"tasks/edit", locals: { task: task })
end

# Uppdatera uppgift
post('/tasks/:id/update') do
  task_id = params[:id].to_i
  title = params[:title]
  deadline = params[:deadline]
  db = SQLite3::Database.new('db/study_planner.db')
  db.results_as_hash = true
  db.execute("UPDATE tasks SET title = ?, deadline = ? WHERE id = ?", [title, deadline, task_id])
  redirect("/projects/#{params[:project_id]}/tasks")
end

# Ta bort uppgift
post('/tasks/delete') do
  task_id = params[:id].to_i
  project_id = params[:project_id].to_i
  db = SQLite3::Database.new('db/study_planner.db')
  db.results_as_hash = true
  db.execute("DELETE FROM tasks WHERE id = ?", [task_id])
  redirect request.referer || '/default_redirect_path'

end




#Logga ut
post '/logout' do
  session.clear  
  redirect '/'   
end

post '/logout' do
  session.clear
  flash[:success] = "You have successfully logged out."
  redirect '/'
end
