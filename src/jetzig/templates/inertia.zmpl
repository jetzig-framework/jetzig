<!DOCTYPE html>
<html>
  <head>
    @partial views:inertia/head
  </head>
  <body>
    <div
      id="app"
      data-page='{"component":"{{jetzig_view}}","props":{{zmpl.toJson()}},"url":"{{context.path()}}","version":"c32b8e4965f418ad16eaebba1d4e960f"}'
    >
    </div>
  </body>
</html>
