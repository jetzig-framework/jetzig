# fish-completions
# Fish-shell Completions for `jetzig` (https://www.jetzig.dev/)

complete -x -c jetzig -s h -l help -d "Print help and exit | More information"
# ?
# complete -x -c jetzig -s e -l environment -d "Jetzig environment. (default: development)" -a "production testing development"

complete -x -c jetzig -n __fish_use_subcommand -a "
    init\t'Initialize a new project.'
    update\t'Update current project to latest version of Jetzig.'
    generate\t'Generate scaffolding.'
    server\t'Run a development server.'
    routes\t'List all routes in your app.'
    bundle\t'Create a deployment bundle.'
    database\t'Manage the application database.'
    auth\t'Utilities for Jetzig authentication.'
    test\t'Run app tests.'
    "


## init
# -p, --path   Set the output path relative to the current directory (default: current directory)
complete -r -c jetzig -n "__fish_seen_subcommand_from init" -s p -l path -d "Set the output path relative to the current directory (default: current directory)"

## update

## generate [job|view|layout|mailer|secret|partial|migration|middleware]
complete -x -c jetzig -n "__fish_seen_subcommand_from generate; and __fish_is_nth_token 2" -a "
    job\t'Generate a new Job. Jobs can be scheduled to run in the background.'
    view\t'Generate a view. Pass optional action names. Optionally suffix actions with `:static` to use static routing.'
    layout\t'Generate a layout. Layouts encapsulate common boilerplate mark-up.'
    mailer\t'Generate a new Mailer. Mailers provide an interface for sending emails from a Jetzig application.'
    secret\t'Generate a secure random secret suitable for use as the `JETZIG_SECRET` environment variable.'
    partial\t'Generate a partial template. Expects a view name followed by a partial name.'
    migration\t'Generate a new Migration. Migrations modify the applications database schema.'
    middleware\t'Generate a middleware module. Module name must be in CamelCase.'
    "
### view SLIGHT BUG
complete -x -c jetzig -n "__fish_seen_subcommand_from generate; and __fish_prev_arg_in view index get post put patch delete" -a "index get post put patch delete"

## server
complete -x -c jetzig -n "__fish_seen_subcommand_from server" -l reload -d "Enable or disable automatic reload on update (default: true)" -a "true false"
complete -x -c jetzig -n "__fish_seen_subcommand_from server" -l debug -d "Enable or disable the development debug console (default: true)" -a "true false"

## routes
## bundle
complete -x -c jetzig -n "__fish_seen_subcommand_from bundle" -l optimize -d "Set optimization level, must be one of { Debug, ReleaseFast, ReleaseSmall } (default: ReleaseFast)" -a "Debug ReleaseFast ReleaseSmall"
complete -x -c jetzig -n "__fish_seen_subcommand_from bundle" -l arch -d "Set build target CPU architecture, must be one of { x86_64, aarch64 } (default: Current CPU arch)" -a "x86_64 aarch64"
complete -x -c jetzig -n "__fish_seen_subcommand_from bundle" -l os -d "Set build target operating system, must be one of { linux, macos, windows } (default: Current OS)" -a "linux macos windows"

## database [drop|setup|create|update|migrate|reflect|rollback]
complete -x -c jetzig -n "__fish_seen_subcommand_from database; and __fish_is_nth_token 2" -a "
    drop\t'Drop database.'
    setup\t'Set up a database: create a database, run migrations, reflect schema.'
    create\t'Create a database.'
    update\t'Update a database: run migrations and reflect schema.'
    migrate\t'Run database migrations.'
    reflect\t'Generate a JetQuery schema file and save to `src/app/database/Schema.zig`.'
    rollback\t'Roll back a database migration.'
    "

## auth [init|create]
complete -x -c jetzig -n "__fish_seen_subcommand_from auth; and __fish_is_nth_token 2" -a "
    init\t'Initialize auth(create_users table migration).'
    create\t'Create an account, given the email address'
    "

## test
