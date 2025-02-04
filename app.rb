require 'sinatra'
require 'slim'
require 'sqlite3'
require 'sinatra/reloader'
require 'bcrypt'
require 'sinatra/flash'


enable :sessions

# Databasinställningar
configure do
  set :db, SQLite3::Database.new("db/study_planner.db")
  settings.db.results_as_hash = true

  # Skapa tabeller om de inte redan finns
  settings.db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY,
      username TEXT UNIQUE,
      password TEXT
    );
  SQL

  settings.db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS projects (
      id INTEGER PRIMARY KEY,
      name TEXT,
      user_id INTEGER,
      FOREIGN KEY(user_id) REFERENCES users(id)
    );
  SQL

  settings.db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS tasks (
      id INTEGER PRIMARY KEY,
      title TEXT,
      deadline DATE,
      project_id INTEGER,
      FOREIGN KEY(project_id) REFERENCES projects(id)
    );
  SQL
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
  db = settings.db
  projects = db.execute("SELECT * FROM projects WHERE user_id = ?", [session[:user_id]])
  slim(:"projects/index", locals: { projects: projects })
end

# Nytt projekt
get('/projects/new') do
  redirect('/login') unless session[:user_id]
  slim(:"projects/new")
end

# Skapa projekt
post('/projects/new') do
  name = params[:name]
  db = settings.db
  db.execute("INSERT INTO projects (name, user_id) VALUES (?, ?)", [name, session[:user_id]])
  redirect('/projects')
end

# Visa uppgifter för ett projekt
get('/projects/:id/tasks') do
  project_id = params[:id].to_i
  db = settings.db
  tasks = db.execute("SELECT * FROM tasks WHERE project_id = ?", [project_id])
  slim(:"tasks/index", locals: { tasks: tasks, project_id: project_id })
end

# Ny uppgift
get('/projects/:id/tasks/new') do
  project_id = params[:id].to_i
  slim(:"tasks/new", locals: { project_id: project_id })
end

# Skapa uppgift
post('/projects/:id/tasks/new') do
  title = params[:title]
  deadline = params[:deadline]
  project_id = params[:id].to_i
  db = settings.db
  db.execute("INSERT INTO tasks (title, deadline, project_id) VALUES (?, ?, ?)", [title, deadline, project_id])
  redirect("/projects/#{project_id}/tasks")
end

# Redigera uppgift
get('/tasks/:id/edit') do
  task_id = params[:id].to_i
  db = settings.db
  task = db.execute("SELECT * FROM tasks WHERE id = ?", [task_id]).first
  slim(:"tasks/edit", locals: { task: task })
end

# Uppdatera uppgift
post('/tasks/:id/update') do
  task_id = params[:id].to_i
  title = params[:title]
  deadline = params[:deadline]
  db = settings.db
  db.execute("UPDATE tasks SET title = ?, deadline = ? WHERE id = ?", [title, deadline, task_id])
  redirect("/projects/#{params[:project_id]}/tasks")
end

# Ta bort uppgift
post('/tasks/delete') do
  task_id = params[:id].to_i
  project_id = params[:project_id].to_i
  db = settings.db
  db.execute("DELETE FROM tasks WHERE id = ?", [task_id])
  redirect("/projects/#{project_id}/tasks")
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
